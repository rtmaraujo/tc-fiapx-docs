# Provisiona uma instancia Ubuntu 24.04 com k3s no AWS Academy (learner lab).
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File .\deploy\aws\bootstrap.ps1
#
# Requisitos: AWS CLI v2 configurado (AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY/
# AWS_SESSION_TOKEN no ambiente), ssh e scp disponiveis.
param(
    [string]$Region = 'us-west-2',
    [string]$Name = 'fiapx-k3s',
    [string]$InstanceType = 't3.large',
    [int]$VolumeGb = 30,
    [string]$SshCidr = '0.0.0.0/0',
    [string]$KeyPath = "$HOME\.ssh\fiapx-k3s.pem",
    [string]$KubeConfigPath = "$HOME\.kube\fiapx-k3s.yaml"
)

$ErrorActionPreference = 'Continue'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$userData = Join-Path $PSScriptRoot 'k3s-user-data.sh'
$sshOptions = @('-o', 'StrictHostKeyChecking=no', '-o', "UserKnownHostsFile=$env:TEMP\fiapx_known_hosts", '-o', 'ConnectTimeout=10')

function Invoke-Aws {
    param([string[]]$Argumentos, [switch]$PermitirFalha)
    $saida = & aws @Argumentos --region $Region 2>&1
    if ($LASTEXITCODE -ne 0) {
        if ($PermitirFalha) { return $null }
        throw "aws $($Argumentos -join ' ') falhou: $saida"
    }
    return ($saida | Out-String).Trim()
}

Write-Host '==> validando credenciais'
$identidade = Invoke-Aws @('sts', 'get-caller-identity')
if (-not $identidade) { throw 'AWS CLI sem credenciais validas' }
Write-Host "  conta: $((($identidade | ConvertFrom-Json).Account))"

Write-Host '==> chave SSH'
$chaveExiste = Invoke-Aws @('ec2', 'describe-key-pairs', '--key-names', $Name) -PermitirFalha
if (-not $chaveExiste) {
    $material = Invoke-Aws @('ec2', 'create-key-pair', '--key-name', $Name, '--query', 'KeyMaterial', '--output', 'text')
    $dirChave = Split-Path $KeyPath -Parent
    if (-not (Test-Path $dirChave)) { New-Item -ItemType Directory -Path $dirChave -Force | Out-Null }
    [System.IO.File]::WriteAllText($KeyPath, ($material -replace "`r`n", "`n"))
    Write-Host "  chave criada em $KeyPath"
}
else {
    Write-Host "  chave $Name ja existe"
    if (-not (Test-Path $KeyPath)) { throw "a chave $Name existe na AWS mas o arquivo $KeyPath nao foi encontrado" }
}

Write-Host '==> security group'
$vpcId = Invoke-Aws @('ec2', 'describe-vpcs', '--filters', 'Name=isDefault,Values=true', '--query', 'Vpcs[0].VpcId', '--output', 'text')
$sgId = Invoke-Aws @('ec2', 'describe-security-groups', '--filters', "Name=group-name,Values=$Name", "Name=vpc-id,Values=$vpcId", '--query', 'SecurityGroups[0].GroupId', '--output', 'text')
if (-not $sgId -or $sgId -eq 'None') {
    $sgId = Invoke-Aws @('ec2', 'create-security-group', '--group-name', $Name, '--description', 'FIAP X k3s (HTTP, HTTPS, SSH, kubectl e NodePorts)', '--vpc-id', $vpcId, '--query', 'GroupId', '--output', 'text')
    Write-Host "  criado $sgId"
}
foreach ($porta in @(22, 80, 443, 6443, 30090, 30300, 30825, 30888, 30941)) {
    $null = Invoke-Aws @('ec2', 'authorize-security-group-ingress', '--group-id', $sgId, '--protocol', 'tcp', '--port', "$porta", '--cidr', $SshCidr) -PermitirFalha
}
Write-Host "  $sgId liberado (SSH/HTTP/HTTPS/6443/NodePorts)"

