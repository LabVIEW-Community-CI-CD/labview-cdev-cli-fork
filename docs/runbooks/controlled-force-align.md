# Controlled Force-Align Runbook (Fork -> Upstream)

## Purpose
Use this runbook when `svelderrainruiz/labview-cdev-cli` must be force-aligned to `LabVIEW-Community-CI-CD/labview-cdev-cli` with audited branch-protection restoration.

This operation is an exception path and must be used only for deterministic parity recovery.

## Preconditions
- `gh` is authenticated with permissions to mutate `svelderrainruiz/labview-cdev-cli`.
- Branch target is `main`.
- Upstream source of truth is `LabVIEW-Community-CI-CD/labview-cdev-cli:main`.

## Automated Procedure (Recommended)
Run dry-run first:

```powershell
pwsh -NoProfile -File .\scripts\Invoke-ControlledForkForceAlign.ps1 -DryRun
```

Run live force-align:

```powershell
pwsh -NoProfile -File .\scripts\Invoke-ControlledForkForceAlign.ps1
```

Optional overrides:

```powershell
pwsh -NoProfile -File .\scripts\Invoke-ControlledForkForceAlign.ps1 `
  -ForkRepository svelderrainruiz/labview-cdev-cli `
  -UpstreamRepository LabVIEW-Community-CI-CD/labview-cdev-cli `
  -Branch main `
  -CiWaitTimeoutSeconds 900 `
  -CiPollIntervalSeconds 10
```

Artifacts are written to `artifacts/force-align/<branch>-<timestamp>/`:
- `branch-protection.snapshot.json`
- `branch-protection.relaxed.json`
- `controlled-force-align-report.json`

## What the Script Does
1. Snapshot current branch protection JSON.
2. Apply temporary relaxed protection that allows force updates.
3. Force-align fork branch ref to upstream SHA.
4. Restore original branch protection in a `finally` path.
5. Verify:
   - fork/upstream branch SHA parity
   - branch protection restored (force-push disabled)
   - `CI Pipeline` required status check present
   - latest push CI on aligned SHA succeeds (live mode)

## Manual Fallback Procedure
If automation is unavailable, execute the same sequence:
1. Snapshot protection:
   - `gh api repos/svelderrainruiz/labview-cdev-cli/branches/main/protection`
2. Temporarily relax protection (allow force push).
3. Force-align `main` to upstream `main` SHA.
4. Restore original protection settings exactly.
5. Verify SHA parity and required checks.

Never leave relaxed protection enabled after completion.
