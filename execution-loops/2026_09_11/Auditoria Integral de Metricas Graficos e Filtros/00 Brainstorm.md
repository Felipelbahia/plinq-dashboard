# 00 Brainstorm · Auditoria Integral de Métricas, Gráficos, Filtros e Auditabilidade

> **Data de Início:** 11/09/2026  
> **Ciclo:** 1 · Fase 00 (Brainstorming)  
> **Especialistas:** `@orchestrator`, `@qa-automation-engineer`, `@backend-specialist` & `@frontend-specialist`  
> **Metodologia:** Execution Loop (`execution-loop/SKILL.md` + `brainstorming/SKILL.md`)

---

## 1. Contexto e Motivação da Demanda

O **Dashboard de Suporte Plinq v3.0** é uma SPA analítica e operacional que monitora a fila de atendimento 24x7, calcula SLAs dentro de uma janela comercial rigorosa (09h às 18h BRT, seg a sex, excluindo feriados via `suporteapp_calendar`), mede o desempenho de agentes e bots, e consolida 14 blocos do relatório executivo semanal (RS-01 a RS-14).

Recentemente, a arquitetura de filtros foi expandida para incluir:
1. Multi-seleção com checkboxes em 7 filtros (Canal, Agente, Time, Severidade, Origem, Taxonomia, Tag).
2. Dois filtros booleanos/tristate de janela (Início Fora do Expediente e Início no Fim de Semana).
3. Seletor dinâmico de datas com popover flutuante e presets rápidos (Hoje, Ontem, Esta Semana, Semana Passada, 7D, 30D, Este Mês, Mês Anterior e Personalizado).

O objetivo desta auditoria integral ponta a ponta é **inventariar e inspecionar cada gráfico, cada card de KPI, cada tabela e cada elemento interativo**, validando sob 4 eixos inegociáveis:
1. **Veracidade dos Dados (Data Integrity):** Os dados exibidos refletem exatamente o que está no banco Supabase ou há distorções, campos nulos tratados como zero, ou cálculos incorretos de tempo útil?
2. **Influência dos Filtros Globais (Filter Propagation):** Cada um dos 10 filtros influencia o componente como deveria, ou a RPC/frontend ignora parâmetros silenciosamente?
3. **Detecção de Potenciais Bugs (Bug Hunting & Edge Cases):** Há divisões por zero, fusos GMT vs BRT dessincronizados, quebras de layout em listas vazias, memory leaks em polling de 30s ou inconsistências entre o número do card e a soma de suas partes?
4. **Auditabilidade Estrita (Verifiability & Drill-Down):** O gestor consegue auditar cada número até o ticket individual no Chatwoot via modal de drill-down, e os critérios de filtro do modal correspondem exatamente ao critério da RPC?

---

## 2. Mapeamento e Identificação Exaustiva de Todos os Pontos do Dashboard

O dashboard é composto por **47 itens auditáveis**, distribuídos em 7 grupos estruturais:

### Grupo 1: Barramento de Filtros Globais (10 Filtros + 1 Status)
* **`F-01` · Seletor de Período (Date Picker Popover):** 8 presets rápidos + Personalizado De/Até com restrição de data máxima e fuso BRT.
* **`F-02` · Canal / Caixa de Entrada (`p_inbox_ids`):** Multi-select alimentado por `suporteapp_chatwoot_inboxes`, com default nos inboxes 163, 164, 295, 296.
* **`F-03` · Agente (`p_agent_ids`):** Multi-select alimentado por `suporteapp_chatwoot_agents` (apenas humanos ativos).
* **`F-04` · Time (`p_team_ids`):** Multi-select alimentado por `suporteapp_chatwoot_teams`.
* **`F-05` · Severidade (`p_severities`):** Multi-select de prioridades (P0 Red, P1 Yellow, P2 Green, P3 Green).
* **`F-06` · Origem Atendimento (`p_origins`):** Multi-select binário (Humano vs Bot).
* **`F-07` · Status Taxonomia (`p_taxonomies`):** Multi-select (Válida com 2 tags vs Ausente/Incompleta).
* **`F-08` · Tag / Etiqueta (`p_tags`):** Multi-select com busca de 42 tags oficiais + opção especial `__sem_tag__`.
* **`F-09` · Início Fora do Expediente (`p_business_hours_filter`):** Dropdown de 3 posições (Todas, Só Fora 09h-18h, Excluir Fora).
* **`F-10` · Início no Fim de Semana (`p_weekend_filter`):** Dropdown de 3 posições (Todas, Só Fim de Semana, Excluir Fim de Semana).
* **`F-11` · Header Status & Top Badge de Adesão:** Indicador pulsante de sync em tempo real e badge dinâmico `#badge-adherence-top` ativado quando adesão < 95%.

