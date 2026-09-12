-- Migration: 20260827_fix_rpcs_contrato_e_filtros.sql
-- Descrição: Fase B do projeto de correção do Dashboard v3.0.
--
-- Contrato de filtro comum, usado em toda RPC nova/alterada abaixo (mesmos 4 filtros que
-- hoje existem na barra de filtros do index.html mas nunca chegavam a nenhuma query):
--   p_inbox_id  INTEGER DEFAULT NULL  -- NULL = todos os canais; senão chatwoot_inbox_id exato
--   p_severity  TEXT    DEFAULT 'all' -- 'all' | 'P0' | 'P1' | 'P2' | 'P3'
--   p_origin    TEXT    DEFAULT 'all' -- 'all' | 'human' | 'bot' (current_agent_id é bot?)
--   p_taxonomy  TEXT    DEFAULT 'all' -- 'all' | 'valid' | 'missing' (2 tags obrigatórias)
--
-- suporteapp_rpc_turn_metrics e suporteapp_rpc_daily_shift_metrics já existiam ao vivo com
-- lógica real (não são as versões do arquivo antigo 04_VIEWS_DASHBOARD_E_RELATORIO.sql,
-- que estava desatualizado) — aqui elas são estendidas (CREATE OR REPLACE, mesma
-- assinatura + colunas novas) para: (a) aceitar os filtros acima e (b) devolver as colunas
-- que src/dashboard.js já esperava e não existiam (resolved_manual, resolved_inactivity,
-- tickets_resolved, d10_median_turn2_biz_minutes, outside_biz_count/red_count/pct,
-- inherited_queue_count, time_to_zero_hours, max_idle_minutes, max_idle_start).
--
-- suporteapp_rpc_weekly_handoff e suporteapp_rpc_weekly_reasons JÁ estavam corretas e
-- ligadas a suporteapp_label_taxonomy/current_labels — não precisaram de correção, só
-- ganham os 4 filtros novos para consistência com o resto do dashboard.
--
-- suporteapp_rpc_bot_metrics (404 ao vivo) e suporteapp_rpc_avoidable_vs_structural (404 ao
-- vivo) são criadas do zero aqui, com dado real em vez dos literais fixos do arquivo antigo.
--
-- suporteapp_v_dashboard_queue (Bloco A) vira também uma função parametrizada
-- suporteapp_rpc_dashboard_queue, porque view sem parâmetro não consegue responder aos 4
-- filtros antes da agregação — a view original é mantida intacta por compatibilidade.

-- Helper reaproveitado em várias RPCs: tickets é do agente atual bot?
CREATE OR REPLACE FUNCTION public.suporteapp_fn_is_bot_agent(p_chatwoot_agent_id INTEGER)
RETURNS BOOLEAN AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.suporteapp_chatwoot_agents ag
        WHERE ag.chatwoot_id = p_chatwoot_agent_id AND ag.is_bot = true
    );
$$ LANGUAGE sql STABLE;

