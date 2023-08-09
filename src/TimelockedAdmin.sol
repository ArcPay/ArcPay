// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {TimelockController} from "../lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {Ownable2Step} from "../lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";

contract TimelockedAdmin is TimelockController, Ownable2Step {
    constructor(uint minDelay, address[] memory proposers, address[] memory executors, address admin)
        TimelockController(minDelay, proposers, executors, admin)
    {}
}
