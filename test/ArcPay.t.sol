// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/ArcPay.sol";

contract ArcPayTest is Test {
    ArcPay public arc;

    function setUp() public {
        arc = new ArcPay(address(this));
    }

    function testMint() public {
        arc.mint{value: 1}(address(1));
    }
}
