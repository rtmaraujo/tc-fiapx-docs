# Infraestrutura local

| Pasta | Conteudo |
|---|---|
| `postgres/init` | Script que cria os tres bancos e usuarios na primeira subida do container |
| `kafka` | Script para criar os topicos em um cluster Kafka externo |
| `prometheus` | Configuracao de scrape dos tres servicos |
| `grafana` | Provisionamento do datasource e dashboard "FIAP X - Visao geral" |

Tudo e orquestrado pelo [`docker-compose.yml`](../docker-compose.yml) na raiz do repositorio de documentacao.

## Bancos

| Banco | Usuario |
|---|---|
| `fiapx_auth` | `fiapx_auth_user` |
| `fiapx_video` | `fiapx_video_user` |
| `fiapx_processing` | `fiapx_processing_user` |

As tabelas sao criadas pelo Flyway de cada servico no start da aplicacao.

## Kafka

| Topico | Particoes |
|---|---|
| `fiapx.video.solicitado` | 3 |
| `fiapx.video.processado` | 3 |
| `fiapx.video.falha` | 3 |

## Storage S3

Bucket `fiapx-videos`, criado automaticamente pelo servico `storage-init` no SeaweedFS (S3-compativel).

O ambiente local usa SeaweedFS porque as imagens oficiais do MinIO deixaram de ser distribuidas publicamente. O codigo continua usando o cliente MinIO (compativel com S3), entao em producao basta apontar `STORAGE_ENDPOINT` para o S3 (AWS) ou outro endpoint compativel.

## Observabilidade

- Prometheus: http://localhost:9090
- Grafana: http://localhost:3000 (`admin` / `fiapx12345`)
- Zipkin: http://localhost:9411
