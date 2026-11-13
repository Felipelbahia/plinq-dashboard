# Mapa de destinos: Dashboard
Produz: software. Estrutura: mono-marca (suposição: dono não respondeu).
Atualizado em 2026-11-12. Se este mapa divergir de uma regra de skill, **vale este mapa**. Tipo de entrega que não está aqui entra aqui antes de ser gravado.

| Tipo de entrega | Caminho | Escopo | Nome e metadados | Observação |
|---|---|---|---|---|
| Documentos técnicos (guias, decisões) | docs/ | projeto | `<tema>.md` | |
| Relatórios (auditoria, segurança, performance) | docs/relatorios/AAAA-MM-DD - Nome/ | projeto | `relatorio.md` + anexos | pasta nasce quando for preciso |
| Exportações de dados pedidas por pessoas | exports/AAAA-MM-DD - Nome/ | projeto | `<conteudo>.csv` | **fora do git** (`exports/` no `.gitignore` antes do 1º uso) |
| Código (módulos, rotas, testes, configs) | segue a stack e o `STANDARDS.md`/skill do framework | projeto | | fora do mapa |
| Conteúdo existente | scripts/ | projeto | | pasta já existente; uso a confirmar com o dono (nada foi movido) |
| Conteúdo existente | sql/ | projeto | | pasta já existente; uso a confirmar com o dono (nada foi movido) |
| Conteúdo existente | src/ | projeto | | pasta já existente; uso a confirmar com o dono (nada foi movido) |
| Planos, loops e handoffs | .agent/plans/ | projeto | `execution-loops/AAAA_MM_DD/<Título>/NN Nome.md`, `handoffs/` | fixo pelas regras do kit; fora do git |
| Itens adiados | inbox/ | projeto | `NNN-assunto.md` | fixo pelas regras do kit |
| Memória de longo prazo | memory.md | projeto | `Problema → Solução` | fixo |
| Este mapa | docs/ | projeto | | |

## Como usar este mapa (toda IA e skill que grava arquivo)
1. Leia esta tabela antes de gravar. Use o **Caminho** da linha do tipo de entrega. Não monte caminho por conta própria.
2. Tipo de entrega que não está aqui: acrescente a linha antes de gravar e avise o dono.
3. Pasta citada aqui que não existe: crie só essa pasta.
4. Nunca mova nem apague arquivo existente para encaixar na estrutura; mudança de lugar só com aprovação.
5. Dúvida que este mapa não resolve: skill `mapa-de-destinos`.

## Inconsistências encontradas (nada foi movido)
- `execution-loops/` na **raiz**: legado; pelo kit o lugar é `.agent/plans/execution-loops/`. Migrar só a pedido do dono.

## Respostas da conversa de criação
| Pergunta | Resposta | Data |
|---|---|---|
| O que o projeto entrega além de código? | a confirmar pelo dono | 2026-11-12 |
| Há mais de uma marca ou produto? | suposição: mono-marca, dono não respondeu | 2026-11-12 |
| Fluxo de aprovação | 0 sem esteira (suposição) | 2026-11-12 |
