# Cria os repositorios no GitHub e envia a branch main dos quatro projetos da Fase 5.
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File .\scripts\publicar-github.ps1
#   powershell -ExecutionPolicy Bypass -File .\scripts\publicar-github.ps1 -Privado
#   powershell -ExecutionPolicy Bypass -File .\scripts\publicar-github.ps1 -Simular
#
# Requisitos: gh autenticado (gh auth login) com escopo repo.
param(
    [string]$Owner = 'rtmaraujo',
    [switch]$Privado,
    [switch]$Simular
)

$ErrorActionPreference = 'Continue'

$raiz = Split-Path $PSScriptRoot -Parent

$repos = @(
    @{ Nome = 'tc-fiapx-auth-service';       Diretorio = (Join-Path $raiz 'tc-fiapx-auth-service');       Descricao = 'FIAP X Fase 5 - autenticacao e emissao de JWT (Spring Boot 4 + Java 21)' }
    @{ Nome = 'tc-fiapx-video-service';      Diretorio = (Join-Path $raiz 'tc-fiapx-video-service');      Descricao = 'FIAP X Fase 5 - upload, status, download e notificacao de falhas (Spring Boot 4 + Java 21)' }
    @{ Nome = 'tc-fiapx-processing-service'; Diretorio = (Join-Path $raiz 'tc-fiapx-processing-service'); Descricao = 'FIAP X Fase 5 - extracao de frames com FFmpeg e mensageria Kafka (Spring Boot 4 + Java 21)' }
    @{ Nome = 'tc-fiapx-docs';               Diretorio = $raiz;                                         Descricao = 'FIAP X Fase 5 - documentacao C4, infraestrutura Docker/Kubernetes, observabilidade e Postman' }
)

$visibilidade = if ($Privado) { '--private' } else { '--public' }
$falhas = @()

foreach ($repo in $repos) {
    $nome = $repo.Nome
    $dir = $repo.Diretorio
    Write-Host "==> $Owner/$nome ($($repo.Descricao))"

    if (-not (Test-Path $dir)) {
        throw "diretorio nao encontrado: $dir"
    }

    $pendente = git -C $dir status --porcelain
    if ($pendente) {
        Write-Warning "  ha alteracoes nao commitadas em $dir; elas NAO serao publicadas"
    }

    gh repo view "$Owner/$nome" --json name 2>$null | Out-Null
    $existe = ($LASTEXITCODE -eq 0)
    if (-not $existe) {
        $argumentos = @('repo', 'create', "$Owner/$nome", $visibilidade,
            '--description', $repo.Descricao, '--disable-wiki')
        if ($Simular) {
            Write-Host "  [simulacao] gh $($argumentos -join ' ')"
        }
        else {
            & gh @argumentos
            if ($LASTEXITCODE -ne 0) {
                $falhas += "$nome (criacao)"
                continue
            }
        }
    }
    else {
        Write-Host "  repositorio ja existe, seguindo para o push"
    }

    $remote = git -C $dir remote get-url origin 2>$null
    $semRemote = ($LASTEXITCODE -ne 0 -or -not $remote)
    if ($semRemote) {
        if ($Simular) {
            Write-Host "  [simulacao] git remote add origin https://github.com/$Owner/$nome.git"
        }
        else {
            git -C $dir remote add origin "https://github.com/$Owner/$nome.git"
        }
    }
    elseif ($remote -notmatch [regex]::Escape("$Owner/$nome")) {
        Write-Warning "  origin aponta para $remote; ajuste manualmente antes do push"
    }

    if ($Simular) {
        Write-Host "  [simulacao] git push -u origin main"
    }
    else {
        git -C $dir push -u origin main
        if ($LASTEXITCODE -ne 0) {
            $falhas += "$nome (push)"
            continue
        }
    }
    Write-Host "  ok: https://github.com/$Owner/$nome"
}

if ($falhas.Count -gt 0) {
    Write-Error ("falhas: " + ($falhas -join ', '))
    exit 1
}

Write-Host 'Publicacao concluida.'
