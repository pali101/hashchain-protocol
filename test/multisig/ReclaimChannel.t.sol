// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {Multisig} from "../../src/Multisig_2of2.sol";
import {BaseTestHelper} from "../helper/BaseTestHelper.sol";

contract ReclaimChannelTest is Test, BaseTestHelper {
    Multisig public multisig;

    function setUp() public {
        setUpNativeTokenWithCreateChannel();
    }

    function setUpNativeToken() public {
        vm.startPrank(OWNER);
        multisig = new Multisig();
        vm.stopPrank();
        vm.deal(PAYER, INITIAL_BALANCE);
        vm.deal(PAYER2, INITIAL_BALANCE);
    }

    function setUpNativeTokenWithCreateChannel() public {
        setUpNativeToken();
        vm.startPrank(PAYER);
        multisig.createChannel{value: DEPOSIT_AMOUNT}(PAYEE, NATIVE_TOKEN, DEPOSIT_AMOUNT, DURATION, RECLAIM_DELAY);
        vm.stopPrank();
    }

    function testMultisigReclaimChannelWithNativeToken() public {
        uint256 contractBalanceBefore = address(multisig).balance;
        uint256 payerBalanceBefore = PAYER.balance;
        vm.warp(block.timestamp + RECLAIM_DELAY + 1); // Move time forward to allow reclaim
        vm.startPrank(PAYER);
        multisig.reclaimChannel(PAYEE, NATIVE_TOKEN);
        vm.stopPrank();

        uint256 contractBalanceAfter = address(multisig).balance;
        uint256 payerBalanceAfter = PAYER.balance;

        assertEq(
            contractBalanceAfter, contractBalanceBefore - DEPOSIT_AMOUNT, "Incorrect contract balance after reclaim"
        );
        assertEq(payerBalanceAfter - payerBalanceBefore, DEPOSIT_AMOUNT, "Incorrect amount sent to payer");
    }

    function testMultipleReclaimChannelTooEarlyRevert() public {
        uint256 contractBalanceBefore = address(multisig).balance;
        uint256 payerBalanceBefore = PAYER.balance;
        vm.warp(block.timestamp + RECLAIM_DELAY - 10); // Move time forward but not enough to allow reclaim
        vm.startPrank(PAYER);
        vm.expectRevert(
            abi.encodeWithSignature("PayerCannotRedeemChannelYet(uint256,uint256)", block.timestamp, RECLAIM_DELAY + 1)
        );
        multisig.reclaimChannel(PAYEE, NATIVE_TOKEN);
        vm.stopPrank();

        _assertChannelStateWhenFailedReclaim(
            contractBalanceBefore, payerBalanceBefore, address(multisig).balance, PAYER.balance
        );
    }

    function testMultipleNonExistentChannelReclaim() public {
        uint256 contractBalanceBefore = address(multisig).balance;
        uint256 payerBalanceBefore = PAYER.balance;
        vm.startPrank(PAYER);
        vm.expectRevert(abi.encodeWithSignature("ChannelDoesNotExistOrWithdrawn()"));
        multisig.reclaimChannel(PAYEE2, NATIVE_TOKEN); // PAYEE2 has no channel with PAYER
        vm.stopPrank();

        _assertChannelStateWhenFailedReclaim(
            contractBalanceBefore, payerBalanceBefore, address(multisig).balance, PAYER.balance
        );
    }

    function _assertChannelStateWhenFailedReclaim(
        uint256 contractBalanceBefore,
        uint256 payeeBalanceBefore,
        uint256 contractBalanceAfter,
        uint256 payeeBalanceAfter
    ) internal pure {
        assertEq(
            contractBalanceAfter, contractBalanceBefore, "contract balance should remain unchanged after failed redeem"
        );
        assertEq(payeeBalanceAfter, payeeBalanceBefore, "payee balance should remain unchanged after failed redeem");
    }
}
