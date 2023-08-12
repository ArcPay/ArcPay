// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ArcPay} from "../src/ArcPay.sol";

// This contract is just to test proxy upgrade.
contract ArcPayV2 is ArcPay {
    function v2() external pure returns (bool) {
        return true;
    }
}

