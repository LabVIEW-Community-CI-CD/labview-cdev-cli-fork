function Assert-CdevCiRepositoryTarget {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repository
    )

    $candidate = [string]$Repository
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        throw 'ci integration-gate requires a non-empty repository target.'
    }

    if ($candidate -match '^(?i)LabVIEW-Community-CI-CD\/') {
        throw "Fork workflow guardrail: direct ci integration-gate dispatch to '$candidate' is not allowed. Use a fork repo target (for example: svelderrainruiz/labview-cdev-surface)."
    }
}

function Invoke-CdevCiIntegrationGate {
    param(
        [string]$Repository = 'svelderrainruiz/labview-cdev-surface',
        [string]$Branch = 'main',
        [string]$Workflow = 'ci.yml',
        [int]$PollSeconds = 15,
        [int]$WaitTimeoutSeconds = 3600,
        [string[]]$RequiredJobs = @('CI Pipeline', 'Workspace Installer Contract', 'Reproducibility Contract', 'Provenance Contract')
    )

    Assert-CdevCommand -Name 'gh'
    Assert-CdevCiRepositoryTarget -Repository $Repository

    & gh workflow run $Workflow -R $Repository --ref $Branch
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to dispatch workflow '$Workflow' on '$Repository' ref '$Branch'."
    }

    Start-Sleep -Seconds 5

    $runListJson = & gh run list -R $Repository --workflow $Workflow --branch $Branch --limit 1 --json databaseId,status,conclusion,url,headSha,event
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to resolve workflow run after dispatch."
    }

    $runList = $runListJson | ConvertFrom-Json -ErrorAction Stop
    if (@($runList).Count -eq 0) {
        throw "No workflow run found for '$Workflow' on branch '$Branch'."
    }

    $runId = [string]$runList[0].databaseId
    $deadline = (Get-Date).AddSeconds($WaitTimeoutSeconds)

    do {
        $runViewJson = & gh run view $runId -R $Repository --json status,conclusion,url,jobs,workflowName,headBranch
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to inspect run '$runId'."
        }

        $run = $runViewJson | ConvertFrom-Json -ErrorAction Stop
        if ([string]$run.status -eq 'completed') {
            $errors = @()
            if ([string]$run.conclusion -ne 'success') {
                $errors += "Workflow conclusion is '$([string]$run.conclusion)'."
            }

            foreach ($jobName in $RequiredJobs) {
                $job = @($run.jobs | Where-Object { [string]$_.name -eq $jobName } | Select-Object -First 1)
                if ($null -eq $job) {
                    $errors += "Required job missing: $jobName"
                    continue
                }
                if ([string]$job.conclusion -ne 'success') {
                    $errors += "Required job '$jobName' conclusion is '$([string]$job.conclusion)'."
                }
            }

            $status = if ($errors.Count -eq 0) { 'succeeded' } else { 'failed' }
            return (New-CdevResult -Status $status -Errors $errors -Data ([ordered]@{
                repository = $Repository
                branch = $Branch
                workflow = $Workflow
                run_id = $runId
                run_url = [string]$run.url
                conclusion = [string]$run.conclusion
                jobs = @($run.jobs)
            }))
        }

        Start-Sleep -Seconds $PollSeconds
    } while ((Get-Date) -lt $deadline)

    return (New-CdevResult -Status 'failed' -Errors @("Timed out waiting for run '$runId' to complete."))
}
