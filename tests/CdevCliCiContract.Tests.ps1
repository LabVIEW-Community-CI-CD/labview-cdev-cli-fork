#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'cdev CLI ci contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:entrypointPath = Join-Path $script:repoRoot 'scripts/Invoke-CdevCli.ps1'
        $script:ciCommandsPath = Join-Path $script:repoRoot 'scripts/lib/Ci.Commands.ps1'
        $script:agentsPath = Join-Path $script:repoRoot 'AGENTS.md'

        foreach ($path in @($script:entrypointPath, $script:ciCommandsPath, $script:agentsPath)) {
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                throw "Missing required CI contract file: $path"
            }
        }

        $script:entrypoint = Get-Content -LiteralPath $script:entrypointPath -Raw
        $script:ciCommands = Get-Content -LiteralPath $script:ciCommandsPath -Raw
        $script:agents = Get-Content -LiteralPath $script:agentsPath -Raw
    }

    It 'defaults ci integration-gate repo target to fork-safe surface repo' {
        $script:entrypoint | Should -Match 'ci integration-gate'
        $script:entrypoint | Should -Match '''svelderrainruiz/labview-cdev-surface'''
        $script:ciCommands | Should -Match '''svelderrainruiz/labview-cdev-surface'''
    }

    It 'enforces fork workflow guardrail against upstream workflow dispatch targets' {
        $script:ciCommands | Should -Match 'Assert-CdevCiRepositoryTarget'
        $script:ciCommands | Should -Match 'LabVIEW-Community-CI-CD'
        $script:ciCommands | Should -Match 'Fork workflow guardrail'
        $script:ciCommands | Should -Match 'gh workflow run'
        $script:ciCommands | Should -Match '-R \$Repository'
    }

    It 'documents fork-only gh repo pinning in AGENTS policy' {
        $script:agents | Should -Match 'Required direct `gh` pin for fork operations'
        $script:agents | Should -Match '-R svelderrainruiz/labview-cdev-cli'
        $script:agents | Should -Match 'Forbidden in fork workflow'
    }

    It 'has parse-safe PowerShell syntax' {
        foreach ($content in @($script:entrypoint, $script:ciCommands)) {
            $tokens = $null
            $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$tokens, [ref]$errors)
            @($errors).Count | Should -Be 0
        }
    }
}
