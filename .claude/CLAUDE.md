---
trigger: always_on
---

# CLAUDE.md - Antigravity Kit (Plinq Support Dashboard)

> This file defines how the AI behaves in this workspace.

---

## CRITICAL: AGENT & SKILL PROTOCOL (START HERE)

> **MANDATORY:** You MUST read the appropriate agent file and its skills BEFORE performing any implementation. This is the highest priority rule.

### 1. Modular Skill Loading Protocol

Agent activated → Check frontmatter "skills:" → Read SKILL.md (INDEX) → Read specific sections.

- **Selective Reading:** DO NOT read ALL files in a skill folder. Read `SKILL.md` first, then only read sections matching the user's request.
- **Rule Priority:** P0 (GEMINI.md / CLAUDE.md) > P1 (Agent .md) > P2 (SKILL.md). All rules are binding.

### 2. Dual Rules Parity & File Locations (GEMINI.md & CLAUDE.md)
- **CRITICAL PARITY:** `GEMINI.md` and `CLAUDE.md` MUST remain 100% identical in content at all times. Any modification in one MUST be synchronized across all rule files.
- **FILE PLACEMENT & NAMING CONVENTIONS:**
  - **Claude Code:** Must be named strictly in UPPERCASE as `CLAUDE.md` located at the project root (`./CLAUDE.md`) or inside `./.claude/CLAUDE.md`.
  - **Google Antigravity:** Located in `./.agent/rules/GEMINI.md` (and/or `./GEMINI.md`).
  - **Synchronization:** The script `.agent/scripts/sync_rules.py` automatically maintains synchronization between `./.agent/rules/GEMINI.md`, `./CLAUDE.md`, `./.claude/CLAUDE.md`, and `./.agent/rules/CLAUDE.md`.

### 3. Local Skill Creation Scope
- **STRICT LOCAL SCOPE:** When requested to create a new skill, it MUST be created ONLY inside the active project workspace (`<project_root>/.agent/skills/<skill_name>/`).
- **Global Exemption:** NEVER create a skill in global `0 Padrões` or `0 Mkt` unless explicitly requested by the user (e.g., *"Crie esta skill no 0 Padrões"*).
- **Central Registry:** Whenever a new local skill is created, record it in the project's central sheet at `/Users/macbookpro/Documents/VibeCoding/0 Padrões/projetos/Dashboard Suporte Plinq.md`.
- **Claude Code Discovery (CRITICAL):** Claude Code (the CLI — not Google Antigravity) never scans `.agent/skills/`; it only auto-discovers `SKILL.md` files under `.claude/skills/` (project) and `~/.claude/skills/` (personal). Whenever a skill exists or is created at `.agent/skills/<name>/`, ALSO create `.claude/skills/<name>` as a **symlink** (`ln -s "../../.agent/skills/<name>" ".claude/skills/<name>"`) — never a copy. Never delete a `.claude/skills/<name>` entry as a "duplicate" of `.agent/skills/<name>` without first running `test -L ".claude/skills/<name>"` — if it's a real directory rather than a symlink, it may be the only thing making that skill discoverable by Claude Code, not redundant content.
- **Skill Authoring Guide:** Whenever creating or editing a skill (any project), read `.agent/skills/writing-skills/SKILL.md` first (or global `/Users/macbookpro/Documents/VibeCoding/0 Padrões/.agent/skills/writing-skills/SKILL.md`) — it defines the TDD-for-skills methodology that all new skills must follow.

### 4. Fallback Resolution Protocol
When a requested skill or workflow is NOT found in the current project workspace:
1. **1st Priority (Local Project):** Check active workspace (`./.agent/skills/` or `./.agents/skills/`).
2. **2nd Priority (Global Base):** Search in `/Users/macbookpro/Documents/VibeCoding/0 Padrões/.agent/skills/`.
3. **3rd Priority (Global Marketing):** For marketing, SEO, copywriting or growth tasks, search in `/Users/macbookpro/Documents/VibeCoding/0 Mkt/`.
4. **Automated resolver (Claude Code):** the personal skill `~/.claude/skills/skill-resolver/SKILL.md` implements this exact search order as an invokable procedure.
5. **Scope:** any skill, agent, or script named anywhere in these rule files falls under this same resolution order, whether or not that mention spells out a path.

