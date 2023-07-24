// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/ArcPay.sol";

contract ArcPayScript is Script {
    function setUp() public {}

    function run() public {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        console2.log(
            // Owner is set to Anvil's first address.
            address(new ArcPay(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266))
        );
        vm.stopBroadcast();
    }
}
