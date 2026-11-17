# Smoke test do FIAP X: cadastro, login, upload, polling e download do ZIP.
# Uso: powershell -ExecutionPolicy Bypass -File .\scripts\smoke-test.ps1 -VideoPath .\video.mp4
param(
    [string]$AuthUrl = 'http://localhost:8081',
    [string]$VideoUrl = 'http://localhost:8082',
    [string]$VideoPath = 'video.mp4',
    [string]$Email = "smoke.$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())@fiapx.com",
    [string]$Senha = 'senha1234',
    [string]$Nome = 'Smoke Test',
    [int]$Tentativas = 60,
    [int]$IntervaloSegundos = 3
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $VideoPath)) {
    throw "arquivo de video nao encontrado: $VideoPath"
}

function Invoke-Json {
    param(
        [string]$Metodo,
        [string]$Url,
        [hashtable]$Corpo,
        [string]$Token
    )
    $parametros = @{
        Method      = $Metodo
        Uri         = $Url
        ContentType = 'application/json; charset=utf-8'
    }
    if ($Corpo) {
        $parametros.Body = [System.Text.Encoding]::UTF8.GetBytes(($Corpo | ConvertTo-Json -Compress))
    }
    if ($Token) {
        $parametros.Headers = @{ Authorization = "Bearer $Token" }
    }
    return Invoke-RestMethod @parametros
}

Write-Host '==> registrando usuario'
try {
    $null = Invoke-Json -Metodo 'POST' -Url "$AuthUrl/api/auth/register" -Corpo @{ nome = $Nome; email = $Email; senha = $Senha }
    Write-Host '  register: 201'
}
catch {
    $codigo = $_.Exception.Response.StatusCode.value__
    if ($codigo -eq 409) {
        Write-Host '  register: 409 (usuario ja existe, seguindo)'
    }
    else {
        throw "falha no cadastro ($codigo): $($_.Exception.Message)"
    }
}

Write-Host '==> autenticando'
$login = Invoke-Json -Metodo 'POST' -Url "$AuthUrl/api/auth/login" -Corpo @{ email = $Email; senha = $Senha }
$token = $login.accessToken
if (-not $token) { throw 'login sem accessToken' }

Write-Host "==> enviando $VideoPath"
$uploadResposta = & curl.exe -sS -X POST "$VideoUrl/api/videos" `
    -H "Authorization: Bearer $token" `
    -F "arquivo=@$VideoPath"
if ($LASTEXITCODE -ne 0) { throw "falha no upload (curl exit $LASTEXITCODE)" }
$video = $uploadResposta | ConvertFrom-Json
if (-not $video.id) { throw "falha no upload: $uploadResposta" }
Write-Host "  videoId=$($video.id) status=$($video.status)"

Write-Host '==> aguardando processamento'
$statusVideo = $video.status
for ($i = 1; $i -le $Tentativas; $i++) {
    $atual = Invoke-Json -Metodo 'GET' -Url "$VideoUrl/api/videos/$($video.id)" -Token $token
    $statusVideo = $atual.status
    Write-Host "  tentativa $i`: $statusVideo"
    if ($statusVideo -eq 'CONCLUIDO') { break }
    if ($statusVideo -eq 'ERRO') { throw "processamento falhou: motivo=$($atual.mensagemErro)" }
    Start-Sleep -Seconds $IntervaloSegundos
}

if ($statusVideo -ne 'CONCLUIDO') {
    throw "timeout aguardando o processamento (ultimo status: $statusVideo)"
}

Write-Host '==> baixando ZIP'
$zip = Join-Path $env:TEMP "frames-$($video.id).zip"
& curl.exe -sS -f -o $zip "$VideoUrl/api/videos/$($video.id)/download" -H "Authorization: Bearer $token"
if ($LASTEXITCODE -ne 0) { throw 'falha no download do ZIP' }

Add-Type -AssemblyName System.IO.Compression.FileSystem
$arquivoZip = [System.IO.Compression.ZipFile]::OpenRead($zip)
$frames = @($arquivoZip.Entries | Where-Object { $_.Name -like 'frame_*' })
$arquivoZip.Dispose()

Write-Host "  frames no ZIP: $($frames.Count)"
if ($frames.Count -lt 1) { throw 'ZIP sem frames' }

Write-Host "OK: fluxo completo validado (video $($video.id), $($frames.Count) frames)"
