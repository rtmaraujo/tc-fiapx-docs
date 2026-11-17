# Aplica a stack completa (infra + 3 servicos) no cluster k3s provisionado pelo bootstrap.ps1.
#
# Uso:
#   $env:KUBECONFIG="$HOME\.kube\fiapx-k3s.yaml"
#   powershell -ExecutionPolicy Bypass -File .\deploy\deploy.ps1
#
# Imagens: ghcr.io/rtmaraujo/tc-fiapx-*:latest (publicadas pelo CI na main).
param(
    [string]$KubeConfig = "$HOME\.kube\fiapx-k3s.yaml",
    [string]$AppsRoot = '',
    [string]$JwtSecret = 'fiapx-prod-secret-key-with-at-least-32-bytes',
    [string]$StorageAccessKey = 'fiapx',
    [string]$StorageSecretKey = 'fiapx12345',
    [string]$PostgresPassword = 'fiapx12345',
    [string]$GrafanaUser = 'admin',
    [string]$GrafanaPassword = 'fiapx12345',
    [string]$PublicIp = ''
)

$ErrorActionPreference = 'Continue'
$raiz = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not $AppsRoot) { $AppsRoot = $raiz }
$k8s = Join-Path $PSScriptRoot 'k8s'
$namespace = 'fiapx'

$env:KUBECONFIG = $KubeConfig
if (-not (Test-Path $KubeConfig)) { throw "kubeconfig nao encontrado: $KubeConfig" }

function Invoke-Kubectl {
    param([string[]]$Argumentos, [switch]$PermitirFalha)
    $saida = & kubectl @Argumentos 2>&1
    if ($LASTEXITCODE -ne 0 -and -not $PermitirFalha) {
        throw "kubectl $($Argumentos -join ' ') falhou: $($saida | Out-String)"
    }
    return ($saida | Out-String).Trim()
}

function Set-Secret {
    param([string]$Nome, [hashtable]$Valores)
    $argumentos = @('-n', $namespace, 'create', 'secret', 'generic', $Nome, '--save-config', '--dry-run=client', '-o', 'yaml')
    foreach ($chave in $Valores.Keys) { $argumentos += "--from-literal=$chave=$($Valores[$chave])" }
    $yaml = & kubectl @argumentos 2>&1
    if ($LASTEXITCODE -ne 0) { throw "falha ao gerar o secret $Nome`: $yaml" }
    $yaml | kubectl -n $namespace apply -f - | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "falha ao aplicar o secret $Nome" }
    Write-Host "  secret $Nome"
}

function Wait-Deployment {
    param([string]$Nome, [int]$Timeout = 420)
    $null = Invoke-Kubectl @('-n', $namespace, 'rollout', 'status', "deployment/$Nome", "--timeout=${Timeout}s")
    Write-Host "  $Nome pronto"
}

function Wait-Job {
    param([string]$Nome, [int]$Timeout = 300)
    $null = Invoke-Kubectl @('-n', $namespace, 'wait', '--for=condition=complete', "job/$Nome", "--timeout=${Timeout}s")
    Write-Host "  job $Nome concluido"
}

Write-Host '==> conectando ao cluster'
$nodes = Invoke-Kubectl @('get', 'nodes', '-o', 'wide')
$nodes | Write-Host

Write-Host '==> namespace e secrets'
$null = Invoke-Kubectl @('apply', '-f', (Join-Path $k8s '00-namespace.yaml'))
Set-Secret 'postgres-secret' @{ POSTGRES_PASSWORD = $PostgresPassword }
Set-Secret 'storage-secret' @{ STORAGE_ACCESS_KEY = $StorageAccessKey; STORAGE_SECRET_KEY = $StorageSecretKey }
Set-Secret 'grafana-secret' @{ GF_SECURITY_ADMIN_USER = $GrafanaUser; GF_SECURITY_ADMIN_PASSWORD = $GrafanaPassword }
Set-Secret 'auth-service-secret' @{ DB_USER = 'fiapx_auth_user'; DB_PASSWORD = 'fiapx_auth_pass'; JWT_SECRET = $JwtSecret }
Set-Secret 'video-service-secret' @{
    DB_USER             = 'fiapx_video_user'
    DB_PASSWORD         = 'fiapx_video_pass'
    STORAGE_ACCESS_KEY  = $StorageAccessKey
    STORAGE_SECRET_KEY  = $StorageSecretKey
    JWT_SECRET          = $JwtSecret
}
Set-Secret 'processing-service-secret' @{
    DB_USER            = 'fiapx_processing_user'
    DB_PASSWORD        = 'fiapx_processing_pass'
    STORAGE_ACCESS_KEY = $StorageAccessKey
    STORAGE_SECRET_KEY = $StorageSecretKey
}

