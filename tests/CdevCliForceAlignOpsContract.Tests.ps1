#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'cdev CLI controlled force-align operations contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:opsScriptPath = Join-Path $script:repoRoot 'scripts/Invoke-ControlledForkForceAlign.ps1'
        $script:runbookPath = Join-Path $script:repoRoot 'docs/runbooks/controlled-force-align.md'
        $script:agentsPath = Join-Path $script:repoRoot 'AGENTS.md'

        foreach ($path in @($script:opsScriptPath, $script:runbookPath, $script:agentsPath)) {
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                throw "Missing required controlled force-align contract file: $path"
            }
        }

        $script:opsScript = Get-Content -LiteralPath $script:opsScriptPath -Raw
        $script:runbook = Get-Content -LiteralPath $script:runbookPath -Raw
        $script:agents = Get-Content -LiteralPath $script:agentsPath -Raw
    }

    It 'documents auditable force-align sequence and safeguards' {
        foreach ($token in @(
            'snapshot branch protection',
            'temporarily relax protection',
            'force-align fork branch ref to upstream SHA',
            'restore branch protection in a finally path',
            'Never leave `allow_force_pushes` enabled'
        )) {
            $script:agents | Should -Match ([regex]::Escape($token))
        }
    }

    It 'implements protection snapshot, temporary relax, force-align, and restore verification' {
        foreach ($token in @(
            'branches/$Branch/protection',
            'allow_force_pushes = $true',
            'git/refs/heads/$Branch',
            'force=true',
            'finally',
            'CI Pipeline',
            'protection_restore_succeeded'
        )) {
            $script:opsScript | Should -Match ([regex]::Escape($token))
        }
    }

    It 'provides dry-run and live runbook commands with deterministic artifact output' {
        foreach ($token in @(
            'Invoke-ControlledForkForceAlign.ps1 -DryRun',
            'Invoke-ControlledForkForceAlign.ps1',
            'branch-protection.snapshot.json',
            'branch-protection.relaxed.json',
            'controlled-force-align-report.json'
        )) {
            $script:runbook | Should -Match ([regex]::Escape($token))
        }
    }

    It 'has parse-safe PowerShell syntax' {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($script:opsScript, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
    }
}
