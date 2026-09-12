# 07 Plan · Implementação e Validação do Drill-Down Alinhado (Ciclo 2)

> **Ciclo:** 2 · Fase 07 (Plan)  
> **Metodologia:** Execution Loop (`execution-loop/SKILL.md` + `plan-writing/SKILL.md`)  
> **Alvo:** Fechar o Item 9 da Rubrica em 10/10

---

## 1. Etapas Técnicas de Modificação

### Etapa 1: Helper de Intervalo de Datas Ativo (`getActiveDateRange`)
- Criar a função `getActiveDateRange()` em `src/dashboard.js`.
- Se `currentFilters.dateStart` e `dateEnd` estiverem presentes, resolver `[YYYY-MM-DDT00:00:00-03:00, (dateEnd + 1)T00:00:00-03:00]`.
- Se for preset `'today'`, resolver início de hoje às 00:00:00 BRT até agora.
- Se for `'7d'` ou `'30d'`, subtrair 7 ou 30 dias de agora.

### Etapa 2: Refatoração de `openDrilldownModal(type)` em `src/dashboard.js`
- Adicionar filtragem em memória para os 6 filtros adicionais:
  - Tags (`msGetParam('tag')`): verificar se o chamado possui a tag ou se tem 0 tags quando `'__sem_tag__'`.
  - Origem (`msGetParam('origin')`): verificar se `current_agent_id` é bot ou humano.
  - Taxonomia (`msGetParam('taxonomy')`): verificar se possui as duas tags obrigatórias.
  - Início fora de expediente (`filter-business-hours`): verificar se `created_at` caiu fora de 09h-18h seg a sex.
  - Fim de semana (`filter-weekend`): verificar se `created_at` caiu entre sexta 18h e segunda 09h.
- Para métricas de período, filtrar por data:
  - Criação de tickets (`t.created_at >= range.start && t.created_at < range.end`) para D-07 a D-10, D-11_created, D-12, RS-01 a RS-04, RS-06, RS-09, RS-12.
  - Resolução de tickets (`t.resolved_at >= range.start && t.resolved_at < range.end`) para D-11_manual, D-11_inactivity, RS-05, RS-10.
  - Manter fila viva (sem restrição de data de criação) para D-01 a D-06.

### Etapa 3: Correção do Cálculo da Coluna de Espera
- Se `t.status === 'resolved'`:
  - Se `t.first_public_reply_at`: tempo de espera = `t.first_public_reply_at - t.created_at` (Tempo até 1ª Resposta).
  - Senão: tempo até resolução = `t.resolved_at - t.created_at`.
- Se `t.status === 'open'`:
  - Tempo de fila = `NOW() - (t.last_customer_message_at || t.created_at)`.

### Etapa 4: Alinhamento Estrito do D-03
- Filtrar `t.status === 'open' && t.queue_state === 'waiting_plinq' && (t.priority === 'P0' || t.current_labels?.includes('sev-red')) && waitMinutes > 10`.

### Etapa 5: Validação e Testes
- Executar `npm run test:security` para confirmar conformidade de build e segurança.
- Executar script de teste automatizado de drilldown.
- Documentar em `08 Execução.md` e avaliar em `09 QA.md`.