### 4b. Skills Sempre Alcançáveis (Qualquer Projeto, Qualquer IA)

Estas 3 skills devem estar ao alcance deste projeto mesmo sem cópia local no `.agent/skills/`:

| Skill | Papel | Caminho (0 Padrões) |
|---|---|---|
| `writing-skills` | Como criar/editar qualquer skill (TDD aplicado a documentação) | `/Users/macbookpro/Documents/VibeCoding/0 Padrões/.agent/skills/writing-skills/SKILL.md` |
| `session-handoff` | Documentar o trabalho da sessão para continuar em outra (handoff) | `/Users/macbookpro/Documents/VibeCoding/0 Padrões/.agent/skills/session-handoff/SKILL.md` |
| `execution-loop` | Ciclo Espec → Plan → Execução → QA (nota 0-10) → Debug | `/Users/macbookpro/Documents/VibeCoding/0 Padrões/.agent/skills/execution-loop/SKILL.md` (+ sub-skill `spec-writing`) |

### 4c. Projetos Relacionados (Fonte de Dados e Acessos ao Supabase)

Este Dashboard é uma aplicação **somente leitura** que mede e visualiza o que acontece no ecossistema do Chamados APP — ele não gera os dados, só os consulta no Supabase (`Plinq_V1`, `project_id: hqqzfccgkqdmhznwaxqj`). Dois projetos irmãos são referência obrigatória, cada um com um papel diferente:

| Projeto | Caminho | Papel para este Dashboard |
| :--- | :--- | :--- |
| **Chamados APP (raiz)** | `/Users/macbookpro/Documents/Plinq/Code/Chamados APP` (dois níveis acima deste projeto: `../../`) | **Fonte de verdade do esquema e das regras de negócio** que geram os dados lidos aqui — tabelas/views/RPCs `suporteapp_*`, fluxo Chatwoot→N8N→Supabase, taxonomia de etiquetas e prioridades. Consultar as skills `suporteapp-db-schema` (dicionário de dados, ERD, pegadinhas) e `suporteapp-sql-cookbook` (queries prontas) — ambas já em `.claude/skills/` na raiz do Chamados APP, portanto descobertas nativamente pelo Claude Code quando este for aberto como parte daquele workspace; quando este Dashboard for aberto como projeto isolado, ler os arquivos diretamente em `../../.claude/skills/suporteapp-db-schema/SKILL.md` e `../../.claude/skills/suporteapp-sql-cookbook/SKILL.md`. Ver também `../../documentacao/` para especificações técnicas mais amplas (ex: OpenAPI do backend Plinq). |
| **Supabase Manager** | `/Users/macbookpro/Documents/Plinq/Code/Supabase` | **Referência de acesso/ferramental ao Supabase** — mesmo banco `Plinq_V1`, MCP dedicado `supabase-plinq`, scripts de conexão direta (`scripts/db.ts`) e práticas de segurança de chaves (`sb_publishable_`/`sb_secret_`). Consultar `claude.md` desse projeto para o desenho arquitetural do acesso ao banco antes de assumir como uma credencial ou fluxo de auth deveria funcionar. |

- **MCP obrigatório para consultas ao banco**: usar o servidor `supabase-plinq` (mesmo `project_id` acima) para qualquer inspeção de schema, leitura de advisors/logs ou execução de SQL via ferramenta MCP — nunca um servidor Supabase de outro projeto.
- **Direção do fluxo de informação**: este projeto NUNCA deve escrever nas tabelas `suporteapp_*` nem alterar o esquema — mudanças de schema pertencem ao repositório Chamados APP (raiz), que versiona as migrações DDL.

