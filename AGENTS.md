# Local Agent Instructions

## Mission
This repository is the control-plane CLI for deterministic `C:\dev` workspace orchestration.

## Remote/CI Guardrail (Fork Workflow)
- This repo is operated in fork workflow mode by default.
- Allowed mutation target from local agent environment: `origin` (`svelderrainruiz/labview-cdev-cli`).
- Treat `upstream` (`LabVIEW-Community-CI-CD/labview-cdev-cli`) as read-only from fork worktrees.
- Forbidden in fork workflow:
  - `git push upstream ...`
  - `gh workflow run ... -R LabVIEW-Community-CI-CD/labview-cdev-cli`
  - `gh run rerun ... -R LabVIEW-Community-CI-CD/labview-cdev-cli`
- Required direct `gh` pin for fork operations: `-R svelderrainruiz/labview-cdev-cli`.

## CLI Orchestration Contract
- CLI entrypoint: `scripts/Invoke-CdevCli.ps1`.
- Windows invocation contract: `powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\scripts\Invoke-CdevCli.ps1 ...`.
- Linux invocation contract: `pwsh -NoProfile -File ./scripts/Invoke-CdevCli.ps1 ...`.
- CLI is the preferred operator interface for:
  - repo topology inspection (`repos list`)
  - governance checks (`repos doctor`)
  - installer iterations (`installer exercise`)
  - post-action gate summaries (`postactions collect`)
  - Linux NI deploy checks (`linux deploy-ni`).
- Core command tokens that must stay stable:
  - `Invoke-CdevCli.ps1`
  - `repos doctor`
  - `installer exercise`
  - `postactions collect`
  - `linux deploy-ni`
  - `desktop-linux`
  - `nationalinstruments/labview:latest-linux`

## Surface Coupling Contract
- `labview-cdev-cli` consumes governance contract from `C:\dev\labview-cdev-surface` by default.
- Default surface root is `C:\dev\labview-cdev-surface` unless `CDEV_SURFACE_ROOT` is set.
- `surface sync` resolves and reports surface ref SHA before control-plane operations.

## Linux Contract
- Linux install support is manifest-native (not NSIS).
- `scripts/lib/Install-WorkspaceFromManifest.Linux.ps1` provisions workspace from manifest pins.
- `scripts/lib/Invoke-NiLinuxDeployCheck.ps1` validates NI Linux image deploy path using Docker Desktop Linux context.
- Default Linux deploy image: `nationalinstruments/labview:latest-linux`.

## Windows Contract
- Windows gate orchestration must target Docker Desktop Windows container mode on self-hosted runners.
- Required gate runner labels:
  - `self-hosted`
  - `windows`
  - `self-hosted-windows-lv`
  - `windows-containers`
  - `user-session`
  - `cdev-surface-windows-gate`
- Default Windows gate image is `nationalinstruments/labview:2026q1-windows` unless an explicit override is set by policy.
- Gate container command surface must use Windows PowerShell (`powershell.exe`) and may use host-mounted PowerShell 7, but must not require in-image `pwsh` availability.
- `g-cli` is a host-side dependency for Windows LabVIEW execution and is not required to exist inside the container image.
- Gate runs that exercise PPL validation must enforce one bitness per image run (`LVIE_GATE_SINGLE_PPL_BITNESS=32|64`), never serialized dual-bitness in a single run.
- When gate-required LabVIEW year is `2026`, x86 parity must be enforced before 32-bit PPL validation; if missing, bootstrap `ni-labview-2026-core-x86-en` via NI Package Manager.
- `VIPM_COMMUNITY_EDITION=true` must be set for Windows image lanes that activate VIPM CLI in community mode.

## CI Contract
- Required checks for default branch target:
  - `CI Pipeline`
  - `CLI Contract`
  - `Provenance Contract`
- `release-cli.yml` is manual dispatch only and must publish:
  - `cdev-cli-win-x64.zip`
  - `cdev-cli-linux-x64.tar.gz`
  - `.sha256`
  - `cdev-cli.spdx.json`
  - `cdev-cli.slsa.json`
