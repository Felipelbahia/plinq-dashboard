# 02 Plan · Revisão de Layout (Seletor de Datas & Tooltips Estruturados nos Indicadores)

> **Ciclo:** 1 · Fase 02 (Plan)  
> **Metodologia:** Execution Loop (`execution-loop/SKILL.md` + `plan-writing/SKILL.md`)  
> **Skills Aplicadas:** `frontend-design`, `clean-code`

---

## Goal

Modernizar a experiência de datas do Dashboard de Suporte Plinq com um seletor de período via popover flutuante (presets rápidos e intervalo seguro) e adicionar tooltips informativos estruturados com ícone circular `(i)` em todos os indicadores operacionais.

---

## Tasks

- [ ] **Task 1: Estilização CSS do Popover de Data e dos Tooltips**
  - Adicionar em `src/styles.css` os estilos Dark Mode Glassmorphism para `.date-picker-popover`, `.date-picker-trigger`, `.date-picker-panel`, `.date-preset-grid`, `.date-preset-chip`, `.date-custom-panel`, `.date-apply-btn`, e os estilos de `.metric-tooltip-container`, `.metric-info-btn`, `.tooltip-bubble`, `.tooltip-item`.
  - *Verify:* Inspecionar visualmente classes e garantir ausência de conflitos de z-index ou overflow.

- [ ] **Task 2: Refatoração do Seletor de Data no HTML**
  - Em `index.html`, substituir o `<select id="filter-period">` e `#filter-date-range-group` pelo novo componente integrado `#date-picker-group` com trigger button, grid de presets rápidos e formulário de intervalo customizado com botão "Aplicar Intervalo".
  - *Verify:* Verificar se a barra de filtros renderiza de forma estável, sem campos soltos empurrando outros filtros.

- [ ] **Task 3: Lógica JS do Seletor de Datas e Presets no Fuso BRT**
  - Em `src/dashboard.js`, implementar `handlePresetSelect(presetKey)`, `calculateDateRange(presetKey)` com fuso oficial de Brasília (`America/Sao_Paulo`), gerenciamento do popover (abrir/fechar/outside click/Esc), validação de datas e disparo de `updateDashboard()` com `p_period`, `p_date_start` e `p_date_end`.
  - *Verify:* Alternar entre presets (Hoje, Ontem, Esta Semana, etc.) e verificar se as RPCs do Supabase recebem os parâmetros esperados.

- [ ] **Task 4: Atualização Dinâmica dos Badges de Período**
  - Em `src/dashboard.js`, atualizar a função que atualiza os badges `period-badge-b`, `period-badge-c`, `period-badge-d` e `period-badge-p3` para formatar e exibir as datas legíveis (ex: `Período: 05/09 a 11/09/2026`).
  - *Verify:* Verificar o texto exibido nos 4 badges ao mudar de preset ou aplicar data customizada.

- [ ] **Task 5: Inclusão dos Ícones de Tooltip nos Indicadores**
  - Inserir os botões informativos `(i)` nos cabeçalhos dos cards D-01 a D-12, C-01 a C-03, RS-02, RS-04, etc., com o balão de tooltip estruturado contendo: **O que mede**, **Cálculo & Fuso** e **Meta / Benchmark**.
  - *Verify:* Passar o mouse e focar com teclado nos cards, checando alinhamento e clareza textual.

- [ ] **Task 6: Proteção de Eventos nos Cards Interativos**
  - Assegurar `onclick="event.stopPropagation()"` e controle de foco no ícone de informação para que inspecionar o tooltip nunca dispare o modal de drill-down.
  - *Verify:* Clicar deliberadamente no ícone `(i)` de um card interativo (ex: D-01 e D-03) e garantir que o modal permaneça fechado.

- [ ] **Task 7: Testes de Integridade, Segurança e Build**
  - Executar `npm run test:security` para validar que nenhuma chamada ou injeção foi comprometida, e verificar o build estático.
  - *Verify:* Suíte de segurança passando com 0 vulnerabilidades.

---

## Done When

- [ ] O seletor de período opera através do trigger unificado com popover flutuante e presets rápidos.
- [ ] O intervalo customizado valida datas e possui botão "Aplicar", sem deslocar a barra de filtros.
- [ ] Os badges dos blocos B, C, D e P3 exibem o intervalo real formatado.
- [ ] Todos os indicadores principais contam com ícone `(i)` e tooltip estruturado com 3 seções informativas.
- [ ] Clicar no ícone de informação não abre o drill-down dos cards interativos.
- [ ] Testes de segurança `npm run test:security` passam com 100% de sucesso.