### 5. Brownfield Rule Merging (Preservação de Regras Existentes)
- **PRESERVAÇÃO E MESCLAGEM:** Ao atualizar este projeto, NUNCA apague ou sobrescreva do zero as regras locais previamente estabelecidas. As especificações locais do Plinq Support Dashboard (scripts npm, variáveis de ambiente, proteção de chaves no build, headers da Vercel e contratos de RPCs do Supabase) estão 100% preservadas e integradas neste documento.

### 6. Enforcement Protocol
1. **When agent is activated:** Activate: Read Rules → Check Frontmatter → Load SKILL.md → Apply All.
2. **Forbidden:** Never skip reading agent rules or skill instructions. "Read → Understand → Apply" is mandatory.

---

## 📥 REQUEST CLASSIFIER (STEP 1)

**Before ANY action, classify the request:**

| Request Type     | Keywords                          | Mode   | Result                                      |
| ---------------- | --------------------------------- | ------ | ------------------------------------------- |
| **QUESTION**     | "what is", "explain", "how"       | ASK    | Text Response (No Plan)                     |
| **SIMPLE TASK**  | "run", "check", "list", "debug"   | EDIT   | Direct Execution (No Plan)                  |
| **COMPLEX CODE** | "build", "create", "refactor"     | EDIT   | **`.agent/plans/{slug}.md` Required**       |
| **DESIGN/UI**    | "design", "UI", "page"            | EDIT   | **`.agent/plans/{slug}.md` Required**       |

---

## 🤖 INTELLIGENT AGENT ROUTING (STEP 2 - AUTO)

**ALWAYS ACTIVE: Before responding to ANY request, automatically analyze and select the best agent(s).**

### Auto-Selection Protocol
1. **Analyze (Silent)**: Detect domains (Frontend, Design, Database/SQL, Security, QA) from user request.
2. **Select Agent(s)**: Choose the most appropriate specialist(s).
3. **Inform User**: Concisely state which expertise is being applied.
4. **Apply**: Generate response using the selected agent's persona and rules.

### Response Format (MANDATORY)
When auto-applying an agent, inform the user:

```markdown
🤖 **Applying knowledge of `@[agent-name]`...**

[Continue with specialized response]
```

---

## TIER 0: UNIVERSAL RULES (Always Active)

### 🌐 Language Handling
When user's prompt is NOT in English:
1. **Internally translate** for better comprehension.
2. **Respond in user's language** - match their communication.
3. **Code comments/variables** remain in English (or Portuguese when following local project nomenclature like `suporteapp_*`).

### 🧹 Clean Code (Global Mandatory)
**ALL code MUST follow `@[skills/clean-code]` rules. No exceptions.**
- **Code**: Concise, direct, no over-engineering. Self-documenting.
- **Vanilla First**: Não adicionar frameworks pesados de frontend sem solicitação explícita do usuário.
- **Testing**: Executar suite de segurança e auditoria (`npm run test:security`) após alterações críticas.
- **Performance**: Manter renderização rápida (Core Web Vitals) e resposta assíncrona fluida para queries ao Supabase.

### 📁 File Dependency Awareness
**Before modifying ANY file:**
1. Consultar [`STANDARDS.md`](STANDARDS.md) e [`README.md`](README.md) para convenções de arquitetura e fluxo de dados.
2. Consultar [`package.json`](package.json) para dependências e scripts de execução.
3. Consultar [`sql/README.md`](sql/README.md) e scripts em `sql/` ao alterar qualquer chamada a RPC ou view do Supabase.
4. Atualizar arquivos dependentes juntos (ex: sincronização entre `index.html`, `src/dashboard.js` e `src/styles.css`).

### 🧠 Read → Understand → Apply
```
❌ WRONG: Read agent file → Start coding
✅ CORRECT: Read → Understand WHY → Apply PRINCIPLES → Code
```

---

## TIER 1: CODE RULES (When Writing Code)

### 💻 Project Type Routing (Frontend Web / Supabase PostgreSQL)

Este projeto é uma **Aplicação Web Frontend Pura (SPA Vanilla)** integrada ao **Supabase PostgreSQL** e hospedada na **Vercel**.

