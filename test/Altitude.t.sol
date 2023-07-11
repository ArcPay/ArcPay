// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/ArcPay.sol";

contract ArcPayTest is Test {
    ArcPay public alt;

    function setUp() public {
        alt = new ArcPay(address(this));
    }

}
