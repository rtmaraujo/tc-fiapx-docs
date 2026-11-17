# Derruba os recursos criados pelo bootstrap.ps1 (instancia, security group e chave).
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File .\deploy\aws\teardown.ps1
#   powershell -ExecutionPolicy Bypass -File .\deploy\aws\teardown.ps1 -KeepKeyPair
param(
    [string]$Region = 'us-west-2',
    [string]$Name = 'fiapx-k3s',
    [switch]$KeepKeyPair
)

$ErrorActionPreference = 'Continue'

function Invoke-Aws {
    param([string[]]$Argumentos, [switch]$PermitirFalha)
    $saida = & aws @Argumentos --region $Region 2>&1
    if ($LASTEXITCODE -ne 0) {
        if ($PermitirFalha) { return $null }
        throw "aws $($Argumentos -join ' ') falhou: $saida"
    }
    return ($saida | Out-String).Trim()
}

Write-Host '==> procurando instancias'
$ids = Invoke-Aws @(
    'ec2', 'describe-instances',
    '--filters', "Name=tag:Name,Values=$Name", 'Name=instance-state-name,Values=pending,running,stopping,stopped',
    '--query', 'Reservations[].Instances[].InstanceId', '--output', 'text'
)
if ($ids) {
    $lista = $ids -split "\s+" | Where-Object { $_ }
    Write-Host "  terminando: $($lista -join ', ')"
    $null = Invoke-Aws (@('ec2', 'terminate-instances', '--instance-ids') + $lista)
    $null = Invoke-Aws (@('ec2', 'wait', 'instance-terminated', '--instance-ids') + $lista)
}
else {
    Write-Host '  nenhuma instancia ativa'
}

Write-Host '==> removendo security group'
$sgId = Invoke-Aws @(
    'ec2', 'describe-security-groups',
    '--filters', "Name=group-name,Values=$Name",
    '--query', 'SecurityGroups[0].GroupId', '--output', 'text'
) -PermitirFalha
if ($sgId -and $sgId -ne 'None') {
    $removeu = $false
    for ($i = 1; $i -le 12; $i++) {
        $null = Invoke-Aws @('ec2', 'delete-security-group', '--group-id', $sgId) -PermitirFalha
        if ($LASTEXITCODE -eq 0) { $removeu = $true; break }
        Start-Sleep -Seconds 10
    }
    if ($removeu) { Write-Host "  $sgId removido" } else { Write-Warning "  nao foi possivel remover $sgId (interfaces ainda em uso)" }
}

if (-not $KeepKeyPair) {
    Write-Host '==> removendo key pair'
    $null = Invoke-Aws @('ec2', 'delete-key-pair', '--key-name', $Name) -PermitirFalha
    Write-Host "  chave $Name removida da AWS (o arquivo local nao e apagado)"
}

Write-Host ''
Write-Host 'Recursos da AWS removidos. O kubeconfig local pode ser apagado manualmente.'
