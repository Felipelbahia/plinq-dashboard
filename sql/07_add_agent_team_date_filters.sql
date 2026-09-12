-- Migration: 20260911_add_agent_team_date_filters.sql
-- Descrição: Fecha o gap identificado na auditoria de filtros do Dashboard v3.0 — adiciona
-- filtro de Agente (current_agent_id), Time (current_team_id) e data customizada
-- (p_date_start/p_date_end) em TODAS as RPCs do dashboard, exceto onde não fizer sentido
-- semântico (ex: data em suporteapp_rpc_dashboard_queue, que é a fila "agora").
--
-- Também fecha o bug encontrado na mesma auditoria: suporteapp_rpc_recurrence_rate não
-- aceitava NENHUM parâmetro (janelas de 7d/30d fixas), então o filtro de período nunca surtia
-- efeito nesse card — agora aceita p_period/p_date_start/p_date_end como as demais.
--
-- Nova função helper: suporteapp_fn_resolve_period_range — resolve o intervalo [start, end)
-- tanto para os presets 'today'/'7d'/'30d' quanto para um intervalo de datas customizado
-- (quando p_date_start/p_date_end vêm preenchidos, sempre prevalecem sobre p_period). Criada do
-- zero (autocontida) porque suporteapp_fn_get_period_start está ativa no banco mas seu
-- CREATE FUNCTION não existe em nenhum arquivo do repositório (gap de sincronização
-- pré-existente, fora do escopo desta migração) — construir em cima dela seria depender de um
-- contrato que não está versionado.

-- =============================================================================
-- 0. Helper: resolve intervalo de período/data (com limite superior explícito)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.suporteapp_fn_resolve_period_range(
    p_period TEXT DEFAULT 'today',
    p_date_start DATE DEFAULT NULL,
    p_date_end DATE DEFAULT NULL
)
RETURNS TABLE (range_start TIMESTAMPTZ, range_end TIMESTAMPTZ) AS $$
DECLARE
    v_now TIMESTAMPTZ := NOW();
    v_today_start TIMESTAMPTZ := (date_trunc('day', v_now AT TIME ZONE 'America/Sao_Paulo')) AT TIME ZONE 'America/Sao_Paulo';
BEGIN
    IF p_date_start IS NOT NULL AND p_date_end IS NOT NULL THEN
        range_start := (p_date_start::timestamp) AT TIME ZONE 'America/Sao_Paulo';
        range_end := ((p_date_end + 1)::timestamp) AT TIME ZONE 'America/Sao_Paulo';
        RETURN NEXT;
        RETURN;
    END IF;

    range_end := v_now;
    CASE p_period
        WHEN '7d' THEN range_start := v_now - INTERVAL '7 days';
        WHEN '30d' THEN range_start := v_now - INTERVAL '30 days';
        ELSE range_start := v_today_start; -- 'today' (default)
    END CASE;
    RETURN NEXT;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION public.suporteapp_fn_resolve_period_range IS
  'Resolve [range_start, range_end) para os presets today/7d/30d ou para um intervalo de datas customizado (p_date_start/p_date_end, sempre prioritário sobre p_period). Usada por todas as RPCs do Dashboard, exceto suporteapp_rpc_dashboard_queue (Bloco A, tempo real, sem filtro de data).';

