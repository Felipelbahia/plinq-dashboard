-- L5 (patch, 2026-10-02): "resposta humana" de verdade.
-- O bot JulIA (verificação inicial) responde em ~4 s em parte das conversas e o antigo critério (agent OU bot) fazia a 1ª resposta
-- "humana" e o estado da fila (aguardando Plinq x usuária) enxergarem essa mensagem automática. As colunas legadas
-- (first_public_reply_at / last_agent_message_at = agent|bot, regra de suporteapp_record_message_event) continuam na visão;
-- novas colunas first_human_reply_at / last_human_message_at (só sender_type='agent') passam a alimentar as métricas que se
-- chamam "humanas": turn_metrics, avoidable_vs_structural, weekly_reasons (espera), dashboard_queue, alarm_panel, daily_shift_metrics
-- (herdadas) e first_contact_resolution (só saídas de agente). suporteapp_v_response_pairs já ignorava bot.

CREATE OR REPLACE VIEW public.suporteapp_v_conversations AS
SELECT
  s.chatwoot_conversation_id                                   AS conversation_id,
  s.chatwoot_inbox_id                                          AS inbox_id,
  i.channel_type                                               AS channel,
  s.native_status                                              AS status,
  COALESCE(s.chatwoot_native_priority, 'none')                 AS severity,
  COALESCE(s.chatwoot_created_at, m.first_message_at, s.created_at) AS created_at,
  s.resolved_at,
  s.reopened_count,
  s.last_reopened_at,
  CASE WHEN s.native_status = 'resolved' AND s.resolved_at IS NOT NULL
       THEN public.suporteapp_fn_classify_resolution_type(s.current_agent_id, s.resolved_at, m.last_customer_message_at) END AS resolution_type,
  s.current_agent_id,
  s.current_agent_name,
  s.current_team_id,
  s.current_team_name,
  COALESCE(s.current_labels, ARRAY[]::text[])                  AS current_labels,
  m.first_agent_action_at,
  m.first_public_reply_at,
  m.last_customer_message_at,
  m.last_agent_message_at,
  s.chatwoot_contact_id                                        AS contact_id,
  c.name                                                       AS contact_name,
  c.person_id,
  c.company_id,
  comp.name                                                    AS company_name,
  s.snoozed_until,
  s.waiting_since,
  s.last_activity_at,
  m.first_human_reply_at,
  m.last_human_message_at
FROM public.suporteapp_conversation_snapshot s
LEFT JOIN public.suporteapp_chatwoot_inboxes i
       ON i.chatwoot_inbox_id = s.chatwoot_inbox_id
LEFT JOIN LATERAL (
  SELECT min(x.created_at) AS first_message_at,
         min(x.created_at) FILTER (WHERE x.sender_type IN ('agent','bot') AND x.message_type IN ('outgoing','private_note')) AS first_agent_action_at,
         min(x.created_at) FILTER (WHERE x.sender_type IN ('agent','bot') AND x.message_type = 'outgoing')                    AS first_public_reply_at,
         max(x.created_at) FILTER (WHERE x.sender_type = 'customer')                                                          AS last_customer_message_at,
         max(x.created_at) FILTER (WHERE x.sender_type IN ('agent','bot') AND x.message_type = 'outgoing')                    AS last_agent_message_at,
         min(x.created_at) FILTER (WHERE x.sender_type = 'agent' AND x.message_type = 'outgoing')                             AS first_human_reply_at,
         max(x.created_at) FILTER (WHERE x.sender_type = 'agent' AND x.message_type = 'outgoing')                             AS last_human_message_at
    FROM public.suporteapp_messages x
   WHERE x.chatwoot_conversation_id = s.chatwoot_conversation_id
     AND x.message_type <> 'template'
) m ON true
LEFT JOIN public.suporteapp_contacts c
       ON c.chatwoot_contact_id = s.chatwoot_contact_id
LEFT JOIN public.suporteapp_chatwoot_companies comp
       ON comp.chatwoot_company_id = c.company_id AND comp.chatwoot_account_id = 88;

REVOKE ALL ON public.suporteapp_v_conversations FROM PUBLIC, anon, authenticated;

DROP FUNCTION IF EXISTS public.suporteapp_rpc_conversation_drilldown(integer[], integer[], integer[], text[], text[], text[], text[], text, text, integer);
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
           c.first_human_reply_at, c.last_customer_message_at, c.last_human_message_at, c.contact_name, c.company_name,
           CASE WHEN c.last_customer_message_at IS NOT NULL
                     AND (c.last_human_message_at IS NULL OR c.last_customer_message_at > c.last_human_message_at)
                THEN 'waiting_plinq' ELSE 'waiting_customer' END
      FROM public.suporteapp_fn_scope_conversations(
             p_inbox_ids, p_agent_ids, p_team_ids, p_severities, p_origins, p_taxonomies, p_tags,
             p_business_hours_filter, p_weekend_filter) c
     ORDER BY c.created_at DESC
     LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 1500), 5000));
$function$;

