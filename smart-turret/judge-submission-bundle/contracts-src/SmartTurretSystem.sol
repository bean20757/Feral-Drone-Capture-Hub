// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import { System } from "@latticexyz/world/src/System.sol";

import { 
  Turret, 
  SmartTurretTarget, 
  TargetPriority, 
  AggressionParams 
} from "@eveworld/world-v2/src/namespaces/evefrontier/systems/smart-turret/types.sol";

import { Characters } from "@eveworld/world-v2/src/namespaces/evefrontier/codegen/tables/Characters.sol";
import { CharactersByAccount } from "@eveworld/world-v2/src/namespaces/evefrontier/codegen/tables/CharactersByAccount.sol";
import { accessSystem } from "@eveworld/world-v2/src/namespaces/evefrontier/codegen/systems/AccessSystemLib.sol";

import { TurretAllowlist } from "../codegen/tables/TurretAllowlist.sol";

/**
 * @dev This contract is an example for implementing logic to a smart turret
 */
contract SmartTurretSystem is System {
  event DroneCaptured(uint256 indexed turretId, uint256 indexed droneId);
  event DroneExtracted(uint256 indexed turretId, uint256 indexed extractorCharacterId, uint256 indexed droneId);
  event TurretDeployed(uint256 indexed turretId, uint256 coordinates);
  event TurretPacked(uint256 indexed turretId);
  event DroneStatusUpdated(uint256 indexed turretId, uint256 indexed droneId, uint256 currentHP);
  event D1FuelLoaded(uint256 indexed turretId, uint256 amountAdded, uint256 newBalance);
  event D1FuelConsumed(uint256 indexed turretId, uint256 amountConsumed, uint256 remainingBalance);
  event DroneBecameFeral(uint256 indexed turretId, uint256 indexed droneId);

  mapping(uint256 => bool) public capturedDrones;
  uint256 public droneCount;
  uint256 public maxCapacity = 5;

  // 1. Updated Memory Chip (Now tracks time!)
  struct DroneStats {
    bool isCaptured;
    bool inBay;
    uint256 hp;
    uint256 lastHealTime;
  }

  mapping(uint256 => mapping(uint256 => DroneStats)) public turretMemory;
  mapping(uint256 => bool) public isDeployed;
  mapping(uint256 => uint256) public d1Fuel;
  mapping(uint256 => uint256) public lastFuelBurnTimestamp;

  // NEW: We need a list of drones in the hub so we can pause their healing when packed up
  mapping(uint256 => uint256[]) public hubInventory;

  uint256 internal constant D1_BURN_INTERVAL_SECONDS = 60;

  /**
   * @dev Returns false when the target is a drone.
   * @param smartTurretId The Smart Turret id
   * @param characterId The source character id
   * @param targetCharacterId The target character id
   */
  function canAttack(
    uint256 smartTurretId,
    uint256 characterId,
    uint256 targetCharacterId
  ) public view returns (bool) {
    smartTurretId;
    characterId;

    if (_isDrone(targetCharacterId)) {
      if (droneCount >= maxCapacity) {
        return true;
      }

      return false;
    }

    return true;
  }

  /**
   * @dev Pure unit-test overload that doesn't depend on world Store state.
   *      Drone IDs in [10000, 20000] are treated as drones.
   */
  function canAttack(
    uint256 smartTurretId,
    uint256 targetCharacterId
  ) public view returns (bool) {
    smartTurretId;

    if (targetCharacterId >= 10000 && targetCharacterId <= 20000) {
      if (droneCount >= maxCapacity) {
        return true;
      }

      return false;
    }

    return true;
  }

  function captureDrone(uint256 turretId, uint256 droneId) public {
    require(isDrone(droneId), "Target is not a drone!");
    require(droneCount < maxCapacity, "Turret is at max drone capacity!");

    if (!capturedDrones[droneId]) {
      capturedDrones[droneId] = true;
      droneCount += 1;
    }

    emit DroneCaptured(turretId, droneId);
  }

  // 1. The Salvage Beacon: Broadcasts the exact loot drops to your dashboard
  event DroneRefined(uint256 indexed turretId, uint256 indexed droneId, uint256 exotronicsYield, uint256 dataYield);
  event DroneRecalled(uint256 indexed turretId, uint256 indexed droneId, uint256 currentHP);

  // 2. Legacy Cargo Hold (kept for compatibility with existing refinery flow)
  mapping(uint256 => bool) public refinedDrones;
  mapping(uint256 => uint256) public fossilizedExotronics;
  mapping(uint256 => uint256) public fossilizedData;

  // 3. The Extraction Logic: Breaks the drone down into raw materials
  function refineDrone(uint256 turretId, uint256 droneId) public {
    // Safety Checks
    require(capturedDrones[droneId] == true, "Error: Drone is not in holding!");
    require(refinedDrones[droneId] == false, "Error: Drone has already been scrapped!");

    // Lock the drone so it can't be scrapped again
    refinedDrones[droneId] = true;

    // The "Loot Table" (Static for the hackathon prototype)
    uint256 exotronicsYield = 50;
    uint256 dataYield = 15;

    // Deposit the minerals into the Turret's inventory
    fossilizedExotronics[turretId] += exotronicsYield;
    fossilizedData[turretId] += dataYield;

    // Fire the Salvage Beacon for the Python script
    emit DroneRefined(turretId, droneId, exotronicsYield, dataYield);
  }

  // 1. The Combat Log Beacon
  // We index the turret, the drone used as ammo, and the enemy target.
  event DroneDeployed(uint256 indexed turretId, uint256 indexed deployedDroneId, uint256 indexed targetId, uint256 damage);

  // 2. The Ammo Tracker
  mapping(uint256 => bool) public expendedDrones;

  // 4. Launching the Drone (Pulls it out of the bay)
  function deployDroneToAttack(uint256 turretId, uint256 droneId, uint256 targetId) public {
    require(isDeployed[turretId], "Deploy the hub first!");

    _syncFuel(turretId);
    require(d1Fuel[turretId] > 0, "Out of D1 fuel");

    DroneStats storage drone = turretMemory[turretId][droneId];
    require(drone.isCaptured, "Drone is no longer under turret control");
    require(drone.inBay, "Commander: That drone is not in the bay!");

    // CRITICAL STEP: Lock in the health it gained while resting BEFORE it leaves!
    drone.hp = getCurrentHP(turretId, droneId);

    // Mark it as launched. This instantly stops the getCurrentHP math.
    drone.inBay = false;

    uint256 damageDealt = 500;

    emit DroneDeployed(turretId, droneId, targetId, damageDealt);
  }

  // Player interaction: manually launch a drone from bay
  function userDeployDrone(uint256 turretId, uint256 droneId, uint256 targetId) public {
    deployDroneToAttack(turretId, droneId, targetId);
  }

  // Player interaction: recall a launched drone back into bay
  function userRecallDrone(uint256 turretId, uint256 droneId) public {
    require(isDeployed[turretId], "Deploy the hub first!");

    _syncFuel(turretId);

    DroneStats storage drone = turretMemory[turretId][droneId];
    require(drone.isCaptured, "Drone is not captured");
    require(!drone.inBay, "Drone is already in the bay");

    uint256 currentHp = getCurrentHP(turretId, droneId);
    drone.hp = currentHp;
    drone.inBay = true;
    drone.lastHealTime = block.timestamp;

    emit DroneRecalled(turretId, droneId, currentHp);
    emit DroneStatusUpdated(turretId, droneId, currentHp);
  }

  // 1. The Radar Beacon: Alerts the dashboard that a target has been painted
  event TargetLocked(uint256 indexed turretId, uint256 indexed targetId);

  // 2. The Targeting Computer: Stores the active enemy ID for each turret
  mapping(uint256 => uint256) public activeTargetLocks;

  // 3. The Lock-On Command: The player tells the turret who to shoot
  function setTargetLock(uint256 turretId, uint256 targetId) public {
    activeTargetLocks[turretId] = targetId;
    emit TargetLocked(turretId, targetId);
  }

  // 4. The Auto-Fire Sequence: Grabs a drone and hurls it at the locked target
  function autoDeployDrone(uint256 turretId, uint256 droneId) public {
    // Read the radar to find out who we are shooting at
    uint256 lockedTarget = activeTargetLocks[turretId];

    // Safety check: Make sure we actually have a target locked!
    require(lockedTarget != 0, "System Error: No active target locked in the computer!");

    // Route the command directly into our existing combat system
    deployDroneToAttack(turretId, droneId, lockedTarget);
  }

  // 2. The Conditional Repair Logic
  function getCurrentHP(uint256 turretId, uint256 droneId) public view returns (uint256) {
    DroneStats memory drone = turretMemory[turretId][droneId];

    // If the hub is packed UP, or the drone is OUT flying, time is frozen.
    if (!isDeployed[turretId] || !drone.inBay) {
      return drone.hp;
    }

    // Otherwise, it's resting in a deployed bay. Run the healing math!
    uint256 secondsPassed = block.timestamp - drone.lastHealTime;
    uint256 hpGained = secondsPassed / 10;
    uint256 currentHp = drone.hp + hpGained;

    // Cap the health at 100 (Max HP)
    if (currentHp > 100) {
      return 100;
    }
    return currentHp;
  }

  // 3. Updated Deploy: Restarts the healing timer for all drones inside
  function deployHub(uint256 turretId, uint256 coordinates) public {
    require(!isDeployed[turretId], "Already deployed!");
    require(d1Fuel[turretId] > 0, "Out of D1 fuel");

    isDeployed[turretId] = true;
    lastFuelBurnTimestamp[turretId] = block.timestamp;

    // Restart the clock for every drone in the cargo
    uint256[] memory drones = hubInventory[turretId];
    for (uint i = 0; i < drones.length; i++) {
      turretMemory[turretId][drones[i]].lastHealTime = block.timestamp;
    }

    emit TurretDeployed(turretId, coordinates);
  }

  // 4. Updated Pack Up: Calculates final HP and pauses the timer
  function packUpHub(uint256 turretId) public {
    require(isDeployed[turretId], "Already in cargo!");

    _syncFuel(turretId);

    // Permanently save the healed HP to memory before pulling the plug
    uint256[] memory drones = hubInventory[turretId];
    for (uint i = 0; i < drones.length; i++) {
      uint256 dId = drones[i];
      turretMemory[turretId][dId].hp = getCurrentHP(turretId, dId);
    }

    isDeployed[turretId] = false;
    lastFuelBurnTimestamp[turretId] = 0;
    emit TurretPacked(turretId);
  }

  // 3. Catching the Drone (Puts it in the bay)
  function captureDronePersistent(uint256 turretId, uint256 droneId, uint256 startingHP) public {
    require(isDeployed[turretId], "Deploy the hub first!");

    if (!capturedDrones[droneId]) {
      require(droneCount < maxCapacity, "Turret is at max drone capacity!");
      capturedDrones[droneId] = true;
      droneCount += 1;
    }

    turretMemory[turretId][droneId] = DroneStats({
      isCaptured: true,
      inBay: true,
      hp: startingHP,
      lastHealTime: block.timestamp
    });

    hubInventory[turretId].push(droneId);

    emit DroneStatusUpdated(turretId, droneId, startingHP);
  }

  // IFF Matrix: turretId => characterId => isFriendly
  mapping(uint256 => mapping(uint256 => bool)) public iffFriendlyIds;

  event IFFUpdated(uint256 indexed turretId, uint256 indexed characterId, bool isFriendly);
  event IntruderEngaged(uint256 indexed turretId, uint256 indexed intruderId, uint256 indexed deployedDroneId);

  function setIFFFriendly(uint256 turretId, uint256 characterId, bool friendStatus) public {
    iffFriendlyIds[turretId][characterId] = friendStatus;
    emit IFFUpdated(turretId, characterId, friendStatus);
  }

  function isFriendly(uint256 turretId, uint256 characterId) public view returns (bool) {
    return iffFriendlyIds[turretId][characterId];
  }

  function engageIfHostile(uint256 turretId, uint256 intruderId) public returns (bool engaged) {
    if (isFriendly(turretId, intruderId)) {
      return false;
    }

    if (!isDeployed[turretId]) {
      return false;
    }

    _syncFuel(turretId);
    if (d1Fuel[turretId] == 0) {
      return false;
    }

    uint256 availableDroneId = _findAvailableDrone(turretId);
    if (availableDroneId == 0) {
      return false;
    }

    deployDroneToAttack(turretId, availableDroneId, intruderId);
    emit IntruderEngaged(turretId, intruderId, availableDroneId);
    return true;
  }

  function _findAvailableDrone(uint256 turretId) internal view returns (uint256 availableDroneId) {
    for (uint256 droneId = 10000; droneId <= 20000; droneId++) {
      if (capturedDrones[droneId] && turretMemory[turretId][droneId].inBay && !refinedDrones[droneId] && !expendedDrones[droneId]) {
        return droneId;
      }
    }

    return 0;
  }

  function canExtract(uint256 extractorCharacterId) public view returns (bool) {
    uint256 allowedCorp = TurretAllowlist.get();
    uint256 extractorCorp = Characters.getTribeId(extractorCharacterId);

    return extractorCorp == allowedCorp;
  }

  function extractCapturedDrone(uint256 smartTurretId, uint256 extractorCharacterId, uint256 droneId) public {
    smartTurretId;

    require(capturedDrones[droneId], "Drone is not captured");
    require(CharactersByAccount.get(_msgSender()) == extractorCharacterId, "Character does not belong to sender");
    require(canExtract(extractorCharacterId), "Access denied: corp mismatch");

    capturedDrones[droneId] = false;
    if (droneCount > 0) {
      droneCount -= 1;
    }

    emit DroneExtracted(smartTurretId, extractorCharacterId, droneId);
  }

  function loadD1Fuel(uint256 turretId, uint256 amount) public {
    require(amount > 0, "Fuel amount must be greater than zero");

    if (isDeployed[turretId]) {
      _syncFuel(turretId);
    }

    d1Fuel[turretId] += amount;

    if (isDeployed[turretId] && lastFuelBurnTimestamp[turretId] == 0) {
      lastFuelBurnTimestamp[turretId] = block.timestamp;
    }

    emit D1FuelLoaded(turretId, amount, d1Fuel[turretId]);
  }

  function getCurrentD1Fuel(uint256 turretId) public view returns (uint256) {
    if (!isDeployed[turretId]) {
      return d1Fuel[turretId];
    }

    uint256 lastBurn = lastFuelBurnTimestamp[turretId];
    if (lastBurn == 0 || d1Fuel[turretId] == 0) {
      return d1Fuel[turretId];
    }

    uint256 elapsedMinutes = (block.timestamp - lastBurn) / D1_BURN_INTERVAL_SECONDS;
    if (elapsedMinutes >= d1Fuel[turretId]) {
      return 0;
    }

    return d1Fuel[turretId] - elapsedMinutes;
  }

  function isDrone(uint256 droneId) public pure returns (bool) {
    return droneId >= 10000 && droneId <= 20000;
  }

  function _syncFuel(uint256 turretId) internal {
    if (!isDeployed[turretId]) {
      return;
    }

    uint256 fuelBalance = d1Fuel[turretId];
    uint256 lastBurn = lastFuelBurnTimestamp[turretId];

    if (fuelBalance == 0) {
      lastFuelBurnTimestamp[turretId] = block.timestamp;
      return;
    }

    if (lastBurn == 0) {
      lastFuelBurnTimestamp[turretId] = block.timestamp;
      return;
    }

    uint256 elapsedMinutes = (block.timestamp - lastBurn) / D1_BURN_INTERVAL_SECONDS;
    if (elapsedMinutes == 0) {
      return;
    }

    uint256 consumed = elapsedMinutes;
    if (consumed >= fuelBalance) {
      consumed = fuelBalance;
      d1Fuel[turretId] = 0;
      lastFuelBurnTimestamp[turretId] = block.timestamp;
      emit D1FuelConsumed(turretId, consumed, 0);
      _feralizeDeployedDrones(turretId);
      return;
    }

    d1Fuel[turretId] = fuelBalance - consumed;
    lastFuelBurnTimestamp[turretId] = lastBurn + (elapsedMinutes * D1_BURN_INTERVAL_SECONDS);
    emit D1FuelConsumed(turretId, consumed, d1Fuel[turretId]);
  }

  function _feralizeDeployedDrones(uint256 turretId) internal {
    uint256[] memory drones = hubInventory[turretId];
    for (uint256 i = 0; i < drones.length; i++) {
      uint256 droneId = drones[i];
      DroneStats storage drone = turretMemory[turretId][droneId];

      if (drone.isCaptured && !drone.inBay) {
        drone.isCaptured = false;
        drone.hp = 0;

        if (capturedDrones[droneId]) {
          capturedDrones[droneId] = false;
          if (droneCount > 0) {
            droneCount -= 1;
          }
        }

        emit DroneBecameFeral(turretId, droneId);
      }
    }
  }

  function _isDrone(uint256 targetCharacterId) internal view returns (bool) {
    return !Characters.getExists(targetCharacterId);
  }

  /**
   * @dev a function to implement logic for Smart Turret based on proximity
   * @param smartTurretId The Smart Turret id
   * @param characterId is the owner of the Smart Turret
   * @param priorityQueue is the queue of existing targets ordered by priority, index 0 being the lowest priority
   * @param turret is the turret data
   * @param turretTarget is the player in the zone
   * This runs on a tick based cycle when the player is in proximity of the Smart Turret
   * The game receives the new priority queue, and select targets based on the reverse order of the new queue. 
   * Meaning the targets with the highest index will be picked first.
   */
  function inProximity(
    uint256 smartTurretId,
    uint256 characterId,
    TargetPriority[] memory priorityQueue,
    Turret memory turret,
    SmartTurretTarget memory turretTarget
  ) public view returns (TargetPriority[] memory updatedPriorityQueue) {
    // Get the allowed corp ID singleton
    uint256 allowedCorp = TurretAllowlist.get();
    // Get the corp ID of the player that is in proximity of the Smart Turret
    uint256 characterCorp = Characters.getTribeId(turretTarget.characterId);

    // Find if the player is already in the queue. 
    // This might happen if the player joins the corp while in proximity.
    bool foundInPriorityQueue = getIsTargetInQueue(priorityQueue, turretTarget.characterId);
    
    // Check if the player shouldn't be targeted
    if (characterCorp == allowedCorp) {
      if (!foundInPriorityQueue) {
        // Return the unchanged array
        return priorityQueue;     
      }

      // If found, create a new array without the character
      return removeTargetFromQueue(priorityQueue, turretTarget.characterId);
    }

    // Prioritize ships with the lowest total health percentage. hPRatio, shieldRatio and armorRatio are between [0-100]
    uint256 calculatedWeight = calculateWeight(turretTarget);

    // Weight is not currently used in-game as the game uses the position of elements in the array, however we set it for the bubble sort algorithm to use
    // If already in the queue, update the weight and sort the array
    if (foundInPriorityQueue) {
      return updateWeight(priorityQueue);
    }

    // Create the new priority
    TargetPriority memory newTarget = TargetPriority({ target: turretTarget, weight: calculatedWeight }); 

    // If not already in the queue, add to the queue
    return addTargetToQueue(priorityQueue, newTarget);
  }

  /**
   * @dev a function to check if a target is in the queue
   * @param priorityQueue is the queue to check
   * @param characterId is the character ID to check
   * @return isInQueue is true if the target is in the queue
   */
  function getIsTargetInQueue(
    TargetPriority[] memory priorityQueue, 
    uint256 characterId
  ) public pure returns (bool isInQueue) {
    for (uint i = 0; i < priorityQueue.length; i++) {
      if (priorityQueue[i].target.characterId == characterId) {
        return true;
      }
    }

    return false;
  }

  /**
   * @dev a function to remove a target from the queue
   * @param priorityQueue is the queue to remove the target from
   * @param characterId is the character ID to remove
   * @return updatedPriorityQueue is the updated queue
   */
  function removeTargetFromQueue(
    TargetPriority[] memory priorityQueue, 
    uint256 characterId
  ) public pure returns (TargetPriority[] memory updatedPriorityQueue) {
      // Create the smaller temporary array
      updatedPriorityQueue = new TargetPriority[](priorityQueue.length - 1);

      // Loop over the queue and only set if not the character
      for (uint i = 0; i < priorityQueue.length; i++) {
        if (priorityQueue[i].target.characterId != characterId) {
          updatedPriorityQueue[i] = priorityQueue[i];
        }
      }

      // Sort the array
      updatedPriorityQueue = bubbleSortTargetPriorityArray(updatedPriorityQueue);

      return updatedPriorityQueue;
  }

  /**
   * @dev a function to update all of the weights in the queue
   * @param priorityQueue is the queue to update the weights of the targets in
   * @return updatedPriorityQueue is the updated queue
   */
  function updateWeight(
    TargetPriority[] memory priorityQueue
  ) public pure returns (TargetPriority[] memory updatedPriorityQueue) {
    for (uint i = 0; i < priorityQueue.length; i++) {
      priorityQueue[i].weight = calculateWeight(priorityQueue[i].target);
    }

    // Sort the array
    priorityQueue = bubbleSortTargetPriorityArray(priorityQueue);

    return priorityQueue;
  }

  /**
   * @dev a function to add a target to the queue
   * @param priorityQueue is the queue to add the target to
   * @param newTarget is the target to add
   * @return updatedPriorityQueue is the updated queue
   */
  function addTargetToQueue(
    TargetPriority[] memory priorityQueue, 
    TargetPriority memory newTarget
  ) public pure returns (TargetPriority[] memory updatedPriorityQueue) {
    // Create the larger temporary array
    updatedPriorityQueue = new TargetPriority[](priorityQueue.length + 1);

    // Clone the priority queue to the temp array
    for (uint i = 0; i < priorityQueue.length; i++) {
      updatedPriorityQueue[i] = priorityQueue[i];
    }

    // Set the new target to the end of the temp array
    updatedPriorityQueue[priorityQueue.length] = newTarget;      

    // Sort the array
    updatedPriorityQueue = bubbleSortTargetPriorityArray(updatedPriorityQueue);

    return updatedPriorityQueue;
  }

  /**
   * @dev a function to sort the priority queue by weight, using the bubble sort algorithm
   * @param priorityQueue is the queue to sort
   */
  function bubbleSortTargetPriorityArray(
    TargetPriority[] memory priorityQueue
  ) public pure returns (TargetPriority[] memory sortedPriorityQueue) {
    uint256 length = priorityQueue.length;

    // Doesn't need sorting if the queue only has 1 or 0 entries
    if (length < 2) return priorityQueue;

    bool swapped;
    // Loop until the bubble sort algorithm stops sorting
    do {
      swapped = false;

      // Loop to the second last element, as it will sort for the next element
      for (uint256 i = 0; i < length - 1; i++) {
        // Check if a swap needs to happen
        if (priorityQueue[i].weight > priorityQueue[i + 1].weight) {
          // Swap the values in the array
          (priorityQueue[i], priorityQueue[i+1]) = (priorityQueue[i + 1], priorityQueue[i]);
          // Do another loop
          swapped = true;
        }
      }
    }
    while (swapped);

    return priorityQueue;
  }

  /**
   * @dev a function to calculate the weight of the target
   * @param target is the target
   * This calculates weight so that the higher the weight, the higher the priority. 
   * As the targets are prioritized and the game selects the targets in reverse order they are returned.
   */
  function calculateWeight(SmartTurretTarget memory target) internal pure returns (uint256 weight) {
    uint256 MAX_COMBINED_HP_RATIO = 300;

    weight = MAX_COMBINED_HP_RATIO - (
      target.hpRatio + 
      target.shieldRatio + 
      target.armorRatio
    );

    return weight;
  }

  /**
   * @dev a function to set the allowed tribe which does not get targeted by the Smart Turret
   * @param tribeID is the allowed tribe
   * @notice this function is only callable by the owner of the smart turret
   */
  function setAllowedTribe(uint256 smartTurretId, uint256 tribeID) public {
    // Ensure it's the admin calling this function
    require(accessSystem.isOwner(smartTurretId, _msgSender()), "You are not authorized to set the allowed tribe");

    // Validation check on the tribe ID
    require(tribeID > 1000, "Invalid Tribe ID");

    // Set the allowed corp ID in MUD
    TurretAllowlist.set(tribeID);
  }

  /**
   * @dev a function to implement logic for smart turret based on aggression
   * @param aggressionParams is the aggression parameters
   */
  function aggression(
    AggressionParams memory aggressionParams
  ) public view returns (TargetPriority[] memory updatedPriorityQueue) {
    return aggressionParams.priorityQueue;
  }
}
