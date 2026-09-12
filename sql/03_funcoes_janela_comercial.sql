-- ==============================================================================
-- CHAMADOS APP · DASHBOARD DE SUPORTE V3.0
-- Funções PL/pgSQL para Cálculo de Janela Comercial (Horário de Brasília UTC-3)
-- ==============================================================================

-- 1. Função: Momento Atendível (Dicionário · Item 3)
-- Retorna o primeiro instante em que uma pessoa poderia responder (09:00-18:00 BRT em dia útil)
CREATE OR REPLACE FUNCTION public.suporteapp_fn_get_atendivel_start(p_ts TIMESTAMPTZ)
RETURNS TIMESTAMPTZ AS $$
DECLARE
    v_local_ts TIMESTAMP;
    v_date DATE;
    v_time TIME;
    v_is_biz BOOLEAN;
    v_start_time TIME;
    v_end_time TIME;
    v_next_biz_date DATE;
BEGIN
    IF p_ts IS NULL THEN RETURN NULL; END IF;

    -- Converte timestamp para fuso de Brasília
    v_local_ts := p_ts AT TIME ZONE 'America/Sao_Paulo';
    v_date := v_local_ts::DATE;
    v_time := v_local_ts::TIME;

    -- Verifica se o dia é útil no calendário
    SELECT is_business_day, start_time, end_time
    INTO v_is_biz, v_start_time, v_end_time
    FROM public.suporteapp_calendar
    WHERE calendar_date = v_date;

    IF v_is_biz IS NULL THEN v_is_biz := (EXTRACT(ISODOW FROM v_date) NOT IN (6,7)); v_start_time := '09:00:00'; v_end_time := '18:00:00'; END IF;

    -- Se chegou dentro da janela comercial
    IF v_is_biz AND v_time >= v_start_time AND v_time < v_end_time THEN
        RETURN p_ts;
    END IF;

    -- Se chegou no mesmo dia útil mas antes das 9h
    IF v_is_biz AND v_time < v_start_time THEN
        RETURN (v_date || ' ' || v_start_time)::TIMESTAMP AT TIME ZONE 'America/Sao_Paulo';
    END IF;

    -- Caso contrário (após 18h ou em dia não útil/feriado), busca a próxima abertura de janela
    SELECT calendar_date INTO v_next_biz_date
    FROM public.suporteapp_calendar
    WHERE calendar_date > v_date AND is_business_day = true
    ORDER BY calendar_date ASC
    LIMIT 1;

    IF v_next_biz_date IS NULL THEN
        RETURN (v_date + INTERVAL '1 day' + v_start_time)::TIMESTAMP AT TIME ZONE 'America/Sao_Paulo';
    END IF;

    RETURN (v_next_biz_date || ' 09:00:00')::TIMESTAMP AT TIME ZONE 'America/Sao_Paulo';
END;
$$ LANGUAGE plpgsql STABLE;

-- 2. Função: Cálculo de Espera Atendível em Minutos (Dicionário · Item 4)
-- Calcula minutos decorridos entre p_start_ts e p_end_ts contando apenas horas úteis (09:00-18:00 BRT)
CREATE OR REPLACE FUNCTION public.suporteapp_fn_calculate_business_minutes(
    p_start_ts TIMESTAMPTZ,
    p_end_ts TIMESTAMPTZ
)
RETURNS NUMERIC AS $$
DECLARE
    v_effective_start TIMESTAMPTZ;
    v_start_local TIMESTAMP;
    v_end_local TIMESTAMP;
    v_curr_date DATE;
    v_end_date DATE;
    v_total_seconds NUMERIC := 0;
    v_day_start TIMESTAMP;
    v_day_end TIMESTAMP;
    v_overlap_start TIMESTAMP;
    v_overlap_end TIMESTAMP;
    v_is_biz BOOLEAN;
BEGIN
    IF p_start_ts IS NULL OR p_end_ts IS NULL OR p_end_ts <= p_start_ts THEN
        RETURN 0;
    END IF;

    -- Ajusta o início para o momento atendível
    v_effective_start := public.suporteapp_fn_get_atendivel_start(p_start_ts);
    IF p_end_ts <= v_effective_start THEN
        RETURN 0;
    END IF;

    v_start_local := v_effective_start AT TIME ZONE 'America/Sao_Paulo';
    v_end_local := p_end_ts AT TIME ZONE 'America/Sao_Paulo';

    v_curr_date := v_start_local::DATE;
    v_end_date := v_end_local::DATE;

    WHILE v_curr_date <= v_end_date LOOP
        SELECT is_business_day INTO v_is_biz
        FROM public.suporteapp_calendar
        WHERE calendar_date = v_curr_date;

        IF v_is_biz IS NULL THEN
            v_is_biz := (EXTRACT(ISODOW FROM v_curr_date) NOT IN (6,7));
        END IF;

        IF v_is_biz THEN
            v_day_start := (v_curr_date || ' 09:00:00')::TIMESTAMP;
            v_day_end := (v_curr_date || ' 18:00:00')::TIMESTAMP;

            v_overlap_start := GREATEST(v_start_local, v_day_start);
            v_overlap_end := LEAST(v_end_local, v_day_end);

            IF v_overlap_end > v_overlap_start THEN
                v_total_seconds := v_total_seconds + EXTRACT(EPOCH FROM (v_overlap_end - v_overlap_start));
            END IF;
        END IF;

        v_curr_date := v_curr_date + INTERVAL '1 day';
    END LOOP;

    RETURN ROUND(v_total_seconds / 60.0, 2);
END;
$$ LANGUAGE plpgsql STABLE;