| Domínio de Trabalho | Agente Primário | Skills Relevantes |
| :--- | :--- | :--- |
| **Frontend Web / UI / UX** | `frontend-specialist` | `frontend-design`, `clean-code` |
| **Segurança & Auditoria** | `security-auditor` | `vulnerability-scanner` |
| **Banco de Dados / SQL / RPCs** | `backend-specialist` | `database-design` |
| **QA / Testes / Validação** | `qa-automation-engineer` | `testing-patterns` |
| **Planejamento Geral** | `project-planner` | `plan-writing`, `brainstorming` |
| **Orquestração Geral** | `orchestrator` | `execution-loop` |

*(Nota: Diretrizes de Mobile, Data Science/AI Training e servidores customizados foram removidas do escopo deste projeto por não se aplicarem).*

### 🛠️ Comandos de Desenvolvimento, Build e Testes (Preservados do package.json)

| Comando | Descrição | O que executa |
| :--- | :--- | :--- |
| `npm run dev` | Ambiente de desenvolvimento local | `node scripts/generate-config.js && serve -p 3000 .` (porta 3000) |
| `npm run build` | Build para produção (Vercel / CI) | `node scripts/generate-config.js` (gera `config.js` com trava de segurança) |
| `npm run start` | Inicia servidor estático | `serve -p 3000 .` |
| `npm run test:security` | Auditoria de segurança e testes de invasão RLS | `node scripts/security-audit-and-attacks.js` |

### 🔒 Regras Estritas de Segurança e Variáveis de Ambiente

1. **Variáveis de Ambiente Suportadas**:
   - `SUPABASE_URL`: URL da instância Supabase (ex: `https://xxxxxx.supabase.co`).
   - `SUPABASE_ANON_KEY`: Chave pública `anon` com permissões restritas a leitura por RLS.
2. **Trava de Segurança de Build (`scripts/generate-config.js`)**:
   - É terminantemente PROIBIDO injetar chaves privilegiadas (`service_role`, `sb_secret_` ou `sbp_`) no frontend. O script de build abortará a execução se qualquer chave secreta for informada.
3. **Headers de Segurança HTTP na Vercel (`vercel.json`)**:
   - Toda resposta do servidor aplica `X-Frame-Options: SAMEORIGIN`, `X-Content-Type-Options: nosniff`, `X-XSS-Protection: 1; mode=block` e `Referrer-Policy: strict-origin-when-cross-origin`.
4. **Contrato de Banco de Dados (`sql/`)**:
   - Tabelas, views e RPCs utilizam prefixo `suporteapp_`.
   - Janela comercial calculada entre 09h00 e 18h00 BRT com feriados via `suporteapp_calendar`.

### 🛑 GLOBAL SOCRATIC GATE (TIER 0)

**MANDATORY: Every user request must pass through the Socratic Gate before ANY tool use or implementation.**

| Request Type | Strategy | Required Action |
| :--- | :--- | :--- |
| **New Feature / Build** | Deep Discovery | ASK minimum 3 strategic questions |
| **Code Edit / Bug Fix** | Context Check | Confirm understanding + ask impact questions |
| **Vague / Simple** | Clarification | Ask Purpose, Users, and Scope |
| **Full Orchestration** | Gatekeeper | **STOP** subagents until user confirms plan details |
| **Direct "Proceed"** | Validation | **STOP** → Ask 2 "Edge Case" questions |

**Offer the Execution Loop:** For COMPLEX CODE, DESIGN/UI, or any multi-file request, ask the user whether to run it under the `execution-loop` skill (Espec → Plan → Execução → QA 0-10 → Debug, em `0 Padrões/.agent/skills/execution-loop/SKILL.md`).

### 🏁 Final Checklist Protocol

**Scripts Disponíveis para Auditoria:**

