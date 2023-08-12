// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/ArcPay.sol";
import "../src/TimelockedAdmin.sol";
import {ERC1967Proxy} from "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract ArcPayTest is Test {
    ArcPay public arcProxy;
    ArcPay public arcImpl;
    TimelockedAdmin public arcOwner;
    address admin;
    address proposer;
    address executor;
    address operator;
    bytes32 salt = "1";

    function setUp() public {
        admin = makeAddr("admin");
        proposer = makeAddr("proposer");
        executor = makeAddr("executor");
        operator = makeAddr("operator");
        arcImpl = new ArcPay();

        address[] memory proposers = new address[](1);
        proposers[0] = proposer;
        address[] memory executors = new address[](1);
        executors[0] = executor;

        arcOwner = new TimelockedAdmin(1 days, proposers, executors, admin);
        arcProxy = ArcPay(payable(address(
            new ERC1967Proxy{salt : salt}(
                address(arcImpl),
                abi.encodeCall(ArcPay.initialize, (arcOwner, operator))
        ))));
    }

    function testMint() public {
        arcProxy.mint{value: 1}(address(1));
    }
}
