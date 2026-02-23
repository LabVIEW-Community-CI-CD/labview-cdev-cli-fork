#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter()]
    [string]$SurfaceRoot = 'C:\dev\labview-cdev-surface',

    [Parameter()]
    [string]$ManifestPath,

    [Parameter()]
    [string]$WorkspaceRoot = 'C:\dev-linux',

    [Parameter()]
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) '..\..\artifacts\workspace-install-linux-latest.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Normalize-Url {
    param([string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) { return '' }
    return ($Url.Trim().TrimEnd('/')).ToLowerInvariant()
}

function Add-Sequence {
    param(
        [Parameter(Mandatory = $true)][System.Collections.ArrayList]$Sequence,
        [Parameter(Mandatory = $true)][string]$Phase,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter()][string]$Message = ''
    )
    [void]$Sequence.Add([pscustomobject]@{
        index = $Sequence.Count + 1
        timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
        phase = $Phase
        status = $Status
        message = $Message
    })
}

foreach ($commandName in @('git', 'dotnet', 'pwsh')) {
    if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
        throw "Required command '$commandName' was not found on PATH."
    }
}

$resolvedSurfaceRoot = [System.IO.Path]::GetFullPath($SurfaceRoot)
$resolvedWorkspaceRoot = [System.IO.Path]::GetFullPath($WorkspaceRoot)
$resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$resolvedManifestPath = if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    Join-Path $resolvedSurfaceRoot 'workspace-governance.json'
} else {
    [System.IO.Path]::GetFullPath($ManifestPath)
}

if (-not (Test-Path -LiteralPath $resolvedManifestPath -PathType Leaf)) {
    throw "Manifest not found: $resolvedManifestPath"
}

Ensure-Directory -Path $resolvedWorkspaceRoot
Ensure-Directory -Path (Split-Path -Parent $resolvedOutputPath)

$manifest = Get-Content -LiteralPath $resolvedManifestPath -Raw | ConvertFrom-Json -ErrorAction Stop
$sourceRoot = [string]$manifest.workspace_root
if ([string]::IsNullOrWhiteSpace($sourceRoot)) {
    throw "Manifest is missing workspace_root: $resolvedManifestPath"
}

$repoResults = @()
$errors = @()
$warnings = @()
$postSequence = New-Object System.Collections.ArrayList

