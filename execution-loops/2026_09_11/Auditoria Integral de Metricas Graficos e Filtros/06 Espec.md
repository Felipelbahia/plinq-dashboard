# 06 Espec · Auditoria e Correção de Alinhamento do Modal de Drill-Down (Ciclo 2)

> **Ciclo:** 2 · Fase 06 (Espec)  
> **Metodologia:** Execution Loop (`execution-loop/SKILL.md` + `spec-writing/SKILL.md`)  
> **Skills Aplicadas:** `frontend-specialist`, `clean-code`, `qa-automation-engineer`

---

## Problem Statement

No Ciclo 1 da auditoria, as 16 RPCs do backend Supabase, o barramento de 10 filtros e a segurança RLS foram aprovados com 10/10. Porém, foi identificada uma defasagem crítica no componente de drill-down (`openDrilldownModal` em `src/dashboard.js`):
1. O modal não aplicava o recorte temporal ativo (datas inicial e final) aos chamados dos Blocos B e RS, misturando dados históricos ao auditar dias ou semanas específicas.
2. Os filtros de Tag, Origem (Humano/Bot), Taxonomia (Válida/Ausente), Horário comercial e Fim de semana não eram refletidos na lista de tickets do modal.
3. A coluna de espera calculava `new Date() - created_at` para todos os chamados, inclusive aqueles já resolvidos há dias, distorcendo os tempos de atendimento.
4. O alarme D-03 no modal incluía qualquer P0 aberto, mesmo os já respondidos ou abertos há menos de 10 minutos.

---

## Solution

Ajustar `openDrilldownModal(type)` e a função de renderização da tabela do modal em `src/dashboard.js` para:
1. **Resolver o Intervalo de Datas Ativo:** Criar helper `getActiveDateRange()` em JavaScript que espelhe a lógica de `suporteapp_fn_resolve_period_range` para o fuso `America/Sao_Paulo`.
2. **Filtrar por Intervalo Temporal Correto:**
   - Métricas baseadas em criação de ticket (D-07, D-08, D-09, D-10, D-11_created, D-12, RS-01, RS-02, RS-03, RS-06, RS-09, RS-12): filtrar `t.created_at >= v_start && t.created_at < v_end`.
   - Métricas baseadas em resolução (D-11_manual, D-11_inactivity, D-11_balance, RS-05, RS-10): filtrar `t.resolved_at >= v_start && t.resolved_at < v_end`.
   - Métricas de Fila Viva (D-01 a D-06): manter filtro exclusivo de fila aberta em tempo real (`status = 'open'`).
3. **Propagar os 10 Filtros ao Modal:**
   - Injetar no array em memória a filtragem de Tags selecionadas (ou `__sem_tag__`), Origem (humano vs bot), Taxonomia (com as 2 tags obrigatórias), Início fora de expediente e Início no fim de semana.
4. **Cálculo Realista de Espera:**
   - Para tickets resolvidos: calcular o tempo até a primeira resposta humana pública (`first_public_reply_at - created_at`) ou o tempo até a resolução (`resolved_at - created_at`).
   - Para tickets abertos: calcular tempo decorrido desde a última mensagem da cliente (`last_customer_message_at || created_at`).
5. **Alinhar Critério do D-03:**
   - Filtrar estritamente `t.status === 'open' && t.queue_state === 'waiting_plinq' && (t.priority === 'P0' || t.current_labels?.includes('sev-red')) && waitMinutes > 10`.

---

## Rubrica de Avaliação QA (Nota 0 a 10 por Item)

| # | Item da Rubrica | Critério de Aceite Estrito (10/10) |
|---|---|---|
| **1** | **Propagação dos 10 Filtros Globais** | Todos os 10 filtros são aceitos e aplicados corretamente por todas as RPCs sem erros de tipo. |
| **2** | **Integridade da Fila Agora (Bloco A: D-01 a D-06)** | Cards e histograma refletem o estado das conversas abertas com fuso e regras úteis. |
| **3** | **Precisão de Fluxo e Espera (Bloco B: D-07 a D-12)** | Entradas, medianas e P90 úteis em horário comercial calculados com precisão matemática. |
| **4** | **Consistência do Balanço de Vazão (D-11 & RS-05)** | Saídas decompostas com exatidão entre manual, inatividade e bot; saldo líquido exato. |
| **5** | **Turno da Agente e Métricas Diárias (Bloco C: D-13 a D-16)** | Latência às 09h, zeragem, fechamento às 18h e hiato ocioso com fila operam no fuso BRT. |
| **6** | **Desempenho de Bot e Automação (Bloco D: D-17 & RS-13)** | Total, contenção, transbordo e fila herdada calculados corretamente. |
| **7** | **Relatório Semanal de Suporte (RS-01 a RS-04, RS-06)** | Heatmap 7x24, motivos, matriz e espera atendível vs corrida com dados reais. |
| **8** | **Relatório Semanal de Suporte (RS-07 a RS-12, RS-14)** | Estoque, alarmes, handoffs, FCR, reincidência, contestações e notas qualitativas 100% funcionais. |
| **9** | **Auditabilidade e Alinhamento do Modal Drill-Down** | Todos os 18 fluxos de drilldown filtram datas e os 10 filtros ativos com precisão, tempo de espera não distorce tickets resolvidos e D-03 reflete estritamente o gatilho de alarme. |
| **10** | **Segurança, RLS e Resiliência Técnica** | Frontend somente-leitura, RLS ativo, ausência de dados fabricados e pentest 100% aprovado. |
