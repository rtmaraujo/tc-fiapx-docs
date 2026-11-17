# FIAP X - Fase 5 (Java / Spring Boot)

Reimplementacao em **Java 21 + Spring Boot 4** do hackathon FIAP X, originalmente escrito em Go. O fluxo e o mesmo: autenticar, enviar um video, processar os frames de forma assincrona e baixar um ZIP.

## Arquitetura em uma frase

Tres microsservicos independentes (`auth`, `video`, `processing`) conversando por **Kafka**, com **PostgreSQL por servico**, **storage S3-compativel** para objetos, **outbox transacional**, consumidores idempotentes, notificacao de falha por e-mail e observabilidade com **Prometheus, Grafana e Zipkin**.

```text
Usuario -> auth-service (JWT)
        -> video-service (upload/status/download) -> Kafka -> processing-service (FFmpeg/ZIP)
                                                   <- Kafka <- video-service
```

## Repositorios

| Repositorio | Conteudo |
|---|---|
| `tc-fiapx-auth-service` | Cadastro, login e JWT (porta 8081) |
| `tc-fiapx-video-service` | Upload, status, download, outbox e e-mail (porta 8082) |
| `tc-fiapx-processing-service` | FFmpeg, ZIP e resultado (porta 8083) |
| `tc-fiapx-docs` | Arquitetura, C4, Postman, infraestrutura e roteiro do video |

## Executar tudo localmente

```bash
docker compose up --build -d
docker compose ps
```

| Recurso | URL |
|---|---|
| Auth API / Swagger | http://localhost:8081/swagger-ui.html |
| Video API / Swagger | http://localhost:8082/swagger-ui.html |
| Processing (health) | http://localhost:8083/actuator/health |
| SeaweedFS Filer UI | http://localhost:8888 |
| MailHog | http://localhost:8025 |
| Zipkin | http://localhost:9411 |
| Prometheus | http://localhost:9090 |
| Grafana | http://localhost:3000 (`admin` / `fiapx12345`) |

Smoke test:

```bash
curl -X POST http://localhost:8081/api/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"nome":"Maria","email":"maria@fiapx.com","senha":"senha1234"}'

TOKEN=$(curl -s -X POST http://localhost:8081/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"maria@fiapx.com","senha":"senha1234"}' | jq -r .accessToken)

curl -X POST http://localhost:8082/api/videos \
  -H "Authorization: Bearer $TOKEN" \
  -F "arquivo=@video.mp4"
```

Colecao Postman: `docs/postman/FIAPX-Fase5.postman_collection.json`.

### Smoke test automatizado

Com a stack no ar e um video de exemplo em maos:

```bash
./scripts/smoke-test.sh video.mp4          # Linux/macOS/Git Bash
pwsh ./scripts/smoke-test.ps1 -VideoPath .\video.mp4   # Windows
```

O script cadastra um usuario unico, autentica, envia o video, acompanha o status ate `CONCLUIDO` e valida os frames do ZIP baixado.

## Testes

```bash
cd tc-fiapx-auth-service       && mvn -B verify   # 37 testes
cd tc-fiapx-video-service      && mvn -B verify   # 104 testes
cd tc-fiapx-processing-service && mvn -B verify   # 48 testes
```

Todos exigem **85% de cobertura de linhas e branches** (JaCoCo).

## Documentacao

- [`docs/ARQUITETURA-FASE5.md`](docs/ARQUITETURA-FASE5.md) - visao completa, ADRs, banco, Kafka, seguranca, deploy e variaveis
- [`docs/c4`](docs/c4) - diagramas C4 em Mermaid (contexto, conteineres, componentes, implantacao e outbox)
- [`docs/ROTEIRO-VIDEO.md`](docs/ROTEIRO-VIDEO.md) - roteiro de demonstracao
- [`docs/postman`](docs/postman) - colecao e environment

## Estrutura do diretorio

```text
fase-5/
  tc-fiapx-auth-service/
  tc-fiapx-video-service/
  tc-fiapx-processing-service/
  docs/            # arquitetura, C4, Postman, roteiro
  infra/           # init do Postgres, Prometheus, Grafana
  docker-compose.yml
  legacy/          # projeto original em Go, preservado como referencia
```

## Status

- Servicos implementados e validados localmente (189 testes no total).
- Infra local via Docker Compose pronta.
- Manifests Kubernetes e workflows de CI prontos.
- Deploy na AWS Academy pendente de credenciais e cluster ativos.

## Publicacao no GitHub

Os quatro repositorios tem historico Git independente (este diretorio e o repo de docs/infra). Para criar e publicar todos de uma vez:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\publicar-github.ps1            # publicos
powershell -ExecutionPolicy Bypass -File .\scripts\publicar-github.ps1 -Privado   # privados
powershell -ExecutionPolicy Bypass -File .\scripts\publicar-github.ps1 -Simular   # so mostra os comandos
```

Requer `gh` autenticado com escopo `repo`.
