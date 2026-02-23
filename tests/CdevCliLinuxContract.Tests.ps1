#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'cdev CLI linux contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:linuxInstallScript = Join-Path $script:repoRoot 'scripts/lib/Install-WorkspaceFromManifest.Linux.ps1'
        $script:linuxDeployScript = Join-Path $script:repoRoot 'scripts/lib/Invoke-NiLinuxDeployCheck.ps1'

        if (-not (Test-Path -LiteralPath $script:linuxInstallScript -PathType Leaf)) {
            throw "Missing Linux install script: $script:linuxInstallScript"
        }
        if (-not (Test-Path -LiteralPath $script:linuxDeployScript -PathType Leaf)) {
            throw "Missing Linux deploy script: $script:linuxDeployScript"
        }

        $script:linuxInstall = Get-Content -LiteralPath $script:linuxInstallScript -Raw
        $script:linuxDeploy = Get-Content -LiteralPath $script:linuxDeployScript -Raw
    }

    It 'implements manifest-native linux install behavior and not-supported post-action flags' {
        $script:linuxInstall | Should -Match 'platform = ''linux''' 
        $script:linuxInstall | Should -Match 'not_supported'
        $script:linuxInstall | Should -Match 'Build-RunnerCliBundleFromManifest.ps1'
    }

    It 'implements NI linux image deploy checks with workspace mount model' {
        $script:linuxDeploy | Should -Match 'desktop-linux'
        $script:linuxDeploy | Should -Match 'nationalinstruments/labview:latest-linux'
        $script:linuxDeploy | Should -Match '-v'
        $script:linuxDeploy | Should -Match 'runlabview.sh'
    }

    It 'has parse-safe PowerShell syntax' {
        foreach ($content in @($script:linuxInstall, $script:linuxDeploy)) {
            $tokens = $null
            $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$tokens, [ref]$errors)
            @($errors).Count | Should -Be 0
        }
    }
}
