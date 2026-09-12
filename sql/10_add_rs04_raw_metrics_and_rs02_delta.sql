-- Migration: 20260911_add_rs04_raw_metrics_and_rs02_delta.sql
-- Descrição: Fecha 2 lacunas de funcionalidade encontradas na revisão de UX/precisão do
-- Dashboard v3.0 (05 Revisão Funcionalidade UX Precisão.md):
--
-- 1. RS-04 "Espera Corrida" nunca calculava Média nem % na Meta (só Mediana/P90 existiam em
--    suporteapp_rpc_turn_metrics) — dashboard.js hardcodava 'N/D' para sempre nesses 2 campos.
--    Adiciona rs04_avg_turn1_raw_minutes e rs04_meta_10min_compliance_raw_pct.
--
-- 2. RS-02 "Delta Semanal" era uma coluna morta na UI (thead prometia, tbody sempre '—').
--    suporteapp_rpc_weekly_reasons ganha volume_delta_pct: compara a contagem de cada motivo no
--    período atual [v_start, v_end) contra a janela imediatamente anterior de mesma duração
--    [v_start - (v_end - v_start), v_start) — mesmos filtros de canal/severidade/agente/time/
--    origem aplicados a ambas as janelas. NULL quando o motivo não existia no período anterior
--    (não faz sentido inventar um "+infinito%" — a UI deve mostrar "novo" ou "—").
--
-- Ambas exigem DROP FUNCTION antes do CREATE OR REPLACE porque mudam a lista de colunas de
-- retorno (Postgres não permite CREATE OR REPLACE alterar o RETURNS TABLE de uma função já
-- existente, mesmo mantendo os parâmetros de entrada idênticos).

DROP FUNCTION IF EXISTS public.suporteapp_rpc_turn_metrics(text, integer, text, text, text, integer, integer, date, date);
DROP FUNCTION IF EXISTS public.suporteapp_rpc_weekly_reasons(text, integer, text, text, integer, integer, date, date);

-- =============================================================================
-- 1. suporteapp_rpc_turn_metrics — + rs04_avg_turn1_raw_minutes / rs04_meta_10min_compliance_raw_pct
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
          -- Guarda de qualidade de dado: exclui tickets com first_public_reply_at < created_at
          -- (dado corrompido do pipeline de ingestão — confirmado ao vivo 17/107 casos em 30d,
          -- pior caso -201 dias). Sem essa guarda, suporteapp_fn_calculate_business_minutes já
          -- retorna 0 para esses casos (tratando como "resposta instantânea", inflando
          -- d09_meta_10min_compliance_pct) e a média raw ficava negativa e sem sentido.
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
        (SELECT ROUND(AVG(turn1_biz_minutes), 2) FROM turn1_messages),
        (SELECT PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY turn1_biz_minutes) FROM turn1_messages),
        (SELECT PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY turn1_biz_minutes) FROM turn1_messages),
        (SELECT ROUND(COUNT(*) FILTER (WHERE turn1_biz_minutes <= 10 AND first_public_reply_at IS NOT NULL)::numeric * 100.0 /
                NULLIF(COUNT(*) FILTER (WHERE first_public_reply_at IS NOT NULL), 0), 2) FROM turn1_messages),
        (SELECT PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY turn1_raw_minutes) FROM turn1_messages),
        (SELECT PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY turn1_raw_minutes) FROM turn1_messages),
        (SELECT ROUND(AVG(turn1_raw_minutes), 2) FROM turn1_messages),
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

-- =============================================================================
-- 2. suporteapp_rpc_weekly_reasons — + volume_delta_pct (vs. janela anterior de mesma duração)
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
    volume_delta_pct NUMERIC,
    median_wait_biz_minutes DOUBLE PRECISION,
    median_resolution_biz_minutes DOUBLE PRECISION
) AS $$
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
    ),
    previous_tags AS (
        SELECT
            COALESCE(
                (SELECT tag FROM unnest(t.current_labels) AS tag
                 JOIN public.suporteapp_label_taxonomy tax ON tax.label_name = tag AND tax.label_category = 'reason'
                 LIMIT 1),
                CASE WHEN array_length(t.current_labels, 1) > 1 THEN '(múltiplo)' ELSE '(ausente)' END
            ) AS reason_label
        FROM public.suporteapp_tickets t
        WHERE t.created_at >= v_prev_start AND t.created_at < v_prev_end
          AND (p_inbox_id IS NULL OR t.chatwoot_inbox_id = p_inbox_id)
          AND (p_severity = 'all' OR t.priority = p_severity)
          AND (p_agent_id IS NULL OR t.current_agent_id = p_agent_id)
          AND (p_team_id IS NULL OR t.current_team_id = p_team_id)
          AND (
                p_origin = 'all'
                OR (p_origin = 'bot' AND public.suporteapp_fn_is_bot_agent(t.current_agent_id))
                OR (p_origin = 'human' AND NOT public.suporteapp_fn_is_bot_agent(t.current_agent_id))
              )
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
$$ LANGUAGE plpgsql STABLE;
