# Documentacao - FIAP X Fase 5

| Documento | Descricao |
|---|---|
| [ARQUITETURA-FASE5.md](./ARQUITETURA-FASE5.md) | Arquitetura completa: requisitos, ADRs, C4, banco, Kafka, seguranca, deploy e operacao |
| [c4/01-contexto.mmd](./c4/01-contexto.mmd) | C4 nivel 1 - contexto |
| [c4/02-conteineres.mmd](./c4/02-conteineres.mmd) | C4 nivel 2 - conteineres |
| [c4/03-componentes-auth.mmd](./c4/03-componentes-auth.mmd) | C4 nivel 3 - auth-service |
| [c4/03-componentes-video.mmd](./c4/03-componentes-video.mmd) | C4 nivel 3 - video-service |
| [c4/03-componentes-processing.mmd](./c4/03-componentes-processing.mmd) | C4 nivel 3 - processing-service |
| [c4/04-implantacao.mmd](./c4/04-implantacao.mmd) | C4 - implantacao (Compose e k3s) |
| [c4/05-codigo-outbox.mmd](./c4/05-codigo-outbox.mmd) | C4 nivel 4 (opcional) - outbox transacional |
| [postman](./postman) | Colecao e environment do Postman |
| [ROTEIRO-VIDEO.md](./ROTEIRO-VIDEO.md) | Roteiro de gravacao da entrega |
| [`../scripts`](../scripts) | Smoke test automatizado (bash e PowerShell) |

## Como renderizar os diagramas

Os arquivos `.mmd` usam a sintaxe C4 do Mermaid. Opcoes:

- GitHub: cole o conteudo em um bloco ` ```mermaid `.
- VS Code: extensao `Markdown Preview Mermaid Support`.
- CLI: `npx @mermaid-js/mermaid-cli -i docs/c4/02-conteineres.mmd -o conteineres.png`.

## Scripts de banco

- `infra/postgres/init/01-create-databases.sql` cria os tres bancos e usuarios no ambiente local.
- As tabelas sao criadas por Flyway em cada servico:
  - `tc-fiapx-auth-service/src/main/resources/db/migration/V1__create_usuario.sql`
  - `tc-fiapx-video-service/src/main/resources/db/migration/V1__create_video_tables.sql`
  - `tc-fiapx-processing-service/src/main/resources/db/migration/V1__create_processamento.sql`
