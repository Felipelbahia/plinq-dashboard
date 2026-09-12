# 01 Espec · Revisão de Layout (Seletor de Datas & Tooltips Estruturados nos Indicadores)

> **Ciclo:** 1 · Fase 01 (Espec)  
> **Metodologia:** Execution Loop (`execution-loop/SKILL.md` + `spec-writing/SKILL.md`)  
> **Skills Aplicadas:** `frontend-design`, `clean-code`

---

## Problem Statement

O usuário e os gestores do Dashboard de Suporte Plinq enfrentam dois atritos fundamentais na interface atual:
1. **Instabilidade e Rigidez no Filtro de Datas:** O seletor de período anterior utiliza um `<select>` nativo com opções limitadas ("Hoje", "7D", "30D", "Personalizado"). Ao selecionar "Personalizado", dois campos `<input type="date">` são inseridos na barra de filtros flexbox, empurrando os outros 8 filtros, quebrando o layout visual e disparando consultas com intervalos incompletos. Faltam também atalhos essenciais do dia a dia da operação, como "Ontem", "Esta Semana", "Semana Passada", "Este Mês" e "Mês Anterior".
2. **Opacidade Regulatória das Métricas nos Cards:** O dashboard calcula métricas críticas com regras específicas (ex: contagem estrita dentro do horário comercial de 09h às 18h BRT, exclusão de finais de semana e feriados, tempos de primeiro turno, volumetria por turno). Atualmente, os cards não possuem nenhuma indicação inline sobre o que medem, qual critério de fuso/janela útil utilizam ou qual a meta de conformidade da Plinq.

---

## Solution

1. **Componente de Período Integrado com Popover Flutuante:**
   - Um botão/trigger fixo e elegante na barra de filtros (`[ 📅 Período: Hoje (11/09) ▾ ]`) que não altera a largura da barra nem empurra os demais filtros.
   - Popover flutuante Dark Mode Glassmorphism com presets rápidos categorizados (*Hoje*, *Ontem*, *Esta Semana*, *Semana Passada*, *Últimos 7 Dias*, *Últimos 30 Dias*, *Este Mês*, *Mês Anterior*).
   - Área de intervalo customizado (De / Até) com validações em tempo real e botão explícito "Aplicar Intervalo", impedindo consultas com datas parciais ou inválidas.
   - Sincronização automática dos badges de período nos Blocos B, C, D e P3 exibindo o intervalo amigável real (ex: `Período: 01/09 a 11/09/2026`).
2. **Tooltips Estruturados nos Indicadores:**
   - Adição de ícone circular `(i)` ao lado do título de cada indicador (D-01 a D-12, C-01 a C-03, RS-02, RS-04, etc.).
   - Balão flutuante estilizado exibindo três tópicos claros: **O que mede**, **Cálculo & Fuso** (evidenciando dias úteis 09h-18h BRT vs corrido 24x7) e **Meta / Benchmark**.
   - Isolamento de clique (`stopPropagation`) para garantir que inspecionar a ajuda não dispare a abertura do modal de drill-down nos cards clicáveis.

---

## User Stories

1. **US-01 (Navegação Rápida):** Como gestor de suporte, quero selecionar períodos frequentes (ex: "Ontem" ou "Esta Semana") com apenas 1 clique em um preset, para auditar rapidamente fechamentos sem precisar digitar datas manualmente.
2. **US-02 (Estabilidade Visual da Barra):** Como usuário, quero abrir o seletor de data e digitar um intervalo personalizado sem que os outros 8 filtros da barra mudem de lugar ou quebrem de linha.
3. **US-03 (Prevenção de Consultas Quebradas):** Como usuário, quero que o dashboard só execute a consulta personalizada após eu definir a data inicial e final e clicar em "Aplicar", para evitar lentidão e consultas incompletas no banco.
4. **US-04 (Clareza do Período Ativo):** Como operador, quero ver claramente nos badges dos blocos B, C, D e P3 o intervalo exato de datas ativo (ex: `01/09 a 11/09/2026`), sabendo exatamente o recorte temporal analisado.
5. **US-05 (Contexto Educativo dos Indicadores):** Como novo atendente ou auditor, quero passar o mouse no ícone `(i)` de qualquer indicador (ex: D-08 ou D-04) e ler exatamente o que ele mede, se considera horário comercial e qual a meta Plinq, sem precisar consultar um manual externo.
6. **US-06 (Uso sem Interrupção nos Cards):** Como usuário, quero consultar a explicação de um indicador clicável (como D-01 ou D-03) sem que o modal de drill-down se abra acidentalmente.

