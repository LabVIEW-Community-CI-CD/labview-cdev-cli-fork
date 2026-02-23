function Invoke-CdevInstallerBuild {
    param(
        [Parameter(Mandatory = $true)][string]$SurfaceRoot,
        [string]$OutputRoot
    )

    $scriptPath = Join-Path $SurfaceRoot 'scripts\Exercise-WorkspaceInstallerLocal.ps1'
    $resolvedOutput = if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
        Join-Path $SurfaceRoot 'artifacts\release\cli-build'
    } else {
        [System.IO.Path]::GetFullPath($OutputRoot)
    }

    $run = Invoke-CdevPwshScript -ScriptPath $scriptPath -Arguments @(
        '-OutputRoot', $resolvedOutput,
        '-SkipSmokeBuild',
        '-SkipSmokeInstall'
    )

    $status = if ($run.exit_code -eq 0) { 'succeeded' } else { 'failed' }
    $errors = @()
    if ($run.exit_code -ne 0) { $errors += "Installer build failed with exit code $($run.exit_code)." }

    return (New-CdevResult -Status $status -InvokedScripts @($run.script) -Reports @(Join-Path $resolvedOutput 'exercise-report.json') -Errors $errors -Data ([ordered]@{
        output_root = $resolvedOutput
    }))
}

function Invoke-CdevInstallerExercise {
    param(
        [Parameter(Mandatory = $true)][string]$SurfaceRoot,
        [string[]]$PassThroughArgs
    )

    $scriptPath = Join-Path $SurfaceRoot 'scripts\Invoke-WorkspaceInstallerIteration.ps1'
    $run = Invoke-CdevPwshScript -ScriptPath $scriptPath -Arguments @($PassThroughArgs)

    $status = if ($run.exit_code -eq 0) { 'succeeded' } else { 'failed' }
    $errors = @()
    if ($run.exit_code -ne 0) { $errors += "Installer exercise failed with exit code $($run.exit_code)." }

    return (New-CdevResult -Status $status -InvokedScripts @($run.script) -Errors $errors)
}

function Invoke-CdevInstallerInstall {
    param(
        [Parameter(Mandatory = $true)][string]$InstallerPath,
        [string]$ExpectedReportPath = 'C:\dev\artifacts\workspace-install-latest.json'
    )

    $resolvedInstaller = [System.IO.Path]::GetFullPath($InstallerPath)
    if (-not (Test-Path -LiteralPath $resolvedInstaller -PathType Leaf)) {
        throw "Installer not found: $resolvedInstaller"
    }

    $proc = Start-Process -FilePath $resolvedInstaller -ArgumentList '/S' -Wait -PassThru
    $errors = @()
    if ($proc.ExitCode -ne 0) {
        $errors += "Installer exited with code $($proc.ExitCode)."
    }

    $reports = @()
    if (Test-Path -LiteralPath $ExpectedReportPath -PathType Leaf) {
        $reports += $ExpectedReportPath
    } else {
        $errors += "Expected installer report not found: $ExpectedReportPath"
    }

    $status = if ($errors.Count -eq 0) { 'succeeded' } else { 'failed' }
    return (New-CdevResult -Status $status -Reports $reports -Errors $errors -Data ([ordered]@{
        installer_path = $resolvedInstaller
        exit_code = $proc.ExitCode
        expected_report = $ExpectedReportPath
    }))
}

function Invoke-CdevPostactionsCollect {
    param([string]$ReportPath = 'C:\dev\artifacts\workspace-install-latest.json')

    $resolvedReport = [System.IO.Path]::GetFullPath($ReportPath)
    if (-not (Test-Path -LiteralPath $resolvedReport -PathType Leaf)) {
        throw "Installer report not found: $resolvedReport"
    }

    $report = Get-Content -LiteralPath $resolvedReport -Raw | ConvertFrom-Json -ErrorAction Stop
    $errors = @()

    $ppl32 = [string]$report.ppl_capability_checks.'32'.status
    $ppl64 = [string]$report.ppl_capability_checks.'64'.status
    $vip = [string]$report.vip_package_build_check.status

    if ($ppl32 -ne 'pass') { $errors += "PPL x32 status is '$ppl32'" }
    if ($ppl64 -ne 'pass') { $errors += "PPL x64 status is '$ppl64'" }
    if ($vip -ne 'pass') { $errors += "VIP status is '$vip'" }

    if ($null -ne $report.post_action_sequence) {
        @($report.post_action_sequence) | Select-Object index,phase,bitness,status,message | Format-Table -AutoSize | Out-Host
    }

    $status = if ($errors.Count -eq 0) { 'succeeded' } else { 'failed' }
    return (New-CdevResult -Status $status -Reports @($resolvedReport) -Errors $errors -Data ([ordered]@{
        ppl_32 = $ppl32
        ppl_64 = $ppl64
        vip = $vip
    }))
}
