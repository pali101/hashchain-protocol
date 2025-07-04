// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {MuPay} from "../src/MuPay.sol";

contract MaliciousReceiver {
    // Rejects any ETH sent to it
    fallback() external payable {
        revert("ETH Transfer Failed");
    }
}

contract RedeemChannelTest is Test {
    MuPay public muPay;
    address public payer = address(0x1);
    address public merchant = address(0x2);

    // Setup parameters
    address token = address(0);
    bytes32 trustAnchor = 0x7cacb8c6cc65163d30a6c8ce47c0d284490d228d1d1aa7e9ae3f149f77b32b5d;
    bytes32 finalToken = 0x484f839e58e0b400163856f9b4d2c6254e142d89d8b03f1e33a6717620170f30;
    uint256 amount = 1e18;
    uint16 numberOfTokens = 100;
    uint64 merchantWithdrawAfterBlocks = uint64(block.number) + 10;
    uint64 payerWithdrawAfterBlocks = uint64(block.number) + 100;
    uint16 numberOfTokensUsed = 50;

    function setUp() external {
        muPay = new MuPay();
        vm.deal(payer, 10 ether);

        // Expect event emission
        vm.expectEmit(true, true, false, true);
        emit MuPay.ChannelCreated(payer, merchant, token, amount, numberOfTokens, merchantWithdrawAfterBlocks);

        vm.prank(payer);
        muPay.createChannel{value: amount}(
            merchant, token, trustAnchor, amount, numberOfTokens, merchantWithdrawAfterBlocks, payerWithdrawAfterBlocks
        );
    }

    function testRedeemChannelSuccess() public {
        // Move forward by 11 block
        vm.roll(block.number + 11);

        (,, uint256 storedAmount, uint256 storedNumberOfToken,,) = muPay.channelsMapping(payer, merchant, token);

        uint256 payableAmountMerchant = (storedAmount * numberOfTokensUsed) / storedNumberOfToken;
        uint256 payableAmountPayer = storedAmount - payableAmountMerchant;

        uint256 payerBalanceBefore = payer.balance;
        uint256 contractBalanceBefore = address(muPay).balance;
        uint256 merchantBalanceBefore = merchant.balance;

        vm.expectEmit(true, true, false, true);
        emit MuPay.ChannelRedeemed(payer, merchant, token, payableAmountMerchant, finalToken, numberOfTokensUsed);

        vm.expectEmit(true, true, false, true);
        emit MuPay.ChannelRefunded(payer, merchant, token, payableAmountPayer);

        vm.prank(merchant);
        muPay.redeemChannel(payer, token, finalToken, numberOfTokensUsed);

        // Check balances after transaction
        uint256 payerBalanceAfter = payer.balance;
        uint256 contractBalanceAfter = address(muPay).balance;
        uint256 merchantBalanceAfter = merchant.balance;

        // Verify balance deductions
        assertEq(payerBalanceAfter - payerBalanceBefore, payableAmountPayer, "Incorrect amount refunded to payer");
        assertEq(contractBalanceBefore - contractBalanceAfter, amount, "Incorrect amount deducted from contract");
        assertEq(
            merchantBalanceAfter - merchantBalanceBefore, payableAmountMerchant, "Incorrect amount added to merchant"
        );

        (,, uint256 retrievedAmount,,,) = muPay.channelsMapping(payer, merchant, token);
        assertEq(retrievedAmount, 0, "Channel should be deleted after redeeming");
    }

    function testRedeemBeforeAllowedBlocks() public {
        vm.expectRevert(
            abi.encodeWithSelector(MuPay.MerchantCannotRedeemChannelYet.selector, merchantWithdrawAfterBlocks + 1)
        );

        vm.prank(merchant);
        muPay.redeemChannel(payer, token, finalToken, numberOfTokensUsed);
    }

    function testRedeemWithIncorrectToken() public {
        bytes32 incorrectFinalToken = 0x484f839e58e0b400163856f9b4d2c6254e142d89d8b03f1e33a6717620170f31;

        vm.roll(block.number + 11);
        vm.expectRevert(MuPay.TokenVerificationFailed.selector);

        vm.prank(merchant);
        muPay.redeemChannel(payer, token, incorrectFinalToken, numberOfTokensUsed);
    }

    function testRedeemWithTokenCountExceeded() public {
        (,,, uint16 storedNumberOfToken,,) = muPay.channelsMapping(payer, merchant, token);
        uint16 incorrectNumberOfTokensUsed = storedNumberOfToken + 10;

        vm.roll(block.number + 11);
        vm.expectRevert(
            abi.encodeWithSelector(MuPay.TokenCountExceeded.selector, storedNumberOfToken, incorrectNumberOfTokensUsed)
        );

        vm.prank(merchant);
        muPay.redeemChannel(payer, token, finalToken, incorrectNumberOfTokensUsed);
    }

    function testRedeemPaymentDistribution() public {
        vm.roll(block.number + 11);
        (,, uint256 storedAmount, uint256 storedNumberOfToken,,) = muPay.channelsMapping(payer, merchant, token);

        // calculate expected payments
        uint256 payableAmountMerchant = (storedAmount * numberOfTokensUsed) / storedNumberOfToken;
        uint256 payableAmountPayer = storedAmount - payableAmountMerchant;

        // Capture balances before the transaction
        uint256 payerBalanceBefore = payer.balance;
        uint256 contractBalanceBefore = address(muPay).balance;
        uint256 merchantBalanceBefore = merchant.balance;

        vm.expectEmit(true, true, false, true);
        emit MuPay.ChannelRedeemed(payer, merchant, token, payableAmountMerchant, finalToken, numberOfTokensUsed);

        vm.expectEmit(true, true, false, true);
        emit MuPay.ChannelRefunded(payer, merchant, token, payableAmountPayer);

        vm.prank(merchant);
        muPay.redeemChannel(payer, token, finalToken, numberOfTokensUsed);

        // Check balances after transaction
        uint256 payerBalanceAfter = payer.balance;
        uint256 contractBalanceAfter = address(muPay).balance;
        uint256 merchantBalanceAfter = merchant.balance;

        // Verify balance deductions
        assertEq(payerBalanceAfter - payerBalanceBefore, payableAmountPayer, "Incorrect amount refunded to payer");
        assertEq(contractBalanceBefore - contractBalanceAfter, amount, "Incorrect amount deducted from contract");
        assertEq(
            merchantBalanceAfter - merchantBalanceBefore, payableAmountMerchant, "Incorrect amount added to merchant"
        );
    }

    function testRedeemChannelFailToSendEther() public {
        MaliciousReceiver maliciousMerchant = new MaliciousReceiver();

        vm.prank(payer);
        muPay.createChannel{value: amount}(
            address(maliciousMerchant),
            token,
            trustAnchor,
            amount,
            numberOfTokens,
            merchantWithdrawAfterBlocks,
            payerWithdrawAfterBlocks
        );

        vm.roll(block.number + 11);

        vm.expectRevert(MuPay.FailedToSendEther.selector);

        // Malicious merchant tries to redeem
        vm.prank(address(maliciousMerchant));
        muPay.redeemChannel(payer, token, finalToken, numberOfTokensUsed);
    }
}
