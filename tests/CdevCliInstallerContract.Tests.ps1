#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'cdev CLI installer command contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:installerCommands = Get-Content -LiteralPath (Join-Path $script:repoRoot 'scripts/lib/Installer.Commands.ps1') -Raw
    }

    It 'contains build, exercise, install and postaction collection handlers' {
        $script:installerCommands | Should -Match 'Invoke-CdevInstallerBuild'
        $script:installerCommands | Should -Match 'Invoke-CdevInstallerExercise'
        $script:installerCommands | Should -Match 'Invoke-CdevInstallerInstall'
        $script:installerCommands | Should -Match 'Invoke-CdevPostactionsCollect'
    }

    It 'enforces dual-bitness and vip pass checks in postaction collection' {
        $script:installerCommands | Should -Match "ppl_capability_checks.'32'.status"
        $script:installerCommands | Should -Match "ppl_capability_checks.'64'.status"
        $script:installerCommands | Should -Match 'vip_package_build_check.status'
    }

    It 'has parse-safe PowerShell syntax' {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($script:installerCommands, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
    }
}
