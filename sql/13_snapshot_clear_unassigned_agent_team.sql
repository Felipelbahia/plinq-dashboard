-- L1 Desatribuição de Agente e Time (2026-10-02).
-- Bug: o snapshot nunca registrava desatribuição (COALESCE mantinha o agente/time antigo).
-- Correção: com p_native_status informado (retrato completo da conversa, só o que o workflow
-- 'Log de Eventos da Conversa' envia) agente/time são gravados como vieram, inclusive NULL.
-- Mesma assinatura (sem overload); nada além dos 4 campos muda.
CREATE OR REPLACE FUNCTION public.suporteapp_upsert_conversation_snapshot(p_chatwoot_conversation_id bigint, p_event_at timestamp with time zone, p_chatwoot_inbox_id integer DEFAULT NULL::integer, p_ticket_id uuid DEFAULT NULL::uuid, p_native_status text DEFAULT NULL::text, p_agent_id integer DEFAULT NULL::integer, p_agent_name text DEFAULT NULL::text, p_team_id integer DEFAULT NULL::integer, p_team_name text DEFAULT NULL::text, p_labels text[] DEFAULT NULL::text[], p_n8n_workflow text DEFAULT NULL::text, p_n8n_execution text DEFAULT NULL::text, p_conversation_subject text DEFAULT NULL::text, p_contact_name text DEFAULT NULL::text, p_contact_email text DEFAULT NULL::text, p_custom_attributes jsonb DEFAULT NULL::jsonb)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_old   jsonb;
  v_last  timestamptz;
  v_apply boolean;
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
      conversation_subject, contact_name, contact_email, custom_attributes
  ) VALUES (
      p_chatwoot_conversation_id, p_chatwoot_inbox_id, p_ticket_id, p_native_status,
      p_agent_id, p_agent_name, p_team_id, p_team_name,
      p_labels, p_event_at, 'n8n', p_n8n_workflow, p_n8n_execution,
      p_conversation_subject, p_contact_name, p_contact_email, COALESCE(p_custom_attributes, '{}'::jsonb)
  )
  ON CONFLICT (chatwoot_conversation_id) DO UPDATE SET
      chatwoot_inbox_id = COALESCE(EXCLUDED.chatwoot_inbox_id, suporteapp_conversation_snapshot.chatwoot_inbox_id),
      ticket_id = COALESCE(EXCLUDED.ticket_id, suporteapp_conversation_snapshot.ticket_id),
      native_status = COALESCE(EXCLUDED.native_status, suporteapp_conversation_snapshot.native_status),
      -- L1 (2026-10-02): retrato completo de conversa (p_native_status informado) grava agente/time como vieram,
      -- inclusive NULL (= desatribuído). Chamada parcial (status nulo) continua preservando o valor anterior.
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
      last_event_at = EXCLUDED.last_event_at,
      updated_at = now(),
      aplicacao = 'n8n',
      n8n_workflow = EXCLUDED.n8n_workflow,
      n8n_execution = EXCLUDED.n8n_execution
  WHERE suporteapp_conversation_snapshot.last_event_at IS NULL
     OR EXCLUDED.last_event_at >= suporteapp_conversation_snapshot.last_event_at;
END;
$function$;
