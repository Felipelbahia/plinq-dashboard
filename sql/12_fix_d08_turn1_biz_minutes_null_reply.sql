-- =============================================================================
-- FIX: D-08 Mediana e P90 de 1ª Resposta (suporteapp_rpc_turn_metrics)
-- =============================================================================
-- MOTIVO:
-- Chamados sem resposta humana (first_public_reply_at IS NULL) tinham seu tempo
-- comercial avaliado como 0 pela função suporteapp_fn_calculate_business_minutes.
-- Isso injetava dezenas de "0 min" no cálculo de PERCENTILE_CONT(0.50), puxando
-- a mediana (D-08) erroneamente para 0.
--
-- CORREÇÃO:
-- 1. turn1_biz_minutes passa a retornar NULL quando first_public_reply_at é NULL.
-- 2. As agregações de AVG, PERCENTILE_CONT(0.50) e PERCENTILE_CONT(0.90) aplicam
--    filtro explícito FILTER (WHERE first_public_reply_at IS NOT NULL),
--    garantindo que o tempo de primeira resposta reflita estritamente os chamados
--    que de fato receberam atendimento humano.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.suporteapp_rpc_turn_metrics(
    p_period TEXT DEFAULT 'today',
    p_date_start DATE DEFAULT NULL,
    p_date_end DATE DEFAULT NULL,
    p_inbox_ids INTEGER[] DEFAULT NULL,
    p_agent_ids INTEGER[] DEFAULT NULL,
    p_team_ids INTEGER[] DEFAULT NULL,
    p_severities TEXT[] DEFAULT NULL,
    p_origins TEXT[] DEFAULT NULL,
    p_taxonomies TEXT[] DEFAULT NULL,
    p_tags TEXT[] DEFAULT NULL,
    p_business_hours_filter TEXT DEFAULT 'all',
    p_weekend_filter TEXT DEFAULT 'all'
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
    rs04_avg_turn1_raw_minutes NUMERIC,
    rs04_meta_10min_compliance_raw_pct NUMERIC,
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
        SELECT t.* FROM public.suporteapp_fn_scope_tickets(
            p_inbox_ids, p_agent_ids, p_team_ids, p_severities, p_origins, p_taxonomies, p_tags,
            p_business_hours_filter, p_weekend_filter
        ) t
    ),
    turn1_messages AS (
        SELECT
            s.id AS ticket_id,
            s.created_at AS ticket_created_at,
            s.first_public_reply_at,
            s.priority,
            s.current_labels,
            CASE 
                WHEN s.first_public_reply_at IS NOT NULL 
                THEN public.suporteapp_fn_calculate_business_minutes(s.created_at, s.first_public_reply_at)
                ELSE NULL 
            END AS turn1_biz_minutes,
            ROUND(EXTRACT(EPOCH FROM (s.first_public_reply_at - s.created_at)) / 60.0, 2) AS turn1_raw_minutes,
            (public.suporteapp_fn_get_atendivel_start(s.created_at) <> s.created_at) AS created_outside_biz
        FROM scoped s
        WHERE s.created_at >= v_start AND s.created_at < v_end
          AND (s.first_public_reply_at IS NULL OR s.first_public_reply_at >= s.created_at)
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
        (SELECT ROUND(AVG(turn1_biz_minutes) FILTER (WHERE first_public_reply_at IS NOT NULL), 2) FROM turn1_messages),
        (SELECT PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY turn1_biz_minutes) FILTER (WHERE first_public_reply_at IS NOT NULL) FROM turn1_messages),
        (SELECT PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY turn1_biz_minutes) FILTER (WHERE first_public_reply_at IS NOT NULL) FROM turn1_messages),
        (SELECT ROUND(COUNT(*) FILTER (WHERE turn1_biz_minutes <= 10 AND first_public_reply_at IS NOT NULL)::numeric * 100.0 /
                NULLIF(COUNT(*) FILTER (WHERE first_public_reply_at IS NOT NULL), 0), 2) FROM turn1_messages),
        (SELECT PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY turn1_raw_minutes) FILTER (WHERE first_public_reply_at IS NOT NULL) FROM turn1_messages),
        (SELECT PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY turn1_raw_minutes) FILTER (WHERE first_public_reply_at IS NOT NULL) FROM turn1_messages),
        (SELECT ROUND(AVG(turn1_raw_minutes) FILTER (WHERE first_public_reply_at IS NOT NULL), 2) FROM turn1_messages),
        (SELECT ROUND(COUNT(*) FILTER (WHERE turn1_raw_minutes <= 10 AND first_public_reply_at IS NOT NULL)::numeric * 100.0 /
                NULLIF(COUNT(*) FILTER (WHERE first_public_reply_at IS NOT NULL), 0), 2) FROM turn1_messages),
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

GRANT EXECUTE ON FUNCTION public.suporteapp_rpc_turn_metrics TO anon, authenticated;
