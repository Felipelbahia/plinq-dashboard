# Walkthrough: Revisão de Layout (Seletor de Datas & Tooltips Estruturados nos Indicadores)

Concluímos a revisão de layout do **Dashboard de Suporte Plinq v3.0** com foco no aspecto de datas e na clareza pedagógica das métricas operacionais, seguindo o rigor metodológico do **Execution Loop** (`execution-loop/SKILL.md`).

---

## 🚀 Principais Mudanças Implementadas

### 1. Novo Seletor de Período com Popover Flutuante & Glassmorphism
* **Trigger Estável:** Substituição do `<select>` nativo e dos campos soltos por um botão integrado na barra de filtros:
  ```html
  <div class="filter-group date-picker-group" id="date-picker-group">
    <button type="button" class="date-picker-trigger" onclick="toggleDatePicker(event)">
      <div class="trigger-content">
        <svg class="calendar-icon" ...></svg>
        <span id="date-picker-label">Últimos 30 Dias (12/08 a 11/09)</span>
      </div>
      <span class="chevron">▾</span>
    </button>
  ...
  ```
  Isso elimina qualquer deslocamento ou quebra de linha nos outros 8 filtros globais (`Caixa`, `Agente`, `Time`, `Severidade`, `Origem`, etc.).
* **8 Presets Rápidos:**
  * *Diários:* **Hoje**, **Ontem**
  * *Semanais:* **Esta Semana**, **Semana Passada**, **Últimos 7 Dias**
  * *Mensais:* **Este Mês**, **Mês Anterior**, **Últimos 30 Dias (Padrão Inicial)**
* **Intervalo Customizado Seguro:**
  * Campos de data inicial e final com validação em tempo real (`data inicial <= data final`).
  * Atributo `max` fixado no dia atual para impedir seleção acidental de datas futuras.
  * Botão de confirmação **"Aplicar Intervalo"**, impedindo o disparo de requisições com dados parciais.
* **Fuso Horário Oficial:** Cálculos padronizados no Horário de Brasília (`America/Sao_Paulo`) com indicação visual no rodapé do popover.
* **Sincronização dos Badges:** Os blocos B, C, D e P3 exibem o intervalo real formatado (ex: `Período: 12/08 a 11/09/2026`).

---

### 2. Tooltips Estruturados com Ícone Circular `(i)` nos Indicadores
Adicionado botão informativo com balão flutuante estilizado (Dark Mode Glassmorphism com `backdrop-filter: blur(14px)`) em todos os cards analíticos:
* **Bloco A:** D-01 (Fila Plinq), D-02 (Aguardando Usuária), D-03 (Alerta Red > 10m), D-05 (Sem Atendimento), D-06 (Adesão Taxonomia), D-04 (Envelhecimento da Fila).
* **Bloco B:** D-07 (Volume Novas), D-09 (Meta 10 min), D-08 Mediana (1ª Resposta), D-08 P90 (1ª Resposta), D-10 (Respostas Seguintes), D-12 (Demanda Fora da Janela), D-11 (Balanço Entrada vs Saída).
* **Bloco C:** D-13 (Latência de Abertura), D-14 (Fila Herdada & Zeragem), D-15 (Horário Último Envio), D-16 (Maior Hiato Ocioso).
* **Bloco D:** D-17 Total (Atendidos Bot), D-17 Contenção, D-17 Transbordo, D-17 Fila Herdada.

Cada tooltip contém 3 seções claras:
1. **O que mede:** Explicação funcional sem ambiguidades.
2. **Cálculo & Fuso:** Indicação explícita sobre a janela útil (09h às 18h BRT, seg a sex) vs corrido (24x7).
3. **Meta / Benchmark:** Metas oficiais operacionais da Plinq.

> [!TIP]
> **Isolamento de Eventos:** Todos os wrappers possuem `onclick="event.stopPropagation()"`. Interagir ou passar o mouse sobre o ícone de ajuda em cards clicáveis (como D-01 e D-03) **não abre** o modal de drilldown.

---

### 3. Caixas de Entrada Padrão & Header Fixo no Topo
* **Caixas de Entrada Marcadas por Padrão:**
  * Atualizado `DEFAULT_INBOX_IDS = [163, 164, 295, 296]` para incluir explicitamente:
    * `163`: `Plinq - Atendimento WhatsApp (Whatsapp)`
    * `295`: `Facebook - Plinq (FacebookPage)`
    * Além dos já configurados `Site - Plinq` (164) e `deumplinq` (296).
  * Canais técnicos (API de triagem) e institucionais internos permanecem desmarcados por padrão.
* **Header com Rolagem Natural:**
  * Configurado com `position: relative; z-index: 50;`.
  * Ao rolar a página para baixo, o menu e a barra de filtros desaparecem naturalmente com o fluxo do documento, liberando 100% da área visual da tela para focar nos gráficos, tabelas e cards analíticos.
* **Período Padrão Inicial (Últimos 30 Dias):**
  * Atualizado `currentFilters.period = '30d'` e `currentFilters.activePreset = '30d'`.
  * O seletor de período, os badges dos blocos B, C, D e o relatório da Parte 3 agora inicializam exibindo os dados consolidados dos **Últimos 30 Dias** por padrão.

---

### 4. Correção da Métrica D-08 (Mediana de 1ª Resposta Comercial)
* **Diagnóstico da Causa Raiz:**
  * No período de 30 dias, havia 137 chamados: 78 com 1ª resposta humana e 59 ainda sem resposta humana (`first_public_reply_at IS NULL`).
  * A função `suporteapp_fn_calculate_business_minutes` retornava `0` quando o fim era `NULL`.
  * A RPC `suporteapp_rpc_turn_metrics` calculava `PERCENTILE_CONT(0.50)` incluindo esses 59 registros zerados, puxando artificialmente a mediana da amostra para **0 min**.
* **Correção no Supabase (`sql/12_fix_d08_turn1_biz_minutes_null_reply.sql`):**
  * `turn1_biz_minutes` agora resulta em `NULL` quando `first_public_reply_at IS NULL`.
  * Adicionado `FILTER (WHERE first_public_reply_at IS NOT NULL)` nas agregações de média, mediana e P90.
* **Valores Reais Medidos e Validados:**
  * **D-08 Mediana 1ª Resposta:** de `0 min` ➔ **`14 min`** (14.31 min)
  * **D-08 P90 1ª Resposta:** de `92 min` ➔ **`158 min`** (2h38 min)
  * **Média Comercial (RS-04):** de `28 min` ➔ **`49 min`** (49.10 min)

---

## 🧪 Resultados dos Testes de Verificação

### 1. Bateria de Pentest e Segurança (`npm run test:security`)
```
Total de testes executados: 30
Sucessos (Mitigações ativas): 30
Falhas de segurança: 0
Status: 100% PASS
```

### 2. Build Estático (`npm run build`)
```
✅ [build] config.js gerado com sucesso!
ℹ️ [build] SUPABASE_URL: https://hqqzfccgkqdmhznwaxqj.supabase.co
ℹ️ [build] SUPABASE_KEY: [OCULTO] (sb_p...hc2Y)
Status: 100% PASS
```

### 3. Rubrica de Qualidade QA (`04 QA.md`)
* Todos os **7 critérios da rubrica** foram verificados e receberam **Nota 10/10**.