-- =============================================================================
-- 1. suporteapp_rpc_dashboard_queue — Bloco A (D-01 a D-06), parametrizada
-- =============================================================================
CREATE OR REPLACE FUNCTION public.suporteapp_rpc_dashboard_queue(
    p_inbox_id INTEGER DEFAULT NULL,
    p_severity TEXT DEFAULT 'all',
    p_origin TEXT DEFAULT 'all',
    p_taxonomy TEXT DEFAULT 'all'
)
RETURNS TABLE (
    d01_waiting_plinq BIGINT,
    d02_waiting_customer BIGINT,
    d03_red_aberta_alerts BIGINT,
    d05_unserviced_tickets BIGINT,
    d04_under_1h BIGINT,
    d04_1h_to_4h BIGINT,
    d04_4h_to_24h BIGINT,
    d04_24h_to_72h BIGINT,
    d04_over_72h BIGINT,
    d04_median_biz_minutes NUMERIC,
    d04_p90_biz_minutes NUMERIC,
    d06_taxonomy_adherence_pct NUMERIC
) AS $$
    WITH base AS (
        SELECT t.*
        FROM public.suporteapp_tickets t
        WHERE t.status = 'open'
          AND (p_inbox_id IS NULL OR t.chatwoot_inbox_id = p_inbox_id)
          AND (p_severity = 'all' OR t.priority = p_severity)
          AND (
                p_origin = 'all'
                OR (p_origin = 'bot' AND public.suporteapp_fn_is_bot_agent(t.current_agent_id))
                OR (p_origin = 'human' AND NOT public.suporteapp_fn_is_bot_agent(t.current_agent_id))
              )
          AND (
                p_taxonomy = 'all'
                OR (p_taxonomy = 'valid' AND t.current_labels && ARRAY['sev-red','sev-yellow','sev-green']
                        AND t.current_labels && ARRAY['login-acesso','duvida-de-plano','erro-tecnico','app-fora-do-ar','reembolso','meus-dados-lgpd','pessoa-consultada','advogado-ou-autoridade'])
                OR (p_taxonomy = 'missing' AND NOT (t.current_labels && ARRAY['sev-red','sev-yellow','sev-green']
                        AND t.current_labels && ARRAY['login-acesso','duvida-de-plano','erro-tecnico','app-fora-do-ar','reembolso','meus-dados-lgpd','pessoa-consultada','advogado-ou-autoridade']))
              )
    ),
    current_queue AS (
        SELECT
            b.*,
            CASE
                WHEN b.last_customer_message_at IS NOT NULL
                     AND (b.last_agent_message_at IS NULL OR b.last_customer_message_at > b.last_agent_message_at)
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
                WHERE current_labels && ARRAY['sev-red','sev-yellow','sev-green']
                  AND current_labels && ARRAY['login-acesso','duvida-de-plano','erro-tecnico','app-fora-do-ar','reembolso','meus-dados-lgpd','pessoa-consultada','advogado-ou-autoridade']
            ) AS valid_tagged_tickets
        FROM base
    )
    SELECT
        COUNT(*) FILTER (WHERE queue_state = 'waiting_plinq'),
        COUNT(*) FILTER (WHERE queue_state = 'waiting_customer'),
        COUNT(*) FILTER (WHERE queue_state = 'waiting_plinq' AND (priority = 'P0' OR 'sev-red' = ANY(current_labels)) AND waiting_raw_minutes > 10),
        COUNT(*) FILTER (WHERE queue_state = 'waiting_plinq' AND last_agent_message_at IS NULL),
        COUNT(*) FILTER (WHERE queue_state = 'waiting_plinq' AND waiting_biz_minutes < 60),
        COUNT(*) FILTER (WHERE queue_state = 'waiting_plinq' AND waiting_biz_minutes >= 60 AND waiting_biz_minutes < 240),
        COUNT(*) FILTER (WHERE queue_state = 'waiting_plinq' AND waiting_biz_minutes >= 240 AND waiting_biz_minutes < 1440),
        COUNT(*) FILTER (WHERE queue_state = 'waiting_plinq' AND waiting_biz_minutes >= 1440 AND waiting_biz_minutes < 4320),
        COUNT(*) FILTER (WHERE queue_state = 'waiting_plinq' AND waiting_biz_minutes >= 4320),
        PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY waiting_biz_minutes) FILTER (WHERE queue_state = 'waiting_plinq'),
        PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY waiting_biz_minutes) FILTER (WHERE queue_state = 'waiting_plinq'),
        (SELECT ROUND(valid_tagged_tickets * 100.0 / NULLIF(total_tickets, 0), 2) FROM adherence_calc)
    FROM current_queue;
$$ LANGUAGE sql STABLE;

-- =============================================================================
-- 2. suporteapp_rpc_turn_metrics — estendida com filtros + colunas D-10/D-11/D-12
-- =============================================================================
CREATE OR REPLACE FUNCTION public.suporteapp_rpc_turn_metrics(
    p_period TEXT DEFAULT 'today',
    p_inbox_id INTEGER DEFAULT NULL,
    p_severity TEXT DEFAULT 'all',
    p_origin TEXT DEFAULT 'all',
    p_taxonomy TEXT DEFAULT 'all'
)
RETURNS TABLE (
    total_tickets BIGINT,
    tickets_with_human_reply BIGINT,
    d08_without_human_reply BIGINT,
    d08_avg_turn1_biz_minutes NUMERIC,
    d08_median_turn1_biz_minutes DOUBLE PRECISION,
    d08_p90_turn1_biz_minutes DOUBLE PRECISION,
    d09_meta_10min_compliance_pct NUMERIC,
    rs04_median_turn1_raw_minutes DOUBLE PRECISION,
    rs04_p90_turn1_raw_minutes DOUBLE PRECISION,
    tickets_resolved BIGINT,
    resolved_manual BIGINT,
    resolved_inactivity BIGINT,
    resolved_bot_auto BIGINT,
    d10_median_turn2_biz_minutes DOUBLE PRECISION,
    outside_biz_count BIGINT,
    outside_red_count BIGINT,
    outside_biz_pct NUMERIC
) AS $$
DECLARE
    v_start TIMESTAMPTZ;