Write-Host '==> AMI Ubuntu 24.04'
$amiId = Invoke-Aws @(
    'ec2', 'describe-images', '--owners', '099720109477',
    '--filters', 'Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*', 'Name=state,Values=available',
    '--query', 'Images | sort_by(@,&CreationDate)[-1].ImageId', '--output', 'text'
)
Write-Host "  $amiId"

Write-Host '==> instancia'
$existente = Invoke-Aws @(
    'ec2', 'describe-instances',
    '--filters', "Name=tag:Name,Values=$Name", 'Name=instance-state-name,Values=pending,running',
    '--query', 'Reservations[].Instances[0].InstanceId', '--output', 'text'
)
if ($existente) {
    $instanceId = ($existente -split "\s+")[0]
    Write-Host "  reutilizando $instanceId"
}
else {
    $userDataUri = 'file://' + ((Resolve-Path $userData).Path -replace '\\', '/')
    $instanceId = Invoke-Aws @(
        'ec2', 'run-instances',
        '--image-id', $amiId,
        '--instance-type', $InstanceType,
        '--key-name', $Name,
        '--security-group-ids', $sgId,
        '--count', '1',
        '--user-data', $userDataUri,
        '--block-device-mappings', "[{`"DeviceName`":`"/dev/sda1`",`"Ebs`":{`"VolumeSize`":$VolumeGb,`"VolumeType`":`"gp3`",`"DeleteOnTermination`":true}}]",
        '--tag-specifications', "ResourceType=instance,Tags=[{Key=Name,Value=$Name}]",
        '--query', 'Instances[0].InstanceId', '--output', 'text'
    )
    Write-Host "  criada $instanceId ($InstanceType, ${VolumeGb}GB gp3)"
}

Write-Host '==> aguardando a instancia'
$null = Invoke-Aws @('ec2', 'wait', 'instance-running', '--instance-ids', $instanceId)
$ip = Invoke-Aws @('ec2', 'describe-instances', '--instance-ids', $instanceId, '--query', 'Reservations[0].Instances[0].PublicIpAddress', '--output', 'text')
Write-Host "  ip publico: $ip"

Write-Host '==> aguardando o k3s (pode levar alguns minutos)'
$pronto = $false
for ($i = 1; $i -le 90; $i++) {
    Start-Sleep -Seconds 10
    $teste = & ssh @sshOptions -i $KeyPath "ubuntu@$ip" 'test -f /var/log/fiapx-ready && echo pronta' 2>$null
    if ($teste -match 'pronta') { $pronto = $true; break }
}
if (-not $pronto) {
    & ssh @sshOptions -i $KeyPath "ubuntu@$ip" 'sudo tail -20 /var/log/fiapx-bootstrap.log' 2>&1
    throw 'k3s nao ficou pronto no tempo esperado'
}
Write-Host "  k3s pronto apos ~$($i * 10)s"

Write-Host '==> baixando kubeconfig'
$dirKube = Split-Path $KubeConfigPath -Parent
if (-not (Test-Path $dirKube)) { New-Item -ItemType Directory -Path $dirKube -Force | Out-Null }
$temp = Join-Path $env:TEMP 'k3s.yaml'
& scp @sshOptions -i $KeyPath "ubuntu@$ip:/etc/rancher/k3s/k3s.yaml" $temp | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'falha ao copiar o kubeconfig' }
$conteudo = (Get-Content $temp -Raw) -replace 'https://127\.0\.0\.1:6443', "https://${ip}:6443"
[System.IO.File]::WriteAllText($KubeConfigPath, $conteudo)
Remove-Item $temp -Force

Write-Host ''
Write-Host "k3s disponivel em https://${ip}:6443"
Write-Host "kubeconfig: $KubeConfigPath"
Write-Host ''
Write-Host 'Proximo passo:'
Write-Host "  `$env:KUBECONFIG='$KubeConfigPath'"
Write-Host '  powershell -ExecutionPolicy Bypass -File .\deploy\deploy.ps1'
