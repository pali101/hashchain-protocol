// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {MuPay} from "../src/MuPay.sol";

contract CreateChannelTest is Test {
    MuPay public muPay;
    address public payer = address(0x1);
    address public merchant = address(0x2);
    address token = address(0);

    function setUp() external {
        muPay = new MuPay();
        vm.deal(payer, 10 ether);
    }

    function testCreateChannelSuccess() public {
        // Setup parameters
        bytes32 trustAnchor = 0x7cacb8c6cc65163d30a6c8ce47c0d284490d228d1d1aa7e9ae3f149f77b32b5d;
        uint256 amount = 1e18;
        uint16 numberOfTokens = 100;
        uint64 merchantWithdrawAfterBlocks = uint64(block.number) + 1;
        uint64 payerWithdrawAfterBlocks = uint64(block.number) + 1;

        // Check balances before transaction
        uint256 payerBalanceBefore = payer.balance;
        uint256 contractBalanceBefore = address(muPay).balance;

        // Expect event emission
        vm.expectEmit(true, true, false, true);
        emit MuPay.ChannelCreated(payer, merchant, token, amount, numberOfTokens, merchantWithdrawAfterBlocks);

        // Execute the function call
        vm.prank(payer);
        muPay.createChannel{value: amount}(
            merchant, token, trustAnchor, amount, numberOfTokens, merchantWithdrawAfterBlocks, payerWithdrawAfterBlocks
        );

        // Check balances after transaction
        uint256 payerBalanceAfter = payer.balance;
        uint256 contractBalanceAfter = address(muPay).balance;

        // Verify balance deductions
        assertEq(payerBalanceBefore - payerBalanceAfter, amount, "Incorrect amount deducted from payer");
        assertEq(contractBalanceAfter - contractBalanceBefore, amount, "Incorrect amount added to contract");

        // Verify storage updates
        (address storedToken, bytes32 storedTrustAnchor, uint256 storedAmount, uint256 storedNumberOfToken,,) =
            muPay.channelsMapping(payer, merchant, token);

        assertEq(storedToken, token, "Incorrect token address stored");
        assertEq(storedTrustAnchor, trustAnchor, "Incorrect trust anchor stored");
        assertEq(storedAmount, amount, "Incorrect amount stored");
        assertEq(storedNumberOfToken, numberOfTokens, "Incorrect number of tokens stored");
    }

    function testCreateChannelIncorrectAmount() public {
        // Setup parameters
        bytes32 trustAnchor = 0x7cacb8c6cc65163d30a6c8ce47c0d284490d228d1d1aa7e9ae3f149f77b32b5d;
        uint256 amount = 1e18;
        uint16 numberOfTokens = 100;
        uint64 merchantWithdrawAfterBlocks = 1;
        uint64 payerWithdrawAfterBlocks = 1;

        uint256 incorrectAmount = 1e10;

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(MuPay.IncorrectAmount.selector, incorrectAmount, amount));

        // Execute the function call
        vm.prank(payer);
        muPay.createChannel{value: incorrectAmount}(
            merchant, token, trustAnchor, amount, numberOfTokens, merchantWithdrawAfterBlocks, payerWithdrawAfterBlocks
        );
    }

    function testCreateChannelDuplicateCheck() public {
        // Setup parameters
        bytes32 trustAnchor = 0x7cacb8c6cc65163d30a6c8ce47c0d284490d228d1d1aa7e9ae3f149f77b32b5d;
        uint256 amount = 1e18;
        uint16 numberOfTokens = 100;
        uint64 merchantWithdrawAfterBlocks = 1;
        uint64 payerWithdrawAfterBlocks = 1;

        // Execute the function call
        vm.prank(payer);
        muPay.createChannel{value: amount}(
            merchant, token, trustAnchor, amount, numberOfTokens, merchantWithdrawAfterBlocks, payerWithdrawAfterBlocks
        );

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(MuPay.ChannelAlreadyExist.selector, payer, merchant, token, amount, numberOfTokens)
        );

        // Execute the function call again
        vm.prank(payer);
        muPay.createChannel{value: amount}(
            merchant, token, trustAnchor, amount, numberOfTokens, merchantWithdrawAfterBlocks, payerWithdrawAfterBlocks
        );
    }

    function testCreateChannelZeroToken() public {
        // Setup parameters
        bytes32 trustAnchor = 0x7cacb8c6cc65163d30a6c8ce47c0d284490d228d1d1aa7e9ae3f149f77b32b5d;
        uint256 amount = 1e18;
        // Set number of token as 0
        uint16 numberOfTokens = 0;
        uint64 merchantWithdrawAfterBlocks = 1;
        uint64 payerWithdrawAfterBlocks = 1;

        vm.expectRevert(MuPay.ZeroTokensNotAllowed.selector);

        // Execute the function call
        vm.prank(payer);
        muPay.createChannel{value: amount}(
            merchant, token, trustAnchor, amount, numberOfTokens, merchantWithdrawAfterBlocks, payerWithdrawAfterBlocks
        );
    }

    function testCreateChannelFailsIfPayerWithdrawIsTooSoon() public {
        // Setup parameters
        bytes32 trustAnchor = 0x7cacb8c6cc65163d30a6c8ce47c0d284490d228d1d1aa7e9ae3f149f77b32b5d;
        uint256 amount = 1e18;
        uint16 numberOfTokens = 100;

        // payerWithdrawAfterBlocks should be at least (11 * 10) / 10 = 11
        uint64 merchantWithdrawAfterBlocks = 10;
        uint64 payerWithdrawAfterBlocks = 5; // Invalid: Less than 11 (110% rule)

        vm.expectRevert(MuPay.MerchantWithdrawTimeTooShort.selector);

        // Execute the function call
        vm.prank(payer);
        muPay.createChannel{value: amount}(
            merchant, token, trustAnchor, amount, numberOfTokens, merchantWithdrawAfterBlocks, payerWithdrawAfterBlocks
        );
    }

    function testCreateChannelSucceedsIfPayerWithdrawMeetsGap() public {
        // Setup parameters
        bytes32 trustAnchor = 0x7cacb8c6cc65163d30a6c8ce47c0d284490d228d1d1aa7e9ae3f149f77b32b5d;
        uint256 amount = 1e18;
        uint16 numberOfTokens = 100;
        uint64 merchantWithdrawAfterBlocks = 10;
        uint64 payerWithdrawAfterBlocks = 11; // Meets the 110% rule

        // Check balances before transaction
        uint256 payerBalanceBefore = payer.balance;
        uint256 contractBalanceBefore = address(muPay).balance;

        vm.prank(payer);
        muPay.createChannel{value: amount}(
            merchant, token, trustAnchor, amount, numberOfTokens, merchantWithdrawAfterBlocks, payerWithdrawAfterBlocks
        );

        // Check balances after transaction
        uint256 payerBalanceAfter = payer.balance;
        uint256 contractBalanceAfter = address(muPay).balance;

        // Verify balance deductions
        assertEq(payerBalanceBefore - payerBalanceAfter, amount, "Incorrect amount deducted from payer");
        assertEq(contractBalanceAfter - contractBalanceBefore, amount, "Incorrect amount added to contract");
    }

    function testCreateChannelFailsIfPayerWithdrawJustBelowThreshold() public {
        // Setup parameters
        bytes32 trustAnchor = 0x7cacb8c6cc65163d30a6c8ce47c0d284490d228d1d1aa7e9ae3f149f77b32b5d;
        uint256 amount = 1e18;
        uint16 numberOfTokens = 100;
        uint64 merchantWithdrawAfterBlocks = 10;
        uint64 payerWithdrawAfterBlocks = 10; // Just below the allowed 11

        vm.expectRevert(MuPay.MerchantWithdrawTimeTooShort.selector);
        vm.prank(payer);
        muPay.createChannel{value: amount}(
            merchant, token, trustAnchor, amount, numberOfTokens, merchantWithdrawAfterBlocks, payerWithdrawAfterBlocks
        );
    }

    function testCreateChannelValidWithdrawTimes() public {
        // Setup parameters
        bytes32 trustAnchor = 0x7cacb8c6cc65163d30a6c8ce47c0d284490d228d1d1aa7e9ae3f149f77b32b5d;
        uint256 amount = 1e18;
        uint16 numberOfTokens = 100;

        // Test Case 1: Equal withdraw after blocks
        uint64 merchantWithdrawAfterBlocks1 = uint64(block.number) + 5;
        uint64 payerWithdrawAfterBlocks1 = uint64(block.number) + 5;

        // Test Case 1
        vm.expectEmit(true, true, false, true);
        emit MuPay.ChannelCreated(payer, merchant, token, amount, numberOfTokens, merchantWithdrawAfterBlocks1);

        vm.prank(payer);
        muPay.createChannel{value: amount}(
            merchant,
            token,
            trustAnchor,
            amount,
            numberOfTokens,
            merchantWithdrawAfterBlocks1,
            payerWithdrawAfterBlocks1
        );

        // Verify storage updates for Test Case 1
        (,,,, uint256 storedMerchantWithdrawAfterBlocks1, uint256 storedPayerWithdrawAfterBlocks1) =
            muPay.channelsMapping(payer, merchant, token);

        assertEq(
            storedMerchantWithdrawAfterBlocks1,
            merchantWithdrawAfterBlocks1 + 1,
            "Incorrect merchant withdraw after blocks stored"
        );
        assertEq(
            storedPayerWithdrawAfterBlocks1,
            payerWithdrawAfterBlocks1 + 1,
            "Incorrect payer withdraw after blocks stored"
        );

        address merchant2 = address(0x3);

        // Test Case 2: Merchant withdraw after blocks < payer withdraw after blocks
        uint64 merchantWithdrawAfterBlocks2 = 1;
        uint64 payerWithdrawAfterBlocks2 = 5;

        // Test Case 2
        vm.expectEmit(true, true, false, true);
        emit MuPay.ChannelCreated(payer, merchant2, token, amount, numberOfTokens, merchantWithdrawAfterBlocks2);

        vm.prank(payer);
        muPay.createChannel{value: amount}(
            merchant2,
            token,
            trustAnchor,
            amount,
            numberOfTokens,
            merchantWithdrawAfterBlocks2,
            payerWithdrawAfterBlocks2
        );

        // Verify storage updates for Test Case 2
        (,,,, uint256 storedMerchantWithdrawAfterBlocks2, uint256 storedPayerWithdrawAfterBlocks2) =
            muPay.channelsMapping(payer, merchant2, token);

        assertEq(
            storedMerchantWithdrawAfterBlocks2,
            merchantWithdrawAfterBlocks2 + 1,
            "Incorrect merchant withdraw after blocks stored"
        );
        assertEq(
            storedPayerWithdrawAfterBlocks2,
            payerWithdrawAfterBlocks2 + 1,
            "Incorrect payer withdraw after blocks stored"
        );
    }
}