BEGIN
    v_start := public.suporteapp_fn_get_period_start(p_period);

    RETURN QUERY
    WITH scoped AS (
        SELECT t.*
        FROM public.suporteapp_tickets t
        WHERE (p_inbox_id IS NULL OR t.chatwoot_inbox_id = p_inbox_id)
          AND (p_severity = 'all' OR t.priority = p_severity)
          AND (
                p_origin = 'all'
                OR (p_origin = 'bot' AND public.suporteapp_fn_is_bot_agent(t.current_agent_id))
                OR (p_origin = 'human' AND NOT public.suporteapp_fn_is_bot_agent(t.current_agent_id))
              )
          AND (
                p_taxonomy = 'all'
                OR (p_taxonomy = 'valid' AND t.current_labels && ARRAY['sev-red','sev-yellow','sev-green']
                        AND t.current_labels && ARRAY['login-acesso','duvida-de-plano','erro-tecnico','app-fora-do-ar','reembolso','meus-dados-lgpd','pessoa-consultada','advogado-ou-autoridade'])
                OR (p_taxonomy = 'missing' AND NOT (t.current_labels && ARRAY['sev-red','sev-yellow','sev-green']
                        AND t.current_labels && ARRAY['login-acesso','duvida-de-plano','erro-tecnico','app-fora-do-ar','reembolso','meus-dados-lgpd','pessoa-consultada','advogado-ou-autoridade']))
              )
    ),
    turn1_messages AS (
        SELECT
            s.id AS ticket_id,
            s.created_at AS ticket_created_at,
            s.first_public_reply_at,
            s.priority,
            s.current_labels,
            public.suporteapp_fn_calculate_business_minutes(s.created_at, s.first_public_reply_at) AS turn1_biz_minutes,
            ROUND(EXTRACT(EPOCH FROM (s.first_public_reply_at - s.created_at)) / 60.0, 2) AS turn1_raw_minutes,
            (public.suporteapp_fn_get_atendivel_start(s.created_at) <> s.created_at) AS created_outside_biz
        FROM scoped s
        WHERE s.created_at >= v_start
    ),
    resolved_in_period AS (
        SELECT s.id, s.resolution_type
        FROM scoped s
        WHERE s.resolved_at >= v_start
    ),
    turn2_pairs AS (
        SELECT
            rp.ticket_id,
            public.suporteapp_fn_calculate_business_minutes(rp.customer_message_at, rp.agent_response_at) AS turn_biz_minutes,
            ROW_NUMBER() OVER (PARTITION BY rp.ticket_id ORDER BY rp.customer_message_at) AS rn
        FROM public.suporteapp_v_response_pairs rp
        JOIN scoped s ON s.id = rp.ticket_id
        WHERE rp.customer_message_at >= v_start
    )
    SELECT
        (SELECT COUNT(*) FROM turn1_messages),
        (SELECT COUNT(*) FROM turn1_messages WHERE first_public_reply_at IS NOT NULL),
        (SELECT COUNT(*) FROM turn1_messages WHERE first_public_reply_at IS NULL),
        (SELECT ROUND(AVG(turn1_biz_minutes), 2) FROM turn1_messages),
        (SELECT PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY turn1_biz_minutes) FROM turn1_messages),
        (SELECT PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY turn1_biz_minutes) FROM turn1_messages),
        (SELECT ROUND(COUNT(*) FILTER (WHERE turn1_biz_minutes <= 10 AND first_public_reply_at IS NOT NULL)::numeric * 100.0 /
                NULLIF(COUNT(*) FILTER (WHERE first_public_reply_at IS NOT NULL), 0), 2) FROM turn1_messages),
        (SELECT PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY turn1_raw_minutes) FROM turn1_messages),
        (SELECT PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY turn1_raw_minutes) FROM turn1_messages),
        (SELECT COUNT(*) FROM resolved_in_period),
        (SELECT COUNT(*) FROM resolved_in_period WHERE resolution_type = 'manual'),
        (SELECT COUNT(*) FROM resolved_in_period WHERE resolution_type = 'inactivity_3d'),
        (SELECT COUNT(*) FROM resolved_in_period WHERE resolution_type = 'bot_auto'),
        (SELECT PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY turn_biz_minutes) FROM turn2_pairs WHERE rn > 1),
        (SELECT COUNT(*) FROM turn1_messages WHERE created_outside_biz),
        (SELECT COUNT(*) FROM turn1_messages WHERE created_outside_biz AND (priority = 'P0' OR 'sev-red' = ANY(current_labels))),
        (SELECT ROUND(COUNT(*) FILTER (WHERE created_outside_biz)::numeric * 100.0 / NULLIF(COUNT(*), 0), 2) FROM turn1_messages);
