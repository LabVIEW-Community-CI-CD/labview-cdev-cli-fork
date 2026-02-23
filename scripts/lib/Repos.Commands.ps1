function Invoke-CdevReposList {
    param(
        [Parameter(Mandatory = $true)][string]$SurfaceRoot,
        [string]$ManifestPath
    )

    $resolvedManifest = if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
        Join-Path $SurfaceRoot 'workspace-governance.json'
    } else {
        [System.IO.Path]::GetFullPath($ManifestPath)
    }

    if (-not (Test-Path -LiteralPath $resolvedManifest -PathType Leaf)) {
        throw "Manifest not found: $resolvedManifest"
    }

    $manifest = Get-Content -LiteralPath $resolvedManifest -Raw | ConvertFrom-Json -ErrorAction Stop
    $rows = @($manifest.managed_repos | ForEach-Object {
        [pscustomobject]@{
            path = [string]$_.path
            mode = [string]$_.mode
            required_gh_repo = [string]$_.required_gh_repo
            default_branch = [string]$_.default_branch
            pinned_sha = [string]$_.pinned_sha
        }
    })

    $rows | Format-Table -AutoSize | Out-Host

    return (New-CdevResult -Data ([ordered]@{
        manifest_path = $resolvedManifest
        managed_repo_count = @($rows).Count
        managed_repos = $rows
    }))
}

function Invoke-CdevReposDoctor {
    param(
        [Parameter(Mandatory = $true)][string]$SurfaceRoot,
        [string]$WorkspaceRoot = 'C:\dev'
    )

    $policyScript = Join-Path $SurfaceRoot 'scripts\Test-PolicyContracts.ps1'
    $assertScript = Join-Path $SurfaceRoot 'scripts\Assert-WorkspaceGovernance.ps1'
    $manifestPath = Join-Path $SurfaceRoot 'workspace-governance.json'
    $auditReport = Join-Path $WorkspaceRoot 'artifacts\workspace-governance-latest.json'

    $invoked = @()
    $reports = @()
    $errors = @()

    $policyRun = Invoke-CdevPwshScript -ScriptPath $policyScript -Arguments @('-WorkspaceRoot', $WorkspaceRoot, '-FailOnWarning')
    $invoked += $policyRun.script
    if ($policyRun.exit_code -ne 0) {
        $errors += "Policy contracts failed with exit code $($policyRun.exit_code)."
    }

    $auditRun = Invoke-CdevPwshScript -ScriptPath $assertScript -Arguments @(
        '-WorkspaceRoot', $WorkspaceRoot,
        '-ManifestPath', $manifestPath,
        '-Mode', 'Audit',
        '-OutputPath', $auditReport
    )
    $invoked += $auditRun.script
    if ($auditRun.exit_code -ne 0) {
        $errors += "Workspace governance audit failed with exit code $($auditRun.exit_code)."
    }

    if (Test-Path -LiteralPath $auditReport -PathType Leaf) {
        $reports += $auditReport
    }

    $status = if ($errors.Count -eq 0) { 'succeeded' } else { 'failed' }
    return (New-CdevResult -Status $status -InvokedScripts $invoked -Reports $reports -Errors $errors -Data ([ordered]@{
        workspace_root = $WorkspaceRoot
        audit_report = $auditReport
    }))
}

function Invoke-CdevSurfaceSync {
    param(
        [Parameter(Mandatory = $true)][string]$SurfaceRoot,
        [string]$Ref = 'origin/main'
    )

    & git -C $SurfaceRoot fetch --prune origin
    if ($LASTEXITCODE -ne 0) {
        throw "git fetch failed for $SurfaceRoot"
    }

    $sha = (& git -C $SurfaceRoot rev-parse $Ref).Trim().ToLowerInvariant()
    if ($LASTEXITCODE -ne 0 -or $sha -notmatch '^[0-9a-f]{40}$') {
        throw "Failed to resolve ref '$Ref' in $SurfaceRoot"
    }

    Write-Host "Resolved $Ref => $sha"

    return (New-CdevResult -Data ([ordered]@{
        surface_root = $SurfaceRoot
        reference = $Ref
        resolved_sha = $sha
    }))
}
