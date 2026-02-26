#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
    [string]$UpstreamRepository = 'LabVIEW-Community-CI-CD/labview-cdev-cli',

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
    [string]$ForkRepository = 'svelderrainruiz/labview-cdev-cli',

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9._/-]+$')]
    [string]$UpstreamBranch = 'main',

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9._/-]+$')]
    [string]$ForkBranch = 'main',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = (Join-Path (Get-Location) 'fork-upstream-sync-drift-report.json')
)

$ErrorActionPreference = 'Stop'

function Invoke-GhQuery {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [Parameter(Mandatory)]
        [string]$Description
    )

    $result = & gh @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to query $Description."
    }
    return [string]$result
}

function Get-ReleaseAssetDigestMap {
    param(
        [Parameter(Mandatory)]
        [string]$Repository,

        [Parameter(Mandatory)]
        [string]$Tag
    )

    $json = & gh release view $Tag -R $Repository --json assets
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to query release '$Tag' in '$Repository'."
    }

    $release = $json | ConvertFrom-Json -ErrorAction Stop
    $map = @{}
    foreach ($asset in @($release.assets)) {
        $name = [string]$asset.name
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $map[$name] = [string]$asset.digest
        }
    }
    return $map
}

if (-not (Get-Command -Name 'gh' -ErrorAction SilentlyContinue)) {
    throw 'GitHub CLI (gh) is required for sync guard checks.'
}

$upstreamHead = (Invoke-GhQuery -Arguments @('api', "repos/$UpstreamRepository/commits/$UpstreamBranch", '--jq', '.sha') -Description "upstream branch head").Trim()
$forkHead = (Invoke-GhQuery -Arguments @('api', "repos/$ForkRepository/commits/$ForkBranch", '--jq', '.sha') -Description "fork branch head").Trim()
$upstreamLatestTag = (Invoke-GhQuery -Arguments @('api', "repos/$UpstreamRepository/releases/latest", '--jq', '.tag_name') -Description "upstream latest release tag").Trim()
$forkLatestTag = (Invoke-GhQuery -Arguments @('api', "repos/$ForkRepository/releases/latest", '--jq', '.tag_name') -Description "fork latest release tag").Trim()

$upstreamAssetDigests = Get-ReleaseAssetDigestMap -Repository $UpstreamRepository -Tag $upstreamLatestTag
$forkAssetDigests = Get-ReleaseAssetDigestMap -Repository $ForkRepository -Tag $forkLatestTag

$requiredAssets = @(
    'cdev-cli-win-x64.zip',
    'cdev-cli-linux-x64.tar.gz'
)

$mismatches = @()
$branchMatches = [string]::Equals($upstreamHead, $forkHead, [System.StringComparison]::Ordinal)
if (-not $branchMatches) {
    $mismatches += 'main_head'
}

$releaseMatches = [string]::Equals($upstreamLatestTag, $forkLatestTag, [System.StringComparison]::Ordinal)
if (-not $releaseMatches) {
    $mismatches += 'latest_release_tag'
}

$assetParity = @()
foreach ($assetName in $requiredAssets) {
    $upstreamDigest = [string]$upstreamAssetDigests[$assetName]
    $forkDigest = [string]$forkAssetDigests[$assetName]
    $assetMatches = (-not [string]::IsNullOrWhiteSpace($upstreamDigest)) -and
        (-not [string]::IsNullOrWhiteSpace($forkDigest)) -and
        [string]::Equals($upstreamDigest, $forkDigest, [System.StringComparison]::Ordinal)

    if (-not $assetMatches) {
        $mismatches += "asset_digest:$assetName"
    }

    $assetParity += [ordered]@{
        asset = $assetName
        upstream_digest = $upstreamDigest
        fork_digest = $forkDigest
        matches = $assetMatches
    }
}

$report = [ordered]@{
    schema_version = '1.0'
    generated_at_utc = [DateTime]::UtcNow.ToString('o')
    upstream_repository = $UpstreamRepository
    fork_repository = $ForkRepository
    branch_parity = [ordered]@{
        upstream_branch = $UpstreamBranch
        fork_branch = $ForkBranch
        upstream_head = $upstreamHead
        fork_head = $forkHead
        matches = $branchMatches
    }
    release_parity = [ordered]@{
        upstream_latest_tag = $upstreamLatestTag
        fork_latest_tag = $forkLatestTag
        matches = $releaseMatches
    }
    asset_parity = @($assetParity)
    status = if ($mismatches.Count -eq 0) { 'in_sync' } else { 'drift_detected' }
    mismatches = @($mismatches)
}

$outputDirectory = Split-Path -Path $OutputPath -Parent
if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM
Write-Host "Sync guard report written: $OutputPath"

if ($mismatches.Count -gt 0) {
    throw "Drift detected: $($mismatches -join ', ')"
}