END;
$$ LANGUAGE plpgsql STABLE;

-- =============================================================================
-- 3. suporteapp_rpc_daily_shift_metrics — estendida com D-14/D-16 (+ filtros)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.suporteapp_rpc_daily_shift_metrics(
    p_period TEXT DEFAULT 'today',
    p_inbox_id INTEGER DEFAULT NULL,
    p_severity TEXT DEFAULT 'all',
    p_origin TEXT DEFAULT 'all',
    p_taxonomy TEXT DEFAULT 'all'
)
RETURNS TABLE (
    period_days INTEGER,
    avg_opening_latency_minutes NUMERIC,
    avg_closing_time TEXT,
    avg_stop_before_closing_minutes NUMERIC,
    days_count INTEGER,
    inherited_queue_count BIGINT,
    time_to_zero_hours NUMERIC,
    max_idle_minutes NUMERIC,
    max_idle_start TEXT
) AS $$
DECLARE
    v_start TIMESTAMPTZ;
    v_today_9am TIMESTAMPTZ;
    v_today_18pm TIMESTAMPTZ;
BEGIN
    v_start := public.suporteapp_fn_get_period_start(p_period);
    v_today_9am := ((NOW() AT TIME ZONE 'America/Sao_Paulo')::date || ' 09:00:00')::timestamp AT TIME ZONE 'America/Sao_Paulo';
    v_today_18pm := ((NOW() AT TIME ZONE 'America/Sao_Paulo')::date || ' 18:00:00')::timestamp AT TIME ZONE 'America/Sao_Paulo';

    RETURN QUERY
    WITH scoped_msgs AS (
        SELECT m.*
        FROM public.suporteapp_messages m
        JOIN public.suporteapp_tickets t ON t.id = m.ticket_id
        WHERE (p_inbox_id IS NULL OR t.chatwoot_inbox_id = p_inbox_id)
          AND (p_severity = 'all' OR t.priority = p_severity)
          AND (
                p_origin = 'all'
                OR (p_origin = 'bot' AND public.suporteapp_fn_is_bot_agent(t.current_agent_id))
                OR (p_origin = 'human' AND NOT public.suporteapp_fn_is_bot_agent(t.current_agent_id))
              )
    ),
    agent_replies AS (
        SELECT
            (m.created_at AT TIME ZONE 'America/Sao_Paulo')::date AS reply_date,
            MIN(m.created_at AT TIME ZONE 'America/Sao_Paulo') AS first_reply_time,
            MAX(m.created_at AT TIME ZONE 'America/Sao_Paulo') AS last_reply_time
        FROM scoped_msgs m
        WHERE m.sender_type IN ('agent', 'User')
          AND m.is_private = false
          AND m.created_at >= v_start
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
        SELECT t.id, t.resolved_at
        FROM public.suporteapp_tickets t
        WHERE (p_inbox_id IS NULL OR t.chatwoot_inbox_id = p_inbox_id)
          AND (p_severity = 'all' OR t.priority = p_severity)
          AND t.created_at < v_today_9am
          AND (t.status != 'resolved' OR t.resolved_at >= v_today_9am)
          AND (t.last_customer_message_at IS NOT NULL
               AND (t.last_agent_message_at IS NULL OR t.last_customer_message_at > t.last_agent_message_at)
               OR t.status != 'resolved')
    )
    SELECT
        (CASE WHEN p_period = 'today' THEN 1 WHEN p_period = '7d' THEN 7 ELSE 30 END),
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
$$ LANGUAGE plpgsql STABLE;

-- =============================================================================
-- 4. suporteapp_rpc_bot_metrics — real (não existia; era 404 ao vivo)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.suporteapp_rpc_bot_metrics(
    p_period TEXT DEFAULT 'today',
    p_inbox_id INTEGER DEFAULT NULL,
    p_severity TEXT DEFAULT 'all'
)
RETURNS TABLE (
    bot_total_conversations BIGINT,
    bot_containment_pct NUMERIC,
    bot_handover_pct NUMERIC,
    bot_inherited_queue BIGINT
) AS $$
DECLARE
    v_start TIMESTAMPTZ;
    v_today_9am TIMESTAMPTZ;
