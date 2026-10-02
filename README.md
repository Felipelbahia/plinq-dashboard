# 📊 Plinq · Dashboard de Suporte & Relatório Executivo v3.0

[![Vercel Deployment](https://img.shields.io/badge/Vercel-Deployed-000000?style=for-the-badge&logo=vercel&logoColor=white)](https://vercel.com)
[![Supabase](https://img.shields.io/badge/Supabase-Database%20%26%20Realtime-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white)](https://supabase.com)
[![JavaScript](https://img.shields.io/badge/JavaScript-ES6%2B%20Vanilla-F7DF1E?style=for-the-badge&logo=javascript&logoColor=black)](https://developer.mozilla.org/pt-BR/docs/Web/JavaScript)
[![CSS3 Glassmorphism](https://img.shields.io/badge/CSS3-Dark%20Mode%20Glass-1572B6?style=for-the-badge&logo=css3&logoColor=white)](https://developer.mozilla.org/pt-BR/docs/Web/CSS)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge)](LICENSE)

> Aplicação web de **monitoramento em tempo real da operação de atendimento e suporte da Plinq**, desenvolvida sobre a Tríade (Chatwoot, Supabase e N8N). Conta com fila viva 24x7, barramento de filtros globais combinados, cálculo de espera atendível em janela comercial (09h às 18h BRT), métricas de CX (CSAT/NPS), taxonomia de etiquetas e pauta executiva semanal.


> **Atualização de 2026-10-02:** o dashboard agora lê **conversas** (id da conversa do Chatwoot), não tickets — e a **severidade é a prioridade nativa do Chatwoot** (Urgente/Alta/Média/Baixa/Nenhuma). Onde este README fala em "chamado/ticket", leia "conversa"; onde fala em P0/P1/P2/P3, leia a prioridade nativa. Detalhes em `../../documentacao/detalhamento/13-dashboard-por-conversa.md` e `sql/README.md` (scripts 13–21).


---

## 🚀 Deploy em 1 Clique na Vercel

[![Deploy with Vercel](https://vercel.com/button)](https://vercel.com/new/clone?repository-url=https%3A%2F%2Fgithub.com%2FSEU-USUARIO-OU-ORG%2Fdashboard-suporte-plinq&env=SUPABASE_URL,SUPABASE_ANON_KEY&project-name=plinq-support-dashboard&repository-name=plinq-support-dashboard)

---

## 🧭 Visão Geral & Recursos

### 🎛️ Barramento de Filtros Globais Combinados
Todos os blocos do dashboard reagem em sincronia aos filtros do cabeçalho:
* **Período de Análise**: Hoje, Últimos 7 Dias, Últimos 30 Dias.
* **Canal / Inbox**: Todos os canais ou seleção dinâmica por caixa de entrada (WhatsApp, Widget Web, etc.).
* **Severidade**: Todas, P0 / Red (Risco Churn/Cobrança), P1 / Yellow (Erro Login/Consulta), P2 / Green (Dúvidas), P3 / Green (Feedback/Elogios).
* **Origem do Atendimento**: Todos, Somente Atendimento Humano, Somente Respostas por Bot.
* **Status da Taxonomia**: Todas as conversas, Com Taxonomia Válida (2 tags obrigatórias: Severidade + Motivo), Com Taxonomia Incompleta/Ausente.

---

### 🧱 Estrutura dos Blocos Operacionais

```
┌────────────────────────────────────────────────────────────────────────┐
│                        BARRAMENTO DE FILTROS GLOBAIS                   │
├────────────────────────────────────────────────────────────────────────┤
│ [A] FILA AGORA (24x7)                                                 │
│     ├── D-01 Fila Plinq (Aguardando Resposta Humana)                   │
│     ├── D-02 Aguardando Usuária                                        │
│     ├── D-03 Alerta Vermelho P0 (>10 min sem resposta)                 │
│     ├── D-04 Histograma de Idade / Envelhecimento (<1h até >72h)       │
│     ├── D-05 Sem Atendimento Nenhum (Zero respostas de saída)          │
│     └── D-06 Adesão à Taxonomia (%)                                    │
├────────────────────────────────────────────────────────────────────────┤
│ [B] FLUXO E TEMPOS DE ESPERA                                          │
│     ├── D-07 Volume de Entrada vs. Saída (Criados vs Resolvidos)       │
│     ├── D-08 Mediana e P90 de 1ª Resposta Atendível (Janela Comercial) │
│     ├── D-09 Resolução por Tipo: Manual vs Inatividade 3 Dias vs Bot   │
│     ├── D-10 Turn 2+: Mediana e P90 das respostas subsequentes         │
│     ├── D-11 Espera por Canal / Inbox (Detalhamento dinâmico)          │
│     └── D-12 Fora da Janela Comercial (Mensagens pós 18h / Finais Sem) │
├────────────────────────────────────────────────────────────────────────┤
│ [C] QUALIDADE & SATISFAÇÃO (CX)                                        │
│     ├── D-13 CSAT Geral e Comparativo Humano vs. Bot                   │
│     ├── D-14 Alertas de Detratores (Notas 1 e 2 com auditoria rápida)  │
│     └── D-15 Distribuição de Notas (1 a 5 estrelas)                    │
├────────────────────────────────────────────────────────────────────────┤
│ [D] EFICIÊNCIA & RELATÓRIO EXECUTIVO SEMANAL                           │
│     ├── D-16 Tempo para Zerar a Fila (Capacidade Operacional)          │
│     ├── D-17 Ociosidade Máxima do Atendente (Janela de Espera Ociosa)  │
│     └── RS-01 a RS-14: Heatmap de Horários, Matriz de Transbordo,      │
│         Top Motivos, Desempenho de Bots e Pauta Semanal                │
├────────────────────────────────────────────────────────────────────────┤
│ [🔍] MODAL DE DRILL-DOWN (Inspeção Granular por Chamado / Ticket)      │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 🛠️ Tecnologias Utilizadas

* **Frontend**: HTML5 Semântico, CSS3 Moderno (**Dark Mode HSL Curated com Glassmorphism** e animações de alerta), JavaScript ES6+ (Zero dependências externas pesadas, carregamento instantâneo).
* **Tipografia**: Google Fonts ([Inter](https://fonts.google.com/specimen/Inter)).
* **Banco de Dados**: [Supabase PostgreSQL](https://supabase.com) (PostgREST API, views agregadas, migrações e RPCs com funções PL/pgSQL de janela comercial).
* **Hospedagem & CDN**: [Vercel](https://vercel.com) com headers de segurança HTTP (`nosniff`, `SAMEORIGIN`, CSP/Permissions-Policy) e geração automatizada de runtime config.

---

## 💻 Como Rodar Localmente

### Pré-requisitos
* **Node.js** v18 ou superior instalado.

### Passo a Passo

1. **Clone ou acerte o diretório do projeto**:
   ```bash
   git clone https://github.com/SEU-USUARIO-OU-ORG/dashboard-suporte-plinq.git
   cd dashboard-suporte-plinq
   ```

2. **Configure as Variáveis de Ambiente**:
   ```bash
   cp .env.example .env
   ```
   Edite o `.env` informando os dados da sua instância do Supabase:
   ```env
   SUPABASE_URL=https://seu-projeto.supabase.co
   SUPABASE_ANON_KEY=sua_chave_anon_aqui
   ```

3. **Instale as dependências de desenvolvimento**:
   ```bash
   npm install
   ```

4. **Inicie o servidor de desenvolvimento**:
   ```bash
   npm run dev
   ```
   O script gerará `config.js` e iniciará o servidor local em:
   👉 **`http://localhost:3000`**

---

## 🐙 Como Subir no GitHub como Projeto Independente

Se esta pasta for publicada em um repositório GitHub novo:

```bash
# 1. Navegue até a pasta do Dashboard
cd "/Users/macbookpro/Documents/Plinq/Code/Chamados APP/Projeto Dashboard/Dashboard"

# 2. Inicialize o repositório Git
git init

# 3. Adicione todos os arquivos
git add .

# 4. Crie o commit inicial
git commit -m "feat: initial commit - Plinq Support Dashboard v3.0"

# 5. Defina a branch principal como main
git branch -M main

# 6. Crie o repositório no seu GitHub (ex: dashboard-suporte-plinq) e vincule o remote
git remote add origin https://github.com/SEU-USUARIO-OU-ORG/dashboard-suporte-plinq.git

# 7. Envie os arquivos para o GitHub
git push -u origin main
```

---

## ▲ Como Publicar na Vercel

### Método 1: Pela Interface Web da Vercel (Recomendado)

1. Acesse o [Dashboard da Vercel](https://vercel.com/dashboard) e clique em **"Add New..."** > **"Project"**.
2. Selecione o repositório Git que você acabou de subir (`dashboard-suporte-plinq`).
3. Nas configurações do projeto:
   * **Framework Preset**: Selecione `Other`.
   * **Root Directory**: `./` (raiz do repositório).
   * **Build Command**: `npm run build` *(já configurado no vercel.json e package.json)*.
   * **Output Directory**: `.` *(já configurado)*.
4. Na seção **Environment Variables**, adicione:
   * `SUPABASE_URL` = `https://seu-projeto.supabase.co` *(sua URL do Supabase)*
   * `SUPABASE_ANON_KEY` = `sua_chave_anon_aqui` *(sua chave anon pública)*
5. Clique em **"Deploy"**.
6. Em poucos segundos, sua aplicação estará no ar com HTTPS gratuito, CDN global e domínio customizável!

### Método 2: Pelo Terminal via Vercel CLI

```bash
# 1. Instale ou execute a CLI da Vercel
npx vercel

# 2. Para deploy direto em produção
npx vercel --prod
```

---

## 🗄️ Configuração do Banco de Dados (Supabase)

O dashboard necessita de tabelas, funções e RPCs específicas no Supabase PostgreSQL. Se estiver conectando a um projeto Supabase novo, execute os scripts presentes na pasta [`sql/`](./sql/README.md) na seguinte ordem no **SQL Editor do Supabase**:

1. [`sql/01_ddl_estrutura_dados.sql`](./sql/01_ddl_estrutura_dados.sql) — Criação das tabelas de apoio, taxonomia e auditoria com RLS ativado.
2. [`sql/02_populate_calendar_2026_2028.sql`](./sql/02_populate_calendar_2026_2028.sql) — Carga do calendário comercial de feriados BR + SP.
3. [`sql/03_funcoes_janela_comercial.sql`](./sql/03_funcoes_janela_comercial.sql) — Funções PL/pgSQL para cálculo de espera atendível (09:00 às 18:00 BRT).
4. [`sql/04_views_dashboard_e_relatorio.sql`](./sql/04_views_dashboard_e_relatorio.sql) — Views base de métricas operacionais.
5. [`sql/05_fix_rpcs_contrato_e_filtros.sql`](./sql/05_fix_rpcs_contrato_e_filtros.sql) — RPCs finais parametrizadas consumidas pelo frontend com suporte aos 5 filtros globais.

Consulte o [Manual SQL](./sql/README.md) para detalhes completos de cada migração.

---

## 📁 Estrutura de Arquivos do Projeto

```
.
├── .env.example              # Exemplo de variáveis de ambiente
├── .gitattributes            # Normalização de quebras de linha
├── .gitignore                # Arquivos ignorados pelo Git
├── config.example.js         # Exemplo de configuração estática manual
├── favicon.svg               # Ícone SVG em alta resolução com gradiente Plinq
├── index.html                # Página principal com os 4 blocos e modal de drill-down
├── LICENSE                   # Licença MIT
├── package.json              # Metadados do projeto, scripts dev/build/start
├── README.md                 # Documentação completa do projeto
├── site.webmanifest          # Manifesto Web App (PWA)
├── vercel.json               # Configurações de build e headers de segurança da Vercel
│
├── scripts/
│   └── generate-config.js    # Script de build que gera config.js a partir do ambiente
│
├── src/
│   ├── dashboard.js          # Lógica frontend, chamadas RPC Supabase e drill-down
│   └── styles.css            # Estilos Dark Mode Glassmorphism e responsividade
│
└── sql/                      # Scripts SQL para setup do banco de dados no Supabase
    ├── README.md             # Guia de execução dos scripts SQL
    ├── 01_ddl_estrutura_dados.sql
    ├── 02_populate_calendar_2026_2028.sql
    ├── 03_funcoes_janela_comercial.sql
    ├── 04_views_dashboard_e_relatorio.sql
    └── 05_fix_rpcs_contrato_e_filtros.sql
```

---

## 🔒 Segurança e Boas Práticas

* **Nenhum Dado Sensível no Bundle**: Apenas a chave pública `anon` do Supabase é utilizada no frontend. Todas as políticas de acesso são protegidas por Row Level Security (RLS) no banco de dados.
* **Headers HTTP de Segurança**: O arquivo `vercel.json` inclui cabeçalhos de proteção contra Clickjacking (`X-Frame-Options: SAMEORIGIN`), MIME-sniffing (`X-Content-Type-Options: nosniff`) e Cross-Site Scripting.
* **Resiliência a Falhas**: Se alguma RPC do Supabase falhar, o dashboard exibe feedback visual claro (`erro`) em vez de travar ou exibir métricas inventadas.

---

## 📄 Licença

Este projeto é distribuído sob a licença **MIT**. Consulte o arquivo [LICENSE](LICENSE) para mais detalhes.
