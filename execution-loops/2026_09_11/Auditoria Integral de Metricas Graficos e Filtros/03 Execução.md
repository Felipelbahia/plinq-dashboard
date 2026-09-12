# 03 Execução · Auditoria Integral de Métricas, Gráficos, Filtros e Auditabilidade

> **Ciclo:** 1 · Fase 03 (Execução)  
> **Metodologia:** Execution Loop (`execution-loop/SKILL.md` + `executing-plans/SKILL.md`)  
> **Evidências Coletadas:** Bateria automatizada de 60 verificações das RPCs, 30 testes de pentest/segurança, inspeção de 12 migrações SQL e revisão de código em `src/dashboard.js` e `index.html`.

---

## 1. Evidências de Execução dos Testes Automatizados

### 1.1 Suíte de Segurança e Invasão RLS (`npm run test:security`)
- **Comando:** `npm run test:security`
- **Resultado:** 30 testes executados, 30 aprovados (100% de sucesso).
- **Evidências:**
  - Bloqueio integral de INSERT/UPDATE/DELETE não autenticado em `suporteapp_tickets` e `suporteapp_weekly_reports` (HTTP 401).
  - Bloqueio de leitura de tabelas financeiras, staging de créditos e credenciais de usuários (RLS ativo retornando 0 registros ou HTTP 500).
  - Proteção contra injeção de SQL em parâmetros `p_period` e `p_severity`.
  - Trava de build em `scripts/generate-config.js` prevenindo vazamento de tokens privilegiados (`sb_secret_` ou `sbp_`).
  - Sanitização de XSS em `escapeHtml` com neutralização de tags maliciosas.

### 1.2 Bateria Automatizada de Verificação das 16 RPCs e Filtros (`scripts/audit-all-dash-components.js`)
- **Comando:** `node scripts/audit-all-dash-components.js`
- **Resultado:** 60 verificações executadas, 60 aprovadas (100% de sucesso).
- **Evidências:**
  - Todas as 16 RPCs respondem com HTTP 200 e estruturas JSON válidas sob o schema esperado.
  - O filtro de caixas de entrada (`p_inbox_ids`), agentes (`p_agent_ids`), times (`p_team_ids`), severidades (`p_severities`), tags (`p_tags`, incluindo `'__sem_tag__'`), horário comercial (`p_business_hours_filter`) e finais de semana (`p_weekend_filter`) executam sem erros de tipo no PostgreSQL.
  - Os cálculos de percentis e medianas retornam `null` ou valores numéricos contínuos em ponto flutuante, sem divisão por zero ou quebras.

---

## 2. Auditoria Ponto a Ponto dos 47 Itens do Dashboard

### Grupo 1: Barramento de Filtros Globais (F-01 a F-11)
- **F-01 (Período):** Seletor popover com 8 presets rápidos e De/Até customizado. A função `suporteapp_fn_resolve_period_range` calcula o intervalo no fuso de São Paulo com `range_end := (p_date_end + 1)` garantindo cobertura integral do dia final.
- **F-02 a F-08 (Multi-selects):** O motor genérico `msState` em `src/dashboard.js` manipula conjuntos `Set<string>`. Quando todos os itens estão marcados, `msGetParam(key)` retorna `null` (sem restrição); quando desmarca itens, envia array com os IDs/strings restantes. O SQL em `suporteapp_fn_scope_tickets` trata `p_param IS NULL OR col = ANY(p_param)`.
- **F-09 e F-10 (Horário & Fim de Semana):** Helpers SQL `suporteapp_fn_is_weekend_start` e `suporteapp_fn_get_atendivel_start` aplicam as regras de horário (09h-18h Seg-Sex e Sex 18h-Seg 09h).
- **F-11 (Header Live Status & Badge de Adesão):** Badge de topo ativado dinamicamente se a adesão geral à taxonomia for inferior a 95%.

