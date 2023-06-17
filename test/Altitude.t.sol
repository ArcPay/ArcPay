// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Altitude.sol";

contract AltitudeTest is Test {
    Altitude public alt;

    function setUp() public {
        alt = new Altitude(address(this));
    }

}
