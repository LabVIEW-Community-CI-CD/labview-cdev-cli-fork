#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$CommandArgs,

    [Parameter()]
    [string]$SurfaceRoot,

    [Parameter()]
    [string]$ReportPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\cli\cdev-cli-last-run.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$libRoot = Join-Path $PSScriptRoot 'lib'
foreach ($libFile in @(
    'Common.ps1',
    'Repos.Commands.ps1',
    'Installer.Commands.ps1',
    'Linux.Commands.ps1',
    'Ci.Commands.ps1',
    'Release.Commands.ps1'
)) {
    $path = Join-Path $libRoot $libFile
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required library file not found: $path"
    }
    . $path
}

function Show-CdevHelp {
    param([string]$Topic = '')

    $helpLines = @(
        'cdev control-plane CLI',
        '',
        'Usage:',
        '  pwsh -NoProfile -File scripts/Invoke-CdevCli.ps1 <group> <command> [options]',
        '',
        'Groups and commands:',
        '  help [topic]',
        '  repos list',
        '  repos doctor',
        '  surface sync',
        '  installer build',
        '  installer exercise',
        '  installer install',
        '  postactions collect',
        '  linux install',
        '  linux deploy-ni',
        '  ci integration-gate',
        '  release package',
        '',
        'Examples:',
        '  pwsh -NoProfile -File scripts/Invoke-CdevCli.ps1 repos list',
        '  pwsh -NoProfile -File scripts/Invoke-CdevCli.ps1 repos doctor --workspace-root C:\dev',
        '  pwsh -NoProfile -File scripts/Invoke-CdevCli.ps1 installer exercise --mode fast --iterations 1',
        '  pwsh -NoProfile -File scripts/Invoke-CdevCli.ps1 postactions collect --report-path C:\dev\artifacts\workspace-install-latest.json',
        '  pwsh -NoProfile -File scripts/Invoke-CdevCli.ps1 linux install --workspace-root C:\dev-linux',
        '  pwsh -NoProfile -File scripts/Invoke-CdevCli.ps1 linux deploy-ni --workspace-root C:\dev-linux --docker-context desktop-linux'
    )

    if ([string]::IsNullOrWhiteSpace($Topic)) {
        $helpLines | ForEach-Object { Write-Host $_ }
        return
    }

    switch ($Topic) {
        'repos' { Write-Host 'repos commands: list, doctor' }
        'installer' { Write-Host 'installer commands: build, exercise, install' }
        'postactions' { Write-Host 'postactions command: collect' }
        'linux' { Write-Host 'linux commands: install, deploy-ni' }
        'ci' { Write-Host 'ci command: integration-gate' }
        'release' { Write-Host 'release command: package' }
        default {
            Write-Host "Unknown help topic '$Topic'."
            $helpLines | ForEach-Object { Write-Host $_ }
        }
    }
}

Assert-CdevCommand -Name 'pwsh'
$cliRepoRoot = Get-CdevRepoRoot -ScriptPath $PSCommandPath
$resolvedSurfaceRoot = Resolve-CdevSurfaceRoot -SurfaceRoot $SurfaceRoot
$argsMap = Convert-CdevArgsToMap -Args $CommandArgs

$group = if ($CommandArgs.Count -ge 1) { [string]$CommandArgs[0].ToLowerInvariant() } else { 'help' }
$command = if ($CommandArgs.Count -ge 2) { [string]$CommandArgs[1].ToLowerInvariant() } else { '' }
$passThroughArgs = if ($CommandArgs.Count -ge 3) { @($CommandArgs[2..($CommandArgs.Count - 1)]) } else { @() }

$result = $null
$exitCode = 0

