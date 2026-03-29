# 🚁 Feral Drone Capture Hub (EVE Frontier Smart Assembly)

## 📖 Overview
The **Feral Drone Capture Hub** is a custom Smart Assembly built for EVE Frontier using the MUD framework.

Instead of relying on default Smart Turret behavior, this project reprograms turret logic to identify Feral Drone targets, avoid attacking them, capture them, store capture state, and emit an on-chain beacon event for off-chain monitoring.

## 🏗️ Architecture
This prototype demonstrates a full-stack loop that works quickly in local development without a heavy indexer.

- **On-Chain (Solidity/MUD)**
  - Overrides turret attack logic so drone targets are not attacked.
  - Adds capture logic that stores captured drone IDs in contract memory.
  - Emits indexed event: `DroneCaptured(turretId, droneId)`.
- **Off-Chain (Python/web3.py)**
  - Lightweight scanner listens directly to local Anvil RPC.
  - Reads event logs, decodes indexed topics, prints human-readable alerts.

## 🧩 Feature Guide (What was added + how to use)

- **Drone-safe targeting + capture hub**
  - What it does: captures drones instead of destroying them when capacity allows.
  - Use it: run the trigger script and monitor `DroneCaptured` output in scanner.

- **Capacity control**
  - What it does: enforces max drone holding capacity (`maxCapacity = 5`).
  - Use it: repeatedly capture drones in scripts/tests until full and confirm behavior at cap.

- **Refinery pipeline**
  - What it does: converts captured drones into materials.
  - Use it: call `refineDrone(...)`; monitor `DroneRefined` for yields.

- **Combat launch + radar lock**
  - What it does: allows target lock and drone launch against targets.
  - Use it: call `setTargetLock(...)` and `autoDeployDrone(...)`/`deployDroneToAttack(...)`; watch `TargetLocked` and `DroneDeployed`.

- **IFF friend/foe logic**
  - What it does: marks friendlies and auto-engages hostiles.
  - Use it: call `setIFFFriendly(...)` then `engageIfHostile(...)`; watch `IFFUpdated` and `IntruderEngaged`.

- **Corp-only extraction security**
  - What it does: restricts extraction to approved corp context.
  - Use it: run `script/CorpOnlyExtractDemo.s.sol` (allow) and `script/CorpOnlyExtractDeniedDemo.s.sol` (deny).

- **Portable hub lifecycle**
  - What it does: supports deploy/pack-up mobility while preserving drone memory.
  - Use it: load fuel with `loadD1Fuel(...)`, then call `deployHub(...)` and `packUpHub(...)`; watch `TurretDeployed` and `TurretPacked`.

- **D1 fuel burn + feral fallback**
  - What it does: burns `1` D1 fuel per minute while deployed and, on depletion, only drones currently launched (`inBay = false`) become feral again.
  - Use it: top up with `loadD1Fuel(turretId, amount)` before deployment and monitor remaining fuel with `getCurrentD1Fuel(...)`.

- **Persistent memory chip + repair bay**
  - What it does: stores per-drone memory (`isCaptured`, `inBay`, `hp`, `lastHealTime`) and computes conditional healing via `getCurrentHP(...)`.
  - Use it: capture with `captureDronePersistent(...)`, leave drone in bay while deployed to heal, then launch to freeze healing (`inBay = false`).

- **Logistics + status telemetry**
  - What it does: streams movement and health updates to scanner/dashboard.
  - Use it: run scanner and trigger lifecycle actions; observe logistics and status messages in real time.

## 🚀 Quick Start (Local)

### 1) Prerequisites
- Foundry installed (`forge`, `anvil`) and local chain running.
- Python 3 installed.
- `web3` installed for the dashboard scanner.

### 2) Start the Python Scanner (Dashboard)
Open a terminal:

```bash
cd "C:\EVE Project\builder-examples\drone-dashboard"
```

If `python` is unavailable in your shell, use the direct executable path:

```bash
"C:\Users\Dell\AppData\Local\Programs\Python\Python312\python.exe" scanner.py
```

Expected output:

```text
🟢 SUCCESS: Dashboard connected to Local EVE World!
🛰️ Scanning space for captured drones... (Press Ctrl+C to stop)
```