BEGIN
    v_start := public.suporteapp_fn_get_period_start(p_period);
    v_today_9am := ((NOW() AT TIME ZONE 'America/Sao_Paulo')::date || ' 09:00:00')::timestamp AT TIME ZONE 'America/Sao_Paulo';

    RETURN QUERY
    WITH bot_started AS (
        -- Conversas cujo primeiro remetente registrado foi um agent bot (sender_type='bot'
        -- ou sender_agent_id de um is_bot=true), no período.
        SELECT DISTINCT t.id, t.status, t.created_at, t.current_agent_id
        FROM public.suporteapp_tickets t
        JOIN public.suporteapp_messages m ON m.ticket_id = t.id
        WHERE (p_inbox_id IS NULL OR t.chatwoot_inbox_id = p_inbox_id)
          AND (p_severity = 'all' OR t.priority = p_severity)
          AND t.created_at >= v_start
          AND (m.sender_type = 'bot' OR public.suporteapp_fn_is_bot_agent(m.sender_agent_id))
    ),
    transferred_from_bot AS (
        SELECT DISTINCT tr.ticket_id
        FROM public.suporteapp_v_transfers tr
        WHERE public.suporteapp_fn_is_bot_agent(tr.from_agent_id::integer)
    )
    SELECT
        (SELECT COUNT(*) FROM bot_started),
        (SELECT ROUND(COUNT(*) FILTER (WHERE bs.status = 'resolved' AND bs.id NOT IN (SELECT ticket_id FROM transferred_from_bot))::numeric * 100.0
                / NULLIF(COUNT(*), 0), 2) FROM bot_started bs),
        (SELECT ROUND(COUNT(*) FILTER (WHERE bs.id IN (SELECT ticket_id FROM transferred_from_bot))::numeric * 100.0
                / NULLIF(COUNT(*), 0), 2) FROM bot_started bs),
        (SELECT COUNT(*) FROM bot_started bs WHERE bs.status != 'resolved' AND bs.created_at < v_today_9am);
END;
$$ LANGUAGE plpgsql STABLE;

-- =============================================================================
-- 5. suporteapp_rpc_avoidable_vs_structural — real (não existia; era 404 ao vivo)
-- RS-06: separa a espera da usuária (raw, tempo corrido) em "evitável" (parte que caiu
-- dentro da janela comercial) vs. "estrutural" (parte fora da janela), usando
-- suporteapp_fn_get_atendivel_start como fronteira.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.suporteapp_rpc_avoidable_vs_structural(
    p_period TEXT DEFAULT 'today',
    p_inbox_id INTEGER DEFAULT NULL,
    p_severity TEXT DEFAULT 'all'
)
RETURNS TABLE (
    avoidable_pct NUMERIC,
    structural_pct NUMERIC,
    avoidable_hours NUMERIC,
    structural_hours NUMERIC
) AS $$
DECLARE
    v_start TIMESTAMPTZ;
BEGIN
    v_start := public.suporteapp_fn_get_period_start(p_period);

    RETURN QUERY
    WITH scoped AS (
        SELECT t.created_at, t.first_public_reply_at,
               public.suporteapp_fn_get_atendivel_start(t.created_at) AS atendivel_start
        FROM public.suporteapp_tickets t
        WHERE t.created_at >= v_start
          AND t.first_public_reply_at IS NOT NULL
          AND (p_inbox_id IS NULL OR t.chatwoot_inbox_id = p_inbox_id)
          AND (p_severity = 'all' OR t.priority = p_severity)
    ),
    split AS (
        SELECT
            GREATEST(0, EXTRACT(EPOCH FROM (atendivel_start - created_at))) / 3600.0 AS structural_h,
            GREATEST(0, EXTRACT(EPOCH FROM (first_public_reply_at - atendivel_start))) / 3600.0 AS avoidable_h
        FROM scoped
    )
    SELECT
        ROUND(SUM(avoidable_h) * 100.0 / NULLIF(SUM(avoidable_h) + SUM(structural_h), 0), 2),
        ROUND(SUM(structural_h) * 100.0 / NULLIF(SUM(avoidable_h) + SUM(structural_h), 0), 2),
        ROUND(SUM(avoidable_h), 1),
        ROUND(SUM(structural_h), 1)
    FROM split;
