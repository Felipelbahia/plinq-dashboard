# Plinq Support Dashboard — Coding Standards & Architecture

> **Reference for AI Agents**  
> Este documento estabelece as normas de código, convenções de arquitetura e padrões operacionais do projeto **Plinq Support Dashboard (v3.0)**, estendendo a base global em `/Users/macbookpro/Documents/VibeCoding/0 Padrões/STANDARDS_TEMPLATE.md`.

---

## 1. Regra de Ouro Arquitetural (Frontend Estático Puro + Supabase)

> 🚨 **NÃO EXISTE SERVIDOR BACKEND CUSTOMIZADO NESTE REPOSITÓRIO!**
> 
> A aplicação roda como um Frontend Web Estático (SPA Vanilla) hospedado na Vercel, consumindo dados diretamente do **Supabase PostgreSQL (`Plinq_V1`)**:
> 1. **Frontend**: HTML5 Semântico, CSS3 Moderno (Dark Mode Glassmorphism com tokens HSL), JavaScript ES6+ Vanilla (zero dependências pesadas de framework).
> 2. **Database & API**: Supabase PostgreSQL acessado via PostgREST / RPCs parametrizadas utilizando a biblioteca oficial `@supabase/supabase-js` (carregada via CDN ou runtime).
> 3. **Hospedagem & CDN**: Vercel com geração dinâmica de configuração em tempo de build (`scripts/generate-config.js`) e cabeçalhos HTTP estritos de segurança (`vercel.json`).

---

## 2. Naming Conventions & Database Rules

| Type | Convention | Example |
| :--- | :--- | :--- |
| **Arquivos Frontend** | `kebab-case` ou semântico | `index.html`, `dashboard.js`, `styles.css` |
| **Scripts Node.js** | `kebab-case.js` (ES Modules) | `generate-config.js`, `security-audit-and-attacks.js` |
| **Classes e IDs CSS** | `kebab-case` / BEM-like | `.metric-card`, `#filter-period`, `.badge-p0` |
| **Variáveis CSS** | `--kebab-case` | `--bg-primary`, `--accent-cyan`, `--glass-bg` |
| **Supabase Tables** | `snake_case` (prefixo `suporteapp_`) | `suporteapp_calendar`, `suporteapp_weekly_reports` |
| **Supabase Views** | `snake_case` (prefixo `suporteapp_v_`) | `suporteapp_v_dashboard_queue`, `suporteapp_v_turn_times_detail` |
| **Supabase RPCs** | `snake_case` (prefixo `suporteapp_rpc_`) | `suporteapp_rpc_dashboard_queue`, `suporteapp_rpc_turn_metrics` |
| **Constantes JS** | `SCREAMING_SNAKE_CASE` | `DEFAULT_PERIOD`, `BUSINESS_HOURS_START` |

---

## 3. Estrutura Padrão de Pastas

- **`/.agent`**: Regras multi-IA (`rules/`), scripts de sincronização (`scripts/`), planos (`plans/`) e skills locais (`skills/`).
- **`/.claude`**: Diretório de compatibilidade para Claude Code CLI (`skills/`).
- **`/scripts`**: Scripts de manutenção, build e auditoria de segurança (`generate-config.js`, `security-audit-and-attacks.js`).
- **`/src`**: Código-fonte do frontend (`dashboard.js` e `styles.css`).
- **`/sql`**: Scripts DDL, funções de janela comercial, views e RPCs para o Supabase PostgreSQL.
- **Raiz (`./`)**: Arquivos de entrada web (`index.html`, `favicon.svg`, `site.webmanifest`), configurações de deploy (`vercel.json`), dependências (`package.json`) e variáveis de ambiente (`.env.example`).

---

## 4. Diretrizes de Segurança e Protocolo de Execução

1. **Uso Exclusivo de Chave Pública Anon no Frontend**:
   - O dashboard DEVE consumir exclusivamente a chave pública (`SUPABASE_ANON_KEY` / `sb_publishable_...`).
   - NUNCA expor ou injetar chaves privilegiadas (`service_role`, `sb_secret_` ou `sbp_`) no frontend ou no bundle compilado.
   - O script de build (`scripts/generate-config.js`) possui trava de segurança automática: aborta o build imediatamente se detectar chaves privilegiadas.

2. **Row Level Security (RLS) no Supabase**:
   - Todas as tabelas `suporteapp_*` devem ter RLS ativado.
   - O acesso anônimo é estritamente limitado à leitura (`SELECT`) em views e execução (`EXECUTE`) de RPCs analíticas seguras.

3. **Headers HTTP de Segurança na Vercel**:
   - Todas as rotas servidas pela Vercel aplicam `X-Frame-Options: SAMEORIGIN`, `X-Content-Type-Options: nosniff`, `X-XSS-Protection: 1; mode=block` e `Referrer-Policy: strict-origin-when-cross-origin`.

4. **Tratamento Resiliente de Erros na UI**:
   - Caso qualquer RPC ou query do Supabase falhe ou retorne erro de rede, o componente afetado deve exibir estado de erro gracioso com badge de alerta, sem travar o restante do dashboard.

---

## 5. Projetos Relacionados & Fontes de Referência

Este Dashboard só lê e mede o que já aconteceu no ecossistema Chamados APP; ele não é a fonte dos dados. Dois projetos irmãos servem de referência (detalhado em `CLAUDE.md` §4c):

| Projeto | Caminho | Uso |
| :--- | :--- | :--- |
| **Chamados APP (raiz)** | `../../` (`/Users/macbookpro/Documents/Plinq/Code/Chamados APP`) | Esquema `suporteapp_*`, regras de negócio, skills `suporteapp-db-schema` e `suporteapp-sql-cookbook` em `../../.claude/skills/`. |
| **Supabase Manager** | `/Users/macbookpro/Documents/Plinq/Code/Supabase` | Ferramental de acesso ao mesmo banco `Plinq_V1` — MCP `supabase-plinq`, scripts de conexão direta, práticas de chaves. |

Toda consulta MCP ao banco deve usar o servidor `supabase-plinq` (`project_id: hqqzfccgkqdmhznwaxqj`) — é o mesmo projeto Supabase usado pelo Chamados APP e pelo Supabase Manager, não um projeto separado.

---

## 6. Princípios Gerais (`clean-code`)

- **KISS & Zero Bloat**: Manter a aplicação leve, sem adicionar dependências npm desnecessárias para o frontend.
- **Acessibilidade e Semântica**: Manter tags HTML5 semânticas (`<header>`, `<main>`, `<section>`, `<article>`, `<button>`), contraste de cores adequado e atributos `aria-*` onde necessário.
- **Validação Automatizada**: Executar a suíte de auditoria de segurança com `npm run test:security` antes de qualquer entrega ou deploy em produção.