| Script | Localização / Origem | Quando Usar |
| :--- | :--- | :--- |
| `security-audit-and-attacks.js` | `scripts/security-audit-and-attacks.js` (Local) | Sempre que alterar chaves, queries ou RPCs |
| `sync_rules.py` | `.agent/scripts/sync_rules.py` (Local / 0 Padrões) | Sempre que alterar qualquer arquivo de regra |
| `checklist.py` | `0 Padrões/.agent/scripts/checklist.py` | Pré-deploy e auditoria geral |
| `security_scan.py` | `0 Padrões/.agent/skills/vulnerability-scanner/scripts/` | Auditoria de vulnerabilidades |
| `ux_audit.py` | `0 Padrões/.agent/skills/frontend-design/scripts/` | Após modificações na interface |
| `accessibility_checker.py` | `0 Padrões/.agent/skills/frontend-design/scripts/` | Checagem de acessibilidade e contraste |
| `lighthouse_audit.py` | `0 Padrões/.agent/skills/performance-profiling/scripts/` | Antes de deploys de produção |

---

## TIER 2: DESIGN & UI RULES

> Diretrizes visuais específicas para o Plinq Support Dashboard:

1. **Dark Mode Glassmorphism**:
   - Paleta de cores baseada em HSL escuro com gradientes sutis, bordas com transparência (`rgba(255, 255, 255, 0.08)`) e `backdrop-filter: blur(12px)`.
   - Acentos visuais nos tons oficiais Plinq: ciano/azul para neutros, verde para OK/resolvidos, amarelo para atenção/P1, vermelho para alertas críticos/P0.
2. **Tipografia & Ícones**:
   - Google Fonts Inter (`font-family: 'Inter', sans-serif`).
   - Ícones em SVG inline de alta nitidez.
3. **Resiliência de Layout**:
   - Barramento de 5 filtros globais sincronizado em tempo real.
   - Tratamento de estados vazios (empty state), carregando (skeletons/spinners) e erro de conexão com feedback claro.

---

## 📋 PLANS & AUDITS CONVENTION

> Todos os planos de tarefa, auditorias técnicas e especificações DEVEM ser salvos em `.agent/plans/`.

**Naming:** `.agent/plans/{task-slug}.md`

### 📋 System Artifacts Export (MANDATORY)
Sempre que o sistema gerar artefatos nativos (`implementation_plan.md`, `task.md`, `walkthrough.md`), salve uma cópia exata do conteúdo final dentro de `.agent/plans/`:

| Artifact | Origem | Destino Obrigatório no Repositório |
| :--- | :--- | :--- |
| `implementation_plan.md` | System artifact | `.agent/plans/{Task Name} [PLAN].md` |
| `task.md` | System artifact | `.agent/plans/{Task Name} [TASK].md` |
| `walkthrough.md` | System artifact | `.agent/plans/{Task Name} [WALKTHROUGH].md` |

- `{Task Name}` deve ser o nome legível da tarefa (ex: `Atualizacao Padrao Inteligencia Global`).

---

## 📁 QUICK REFERENCE

### Agentes & Skills
- **Especialistas**: `frontend-specialist`, `security-auditor`, `backend-specialist`, `qa-automation-engineer`, `project-planner`, `orchestrator`
- **Skills Chave**: `clean-code`, `brainstorming`, `execution-loop`, `spec-writing`, `writing-skills`, `session-handoff`, `frontend-design`, `database-design`, `vulnerability-scanner`, `testing-patterns`, `performance-profiling`

### Arquivos Chave do Projeto
- `index.html`: Layout mestre com os 4 blocos operacionais e modal de drill-down
- `src/dashboard.js`: Lógica de consumo de RPCs do Supabase, filtros e renderização
- `src/styles.css`: Estilos Dark Mode Glassmorphism e tokens CSS
- `scripts/generate-config.js`: Script de build e geração segura de `config.js`
- `scripts/security-audit-and-attacks.js`: Suíte de testes de penetração e auditoria RLS
- `sql/README.md`: Guia de migrações e contratos de RPCs do banco de dados
- `STANDARDS.md`: Normas de arquitetura, convenções e código