---

## Implementation Decisions

1. **Tecnologia & Padrões:** Vanilla JS e CSS puro, sem adição de bibliotecas externas (respeitando as diretrizes de arquitetura do projeto e mantendo performance máxima).
2. **Componente de Data:**
   - HTML: Substituição do `<select id="filter-period">` por `<div class="filter-group date-picker-popover" id="date-picker-group">` contendo o trigger button e o painel `#date-picker-panel` flutuante.
   - JS: Cálculo exato dos intervalos no fuso horário de Brasília (`America/Sao_Paulo`). O backend Supabase (`suporteapp_fn_resolve_period_range`) já recebe `p_date_start` e `p_date_end` perfeitamente formatados (`YYYY-MM-DD`).
   - CSS: Classes `.date-picker-trigger`, `.date-picker-panel`, `.date-preset-chip`, `.date-custom-row`, `.date-apply-btn`.
3. **Componente de Tooltip:**
   - CSS: Classes `.metric-info-icon`, `.tooltip-bubble`, `.tooltip-title`, `.tooltip-section`.
   - Isolamento: `onclick="event.stopPropagation()"` e controle via CSS `:hover` / `:focus-visible` com acessibilidade para teclado.
   - Dicionário de Metadados: Um mapa centralizado em JavaScript (`METRIC_DESCRIPTIONS`) ou atributos `data-*` que injetam as informações de forma manutenível e limpa.

---

## Testing Decisions

- **Testes Manuais de Interação:**
  1. Alternar entre cada um dos presets (Hoje, Ontem, Esta Semana, Semana Passada, Últimos 7D, Últimos 30D, Este Mês, Mês Anterior) e verificar as chamadas de RPC e atualização dos badges.
  2. Testar seleção de data personalizada com validação de datas invertidas e verificação do botão "Aplicar".
  3. Passar o mouse e focar com teclado nos ícones `(i)` dos cards D-01 a D-12 e C-01 a C-03; clicar no ícone e confirmar que o drill-down modal NÃO abre.
- **Auditoria de Segurança:**
  - Executar a suíte de testes de penetração e integridade: `npm run test:security`.

---

## Out of Scope

- Alterações em migrações DDL ou procedures SQL no Supabase.
- Modificação na regra de negócio da janela comercial (09:00 às 18:00 BRT).
- Inclusão de frameworks externos (React, Vue, Tailwind, Moment.js).

---

## Rubrica de Avaliação QA (Nota 0 a 10)

| # | Item | Critério de Aceite |
|---|---|---|
| 1 | **Estabilidade da Barra de Filtros** | A barra de filtros mantém layout estável e consistente em qualquer seleção de período, sem quebras de linha abruptas causadas pelo seletor de data. |
| 2 | **Presets de Data Completos** | Presets rápidos funcionais para Hoje, Ontem, Esta Semana, Semana Passada, Últimos 7 Dias, Últimos 30 Dias, Este Mês e Mês Anterior. |
| 3 | **Intervalo Customizado com Botão Aplicar** | O intervalo customizado possui validação de data inicial <= final e só dispara consultas ao clicar em "Aplicar". |
| 4 | **Sincronização dos Badges de Período** | Os badges dos blocos B, C, D e P3 exibem o intervalo real resolvido em formato DD/MM/AAAA. |
| 5 | **Tooltips Estruturados nos Indicadores** | Todos os indicadores D-* e C-* possuem ícone circular `(i)` com tooltip exibindo "O que mede", "Cálculo & Fuso" e "Meta". |
| 6 | **Proteção de Eventos nos Cards Clicáveis** | Clicar ou interagir com o ícone de ajuda de um card interativo não abre o modal de drilldown. |
| 7 | **Integridade de Segurança e Build** | Build estático e testes de segurança (`npm run test:security`) executam com 100% de aprovação. |
