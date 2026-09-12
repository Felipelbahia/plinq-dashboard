# 03 Execução · Revisão de Layout (Seletor de Datas & Tooltips Estruturados nos Indicadores)

> **Ciclo:** 1 · Fase 03 (Execução)  
> **Metodologia:** Execution Loop (`execution-loop/SKILL.md` + `executing-plans/SKILL.md`)  
> **Skills Aplicadas:** `frontend-design`, `clean-code`

---

## Resumo das Modificações Realizadas

### 1. Estilização CSS Dark Mode Glassmorphism (`src/styles.css`)
- **Seletor de Período e Popover:**
  - `.date-picker-group`: Container relativo estável na barra de filtros.
  - `.date-picker-trigger`: Botão gatilho com ícone de calendário, texto dinâmico e chevron animado (`rotate(180deg)`).
  - `.date-picker-panel`: Painel flutuante com `backdrop-filter: blur(16px)`, animação `popoverFadeIn` e sombra profunda.
  - `.date-preset-grid` e `.date-preset-chip`: Grade 2x4 de atalhos rápidos com efeito neon no chip `.active`.
  - `.date-custom-panel` e `.date-custom-apply-btn`: Painel de intervalo personalizado com inputs escuros e botão de aplicação com gradiente ciano/azul.
  - `.date-panel-footer`: Rodapé informativo com indicação do fuso `America/Sao_Paulo` (BRT) e atalho para restaurar o padrão "Hoje".
- **Tooltips Estruturados dos Indicadores:**
  - `.card-label-wrap`: Wrapper flexível para título e botão de ajuda.
  - `.metric-tooltip-wrapper` e `.metric-info-btn`: Botão circular discreto com ícone `(i)` SVG e foco/hover acessível.
  - `.tooltip-bubble`: Balão flutuante estilizado com `backdrop-filter: blur(14px)`, `z-index: 500`, transição suave de opacidade e posicionamento inteligente (alinhamento à direita automático para cards nas extremidades).
  - `.tooltip-header`, `.tooltip-section`, `.tooltip-label`, `.tooltip-desc`, `.tooltip-meta`: Tipografia estruturada para os tópicos "O que mede", "Cálculo & Fuso" e "Meta / Benchmark".

### 2. Estrutura HTML da Barra e Cards (`index.html`)
- **Novo Barramento de Filtro de Data:**
  - Remoção do `<select id="filter-period">` nativo e do `#filter-date-range-group` adjacente que empurrava outros filtros.
  - Inclusão do componente integrado `#date-picker-group` com atalhos rápidos e formulário customizado com botão "Aplicar Intervalo".
- **Tooltips Pedagógicos nos Cards:**
  - Inseridos botões `(i)` com balões informativos estruturados em todos os cards:
    - **Bloco A:** D-01 (Fila Plinq), D-02 (Aguardando Usuária), D-03 (Alerta Red > 10m), D-05 (Sem Atendimento), D-06 (Adesão Taxonomia), D-04 (Envelhecimento da Fila).
    - **Bloco B:** D-07 (Volume Novas), D-09 (Meta 10 min), D-08 Mediana (1ª Resposta), D-08 P90 (1ª Resposta), D-10 (Respostas Seguintes), D-12 (Fora da Janela), D-11 (Balanço Entrada vs Saída).
    - **Bloco C:** D-13 (Latência de Abertura), D-14 (Fila Herdada & Zeragem), D-15 (Horário Último Envio), D-16 (Maior Hiato Ocioso).
    - **Bloco D:** D-17 Total (Atendidos Bot), D-17 Contenção, D-17 Transbordo, D-17 Fila Herdada.
  - Adicionado `onclick="event.stopPropagation()"` no container do tooltip para blindar contra abertura acidental do modal de drilldown nos cards clicáveis.

### 3. Lógica JavaScript de Datas no Fuso BRT (`src/dashboard.js`)
- Implementadas as funções utilitárias:
  - `getBrtTodayDate()`: Determina ano, mês e dia com precisão no fuso oficial de Brasília (`America/Sao_Paulo`).
  - `toIsoDate(d)`: Converte data para formato ISO `YYYY-MM-DD`.
  - `formatDateBR(isoStr)` e `formatDateBRShort(isoStr)`: Formatação padrão brasileira `DD/MM/AAAA` e `DD/MM`.
- Implementados os controladores do Date Picker:
  - `toggleDatePicker(evt)` e `closeDatePicker()`: Gerencia exibição do popover, com fechamento ao clicar fora ou teclar `Escape`.
  - `selectPreset(presetKey)`: Calcula o intervalo correto para os 8 presets (*today*, *yesterday*, *this_week*, *last_week*, *7d*, *30d*, *this_month*, *last_month*), atualiza o rótulo do trigger, atualiza os badges dos blocos B, C, D e P3 e executa `updateDashboard()`.
  - `validateCustomDateInputs()` e `applyCustomDateRange()`: Validação estrita (impede data inicial > final) e disparo sob demanda no clique em "Aplicar Intervalo".
  - `updatePeriodBadges(label)`: Sincroniza o texto resolvido em todos os badges de seção.
  - `dateRangeParams()`: Envia `p_date_start` e `p_date_end` para o backend Supabase sempre que houver datas resolvidas.
  - `DOMContentLoaded`: Inicializa `max` dos inputs de data na data de hoje e formata o gatilho inicial com a data do dia.

### 4. Reforço de Segurança no Build (`scripts/generate-config.js`)
- Criada função `isSecretKey` para inspecionar tanto `process.env.SUPABASE_ANON_KEY` quanto `process.env.SUPABASE_KEY`, impedindo que qualquer chave confidencial (`sb_secret_`, `service_role`, `sbp_`) seja introduzida inadvertidamente no frontend.

---

## Evidências de Validação

### Teste de Segurança e Pentest
```bash
npm run test:security
```
**Resultado:**
- Total de testes executados: 30
- Sucessos (Mitigações ativas): 30
- Falhas de segurança: 0
- Código de saída: 0 (`[✅ PASS]` em todas as 6 suítes).

### Build Estático
```bash
npm run build
```
**Resultado:**
- `config.js` gerado com sucesso sem vazamento de segredos.
- Código de saída: 0.