foreach ($repo in @($manifest.managed_repos)) {
    $path = [string]$repo.path
    $pinned = ([string]$repo.pinned_sha).ToLowerInvariant()
    $targetPath = $path

    if ($path.StartsWith($sourceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $suffix = $path.Substring($sourceRoot.Length).TrimStart('\')
        $targetPath = if ([string]::IsNullOrWhiteSpace($suffix)) { $resolvedWorkspaceRoot } else { Join-Path $resolvedWorkspaceRoot $suffix }
    }
    $targetPath = [System.IO.Path]::GetFullPath($targetPath)

    $result = [ordered]@{
        path = $targetPath
        repo_name = [string]$repo.repo_name
        required_gh_repo = [string]$repo.required_gh_repo
        status = 'pass'
        issues = @()
        pinned_sha = $pinned
        head_sha = ''
    }

    try {
        if ($pinned -notmatch '^[0-9a-f]{40}$') {
            throw "Invalid pinned_sha '$pinned'"
        }

        $originUrl = [string]$repo.required_remotes.origin
        if ([string]::IsNullOrWhiteSpace($originUrl)) {
            throw "Missing required_remotes.origin"
        }

        if (-not (Test-Path -LiteralPath $targetPath -PathType Container)) {
            Ensure-Directory -Path (Split-Path -Parent $targetPath)
            & git clone $originUrl $targetPath
            if ($LASTEXITCODE -ne 0) {
                throw "git clone failed for $targetPath"
            }
        }

        if (-not (Test-Path -LiteralPath (Join-Path $targetPath '.git') -PathType Container)) {
            throw "Not a git repository: $targetPath"
        }

        foreach ($remoteProp in $repo.required_remotes.PSObject.Properties) {
            $remoteName = [string]$remoteProp.Name
            $expectedUrl = [string]$remoteProp.Value
            if ([string]::IsNullOrWhiteSpace($remoteName) -or [string]::IsNullOrWhiteSpace($expectedUrl)) { continue }

            $current = (& git -C $targetPath remote get-url $remoteName 2>$null).Trim()
            if ($LASTEXITCODE -ne 0) {
                & git -C $targetPath remote add $remoteName $expectedUrl
                if ($LASTEXITCODE -ne 0) { throw "Failed to add remote $remoteName" }
                $current = (& git -C $targetPath remote get-url $remoteName).Trim()
            }

            if ((Normalize-Url $current) -ne (Normalize-Url $expectedUrl)) {
                $result.status = 'fail'
                $result.issues += "remote_mismatch_$remoteName"
            }
        }

        & git -C $targetPath fetch --no-tags origin
        if ($LASTEXITCODE -ne 0) { throw "git fetch failed for $targetPath" }

        & git -C $targetPath checkout --detach $pinned
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to checkout pinned SHA '$pinned'"
        }

        $head = (& git -C $targetPath rev-parse HEAD).Trim().ToLowerInvariant()
        $result.head_sha = $head
        if ($head -ne $pinned) {
            $result.status = 'fail'
            $result.issues += 'head_sha_mismatch'
        }
    } catch {
        $result.status = 'fail'
        $result.issues += 'exception'
        $errors += "$targetPath :: $($_.Exception.Message)"
    }

    if ($result.status -ne 'pass') {
        $errors += "$targetPath :: repository contract failed"
    }

    $repoResults += [pscustomobject]$result
}

$repoFailureCount = @($repoResults | Where-Object { [string]$_.status -ne 'pass' }).Count
if ($repoFailureCount -eq 0) {
    Add-Sequence -Sequence $postSequence -Phase 'repository-contracts' -Status 'pass' -Message 'All managed repos satisfied pinned contract.'
} else {
    Add-Sequence -Sequence $postSequence -Phase 'repository-contracts' -Status 'fail' -Message "$repoFailureCount repo contracts failed."
}

$runnerCliResult = [ordered]@{
    status = 'not_run'
    message = ''
    output_root = Join-Path $resolvedWorkspaceRoot 'tools\runner-cli\linux-x64'
}

try {
    $bundleScript = Join-Path $resolvedSurfaceRoot 'scripts\Build-RunnerCliBundleFromManifest.ps1'
    if (-not (Test-Path -LiteralPath $bundleScript -PathType Leaf)) {
        throw "Bundle script not found: $bundleScript"
    }

    Ensure-Directory -Path $runnerCliResult.output_root

    & pwsh -NoProfile -File $bundleScript `
        -ManifestPath $resolvedManifestPath `
        -OutputRoot $runnerCliResult.output_root `
        -RepoName 'labview-icon-editor' `
        -Runtime 'linux-x64' `
        -Deterministic:$true

    if ($LASTEXITCODE -ne 0) {
        throw "Build-RunnerCliBundleFromManifest failed with exit code $LASTEXITCODE"
    }

    $runnerCliResult.status = 'pass'
    $runnerCliResult.message = 'linux-x64 runner-cli bundle built from manifest pin.'
} catch {
    $runnerCliResult.status = 'fail'
    $runnerCliResult.message = $_.Exception.Message
    $errors += $runnerCliResult.message
}

Add-Sequence -Sequence $postSequence -Phase 'runner-cli-bundle' -Status ([string]$runnerCliResult.status) -Message ([string]$runnerCliResult.message)

$pplChecks = [ordered]@{
    '32' = [ordered]@{ status = 'not_supported'; message = 'LabVIEW Windows-only gate; not supported in linux manifest-native install.' }
    '64' = [ordered]@{ status = 'not_supported'; message = 'LabVIEW Windows-only gate; not supported in linux manifest-native install.' }
}
$vipCheck = [ordered]@{ status = 'not_supported'; message = 'VIP build gate is Windows LabVIEW dependent; not supported in linux manifest-native install.' }

$status = if ($errors.Count -eq 0) { 'succeeded' } else { 'failed' }

[ordered]@{
    timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
    platform = 'linux'
    status = $status
    workspace_root = $resolvedWorkspaceRoot
    surface_root = $resolvedSurfaceRoot
    manifest_path = $resolvedManifestPath
    repositories = $repoResults
    runner_cli_bundle = $runnerCliResult
    ppl_capability_checks = $pplChecks
    vip_package_build_check = $vipCheck
    linux_deploy_check = [ordered]@{ status = 'not_run'; message = 'Run Invoke-NiLinuxDeployCheck.ps1 separately.' }
    post_action_sequence = $postSequence
    warnings = $warnings
    errors = $errors
} | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $resolvedOutputPath -Encoding utf8

Write-Host "Linux install report: $resolvedOutputPath"

if ($status -ne 'succeeded') { exit 1 }
exit 0