### Grupo 2: Bloco A — Fila Agora (Momento Atual Vivo 24x7 - Sem Filtro de Período)
*Fonte: RPC `suporteapp_rpc_dashboard_queue`.*
* **`A-01` (Card D-01):** Fila Atendimento Plinq (Chamados abertos com a última mensagem da cliente). Drill-down: `d01`.
* **`A-02` (Card D-02):** Aguardando Usuária (Chamados abertos onde o último retorno foi de atendente humano). Drill-down: `d02`.
* **`A-03` (Card D-03):** Alerta Red (> 10 min) (Chamados P0/`sev-red` pendentes há mais de 10 min). Alerta visual imediato. Drill-down: `d03`.
* **`A-04` (Card D-05):** Sem Atendimento Nenhum (Chamados abertos virgens sem nenhuma resposta humana de saída). Drill-down: `d05`.
* **`A-05` (Card D-06):** Adesão à Taxonomia (%) (% com etiquetas válidas de Severidade e Motivo). Drill-down: `d06`.
* **`A-06` (Gráfico/Histograma D-04):** Envelhecimento da Fila em Janela Comercial:
  * Mediana de espera útil (`#d04-median`) e P90 (`#d04-p90`).
  * 5 barras proporcionais: `< 1h`, `1h a 4h`, `4h a 24h`, `24h a 72h` e `> 72h`. Drill-down: `d04`.

### Grupo 3: Bloco B — Fluxo de Chamados e Espera (D-07 a D-12 + RS-04)
*Fonte: RPC `suporteapp_rpc_turn_metrics`.*
* **`B-01` (Card D-07):** Conversas Novas (Entradas) no período. Drill-down: `d07`.
* **`B-02` (Card D-09):** Meta de 10 min (Cumprimento SLA) (% primeiras respostas <= 10 min úteis). Drill-down: `d09`.
* **`B-03` (Card D-08 Mediana):** Mediana da 1ª Resposta em minutos úteis BRT. Drill-down: `d08_med`.
* **`B-04` (Card D-08 P90):** P90 da 1ª Resposta em minutos úteis BRT. Drill-down: `d08_p90`.
* **`B-05` (Card D-10):** Espera Respostas Seguintes (Turnos 2 em diante em minutos úteis). Drill-down: `d10`.
* **`B-06` (Card D-12):** Demanda Fora da Janela (% e contadores brutos de chamados iniciados fora do horário comercial). Drill-down: `d12`.
* **`B-07` (Painel/Gráfico D-11):** Balanço de Entrada contra Saída (Vazão da Fila):
  * Card Entrada: Novos Criados (`#d11-created`). Drill-down: `d11_created`.
  * Card Saída Humana: Resolvidos Manualmente (`#d11-manual`). Drill-down: `d11_manual`.
  * Card Saída Automática: Resolvidos por Inatividade de 3 dias (`#d11-inactivity`). Drill-down: `d11_inactivity`.
  * Card Saldo Líquido: Variação de estoque (`#d11-balance-val`). Drill-down: `d11_balance`.
  * Barra empilhada proporcional: Trabalho Efetivo Humano vs Limpeza por Inatividade.

### Grupo 4: Bloco C — Turno da Agente (D-13 a D-16)
*Fonte: RPC `suporteapp_rpc_daily_shift_metrics`.*
* **`C-01` (Card D-13):** Latência de Abertura (Minutos até a 1ª resposta humana após as 09:00 BRT). Drill-down: `d13`.
* **`C-02` (Card D-14):** Fila Herdada & Zeragem (Estoque às 09:00 e tempo decorrido para zerar em horas). Drill-down: `d14`.
* **`C-03` (Card D-15):** Horário do Último Envio (Timestamp da última resposta enviada antes das 18:00 BRT). Drill-down: `d15`.
* **`C-04` (Card D-16):** Maior Hiato Ocioso (Maior pausa durante o expediente com fila ativa). Drill-down: `d16`.

### Grupo 5: Bloco D — Desempenho do Bot e IA (D-17)
*Fonte: RPC `suporteapp_rpc_bot_metrics`.*
* **`D-01` (Card D-17 Total):** Atendidos pelo Bot (Total de conversas com interação automatizada). Drill-down: `d17_total`.
* **`D-02` (Card D-17 Contenção):** Taxa de Contenção Bot (% resolvidas 100% pelo bot sem intervenção humana). Drill-down: `d17_containment`.
* **`D-03` (Card D-17 Transbordo):** Transbordo p/ Humano (% que exigiram atendente da equipe). Drill-down: `d17_handover`.
* **`D-04` (Card D-17 Herdada):** Fila Herdada do Bot (Clientes noturnos do bot aguardando na fila das 09:00). Drill-down: `d17_inherited`.

