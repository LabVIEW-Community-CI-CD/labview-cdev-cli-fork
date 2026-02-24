# labview-cdev-cli

Control-plane CLI for deterministic `C:\dev` workspace operations.

## Entrypoint

```powershell
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\scripts\Invoke-CdevCli.ps1 <group> <command> [options]
```

On Linux, invoke the same entrypoint with `pwsh -NoProfile -File`.

## Commands

- `help [topic]`
- `repos list`
- `repos doctor`
- `surface sync`
- `installer build`
- `installer exercise`
- `installer install`
- `postactions collect`
- `linux install`
- `linux deploy-ni`
- `ci integration-gate`
- `release package`

## Quick Start

```powershell
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\scripts\Invoke-CdevCli.ps1 repos list
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\scripts\Invoke-CdevCli.ps1 repos doctor --workspace-root C:\dev
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\scripts\Invoke-CdevCli.ps1 installer exercise --mode fast --iterations 1
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\scripts\Invoke-CdevCli.ps1 ci integration-gate --repo svelderrainruiz/labview-cdev-surface --branch main
```

## Linux Flow (Docker Desktop Linux)

```powershell
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\scripts\Invoke-CdevCli.ps1 linux install --workspace-root C:\dev-linux
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\scripts\Invoke-CdevCli.ps1 linux deploy-ni --workspace-root C:\dev-linux --docker-context desktop-linux --image nationalinstruments/labview:latest-linux
```

## Release Packaging

```powershell
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\scripts\Invoke-CdevCli.ps1 release package --output-root .\artifacts\release\cli
```

Release artifacts:
- `cdev-cli-win-x64.zip`
- `cdev-cli-linux-x64.tar.gz`
- `.sha256`
- `cdev-cli.spdx.json`
- `cdev-cli.slsa.json`
