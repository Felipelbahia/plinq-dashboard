-- Migration: 20260911_fix_rls_chatwoot_agents_teams_anon_select.sql
-- Descrição: BUG FIX encontrado na revisão de UX/funcionalidade do Dashboard v3.0 —
-- suporteapp_chatwoot_agents e suporteapp_chatwoot_teams têm RLS habilitada (correto, regra
-- absoluta de segurança do projeto) mas nunca ganharam uma policy de SELECT para o role `anon`
-- (usado pela SUPABASE_ANON_KEY do frontend), diferente de suporteapp_tickets e
-- suporteapp_chatwoot_inboxes, que já tinham essa policy desde as migrações anteriores. Efeito
-- prático confirmado ao vivo (SET LOCAL ROLE anon): as duas tabelas retornam 0 linhas para
-- anon, então os filtros de Agente e Time adicionados em 20260911_add_agent_team_date_filters.sql
-- nunca conseguiam popular seus dropdowns (loadAgentDirectory()/loadTeamDirectory() em
-- src/dashboard.js sempre caíam no branch de erro silencioso).

CREATE POLICY suporteapp_chatwoot_agents_anon_select
  ON public.suporteapp_chatwoot_agents
  FOR SELECT
  TO anon
  USING (true);

CREATE POLICY suporteapp_chatwoot_teams_anon_select
  ON public.suporteapp_chatwoot_teams
  FOR SELECT
  TO anon
  USING (true);