### Grupo 6: Parte 3 — Relatório Semanal de Suporte (RS-01 a RS-14 Integral)
* **`E-01` (Card Topo RS-12):** Contestações de Relatório & Falso Negativo (RPC `suporteapp_rpc_contest_and_false_negative`). Drill-down: `rs12`.
* **`E-02` (Tabela/Heatmap RS-01):** Volume Semanal & Mapa de Calor 7x24 (RPC `suporteapp_rpc_weekly_heatmap`). Drill-down: `rs01`.
* **`E-03` (Tabela RS-02):** Concentração de Assuntos por Motivo (RPC `suporteapp_rpc_weekly_reasons` - 6 colunas, com categorias `(ausente)` e `(múltiplo)` no topo). Drill-down: `rs02`.
* **`E-04` (Tabela RS-03):** Matriz Cruzada Motivo vs Severidade (RPC `suporteapp_rpc_reason_severity_matrix` - auditoria P0, P1, P2-P3). Drill-down: `rs03`.
* **`E-05` (Tabela RS-04):** Espera Atendível vs Espera Corrida (RPC `suporteapp_rpc_turn_metrics` - Média, Mediana, P90, Meta <= 10m). Drill-down: `rs04`.
* **`E-06` (Tabela RS-05):** Decomposição de Resolução e Reaberturas (RPCs `suporteapp_rpc_resolution_breakdown` e `suporteapp_rpc_reopen_count`). Drill-down: `rs05`.
* **`E-07` (Gráfico de Barras RS-06):** Distribuição de Espera: Evitável vs Estrutural (RPC `suporteapp_rpc_avoidable_vs_structural`). Drill-down: `rs06`.
* **`E-08` (Cards RS-07):** Balanço de Estoque Carregado (RPC `suporteapp_rpc_carried_stock` - Abertura, Carregadas, > 7 dias). Drill-down: `rs07`.
* **`E-09` (Painel RS-08):** Painel de Alarmes Executivos (RPC `suporteapp_rpc_alarm_panel` - 4 quadrantes de inconformidade operacional). Drill-down: `rs08`.
* **`E-10` (Tabela RS-09):** Handoff Externo por Área (RPC `suporteapp_rpc_weekly_handoff`). Drill-down: `rs09`.
* **`E-11` (Tabela RS-10):** Resolvidas em 1 Toque - FCR (RPC `suporteapp_rpc_first_contact_resolution`). Drill-down: `rs10`.
* **`E-12` (Cards RS-11):** Taxa de Reincidência 7d e 30d (RPC `suporteapp_rpc_recurrence_rate`). Drill-down: `rs11`.
* **`E-13` (Tabela RS-13):** Consolidação do Bot & Fila de Expansão Whitelist (RPC `suporteapp_rpc_bot_handover_top_subjects`). Drill-down: `rs13`.
* **`E-14` (Formulário RS-14):** Notas da Reunião de Suporte & Diagnóstico Qualitativo (Persistência segura em `localStorage`).

### Grupo 7: Modal de Drill-Down e Auditoria de Tickets
* **`M-01` a `M-18`:** Auditoria dos 18 modos de abertura do modal de inspeção granular, verificando se os filtros de consulta REST sobre `suporteapp_tickets` e a filtragem em memória coincidem exatamente com a lógica das RPCs correspondentes, exibem links diretos para o Chatwoot (`https://app.digi2b.com/app/accounts/88/conversations/...`) e tratam status de fila corretamente.

---

## 3. Metodologia do Execution Loop para Esta Auditoria

A execução do loop seguirá a disciplina de 5 fases de `execution-loop/SKILL.md`:
1. **00 Brainstorm (este documento):** Delimitação do escopo, identificação de todos os 47 pontos e definição dos 4 eixos de teste.
2. **01 Espec:** Especificação técnica detalhada de cada ponto, suas regras matemáticas, fontes de verdade no banco, comportamento esperado sob filtros e uma **Rubrica de QA com 10 itens agrupados (pontuação 0 a 10 cada)**.
3. **02 Plan:** Roteiro sequencial de inspeção de código, execução de scripts de teste, testes de consulta às RPCs e simulação de filtros.
4. **03 Execução:** Registro detalhado de cada teste executado, comandos rodados, inspeções nas 12 migrações SQL e no frontend, com apontamento de eventuais bugs ou discrepâncias encontradas.
5. **04 QA:** Avaliação formal de cada item da Rubrica com evidências concretas (output de scripts, diffs, testes de API). Qualquer nota < 10 dispara imediatamente a fase de Debug.
