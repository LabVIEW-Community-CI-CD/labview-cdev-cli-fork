Set-StrictMode -Version Latest

function Resolve-CdevPowerShellHost {
    [CmdletBinding()]
    param()

    $isWindowsHost = [string]::Equals($env:OS, 'Windows_NT', [System.StringComparison]::OrdinalIgnoreCase)
    $candidates = if ($isWindowsHost) {
        @('powershell.exe', 'powershell', 'pwsh.exe', 'pwsh')
    } else {
        @('pwsh', 'pwsh.exe', 'powershell', 'powershell.exe')
    }

    foreach ($candidate in $candidates) {
        $command = Get-Command -Name $candidate -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace($command.Source)) {
            return $command.Source
        }
    }

    throw "Unable to resolve a PowerShell host executable (tried: $($candidates -join ', '))."
}

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
    param([string[]]$InputArgs)

    $map = @{}
    if ($null -eq $InputArgs) {
        return $map
    }

    $i = 0
    while ($i -lt $InputArgs.Count) {
        $token = [string]$InputArgs[$i]
        if (-not $token.StartsWith('--')) {
            $i++
            continue
        }

        $key = $token.Substring(2)
        $value = $true
        if (($i + 1) -lt $InputArgs.Count -and -not ([string]$InputArgs[$i + 1]).StartsWith('--')) {
            $value = [string]$InputArgs[$i + 1]
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

    $powerShellHost = Resolve-CdevPowerShellHost
    $argList = @('-NoProfile')
    if ([string]::Equals($env:OS, 'Windows_NT', [System.StringComparison]::OrdinalIgnoreCase)) {
        $argList += @('-ExecutionPolicy', 'RemoteSigned')
    }
    $argList += @('-File', $ScriptPath)
    if ($null -ne $Arguments -and $Arguments.Count -gt 0) {
        $argList += $Arguments
    }

    & $powerShellHost @argList
    $exitCode = if ($LASTEXITCODE -ne $null) { [int]$LASTEXITCODE } else { 0 }

    return [pscustomobject]@{
        script = $ScriptPath
        host = $powerShellHost
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