END;
$$ LANGUAGE plpgsql STABLE;

-- =============================================================================
-- 6. suporteapp_rpc_weekly_reasons / suporteapp_rpc_weekly_handoff — só ganham filtros
-- (a lógica de dado já estava correta; só retornavam pouco/nada por baixa adesão de tags)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.suporteapp_rpc_weekly_reasons(
    p_period TEXT DEFAULT 'today',
    p_inbox_id INTEGER DEFAULT NULL,
    p_severity TEXT DEFAULT 'all',
    p_origin TEXT DEFAULT 'all'
)
RETURNS TABLE (
    reason_label TEXT,
    total_count BIGINT,
    volume_pct NUMERIC,
    median_wait_biz_minutes DOUBLE PRECISION,
    median_resolution_biz_minutes DOUBLE PRECISION
) AS $$
DECLARE
    v_start TIMESTAMPTZ;
BEGIN
    v_start := public.suporteapp_fn_get_period_start(p_period);

    RETURN QUERY
    WITH unnested_tags AS (
        SELECT
            t.id AS ticket_id,
            t.created_at,
            t.resolved_at,
            t.first_public_reply_at,
            COALESCE(
                (SELECT tag FROM unnest(t.current_labels) AS tag
                 JOIN public.suporteapp_label_taxonomy tax ON tax.label_name = tag AND tax.label_category = 'reason'
                 LIMIT 1),
                CASE WHEN array_length(t.current_labels, 1) > 1 THEN '(múltiplo)' ELSE '(ausente)' END
            ) AS reason_label,
            public.suporteapp_fn_calculate_business_minutes(t.created_at, t.first_public_reply_at) AS wait_biz_min,
            public.suporteapp_fn_calculate_business_minutes(t.created_at, t.resolved_at) AS resolution_biz_min
        FROM public.suporteapp_tickets t
        WHERE t.created_at >= v_start
          AND (p_inbox_id IS NULL OR t.chatwoot_inbox_id = p_inbox_id)
          AND (p_severity = 'all' OR t.priority = p_severity)
          AND (
                p_origin = 'all'
                OR (p_origin = 'bot' AND public.suporteapp_fn_is_bot_agent(t.current_agent_id))
                OR (p_origin = 'human' AND NOT public.suporteapp_fn_is_bot_agent(t.current_agent_id))
              )
    )
    SELECT
        ut.reason_label,
        COUNT(*),
        ROUND(COUNT(*)::numeric * 100.0 / SUM(COUNT(*)) OVER (), 2),
        PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY ut.wait_biz_min),
        PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY ut.resolution_biz_min)
    FROM unnested_tags ut
    GROUP BY ut.reason_label
    ORDER BY 2 DESC;
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION public.suporteapp_rpc_weekly_handoff(
    p_period TEXT DEFAULT 'today',
    p_inbox_id INTEGER DEFAULT NULL,
    p_severity TEXT DEFAULT 'all'
)
RETURNS TABLE (
    destiny_area TEXT,
    reason_label TEXT,
    total_tickets BIGINT,
    median_resolution_days DOUBLE PRECISION
) AS $$
DECLARE
    v_start TIMESTAMPTZ;
BEGIN
    v_start := public.suporteapp_fn_get_period_start(p_period);

    RETURN QUERY
    WITH handoff_tickets AS (
        SELECT
            t.id AS ticket_id,
            t.created_at,
            t.resolved_at,
            tax.destiny_area,
            tax.label_name AS reason_label,
            ROUND(EXTRACT(EPOCH FROM (t.resolved_at - t.created_at)) / 86400.0, 2) AS resolution_days
        FROM public.suporteapp_tickets t
        JOIN public.suporteapp_label_taxonomy tax ON tax.label_name = ANY(t.current_labels)
        WHERE tax.destiny_area IN ('engenharia', 'Gabi', 'Mariana')
          AND t.created_at >= v_start
          AND (p_inbox_id IS NULL OR t.chatwoot_inbox_id = p_inbox_id)
          AND (p_severity = 'all' OR t.priority = p_severity)
    )
    SELECT ht.destiny_area, ht.reason_label, COUNT(*), PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY ht.resolution_days)
    FROM handoff_tickets ht
    GROUP BY ht.destiny_area, ht.reason_label
    ORDER BY ht.destiny_area;
END;
$$ LANGUAGE plpgsql STABLE;
