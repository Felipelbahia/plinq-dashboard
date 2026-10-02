-- L2 Estado Nativo da Conversa (2026-10-02)
-- Guarda no snapshot os campos nativos do Chatwoot que faltavam: prioridade, criação, resolução/reabertura,
-- primeira resposta nativa, espera, soneca, SLA, última atividade e muted. Base do dashboard por conversa (L5).
--
-- 1) 11 colunas em suporteapp_conversation_snapshot (nulas = ainda não sincronizado, nunca "zero inventado").
-- 2) suporteapp_upsert_conversation_snapshot v2 (25 parâmetros): troca a v1 (16) na MESMA transação para não
--    criar overload; a chamada antiga do N8N (16 parâmetros nomeados) continua resolvendo para a v2.
--    Mantém L1 (retrato completo limpa agente/time) e a proteção de evento fora de ordem.
-- 3) suporteapp_sync_conversation_state: RPC única da reconciliação horária e do backfill.

ALTER TABLE public.suporteapp_conversation_snapshot
  ADD COLUMN IF NOT EXISTS chatwoot_native_priority text,
  ADD COLUMN IF NOT EXISTS resolved_at              timestamptz,
  ADD COLUMN IF NOT EXISTS reopened_count           integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_reopened_at         timestamptz,
  ADD COLUMN IF NOT EXISTS chatwoot_created_at      timestamptz,
  ADD COLUMN IF NOT EXISTS first_reply_at           timestamptz,
  ADD COLUMN IF NOT EXISTS waiting_since            timestamptz,
  ADD COLUMN IF NOT EXISTS snoozed_until            timestamptz,
  ADD COLUMN IF NOT EXISTS sla_policy_id            integer,
  ADD COLUMN IF NOT EXISTS last_activity_at         timestamptz,
  ADD COLUMN IF NOT EXISTS muted                    boolean;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid = 'public.suporteapp_conversation_snapshot'::regclass
                    AND conname = 'suporteapp_conversation_snapshot_native_priority_chk') THEN
    ALTER TABLE public.suporteapp_conversation_snapshot
      ADD CONSTRAINT suporteapp_conversation_snapshot_native_priority_chk
      CHECK (chatwoot_native_priority IS NULL OR chatwoot_native_priority IN ('none','low','medium','high','urgent'));
  END IF;
END $$;

COMMENT ON COLUMN public.suporteapp_conversation_snapshot.chatwoot_native_priority IS
  'Prioridade NATIVA do Chatwoot (none/low/medium/high/urgent) — a "severidade" do dashboard. NULL = ainda não sincronizado. Não confundir com custom_attributes.prioridade_suporte (P0-P3 da triagem).';
COMMENT ON COLUMN public.suporteapp_conversation_snapshot.resolved_at IS
  'Última vez que a conversa passou para resolved. Tempo real: transição de native_status; histórico: atividades conversation_status_changed do Chatwoot.';
COMMENT ON COLUMN public.suporteapp_conversation_snapshot.reopened_count IS
  'Nº de transições resolved -> open/pending. Nunca diminui (GREATEST na sincronização).';
COMMENT ON COLUMN public.suporteapp_conversation_snapshot.chatwoot_created_at IS 'created_at exato da conversa no Chatwoot.';
COMMENT ON COLUMN public.suporteapp_conversation_snapshot.first_reply_at IS
  'first_reply_created_at NATIVO do Chatwoot (conferência cruzada; o dashboard usa a 1ª saída pública em suporteapp_messages).';
COMMENT ON COLUMN public.suporteapp_conversation_snapshot.waiting_since IS 'waiting_since nativo (NULL = ninguém aguardando). Volátil: atualizado em evento de conversa e na reconciliação.';
COMMENT ON COLUMN public.suporteapp_conversation_snapshot.last_activity_at IS 'last_activity_at nativo. Volátil: atualizado em evento de conversa e na reconciliação.';

-- ---------------------------------------------------------------------------------------------
-- 2) upsert v2
-- ---------------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.suporteapp_upsert_conversation_snapshot(
  bigint, timestamp with time zone, integer, uuid, text, integer, text, integer, text, text[],
  text, text, text, text, text, jsonb);

