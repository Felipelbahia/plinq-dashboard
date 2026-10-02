-- L2 (2026-10-02) patch: suporteapp_sync_conversation_state passa a (a) INSERIR a conversa que o tempo real nunca
-- registrou (webhook 84 não assina conversation_created) e (b) comparar/sincronizar etiquetas (retrato completo).
-- Mesma assinatura; CREATE OR REPLACE. ACL preservada (CREATE OR REPLACE mantém privilégios).

CREATE OR REPLACE FUNCTION public.suporteapp_sync_conversation_state(
  p_items jsonb, p_n8n_workflow text, p_n8n_execution text, p_modo text DEFAULT 'reconciliacao')
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  r record;
  s public.suporteapp_conversation_snapshot%ROWTYPE;
  v_checked int := 0; v_updated int := 0; v_drift int := 0; v_sem int := 0; v_inseridas int := 0;
  v_campos text[]; v_por_campo jsonb := '{}'::jsonb; v_drift_convs jsonb := '[]'::jsonb;
  v_status_trans_reopen boolean; v_new_reopen int; v_new_resolved timestamptz; v_new_last_reopen timestamptz;
  c text;
BEGIN
  IF p_modo NOT IN ('reconciliacao', 'backfill') THEN
    RAISE EXCEPTION 'p_modo invalido: % (use reconciliacao ou backfill)', p_modo;
  END IF;

  FOR r IN
    SELECT * FROM jsonb_to_recordset(COALESCE(p_items, '[]'::jsonb)) AS x(
      conv bigint, inbox integer, labels text[], status text, priority text, agent_id integer, agent_name text, team_id integer, team_name text,
      created_at timestamptz, first_reply_at timestamptz, waiting_since timestamptz, snoozed_until timestamptz,
      sla_policy_id integer, last_activity_at timestamptz, muted boolean,
      resolved_at timestamptz, reopened_count integer, last_reopened_at timestamptz)
  LOOP
    v_checked := v_checked + 1;
    IF r.conv IS NULL THEN CONTINUE; END IF;

    SELECT * INTO s FROM public.suporteapp_conversation_snapshot WHERE chatwoot_conversation_id = r.conv FOR UPDATE;
    IF NOT FOUND THEN
      -- conversa que o tempo real nunca registrou (o webhook não assina conversation_created): cria a linha
      -- a partir do retrato da API; em reconciliação isso é deriva (o tempo real falhou), no backfill é carga.
      IF r.inbox IS NULL THEN v_sem := v_sem + 1; CONTINUE; END IF;
      INSERT INTO public.suporteapp_conversation_snapshot (
        chatwoot_conversation_id, chatwoot_inbox_id, native_status, current_agent_id, current_agent_name,
        current_team_id, current_team_name, current_labels, last_event_at, aplicacao, n8n_workflow, n8n_execution,
        chatwoot_native_priority, chatwoot_created_at, first_reply_at, waiting_since, snoozed_until, sla_policy_id,
        last_activity_at, muted, resolved_at, reopened_count, last_reopened_at)
      VALUES (r.conv, r.inbox, r.status, r.agent_id, CASE WHEN r.agent_id IS NULL THEN NULL ELSE r.agent_name END,
        r.team_id, CASE WHEN r.team_id IS NULL THEN NULL ELSE r.team_name END, COALESCE(r.labels, ARRAY[]::text[]),
        COALESCE(r.last_activity_at, now()), 'n8n', p_n8n_workflow, p_n8n_execution,
        r.priority, r.created_at, r.first_reply_at, r.waiting_since, r.snoozed_until, r.sla_policy_id,
        r.last_activity_at, r.muted, r.resolved_at, COALESCE(r.reopened_count, 0), r.last_reopened_at)
      ON CONFLICT (chatwoot_conversation_id) DO NOTHING;
      v_inseridas := v_inseridas + 1;
      IF p_modo = 'reconciliacao' THEN
        v_drift := v_drift + 1;
        v_por_campo := jsonb_set(v_por_campo, ARRAY['sem_snapshot'], to_jsonb(COALESCE((v_por_campo ->> 'sem_snapshot')::int, 0) + 1));
        IF jsonb_array_length(v_drift_convs) < 50 THEN
          v_drift_convs := v_drift_convs || jsonb_build_object('conv', r.conv, 'campos', jsonb_build_array('sem_snapshot'));
        END IF;
      END IF;
      CONTINUE;
    END IF;

    v_campos := ARRAY[]::text[];
    IF r.status IS NOT NULL AND r.status IS DISTINCT FROM s.native_status THEN v_campos := array_append(v_campos, 'status'); END IF;
    IF r.priority IS NOT NULL AND r.priority IS DISTINCT FROM s.chatwoot_native_priority THEN v_campos := array_append(v_campos, 'prioridade'); END IF;
    IF r.agent_id IS DISTINCT FROM s.current_agent_id THEN v_campos := array_append(v_campos, 'agente'); END IF;
    IF r.team_id IS DISTINCT FROM s.current_team_id THEN v_campos := array_append(v_campos, 'time'); END IF;
    IF r.created_at IS NOT NULL AND (s.chatwoot_created_at IS NULL OR abs(extract(epoch FROM (r.created_at - s.chatwoot_created_at))) > 1)
       THEN v_campos := array_append(v_campos, 'criacao'); END IF;
    IF r.snoozed_until IS DISTINCT FROM s.snoozed_until THEN v_campos := array_append(v_campos, 'soneca'); END IF;
    IF r.sla_policy_id IS DISTINCT FROM s.sla_policy_id THEN v_campos := array_append(v_campos, 'sla'); END IF;
    IF r.labels IS NOT NULL AND
       (SELECT array_agg(x ORDER BY x) FROM unnest(r.labels) x)
         IS DISTINCT FROM (SELECT array_agg(x ORDER BY x) FROM unnest(COALESCE(s.current_labels, ARRAY[]::text[])) x)
       THEN v_campos := array_append(v_campos, 'etiquetas'); END IF;

    -- resolução / reabertura (silencioso)
    v_new_resolved := s.resolved_at;
    IF r.resolved_at IS NOT NULL AND (s.resolved_at IS NULL OR abs(extract(epoch FROM (r.resolved_at - s.resolved_at))) > 300) THEN
      v_new_resolved := r.resolved_at;
    END IF;
    v_status_trans_reopen := (s.native_status = 'resolved' AND r.status IN ('open', 'pending'));
    v_new_reopen := GREATEST(s.reopened_count,
                             COALESCE(r.reopened_count, CASE WHEN v_status_trans_reopen THEN s.reopened_count + 1 ELSE s.reopened_count END));
    v_new_last_reopen := GREATEST(s.last_reopened_at, r.last_reopened_at);
    IF v_status_trans_reopen AND v_new_last_reopen IS NULL THEN v_new_last_reopen := now(); END IF;
    IF r.status = 'resolved' AND s.native_status IS DISTINCT FROM 'resolved' AND v_new_resolved IS NOT DISTINCT FROM s.resolved_at THEN
      v_new_resolved := COALESCE(r.resolved_at, now());
    END IF;

    IF cardinality(v_campos) > 0
       OR r.first_reply_at IS DISTINCT FROM s.first_reply_at AND r.first_reply_at IS NOT NULL
       OR r.waiting_since IS DISTINCT FROM s.waiting_since
       OR r.last_activity_at IS NOT NULL AND r.last_activity_at IS DISTINCT FROM s.last_activity_at
       OR r.muted IS NOT NULL AND r.muted IS DISTINCT FROM s.muted
       OR v_new_resolved IS DISTINCT FROM s.resolved_at
       OR v_new_reopen <> s.reopened_count
       OR v_new_last_reopen IS DISTINCT FROM s.last_reopened_at
    THEN
      UPDATE public.suporteapp_conversation_snapshot SET
        native_status = COALESCE(r.status, native_status),
        chatwoot_native_priority = COALESCE(r.priority, chatwoot_native_priority),
        current_agent_id = r.agent_id,
        current_agent_name = CASE WHEN r.agent_id IS NULL THEN NULL ELSE COALESCE(r.agent_name, current_agent_name) END,
        current_team_id = r.team_id,
        current_team_name = CASE WHEN r.team_id IS NULL THEN NULL ELSE COALESCE(r.team_name, current_team_name) END,
        current_labels = COALESCE(r.labels, current_labels),
        chatwoot_created_at = COALESCE(r.created_at, chatwoot_created_at),
        first_reply_at = COALESCE(r.first_reply_at, first_reply_at),
        waiting_since = r.waiting_since,
        snoozed_until = r.snoozed_until,
        sla_policy_id = r.sla_policy_id,
        last_activity_at = COALESCE(r.last_activity_at, last_activity_at),
        muted = COALESCE(r.muted, muted),
        resolved_at = v_new_resolved,
        reopened_count = v_new_reopen,
        last_reopened_at = v_new_last_reopen,
        updated_at = now(),
        aplicacao = 'n8n', n8n_workflow = p_n8n_workflow, n8n_execution = p_n8n_execution
      WHERE chatwoot_conversation_id = r.conv;
      v_updated := v_updated + 1;
    END IF;

    IF p_modo = 'reconciliacao' AND cardinality(v_campos) > 0 THEN
      v_drift := v_drift + 1;
      IF jsonb_array_length(v_drift_convs) < 50 THEN
        v_drift_convs := v_drift_convs || jsonb_build_object('conv', r.conv, 'campos', to_jsonb(v_campos));
      END IF;
      FOREACH c IN ARRAY v_campos LOOP
        v_por_campo := jsonb_set(v_por_campo, ARRAY[c], to_jsonb(COALESCE((v_por_campo ->> c)::int, 0) + 1));
      END LOOP;
    END IF;
  END LOOP;

  INSERT INTO public.suporteapp_ingestion_audit
    (source, messages_checked, messages_recovered, detail, aplicacao, n8n_workflow, n8n_execution)
  VALUES (CASE p_modo WHEN 'backfill' THEN 'backfill_manual_estado' ELSE 'reconciliacao_estado' END,
          v_checked, v_drift,
          jsonb_build_object('modo', p_modo, 'atualizadas', v_updated, 'inseridas', v_inseridas, 'drift', v_drift, 'sem_snapshot', v_sem,
                             'por_campo', v_por_campo, 'conversas_com_drift', v_drift_convs),
          'n8n', p_n8n_workflow, p_n8n_execution);

  RETURN jsonb_build_object('checked', v_checked, 'atualizadas', v_updated, 'inseridas', v_inseridas, 'drift', v_drift, 'sem_snapshot', v_sem,
                            'por_campo', v_por_campo, 'conversas_com_drift', v_drift_convs);
END;
$function$;
