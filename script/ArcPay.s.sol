// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/ArcPay.sol";
import {ERC1967Proxy} from "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract ArcPayScript is Script {
    function setUp() public {}

    function run() public {
        address admin = 0x90F79bf6EB2c4f870365E785982E1f101E93b906; // anvil's fourth key
        address proposer = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC; // anvil's third key
        address executor = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // anvil's second key
        address operator = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; // anvil's first key
        bytes32 arcSalt = "1";
        bytes32 ownerSalt = "1";

        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        ArcPay arcImpl = new ArcPay{salt: arcSalt}();
        console2.log("arcImpl", address(arcImpl));

        address[] memory proposers = new address[](1);
        proposers[0] = proposer;
        address[] memory executors = new address[](1);
        executors[0] = executor;

        TimelockedAdmin arcOwner = new TimelockedAdmin(1 days, proposers, executors, admin);
        console2.log("arcOwner", address(arcOwner));

        ArcPay arcProxy = ArcPay(payable(address(
            new ERC1967Proxy{salt : ownerSalt}(
                address(arcImpl),
                abi.encodeCall(ArcPay.initialize, (arcOwner, operator))
        ))));
        console2.log("arcProxy", address(arcProxy));
        vm.stopBroadcast();
    }
}
