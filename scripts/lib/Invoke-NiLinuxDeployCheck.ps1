#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter()]
    [string]$WorkspaceRoot = 'C:\dev-linux',

    [Parameter()]
    [string]$DockerContext = 'desktop-linux',

    [Parameter()]
    [string]$Image = 'nationalinstruments/labview:latest-linux',

    [Parameter()]
    [string]$RepoFolder = 'labview-for-containers',

    [Parameter()]
    [string]$DeployScriptRelativePath = 'examples/integration-into-cicd/runlabview.sh',

    [Parameter()]
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) '..\..\artifacts\ni-linux-deploy-report.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

foreach ($commandName in @('docker', 'pwsh')) {
    if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
        throw "Required command '$commandName' was not found on PATH."
    }
}

$resolvedWorkspace = [System.IO.Path]::GetFullPath($WorkspaceRoot)
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
Ensure-Directory -Path (Split-Path -Parent $resolvedOutput)

$repoPath = Join-Path $resolvedWorkspace $RepoFolder
$deployHostPath = Join-Path $repoPath $DeployScriptRelativePath

$errors = @()
$status = 'succeeded'
$containerExitCode = 0
$logPath = Join-Path (Split-Path -Parent $resolvedOutput) 'ni-linux-deploy.log'

if (-not (Test-Path -LiteralPath $repoPath -PathType Container)) {
    throw "Repository folder not found under workspace root: $repoPath"
}
if (-not (Test-Path -LiteralPath $deployHostPath -PathType Leaf)) {
    throw "Deploy script not found: $deployHostPath"
}

try {
    & docker --context $DockerContext pull $Image
    if ($LASTEXITCODE -ne 0) { throw "docker pull failed for $Image" }

    $workspaceUnix = '/workspace'
    $repoUnix = "$workspaceUnix/$RepoFolder"
    $deployUnix = "$repoUnix/$($DeployScriptRelativePath -replace '\\','/')"

    $cmd = "set -euo pipefail; chmod +x '$deployUnix'; cd '$repoUnix'; '$deployUnix'"

    & docker --context $DockerContext run --rm `
        -v "${resolvedWorkspace}:$workspaceUnix" `
        $Image `
        bash -lc $cmd 2>&1 | Tee-Object -LiteralPath $logPath

    $containerExitCode = $LASTEXITCODE
    if ($containerExitCode -ne 0) {
        throw "Linux deploy check failed with exit code $containerExitCode"
    }
} catch {
    $status = 'failed'
    if ($containerExitCode -eq 0) { $containerExitCode = 1 }
    $errors += $_.Exception.Message
}

[ordered]@{
    timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
    status = $status
    workspace_root = $resolvedWorkspace
    docker_context = $DockerContext
    image = $Image
    repo_folder = $RepoFolder
    deploy_script_relative_path = $DeployScriptRelativePath
    deploy_script_host_path = $deployHostPath
    container_exit_code = $containerExitCode
    log_path = $logPath
    errors = $errors
} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resolvedOutput -Encoding utf8

Write-Host "NI Linux deploy report: $resolvedOutput"
if ($status -ne 'succeeded') { exit 1 }
exit 0
