# Revisão de Layout: Seletor de Datas & Tooltips Estruturados nos Indicadores

Modernização da experiência de filtros temporais e da documentação inline das métricas do **Dashboard de Suporte Plinq v3.0**.

## User Review Required

> [!IMPORTANT]
> - O seletor de período anterior (`<select>` nativo que expandia campos de data inline na barra) será substituído por um **Trigger Unificado com Popover Flutuante** contendo atalhos rápidos (*Hoje*, *Ontem*, *Esta Semana*, *Semana Passada*, *Últimos 7 Dias*, *Últimos 30 Dias*, *Este Mês*, *Mês Anterior*) e área de intervalo customizado com botão "Aplicar".
> - Todos os indicadores analíticos (cards D-01 a D-12, C-01 a C-03, RS-02, RS-04) receberão um ícone informativo circular `(i)` com balão de tooltip estruturado contendo: **O que mede**, **Cálculo & Fuso** (evidenciando horário comercial 09h-18h BRT vs corrido 24x7) e **Meta / Benchmark**.
> - Nenhuma migração DDL no banco é necessária: o backend Supabase já possui suporte a `p_date_start` e `p_date_end` via `suporteapp_fn_resolve_period_range`.

## Proposed Changes

### 1. Interface & Estilos CSS
#### [MODIFY] [src/styles.css](file:///Users/macbookpro/Documents/Plinq/Code/Chamados%20APP/Projeto%20Dashboard/Dashboard/src/styles.css)
- Adicionar estilos para o componente `.date-picker-popover`, botão gatilho `.date-picker-trigger`, painel flutuante `.date-picker-panel`, grid de atalhos `.date-preset-grid` e chips `.date-preset-chip`.
- Estilizar o painel de intervalo customizado `.date-custom-panel`, inputs Dark Mode e botão `.date-apply-btn`.
- Criar o sistema de tooltips: `.metric-tooltip-container`, `.metric-info-btn`, balão `.tooltip-bubble` com micro-animação de fade/slide e tipografia para `.tooltip-title`, `.tooltip-label` e `.tooltip-value`.

### 2. Estrutura HTML
#### [MODIFY] [index.html](file:///Users/macbookpro/Documents/Plinq/Code/Chamados%20APP/Projeto%20Dashboard/Dashboard/index.html)
- Substituir o `<select id="filter-period">` e `#filter-date-range-group` pelo novo componente integrado `#date-picker-group`.
- Inserir os botões de informação `(i)` com tooltip estruturado nos cabeçalhos de todos os cards de métricas (D-01 a D-12, C-01 a C-03, RS-02, RS-04) com `onclick="event.stopPropagation()"`.

### 3. Lógica JavaScript
#### [MODIFY] [src/dashboard.js](file:///Users/macbookpro/Documents/Plinq/Code/Chamados%20APP/Projeto%20Dashboard/Dashboard/src/dashboard.js)
- Implementar as funções de cálculo de datas para os 8 presets estratégicos utilizando o fuso de Brasília (`America/Sao_Paulo`).
- Controlar o ciclo de vida do popover de data (abrir, fechar ao clicar fora, fechar ao teclar Esc).
- Validar datas no modo customizado e habilitar o botão "Aplicar Intervalo".
- Atualizar a formatação dos badges de período nos blocos B, C, D e P3 para exibir o intervalo legível exato (ex: `01/09 a 11/09/2026`).

---

## Verification Plan

### Automated Tests
- Executar a suíte de auditoria e testes de segurança:
  ```bash
  npm run test:security
  ```
- Validar build estático:
  ```bash
  npm run build
  ```

### Manual Verification
1. **Teste dos Presets:** Clicar em cada um dos atalhos rápidos (*Hoje*, *Ontem*, *Esta Semana*, *Semana Passada*, *Últimos 7 Dias*, *Últimos 30 Dias*, *Este Mês*, *Mês Anterior*) e verificar se a barra de filtros permanece estável, se o trigger exibe o período resolvido e se os cards e badges do dashboard atualizam.
2. **Teste de Intervalo Customizado:** Informar uma data inicial e final válidas e clicar em "Aplicar Intervalo". Testar também validação com data inicial maior que final.
3. **Teste dos Tooltips:** Passar o mouse e navegar via teclado pelos ícones `(i)` dos cards D-01 a D-12 e C-01 a C-03, verificando a renderização correta das 3 seções do tooltip.
4. **Proteção de Clique:** Clicar nos ícones `(i)` de cards interativos (como D-01 e D-03) e garantir que o modal de drilldown não é disparado.
