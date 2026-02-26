#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'cdev CLI fork/upstream sync guard contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:workflowPath = Join-Path $script:repoRoot '.github/workflows/fork-upstream-sync-guard.yml'
        $script:guardScriptPath = Join-Path $script:repoRoot 'scripts/Test-ForkUpstreamSyncGuard.ps1'

        foreach ($path in @($script:workflowPath, $script:guardScriptPath)) {
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                throw "Missing required sync guard contract file: $path"
            }
        }

        $script:workflow = Get-Content -LiteralPath $script:workflowPath -Raw
        $script:guardScript = Get-Content -LiteralPath $script:guardScriptPath -Raw
    }

    It 'runs on schedule and workflow dispatch' {
        $script:workflow | Should -Match 'workflow_dispatch:'
        $script:workflow | Should -Match 'schedule:'
        $script:workflow | Should -Match 'cron:'
    }

    It 'emits and uploads machine-readable drift report artifacts' {
        $script:workflow | Should -Match 'fork-upstream-sync-drift-report\.json'
        $script:workflow | Should -Match 'actions/upload-artifact@v4'
        $script:workflow | Should -Match 'if:\s+always\(\)'
    }

    It 'checks branch parity, release tag parity, and release asset digest parity' {
        foreach ($token in @(
            'main_head',
            'latest_release_tag',
            'asset_digest:',
            'cdev-cli-win-x64.zip',
            'cdev-cli-linux-x64.tar.gz',
            'drift_detected'
        )) {
            $script:guardScript | Should -Match ([regex]::Escape($token))
        }
    }

    It 'has parse-safe PowerShell syntax' {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($script:guardScript, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
    }
}