try {
    switch ($group) {
        'help' {
            $topic = if ($CommandArgs.Count -ge 2) { [string]$CommandArgs[1].ToLowerInvariant() } else { '' }
            Show-CdevHelp -Topic $topic
            $result = New-CdevResult -Status 'succeeded'
        }
        'repos' {
            switch ($command) {
                'list' {
                    $manifestPath = if ($argsMap.ContainsKey('manifest-path')) { [string]$argsMap['manifest-path'] } else { '' }
                    $result = Invoke-CdevReposList -SurfaceRoot $resolvedSurfaceRoot -ManifestPath $manifestPath
                }
                'doctor' {
                    $workspaceRoot = if ($argsMap.ContainsKey('workspace-root')) { [string]$argsMap['workspace-root'] } else { 'C:\dev' }
                    $result = Invoke-CdevReposDoctor -SurfaceRoot $resolvedSurfaceRoot -WorkspaceRoot $workspaceRoot
                }
                default {
                    throw "Unsupported repos command '$command'. Use 'repos list' or 'repos doctor'."
                }
            }
        }
        'surface' {
            switch ($command) {
                'sync' {
                    $ref = if ($argsMap.ContainsKey('ref')) { [string]$argsMap['ref'] } else { 'origin/main' }
                    $result = Invoke-CdevSurfaceSync -SurfaceRoot $resolvedSurfaceRoot -Ref $ref
                }
                default {
                    throw "Unsupported surface command '$command'. Use 'surface sync'."
                }
            }
        }
        'installer' {
            switch ($command) {
                'build' {
                    $outputRoot = if ($argsMap.ContainsKey('output-root')) { [string]$argsMap['output-root'] } else { '' }
                    $result = Invoke-CdevInstallerBuild -SurfaceRoot $resolvedSurfaceRoot -OutputRoot $outputRoot
                }
                'exercise' {
                    $result = Invoke-CdevInstallerExercise -SurfaceRoot $resolvedSurfaceRoot -PassThroughArgs $passThroughArgs
                }
                'install' {
                    if (-not $argsMap.ContainsKey('installer-path')) {
                        throw 'installer install requires --installer-path <path>.'
                    }
                    $reportPath = if ($argsMap.ContainsKey('report-path')) { [string]$argsMap['report-path'] } else { 'C:\dev\artifacts\workspace-install-latest.json' }
                    $result = Invoke-CdevInstallerInstall -InstallerPath ([string]$argsMap['installer-path']) -ExpectedReportPath $reportPath
                }
                default {
                    throw "Unsupported installer command '$command'."
                }
            }
        }
        'postactions' {
            switch ($command) {
                'collect' {
                    $reportPath = if ($argsMap.ContainsKey('report-path')) { [string]$argsMap['report-path'] } else { 'C:\dev\artifacts\workspace-install-latest.json' }
                    $result = Invoke-CdevPostactionsCollect -ReportPath $reportPath
                }
                default {
                    throw "Unsupported postactions command '$command'. Use 'postactions collect'."
                }
            }
        }
        'linux' {
            switch ($command) {
                'install' {
                    $result = Invoke-CdevLinuxInstall -CliRepoRoot $cliRepoRoot -SurfaceRoot $resolvedSurfaceRoot -PassThroughArgs $passThroughArgs
                }
                'deploy-ni' {
                    $result = Invoke-CdevLinuxDeployNi -CliRepoRoot $cliRepoRoot -PassThroughArgs $passThroughArgs
                }
                default {
                    throw "Unsupported linux command '$command'."
                }
            }
        }
        'ci' {
            switch ($command) {
                'integration-gate' {
                    $repo = if ($argsMap.ContainsKey('repo')) { [string]$argsMap['repo'] } else { 'svelderrainruiz/labview-cdev-surface' }
                    $branch = if ($argsMap.ContainsKey('branch')) { [string]$argsMap['branch'] } else { 'main' }
                    $workflow = if ($argsMap.ContainsKey('workflow')) { [string]$argsMap['workflow'] } else { 'ci.yml' }
                    $poll = if ($argsMap.ContainsKey('poll-seconds')) { [int]$argsMap['poll-seconds'] } else { 15 }
                    $timeout = if ($argsMap.ContainsKey('wait-timeout-seconds')) { [int]$argsMap['wait-timeout-seconds'] } else { 3600 }
                    $result = Invoke-CdevCiIntegrationGate -Repository $repo -Branch $branch -Workflow $workflow -PollSeconds $poll -WaitTimeoutSeconds $timeout
                }
                default {
                    throw "Unsupported ci command '$command'. Use 'ci integration-gate'."
                }
            }
        }
        'release' {
            switch ($command) {
                'package' {
                    $outputRoot = if ($argsMap.ContainsKey('output-root')) { [string]$argsMap['output-root'] } else { '' }
                    $result = Invoke-CdevReleasePackage -CliRepoRoot $cliRepoRoot -OutputRoot $outputRoot
                }
                default {
                    throw "Unsupported release command '$command'. Use 'release package'."
                }
            }
        }
        default {
            throw "Unsupported group '$group'. Run 'help' for available commands."
        }
    }
} catch {
    $exitCode = 1
    $result = New-CdevResult -Status 'failed' -Errors @($_.Exception.Message)
    Write-Error $_.Exception.Message
}

$composedCommand = "$group $command".Trim()
Write-CdevRunReport -ReportPath $ReportPath -Command $composedCommand -Args @($CommandArgs) -Result $result
Write-Host "CLI report: $ReportPath"

if ([string]$result.status -ne 'succeeded') {
    exit 1
}

exit $exitCode