Write-Host '==> dashboards do Grafana'
$dashboards = Join-Path $raiz 'infra\grafana\dashboards'
$yamlDash = & kubectl -n $namespace create configmap grafana-dashboards --from-file=$dashboards --dry-run=client -o yaml 2>&1
if ($LASTEXITCODE -ne 0) { throw "falha ao montar o ConfigMap dos dashboards: $yamlDash" }
$yamlDash | kubectl -n $namespace apply -f - | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'falha ao aplicar o ConfigMap dos dashboards' }

Write-Host '==> postgres'
$null = Invoke-Kubectl @('apply', '-f', (Join-Path $k8s '10-postgres.yaml'))
Wait-Deployment 'postgres'

Write-Host '==> kafka'
$null = Invoke-Kubectl @('-n', $namespace, 'delete', 'job', 'kafka-init', '--ignore-not-found')
$null = Invoke-Kubectl @('apply', '-f', (Join-Path $k8s '20-kafka.yaml'))
Wait-Deployment 'kafka'
Wait-Job 'kafka-init'

Write-Host '==> storage S3 (SeaweedFS)'
$null = Invoke-Kubectl @('-n', $namespace, 'delete', 'job', 'storage-init', '--ignore-not-found')
$null = Invoke-Kubectl @('apply', '-f', (Join-Path $k8s '30-seaweedfs.yaml'))
Wait-Deployment 'seaweedfs'
Wait-Job 'storage-init'

Write-Host '==> observabilidade'
$null = Invoke-Kubectl @('apply', '-f', (Join-Path $k8s '40-observability.yaml'))
foreach ($dep in @('mailhog', 'zipkin', 'prometheus', 'grafana')) { Wait-Deployment $dep }

Write-Host '==> servicos'
$servicos = @('tc-fiapx-auth-service', 'tc-fiapx-video-service', 'tc-fiapx-processing-service')
$destino = Join-Path $raiz '.deploy\apps'
foreach ($svc in $servicos) {
    $dir = Join-Path $AppsRoot "$svc\k8s"
    if (-not (Test-Path $dir)) {
        $dir = Join-Path $destino "$svc\k8s"
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $destino -Force | Out-Null
            Write-Host "  clonando $svc"
            git clone --depth 1 "https://github.com/rtmaraujo/$svc.git" (Join-Path $destino $svc) | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "falha ao clonar $svc" }
        }
    }
    Write-Host "  aplicando $svc"
    Get-ChildItem $dir -Filter *.yaml | Where-Object { $_.Name -ne 'secret.example.yaml' } | ForEach-Object {
        $null = Invoke-Kubectl @('apply', '-f', $_.FullName)
    }
}

foreach ($dep in @('tc-fiapx-auth-service', 'tc-fiapx-video-service', 'tc-fiapx-processing-service')) {
    Wait-Deployment $dep 480
}

Write-Host ''
Invoke-Kubectl @('-n', $namespace, 'get', 'pods', '-o', 'wide') | Write-Host
Invoke-Kubectl @('-n', $namespace, 'get', 'svc', '-o', 'wide') | Write-Host

$ip = Invoke-Kubectl @('get', 'nodes', '-o', 'jsonpath={.items[0].status.addresses[?(@.type=="ExternalIP")].address}')
if (-not $ip) {
    $ip = (Invoke-Kubectl @('get', 'nodes', '-o', 'jsonpath={.items[0].status.addresses[?(@.type=="InternalIP")].address}'))
}
Write-Host ''
Write-Host 'Endpoints:'
Write-Host "  API (auth):   http://$ip/api/auth"
Write-Host "  API (video):  http://$ip/api/videos"
Write-Host "  Grafana:      http://${ip}:30300  ($GrafanaUser / $GrafanaPassword)"
Write-Host "  Prometheus:   http://${ip}:30090"
Write-Host "  Zipkin:       http://${ip}:30941"
Write-Host "  MailHog:      http://${ip}:30825"
Write-Host "  SeaweedFS:    http://${ip}:30888"
Write-Host ''
Write-Host 'Smoke test:'
Write-Host "  powershell -ExecutionPolicy Bypass -File .\scripts\smoke-test.ps1 -AuthUrl http://$ip -VideoUrl http://$ip"