-- 17 RPCs (mesma assinatura e colunas de retorno)
CREATE OR REPLACE FUNCTION public.suporteapp_rpc_dashboard_queue(p_inbox_ids integer[] DEFAULT NULL::integer[], p_agent_ids integer[] DEFAULT NULL::integer[], p_team_ids integer[] DEFAULT NULL::integer[], p_severities text[] DEFAULT NULL::text[], p_origins text[] DEFAULT NULL::text[], p_taxonomies text[] DEFAULT NULL::text[], p_tags text[] DEFAULT NULL::text[], p_business_hours_filter text DEFAULT 'all'::text, p_weekend_filter text DEFAULT 'all'::text)
 RETURNS TABLE(d01_waiting_plinq bigint, d02_waiting_customer bigint, d03_red_aberta_alerts bigint, d05_unserviced_tickets bigint, d04_under_1h bigint, d04_1h_to_4h bigint, d04_4h_to_24h bigint, d04_24h_to_72h bigint, d04_over_72h bigint, d04_median_biz_minutes numeric, d04_p90_biz_minutes numeric, d06_taxonomy_adherence_pct numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    WITH base AS (
        SELECT t.* FROM public.suporteapp_fn_scope_conversations(
            p_inbox_ids, p_agent_ids, p_team_ids, p_severities, p_origins, p_taxonomies, p_tags,
            p_business_hours_filter, p_weekend_filter
        ) t
        WHERE t.status = 'open'
    ),
    current_queue AS (
        SELECT
            b.*,
            CASE
                WHEN b.last_customer_message_at IS NOT NULL
                     AND (b.last_human_message_at IS NULL OR b.last_customer_message_at > b.last_human_message_at)
                THEN 'waiting_plinq' ELSE 'waiting_customer'
            END AS queue_state,
            ROUND(EXTRACT(EPOCH FROM (NOW() - COALESCE(b.last_customer_message_at, b.created_at))) / 60.0, 2) AS waiting_raw_minutes,
            public.suporteapp_fn_calculate_business_minutes(COALESCE(b.last_customer_message_at, b.created_at), NOW()) AS waiting_biz_minutes
        FROM base b
    ),
    adherence_calc AS (
        SELECT
            COUNT(*) AS total_tickets,
            COUNT(*) FILTER (
                WHERE EXISTS (SELECT 1 FROM unnest(current_labels) AS l
                               JOIN public.suporteapp_label_taxonomy tx ON tx.label_name = l AND tx.label_category = 'reason')
            ) AS valid_tagged_tickets
        FROM base
    )
    SELECT
        COUNT(*) FILTER (WHERE queue_state = 'waiting_plinq'),
        COUNT(*) FILTER (WHERE queue_state = 'waiting_customer'),
        COUNT(*) FILTER (WHERE queue_state = 'waiting_plinq' AND severity = 'urgent' AND waiting_raw_minutes > 10),
        COUNT(*) FILTER (WHERE queue_state = 'waiting_plinq' AND last_human_message_at IS NULL),
        COUNT(*) FILTER (WHERE queue_state = 'waiting_plinq' AND waiting_biz_minutes < 60),
        COUNT(*) FILTER (WHERE queue_state = 'waiting_plinq' AND waiting_biz_minutes >= 60 AND waiting_biz_minutes < 240),
        COUNT(*) FILTER (WHERE queue_state = 'waiting_plinq' AND waiting_biz_minutes >= 240 AND waiting_biz_minutes < 1440),
        COUNT(*) FILTER (WHERE queue_state = 'waiting_plinq' AND waiting_biz_minutes >= 1440 AND waiting_biz_minutes < 4320),
        COUNT(*) FILTER (WHERE queue_state = 'waiting_plinq' AND waiting_biz_minutes >= 4320),
        PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY waiting_biz_minutes) FILTER (WHERE queue_state = 'waiting_plinq'),
        PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY waiting_biz_minutes) FILTER (WHERE queue_state = 'waiting_plinq'),
        (SELECT ROUND(valid_tagged_tickets * 100.0 / NULLIF(total_tickets, 0), 2) FROM adherence_calc)
    FROM current_queue;
$function$;

CREATE OR REPLACE FUNCTION public.suporteapp_rpc_turn_metrics(p_period text DEFAULT 'today'::text, p_date_start date DEFAULT NULL::date, p_date_end date DEFAULT NULL::date, p_inbox_ids integer[] DEFAULT NULL::integer[], p_agent_ids integer[] DEFAULT NULL::integer[], p_team_ids integer[] DEFAULT NULL::integer[], p_severities text[] DEFAULT NULL::text[], p_origins text[] DEFAULT NULL::text[], p_taxonomies text[] DEFAULT NULL::text[], p_tags text[] DEFAULT NULL::text[], p_business_hours_filter text DEFAULT 'all'::text, p_weekend_filter text DEFAULT 'all'::text)
 RETURNS TABLE(total_tickets bigint, tickets_with_human_reply bigint, d08_without_human_reply bigint, d08_avg_turn1_biz_minutes numeric, d08_median_turn1_biz_minutes double precision, d08_p90_turn1_biz_minutes double precision, d09_meta_10min_compliance_pct numeric, rs04_median_turn1_raw_minutes double precision, rs04_p90_turn1_raw_minutes double precision, rs04_avg_turn1_raw_minutes numeric, rs04_meta_10min_compliance_raw_pct numeric, tickets_resolved bigint, resolved_manual bigint, resolved_inactivity bigint, resolved_bot_auto bigint, d10_median_turn2_biz_minutes double precision, outside_biz_count bigint, outside_red_count bigint, outside_biz_pct numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_start TIMESTAMPTZ;
    v_end TIMESTAMPTZ;
BEGIN
    SELECT range_start, range_end INTO v_start, v_end
    FROM public.suporteapp_fn_resolve_period_range(p_period, p_date_start, p_date_end);

    RETURN QUERY
    WITH scoped AS (
        SELECT t.* FROM public.suporteapp_fn_scope_conversations(
            p_inbox_ids, p_agent_ids, p_team_ids, p_severities, p_origins, p_taxonomies, p_tags,
            p_business_hours_filter, p_weekend_filter
        ) t
    ),
    turn1_messages AS (
        SELECT
            s.conversation_id AS conv_id,
            s.created_at AS ticket_created_at,
            s.first_human_reply_at,
            s.severity,
            s.current_labels,
            CASE 
                WHEN s.first_human_reply_at IS NOT NULL 
                THEN public.suporteapp_fn_calculate_business_minutes(s.created_at, s.first_human_reply_at)
                ELSE NULL 
            END AS turn1_biz_minutes,
            ROUND(EXTRACT(EPOCH FROM (s.first_human_reply_at - s.created_at)) / 60.0, 2) AS turn1_raw_minutes,
            (public.suporteapp_fn_get_atendivel_start(s.created_at) <> s.created_at) AS created_outside_biz
        FROM scoped s
        WHERE s.created_at >= v_start AND s.created_at < v_end
          AND (s.first_human_reply_at IS NULL OR s.first_human_reply_at >= s.created_at)
    ),
    resolved_in_period AS (
        SELECT s.conversation_id, s.resolution_type
        FROM scoped s
        WHERE s.resolved_at >= v_start AND s.resolved_at < v_end
    ),
    turn2_pairs AS (
        SELECT
            rp.chatwoot_conversation_id AS conv_id,
            public.suporteapp_fn_calculate_business_minutes(rp.customer_message_at, rp.agent_response_at) AS turn_biz_minutes,
            ROW_NUMBER() OVER (PARTITION BY rp.chatwoot_conversation_id ORDER BY rp.customer_message_at) AS rn
        FROM public.suporteapp_v_response_pairs rp
        JOIN scoped s ON s.conversation_id = rp.chatwoot_conversation_id
        WHERE rp.customer_message_at >= v_start AND rp.customer_message_at < v_end
    )
    SELECT
        (SELECT COUNT(*) FROM turn1_messages),
        (SELECT COUNT(*) FROM turn1_messages WHERE first_human_reply_at IS NOT NULL),
        (SELECT COUNT(*) FROM turn1_messages WHERE first_human_reply_at IS NULL),
        (SELECT ROUND(AVG(turn1_biz_minutes) FILTER (WHERE first_human_reply_at IS NOT NULL), 2) FROM turn1_messages),
        (SELECT PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY turn1_biz_minutes) FILTER (WHERE first_human_reply_at IS NOT NULL) FROM turn1_messages),
        (SELECT PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY turn1_biz_minutes) FILTER (WHERE first_human_reply_at IS NOT NULL) FROM turn1_messages),
        (SELECT ROUND(COUNT(*) FILTER (WHERE turn1_biz_minutes <= 10 AND first_human_reply_at IS NOT NULL)::numeric * 100.0 /
                NULLIF(COUNT(*) FILTER (WHERE first_human_reply_at IS NOT NULL), 0), 2) FROM turn1_messages),
        (SELECT PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY turn1_raw_minutes) FILTER (WHERE first_human_reply_at IS NOT NULL) FROM turn1_messages),
        (SELECT PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY turn1_raw_minutes) FILTER (WHERE first_human_reply_at IS NOT NULL) FROM turn1_messages),
        (SELECT ROUND(AVG(turn1_raw_minutes) FILTER (WHERE first_human_reply_at IS NOT NULL), 2) FROM turn1_messages),
        (SELECT ROUND(COUNT(*) FILTER (WHERE turn1_raw_minutes <= 10 AND first_human_reply_at IS NOT NULL)::numeric * 100.0 /
                NULLIF(COUNT(*) FILTER (WHERE first_human_reply_at IS NOT NULL), 0), 2) FROM turn1_messages),
        (SELECT COUNT(*) FROM resolved_in_period),
        (SELECT COUNT(*) FROM resolved_in_period WHERE resolution_type = 'manual'),
        (SELECT COUNT(*) FROM resolved_in_period WHERE resolution_type = 'inactivity_3d'),
        (SELECT COUNT(*) FROM resolved_in_period WHERE resolution_type = 'bot_auto'),
        (SELECT PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY turn_biz_minutes) FROM turn2_pairs WHERE rn > 1),
        (SELECT COUNT(*) FROM turn1_messages WHERE created_outside_biz),
        (SELECT COUNT(*) FROM turn1_messages WHERE created_outside_biz AND severity = 'urgent'),
        (SELECT ROUND(COUNT(*) FILTER (WHERE created_outside_biz)::numeric * 100.0 / NULLIF(COUNT(*), 0), 2) FROM turn1_messages);