### 3) Trigger the Capture Event (Blockchain)
Open a second terminal:

```bash
cd "C:\EVE Project\builder-examples\smart-turret\packages\contracts"
forge script script/TriggerCapture.s.sol --rpc-url http://127.0.0.1:8546 --broadcast
```

Optional fuel overrides for the trigger script:

```powershell
$env:D1_FUEL_AMOUNT="10"
$env:USER_D1_FUEL_AMOUNT="5"
```

> Note: In this environment, Foundry/Anvil is exposed on **8546** (not 8545).

### 4) Confirm Dashboard Alert
Back in the scanner terminal, you should see a decoded capture message like:

```text
🚨 ALARM: DRONE CAPTURE DETECTED! 🚨
✅ Turret #1 successfully captured Feral Drone #15000!
```

## ✅ What this proves
- Turret logic can identify and handle drones differently from players.
- Capture action persists drone capture state on-chain.
- Event beacon is emitted and consumed by an off-chain Python listener in real time.
- Corp-only security can gate extraction to alliance members using on-chain `Characters` + `CharactersByAccount` checks.

## 🛡️ Corp-Only Trap (Judge Run)
Run the capture+extract flow through MUD World context:

```bash
cd "C:\EVE Project\builder-examples\smart-turret\packages\contracts"
$env:WORLD_ADDRESS="0x0165878A594ca255338adfa4d48449f69242Eb8F"
$env:PRIVATE_KEY="<same-corp-player-private-key>"
$env:EXTRACTOR_PRIVATE_KEY="<optional: defaults to PRIVATE_KEY>"
$env:SMART_TURRET_ID="<turret-id>"
$env:EXTRACTOR_CHARACTER_ID="<character item id or smart id owned by key>"
forge script script/CorpOnlyExtractDemo.s.sol:CorpOnlyExtractDemo --sig "run(address)" $env:WORLD_ADDRESS --rpc-url http://127.0.0.1:8546 --broadcast
```

If the character's corp differs from the turret allowlist corp, the script reverts with:

```text
Access denied: corp mismatch
```

### Denial Proof (Outsider)

```bash
cd "C:\EVE Project\builder-examples\smart-turret\packages\contracts"
$env:WORLD_ADDRESS="0x0165878A594ca255338adfa4d48449f69242Eb8F"
$env:PRIVATE_KEY="<outsider-player-private-key>"
$env:OUTSIDER_PRIVATE_KEY="<optional: defaults to PRIVATE_KEY>"
$env:SMART_TURRET_ID="<turret-id>"
$env:OUTSIDER_CHARACTER_ID="<outsider character item id or smart id owned by key>"
forge script script/CorpOnlyExtractDeniedDemo.s.sol:CorpOnlyExtractDeniedDemo --sig "run(address)" $env:WORLD_ADDRESS --rpc-url http://127.0.0.1:8546 --broadcast
```

Expected result:

```text
Access denied: corp mismatch
```

## 🎬 Demo Script (Judge Quick Run)
Terminal A (Scanner):

```bash
cd "C:\EVE Project\builder-examples\drone-dashboard"
"C:\Users\Dell\AppData\Local\Programs\Python\Python312\python.exe" scanner.py
```

Terminal B (Trigger):

```bash
cd "C:\EVE Project\builder-examples\smart-turret\packages\contracts"
forge script script/TriggerCapture.s.sol --rpc-url http://127.0.0.1:8546 --broadcast
```

Terminal A should print:

```text
🚨 ALARM: DRONE CAPTURE DETECTED! 🚨
✅ Turret #1 successfully captured Feral Drone #15000!
```

## 🧪 Focused Test Command
From `packages/contracts`, run:

```bash
forge test --match-path test/DroneHubTest.t.sol -vv
```

Current expected result: all Drone Hub tests pass.

### World-Integrated Test Note
- `test/SmartTurretTest.t.sol` depends on a deployed world contract at `WORLD_ADDRESS`.
- If `WORLD_ADDRESS` is unset or points to a non-contract address, the suite now auto-skips instead of reverting in `setUp()`.
- To execute world-integrated assertions, run tests with a valid deployed world address in your environment.
