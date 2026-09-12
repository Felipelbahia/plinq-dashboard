# 00 Brainstorm · Revisão de Layout (Seletor de Datas & Tooltips Estruturados nos Indicadores)

> **Data de Início:** 11/09/2026  
> **Ciclo:** 1 · Fase 00 (Brainstorming)  
> **Especialistas:** `@orchestrator` & `@frontend-specialist`  
> **Metodologia:** Execution Loop (`execution-loop/SKILL.md`)

---

## 1. Contexto e Motivação

O Dashboard de Suporte Plinq v3.0 possui uma barra de 9 filtros globais e dezenas de cards de métricas operacionais com regras de negócio sofisticadas (janela comercial de 09h às 18h BRT, feriados via calendário, SLA de primeiro turno, volumetria diária).

Dois gargalos de experiência de uso (UX) e design foram identificados:
1. **Aspecto da Data no Barramento de Filtros:** O seletor de período anterior utilizava um `<select>` nativo com apenas 4 opções genéricas. Ao selecionar "Personalizado", dois campos `<input type="date">` eram inseridos diretamente no fluxo flexbox da barra, empurrando os outros 8 filtros (`Caixa`, `Agente`, `Time`, `Severidade`, etc.), quebrando a estabilidade do layout e disparando consultas com intervalos incompletos.
2. **Falta de Clareza Pedagógica nos Indicadores:** Usuários e gestores precisam saber rapidamente a regra por trás de cada métrica (se considera horário corrido 24x7 ou horário útil comercial BRT, qual é a fórmula e qual a meta). Não existia nenhum mecanismo de ajuda contextual inline nos cards.

---

## 2. Decisões de Design e UX Alinhadas

### 2.1 Novo Seletor de Período (Abordagem 1: Trigger Unificado + Popover Flutuante)
* **Trigger Estável:** Um botão estilizado no padrão dos multiselects (`[ 📅 Hoje (11/09) ▾ ]`) que mantém largura previsível e não quebra a barra de filtros.
* **Painel Flutuante Glassmorphism:** Popover elegante com `backdrop-filter: blur(12px)`, fechamento automático ao clicar fora ou via tecla `Esc`.
* **Presets Estratégicos:**
  * *Diários:* **Hoje** (padrão), **Ontem** (D-1 fechado).
  * *Semanais:* **Esta Semana** (segunda até hoje), **Semana Passada** (segunda a domingo anterior), **Últimos 7 Dias** (D-7 até agora).
  * *Mensais:* **Este Mês** (dia 1º até hoje), **Mês Anterior** (mês fechado anterior), **Últimos 30 Dias** (D-30 até agora).
  * *Personalizado:* Abre área dedicada com data inicial e final.
* **Intervalo Customizado Seguro:**
  * Entradas de data com validação imediata (data inicial não pode ser superior à final; `max` fixado no dia atual).
  * Botão de confirmação **"Aplicar Intervalo"**, impedindo requisições ao Supabase antes do preenchimento completo.
* **Atualização Dinâmica dos Badges:** Os blocos B, C, D e P3 atualizam seus badges para exibir o intervalo legível exato (ex: `Período: 01/09 a 11/09/2026`).

### 2.2 Tooltips Estruturados com Ícone Circular `(i)` nos Indicadores
* **Localização:** Ícone discreto e polido `(i)` ao lado do título de cada indicador (`.card-label` dos cards D-01 a D-12, C-01 a C-03, RS-02, RS-04, etc.).
* **Estrutura do Conteúdo:**
  * **O que mede:** Descrição sem jargões do propósito do indicador.
  * **Cálculo & Fuso:** Indicação explícita se usa horário comercial (09:00–18:00 BRT seg a sex) ou corrido 24x7.
  * **Meta / Benchmark:** Alvo esperado pela operação Plinq (ex: `Meta < 10 min`, `Alerta Crítico P0`).
* **Proteção de Interação (`stopPropagation`):** O clique ou foco no ícone de tooltip não dispara a abertura do modal de drill-down do card pai.

---

## 3. Escopo e Limites

* **No Escopo:**
  * Refatoração do componente de data em `index.html` e `src/dashboard.js`.
  * Adição das regras de estilo CSS para o popover, presets e tooltips em `src/styles.css`.
  * Mapeamento do dicionário de metadados dos tooltips para todos os indicadores D-* e C-*.
  * Resolução precisa das datas no fuso de Brasília (`America/Sao_Paulo`).
* **Fora de Escopo:**
  * Mudanças de migrações DDL ou contratos de RPC no Supabase (o backend já possui suporte nativo a `p_date_start` e `p_date_end`).
  * Adição de bibliotecas externas pesadas (Flatpickr, Moment.js, etc.) — mantendo o princípio de Vanilla JS/CSS puro e leve.
