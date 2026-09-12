# 05 Debug · Resolução do Gap de Auditabilidade no Modal de Drill-Down

> **Ciclo:** 1 · Fase 05 (Debug)  
> **Especialistas:** `@backend-specialist` & `@frontend-specialist`  
> **Metodologia:** Systematic Debugging (`systematic-debugging/SKILL.md`)  
> **Item Alvo:** Item 9 da Rubrica de QA (Auditabilidade e Alinhamento do Modal Drill-Down) — Nota anterior: 6/10.

---

## 1. Hipótese de Causa-Raiz (Root-Cause Analysis)

A função `openDrilldownModal(type)` em `src/dashboard.js` foi originalmente concebida como uma listagem genérica dos últimos 200 tickets (`suporteapp_tickets?order=created_at.desc&limit=200`) e repassava apenas 4 parâmetros simples para a REST API (`inbox_id`, `priority`, `agent_id`, `team_id`).

Com a evolução das regras de negócio do Dashboard (migração de multi-selects, 10 filtros globais simultâneos, janela de período dinâmica com presets e separação estrita de resoluções manuais vs inatividade), o modal ficou defasado em relação às RPCs:

1. **Falta de Recorte de Data:** Chamados exibidos nos blocos temporais (B e RS) não tinham a data de início e fim aplicadas no modal. Exemplo: um gestor vendo "Entradas de Hoje" (D-07 = 4 tickets) abria o modal e via até 200 tickets de dias anteriores misturados.
2. **Ausência dos 6 Novos Filtros:** As escolhas feitas nos filtros de Tags, Origem (Humano/Bot), Taxonomia (Válida/Ausente), Início Fora de Expediente e Fim de Semana não eram repassadas nem filtradas em memória no modal.
3. **Cálculo Distorcido de Espera para Chamados Resolvidos:** O modal calculava `new Date() - createdDate`. Para tickets abertos, isso reflete o tempo decorrido até agora; porém, para tickets resolvidos há dias ou semanas, o cálculo continuava somando o tempo até o segundo atual, mostrando valores bizarros de "140h 25m" para tickets que foram atendidos em 5 minutos.
4. **Alinhamento Estrito do D-03 (Alerta Red > 10m):** O modal trazia qualquer chamado P0 aberto, sem verificar se a última mensagem era da cliente (`waiting_plinq`) e se o hiato sem resposta já ultrapassava 10 minutos (que é o gatilho real do alarme).

---

## 2. Decisões de Correção para o Ciclo 2

1. **Injeção do Intervalo Temporal Ativo:**
   - Obter os limites `[startDate, endDate]` correspondentes a `currentFilters.period`, `currentFilters.dateStart` e `currentFilters.dateEnd`.
   - Para métricas de criação de conversas (D-07, D-08, D-09, D-10, D-11_created, D-12, RS-01, RS-02, RS-03, RS-06, RS-09, RS-12), filtrar `t.created_at >= startDate && t.created_at < endDate`.
   - Para métricas de resolução de conversas (D-11_manual, D-11_inactivity, D-11_balance, RS-05, RS-10), filtrar `t.resolved_at >= startDate && t.resolved_at < endDate`.
   - Para métricas de Fila Viva (Bloco A: D-01, D-02, D-03, D-04, D-05, D-06), manter a regra temporal viva (`status = 'open'`), sem filtro de data de criação.

2. **Aplicação Completa dos Filtros no Frontend do Modal:**
   - Adicionar filtros em memória para:
     - `tags`: verificar se `t.current_labels` intersecta as tags selecionadas (ou `cardinality = 0` se `__sem_tag__`).
     - `origin`: verificar `t.current_agent_id` (humano vs bot).
     - `taxonomy`: verificar conformidade das 2 tags oficiais (Severidade + Motivo).
     - `business_hours`: verificar se `created_at` caiu em horário comercial BRT (09h-18h seg a sex).
     - `weekend`: verificar se `created_at` caiu na janela de fim de semana (sex 18h a seg 09h).

3. **Cálculo Fiel de Espera e Atendimento:**
   - Se o chamado está **resolvido** (`status === 'resolved'`), a espera exibida é o tempo até a 1ª resposta pública (`first_public_reply_at - created_at`) ou o tempo até a resolução (`resolved_at - created_at`).
   - Se o chamado está **aberto**, a espera exibida é calculada a partir de `last_customer_message_at || created_at`.

4. **Alinhamento Rigoroso de D-03 e D-05:**
   - D-03: filtrar `t.status === 'open' && t.queue_state === 'waiting_plinq' && (t.priority === 'P0' || t.current_labels?.includes('sev-red')) && waitMin > 10`.
   - D-05: filtrar `t.status === 'open' && t.queue_state === 'waiting_plinq' && !t.last_agent_message_at`.

Essa especificação de correção alimenta o **Ciclo 2**, que inicia em `06 Espec.md` (com a rubrica reavaliada).