CREATE OR REPLACE FUNCTION public.suporteapp_upsert_conversation_snapshot(
  p_chatwoot_conversation_id bigint, p_event_at timestamp with time zone,
  p_chatwoot_inbox_id integer DEFAULT NULL::integer, p_ticket_id uuid DEFAULT NULL::uuid,
  p_native_status text DEFAULT NULL::text, p_agent_id integer DEFAULT NULL::integer,
  p_agent_name text DEFAULT NULL::text, p_team_id integer DEFAULT NULL::integer,
  p_team_name text DEFAULT NULL::text, p_labels text[] DEFAULT NULL::text[],
  p_n8n_workflow text DEFAULT NULL::text, p_n8n_execution text DEFAULT NULL::text,
  p_conversation_subject text DEFAULT NULL::text, p_contact_name text DEFAULT NULL::text,
  p_contact_email text DEFAULT NULL::text, p_custom_attributes jsonb DEFAULT NULL::jsonb,
  p_native_priority text DEFAULT NULL::text, p_chatwoot_created_at timestamp with time zone DEFAULT NULL::timestamp with time zone,
  p_first_reply_at timestamp with time zone DEFAULT NULL::timestamp with time zone,
  p_waiting_since timestamp with time zone DEFAULT NULL::timestamp with time zone,
  p_snoozed_until timestamp with time zone DEFAULT NULL::timestamp with time zone,
  p_sla_policy_id integer DEFAULT NULL::integer,
  p_last_activity_at timestamp with time zone DEFAULT NULL::timestamp with time zone,
  p_muted boolean DEFAULT NULL::boolean, p_state_complete boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_old   jsonb;
  v_last  timestamptz;
  v_apply boolean;
  v_prio  text := CASE WHEN lower(p_native_priority) IN ('none','low','medium','high','urgent')
                       THEN lower(p_native_priority) END;
BEGIN
  SELECT s.custom_attributes, s.last_event_at INTO v_old, v_last
    FROM public.suporteapp_conversation_snapshot s
   WHERE s.chatwoot_conversation_id = p_chatwoot_conversation_id
   FOR UPDATE;

  -- mesma proteção contra evento fora de ordem do restante do snapshot
  v_apply := p_custom_attributes IS NOT NULL AND (v_last IS NULL OR p_event_at >= v_last);

  IF v_apply THEN
    INSERT INTO public.suporteapp_conversation_attribute_events
      (chatwoot_conversation_id, attribute_key, old_value, new_value, changed_at, source,
       aplicacao, n8n_workflow, n8n_execution)
    SELECT p_chatwoot_conversation_id, k.key, COALESCE(v_old, '{}'::jsonb) -> k.key, p_custom_attributes -> k.key,
           p_event_at,
           CASE WHEN COALESCE(v_old, '{}'::jsonb) = '{}'::jsonb THEN 'baseline' ELSE 'webhook' END,
           'n8n', p_n8n_workflow, p_n8n_execution
      FROM (SELECT jsonb_object_keys(COALESCE(v_old, '{}'::jsonb)) AS key
            UNION
            SELECT jsonb_object_keys(p_custom_attributes)) k
     WHERE (COALESCE(v_old, '{}'::jsonb) -> k.key) IS DISTINCT FROM (p_custom_attributes -> k.key);
  END IF;

  INSERT INTO public.suporteapp_conversation_snapshot (
      chatwoot_conversation_id, chatwoot_inbox_id, ticket_id, native_status,
      current_agent_id, current_agent_name, current_team_id, current_team_name,
      current_labels, last_event_at, aplicacao, n8n_workflow, n8n_execution,
      conversation_subject, contact_name, contact_email, custom_attributes,
      chatwoot_native_priority, resolved_at, chatwoot_created_at, first_reply_at,
      waiting_since, snoozed_until, sla_policy_id, last_activity_at, muted
  ) VALUES (
      p_chatwoot_conversation_id, p_chatwoot_inbox_id, p_ticket_id, p_native_status,
      p_agent_id, p_agent_name, p_team_id, p_team_name,
      p_labels, p_event_at, 'n8n', p_n8n_workflow, p_n8n_execution,
      p_conversation_subject, p_contact_name, p_contact_email, COALESCE(p_custom_attributes, '{}'::jsonb),
      v_prio, CASE WHEN p_native_status = 'resolved' THEN p_event_at END, p_chatwoot_created_at, p_first_reply_at,
      p_waiting_since, p_snoozed_until, p_sla_policy_id, p_last_activity_at, p_muted
  )
  ON CONFLICT (chatwoot_conversation_id) DO UPDATE SET
      chatwoot_inbox_id = COALESCE(EXCLUDED.chatwoot_inbox_id, suporteapp_conversation_snapshot.chatwoot_inbox_id),
      ticket_id = COALESCE(EXCLUDED.ticket_id, suporteapp_conversation_snapshot.ticket_id),
      native_status = COALESCE(EXCLUDED.native_status, suporteapp_conversation_snapshot.native_status),
      -- L1 (2026-10-02): retrato completo de conversa (status informado) grava agente/time como vieram, inclusive NULL.
      current_agent_id = CASE WHEN EXCLUDED.native_status IS NOT NULL THEN EXCLUDED.current_agent_id
                              ELSE COALESCE(EXCLUDED.current_agent_id, suporteapp_conversation_snapshot.current_agent_id) END,
      current_agent_name = CASE WHEN EXCLUDED.native_status IS NOT NULL THEN EXCLUDED.current_agent_name
                                ELSE COALESCE(EXCLUDED.current_agent_name, suporteapp_conversation_snapshot.current_agent_name) END,
      current_team_id = CASE WHEN EXCLUDED.native_status IS NOT NULL THEN EXCLUDED.current_team_id
                             ELSE COALESCE(EXCLUDED.current_team_id, suporteapp_conversation_snapshot.current_team_id) END,
      current_team_name = CASE WHEN EXCLUDED.native_status IS NOT NULL THEN EXCLUDED.current_team_name
                               ELSE COALESCE(EXCLUDED.current_team_name, suporteapp_conversation_snapshot.current_team_name) END,
      current_labels = COALESCE(EXCLUDED.current_labels, suporteapp_conversation_snapshot.current_labels),
      conversation_subject = COALESCE(EXCLUDED.conversation_subject, suporteapp_conversation_snapshot.conversation_subject),
      contact_name = COALESCE(EXCLUDED.contact_name, suporteapp_conversation_snapshot.contact_name),
      contact_email = COALESCE(EXCLUDED.contact_email, suporteapp_conversation_snapshot.contact_email),
      custom_attributes = CASE WHEN p_custom_attributes IS NOT NULL THEN p_custom_attributes
                               ELSE suporteapp_conversation_snapshot.custom_attributes END,
      -- L2 (2026-10-02): estado nativo
      chatwoot_native_priority = COALESCE(EXCLUDED.chatwoot_native_priority, suporteapp_conversation_snapshot.chatwoot_native_priority),
      chatwoot_created_at = COALESCE(EXCLUDED.chatwoot_created_at, suporteapp_conversation_snapshot.chatwoot_created_at),
      first_reply_at = COALESCE(EXCLUDED.first_reply_at, suporteapp_conversation_snapshot.first_reply_at),
      last_activity_at = COALESCE(EXCLUDED.last_activity_at, suporteapp_conversation_snapshot.last_activity_at),
      muted = COALESCE(EXCLUDED.muted, suporteapp_conversation_snapshot.muted),
      -- waiting_since / snoozed_until / sla_policy_id: NULL é valor real; só limpa em retrato completo explícito
      waiting_since = CASE WHEN p_state_complete THEN EXCLUDED.waiting_since
                           ELSE COALESCE(EXCLUDED.waiting_since, suporteapp_conversation_snapshot.waiting_since) END,
      snoozed_until = CASE WHEN p_state_complete THEN EXCLUDED.snoozed_until
                           ELSE COALESCE(EXCLUDED.snoozed_until, suporteapp_conversation_snapshot.snoozed_until) END,
      sla_policy_id = CASE WHEN p_state_complete THEN EXCLUDED.sla_policy_id
                           ELSE COALESCE(EXCLUDED.sla_policy_id, suporteapp_conversation_snapshot.sla_policy_id) END,
      -- transições de status avaliadas contra o status ANTERIOR da linha (status_changed + updated não contam 2x)
      resolved_at = CASE
          WHEN EXCLUDED.native_status = 'resolved'
               AND suporteapp_conversation_snapshot.native_status IS DISTINCT FROM 'resolved'
          THEN EXCLUDED.last_event_at
          ELSE suporteapp_conversation_snapshot.resolved_at END,
      reopened_count = suporteapp_conversation_snapshot.reopened_count + CASE
          WHEN suporteapp_conversation_snapshot.native_status = 'resolved'
               AND EXCLUDED.native_status IN ('open', 'pending') THEN 1 ELSE 0 END,
      last_reopened_at = CASE
          WHEN suporteapp_conversation_snapshot.native_status = 'resolved'
               AND EXCLUDED.native_status IN ('open', 'pending')
          THEN EXCLUDED.last_event_at
          ELSE suporteapp_conversation_snapshot.last_reopened_at END,
      last_event_at = EXCLUDED.last_event_at,
      updated_at = now(),
      aplicacao = 'n8n',
      n8n_workflow = EXCLUDED.n8n_workflow,
      n8n_execution = EXCLUDED.n8n_execution
  WHERE suporteapp_conversation_snapshot.last_event_at IS NULL
     OR EXCLUDED.last_event_at >= suporteapp_conversation_snapshot.last_event_at;
END;
$function$;

-- ---------------------------------------------------------------------------------------------
-- 3) sincronização do estado nativo (reconciliação horária e backfill)
-- ---------------------------------------------------------------------------------------------
-- Cada item é o RETRATO COMPLETO da conversa vindo da API: agent_id/team_id nulos = sem agente/time.
-- Deriva (= falha do tempo real) conta só nos campos que o webhook sempre entrega: status, prioridade,
-- agente, time, criação, soneca e SLA. Campos voláteis/derivados (first_reply_at, waiting_since,
-- last_activity_at, muted, resolved_at, reaberturas) são atualizados em silêncio.
CREATE OR REPLACE FUNCTION public.suporteapp_sync_conversation_state(
  p_items jsonb, p_n8n_workflow text, p_n8n_execution text, p_modo text DEFAULT 'reconciliacao')
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  r record;
  s public.suporteapp_conversation_snapshot%ROWTYPE;
  v_checked int := 0; v_updated int := 0; v_drift int := 0; v_sem int := 0;
  v_campos text[]; v_por_campo jsonb := '{}'::jsonb; v_drift_convs jsonb := '[]'::jsonb;
  v_status_trans_reopen boolean; v_new_reopen int; v_new_resolved timestamptz; v_new_last_reopen timestamptz;
  c text;
