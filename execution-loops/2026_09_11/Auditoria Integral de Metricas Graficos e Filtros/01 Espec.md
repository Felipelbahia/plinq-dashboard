# 01 Espec · Auditoria Integral de Métricas, Gráficos, Filtros e Auditabilidade

> **Ciclo:** 1 · Fase 01 (Espec)  
> **Metodologia:** Execution Loop (`execution-loop/SKILL.md` + `spec-writing/SKILL.md`)  
> **Skills Aplicadas:** `qa-automation-engineer`, `backend-specialist`, `frontend-design`, `clean-code`

---

## Problem Statement

O Dashboard de Suporte Plinq v3.0 é a ferramenta central de tomada de decisão operacional da liderança e atendimento. Ele sintetiza dados de centenas de conversas do Chatwoot processadas via Supabase, aplicando regras complexas como:
- Contabilização estrita de minutos úteis dentro da janela comercial (09:00 às 18:00 BRT, seg a sex, excluindo feriados nacionais mapeados na tabela `suporteapp_calendar`).
- Distinção entre resoluções manuais por agentes e encerramentos automáticos por inatividade (3 dias sem resposta).
- Filtros dinâmicos cruzados em 10 dimensões simultâneas (período/datas, caixa de entrada, agente, time, severidade, origem, taxonomia, tag, horário de expediente e finais de semana).

Caso qualquer métrica, gráfico ou tabela apresente distorção nos dados, ignore filtros silenciosamente, possua divergência entre o número exibido no card e a listagem do drill-down, ou sofra de cálculos incorretos de tempo/fuso, a operação toma decisões baseadas em premissas falsas. Portanto, é necessária uma auditoria exaustiva e rigorosa, item por item, validando a integridade dos dados, a influência de cada filtro, a ausência de bugs e a auditabilidade total.

---

## Solution

Executar um ciclo completo de auditoria técnica e funcional cobrindo os **47 itens e componentes do Dashboard**, estruturado em:
1. **Auditoria de Contrato de Filtros:** Verificar se todas as 16 RPCs do banco e o frontend propagam e aplicam integralmente os 10 parâmetros de filtro (`p_inbox_ids`, `p_agent_ids`, `p_team_ids`, `p_severities`, `p_origins`, `p_taxonomies`, `p_tags`, `p_business_hours_filter`, `p_weekend_filter`, `p_date_start`/`p_date_end`).
2. **Auditoria da Fila Viva (Bloco A):** Validar se D-01, D-02, D-03, D-05, D-06 e o histograma D-04 refletem o estado real 24x7 das conversas abertas e respeitam o critério de quem está com a bola (`waiting_plinq` vs `waiting_customer`).
3. **Auditoria de Fluxo e Espera (Bloco B):** Validar se D-07 a D-12 e o painel D-11 (Novos Criados vs Resolvidos Manualmente vs Inatividade vs Saldo Líquido) calculam tempos de primeira resposta e de turnos seguintes com precisão matemática em horário comercial.
4. **Auditoria de Turno e Bot (Blocos C e D):** Validar métricas de início de expediente (D-13), zeragem de fila (D-14), encerramento (D-15), hiato ocioso (D-16) e taxas de contenção e transbordo do bot (D-17).
5. **Auditoria dos 14 Módulos do Relatório Semanal (Parte 3):** Validar cada tabela, gráfico e matriz de RS-01 a RS-14 (Heatmap 7x24, motivos, matriz severidade, espera corrida vs atendível, resoluções, estoques, alarmes, handoffs, FCR, reincidência e notas qualitativas).
6. **Auditoria do Sistema de Drill-down:** Verificar se todos os 18 modos de abertura do modal trazem os tickets corretos, com filtros alinhados à RPC correspondente e links válidos para o Chatwoot.
7. **Verificação de Regras de Segurança e Performance:** Confirmar conformidade com RLS `anon` somente-leitura e ausência de memory leaks ou polling desordenado.

---

## User Stories

