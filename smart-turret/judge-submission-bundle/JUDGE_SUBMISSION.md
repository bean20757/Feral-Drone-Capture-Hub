# Smart Turret Judge Submission Guide

## What this package includes
- Smart turret contracts with D1 fuel behavior (1 unit/min while deployed).
- Drone capture, persistence, pack/deploy lifecycle, and launch flow.
- Python scanner dashboard for live event output.

## Environment used for validation
- OS: Windows
- Local RPC: http://127.0.0.1:8546
- Foundry forge: 1.6.0-rc1

## Quick judge run (recommended)

### 1) Start scanner (Terminal A)
```powershell
Set-Location "C:\EVE Project\builder-examples\drone-dashboard"
& "C:\Users\Dell\AppData\Local\Programs\Python\Python312\python.exe" scanner.py
```

Expected startup output includes:
- SUCCESS: Dashboard connected to Local EVE World

### 2) Run trigger script (Terminal B)
```powershell
Set-Location "C:\EVE Project\builder-examples\smart-turret\packages\contracts"
forge script script/TriggerCapture.s.sol --rpc-url http://127.0.0.1:8546 --broadcast
```

Expected behavior:
- Script completes successfully.
- Scanner prints deploy/capture/pack/redeploy/launch events.

## Test command for judges
From contracts folder:
```powershell
forge test -vv
```

Expected result in this environment:
- DroneHubTest: all pass
- SmartTurretTest: skipped when a valid deployed world contract is not available for WORLD_ADDRESS

## Notes
- Root pnpm test now works on Windows for this project setup.
- If a judge uses port 8545, they must ensure an RPC is listening there (default here is 8546).
- TriggerCapture includes D1 fuel loading before deployment to satisfy current fuel mechanics.
- Some Windows environments block direct `.ps1` execution. If so, run the bundled launcher instead:

```cmd
run-judge-validation.cmd
```