END;
$function$;

CREATE OR REPLACE FUNCTION public.suporteapp_rpc_daily_shift_metrics(p_period text DEFAULT 'today'::text, p_date_start date DEFAULT NULL::date, p_date_end date DEFAULT NULL::date, p_inbox_ids integer[] DEFAULT NULL::integer[], p_agent_ids integer[] DEFAULT NULL::integer[], p_team_ids integer[] DEFAULT NULL::integer[], p_severities text[] DEFAULT NULL::text[], p_origins text[] DEFAULT NULL::text[], p_taxonomies text[] DEFAULT NULL::text[], p_tags text[] DEFAULT NULL::text[], p_business_hours_filter text DEFAULT 'all'::text, p_weekend_filter text DEFAULT 'all'::text)
 RETURNS TABLE(period_days integer, avg_opening_latency_minutes numeric, avg_closing_time text, avg_stop_before_closing_minutes numeric, days_count integer, inherited_queue_count bigint, time_to_zero_hours numeric, max_idle_minutes numeric, max_idle_start text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_start TIMESTAMPTZ;
    v_end TIMESTAMPTZ;
    v_today_9am TIMESTAMPTZ;
    v_today_18pm TIMESTAMPTZ;
BEGIN
    SELECT range_start, range_end INTO v_start, v_end
    FROM public.suporteapp_fn_resolve_period_range(p_period, p_date_start, p_date_end);
    v_today_9am := ((NOW() AT TIME ZONE 'America/Sao_Paulo')::date || ' 09:00:00')::timestamp AT TIME ZONE 'America/Sao_Paulo';
    v_today_18pm := ((NOW() AT TIME ZONE 'America/Sao_Paulo')::date || ' 18:00:00')::timestamp AT TIME ZONE 'America/Sao_Paulo';

    RETURN QUERY
    WITH scoped_msgs AS (
        SELECT m.*
        FROM public.suporteapp_messages m
        JOIN public.suporteapp_fn_scope_conversations(
            p_inbox_ids, p_agent_ids, p_team_ids, p_severities, p_origins, p_taxonomies, p_tags,
            p_business_hours_filter, p_weekend_filter
        ) t ON t.conversation_id = m.chatwoot_conversation_id
    ),
    agent_replies AS (
        SELECT
            (m.created_at AT TIME ZONE 'America/Sao_Paulo')::date AS reply_date,
            MIN(m.created_at AT TIME ZONE 'America/Sao_Paulo') AS first_reply_time,
            MAX(m.created_at AT TIME ZONE 'America/Sao_Paulo') AS last_reply_time
        FROM scoped_msgs m
        WHERE m.sender_type IN ('agent', 'User')
          AND m.is_private = false
          AND m.created_at >= v_start AND m.created_at < v_end
        GROUP BY (m.created_at AT TIME ZONE 'America/Sao_Paulo')::date
    ),
    daily_calc AS (
        SELECT
            reply_date,
            EXTRACT(EPOCH FROM (first_reply_time - (reply_date || ' 09:00:00')::timestamp)) / 60.0 AS opening_latency_min,
            EXTRACT(EPOCH FROM (last_reply_time - (reply_date || ' 00:00:00')::timestamp)) AS last_reply_seconds,
            EXTRACT(EPOCH FROM ((reply_date || ' 18:00:00')::timestamp - last_reply_time)) / 60.0 AS stop_before_closing_min
        FROM agent_replies
    ),
    today_gaps AS (
        SELECT
            m.created_at,
            LAG(m.created_at) OVER (ORDER BY m.created_at) AS prev_created_at
        FROM scoped_msgs m
        WHERE m.sender_type IN ('agent', 'User')
          AND m.is_private = false
          AND m.created_at >= v_today_9am AND m.created_at <= v_today_18pm
    ),
    inherited AS (
        SELECT t.conversation_id, t.resolved_at
        FROM public.suporteapp_fn_scope_conversations(
            p_inbox_ids, p_agent_ids, p_team_ids, p_severities, p_origins, p_taxonomies, p_tags,
            p_business_hours_filter, p_weekend_filter
        ) t
        WHERE t.created_at < v_today_9am
          AND (t.status != 'resolved' OR t.resolved_at >= v_today_9am)
          AND (t.last_customer_message_at IS NOT NULL
               AND (t.last_human_message_at IS NULL OR t.last_customer_message_at > t.last_human_message_at)
               OR t.status != 'resolved')
    )
    SELECT
        (CASE WHEN p_period = 'today' THEN 1 WHEN p_period = '7d' THEN 7 WHEN p_period = '30d' THEN 30
              ELSE GREATEST(1, (v_end::date - v_start::date)) END),
        (SELECT ROUND(AVG(GREATEST(0, opening_latency_min)), 2) FROM daily_calc),
        (SELECT COALESCE(TO_CHAR(TO_TIMESTAMP(AVG(last_reply_seconds)), 'HH24:MI'), '18:00') FROM daily_calc),
        (SELECT ROUND(AVG(stop_before_closing_min), 2) FROM daily_calc),
        (SELECT COUNT(*)::int FROM daily_calc),
        (SELECT COUNT(*) FROM inherited),
        (SELECT ROUND(EXTRACT(EPOCH FROM (MAX(resolved_at) - v_today_9am)) / 3600.0, 2)
           FROM inherited WHERE resolved_at IS NOT NULL
           HAVING COUNT(*) FILTER (WHERE resolved_at IS NULL) = 0 AND COUNT(*) > 0),
        (SELECT ROUND(MAX(EXTRACT(EPOCH FROM (created_at - prev_created_at)) / 60.0), 2) FROM today_gaps WHERE prev_created_at IS NOT NULL),
        (SELECT TO_CHAR(prev_created_at AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI') FROM today_gaps
           WHERE prev_created_at IS NOT NULL
           ORDER BY EXTRACT(EPOCH FROM (created_at - prev_created_at)) DESC LIMIT 1);
END;
$function$;

CREATE OR REPLACE FUNCTION public.suporteapp_rpc_bot_metrics(p_period text DEFAULT 'today'::text, p_date_start date DEFAULT NULL::date, p_date_end date DEFAULT NULL::date, p_inbox_ids integer[] DEFAULT NULL::integer[], p_agent_ids integer[] DEFAULT NULL::integer[], p_team_ids integer[] DEFAULT NULL::integer[], p_severities text[] DEFAULT NULL::text[], p_origins text[] DEFAULT NULL::text[], p_taxonomies text[] DEFAULT NULL::text[], p_tags text[] DEFAULT NULL::text[], p_business_hours_filter text DEFAULT 'all'::text, p_weekend_filter text DEFAULT 'all'::text)
 RETURNS TABLE(bot_total_conversations bigint, bot_containment_pct numeric, bot_handover_pct numeric, bot_inherited_queue bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_start TIMESTAMPTZ;
    v_end TIMESTAMPTZ;
    v_today_9am TIMESTAMPTZ;
BEGIN
    SELECT range_start, range_end INTO v_start, v_end
    FROM public.suporteapp_fn_resolve_period_range(p_period, p_date_start, p_date_end);
    v_today_9am := ((NOW() AT TIME ZONE 'America/Sao_Paulo')::date || ' 09:00:00')::timestamp AT TIME ZONE 'America/Sao_Paulo';

    RETURN QUERY
    WITH bot_started AS (
        SELECT DISTINCT t.conversation_id, t.status, t.created_at, t.current_agent_id
        FROM public.suporteapp_fn_scope_conversations(
            p_inbox_ids, p_agent_ids, p_team_ids, p_severities, p_origins, p_taxonomies, p_tags,
            p_business_hours_filter, p_weekend_filter
        ) t
        JOIN public.suporteapp_messages m ON m.chatwoot_conversation_id = t.conversation_id
        WHERE t.created_at >= v_start AND t.created_at < v_end
          AND (m.sender_type = 'bot' OR public.suporteapp_fn_is_bot_agent(m.sender_agent_id))
    ),
    transferred_from_bot AS (
        SELECT DISTINCT tr.chatwoot_conversation_id
        FROM public.suporteapp_v_transfers tr
        WHERE public.suporteapp_fn_is_bot_agent(tr.from_agent_id::integer)
    )
    SELECT
        (SELECT COUNT(*) FROM bot_started),
        (SELECT ROUND(COUNT(*) FILTER (WHERE bs.status = 'resolved' AND bs.conversation_id NOT IN (SELECT chatwoot_conversation_id FROM transferred_from_bot))::numeric * 100.0
                / NULLIF(COUNT(*), 0), 2) FROM bot_started bs),
        (SELECT ROUND(COUNT(*) FILTER (WHERE bs.conversation_id IN (SELECT chatwoot_conversation_id FROM transferred_from_bot))::numeric * 100.0
                / NULLIF(COUNT(*), 0), 2) FROM bot_started bs),
        (SELECT COUNT(*) FROM bot_started bs WHERE bs.status != 'resolved' AND bs.created_at < v_today_9am);
END;
$function$;

CREATE OR REPLACE FUNCTION public.suporteapp_rpc_weekly_reasons(p_period text DEFAULT 'today'::text, p_date_start date DEFAULT NULL::date, p_date_end date DEFAULT NULL::date, p_inbox_ids integer[] DEFAULT NULL::integer[], p_agent_ids integer[] DEFAULT NULL::integer[], p_team_ids integer[] DEFAULT NULL::integer[], p_severities text[] DEFAULT NULL::text[], p_origins text[] DEFAULT NULL::text[], p_taxonomies text[] DEFAULT NULL::text[], p_tags text[] DEFAULT NULL::text[], p_business_hours_filter text DEFAULT 'all'::text, p_weekend_filter text DEFAULT 'all'::text)
 RETURNS TABLE(reason_label text, total_count bigint, volume_pct numeric, volume_delta_pct numeric, median_wait_biz_minutes double precision, median_resolution_biz_minutes double precision)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_start TIMESTAMPTZ;
    v_end TIMESTAMPTZ;
    v_prev_start TIMESTAMPTZ;
    v_prev_end TIMESTAMPTZ;
BEGIN
    SELECT range_start, range_end INTO v_start, v_end
    FROM public.suporteapp_fn_resolve_period_range(p_period, p_date_start, p_date_end);
    v_prev_end := v_start;
    v_prev_start := v_start - (v_end - v_start);

    RETURN QUERY
    WITH scoped AS (
        SELECT t.* FROM public.suporteapp_fn_scope_conversations(
            p_inbox_ids, p_agent_ids, p_team_ids, p_severities, p_origins, p_taxonomies, p_tags,
            p_business_hours_filter, p_weekend_filter
        ) t
    ),
    unnested_tags AS (
        SELECT
            t.conversation_id AS conv_id,
            t.created_at,
            t.resolved_at,
            t.first_human_reply_at,
            COALESCE(
                (SELECT tag FROM unnest(t.current_labels) AS tag
                 JOIN public.suporteapp_label_taxonomy tax ON tax.label_name = tag AND tax.label_category = 'reason'
                 LIMIT 1),
                CASE WHEN array_length(t.current_labels, 1) > 1 THEN '(múltiplo)' ELSE '(ausente)' END
            ) AS reason_label,
            public.suporteapp_fn_calculate_business_minutes(t.created_at, t.first_human_reply_at) AS wait_biz_min,
            public.suporteapp_fn_calculate_business_minutes(t.created_at, t.resolved_at) AS resolution_biz_min
        FROM scoped t
        WHERE t.created_at >= v_start AND t.created_at < v_end
    ),
    previous_tags AS (
        SELECT
            COALESCE(
                (SELECT tag FROM unnest(t.current_labels) AS tag
                 JOIN public.suporteapp_label_taxonomy tax ON tax.label_name = tag AND tax.label_category = 'reason'
                 LIMIT 1),
                CASE WHEN array_length(t.current_labels, 1) > 1 THEN '(múltiplo)' ELSE '(ausente)' END
            ) AS reason_label
        FROM scoped t
        WHERE t.created_at >= v_prev_start AND t.created_at < v_prev_end
    ),
    previous_counts AS (
        SELECT pt.reason_label, COUNT(*) AS n FROM previous_tags pt GROUP BY pt.reason_label
    )
    SELECT
        ut.reason_label,
        COUNT(*),
        ROUND(COUNT(*)::numeric * 100.0 / SUM(COUNT(*)) OVER (), 2),
        CASE WHEN pc.n IS NULL OR pc.n = 0 THEN NULL
             ELSE ROUND((COUNT(*) - pc.n)::numeric * 100.0 / pc.n, 1)
        END,
        PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY ut.wait_biz_min),
        PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY ut.resolution_biz_min)
    FROM unnested_tags ut
    LEFT JOIN previous_counts pc ON pc.reason_label = ut.reason_label
    GROUP BY ut.reason_label, pc.n
    ORDER BY 2 DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.suporteapp_rpc_avoidable_vs_structural(p_period text DEFAULT 'today'::text, p_date_start date DEFAULT NULL::date, p_date_end date DEFAULT NULL::date, p_inbox_ids integer[] DEFAULT NULL::integer[], p_agent_ids integer[] DEFAULT NULL::integer[], p_team_ids integer[] DEFAULT NULL::integer[], p_severities text[] DEFAULT NULL::text[], p_origins text[] DEFAULT NULL::text[], p_taxonomies text[] DEFAULT NULL::text[], p_tags text[] DEFAULT NULL::text[], p_business_hours_filter text DEFAULT 'all'::text, p_weekend_filter text DEFAULT 'all'::text)
 RETURNS TABLE(avoidable_pct numeric, structural_pct numeric, avoidable_hours numeric, structural_hours numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_start TIMESTAMPTZ;
    v_end TIMESTAMPTZ;
BEGIN
    SELECT range_start, range_end INTO v_start, v_end
    FROM public.suporteapp_fn_resolve_period_range(p_period, p_date_start, p_date_end);

    RETURN QUERY
    WITH scoped AS (
        SELECT t.created_at, t.first_human_reply_at,
               public.suporteapp_fn_get_atendivel_start(t.created_at) AS atendivel_start
        FROM public.suporteapp_fn_scope_conversations(
            p_inbox_ids, p_agent_ids, p_team_ids, p_severities, p_origins, p_taxonomies, p_tags,
            p_business_hours_filter, p_weekend_filter
        ) t
        WHERE t.created_at >= v_start AND t.created_at < v_end
          AND t.first_human_reply_at IS NOT NULL
    ),
    split AS (
        SELECT
            GREATEST(0, EXTRACT(EPOCH FROM (atendivel_start - created_at))) / 3600.0 AS structural_h,
            GREATEST(0, EXTRACT(EPOCH FROM (first_human_reply_at - atendivel_start))) / 3600.0 AS avoidable_h
        FROM scoped
    )
    SELECT
        ROUND(SUM(avoidable_h) * 100.0 / NULLIF(SUM(avoidable_h) + SUM(structural_h), 0), 2),
        ROUND(SUM(structural_h) * 100.0 / NULLIF(SUM(avoidable_h) + SUM(structural_h), 0), 2),
        ROUND(SUM(avoidable_h), 1),
        ROUND(SUM(structural_h), 1)
    FROM split;
END;
$function$;

CREATE OR REPLACE FUNCTION public.suporteapp_rpc_weekly_heatmap(p_period text DEFAULT '7d'::text, p_date_start date DEFAULT NULL::date, p_date_end date DEFAULT NULL::date, p_inbox_ids integer[] DEFAULT NULL::integer[], p_agent_ids integer[] DEFAULT NULL::integer[], p_team_ids integer[] DEFAULT NULL::integer[], p_severities text[] DEFAULT NULL::text[], p_origins text[] DEFAULT NULL::text[], p_taxonomies text[] DEFAULT NULL::text[], p_tags text[] DEFAULT NULL::text[], p_business_hours_filter text DEFAULT 'all'::text, p_weekend_filter text DEFAULT 'all'::text)
 RETURNS TABLE(isodow integer, hour_bucket text, total_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_start TIMESTAMPTZ;
    v_end TIMESTAMPTZ;
BEGIN
    SELECT range_start, range_end INTO v_start, v_end
    FROM public.suporteapp_fn_resolve_period_range(p_period, p_date_start, p_date_end);

    RETURN QUERY
    WITH scoped AS (
        SELECT
            EXTRACT(ISODOW FROM t.created_at AT TIME ZONE 'America/Sao_Paulo')::int AS c_dow,
            EXTRACT(HOUR FROM t.created_at AT TIME ZONE 'America/Sao_Paulo')::int AS c_hr
        FROM public.suporteapp_fn_scope_conversations(
            p_inbox_ids, p_agent_ids, p_team_ids, p_severities, p_origins, p_taxonomies, p_tags,
            p_business_hours_filter, p_weekend_filter
        ) t
        WHERE t.created_at >= v_start AND t.created_at < v_end
    ),
    bucketed AS (
        SELECT c_dow AS b_dow,
            CASE
                WHEN c_hr >= 0 AND c_hr < 4 THEN '00h-04h'
                WHEN c_hr >= 4 AND c_hr < 8 THEN '04h-08h'
                WHEN c_hr >= 8 AND c_hr < 12 THEN '09h-12h'
                WHEN c_hr >= 12 AND c_hr < 15 THEN '12h-15h'
                WHEN c_hr >= 15 AND c_hr < 18 THEN '15h-18h'
                WHEN c_hr >= 18 AND c_hr < 21 THEN '18h-21h'
                ELSE '21h-24h'
            END AS b_bucket
        FROM scoped
    )
    SELECT b_dow, b_bucket, COUNT(*) FROM bucketed GROUP BY b_dow, b_bucket ORDER BY b_dow, b_bucket;
END;
$function$;

CREATE OR REPLACE FUNCTION public.suporteapp_rpc_reason_severity_matrix(p_period text DEFAULT '7d'::text, p_date_start date DEFAULT NULL::date, p_date_end date DEFAULT NULL::date, p_inbox_ids integer[] DEFAULT NULL::integer[], p_agent_ids integer[] DEFAULT NULL::integer[], p_team_ids integer[] DEFAULT NULL::integer[], p_severities text[] DEFAULT NULL::text[], p_origins text[] DEFAULT NULL::text[], p_taxonomies text[] DEFAULT NULL::text[], p_tags text[] DEFAULT NULL::text[], p_business_hours_filter text DEFAULT 'all'::text, p_weekend_filter text DEFAULT 'all'::text)
 RETURNS TABLE(reason_label text, p0_count bigint, p1_count bigint, p2_p3_count bigint, total_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_start TIMESTAMPTZ;
    v_end TIMESTAMPTZ;
BEGIN
    SELECT range_start, range_end INTO v_start, v_end
    FROM public.suporteapp_fn_resolve_period_range(p_period, p_date_start, p_date_end);

    RETURN QUERY
    WITH tagged AS (
        SELECT
            t.severity AS t_severity,
            (SELECT tag FROM unnest(t.current_labels) AS tag
             JOIN public.suporteapp_label_taxonomy tax ON tax.label_name = tag AND tax.label_category = 'reason'
             LIMIT 1) AS t_reason_label
        FROM public.suporteapp_fn_scope_conversations(
            p_inbox_ids, p_agent_ids, p_team_ids, p_severities, p_origins, p_taxonomies, p_tags,
            p_business_hours_filter, p_weekend_filter
        ) t
        WHERE t.created_at >= v_start AND t.created_at < v_end
          AND t.current_labels IS NOT NULL
    )
    SELECT
        t_reason_label,
        COUNT(*) FILTER (WHERE t_severity = 'urgent'),
        COUNT(*) FILTER (WHERE t_severity = 'high'),
        COUNT(*) FILTER (WHERE t_severity IN ('medium','low','none')),
        COUNT(*)
    FROM tagged
    WHERE t_reason_label IS NOT NULL
    GROUP BY t_reason_label
    ORDER BY COUNT(*) DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.suporteapp_rpc_resolution_breakdown(p_period text DEFAULT '7d'::text, p_date_start date DEFAULT NULL::date, p_date_end date DEFAULT NULL::date, p_inbox_ids integer[] DEFAULT NULL::integer[], p_agent_ids integer[] DEFAULT NULL::integer[], p_team_ids integer[] DEFAULT NULL::integer[], p_severities text[] DEFAULT NULL::text[], p_origins text[] DEFAULT NULL::text[], p_taxonomies text[] DEFAULT NULL::text[], p_tags text[] DEFAULT NULL::text[], p_business_hours_filter text DEFAULT 'all'::text, p_weekend_filter text DEFAULT 'all'::text)
 RETURNS TABLE(resolution_type text, total_count bigint, pct numeric, median_hours numeric, p90_hours numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_start TIMESTAMPTZ;
    v_end TIMESTAMPTZ;
BEGIN
    SELECT range_start, range_end INTO v_start, v_end
    FROM public.suporteapp_fn_resolve_period_range(p_period, p_date_start, p_date_end);

    RETURN QUERY
    WITH resolved AS (
        SELECT
            COALESCE(t.resolution_type, 'desconhecido') AS r_type,
            EXTRACT(EPOCH FROM (t.resolved_at - t.created_at)) / 3600.0 AS hours
        FROM public.suporteapp_fn_scope_conversations(
            p_inbox_ids, p_agent_ids, p_team_ids, p_severities, p_origins, p_taxonomies, p_tags,
            p_business_hours_filter, p_weekend_filter
        ) t
        WHERE t.status = 'resolved'
          AND t.resolved_at >= v_start AND t.resolved_at < v_end
    )
    SELECT
        r_type,
        COUNT(*),
        ROUND(COUNT(*)::numeric * 100.0 / SUM(COUNT(*)) OVER (), 2),
        ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY hours)::numeric, 2),
        ROUND(PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY hours)::numeric, 2)
    FROM resolved
    GROUP BY r_type
    ORDER BY 2 DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.suporteapp_rpc_reopen_count(p_period text DEFAULT '7d'::text, p_date_start date DEFAULT NULL::date, p_date_end date DEFAULT NULL::date, p_inbox_ids integer[] DEFAULT NULL::integer[], p_agent_ids integer[] DEFAULT NULL::integer[], p_team_ids integer[] DEFAULT NULL::integer[], p_severities text[] DEFAULT NULL::text[], p_origins text[] DEFAULT NULL::text[], p_taxonomies text[] DEFAULT NULL::text[], p_tags text[] DEFAULT NULL::text[], p_business_hours_filter text DEFAULT 'all'::text, p_weekend_filter text DEFAULT 'all'::text)
 RETURNS bigint
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_start TIMESTAMPTZ;
    v_end TIMESTAMPTZ;
BEGIN
    SELECT range_start, range_end INTO v_start, v_end
    FROM public.suporteapp_fn_resolve_period_range(p_period, p_date_start, p_date_end);

    RETURN (
        SELECT COUNT(*) FROM public.suporteapp_fn_scope_conversations(
            p_inbox_ids, p_agent_ids, p_team_ids, p_severities, p_origins, p_taxonomies, p_tags,
            p_business_hours_filter, p_weekend_filter
        ) t
        WHERE t.reopened_count > 0
          AND t.last_reopened_at >= v_start AND t.last_reopened_at < v_end
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.suporteapp_rpc_carried_stock(p_period text DEFAULT '7d'::text, p_date_start date DEFAULT NULL::date, p_date_end date DEFAULT NULL::date, p_inbox_ids integer[] DEFAULT NULL::integer[], p_agent_ids integer[] DEFAULT NULL::integer[], p_team_ids integer[] DEFAULT NULL::integer[], p_severities text[] DEFAULT NULL::text[], p_origins text[] DEFAULT NULL::text[], p_taxonomies text[] DEFAULT NULL::text[], p_tags text[] DEFAULT NULL::text[], p_business_hours_filter text DEFAULT 'all'::text, p_weekend_filter text DEFAULT 'all'::text)
 RETURNS TABLE(opening_stock bigint, created_in_period bigint, resolved_in_period bigint, carried_stock bigint, carried_over_7d bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_start TIMESTAMPTZ;
    v_end TIMESTAMPTZ;
BEGIN
    SELECT range_start, range_end INTO v_start, v_end
    FROM public.suporteapp_fn_resolve_period_range(p_period, p_date_start, p_date_end);

    RETURN QUERY
    WITH scoped AS (
        SELECT t.* FROM public.suporteapp_fn_scope_conversations(
            p_inbox_ids, p_agent_ids, p_team_ids, p_severities, p_origins, p_taxonomies, p_tags,
            p_business_hours_filter, p_weekend_filter
        ) t
    ),
    opening AS (
        SELECT COUNT(*) AS n FROM scoped t
        WHERE t.created_at < v_start AND (t.status != 'resolved' OR t.resolved_at >= v_start)
    ),
    created AS (
        SELECT COUNT(*) AS n FROM scoped t WHERE t.created_at >= v_start AND t.created_at < v_end
    ),
    resolved AS (
        SELECT COUNT(*) AS n FROM scoped t WHERE t.resolved_at >= v_start AND t.resolved_at < v_end
    ),
    carried AS (
        SELECT t.conversation_id, t.created_at FROM scoped t
        WHERE t.status != 'resolved'
    )
    SELECT
        (SELECT n FROM opening),
        (SELECT n FROM created),
        (SELECT n FROM resolved),
        (SELECT COUNT(*) FROM carried),
        (SELECT COUNT(*) FROM carried WHERE created_at < NOW() - INTERVAL '7 days');
END;
$function$;

CREATE OR REPLACE FUNCTION public.suporteapp_rpc_alarm_panel(p_period text DEFAULT '7d'::text, p_date_start date DEFAULT NULL::date, p_date_end date DEFAULT NULL::date, p_inbox_ids integer[] DEFAULT NULL::integer[], p_agent_ids integer[] DEFAULT NULL::integer[], p_team_ids integer[] DEFAULT NULL::integer[], p_severities text[] DEFAULT NULL::text[], p_origins text[] DEFAULT NULL::text[], p_taxonomies text[] DEFAULT NULL::text[], p_tags text[] DEFAULT NULL::text[], p_business_hours_filter text DEFAULT 'all'::text, p_weekend_filter text DEFAULT 'all'::text)
 RETURNS TABLE(sem_atendimento bigint, red_estourado_janela bigint, red_estourado_fora bigint, acima_72h bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_start TIMESTAMPTZ;
    v_end TIMESTAMPTZ;
BEGIN
    SELECT range_start, range_end INTO v_start, v_end
    FROM public.suporteapp_fn_resolve_period_range(p_period, p_date_start, p_date_end);

    RETURN QUERY
    WITH scoped AS (
        SELECT t.* FROM public.suporteapp_fn_scope_conversations(
            p_inbox_ids, p_agent_ids, p_team_ids, p_severities, p_origins, p_taxonomies, p_tags,
            p_business_hours_filter, p_weekend_filter
        ) t
    )
    SELECT
        (SELECT COUNT(*) FROM scoped t
            WHERE t.status = 'open' AND t.last_human_message_at IS NULL),
        (SELECT COUNT(*) FROM scoped t
            WHERE t.status = 'open' AND t.severity = 'urgent'
              AND (public.suporteapp_fn_get_atendivel_start(t.created_at) = t.created_at)
              AND EXTRACT(EPOCH FROM (NOW() - COALESCE(t.last_customer_message_at, t.created_at))) / 60.0 > 10),
        (SELECT COUNT(*) FROM scoped t
            WHERE t.created_at >= v_start AND t.created_at < v_end AND t.severity = 'urgent'
              AND (public.suporteapp_fn_get_atendivel_start(t.created_at) <> t.created_at)),
        (SELECT COUNT(*) FROM scoped t
            WHERE t.status = 'open'
              AND public.suporteapp_fn_calculate_business_minutes(COALESCE(t.last_customer_message_at, t.created_at), NOW()) >= 4320);
END;
$function$;

CREATE OR REPLACE FUNCTION public.suporteapp_rpc_weekly_handoff(p_period text DEFAULT 'today'::text, p_date_start date DEFAULT NULL::date, p_date_end date DEFAULT NULL::date, p_inbox_ids integer[] DEFAULT NULL::integer[], p_agent_ids integer[] DEFAULT NULL::integer[], p_team_ids integer[] DEFAULT NULL::integer[], p_severities text[] DEFAULT NULL::text[], p_origins text[] DEFAULT NULL::text[], p_taxonomies text[] DEFAULT NULL::text[], p_tags text[] DEFAULT NULL::text[], p_business_hours_filter text DEFAULT 'all'::text, p_weekend_filter text DEFAULT 'all'::text)
 RETURNS TABLE(destiny_area text, reason_label text, total_tickets bigint, median_resolution_days double precision)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_start TIMESTAMPTZ;
    v_end TIMESTAMPTZ;
BEGIN
    SELECT range_start, range_end INTO v_start, v_end
    FROM public.suporteapp_fn_resolve_period_range(p_period, p_date_start, p_date_end);

    RETURN QUERY
    WITH handoff_tickets AS (
        SELECT
            t.conversation_id AS conv_id,
            t.created_at,
            t.resolved_at,
            tax.destiny_area,
            tax.label_name AS reason_label,
            ROUND(EXTRACT(EPOCH FROM (t.resolved_at - t.created_at)) / 86400.0, 2) AS resolution_days
        FROM public.suporteapp_fn_scope_conversations(
            p_inbox_ids, p_agent_ids, p_team_ids, p_severities, p_origins, p_taxonomies, p_tags,
            p_business_hours_filter, p_weekend_filter
        ) t
        JOIN public.suporteapp_label_taxonomy tax ON tax.label_name = ANY(t.current_labels)
        WHERE tax.destiny_area IN ('engenharia', 'Gabi', 'Mariana')
          AND t.created_at >= v_start AND t.created_at < v_end
    )
    SELECT ht.destiny_area, ht.reason_label, COUNT(*), PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY ht.resolution_days)
    FROM handoff_tickets ht
    GROUP BY ht.destiny_area, ht.reason_label
    ORDER BY ht.destiny_area;
END;
$function$;

CREATE OR REPLACE FUNCTION public.suporteapp_rpc_first_contact_resolution(p_period text DEFAULT '7d'::text, p_date_start date DEFAULT NULL::date, p_date_end date DEFAULT NULL::date, p_inbox_ids integer[] DEFAULT NULL::integer[], p_agent_ids integer[] DEFAULT NULL::integer[], p_team_ids integer[] DEFAULT NULL::integer[], p_severities text[] DEFAULT NULL::text[], p_origins text[] DEFAULT NULL::text[], p_taxonomies text[] DEFAULT NULL::text[], p_tags text[] DEFAULT NULL::text[], p_business_hours_filter text DEFAULT 'all'::text, p_weekend_filter text DEFAULT 'all'::text)
 RETURNS TABLE(reason_label text, fcr_pct numeric, total_resolved bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_start TIMESTAMPTZ;
    v_end TIMESTAMPTZ;
BEGIN
    SELECT range_start, range_end INTO v_start, v_end
    FROM public.suporteapp_fn_resolve_period_range(p_period, p_date_start, p_date_end);

    RETURN QUERY
    WITH outgoing_counts AS (
        SELECT m.chatwoot_conversation_id AS oc_conv_id, COUNT(*) AS n_outgoing
        FROM public.suporteapp_messages m
        WHERE m.message_type = 'outgoing' AND m.is_private = false AND m.sender_type = 'agent'
        GROUP BY m.chatwoot_conversation_id
    ),
    resolved AS (
        SELECT
            COALESCE(
                (SELECT tag FROM unnest(t.current_labels) AS tag
                 JOIN public.suporteapp_label_taxonomy tax ON tax.label_name = tag AND tax.label_category = 'reason'
                 LIMIT 1),
                '(ausente)'
            ) AS r_reason_label,
            COALESCE(oc.n_outgoing, 0) = 1 AS is_fcr
        FROM public.suporteapp_fn_scope_conversations(
            p_inbox_ids, p_agent_ids, p_team_ids, p_severities, p_origins, p_taxonomies, p_tags,
            p_business_hours_filter, p_weekend_filter
        ) t
        LEFT JOIN outgoing_counts oc ON oc.oc_conv_id = t.conversation_id
        WHERE t.status = 'resolved' AND t.resolved_at >= v_start AND t.resolved_at < v_end
    )
    SELECT r_reason_label, ROUND(COUNT(*) FILTER (WHERE is_fcr)::numeric * 100.0 / NULLIF(COUNT(*), 0), 2), COUNT(*)
    FROM resolved
    GROUP BY r_reason_label
    ORDER BY 3 DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.suporteapp_rpc_recurrence_rate(p_date_end date DEFAULT NULL::date, p_inbox_ids integer[] DEFAULT NULL::integer[], p_agent_ids integer[] DEFAULT NULL::integer[], p_team_ids integer[] DEFAULT NULL::integer[], p_severities text[] DEFAULT NULL::text[], p_origins text[] DEFAULT NULL::text[], p_taxonomies text[] DEFAULT NULL::text[], p_tags text[] DEFAULT NULL::text[], p_business_hours_filter text DEFAULT 'all'::text, p_weekend_filter text DEFAULT 'all'::text)
 RETURNS TABLE(recurrence_7d_pct numeric, recurrence_30d_pct numeric, top_recurring_reason text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_end TIMESTAMPTZ := COALESCE(((p_date_end + 1)::timestamp) AT TIME ZONE 'America/Sao_Paulo', NOW());
BEGIN
    RETURN QUERY
    WITH scoped AS (
        SELECT t.* FROM public.suporteapp_fn_scope_conversations(
            p_inbox_ids, p_agent_ids, p_team_ids, p_severities, p_origins, p_taxonomies, p_tags,
            p_business_hours_filter, p_weekend_filter
        ) t
    ),
    last_7d AS (
        SELECT COALESCE(person_id::text, contact_id::text) AS rkey, COUNT(*) AS n
        FROM scoped
        WHERE created_at >= v_end - INTERVAL '7 days' AND created_at < v_end AND COALESCE(person_id::text, contact_id::text) IS NOT NULL
        GROUP BY 1
    ),
    last_30d AS (
        SELECT COALESCE(person_id::text, contact_id::text) AS rkey, COUNT(*) AS n
        FROM scoped
        WHERE created_at >= v_end - INTERVAL '30 days' AND created_at < v_end AND COALESCE(person_id::text, contact_id::text) IS NOT NULL
        GROUP BY 1
    ),
    top_reason AS (
        SELECT tag, COUNT(*) AS n
        FROM scoped t, unnest(t.current_labels) AS tag
        JOIN public.suporteapp_label_taxonomy tax ON tax.label_name = tag AND tax.label_category = 'reason'
        WHERE COALESCE(t.person_id::text, t.contact_id::text) IN (SELECT rkey FROM last_30d WHERE n > 1)
        GROUP BY tag ORDER BY n DESC LIMIT 1
    )
    SELECT
        ROUND((SELECT COUNT(*) FROM last_7d WHERE n > 1)::numeric * 100.0 / NULLIF((SELECT COUNT(*) FROM last_7d), 0), 2),
        ROUND((SELECT COUNT(*) FROM last_30d WHERE n > 1)::numeric * 100.0 / NULLIF((SELECT COUNT(*) FROM last_30d), 0), 2),
        (SELECT tag FROM top_reason);
END;
$function$;

CREATE OR REPLACE FUNCTION public.suporteapp_rpc_contest_and_false_negative(p_period text DEFAULT '7d'::text, p_date_start date DEFAULT NULL::date, p_date_end date DEFAULT NULL::date, p_inbox_ids integer[] DEFAULT NULL::integer[], p_agent_ids integer[] DEFAULT NULL::integer[], p_team_ids integer[] DEFAULT NULL::integer[], p_severities text[] DEFAULT NULL::text[], p_origins text[] DEFAULT NULL::text[], p_taxonomies text[] DEFAULT NULL::text[], p_tags text[] DEFAULT NULL::text[], p_business_hours_filter text DEFAULT 'all'::text, p_weekend_filter text DEFAULT 'all'::text)
 RETURNS TABLE(contested_count bigint, false_negative_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_start TIMESTAMPTZ;
    v_end TIMESTAMPTZ;
BEGIN
    SELECT range_start, range_end INTO v_start, v_end
    FROM public.suporteapp_fn_resolve_period_range(p_period, p_date_start, p_date_end);

    RETURN QUERY
    SELECT
        COUNT(*) FILTER (WHERE 'relatorio-contestado' = ANY(current_labels)),
        COUNT(*) FILTER (WHERE 'falso-negativo' = ANY(current_labels))
    FROM public.suporteapp_fn_scope_conversations(
        p_inbox_ids, p_agent_ids, p_team_ids, p_severities, p_origins, p_taxonomies, p_tags,
        p_business_hours_filter, p_weekend_filter
    ) t
    WHERE t.created_at >= v_start AND t.created_at < v_end;
END;
$function$;

CREATE OR REPLACE FUNCTION public.suporteapp_rpc_bot_handover_top_subjects(p_period text DEFAULT '7d'::text, p_date_start date DEFAULT NULL::date, p_date_end date DEFAULT NULL::date, p_limit integer DEFAULT 5, p_inbox_ids integer[] DEFAULT NULL::integer[], p_agent_ids integer[] DEFAULT NULL::integer[], p_team_ids integer[] DEFAULT NULL::integer[], p_severities text[] DEFAULT NULL::text[], p_origins text[] DEFAULT NULL::text[], p_taxonomies text[] DEFAULT NULL::text[], p_tags text[] DEFAULT NULL::text[], p_business_hours_filter text DEFAULT 'all'::text, p_weekend_filter text DEFAULT 'all'::text)
 RETURNS TABLE(reason_label text, handover_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_start TIMESTAMPTZ;
    v_end TIMESTAMPTZ;
BEGIN
    SELECT range_start, range_end INTO v_start, v_end
    FROM public.suporteapp_fn_resolve_period_range(p_period, p_date_start, p_date_end);

    RETURN QUERY
    WITH bot_transfers AS (
        SELECT DISTINCT tr.chatwoot_conversation_id
        FROM public.suporteapp_v_transfers tr
        WHERE public.suporteapp_fn_is_bot_agent(tr.from_agent_id::integer)
          AND tr.created_at >= v_start AND tr.created_at < v_end
    )
    SELECT
        COALESCE(
            (SELECT tag FROM unnest(t.current_labels) AS tag
             JOIN public.suporteapp_label_taxonomy tax ON tax.label_name = tag AND tax.label_category = 'reason'
             LIMIT 1),
            '(ausente)'
        ) AS reason_label,
        COUNT(*)
    FROM bot_transfers bt
    JOIN public.suporteapp_fn_scope_conversations(
        p_inbox_ids, p_agent_ids, p_team_ids, p_severities, p_origins, p_taxonomies, p_tags,
        p_business_hours_filter, p_weekend_filter
    ) t ON t.conversation_id = bt.chatwoot_conversation_id
    GROUP BY reason_label
    ORDER BY 2 DESC
    LIMIT p_limit;
END;
$function$;