### Grupo 2: Bloco A — Fila Agora (D-01 a D-06 e Gráfico D-04)
- **D-01 (Fila Plinq):** Contabiliza estritamente conversas abertas cuja última mensagem seja da cliente (`queue_state = 'waiting_plinq'`). Dados corretos.
- **D-02 (Aguardando Usuária):** Contabiliza conversas abertas onde a última mensagem partiu da equipe Plinq. Dados corretos.
- **D-03 (Alerta Red > 10 min):** Alerta visual e sonoro para chamados P0/`sev-red` com espera superior a 10 min.
- **D-05 (Sem Atendimento Nenhum):** Contabiliza conversas abertas na fila sem nenhum envio de agente (`last_agent_message_at IS NULL`).
- **D-06 (Adesão à Taxonomia):** Mede percentual de conversas com 2 tags obrigatórias (Severidade + Motivo).
- **D-04 (Histograma de Envelhecimento):** 5 faixas calculadas com base em `suporteapp_fn_calculate_business_minutes` em horário comercial BRT. Mediana e P90 calculados via `PERCENTILE_CONT(0.50)` e `PERCENTILE_CONT(0.90)`.

### Grupo 3: Bloco B — Fluxo de Chamados e Espera (D-07 a D-12 + RS-04)
- **D-07 (Entradas):** Contabiliza novas conversas criadas dentro do período selecionado.
- **D-08 (Mediana e P90 1ª Resposta):** Validada a migração `12_fix_d08_turn1_biz_minutes_null_reply.sql`. Chamados sem resposta humana (`first_public_reply_at IS NULL`) não geram `turn1_biz_minutes = 0`, evitando distorcer artificialmente a mediana para zero.
- **D-09 (Meta 10 min SLA):** Percentual calculado estritamente sobre chamados que receberam primeira resposta.
- **D-10 (Espera Turnos Seguintes):** Mediana calculada sobre os pares de réplica/tréplica em `suporteapp_v_response_pairs` para turnos > 1.
- **D-11 (Balanço Entrada vs Saída):** Decompõe saídas em `resolved_manual`, `resolved_inactivity` e `resolved_bot_auto`. O saldo líquido é matematicamente exato (`created - totalResolved`).
- **D-12 (Demanda Fora da Janela):** Identifica conversas iniciadas fora do expediente e contabiliza quantas eram de severidade Red (P0).
- **RS-04 (Espera Atendível vs Corrida):** Matriz 4x2 calculando média, mediana, P90 e percentual na meta comparando minutos úteis (biz) vs minutos corridos 24x7 (raw).

### Grupo 4: Bloco C — Turno da Agente (D-13 a D-16)
- **D-13 (Latência de Abertura):** Média em minutos entre 09:00:00 BRT e a primeira mensagem enviada por agente humano no dia.
- **D-14 (Fila Herdada & Zeragem):** Quantidade de chamados pendentes às 09:00 e tempo decorrido até a zeragem completa da fila herdada.
- **D-15 (Horário do Último Envio):** Timestamp médio do último envio humano antes das 18:00 BRT.
- **D-16 (Maior Hiato Ocioso):** Maior intervalo entre mensagens consecutivas de atendentes com fila aberta.

### Grupo 5: Bloco D — Desempenho do Bot e IA (D-17)
- **D-17 Total:** Conversas com interação de bot (`sender_type = 'bot'` ou agente bot).
- **D-17 Contenção:** Percentual de conversas resolvidas pelo bot que não sofreram transbordo para humanos.
- **D-17 Transbordo:** Percentual que exigiu direcionamento para fila humana via `suporteapp_v_transfers`.
- **D-17 Fila Herdada:** Conversas noturnas atendidas pelo bot e não resolvidas que aguardam na fila das 09:00.

