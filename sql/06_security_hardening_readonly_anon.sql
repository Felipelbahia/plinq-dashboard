-- ==============================================================================
-- Migration: 06_security_hardening_readonly_anon.sql
-- Descrição: Hardening de Segurança e Isolamento Read-Only para o Dashboard
-- Data: 2026-09-11
--
-- Objetivos:
-- 1. Revogação estrita de todos os privilégios de escrita (INSERT, UPDATE, DELETE, TRUNCATE) do role anon.
-- 2. Habilitação de RLS em tabelas órfãs/staging desprotegidas.
-- 3. Concessão de SELECT apenas nas tabelas explicitamente necessárias para o Dashboard.
-- 4. Criação de políticas RLS de leitura estrita para anon em suporteapp_tickets e inboxes.
-- 5. Configuração de SECURITY DEFINER com search_path seguro nas 17 RPCs analíticas.
-- ==============================================================================

-- 1. Revogar qualquer privilégio de escrita do role anon em todo o schema public
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON ALL TABLES IN SCHEMA public FROM anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLES FROM anon;

-- 2. Garantir RLS em tabelas de staging órfãs que estavam desprotegidas
ALTER TABLE IF EXISTS public.tmp_expired_credits_20250823 ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.tmp_expired_credits_staging ENABLE ROW LEVEL SECURITY;

-- 3. Conceder apenas SELECT nas tabelas necessárias para o Dashboard
GRANT SELECT ON public.suporteapp_tickets TO anon;
GRANT SELECT ON public.suporteapp_chatwoot_inboxes TO anon;
GRANT SELECT ON public.suporteapp_knowledge_base TO anon;
GRANT SELECT ON public.suporteapp_calendar TO anon;

-- 4. Ajustar todas as 22 funções (RPCs e helpers) para SECURITY DEFINER e search_path seguro
ALTER FUNCTION public.suporteapp_fn_calculate_business_minutes(timestamp with time zone, timestamp with time zone) SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION public.suporteapp_fn_classify_resolution_type(integer, timestamp with time zone, timestamp with time zone) SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION public.suporteapp_fn_get_atendivel_start(timestamp with time zone) SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION public.suporteapp_fn_get_period_start(text) SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION public.suporteapp_fn_is_bot_agent(integer) SECURITY DEFINER SET search_path = public, pg_temp;

ALTER FUNCTION public.suporteapp_rpc_alarm_panel(text) SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION public.suporteapp_rpc_avoidable_vs_structural(text, integer, text) SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION public.suporteapp_rpc_bot_handover_top_subjects(text, integer) SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION public.suporteapp_rpc_bot_metrics(text, integer, text) SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION public.suporteapp_rpc_carried_stock(text) SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION public.suporteapp_rpc_contest_and_false_negative(text) SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION public.suporteapp_rpc_daily_shift_metrics(text, integer, text, text, text) SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION public.suporteapp_rpc_dashboard_queue(integer, text, text, text) SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION public.suporteapp_rpc_first_contact_resolution(text) SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION public.suporteapp_rpc_reason_severity_matrix(text, integer) SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION public.suporteapp_rpc_recurrence_rate() SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION public.suporteapp_rpc_reopen_count(text) SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION public.suporteapp_rpc_resolution_breakdown(text, integer) SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION public.suporteapp_rpc_turn_metrics(text, integer, text, text, text) SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION public.suporteapp_rpc_weekly_handoff(text, integer, text) SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION public.suporteapp_rpc_weekly_heatmap(text, integer, text) SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION public.suporteapp_rpc_weekly_reasons(text, integer, text, text) SECURITY DEFINER SET search_path = public, pg_temp;

-- 5. Conceder permissão de EXECUTE para anon nas RPCs e helpers
GRANT EXECUTE ON FUNCTION public.suporteapp_fn_calculate_business_minutes(timestamp with time zone, timestamp with time zone) TO anon;
GRANT EXECUTE ON FUNCTION public.suporteapp_fn_classify_resolution_type(integer, timestamp with time zone, timestamp with time zone) TO anon;
GRANT EXECUTE ON FUNCTION public.suporteapp_fn_get_atendivel_start(timestamp with time zone) TO anon;
GRANT EXECUTE ON FUNCTION public.suporteapp_fn_get_period_start(text) TO anon;
GRANT EXECUTE ON FUNCTION public.suporteapp_fn_is_bot_agent(integer) TO anon;

GRANT EXECUTE ON FUNCTION public.suporteapp_rpc_alarm_panel(text) TO anon;
GRANT EXECUTE ON FUNCTION public.suporteapp_rpc_avoidable_vs_structural(text, integer, text) TO anon;
GRANT EXECUTE ON FUNCTION public.suporteapp_rpc_bot_handover_top_subjects(text, integer) TO anon;
GRANT EXECUTE ON FUNCTION public.suporteapp_rpc_bot_metrics(text, integer, text) TO anon;
GRANT EXECUTE ON FUNCTION public.suporteapp_rpc_carried_stock(text) TO anon;
GRANT EXECUTE ON FUNCTION public.suporteapp_rpc_contest_and_false_negative(text) TO anon;
GRANT EXECUTE ON FUNCTION public.suporteapp_rpc_daily_shift_metrics(text, integer, text, text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.suporteapp_rpc_dashboard_queue(integer, text, text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.suporteapp_rpc_first_contact_resolution(text) TO anon;
GRANT EXECUTE ON FUNCTION public.suporteapp_rpc_reason_severity_matrix(text, integer) TO anon;
GRANT EXECUTE ON FUNCTION public.suporteapp_rpc_recurrence_rate() TO anon;
GRANT EXECUTE ON FUNCTION public.suporteapp_rpc_reopen_count(text) TO anon;
GRANT EXECUTE ON FUNCTION public.suporteapp_rpc_resolution_breakdown(text, integer) TO anon;
GRANT EXECUTE ON FUNCTION public.suporteapp_rpc_turn_metrics(text, integer, text, text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.suporteapp_rpc_weekly_handoff(text, integer, text) TO anon;
GRANT EXECUTE ON FUNCTION public.suporteapp_rpc_weekly_heatmap(text, integer, text) TO anon;
GRANT EXECUTE ON FUNCTION public.suporteapp_rpc_weekly_reasons(text, integer, text, text) TO anon;

-- 6. Definir políticas RLS de leitura (SELECT) estritas para o role anon
DROP POLICY IF EXISTS "suporteapp_tickets_anon_select" ON public.suporteapp_tickets;
CREATE POLICY "suporteapp_tickets_anon_select" ON public.suporteapp_tickets 
    FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "suporteapp_chatwoot_inboxes_anon_select" ON public.suporteapp_chatwoot_inboxes;
CREATE POLICY "suporteapp_chatwoot_inboxes_anon_select" ON public.suporteapp_chatwoot_inboxes 
    FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "suporteapp_calendar_anon_select" ON public.suporteapp_calendar;
CREATE POLICY "suporteapp_calendar_anon_select" ON public.suporteapp_calendar 
    FOR SELECT TO anon USING (true);
