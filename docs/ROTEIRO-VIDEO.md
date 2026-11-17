# Roteiro do video - FIAP X Fase 5

Duracao alvo: **8 a 12 minutos**. Formato sugerido: gravacao de tela com narracao.

## Antes de gravar (checklist)

- [ ] `docker compose up --build -d` concluido e `docker compose ps` com todos os servicos saudaveis
- [ ] Usuario de demonstracao criado (`maria@fiapx.com` / `senha1234`)
- [ ] Arquivo `video.mp4` curto (10 a 30s) separado na area de trabalho
- [ ] Postman aberto com a colecao FIAP X - Fase 5
- [ ] Abas abertas: MailHog (8025), Grafana (3000), Zipkin (9411), SeaweedFS (8888)
- [ ] Aba do GitHub com os quatro repositorios
- [ ] Terminal com fonte legivel e sem dados sensiveis

## 0:00 - 1:00 | Abertura

> "Este e o FIAP X da Fase 5. O objetivo e receber videos, processar os frames de forma assincrona e disponibilizar o resultado em ZIP. A implementacao original era em Go; nesta fase eu reimplementei em Java 21 com Spring Boot 4, seguindo a arquitetura de tres microsservicos da Fase 4."

Mostrar rapidamente a estrutura do diretorio e o `docker-compose.yml`.

## 1:00 - 2:30 | Arquitetura

Abrir `docs/ARQUITETURA-FASE5.md` e destacar:

1. Tres servicos independentes: auth (8081), video (8082) e processing (8083).
2. Kafka com tres topicos: `solicitado`, `processado` e `falha`.
3. **Outbox transacional**: o video e o evento sao gravados na mesma transacao, evitando perda de pedidos em picos.
4. **Idempotencia** pela tabela `evento_processado`.
5. PostgreSQL com um banco por servico e Flyway.
6. Storage S3-compativel (SeaweedFS no ambiente local) para os videos e ZIPs.
7. Notificacao de falha por e-mail com retentativa.
8. Prometheus, Grafana e Zipkin.

Mostrar o diagrama de conteineres (`docs/c4/02-conteineres.mmd`).

## 2:30 - 3:30 | Autenticacao

No Postman, executar:

1. `Registrar usuario` - mostrar 201 e o corpo.
2. `Login` - mostrar o `accessToken` e explicar que o script salva o token na variavel de colecao.
3. `Usuario autenticado` - mostrar 200 e o `role`.

Falar: "A senha e armazenada com BCrypt custo 12. O token e HS256, issuer fiapx-auth, validade de 2 horas. O video-service valida o mesmo segredo e nao consulta o auth-service em cada requisicao."

## 3:30 - 5:00 | Upload e processamento

1. Executar `Upload de video` com o `video.mp4`.
2. Mostrar `202 Accepted`, `Location` e `status = PENDENTE`.
3. Abrir o Filer do SeaweedFS (http://localhost:8888) e mostrar o objeto em `videos/{usuarioId}/{videoId}/original.mp4`.
4. Abrir o Kafka (opcional) ou os logs do processing-service:

```bash
docker compose logs -f processing-service
```

5. Explicar: "O `OutboxPublisher` publica o evento em ate 2 segundos. O processing-service baixa o video, roda `ffmpeg -vf fps=1`, compacta os frames e publica o resultado."

## 5:00 - 6:00 | Status e download

1. Executar `Consultar status` ate aparecer `CONCLUIDO`.
2. Executar `Listar videos` e mostrar a paginacao e o filtro por status.
3. Executar `Baixar ZIP dos frames` e salvar o arquivo.
4. Abrir o ZIP e mostrar os arquivos `frame_00001.jpg`, `frame_00002.jpg`, etc.
5. Explicar o isolamento por usuario: outro usuario recebe 404 para o mesmo id.

## 6:00 - 7:00 | Falha e notificacao por e-mail

Opcao A (natural): enviar um arquivo de video invalido renomeado para `.mp4`.

```bash
cp documento.pdf video-invalido.mp4
```

Fazer upload pelo Postman e acompanhar:

1. `processing-service` publica `fiapx.video.falha`.
2. `video-service` marca `ERRO` e grava a notificacao.
3. Abrir o MailHog (http://localhost:8025) e mostrar o e-mail com motivo e identificador.
4. Mostrar `GET /api/videos?status=ERRO`.

Falar: "A notificacao fica persistida em uma tabela e e reenviada com retentativa, entao uma indisponibilidade momentanea do SMTP nao perde o aviso."

## 7:00 - 8:00 | Observabilidade

1. Grafana -> dashboard "FIAP X - Visao geral": requisicoes por segundo, latencia p95, erros, lag do Kafka, heap e threads.
2. Zipkin: mostrar um trace do upload atravessando os servicos.
3. Prometheus: executar uma query simples, por exemplo `http_server_requests_seconds_count{application="tc-fiapx-video-service"}`.

## 8:00 - 9:00 | Testes e qualidade

No terminal:

```bash
cd tc-fiapx-auth-service && mvn -B verify
cd ../tc-fiapx-video-service && mvn -B verify
cd ../tc-fiapx-processing-service && mvn -B verify
```

Mostrar o resumo: **37 + 104 + 48 testes**, todos verdes, e a mensagem `All coverage checks have been met` (85% de linhas e branches).

Mostrar o workflow `.github/workflows/ci.yml`: build, testes, SonarCloud, artefato JaCoCo e build da imagem Docker.

## 9:00 - 10:00 | Kubernetes e CI/CD

Mostrar rapidamente:

- `k8s/deployment.yaml` com probes, resources e securityContext.
- `k8s/hpa.yaml` com 2..10 replicas no processing.
- `k8s/ingressroute.yaml` com `/api/auth` e `/api/videos`.

Falar: "O deploy na AWS Academy esta preparado nos manifests e no workflow, mas depende de credenciais e cluster ativos no momento da gravacao. Localmente tudo roda via Docker Compose."

## 10:00 - 11:00 | Encerramento

Retomar os requisitos:

- processa varios videos em paralelo (particoes + replicas);
- nao perde pedidos em picos (outbox);
- autenticacao usuario/senha (JWT + BCrypt);
- listagem por usuario;
- notificacao de erro por e-mail;
- persistencia, escalabilidade, testes, CI/CD, Docker/Kubernetes, Kafka, PostgreSQL + storage S3, Prometheus + Grafana;
- documentacao com C4 e scripts.

> "O projeto original em Go foi preservado em `legacy/projeto-fiapx` como referencia. A versao Java esta organizada em quatro repositorios: tres servicos e o repositorio de documentacao e infraestrutura."

## Plano B

| Problema | Alternativa |
|---|---|
| Docker sem recursos | Aumentar memoria do Docker Desktop ou gravar apenas auth + video + infra |
| FFmpeg lento | Usar video de 10s |
| SMTP indisponivel | Mostrar a linha em `notificacao` e o log do scheduler |
| Cluster AWS fora | Mostrar manifests e explicar que o deploy esta condicionado as credenciais |
| Kafka sem topicos | Rodar `docker compose up kafka-init` e aguardar |
