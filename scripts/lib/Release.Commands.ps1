function New-CdevShaFile {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$OutputPath
    )

    $sha = (Get-FileHash -LiteralPath $FilePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $name = Split-Path -Path $FilePath -Leaf
    "{0} *{1}" -f $sha, $name | Set-Content -LiteralPath $OutputPath -Encoding ascii
    return $sha
}

function Invoke-CdevReleasePackage {
    param(
        [Parameter(Mandatory = $true)][string]$CliRepoRoot,
        [string]$OutputRoot
    )

    $resolvedOutput = if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
        Join-Path $CliRepoRoot 'artifacts\release\cli'
    } else {
        [System.IO.Path]::GetFullPath($OutputRoot)
    }

    $contractPath = Join-Path $CliRepoRoot 'cli-contract.json'
    if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) {
        throw "cli-contract.json not found: $contractPath"
    }
    $contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json -ErrorAction Stop
    $version = [string]$contract.version
    if ([string]::IsNullOrWhiteSpace($version)) {
        throw 'cli-contract.json is missing version.'
    }

    Ensure-CdevDirectory -Path $resolvedOutput
    $stagingRoot = Join-Path $resolvedOutput 'staging'
    if (Test-Path -LiteralPath $stagingRoot -PathType Container) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    }

    $winStage = Join-Path $stagingRoot 'win-x64\cdev-cli'
    $linuxStage = Join-Path $stagingRoot 'linux-x64\cdev-cli'
    Ensure-CdevDirectory -Path $winStage
    Ensure-CdevDirectory -Path $linuxStage

    foreach ($item in @('AGENTS.md', 'README.md', 'cli-contract.json', 'scripts')) {
        Copy-Item -Path (Join-Path $CliRepoRoot $item) -Destination $winStage -Recurse -Force
        Copy-Item -Path (Join-Path $CliRepoRoot $item) -Destination $linuxStage -Recurse -Force
    }

    $zipPath = Join-Path $resolvedOutput 'cdev-cli-win-x64.zip'
    if (Test-Path -LiteralPath $zipPath -PathType Leaf) { Remove-Item -LiteralPath $zipPath -Force }
    Compress-Archive -Path (Join-Path $stagingRoot 'win-x64\*') -DestinationPath $zipPath -CompressionLevel Optimal

    $tarPath = Join-Path $resolvedOutput 'cdev-cli-linux-x64.tar.gz'
    if (Test-Path -LiteralPath $tarPath -PathType Leaf) { Remove-Item -LiteralPath $tarPath -Force }
    & tar -czf $tarPath -C (Join-Path $stagingRoot 'linux-x64') .
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create tar.gz package at $tarPath"
    }

    $zipShaFile = "$zipPath.sha256"
    $tarShaFile = "$tarPath.sha256"
    $zipSha = New-CdevShaFile -FilePath $zipPath -OutputPath $zipShaFile
    $tarSha = New-CdevShaFile -FilePath $tarPath -OutputPath $tarShaFile

    $spdxPath = Join-Path $resolvedOutput 'cdev-cli.spdx.json'
    [ordered]@{
        SPDXID = 'SPDXRef-DOCUMENT'
        spdxVersion = 'SPDX-2.3'
        creationInfo = [ordered]@{
            created = (Get-Date).ToUniversalTime().ToString('o')
            creators = @('Tool: cdev-cli-release-packager')
        }
        name = "cdev-cli-$version"
        files = @(
            [ordered]@{ fileName = 'cdev-cli-win-x64.zip'; checksums = @([ordered]@{ algorithm = 'SHA256'; checksumValue = $zipSha }) },
            [ordered]@{ fileName = 'cdev-cli-linux-x64.tar.gz'; checksums = @([ordered]@{ algorithm = 'SHA256'; checksumValue = $tarSha }) }
        )
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $spdxPath -Encoding utf8

    $slsaPath = Join-Path $resolvedOutput 'cdev-cli.slsa.json'
    [ordered]@{
        _type = 'https://in-toto.io/Statement/v1'
        subject = @(
            [ordered]@{ name = 'cdev-cli-win-x64.zip'; digest = [ordered]@{ sha256 = $zipSha } },
            [ordered]@{ name = 'cdev-cli-linux-x64.tar.gz'; digest = [ordered]@{ sha256 = $tarSha } }
        )
        predicateType = 'https://slsa.dev/provenance/v1'
        predicate = [ordered]@{
            buildDefinition = [ordered]@{ buildType = 'cdev-cli-package'; externalParameters = [ordered]@{ version = $version } }
            runDetails = [ordered]@{ builder = [ordered]@{ id = 'cdev-cli' } }
        }
    } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $slsaPath -Encoding utf8

    return (New-CdevResult -Status 'succeeded' -Reports @($spdxPath, $slsaPath, $zipShaFile, $tarShaFile) -Data ([ordered]@{
        version = $version
        output_root = $resolvedOutput
        assets = @(
            [ordered]@{ name = 'cdev-cli-win-x64.zip'; path = $zipPath; sha256 = $zipSha },
            [ordered]@{ name = 'cdev-cli-linux-x64.tar.gz'; path = $tarPath; sha256 = $tarSha }
        )
    }))
}
