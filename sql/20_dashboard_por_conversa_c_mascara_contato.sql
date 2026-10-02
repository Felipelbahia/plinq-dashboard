-- L5 (patch c, 2026-10-02): o drilldown nunca devolve telefone/e-mail. Contato de WhatsApp sem nome é gravado pelo Chatwoot
-- com o telefone como nome; o teste de PII achou isso numa resposta a anon. Agora vira 'Contato ••••1234' (últimos 4 dígitos) e
-- nome com '@' vira 'Contato sem nome (e-mail)'. Mesma assinatura e colunas.
CREATE OR REPLACE FUNCTION public.suporteapp_rpc_conversation_drilldown(
  p_inbox_ids integer[] DEFAULT NULL::integer[], p_agent_ids integer[] DEFAULT NULL::integer[],
  p_team_ids integer[] DEFAULT NULL::integer[], p_severities text[] DEFAULT NULL::text[],
  p_origins text[] DEFAULT NULL::text[], p_taxonomies text[] DEFAULT NULL::text[],
  p_tags text[] DEFAULT NULL::text[], p_business_hours_filter text DEFAULT 'all'::text,
  p_weekend_filter text DEFAULT 'all'::text, p_limit integer DEFAULT 1500)
 RETURNS TABLE(conversation_id bigint, inbox_id integer, channel text, status text, severity text,
   created_at timestamp with time zone, resolved_at timestamp with time zone, resolution_type text, reopened_count integer,
   current_agent_id integer, current_agent_name text, current_team_id integer, current_team_name text, current_labels text[],
   first_human_reply_at timestamp with time zone, last_customer_message_at timestamp with time zone,
   last_human_message_at timestamp with time zone, contact_name text, company_name text, queue_state text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT c.conversation_id, c.inbox_id, c.channel, c.status, c.severity, c.created_at, c.resolved_at, c.resolution_type,
           c.reopened_count, c.current_agent_id, c.current_agent_name, c.current_team_id, c.current_team_name, c.current_labels,
           c.first_human_reply_at, c.last_customer_message_at, c.last_human_message_at,
           -- contato de WhatsApp sem nome é salvo com o telefone como nome: nunca devolver telefone/e-mail ao anon
           CASE WHEN c.contact_name ~ '@' THEN 'Contato sem nome (e-mail)'
                WHEN c.contact_name !~ '[A-Za-z]' AND regexp_replace(c.contact_name, '\D', '', 'g') ~ '^\d{8,}$'
                     THEN 'Contato ••••' || right(regexp_replace(c.contact_name, '\D', '', 'g'), 4)
                ELSE c.contact_name END,
           c.company_name,
           CASE WHEN c.last_customer_message_at IS NOT NULL
                     AND (c.last_human_message_at IS NULL OR c.last_customer_message_at > c.last_human_message_at)
                THEN 'waiting_plinq' ELSE 'waiting_customer' END
      FROM public.suporteapp_fn_scope_conversations(
             p_inbox_ids, p_agent_ids, p_team_ids, p_severities, p_origins, p_taxonomies, p_tags,
             p_business_hours_filter, p_weekend_filter) c
     ORDER BY c.created_at DESC
     LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 1500), 5000));
$function$;

