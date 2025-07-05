// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {Multisig} from "../../src/Multisig_2of2.sol";
import {BaseTestHelper} from "../helper/BaseTestHelper.sol";

contract CreateChannelTest is Test {
    Multisig multisig;
    address payer = address(0x1);
    address payee = address(0x2);
    address token = address(0x3);
    uint256 amount = 1000;
    uint64 duration = 100;
    uint64 reclaimDelay = 200;

    function setUp() public {
        multisig = new Multisig();
        vm.deal(payer, 10 * amount);
    }

    function testMultisigCreateChannelWithNative() public {
        vm.startPrank(payer);
        multisig.createChannel{value: amount}(payee, address(0), amount, duration, reclaimDelay);
        vm.stopPrank();

        // Verify channel creation
        (
            address channelToken,
            uint256 channelAmount,
            uint64 channelExpiration,
            uint64 reclaimAfter,
            uint256 sessionId,
            uint256 lastNounce
        ) = multisig.channels(payer, payee, address(0));
        assertEq(channelToken, address(0));
        assertEq(channelAmount, amount);
        assertEq(channelExpiration, uint64(block.timestamp) + duration);
        assertEq(sessionId, 1);
        assertEq(reclaimAfter, uint64(block.timestamp) + reclaimDelay);
        assertEq(lastNounce, 1);
    }

    function testMultisigCreateChannelFailsIfReclaimTooSoon() public {
        vm.startPrank(payer);
        vm.expectRevert(
            abi.encodeWithSignature(
                "ReclaimAfterMustBeAfterExpiration(uint64,uint64)", block.timestamp + duration, block.timestamp + 0
            )
        );
        multisig.createChannel{value: amount}(payee, address(0), amount, duration, 0);
        vm.stopPrank();

        _assertChannelNotCreated();
    }

    function testMultisigCreateChannelFailsIfAmountIncorrect() public {
        vm.startPrank(payer);
        vm.expectRevert(abi.encodeWithSignature("IncorrectAmount(uint256,uint256)", amount, amount + 1));
        multisig.createChannel{value: amount}(payee, address(0), amount + 1, duration, reclaimDelay);
        vm.stopPrank();

        _assertChannelNotCreated();
    }

    function testMultisigCreateChannelsFailsIfDuplicate() public {
        vm.startPrank(payer);
        multisig.createChannel{value: amount}(payee, address(0), amount, duration, reclaimDelay);
        vm.expectRevert(
            abi.encodeWithSignature(
                "ChannelAlreadyExist(address,address,address,uint256)", payer, payee, address(0), amount
            )
        );
        amount += 1; // Change amount to trigger revert
        multisig.createChannel{value: amount}(payee, address(0), amount, duration, reclaimDelay);
        amount -= 1; // Reset amount for next tests
        vm.stopPrank();

        // Verify channel have initial values (amount)
        (
            address channelToken,
            uint256 channelAmount,
            uint64 channelExpiration,
            uint64 reclaimAfter,
            uint256 sessionId,
            uint256 lastNounce
        ) = multisig.channels(payer, payee, address(0));
        assertEq(channelToken, address(0), "Channel should use native ETH (zero address)");
        assertEq(channelAmount, amount, "Channel amount should match the deposit");
        assertEq(channelExpiration, uint64(block.timestamp) + duration, "Expiration not set correctly");
        assertEq(reclaimAfter, uint64(block.timestamp) + reclaimDelay, "ReclaimAfter not set correctly");
        assertEq(sessionId, 1, "SessionId should start at 1");
        assertEq(lastNounce, 1, "LastNonce should start at 1");
    }

    // Helper function to check channel not created
    function _assertChannelNotCreated() private view {
        (
            address channelToken,
            uint256 channelAmount,
            uint64 channelExpiration,
            uint64 reclaimAfter,
            uint256 sessionId,
            uint256 lastNounce
        ) = multisig.channels(payer, payee, address(0));

        assertEq(channelToken, address(0), "default address should be zero address");
        assertEq(channelAmount, 0, "default amount should be zero");
        assertEq(channelExpiration, 0, "default expiration should be zero");
        assertEq(sessionId, 0, "default sessionId should be zero");
        assertEq(reclaimAfter, 0, "default reclaimAfter should be zero");
        assertEq(lastNounce, 0, "default lastNounce should be zero");
    }
}
