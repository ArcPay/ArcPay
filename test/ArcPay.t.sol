// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {ArcPay} from "../src/ArcPay.sol";
import {TimelockedAdmin} from "../src/TimelockedAdmin.sol";
import {ERC1967Proxy} from "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ArcPayV2} from "./ArcPayV2.sol";

contract ArcPayTest is Test {
    // `arcProxy` and `arc` refer to the same address, but expose different interfaces.
    ERC1967Proxy public arcProxy;
    ArcPay public arc;

    ArcPay public arcImpl;

    ArcPayV2 public arcV2;

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

        arcProxy = new ERC1967Proxy{salt : salt}(
                address(arcImpl),
                abi.encodeCall(ArcPay.initialize, (arcOwner, operator))
            );

        arc = ArcPay(payable(address(arcProxy)));

        // treated as the new implementation to test proxy upgrades.
        arcV2 = new ArcPayV2();
    }

    ///// Proxy tests /////
    function test_implInitialize() public {
        vm.expectRevert("Initializable: contract is already initialized");
        arcImpl.initialize(arcOwner, operator);
    }

    function test_failProxyUpgrade() public {
        vm.expectRevert("Ownable: caller is not the owner");
        arc.upgradeTo(address(10));

        // cannot upgrade to an EOA
        vm.startPrank(address(arcOwner));
        vm.expectRevert();
        arc.upgradeTo(address(101));

        arc.upgradeTo(address(arcV2));
    }

    function test_failTimelockOperations() public {
        vm.startPrank(proposer);
        vm.expectRevert("TimelockController: insufficient delay");
        arcOwner.schedule(address(arcProxy), 0, "", bytes32(0), bytes32(0), 0);

        vm.expectRevert("TimelockController: insufficient delay");
        arcOwner.schedule(address(arcProxy), 0, "", bytes32(0), bytes32(0), 1 days - 1);

        arcOwner.schedule(address(arcProxy), 0, "", bytes32(0), bytes32(0), 1 days);

        vm.expectRevert(); // TODO: add revert message, the error string needs to be constructed.
        arcOwner.execute(address(arcProxy), 0, "", bytes32(0), bytes32(0));
        vm.stopPrank();

        vm.expectRevert(); // TODO: add revert message, the error string needs to be constructed.
        arcOwner.execute(address(arcProxy), 0, "", bytes32(0), bytes32(0));

        vm.warp(block.timestamp + 1 days - 1);
        vm.expectRevert(); // TODO: add revert message, the error string needs to be constructed.
        arcOwner.execute(address(arcProxy), 0, "", bytes32(0), bytes32(0));

        vm.warp(block.timestamp + 1);
        vm.expectRevert(); // TODO: add revert message, the error string needs to be constructed.
        arcOwner.execute(address(arcProxy), 0, "", bytes32(0), bytes32(0));

        vm.warp(block.timestamp - 100);
        vm.startPrank(executor);
        vm.expectRevert("TimelockController: operation is not ready");
        arcOwner.execute(address(arcProxy), 0, "", bytes32(0), bytes32(0));
        vm.stopPrank();
    }

    function test_proxyUpgrade() public {
        vm.startPrank(proposer);
        arcOwner.schedule(address(arcProxy), 0, abi.encodeCall(arc.upgradeTo, address(arcV2)), bytes32(0), bytes32(0), 1 days);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        vm.startPrank(executor);
        arcOwner.execute(address(arcProxy), 0, abi.encodeCall(arc.upgradeTo, address(arcV2)), bytes32(0), bytes32(0));
        vm.stopPrank();

        arcV2 = ArcPayV2(payable(address(arcProxy)));
        assertTrue(arcV2.v2());

        arcV2.mint{value: 1 ether}(address(this));

        assertEq(arcV2.operator(), operator);
    }

    function testMint() public {
        arc.mint{value: 1 ether}(address(1));
    }
}