1. **US-01 (Propagação Universal de Filtros):** Como gestor, quando aplico qualquer combinação dos 10 filtros globais (ex: filtrar apenas pelo canal "WhatsApp" e severidade "P0"), quero que todos os blocos do dashboard (A, B, C, D e RS) atualizem seus números refletindo exclusivamente o subconjunto selecionado.
2. **US-02 (Precisão da Fila Viva em Tempo Real - Bloco A):** Como líder de atendimento, quero ver em D-01 apenas conversas abertas cuja última mensagem seja da cliente, e em D-02 conversas onde a Plinq já respondeu, sem contaminações de tickets resolvidos.
3. **US-03 (Alerta Crítico Imediato - D-03):** Como operador, quero que conversas P0 / `sev-red` sem resposta há mais de 10 minutos acionem o destaque visual animado no card D-03 e apareçam com prioridade máxima no drill-down.
4. **US-04 (Cálculo Fiel de Janela Comercial - D-04, D-08, D-09, D-10):** Como auditor, quero garantir que tempos de espera excluam finais de semana, feriados e horários fora de 09:00–18:00 BRT, para que o cumprimento do SLA de 10 min (D-09) seja medido de forma justa.
5. **US-05 (Decomposição Transparente de Saídas - D-11 e RS-05):** Como gestor, quero diferenciar claramente conversas resolvidas pelo trabalho efetivo dos atendentes daquelas encerradas por abandono/inatividade após 3 dias.
6. **US-06 (Auditoria Cruzada de Etiquetas - RS-03):** Como coordenador de qualidade, quero cruzar motivos de atendimento com severidade na matriz RS-03 para flagrar anomalias de taxonomia (ex: dúvidas simples marcadas erroneamente como P0).
7. **US-07 (Detalhamento Granular no Modal):** Como supervisor, ao clicar em qualquer card ou linha de gráfico, quero abrir o modal com a lista exata dos tickets correspondentes e poder clicar no link para abrir a conversa diretamente no Chatwoot.
8. **US-08 (Proteção de Dados e Integridade):** Como responsável de segurança, quero assegurar que nenhuma chave privilegiada (`service_role`) trafegue no frontend e que as consultas REST/RPC respeitem as políticas RLS.

---

## Implementation Decisions

1. **Camada de Backend (Supabase PostgreSQL):**
   - Inspecionar diretamente a definição SQL de cada uma das 16 RPCs presentes nas migrações `05_fix_rpcs_contrato_e_filtros.sql`, `07_add_agent_team_date_filters.sql`, `10_add_rs04_raw_metrics_and_rs02_delta.sql`, `11_multiselect_filters_tags_business_hours_weekend.sql` e `12_fix_d08_turn1_biz_minutes_null_reply.sql`.
   - Verificar se as cláusulas `WHERE` de cada RPC incluem e tratam corretamente todos os parâmetros opcionais (arrays nulos = sem filtro; arrays populados = `ANY()` ou `@>`).
2. **Camada de Frontend (`src/dashboard.js`):**
   - Mapear a função `filterParams()` e `dateRangeParams()`, conferindo se todos os parâmetros são enviados com as chaves exatas esperadas pelo PostgreSQL.
   - Auditar a função `openDrilldownModal(type)`: verificar se os filtros REST aplicados em `suporteapp_tickets` e os filtros em memória (`t.status`, `t.queue_state`, `t.resolution_type`) são idênticos aos critérios da RPC do card correspondente.
3. **Tratamento de Exceções e Resiliência:**
   - Conferir se todas as chamadas possuem tratamento de erro com feedback visual claro (funções `errorRow`, textos explicativos) e se nunca exibem dados fabricados (mock/hardcoded).
   - Verificar tratamento de valores nulos (ex: `d08_median` quando não há chamadas com resposta no período, exibindo `sem dado` em vez de quebrar ou exibir `NaN`).

---

## Testing Decisions

1. **Auditoria de Código Estática (Code Review & Traceability):**
   - Rastrear a linha de código de renderização e de chamada para cada um dos 47 itens.