### Grupo 6: Parte 3 — Relatório Semanal de Suporte (RS-01 a RS-14)
- **RS-12 (Contestações & Falso Negativo):** Bloco posicionado no topo executivo, contabilizando etiquetas `relatorio-contestado` e `falso-negativo`.
- **RS-01 (Mapa de Calor 7x24):** Tabela 7 dias x 7 faixas horárias com renderização em cores graduadas de intensidade (azul para dias úteis, laranja para fins de semana).
- **RS-02 (Concentração de Assuntos):** Classificação por motivos com colunas de volume, percentual, delta semanal, mediana de espera e mediana de resolução. Categorias `(ausente)` e `(múltiplo)` tratadas com prioridade.
- **RS-03 (Matriz Motivo vs Severidade):** Cruzamento em tabela de motivos com P0, P1, P2-P3 para auditoria de etiquetagem.
- **RS-05 (Decomposição de Resolução e Reaberturas):** Resoluções manuais vs encerramento por inatividade de 3 dias, além de contagem de reaberturas.
- **RS-06 (Espera Evitável vs Estrutural):** Gráfico de barras empilhadas decompondo tempo em janela comercial vs fora do expediente.
- **RS-07 (Balanço de Estoque Carregado):** Abertura, criadas, encerradas, carregadas e chamados com mais de 7 dias de idade.
- **RS-08 (Painel de Alarmes):** 4 quadrantes de alerta operacional (Sem Atendimento, Red Janela, Red Fora, Acima de 72h).
- **RS-09 (Handoff Externo):** Volume e mediana em dias para resoluções por áreas externas (Engenharia, Gabi, Mariana).
- **RS-10 (FCR - 1 Toque):** Percentual de chamados resolvidos com exatamente uma única mensagem de saída do atendente.
- **RS-11 (Taxa de Reincidência):** Percentual de clientes com mais de um chamado em 7 e 30 dias, e top motivo de retorno.
- **RS-13 (Top 5 Transbordo do Bot):** Lista dos 5 assuntos mais frequentes em que o bot precisou passar para a equipe.
- **RS-14 (Diagnóstico Qualitativo):** 3 campos de texto executivos com salvamento seguro no `localStorage` indexado por semana ISO.

---

## 3. Diagnóstico de Discrepâncias e Oportunidades de Correção (Bug Hunting & Auditabilidade)

A auditoria revelou **duas discrepâncias técnicas** na função `openDrilldownModal(type)` de `src/dashboard.js`:

1. **Desalinhamento Temporal no Drilldown dos Blocos B e RS:**
   - O modal de drilldown fazia `fetchView('suporteapp_tickets?select=*&order=created_at.desc&limit=200')` e passava apenas 4 filtros de query string (`chatwoot_inbox_id`, `priority`, `current_agent_id`, `current_team_id`).
   - Ele **não filtrava por data** (`created_at` ou `resolved_at` no intervalo ativo).
   - *Impacto:* Se o gestor estivesse com o preset "Hoje" selecionado e clicasse em D-07 (Entradas de Hoje) ou D-11 (Resolvidos de Hoje), o modal trazia chamados de até semanas atrás, quebrando a correspondência 1:1 entre o card e o modal.
2. **Cálculo da Coluna "Espera" no Modal:**
   - A coluna no cabeçalho diz `<th>Espera Atendível</th>`, mas o código em linha 1189 calculava `diffMin = (new Date() - createdDate)`, que é tempo corrido 24x7 desde a abertura até agora.
   - Para chamados **já resolvidos** (`status === 'resolved'`), o cálculo continuava somando o tempo até `new Date()`, fazendo chamados resolvidos dias atrás exibirem esperas de "120h" em vez do tempo em que o chamado foi de fato atendido/resolvido.
3. **Filtros de Tag, Origem, Taxonomia, Expediente e Fim de Semana no Drilldown:**
   - O modal não aplicava os novos filtros multi-seleção de Tags, Origem (Humano/Bot), Taxonomia (Válida/Ausente), Início Fora de Expediente e Fim de Semana, podendo exibir tickets que o usuário havia filtrado na barra superior.