-- =============================================================================
-- 0b. Drop das assinaturas antigas antes de recriar com mais parâmetros
-- CREATE OR REPLACE FUNCTION só substitui de fato quando a lista de tipos de parâmetro é
-- idêntica; como esta migração ADICIONA parâmetros novos ao final (agente/time/data), o
-- Postgres trataria os CREATE OR REPLACE abaixo como uma SEGUNDA função sobrecarregada em vez
-- de substituir a antiga — deixando duas versões vivas e quebrando a resolução de RPC do
-- PostgREST ("could not choose the best candidate function"). Assinaturas confirmadas ao vivo
-- via pg_proc/pg_get_function_identity_arguments antes de escrever este DROP.
-- =============================================================================
DROP FUNCTION IF EXISTS public.suporteapp_rpc_dashboard_queue(integer, text, text, text);
DROP FUNCTION IF EXISTS public.suporteapp_rpc_turn_metrics(text, integer, text, text, text);
DROP FUNCTION IF EXISTS public.suporteapp_rpc_daily_shift_metrics(text, integer, text, text, text);
DROP FUNCTION IF EXISTS public.suporteapp_rpc_bot_metrics(text, integer, text);
DROP FUNCTION IF EXISTS public.suporteapp_rpc_avoidable_vs_structural(text, integer, text);
DROP FUNCTION IF EXISTS public.suporteapp_rpc_weekly_reasons(text, integer, text, text);
DROP FUNCTION IF EXISTS public.suporteapp_rpc_weekly_handoff(text, integer, text);
DROP FUNCTION IF EXISTS public.suporteapp_rpc_weekly_heatmap(text, integer, text);
DROP FUNCTION IF EXISTS public.suporteapp_rpc_reason_severity_matrix(text, integer);
DROP FUNCTION IF EXISTS public.suporteapp_rpc_resolution_breakdown(text, integer);
DROP FUNCTION IF EXISTS public.suporteapp_rpc_reopen_count(text);
DROP FUNCTION IF EXISTS public.suporteapp_rpc_carried_stock(text);
DROP FUNCTION IF EXISTS public.suporteapp_rpc_alarm_panel(text);
DROP FUNCTION IF EXISTS public.suporteapp_rpc_first_contact_resolution(text);
DROP FUNCTION IF EXISTS public.suporteapp_rpc_recurrence_rate();
DROP FUNCTION IF EXISTS public.suporteapp_rpc_contest_and_false_negative(text);
DROP FUNCTION IF EXISTS public.suporteapp_rpc_bot_handover_top_subjects(text, integer);

