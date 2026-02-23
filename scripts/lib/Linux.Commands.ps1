function Invoke-CdevLinuxInstall {
    param(
        [Parameter(Mandatory = $true)][string]$CliRepoRoot,
        [Parameter(Mandatory = $true)][string]$SurfaceRoot,
        [string[]]$PassThroughArgs
    )

    $scriptPath = Join-Path $CliRepoRoot 'scripts\lib\Install-WorkspaceFromManifest.Linux.ps1'

    $arguments = @('-SurfaceRoot', $SurfaceRoot)
    if ($null -ne $PassThroughArgs -and $PassThroughArgs.Count -gt 0) {
        $arguments += $PassThroughArgs
    }

    $run = Invoke-CdevPwshScript -ScriptPath $scriptPath -Arguments $arguments
    $status = if ($run.exit_code -eq 0) { 'succeeded' } else { 'failed' }
    $errors = @()
    if ($run.exit_code -ne 0) { $errors += "Linux install failed with exit code $($run.exit_code)." }

    return (New-CdevResult -Status $status -InvokedScripts @($run.script) -Reports @() -Errors $errors)
}

function Invoke-CdevLinuxDeployNi {
    param(
        [Parameter(Mandatory = $true)][string]$CliRepoRoot,
        [string[]]$PassThroughArgs
    )

    $scriptPath = Join-Path $CliRepoRoot 'scripts\lib\Invoke-NiLinuxDeployCheck.ps1'

    $run = Invoke-CdevPwshScript -ScriptPath $scriptPath -Arguments @($PassThroughArgs)
    $status = if ($run.exit_code -eq 0) { 'succeeded' } else { 'failed' }
    $errors = @()
    if ($run.exit_code -ne 0) { $errors += "Linux NI deploy check failed with exit code $($run.exit_code)." }

    return (New-CdevResult -Status $status -InvokedScripts @($run.script) -Errors $errors)
}
