-- Migration: 20260911_fix_rls_messages_taxonomy_anon_select.sql
-- Descrição: BUG CRÍTICO PRÉ-EXISTENTE encontrado na revisão de funcionalidade/precisão do
-- Dashboard v3.0 (não introduzido pela migração de filtros de agente/time/data) —
-- suporteapp_messages, suporteapp_label_taxonomy, suporteapp_escalations e
-- suporteapp_ticket_labels têm RLS habilitada (correto) mas NUNCA tiveram policy de SELECT
-- para o role `anon` (usado pela SUPABASE_ANON_KEY do frontend), diferente de
-- suporteapp_tickets/suporteapp_chatwoot_inboxes, que já tinham.
--
-- Efeito prático confirmado ao vivo (SET LOCAL ROLE anon): as 4 tabelas retornavam 0 linhas
-- para anon. Como todas as RPCs do dashboard são SECURITY INVOKER (rodam com o privilégio de
-- quem chama — correto para RLS funcionar por linha), isso silenciosamente degradava vários
-- blocos sem gerar nenhum erro visível na UI (a RPC "funciona", só devolve dado incompleto):
--   - suporteapp_rpc_daily_shift_metrics (Bloco C, D-13/D-15/D-16) e suporteapp_rpc_bot_metrics
--     (Bloco D, D-17) fazem JOIN direto em suporteapp_messages -> sempre 0 linhas.
--   - suporteapp_rpc_weekly_reasons (RS-02), suporteapp_rpc_reason_severity_matrix (RS-03),
--     suporteapp_rpc_weekly_handoff (RS-09), suporteapp_rpc_first_contact_resolution (RS-10) e
--     suporteapp_rpc_bot_handover_top_subjects (RS-13) fazem JOIN em suporteapp_label_taxonomy
--     -> toda etiqueta de motivo cai em '(ausente)', RS-03/RS-09 ficam sempre vazios (o WHERE
--     filtra reason_label IS NOT NULL) e RS-10 (FCR) reporta 0% para todo mundo (COALESCE(0,0)=1
--     nunca é true porque n_outgoing nunca é lido).
-- suporteapp_escalations/suporteapp_ticket_labels não são lidas por nenhuma RPC hoje, mas
-- ganham a mesma policy por consistência (documentadas em CLAUDE.md §8 como base de futuras
-- views de analytics do dashboard).

CREATE POLICY suporteapp_messages_anon_select
  ON public.suporteapp_messages
  FOR SELECT
  TO anon
  USING (true);

CREATE POLICY suporteapp_label_taxonomy_anon_select
  ON public.suporteapp_label_taxonomy
  FOR SELECT
  TO anon
  USING (true);

CREATE POLICY suporteapp_escalations_anon_select
  ON public.suporteapp_escalations
  FOR SELECT
  TO anon
  USING (true);

CREATE POLICY suporteapp_ticket_labels_anon_select
  ON public.suporteapp_ticket_labels
  FOR SELECT
  TO anon
  USING (true);
