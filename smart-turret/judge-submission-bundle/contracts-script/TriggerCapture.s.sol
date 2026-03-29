// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import "forge-std/Script.sol";
import { SmartTurretSystem } from "../src/systems/SmartTurretSystem.sol";

contract TriggerCapture is Script {
    function run() external {
        // The default local Anvil testing key
        uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

        // 🟢 ACTION! Start the broadcast
        vm.startBroadcast(deployerPrivateKey);

        // 1. Initialize the Hub infrastructure
        SmartTurretSystem turret = new SmartTurretSystem();

        // 1.5 Load D1 fuel so deployment and drone control can operate
        turret.loadD1Fuel(1, 30);

        // 2. Commander deploys the hub at Sector 888
        turret.deployHub(1, 888);

        // 3. A damaged Feral Drone is caught! (Starts at 20 HP)
        turret.captureDronePersistent(1, 15000, 20);

        // 4. ⏳ TIME TRAVEL: Fast-forward 5 minutes (300 seconds)
        // Math: 300 seconds / 10 = 30 HP gained.
        vm.warp(block.timestamp + 300);

        // 5. Pack up the hub. The drone's HP is permanently saved at 50 (20 + 30)
        turret.packUpHub(1);

        // 6. ⏳ TIME TRAVEL: Fast-forward 2 weeks in hyperspace (1,209,600 seconds)
        // Because the Hub is in the player's pocket, healing MUST be frozen.
        vm.warp(block.timestamp + 1209600);

        // 7. Deploy at a new warzone (Sector 999)
        turret.deployHub(1, 999);

        // 8. Launch the drone at an enemy! (Target ID: 777)
        // It should launch with exactly 50 HP, proving the entire system works.
        turret.deployDroneToAttack(1, 15000, 777);

        // 🔴 CUT! End broadcast
        vm.stopBroadcast();
    }
}
