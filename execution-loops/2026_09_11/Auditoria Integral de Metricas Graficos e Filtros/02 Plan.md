# 02 Plan · Auditoria Integral de Métricas, Gráficos, Filtros e Auditabilidade

> **Ciclo:** 1 · Fase 02 (Plan)  
> **Metodologia:** Execution Loop (`execution-loop/SKILL.md` + `plan-writing/SKILL.md`)  
> **Sub-skills:** `executing-plans`, `code-review-checklist`, `testing-patterns`

---

## 1. Visão Geral do Plano de Auditoria

Este plano estabelece o roteiro ordenado de investigação e validação técnica para cobrir cada um dos 10 itens da Rubrica de QA e os 47 componentes individuais catalogados na especificação.

O plano combina 4 métodos de verificação:
1. **Auditoria Estática de Código (SQL & JS):** Inspeção minuciosa das migrações SQL (`05`, `07`, `10`, `11`, `12`) e dos métodos de renderização/drilldown em `src/dashboard.js` e `index.html`.
2. **Auditoria Dinâmica Automatizada (Scripts Node.js):** Execução de scripts de teste contra o backend real do Supabase para aferir o comportamento das 16 RPCs com múltiplos cenários de filtros (nulos, arrays, tags específicas, janelas fora de expediente).
3. **Auditoria de Concordância Matemática e Lógica:** Confronto entre os valores agregados nos cards e os filtros aplicados no modal de drill-down.
4. **Auditoria de Segurança e RLS:** Execução do script `scripts/security-audit-and-attacks.js`.

---

## 2. Etapas de Execução

### Etapa 1: Auditoria dos Filtros Globais e Contratos de RPC (Item 1 da Rubrica)
- Inspecionar a função `filterParams()` e `dateRangeParams()` em `src/dashboard.js`.
- Verificar se todas as 16 RPCs em `11_multiselect_filters_tags_business_hours_weekend.sql` recebem os 9 parâmetros de filtro padronizados.
- Validar se a passagem de arrays vazios vs arrays com IDs funciona como esperado (`ARRAY[]::bigint[]` vs `IS NULL`).
- Criar e rodar script de teste automatizado `scripts/audit-rpc-filters.js` para disparar as RPCs com parâmetros cruzados e registrar tempos e respostas.

### Etapa 2: Auditoria da Fila Viva e Envelhecimento (Bloco A - Item 2 da Rubrica)
- Inspecionar a RPC `suporteapp_rpc_dashboard_queue`.
- Validar se D-01 considera estritamente conversas não resolvidas cuja última mensagem partiu da cliente.
- Validar se D-02 considera conversas onde a última mensagem partiu de atendente.
- Validar se D-03 dispara alerta quando prioridade for `P0` ou tag contiver `sev-red` e tempo for superior a 10 minutos.
- Inspecionar a função `suporteapp_fn_business_minutes_between` no cálculo do histograma D-04 e as faixas de tempo útil.
- Validar o cálculo de adesão à taxonomia (D-06) e o comportamento do top badge de alerta.

### Etapa 3: Auditoria de Fluxo, Espera e Balanço de Entrada vs Saída (Bloco B - Itens 3 e 4 da Rubrica)
- Inspecionar a RPC `suporteapp_rpc_turn_metrics`.
- Auditar a fórmula de cálculo da mediana de primeiro turno (D-08) e a correção da migração `12_fix_d08_turn1_biz_minutes_null_reply.sql` (garantindo que chamadas sem resposta não distorçam a mediana com valor 0).
- Auditar o cálculo de cumprimento da meta de 10 min (D-09) e turnos 2 em diante (D-10).
- Auditar a decomposição do painel D-11:
  - Total criados (`d11-created`).
  - Resolvidos manuais (`d11-manual` - `resolution_type = 'manual'`).
  - Resolvidos por inatividade (`d11-inactivity` - `resolution_type = 'inactivity_3d'`).
  - Saldo líquido (`d11-balance-val = created - totalResolved`).
  - Percentuais da barra empilhada.

### Etapa 4: Auditoria de Turno da Agente e Bot (Blocos C e D - Itens 5 e 6 da Rubrica)
- Inspecionar a RPC `suporteapp_rpc_daily_shift_metrics`:
  - Latência de abertura D-13 (contada a partir de 09:00:00 BRT).
  - Fila herdada e tempo para zerar D-14.
  - Horário de encerramento D-15 (último envio humano antes de 18:00 BRT).
  - Maior hiato ocioso D-16 com fila aberta.
- Inspecionar a RPC `suporteapp_rpc_bot_metrics`:
  - Total de atendimentos do bot, contenção (sem intervenção), transbordo e fila herdada matutina.

### Etapa 5: Auditoria do Relatório Semanal de Suporte (Parte 3 - Itens 7 e 8 da Rubrica)
- Inspecionar cada RPC e sua renderização no DOM:
  - `suporteapp_rpc_weekly_heatmap` (RS-01) -> Tabela 7x24 com coloração diferenciada em finais de semana.
  - `suporteapp_rpc_weekly_reasons` (RS-02) -> Motivos com colunas de espera e resolução, e rótulos `(ausente)` e `(múltiplo)`.
  - `suporteapp_rpc_reason_severity_matrix` (RS-03) -> Cruzamento de motivos com P0, P1, P2-P3.
  - Quadro de espera atendível vs corrida (RS-04) -> Comparação 4x2.
  - `suporteapp_rpc_resolution_breakdown` e `suporteapp_rpc_reopen_count` (RS-05).
  - `suporteapp_rpc_avoidable_vs_structural` (RS-06) -> Barra empilhada e percentuais.
  - `suporteapp_rpc_carried_stock` (RS-07).
  - `suporteapp_rpc_alarm_panel` (RS-08).
  - `suporteapp_rpc_weekly_handoff` (RS-09).
  - `suporteapp_rpc_first_contact_resolution` (RS-10).
  - `suporteapp_rpc_recurrence_rate` (RS-11).
  - `suporteapp_rpc_contest_and_false_negative` (RS-12) no topo executivo.
  - `suporteapp_rpc_bot_handover_top_subjects` (RS-13).
  - Formulário qualitativo com persistência isolada no `localStorage` (RS-14).

### Etapa 6: Auditoria do Sistema de Drill-down (Item 9 da Rubrica)
- Inspecionar `openDrilldownModal(type)` em `src/dashboard.js`.
- Mapear cada um dos 18 tipos de drilldown e comparar seus filtros com a respectiva RPC.
- Verificar se os links para o Chatwoot utilizam `account_id` correto (`88`) e `safeUrlConvId`.

### Etapa 7: Verificação de Segurança, RLS e Execução de Testes (Item 10 da Rubrica)
- Rodar `npm run test:security` e capturar a saída completa.
- Confirmar integridade do `scripts/generate-config.js` e proteção contra vazamento de chave privada.

### Etapa 8: Consolidação em Execução e Avaliação QA
- Registrar todas as evidências em `03 Execução.md`.
- Preencher as notas da Rubrica em `04 QA.md` (0 a 10 com evidências explícitas).
- Em caso de notas < 10, documentar a causa-raiz e abrir `05 Debug.md`.
