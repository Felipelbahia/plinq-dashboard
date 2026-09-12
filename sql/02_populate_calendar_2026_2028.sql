-- ==============================================================================
-- CHAMADOS APP · DASHBOARD DE SUPORTE V3.0
-- Carga de Calendário Comercial (2026, 2027, 2028)
-- Feriados Nacionais (BR) + Estaduais (SP) + Municipais (São Paulo)
-- ==============================================================================

-- 1. Popula todos os dias entre 2026-01-01 e 2028-12-31
INSERT INTO public.suporteapp_calendar (calendar_date, is_business_day, start_time, end_time, is_holiday)
SELECT 
    d::date AS calendar_date,
    CASE WHEN EXTRACT(ISODOW FROM d) IN (6, 7) THEN false ELSE true END AS is_business_day,
    '09:00:00'::time AS start_time,
    '18:00:00'::time AS end_time,
    false AS is_holiday
FROM generate_series('2026-01-01'::date, '2028-12-31'::date, '1 day'::interval) d
ON CONFLICT (calendar_date) DO NOTHING;

-- 2. Atualização dos Feriados Nacionais / Estaduais / Municipais de 2026
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Confraternização Universal' WHERE calendar_date = '2026-01-01';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'city_sp', holiday_name = 'Aniversário de São Paulo' WHERE calendar_date = '2026-01-25';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Carnaval (Segunda)' WHERE calendar_date = '2026-02-16';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Carnaval (Terça)' WHERE calendar_date = '2026-02-17';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Sexta-feira Santa' WHERE calendar_date = '2026-04-03';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Tiradentes' WHERE calendar_date = '2026-04-21';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Dia do Trabalho' WHERE calendar_date = '2026-05-01';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Corpus Christi' WHERE calendar_date = '2026-06-04';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'state_sp', holiday_name = 'Revolução Constitucionalista de 1932' WHERE calendar_date = '2026-07-09';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Independência do Brasil' WHERE calendar_date = '2026-09-07';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Nossa Senhora Aparecida' WHERE calendar_date = '2026-10-12';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Finados' WHERE calendar_date = '2026-11-02';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Proclamação da República' WHERE calendar_date = '2026-11-15';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Dia Nacional de Zumbi e da Consciência Negra' WHERE calendar_date = '2026-11-20';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Natal' WHERE calendar_date = '2026-12-25';

-- 3. Atualização dos Feriados Nacionais / Estaduais / Municipais de 2027
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Confraternização Universal' WHERE calendar_date = '2027-01-01';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'city_sp', holiday_name = 'Aniversário de São Paulo' WHERE calendar_date = '2027-01-25';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Carnaval (Segunda)' WHERE calendar_date = '2027-02-08';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Carnaval (Terça)' WHERE calendar_date = '2027-02-09';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Sexta-feira Santa' WHERE calendar_date = '2027-03-26';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Tiradentes' WHERE calendar_date = '2027-04-21';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Dia do Trabalho' WHERE calendar_date = '2027-05-01';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Corpus Christi' WHERE calendar_date = '2027-05-27';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'state_sp', holiday_name = 'Revolução Constitucionalista de 1932' WHERE calendar_date = '2027-07-09';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Independência do Brasil' WHERE calendar_date = '2027-09-07';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Nossa Senhora Aparecida' WHERE calendar_date = '2027-10-12';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Finados' WHERE calendar_date = '2027-11-02';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Proclamação da República' WHERE calendar_date = '2027-11-15';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Dia Nacional de Zumbi e da Consciência Negra' WHERE calendar_date = '2027-11-20';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Natal' WHERE calendar_date = '2027-12-25';

-- 4. Atualização dos Feriados Nacionais / Estaduais / Municipais de 2028
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Confraternização Universal' WHERE calendar_date = '2028-01-01';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'city_sp', holiday_name = 'Aniversário de São Paulo' WHERE calendar_date = '2028-01-25';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Carnaval (Segunda)' WHERE calendar_date = '2028-02-28';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Carnaval (Terça)' WHERE calendar_date = '2028-02-29';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Sexta-feira Santa' WHERE calendar_date = '2028-04-14';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Tiradentes' WHERE calendar_date = '2028-04-21';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Dia do Trabalho' WHERE calendar_date = '2028-05-01';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Corpus Christi' WHERE calendar_date = '2028-06-15';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'state_sp', holiday_name = 'Revolução Constitucionalista de 1932' WHERE calendar_date = '2028-07-09';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Independência do Brasil' WHERE calendar_date = '2028-09-07';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Nossa Senhora Aparecida' WHERE calendar_date = '2028-10-12';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Finados' WHERE calendar_date = '2028-11-02';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Proclamação da República' WHERE calendar_date = '2028-11-15';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Dia Nacional de Zumbi e da Consciência Negra' WHERE calendar_date = '2028-11-20';
UPDATE public.suporteapp_calendar SET is_business_day = false, is_holiday = true, holiday_type = 'national', holiday_name = 'Natal' WHERE calendar_date = '2028-12-25';