-- =============================================================================
-- 1. suporteapp_rpc_dashboard_queue — Bloco A (tempo real): só ganha agente/time, sem data
-- =============================================================================
CREATE OR REPLACE FUNCTION public.suporteapp_rpc_dashboard_queue(
    p_inbox_id INTEGER DEFAULT NULL,
    p_severity TEXT DEFAULT 'all',
    p_origin TEXT DEFAULT 'all',
    p_taxonomy TEXT DEFAULT 'all',
    p_agent_id INTEGER DEFAULT NULL,
    p_team_id INTEGER DEFAULT NULL
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
          AND (p_agent_id IS NULL OR t.current_agent_id = p_agent_id)
          AND (p_team_id IS NULL OR t.current_team_id = p_team_id)
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
-- 2. suporteapp_rpc_turn_metrics — + p_agent_id/p_team_id/p_date_start/p_date_end
-- =============================================================================
CREATE OR REPLACE FUNCTION public.suporteapp_rpc_turn_metrics(
    p_period TEXT DEFAULT 'today',
    p_inbox_id INTEGER DEFAULT NULL,
    p_severity TEXT DEFAULT 'all',
    p_origin TEXT DEFAULT 'all',
    p_taxonomy TEXT DEFAULT 'all',
    p_agent_id INTEGER DEFAULT NULL,
    p_team_id INTEGER DEFAULT NULL,
    p_date_start DATE DEFAULT NULL,
    p_date_end DATE DEFAULT NULL
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
    v_end TIMESTAMPTZ;
BEGIN
    SELECT range_start, range_end INTO v_start, v_end
    FROM public.suporteapp_fn_resolve_period_range(p_period, p_date_start, p_date_end);

    RETURN QUERY
    WITH scoped AS (
        SELECT t.*
        FROM public.suporteapp_tickets t
        WHERE (p_inbox_id IS NULL OR t.chatwoot_inbox_id = p_inbox_id)
          AND (p_severity = 'all' OR t.priority = p_severity)
          AND (p_agent_id IS NULL OR t.current_agent_id = p_agent_id)
          AND (p_team_id IS NULL OR t.current_team_id = p_team_id)
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
        WHERE s.created_at >= v_start AND s.created_at < v_end
    ),
    resolved_in_period AS (
        SELECT s.id, s.resolution_type
        FROM scoped s
        WHERE s.resolved_at >= v_start AND s.resolved_at < v_end
    ),
    turn2_pairs AS (
        SELECT
            rp.ticket_id,
            public.suporteapp_fn_calculate_business_minutes(rp.customer_message_at, rp.agent_response_at) AS turn_biz_minutes,
            ROW_NUMBER() OVER (PARTITION BY rp.ticket_id ORDER BY rp.customer_message_at) AS rn
        FROM public.suporteapp_v_response_pairs rp
        JOIN scoped s ON s.id = rp.ticket_id
        WHERE rp.customer_message_at >= v_start AND rp.customer_message_at < v_end
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
-- 3. suporteapp_rpc_daily_shift_metrics — + p_agent_id/p_team_id/p_date_start/p_date_end
-- =============================================================================
CREATE OR REPLACE FUNCTION public.suporteapp_rpc_daily_shift_metrics(
    p_period TEXT DEFAULT 'today',
    p_inbox_id INTEGER DEFAULT NULL,
    p_severity TEXT DEFAULT 'all',
    p_origin TEXT DEFAULT 'all',
    p_taxonomy TEXT DEFAULT 'all',
    p_agent_id INTEGER DEFAULT NULL,
    p_team_id INTEGER DEFAULT NULL,
    p_date_start DATE DEFAULT NULL,
    p_date_end DATE DEFAULT NULL
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
        JOIN public.suporteapp_tickets t ON t.id = m.ticket_id
        WHERE (p_inbox_id IS NULL OR t.chatwoot_inbox_id = p_inbox_id)
          AND (p_severity = 'all' OR t.priority = p_severity)
          AND (p_agent_id IS NULL OR t.current_agent_id = p_agent_id)
          AND (p_team_id IS NULL OR t.current_team_id = p_team_id)
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
        SELECT t.id, t.resolved_at
        FROM public.suporteapp_tickets t
        WHERE (p_inbox_id IS NULL OR t.chatwoot_inbox_id = p_inbox_id)
          AND (p_severity = 'all' OR t.priority = p_severity)
          AND (p_agent_id IS NULL OR t.current_agent_id = p_agent_id)
          AND (p_team_id IS NULL OR t.current_team_id = p_team_id)
          AND t.created_at < v_today_9am
          AND (t.status != 'resolved' OR t.resolved_at >= v_today_9am)
          AND (t.last_customer_message_at IS NOT NULL
               AND (t.last_agent_message_at IS NULL OR t.last_customer_message_at > t.last_agent_message_at)
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
$$ LANGUAGE plpgsql STABLE;

-- =============================================================================
-- 4. suporteapp_rpc_bot_metrics — + p_origin dropped (sempre bot), + agente/time/data
-- =============================================================================
CREATE OR REPLACE FUNCTION public.suporteapp_rpc_bot_metrics(
    p_period TEXT DEFAULT 'today',
    p_inbox_id INTEGER DEFAULT NULL,
    p_severity TEXT DEFAULT 'all',
    p_agent_id INTEGER DEFAULT NULL,
    p_team_id INTEGER DEFAULT NULL,
    p_date_start DATE DEFAULT NULL,
    p_date_end DATE DEFAULT NULL
)
RETURNS TABLE (
    bot_total_conversations BIGINT,
    bot_containment_pct NUMERIC,
    bot_handover_pct NUMERIC,
    bot_inherited_queue BIGINT
) AS $$
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
        SELECT DISTINCT t.id, t.status, t.created_at, t.current_agent_id
        FROM public.suporteapp_tickets t
        JOIN public.suporteapp_messages m ON m.ticket_id = t.id
        WHERE (p_inbox_id IS NULL OR t.chatwoot_inbox_id = p_inbox_id)
          AND (p_severity = 'all' OR t.priority = p_severity)
          AND (p_agent_id IS NULL OR t.current_agent_id = p_agent_id)
          AND (p_team_id IS NULL OR t.current_team_id = p_team_id)
          AND t.created_at >= v_start AND t.created_at < v_end
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
-- 5. suporteapp_rpc_avoidable_vs_structural — + agente/time/data
-- =============================================================================
CREATE OR REPLACE FUNCTION public.suporteapp_rpc_avoidable_vs_structural(
    p_period TEXT DEFAULT 'today',
    p_inbox_id INTEGER DEFAULT NULL,
    p_severity TEXT DEFAULT 'all',
    p_agent_id INTEGER DEFAULT NULL,
    p_team_id INTEGER DEFAULT NULL,
    p_date_start DATE DEFAULT NULL,
    p_date_end DATE DEFAULT NULL
)
RETURNS TABLE (
    avoidable_pct NUMERIC,
    structural_pct NUMERIC,
    avoidable_hours NUMERIC,
    structural_hours NUMERIC
) AS $$
DECLARE
    v_start TIMESTAMPTZ;
    v_end TIMESTAMPTZ;
BEGIN
    SELECT range_start, range_end INTO v_start, v_end
    FROM public.suporteapp_fn_resolve_period_range(p_period, p_date_start, p_date_end);

    RETURN QUERY
    WITH scoped AS (
        SELECT t.created_at, t.first_public_reply_at,
               public.suporteapp_fn_get_atendivel_start(t.created_at) AS atendivel_start
        FROM public.suporteapp_tickets t
        WHERE t.created_at >= v_start AND t.created_at < v_end
          AND t.first_public_reply_at IS NOT NULL
          AND (p_inbox_id IS NULL OR t.chatwoot_inbox_id = p_inbox_id)
          AND (p_severity = 'all' OR t.priority = p_severity)
          AND (p_agent_id IS NULL OR t.current_agent_id = p_agent_id)
          AND (p_team_id IS NULL OR t.current_team_id = p_team_id)
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
-- 6. suporteapp_rpc_weekly_reasons / suporteapp_rpc_weekly_handoff — + agente/time/data
-- =============================================================================
CREATE OR REPLACE FUNCTION public.suporteapp_rpc_weekly_reasons(
    p_period TEXT DEFAULT 'today',
    p_inbox_id INTEGER DEFAULT NULL,
    p_severity TEXT DEFAULT 'all',
    p_origin TEXT DEFAULT 'all',
    p_agent_id INTEGER DEFAULT NULL,
    p_team_id INTEGER DEFAULT NULL,
    p_date_start DATE DEFAULT NULL,
    p_date_end DATE DEFAULT NULL
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
    v_end TIMESTAMPTZ;
BEGIN
    SELECT range_start, range_end INTO v_start, v_end
    FROM public.suporteapp_fn_resolve_period_range(p_period, p_date_start, p_date_end);

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
        WHERE t.created_at >= v_start AND t.created_at < v_end
          AND (p_inbox_id IS NULL OR t.chatwoot_inbox_id = p_inbox_id)
          AND (p_severity = 'all' OR t.priority = p_severity)
          AND (p_agent_id IS NULL OR t.current_agent_id = p_agent_id)
          AND (p_team_id IS NULL OR t.current_team_id = p_team_id)
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
    p_severity TEXT DEFAULT 'all',
    p_agent_id INTEGER DEFAULT NULL,
    p_team_id INTEGER DEFAULT NULL,
    p_date_start DATE DEFAULT NULL,
    p_date_end DATE DEFAULT NULL
)
RETURNS TABLE (
    destiny_area TEXT,
    reason_label TEXT,
    total_tickets BIGINT,
    median_resolution_days DOUBLE PRECISION
) AS $$
DECLARE
    v_start TIMESTAMPTZ;
    v_end TIMESTAMPTZ;
BEGIN
    SELECT range_start, range_end INTO v_start, v_end
    FROM public.suporteapp_fn_resolve_period_range(p_period, p_date_start, p_date_end);

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
          AND t.created_at >= v_start AND t.created_at < v_end
          AND (p_inbox_id IS NULL OR t.chatwoot_inbox_id = p_inbox_id)
          AND (p_severity = 'all' OR t.priority = p_severity)
          AND (p_agent_id IS NULL OR t.current_agent_id = p_agent_id)
          AND (p_team_id IS NULL OR t.current_team_id = p_team_id)
    )
    SELECT ht.destiny_area, ht.reason_label, COUNT(*), PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY ht.resolution_days)
    FROM handoff_tickets ht
    GROUP BY ht.destiny_area, ht.reason_label
    ORDER BY ht.destiny_area;
END;
$$ LANGUAGE plpgsql STABLE;

-- =============================================================================
-- 7. suporteapp_rpc_weekly_heatmap (RS-01) — + agente/time/data
-- =============================================================================
CREATE OR REPLACE FUNCTION public.suporteapp_rpc_weekly_heatmap(
    p_period TEXT DEFAULT '7d',
    p_inbox_id INTEGER DEFAULT NULL,
    p_severity TEXT DEFAULT 'all',
    p_agent_id INTEGER DEFAULT NULL,
    p_team_id INTEGER DEFAULT NULL,
    p_date_start DATE DEFAULT NULL,
    p_date_end DATE DEFAULT NULL
)
RETURNS TABLE (
    isodow INTEGER,
    hour_bucket TEXT,
    total_count BIGINT
) AS $$
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
        FROM public.suporteapp_tickets t
        WHERE t.created_at >= v_start AND t.created_at < v_end
          AND (p_inbox_id IS NULL OR t.chatwoot_inbox_id = p_inbox_id)
          AND (p_severity = 'all' OR t.priority = p_severity)
          AND (p_agent_id IS NULL OR t.current_agent_id = p_agent_id)
          AND (p_team_id IS NULL OR t.current_team_id = p_team_id)
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
$$ LANGUAGE plpgsql STABLE;

-- =============================================================================
-- 8. suporteapp_rpc_reason_severity_matrix (RS-03) — + severidade/agente/time/data
-- =============================================================================
CREATE OR REPLACE FUNCTION public.suporteapp_rpc_reason_severity_matrix(
    p_period TEXT DEFAULT '7d',
    p_inbox_id INTEGER DEFAULT NULL,
    p_severity TEXT DEFAULT 'all',
    p_agent_id INTEGER DEFAULT NULL,
    p_team_id INTEGER DEFAULT NULL,
    p_date_start DATE DEFAULT NULL,
    p_date_end DATE DEFAULT NULL
)
RETURNS TABLE (
    reason_label TEXT,
    p0_count BIGINT,
    p1_count BIGINT,
    p2_p3_count BIGINT,
    total_count BIGINT
) AS $$
DECLARE
    v_start TIMESTAMPTZ;
    v_end TIMESTAMPTZ;
BEGIN
    SELECT range_start, range_end INTO v_start, v_end
    FROM public.suporteapp_fn_resolve_period_range(p_period, p_date_start, p_date_end);

    RETURN QUERY
    WITH tagged AS (
        SELECT
            t.priority AS t_priority,
            (SELECT tag FROM unnest(t.current_labels) AS tag
             JOIN public.suporteapp_label_taxonomy tax ON tax.label_name = tag AND tax.label_category = 'reason'
             LIMIT 1) AS t_reason_label
        FROM public.suporteapp_tickets t
        WHERE t.created_at >= v_start AND t.created_at < v_end
          AND (p_inbox_id IS NULL OR t.chatwoot_inbox_id = p_inbox_id)
          AND (p_severity = 'all' OR t.priority = p_severity)
          AND (p_agent_id IS NULL OR t.current_agent_id = p_agent_id)
          AND (p_team_id IS NULL OR t.current_team_id = p_team_id)
          AND t.current_labels IS NOT NULL
    )
    SELECT
        t_reason_label,
        COUNT(*) FILTER (WHERE t_priority = 'P0'),
        COUNT(*) FILTER (WHERE t_priority = 'P1'),
        COUNT(*) FILTER (WHERE t_priority IN ('P2','P3')),
        COUNT(*)
    FROM tagged
    WHERE t_reason_label IS NOT NULL
    GROUP BY t_reason_label
    ORDER BY COUNT(*) DESC;
END;
$$ LANGUAGE plpgsql STABLE;

-- =============================================================================
-- 9. suporteapp_rpc_resolution_breakdown / suporteapp_rpc_reopen_count (RS-05)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.suporteapp_rpc_resolution_breakdown(
    p_period TEXT DEFAULT '7d',
    p_inbox_id INTEGER DEFAULT NULL,
    p_severity TEXT DEFAULT 'all',
    p_agent_id INTEGER DEFAULT NULL,
    p_team_id INTEGER DEFAULT NULL,
    p_date_start DATE DEFAULT NULL,
    p_date_end DATE DEFAULT NULL
)
RETURNS TABLE (
    resolution_type TEXT,
    total_count BIGINT,
    pct NUMERIC,
    median_hours NUMERIC,
    p90_hours NUMERIC
) AS $$
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
        FROM public.suporteapp_tickets t
        WHERE t.status = 'resolved'
          AND t.resolved_at >= v_start AND t.resolved_at < v_end
          AND (p_inbox_id IS NULL OR t.chatwoot_inbox_id = p_inbox_id)
          AND (p_severity = 'all' OR t.priority = p_severity)
          AND (p_agent_id IS NULL OR t.current_agent_id = p_agent_id)
          AND (p_team_id IS NULL OR t.current_team_id = p_team_id)
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
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION public.suporteapp_rpc_reopen_count(
    p_period TEXT DEFAULT '7d',
    p_inbox_id INTEGER DEFAULT NULL,
    p_severity TEXT DEFAULT 'all',
    p_agent_id INTEGER DEFAULT NULL,
    p_team_id INTEGER DEFAULT NULL,
    p_date_start DATE DEFAULT NULL,
    p_date_end DATE DEFAULT NULL
)
RETURNS BIGINT AS $$
DECLARE
    v_start TIMESTAMPTZ;
    v_end TIMESTAMPTZ;
BEGIN
    SELECT range_start, range_end INTO v_start, v_end
    FROM public.suporteapp_fn_resolve_period_range(p_period, p_date_start, p_date_end);

    RETURN (
        SELECT COUNT(*) FROM public.suporteapp_tickets t
        WHERE t.reopened_count > 0
          AND t.last_reopened_at >= v_start AND t.last_reopened_at < v_end
          AND (p_inbox_id IS NULL OR t.chatwoot_inbox_id = p_inbox_id)
          AND (p_severity = 'all' OR t.priority = p_severity)
          AND (p_agent_id IS NULL OR t.current_agent_id = p_agent_id)
          AND (p_team_id IS NULL OR t.current_team_id = p_team_id)
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- =============================================================================
-- 10. suporteapp_rpc_carried_stock (RS-07) — + canal/severidade/agente/time/data
-- =============================================================================
CREATE OR REPLACE FUNCTION public.suporteapp_rpc_carried_stock(
    p_period TEXT DEFAULT '7d',
    p_inbox_id INTEGER DEFAULT NULL,
    p_severity TEXT DEFAULT 'all',
    p_agent_id INTEGER DEFAULT NULL,
    p_team_id INTEGER DEFAULT NULL,
    p_date_start DATE DEFAULT NULL,
    p_date_end DATE DEFAULT NULL
)
RETURNS TABLE (
    opening_stock BIGINT,
    created_in_period BIGINT,
    resolved_in_period BIGINT,
    carried_stock BIGINT,
    carried_over_7d BIGINT
) AS $$
DECLARE
    v_start TIMESTAMPTZ;
    v_end TIMESTAMPTZ;
BEGIN
    SELECT range_start, range_end INTO v_start, v_end
    FROM public.suporteapp_fn_resolve_period_range(p_period, p_date_start, p_date_end);

    RETURN QUERY
    WITH scoped AS (
        SELECT t.* FROM public.suporteapp_tickets t
        WHERE (p_inbox_id IS NULL OR t.chatwoot_inbox_id = p_inbox_id)
          AND (p_severity = 'all' OR t.priority = p_severity)
          AND (p_agent_id IS NULL OR t.current_agent_id = p_agent_id)
          AND (p_team_id IS NULL OR t.current_team_id = p_team_id)
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
        SELECT t.id, t.created_at FROM scoped t
        WHERE t.status != 'resolved'
    )
    SELECT
        (SELECT n FROM opening),
        (SELECT n FROM created),
        (SELECT n FROM resolved),
        (SELECT COUNT(*) FROM carried),
        (SELECT COUNT(*) FROM carried WHERE created_at < NOW() - INTERVAL '7 days');
END;
$$ LANGUAGE plpgsql STABLE;

-- =============================================================================
-- 11. suporteapp_rpc_alarm_panel (RS-08) — + canal/severidade/agente/time/data
-- =============================================================================
CREATE OR REPLACE FUNCTION public.suporteapp_rpc_alarm_panel(
    p_period TEXT DEFAULT '7d',
    p_inbox_id INTEGER DEFAULT NULL,
    p_severity TEXT DEFAULT 'all',
    p_agent_id INTEGER DEFAULT NULL,
    p_team_id INTEGER DEFAULT NULL,
    p_date_start DATE DEFAULT NULL,
    p_date_end DATE DEFAULT NULL
)
RETURNS TABLE (
    sem_atendimento BIGINT,
    red_estourado_janela BIGINT,
    red_estourado_fora BIGINT,
    acima_72h BIGINT
) AS $$
DECLARE
    v_start TIMESTAMPTZ;
    v_end TIMESTAMPTZ;
BEGIN
    SELECT range_start, range_end INTO v_start, v_end
    FROM public.suporteapp_fn_resolve_period_range(p_period, p_date_start, p_date_end);

    RETURN QUERY
    WITH scoped AS (
        SELECT t.* FROM public.suporteapp_tickets t
        WHERE (p_inbox_id IS NULL OR t.chatwoot_inbox_id = p_inbox_id)
          AND (p_severity = 'all' OR t.priority = p_severity)
          AND (p_agent_id IS NULL OR t.current_agent_id = p_agent_id)
          AND (p_team_id IS NULL OR t.current_team_id = p_team_id)
    )
    SELECT
        (SELECT COUNT(*) FROM scoped t
            WHERE t.status = 'open' AND t.last_agent_message_at IS NULL),
        (SELECT COUNT(*) FROM scoped t
            WHERE t.status = 'open' AND (t.priority = 'P0' OR 'sev-red' = ANY(t.current_labels))
              AND (public.suporteapp_fn_get_atendivel_start(t.created_at) = t.created_at)
              AND EXTRACT(EPOCH FROM (NOW() - COALESCE(t.last_customer_message_at, t.created_at))) / 60.0 > 10),
        (SELECT COUNT(*) FROM scoped t
            WHERE t.created_at >= v_start AND t.created_at < v_end AND (t.priority = 'P0' OR 'sev-red' = ANY(t.current_labels))
              AND (public.suporteapp_fn_get_atendivel_start(t.created_at) <> t.created_at)),
        (SELECT COUNT(*) FROM scoped t
            WHERE t.status = 'open'
              AND public.suporteapp_fn_calculate_business_minutes(COALESCE(t.last_customer_message_at, t.created_at), NOW()) >= 4320);
END;
$$ LANGUAGE plpgsql STABLE;

-- =============================================================================
-- 12. suporteapp_rpc_first_contact_resolution (RS-10) — + canal/severidade/agente/time/data
-- =============================================================================
CREATE OR REPLACE FUNCTION public.suporteapp_rpc_first_contact_resolution(
    p_period TEXT DEFAULT '7d',
    p_inbox_id INTEGER DEFAULT NULL,
    p_severity TEXT DEFAULT 'all',
    p_agent_id INTEGER DEFAULT NULL,
    p_team_id INTEGER DEFAULT NULL,
    p_date_start DATE DEFAULT NULL,
    p_date_end DATE DEFAULT NULL
)
RETURNS TABLE (
    reason_label TEXT,
    fcr_pct NUMERIC,
    total_resolved BIGINT
) AS $$
DECLARE
    v_start TIMESTAMPTZ;
    v_end TIMESTAMPTZ;
BEGIN
    SELECT range_start, range_end INTO v_start, v_end
    FROM public.suporteapp_fn_resolve_period_range(p_period, p_date_start, p_date_end);

    RETURN QUERY
    WITH outgoing_counts AS (
        SELECT m.ticket_id AS oc_ticket_id, COUNT(*) AS n_outgoing
        FROM public.suporteapp_messages m
        WHERE m.message_type = 'outgoing' AND m.is_private = false
        GROUP BY m.ticket_id
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
        FROM public.suporteapp_tickets t
        LEFT JOIN outgoing_counts oc ON oc.oc_ticket_id = t.id
        WHERE t.status = 'resolved' AND t.resolved_at >= v_start AND t.resolved_at < v_end
          AND (p_inbox_id IS NULL OR t.chatwoot_inbox_id = p_inbox_id)
          AND (p_severity = 'all' OR t.priority = p_severity)
          AND (p_agent_id IS NULL OR t.current_agent_id = p_agent_id)
          AND (p_team_id IS NULL OR t.current_team_id = p_team_id)
    )
    SELECT r_reason_label, ROUND(COUNT(*) FILTER (WHERE is_fcr)::numeric * 100.0 / NULLIF(COUNT(*), 0), 2), COUNT(*)
    FROM resolved
    GROUP BY r_reason_label
    ORDER BY 3 DESC;
END;
$$ LANGUAGE plpgsql STABLE;

-- =============================================================================
-- 13. suporteapp_rpc_recurrence_rate (RS-11) — BUG FIX: agora aceita período/data
-- (antes não recebia NENHUM parâmetro; janelas 7d/30d eram fixas e o filtro de período da UI
-- nunca surtia efeito nesse card)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.suporteapp_rpc_recurrence_rate(
    p_inbox_id INTEGER DEFAULT NULL,
    p_severity TEXT DEFAULT 'all',
    p_agent_id INTEGER DEFAULT NULL,
    p_team_id INTEGER DEFAULT NULL,
    p_date_end DATE DEFAULT NULL
)
RETURNS TABLE (
    recurrence_7d_pct NUMERIC,
    recurrence_30d_pct NUMERIC,
    top_recurring_reason TEXT
) AS $$
DECLARE
    v_end TIMESTAMPTZ := COALESCE(((p_date_end + 1)::timestamp) AT TIME ZONE 'America/Sao_Paulo', NOW());
BEGIN
    RETURN QUERY
    WITH scoped AS (
        SELECT t.* FROM public.suporteapp_tickets t
        WHERE (p_inbox_id IS NULL OR t.chatwoot_inbox_id = p_inbox_id)
          AND (p_severity = 'all' OR t.priority = p_severity)
          AND (p_agent_id IS NULL OR t.current_agent_id = p_agent_id)
          AND (p_team_id IS NULL OR t.current_team_id = p_team_id)
    ),
    last_7d AS (
        SELECT customer_email, COUNT(*) AS n
        FROM scoped
        WHERE created_at >= v_end - INTERVAL '7 days' AND created_at < v_end AND customer_email IS NOT NULL
        GROUP BY customer_email
    ),
    last_30d AS (
        SELECT customer_email, COUNT(*) AS n
        FROM scoped
        WHERE created_at >= v_end - INTERVAL '30 days' AND created_at < v_end AND customer_email IS NOT NULL
        GROUP BY customer_email
    ),
    top_reason AS (
        SELECT tag, COUNT(*) AS n
        FROM scoped t, unnest(t.current_labels) AS tag
        JOIN public.suporteapp_label_taxonomy tax ON tax.label_name = tag AND tax.label_category = 'reason'
        WHERE t.customer_email IN (SELECT customer_email FROM last_30d WHERE n > 1)
        GROUP BY tag ORDER BY n DESC LIMIT 1
    )
    SELECT
        ROUND((SELECT COUNT(*) FROM last_7d WHERE n > 1)::numeric * 100.0 / NULLIF((SELECT COUNT(*) FROM last_7d), 0), 2),
        ROUND((SELECT COUNT(*) FROM last_30d WHERE n > 1)::numeric * 100.0 / NULLIF((SELECT COUNT(*) FROM last_30d), 0), 2),
        (SELECT tag FROM top_reason);
END;
$$ LANGUAGE plpgsql STABLE;

-- =============================================================================
-- 14. suporteapp_rpc_contest_and_false_negative (RS-12) — + canal/severidade/agente/time/data
-- =============================================================================
CREATE OR REPLACE FUNCTION public.suporteapp_rpc_contest_and_false_negative(
    p_period TEXT DEFAULT '7d',
    p_inbox_id INTEGER DEFAULT NULL,
    p_severity TEXT DEFAULT 'all',
    p_agent_id INTEGER DEFAULT NULL,
    p_team_id INTEGER DEFAULT NULL,
    p_date_start DATE DEFAULT NULL,
    p_date_end DATE DEFAULT NULL
)
RETURNS TABLE (
    contested_count BIGINT,
    false_negative_count BIGINT
) AS $$
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
    FROM public.suporteapp_tickets t
    WHERE t.created_at >= v_start AND t.created_at < v_end
      AND (p_inbox_id IS NULL OR t.chatwoot_inbox_id = p_inbox_id)
      AND (p_severity = 'all' OR t.priority = p_severity)
      AND (p_agent_id IS NULL OR t.current_agent_id = p_agent_id)
      AND (p_team_id IS NULL OR t.current_team_id = p_team_id);
END;
$$ LANGUAGE plpgsql STABLE;

-- =============================================================================
-- 15. suporteapp_rpc_bot_handover_top_subjects (RS-13) — + canal/agente/time/data
-- =============================================================================
CREATE OR REPLACE FUNCTION public.suporteapp_rpc_bot_handover_top_subjects(
    p_period TEXT DEFAULT '7d',
    p_limit INTEGER DEFAULT 5,
    p_inbox_id INTEGER DEFAULT NULL,
    p_severity TEXT DEFAULT 'all',
    p_agent_id INTEGER DEFAULT NULL,
    p_team_id INTEGER DEFAULT NULL,
    p_date_start DATE DEFAULT NULL,
    p_date_end DATE DEFAULT NULL
)
RETURNS TABLE (
    reason_label TEXT,
    handover_count BIGINT
) AS $$
DECLARE
    v_start TIMESTAMPTZ;
    v_end TIMESTAMPTZ;
BEGIN
    SELECT range_start, range_end INTO v_start, v_end
    FROM public.suporteapp_fn_resolve_period_range(p_period, p_date_start, p_date_end);

    RETURN QUERY
    WITH bot_transfers AS (
        SELECT DISTINCT tr.ticket_id
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
    JOIN public.suporteapp_tickets t ON t.id = bt.ticket_id
    WHERE (p_inbox_id IS NULL OR t.chatwoot_inbox_id = p_inbox_id)
      AND (p_severity = 'all' OR t.priority = p_severity)
      AND (p_agent_id IS NULL OR t.current_agent_id = p_agent_id)
      AND (p_team_id IS NULL OR t.current_team_id = p_team_id)
    GROUP BY reason_label
    ORDER BY 2 DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE;