2. **Auditoria Dinâmica via Testes Automatizados:**
   - Executar a suíte de segurança e ataques RLS (`node scripts/security-audit-and-attacks.js`).
   - Criar e rodar um script de auditoria de integridade (`scripts/audit-dashboard-integrity.js`) que testa as RPCs contra o Supabase com diferentes combinações de filtros.
3. **Auditoria de Concordância Card vs Drilldown:**
   - Comparar o valor numérico retornado pelas RPCs com o número de linhas retornado pelo filtro de drill-down equivalente para identificar discrepâncias de lógica.

---

## Out of Scope

- Criação de novas tabelas ou alteração da arquitetura do banco do Chatwoot.
- Adição de novos frameworks de frontend (React, Vue, Tailwind).
- Modificação na regra oficial da janela comercial (09:00 às 18:00 BRT).

---

## Rubrica de Avaliação QA (Nota 0 a 10 por Item)

| # | Item da Rubrica | Critério de Aceite Estrito (10/10) |
|---|---|---|
| **1** | **Propagação dos 10 Filtros Globais** | Todos os 10 filtros (Período, Canal, Agente, Time, Severidade, Origem, Taxonomia, Tag, Fora Expediente, Fim de Semana) são aceitos e aplicados corretamente por todas as RPCs do Dashboard sem erros de tipo ou parâmetros ignorados. |
| **2** | **Integridade da Fila Agora (Bloco A: D-01 a D-06)** | Cards D-01, D-02, D-03, D-05, D-06 e histograma D-04 refletem com precisão o estado das conversas abertas, com lógica correta de `waiting_plinq` vs `waiting_customer` e cálculo útil de envelhecimento. |
| **3** | **Precisão de Fluxo e Espera (Bloco B: D-07 a D-12)** | Métricas D-07 a D-12 calculam entradas, percentual de meta 10m (D-09), medianas e P90 (D-08, D-10) em minutos comerciais úteis BRT, sem distorção por conversas sem resposta ou fora da janela. |
| **4** | **Consistência do Balanço de Vazão (D-11 & RS-05)** | Card D-11 decompõe saídas com precisão entre Resoluções Manuais (`resolution_type = manual`) e Inatividade de 3 dias (`inactivity_3d`), com soma e saldo líquido matematicamente exatos. |
| **5** | **Turno da Agente e Métricas Diárias (Bloco C: D-13 a D-16)** | Métricas de latência após as 09:00 (D-13), fila herdada (D-14), último envio antes das 18:00 (D-15) e hiato ocioso com fila pendente (D-16) operam com fuso BRT exato e sem falsos alarmes. |
| **6** | **Desempenho de Bot e Automação (Bloco D: D-17 & RS-13)** | Métricas de total do bot, taxa de contenção, taxa de transbordo e fila herdada calculam percentuais com denominador correto e listam top assuntos de transbordo em RS-13. |
| **7** | **Relatório Semanal de Suporte (RS-01 a RS-04, RS-06)** | Heatmap 7x24 (RS-01), motivos (RS-02), matriz severidade (RS-03), quadro atendível vs corrida (RS-04) e espera evitável vs estrutural (RS-06) operam com dados reais e sem mocks. |
| **8** | **Relatório Semanal de Suporte (RS-07 a RS-12, RS-14)** | Estoque carregado (RS-07), painel de alarmes (RS-08), handoffs (RS-09), FCR (RS-10), reincidência 7d/30d (RS-11), contestações no topo (RS-12) e notas qualitativas (RS-14) 100% funcionais e auditáveis. |
| **9** | **Auditabilidade e Alinhamento do Modal Drill-Down** | Todos os 18 fluxos de drilldown abrem tabela com tickets reais, links operacionais para o Chatwoot (`accounts/88`), e os critérios de seleção batem exatamente com as métricas do card de origem. |
| **10** | **Segurança, RLS e Resiliência Técnica** | Frontend consome Supabase estritamente via chave pública `anon` e RLS somente-leitura; ausência de dados fabricados (mock); tratamento de erros HTTP/REST; e build seguro (`npm run test:security` 100% aprovado). |
