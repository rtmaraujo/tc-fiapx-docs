# Deploy na AWS Academy (EC2 + k3s)

Infraestrutura de demonstracao: uma instancia EC2 com k3s rodando a stack completa
(PostgreSQL, Kafka, SeaweedFS, MailHog, Zipkin, Prometheus, Grafana e os tres servicos).

## Pre-requisitos

- AWS CLI v2 configurado com as credenciais temporarias do AWS Academy
  (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`).
- `ssh`, `scp` e `kubectl` no PATH.
- Imagens publicadas no GHCR (`ghcr.io/rtmaraujo/tc-fiapx-*:latest`), o que acontece
  no pipeline da `main` ou via `workflow_dispatch`.

## 1. Provisionar a instancia

```powershell
$env:AWS_DEFAULT_REGION = 'us-west-2'
powershell -ExecutionPolicy Bypass -File .\deploy\aws\bootstrap.ps1
```

O script cria (de forma idempotente) a chave SSH, o security group, a instancia
`t3.large` com 30 GB e o k3s ja com `--tls-san` do IP publico. O kubeconfig fica em
`$HOME\.kube\fiapx-k3s.yaml`.

## 2. Aplicar a stack

```powershell
$env:KUBECONFIG="$HOME\.kube\fiapx-k3s.yaml"
powershell -ExecutionPolicy Bypass -File .\deploy\deploy.ps1 -PublicIp <ip-publico>
```

O `deploy.ps1` cria os secrets (sem versionar credenciais), aplica a infraestrutura,
espera os jobs de inicializacao (bancos, topicos, bucket) e os tres servicos.

## 3. Validar

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\smoke-test.ps1 `
  -AuthUrl http://<ip> -VideoUrl http://<ip> -VideoPath .\sample.mp4
```

## Endpoints

| Servico | URL |
|---|---|
| API auth | `http://<ip>/api/auth` |
| API video | `http://<ip>/api/videos` |
| Grafana | `http://<ip>:30300` |
| Prometheus | `http://<ip>:30090` |
| Zipkin | `http://<ip>:30941` |
| MailHog | `http://<ip>:30825` |
| SeaweedFS Filer | `http://<ip>:30888` |

## Observacoes

- As credenciais do AWS Academy expiram ao encerrar a sessao do laboratorio; a instancia
  e os dados do cluster deixam de ser acessiveis quando isso acontece.
- Os NodePorts e o 6443 sao liberados por padrao para `0.0.0.0/0` por causa do laboratorio.
  Em producao, restrinja o `SshCidr` no `bootstrap.ps1`.
- Nada de credencial vai para o Git: secrets sao criados em runtime e o kubeconfig fica
  fora do repositorio (`.deploy/` e `*.pem` ignorados).
- Os servicos usam request de CPU baixo (100m) para caber nas duas replicas de cada um
  em um no unico de 2 vCPU; os limites continuam altos para absorver picos.
- A AWS Academy exige IMDSv2; o cloud-init obtem o IP publico com token.

## 4. Derrubar os recursos

```powershell
powershell -ExecutionPolicy Bypass -File .\deploy\aws\teardown.ps1
```

Encerra a instancia, remove o security group e a key pair (a chave local em `~/.ssh` e mantida).

## Validacao realizada (17/11/2026)

- Cluster k3s `v1.37.2` com 12 pods em `Running` e 2 jobs `Completed`.
- Smoke test E2E: upload, processamento em ~2 s, status `CONCLUIDO` e ZIP com 6 frames.
- Caminho de falha: status `ERRO` e e-mail entregue no MailHog.
- Prometheus com 4 targets `up`, Zipkin com os 3 servicos e Grafana 11.4.0 provisionado.
