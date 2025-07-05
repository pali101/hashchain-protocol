// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {Multisig} from "../../src/Multisig_2of2.sol";
import {BaseTestHelper} from "../helper/BaseTestHelper.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract RedeemChannelTest is Test, BaseTestHelper {
    Multisig public multisig;

    using MessageHashUtils for bytes32;

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

    function getSignature(
        address contractAddress,
        uint256 payerPk,
        address payee,
        address depositToken,
        uint256 amount,
        uint256 nonce,
        uint64 sessionId
    ) public pure returns (bytes memory signature) {
        address payer = vm.addr(payerPk);
        // Create the hash to sign
        bytes32 hash =
            keccak256(abi.encodePacked(contractAddress, payer, payee, depositToken, amount, nonce, sessionId));
        bytes32 messageHash = hash.toEthSignedMessageHash();
        // Sign the hash with the payer's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(payerPk, messageHash);
        signature = abi.encodePacked(r, s, v);
    }

    function testMultisigRedeemChannelWithNativeToken() public {
        uint256 contractBalanceBefore = address(multisig).balance;
        uint256 payeeBalanceBefore = PAYEE.balance;
        vm.startPrank(PAYEE);
        (,,,, uint64 sessionId, uint256 lastNonce) = multisig.channels(PAYER, PAYEE, NATIVE_TOKEN);
        bytes memory signature =
            getSignature(address(multisig), PAYER1PK, PAYEE, NATIVE_TOKEN, DEPOSIT_AMOUNT, lastNonce + 1, sessionId);

        multisig.redeemChannel(PAYER, NATIVE_TOKEN, DEPOSIT_AMOUNT, lastNonce + 1, signature);
        vm.stopPrank();

        // Verify channel redeemed
        (address channelToken, uint256 channelAmount,,,,) = multisig.channels(PAYER, PAYEE, NATIVE_TOKEN);
        assertEq(channelToken, NATIVE_TOKEN, "channel token should be zero address for native token");
        assertEq(channelAmount, 0, "channel amount should be zero after redeem");
        assertEq(
            address(multisig).balance,
            contractBalanceBefore - DEPOSIT_AMOUNT,
            "contract balance should decrease by deposit amount"
        );
        assertEq(PAYEE.balance, payeeBalanceBefore + DEPOSIT_AMOUNT, "payee balance should increase by deposit amount");
    }

    function testMultisigCannotRedeemWithInvalidSignature() public {
        uint256 contractBalanceBefore = address(multisig).balance;
        uint256 payeeBalanceBefore = PAYEE.balance;
        vm.startPrank(PAYEE);
        (,,,, uint64 sessionId, uint256 lastNonce) = multisig.channels(PAYER, PAYEE, NATIVE_TOKEN);
        bytes memory signature =
            getSignature(address(multisig), PAYER2PK, PAYEE, NATIVE_TOKEN, DEPOSIT_AMOUNT, lastNonce + 1, sessionId);

        // Attempt to redeem with an invalid signature
        // Expect revert with InvalidChannelSignature error
        vm.expectRevert();
        multisig.redeemChannel(PAYER, NATIVE_TOKEN, DEPOSIT_AMOUNT, lastNonce + 1, signature);
        vm.stopPrank();

        // Verify channel state remains unchanged
        _assertChannelStateWhenFailedRedeem(
            contractBalanceBefore, payeeBalanceBefore, address(multisig).balance, PAYEE.balance
        );
    }

    function testMultisigCannotRedeemAfterExpiration() public {
        (,,,, uint64 sessionId, uint256 lastNonce) = multisig.channels(PAYER, PAYEE, NATIVE_TOKEN);
        bytes memory signature =
            getSignature(address(multisig), PAYER1PK, PAYEE, NATIVE_TOKEN, DEPOSIT_AMOUNT, lastNonce + 1, sessionId);
        (,, uint64 expiration,,,) = multisig.channels(PAYER, PAYEE, NATIVE_TOKEN);
        vm.warp(expiration + 1); // Move time past expiration

        vm.startPrank(PAYEE);
        // Attempt to redeem after expiration
        vm.expectRevert(abi.encodeWithSignature("ChannelExpired(uint64)", expiration));
        multisig.redeemChannel(PAYER, NATIVE_TOKEN, DEPOSIT_AMOUNT, lastNonce + 1, signature);
        vm.stopPrank();
    }

    function testsMultisigCannotRedeemWithIncorrectAmountHigher() public {
        uint256 contractBalanceBefore = address(multisig).balance;
        uint256 payeeBalanceBefore = PAYEE.balance;
        vm.startPrank(PAYEE);
        (,,,, uint64 sessionId, uint256 lastNonce) = multisig.channels(PAYER, PAYEE, NATIVE_TOKEN);
        bytes memory signature =
            getSignature(address(multisig), PAYER1PK, PAYEE, NATIVE_TOKEN, DEPOSIT_AMOUNT + 1, lastNonce + 1, sessionId);

        // Attempt to redeem with an incorrect amount
        vm.expectRevert(abi.encodeWithSignature("IncorrectAmount(uint256,uint256)", DEPOSIT_AMOUNT + 1, DEPOSIT_AMOUNT));
        multisig.redeemChannel(PAYER, NATIVE_TOKEN, DEPOSIT_AMOUNT + 1, lastNonce + 1, signature);
        vm.stopPrank();

        // Verify channel state remains unchanged
        _assertChannelStateWhenFailedRedeem(
            contractBalanceBefore, payeeBalanceBefore, address(multisig).balance, PAYEE.balance
        );
    }

    function testMultisigCannotRedeemWIthStaleNonce() public {
        uint256 contractBalanceBefore = address(multisig).balance;
        uint256 payeeBalanceBefore = PAYEE.balance;
        vm.startPrank(PAYEE);
        (,,,, uint64 sessionId, uint256 lastNonce) = multisig.channels(PAYER, PAYEE, NATIVE_TOKEN);
        bytes memory signature =
            getSignature(address(multisig), PAYER1PK, PAYEE, NATIVE_TOKEN, DEPOSIT_AMOUNT, lastNonce - 1, sessionId);

        // Attempt to redeem with a stale nonce
        vm.expectRevert(abi.encodeWithSignature("StaleNonce(uint256,uint256)", lastNonce - 1, lastNonce));
        multisig.redeemChannel(PAYER, NATIVE_TOKEN, DEPOSIT_AMOUNT, lastNonce - 1, signature);
        vm.stopPrank();

        // Verify channel state remains unchanged
        _assertChannelStateWhenFailedRedeem(
            contractBalanceBefore, payeeBalanceBefore, address(multisig).balance, PAYEE.balance
        );
    }

    function testMultisigCannotRedeemChannelDoesNotExist() public {
        uint256 contractBalanceBefore = address(multisig).balance;
        uint256 payeeBalanceBefore = PAYEE.balance;
        vm.startPrank(PAYEE);
        bytes memory signature = getSignature(address(multisig), PAYER2PK, PAYEE, NATIVE_TOKEN, DEPOSIT_AMOUNT, 1, 1);

        // Attempt to redeem a channel that does not exist
        vm.expectRevert(abi.encodeWithSignature("ChannelDoesNotExistOrWithdrawn()"));
        multisig.redeemChannel(PAYER2, NATIVE_TOKEN, DEPOSIT_AMOUNT, 1, signature);
        vm.stopPrank();

        // Verify channel state remains unchanged
        _assertChannelStateWhenFailedRedeem(
            contractBalanceBefore, payeeBalanceBefore, address(multisig).balance, PAYEE.balance
        );
    }

    function testMultisigCannotRedeemFromWrongPayee() public {
        uint256 contractBalanceBefore = address(multisig).balance;
        uint256 payeeBalanceBefore = PAYEE.balance;
        vm.startPrank(PAYER2); // PAYER2 tries to redeem
        (,,,, uint64 sessionId, uint256 lastNonce) = multisig.channels(PAYER, PAYEE, NATIVE_TOKEN);
        bytes memory signature =
            getSignature(address(multisig), PAYER1PK, PAYEE, NATIVE_TOKEN, DEPOSIT_AMOUNT, lastNonce + 1, sessionId);

        // Attempt to redeem with the wrong payee
        // Revert with ChannelDoesNotExistOrWithdrawn error
        // since channel between PAYEE2 and PAYER does not exist
        vm.expectRevert(abi.encodeWithSignature("ChannelDoesNotExistOrWithdrawn()"));
        multisig.redeemChannel(PAYER, NATIVE_TOKEN, DEPOSIT_AMOUNT, lastNonce + 1, signature);
        vm.stopPrank();

        // Verify channel state remains unchanged
        _assertChannelStateWhenFailedRedeem(
            contractBalanceBefore, payeeBalanceBefore, address(multisig).balance, PAYEE.balance
        );
    }

    function _assertChannelStateWhenFailedRedeem(
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
