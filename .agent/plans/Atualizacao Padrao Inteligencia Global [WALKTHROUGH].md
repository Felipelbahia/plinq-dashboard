# Walkthrough: Atualização para o Padrão de Inteligência Global

## Resultados da Execução
1. **Regras Locais Preservadas**:
   - `npm run dev`, `npm run build`, `npm run start`, `npm run test:security`
   - `SUPABASE_URL` e `SUPABASE_ANON_KEY` com trava estrita de build contra chaves secretas (`service_role`, `sb_secret_`, `sbp_`)
   - Headers HTTP de segurança Vercel (`nosniff`, `SAMEORIGIN`, CSP)
   - Contrato Supabase PostgreSQL com prefixo `suporteapp_*` e janela comercial (09h às 18h BRT)
2. **Diretrizes Globais Integradas**:
   - Paridade dual multi-IA, isolamento de novas skills com espelhamento para Claude Code, protocolo de fallback em `0 Padrões` e `0 Mkt`, Socratic Gate e exportação mandatória de planos em `.agent/plans/`.
3. **Poda e Adaptação de Referências**:
   - Removidas seções de Mobile (`mobile-developer`, `mobile-design`, `mobile_audit.py`)
   - Removidas seções de AI training / pipelines (`data-scientist`, `ai-engineer`, `mlops-engineer`)
   - Removidas seções de servidores customizados backend (FastAPI, Django, Express, Go)
   - Removidas referências a arquivos que não existiam neste projeto (`CODEBASE.md`, `ARCHITECTURE.md`, `PATTERNS.md`, `memory.md`), substituídos por referências aos arquivos reais (`README.md`, `STANDARDS.md`, `package.json`, `sql/README.md`).
4. **Paridade Multi-IA**:
   - `sync_rules.py` executado com sucesso e saída literal: `✅ Multi-AI Bidirectional Parity Check Passed: All rule files are 100% synchronized!`.
5. **Registro Central**:
   - Ficha técnica criada em `/Users/macbookpro/Documents/VibeCoding/0 Padrões/projetos/Dashboard Suporte Plinq.md`.
   - Linha adicionada à tabela de `/Users/macbookpro/Documents/VibeCoding/0 Padrões/projetos/README.md`.