BEGIN
  IF p_modo NOT IN ('reconciliacao', 'backfill') THEN
    RAISE EXCEPTION 'p_modo invalido: % (use reconciliacao ou backfill)', p_modo;
  END IF;

  FOR r IN
    SELECT * FROM jsonb_to_recordset(COALESCE(p_items, '[]'::jsonb)) AS x(
      conv bigint, status text, priority text, agent_id integer, agent_name text, team_id integer, team_name text,
      created_at timestamptz, first_reply_at timestamptz, waiting_since timestamptz, snoozed_until timestamptz,
      sla_policy_id integer, last_activity_at timestamptz, muted boolean,
      resolved_at timestamptz, reopened_count integer, last_reopened_at timestamptz)
  LOOP
    v_checked := v_checked + 1;
    IF r.conv IS NULL THEN CONTINUE; END IF;

    SELECT * INTO s FROM public.suporteapp_conversation_snapshot WHERE chatwoot_conversation_id = r.conv FOR UPDATE;
    IF NOT FOUND THEN v_sem := v_sem + 1; CONTINUE; END IF;

    v_campos := ARRAY[]::text[];
    IF r.status IS NOT NULL AND r.status IS DISTINCT FROM s.native_status THEN v_campos := array_append(v_campos, 'status'); END IF;
    IF r.priority IS NOT NULL AND r.priority IS DISTINCT FROM s.chatwoot_native_priority THEN v_campos := array_append(v_campos, 'prioridade'); END IF;
    IF r.agent_id IS DISTINCT FROM s.current_agent_id THEN v_campos := array_append(v_campos, 'agente'); END IF;
    IF r.team_id IS DISTINCT FROM s.current_team_id THEN v_campos := array_append(v_campos, 'time'); END IF;
    IF r.created_at IS NOT NULL AND (s.chatwoot_created_at IS NULL OR abs(extract(epoch FROM (r.created_at - s.chatwoot_created_at))) > 1)
       THEN v_campos := array_append(v_campos, 'criacao'); END IF;
    IF r.snoozed_until IS DISTINCT FROM s.snoozed_until THEN v_campos := array_append(v_campos, 'soneca'); END IF;
    IF r.sla_policy_id IS DISTINCT FROM s.sla_policy_id THEN v_campos := array_append(v_campos, 'sla'); END IF;

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
          jsonb_build_object('modo', p_modo, 'atualizadas', v_updated, 'drift', v_drift, 'sem_snapshot', v_sem,
                             'por_campo', v_por_campo, 'conversas_com_drift', v_drift_convs),
          'n8n', p_n8n_workflow, p_n8n_execution);

  RETURN jsonb_build_object('checked', v_checked, 'atualizadas', v_updated, 'drift', v_drift, 'sem_snapshot', v_sem,
                            'por_campo', v_por_campo, 'conversas_com_drift', v_drift_convs);
END;
$function$;

-- ---------------------------------------------------------------------------------------------
-- ACL: só service_role (N8N) executa; nenhuma função aqui é para anon/authenticated
-- ---------------------------------------------------------------------------------------------
DO $$
DECLARE f regprocedure;
BEGIN
  FOR f IN SELECT p.oid::regprocedure FROM pg_proc p
            WHERE p.pronamespace = 'public'::regnamespace
              AND p.proname IN ('suporteapp_upsert_conversation_snapshot', 'suporteapp_sync_conversation_state')
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', f);
  END LOOP;
END $$;
