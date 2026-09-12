# Plano de Auditoria Integral de Métricas, Gráficos e Filtros

> **Tarefa:** Auditoria completa e profunda de cada um dos 47 componentes, gráficos e filtros do Dashboard de Suporte Plinq v3.0, com validação de dados, integridade de filtros, detecção de bugs e auditabilidade total.  
> **Metodologia:** `execution-loop` (Espec → Plan → Execução → QA 10/10 → Debug se necessário).

---

## 1. Escopo e Objetivos
1. **Inventário Completo**: Mapear 1 a 1 todos os componentes do Dashboard (47 itens identificados).
2. **Validação Factual de Dados**: Verificar contratos de retorno das 16 RPCs analíticas do Supabase.
3. **Influência dos 10 Filtros Globais**: Testar impacto de Inboxes, Prioridade, Agente, Time, Período, Horário Comercial, Fim de Semana, Tags (incluindo `__sem_tag__`), Origem (bot/human) e Taxonomia (valid/missing).
4. **Auditabilidade de Ponta a Ponta**: Garantir que o modal de drill-down replique fielmente o recorte analítico e apresente tempos de espera corretos.
5. **Segurança e Isolamento**: Garantir que a aplicação opere exclusivamente em modo Read-Only, sem vazamento de chaves ou permissão de escrita.

---

## 2. Etapas do Plano de Execução
- **Fase 1: Mapeamento e Espec (00 Brainstorm, 01 Espec, 02 Plan)**:
  - Elaborar taxonomia e matriz dos 47 itens.
  - Definir rubrica rigorosa de 10 itens com nota mínima 10/10.
- **Fase 2: Execução de Testes Automatizados (03 Execução)**:
  - Criar e rodar bateria de 30 testes de pentest/RLS (`npm run test:security`).
  - Criar e rodar bateria de 60 verificações técnicas de RPCs e filtros (`scripts/audit-all-dash-components.js`).
- **Fase 3: Avaliação de QA Ciclo 1 (04 QA)**:
  - Identificação de gap no drilldown (nota 6/10 no Item 9) -> Acionamento do Debug.
- **Fase 4: Resolução de Gargalo (05 Debug, 06 Espec, 07 Plan)**:
  - Análise de causa-raiz da falta de recorte temporal e filtros combinados no modal.
- **Fase 5: Implementação e Validação Ciclo 2 (08 Execução, 09 QA)**:
  - Inclusão de `getActiveDateRange()` e scoping de 10 filtros em `src/dashboard.js`.
  - Testes unitários com `scripts/test-drilldown-logic.js`.
  - Reavaliação e aprovação final com 10/10.
