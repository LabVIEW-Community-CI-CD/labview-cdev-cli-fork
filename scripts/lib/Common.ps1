Set-StrictMode -Version Latest

function Get-CdevRepoRoot {
    param([Parameter(Mandatory = $true)][string]$ScriptPath)
    return (Resolve-Path -Path (Join-Path (Split-Path -Parent $ScriptPath) '..')).Path
}

function Resolve-CdevSurfaceRoot {
    param([string]$SurfaceRoot)

    $candidate = $SurfaceRoot
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        $candidate = $env:CDEV_SURFACE_ROOT
    }
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        $candidate = 'C:\dev\labview-cdev-surface'
    }

    $resolved = [System.IO.Path]::GetFullPath($candidate)
    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
        throw "Surface root not found: $resolved"
    }

    return $resolved
}

function Ensure-CdevDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Assert-CdevCommand {
    param([Parameter(Mandatory = $true)][string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found on PATH."
    }
}

function Convert-CdevArgsToMap {
    param([string[]]$Args)

    $map = @{}
    if ($null -eq $Args) {
        return $map
    }

    $i = 0
    while ($i -lt $Args.Count) {
        $token = [string]$Args[$i]
        if (-not $token.StartsWith('--')) {
            $i++
            continue
        }

        $key = $token.Substring(2)
        $value = $true
        if (($i + 1) -lt $Args.Count -and -not [string]$Args[$i + 1] -like '--*') {
            $value = [string]$Args[$i + 1]
            $i += 2
        } else {
            $i += 1
        }
        $map[$key] = $value
    }

    return $map
}

function Invoke-CdevPwshScript {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [string[]]$Arguments
    )

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        throw "Script not found: $ScriptPath"
    }

    $argList = @('-NoProfile', '-File', $ScriptPath)
    if ($null -ne $Arguments -and $Arguments.Count -gt 0) {
        $argList += $Arguments
    }

    & pwsh @argList
    $exitCode = $LASTEXITCODE

    return [pscustomobject]@{
        script = $ScriptPath
        arguments = @($Arguments)
        exit_code = $exitCode
        status = if ($exitCode -eq 0) { 'succeeded' } else { 'failed' }
    }
}

function New-CdevResult {
    param(
        [string]$Status = 'succeeded',
        [string[]]$InvokedScripts = @(),
        [string[]]$Reports = @(),
        [string[]]$Errors = @(),
        $Data = $null
    )

    return [pscustomobject]@{
        status = $Status
        invoked_scripts = @($InvokedScripts)
        reports = @($Reports)
        errors = @($Errors)
        data = $Data
    }
}

function Write-CdevRunReport {
    param(
        [Parameter(Mandatory = $true)][string]$ReportPath,
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string[]]$Args,
        [Parameter(Mandatory = $true)]$Result
    )

    Ensure-CdevDirectory -Path (Split-Path -Parent $ReportPath)

    [ordered]@{
        timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
        command = $Command
        args = @($Args)
        status = [string]$Result.status
        invoked_scripts = @($Result.invoked_scripts)
        reports = @($Result.reports)
        errors = @($Result.errors)
        data = $Result.data
    } | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $ReportPath -Encoding utf8
}
