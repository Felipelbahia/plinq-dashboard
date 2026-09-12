# Scripts SQL de Estrutura e Métricas · Supabase

Esta pasta contém todas as migrações DDL, dados de calendário, funções de janela comercial e RPCs necessárias para rodar o **Dashboard de Suporte v3.0** no PostgreSQL do Supabase.

---

## 🚀 Ordem de Execução no SQL Editor do Supabase

Caso esteja configurando uma nova instância do banco de dados no Supabase, execute os scripts exatamente na seguinte ordem:

1. **`01_ddl_estrutura_dados.sql`**
   - Cria as tabelas de apoio: `suporteapp_calendar`, `suporteapp_auto_messages`, `suporteapp_label_taxonomy`, `suporteapp_weekly_reports` e `suporteapp_activity_logs`.
   - Adiciona a coluna `resolution_type` em `suporteapp_tickets`.
   - Habilita RLS (Row Level Security) e políticas de leitura pública/anon.

2. **`02_populate_calendar_2026_2028.sql`**
   - Popula todos os dias entre 2026-01-01 e 2028-12-31.
   - Aplica os feriados nacionais, estaduais (SP) e municipais (São Paulo) para cálculo da janela comercial (09h00 às 18h00 BRT).

3. **`03_funcoes_janela_comercial.sql`**
   - Cria as funções PL/pgSQL essenciais:
     - `suporteapp_fn_get_atendivel_start`: calcula o momento atendível da mensagem (início do SLA).
     - `suporteapp_fn_calculate_business_minutes`: calcula o tempo líquido decorrido em minutos úteis comerciais.

4. **`04_views_dashboard_e_relatorio.sql`**
   - Cria as views base de agrupamento de métricas: `suporteapp_v_dashboard_queue`, `suporteapp_v_dashboard_turn_metrics`, `suporteapp_v_turn_times_detail`, etc.

5. **`05_fix_rpcs_contrato_e_filtros.sql`**
   - Cria e atualiza as RPCs parametrizadas consumidas diretamente pelo frontend `src/dashboard.js`:
     - `suporteapp_rpc_dashboard_queue` (Bloco A · D-01 a D-06)
     - `suporteapp_rpc_turn_metrics` (Bloco B · D-07 a D-12)
     - `suporteapp_rpc_daily_shift_metrics` (Bloco D · D-16 e D-17)
     - `suporteapp_rpc_bot_metrics` (Bloco D · RS-07 a RS-09)
     - `suporteapp_rpc_avoidable_vs_structural` (RS-10 a RS-12)
     - `suporteapp_rpc_weekly_handoff` (RS-03)
     - `suporteapp_rpc_weekly_reasons` (RS-02)

6. **`06_security_hardening_readonly_anon.sql`**
   - Endurecimento de segurança do `role anon` (chave pública usada pelo frontend) — garante que
     só consegue `SELECT`/`EXECUTE` em tabelas/RPCs de leitura do dashboard, nunca `INSERT`/
     `UPDATE`/`DELETE`.

7. **`07_add_agent_team_date_filters.sql`**
   - Adiciona filtro de **Agente** (`p_agent_id` → `current_agent_id`), **Time** (`p_team_id` →
     `current_team_id`) e **data customizada** (`p_date_start`/`p_date_end`) em todas as RPCs do
     dashboard, via nova função `suporteapp_fn_resolve_period_range` (substitui o uso direto de
     `suporteapp_fn_get_period_start`, cujo `CREATE FUNCTION` não está versionado no repositório).
   - Também corrige `suporteapp_rpc_recurrence_rate` (RS-11), que antes não aceitava nenhum
     parâmetro e por isso ignorava o filtro de período da UI.
   - `suporteapp_rpc_dashboard_queue` (Bloco A, "fila agora") é a única exceção que **não** recebe
     filtro de data — ganha só agente/time.

8. **`08_fix_rls_chatwoot_agents_teams_anon_select.sql`**
   - BUG FIX: `suporteapp_chatwoot_agents`/`suporteapp_chatwoot_teams` tinham RLS habilitada mas
     nenhuma policy de `SELECT` para `anon` — os filtros de Agente/Time do script 07 nunca
     conseguiam popular seus dropdowns em produção. Adiciona a policy `USING (true)` que faltava.

9. **`09_fix_rls_messages_taxonomy_anon_select.sql`**
   - BUG FIX (mais grave, pré-existente): `suporteapp_messages`, `suporteapp_label_taxonomy`,
     `suporteapp_escalations` e `suporteapp_ticket_labels` também não tinham policy de `SELECT`
     para `anon`. Como as RPCs do dashboard são `SECURITY INVOKER`, isso zerava/mascarava vários
     blocos sem erro visível — RS-10 (FCR) chegava a reportar 0% para todo mundo. Corrigido com a
     mesma policy `USING (true)`.

10. **`10_add_rs04_raw_metrics_and_rs02_delta.sql`**
    - RS-04 "Espera Corrida": adiciona `rs04_avg_turn1_raw_minutes` e
      `rs04_meta_10min_compliance_raw_pct` em `suporteapp_rpc_turn_metrics` (antes hardcoded
      `'N/D'` no frontend, nunca calculados).
    - RS-02 "Delta Semanal": adiciona `volume_delta_pct` em `suporteapp_rpc_weekly_reasons`
      (compara o volume de cada motivo contra a janela anterior de mesma duração).
    - Blinda `suporteapp_rpc_turn_metrics` contra dado corrompido: tickets com
      `first_public_reply_at < created_at` (confirmado ao vivo: 16% dos tickets de 30d) são
      excluídos do cálculo — antes inflavam `d09_meta_10min_compliance_pct` (contados como
      "resposta instantânea") e geravam uma média raw negativa sem sentido.

11. **`11_multiselect_filters_tags_business_hours_weekend.sql`**
    - Unifica o contrato de filtros: todos os parâmetros de filtro (canal, agente, time,
      severidade, origem, taxonomia) passam de escalar para **array** (`p_inbox_ids`,
      `p_agent_ids`, `p_team_ids`, `p_severities`, `p_origins`, `p_taxonomies`), para suportar
      multi-seleção por checkbox no frontend. Convenção: `NULL` = sem restrição; array vazio =
      nada passa (usuário desmarcou tudo).
    - Adiciona filtro de **Tag** (`p_tags`, sobre `suporteapp_label_taxonomy.label_name`, com a
      sentinela `'__sem_tag__'` para tickets sem nenhuma etiqueta).
    - Adiciona **`p_business_hours_filter`** (`'all'|'only_outside'|'exclude_outside'`) — início
      da conversa dentro/fora de 09h-18h Seg-Sex.
    - Adiciona **`p_weekend_filter`** (`'all'|'only_weekend'|'exclude_weekend'`) — início da
      conversa entre sexta 18h e segunda 9h (horário de São Paulo).
    - Toda a lógica de filtro comum foi extraída para `suporteapp_fn_scope_tickets(...)
      RETURNS SETOF suporteapp_tickets`, reaproveitada pelas 17 RPCs — evita repetir a mesma
      cláusula `WHERE` em cada uma. Novo helper `suporteapp_fn_is_weekend_start(timestamptz)`.
