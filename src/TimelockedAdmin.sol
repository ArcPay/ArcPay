// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {TimelockController} from "../lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";

contract TimelockedAdmin is TimelockController {
    constructor(uint minDelay, address[] memory proposers, address[] memory executors, address admin)
        TimelockController(minDelay, proposers, executors, admin)
    {}
}
