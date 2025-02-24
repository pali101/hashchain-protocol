// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {MuPay} from "../src/MuPay.sol";

contract CreateChannelTest is Test {
    MuPay public muPay;
    address public payer = address(0x1);
    address public merchant = address(0x2);

    function setUp() external {
        muPay = new MuPay();
        vm.deal(payer, 10 ether);
    }

    function testCreateChannelSuccess() public {
        // Setup parameters
        bytes32 trustAnchor = 0x7cacb8c6cc65163d30a6c8ce47c0d284490d228d1d1aa7e9ae3f149f77b32b5d;
        uint256 amount = 1e18;
        uint256 numberOfTokens = 100;
        uint256 merchantWithdrawAfterBlocks = 1;
        uint256 payerWithdrawAfterBlocks = 1;

        // Check balances before transaction
        uint256 payerBalanceBefore = payer.balance;
        uint256 contractBalanceBefore = address(muPay).balance;

        // Expect event emission
        vm.expectEmit(true, true, false, true);
        emit MuPay.ChannelCreated(payer, merchant, amount, numberOfTokens, merchantWithdrawAfterBlocks);

        // Execute the function call
        vm.prank(payer);
        muPay.createChannel{value: amount}(
            merchant, trustAnchor, amount, numberOfTokens, merchantWithdrawAfterBlocks, payerWithdrawAfterBlocks
        );

        // Check balances after transaction
        uint256 payerBalanceAfter = payer.balance;
        uint256 contractBalanceAfter = address(muPay).balance;

        // Verify balance deductions
        assertEq(payerBalanceBefore - payerBalanceAfter, amount, "Incorrect amount deducted from payer");
        assertEq(contractBalanceAfter - contractBalanceBefore, amount, "Incorrect amount added to contract");

        // Verify storage updates
        (
            bytes32 storedTrustAnchor,
            uint256 storedAmount,
            uint256 storedToken,
            uint256 storedMerchantWithdrawAfterBlocks,
            uint256 storedPayerWithdrawAfterBlocks
        ) = muPay.channelsMapping(payer, merchant);

        assertEq(storedTrustAnchor, trustAnchor, "Incorrect trust anchor stored");
        assertEq(storedAmount, amount, "Incorrect amount stored");
        assertEq(storedToken, numberOfTokens, "Incorrect number of tokens stored");
        assertEq(
            storedMerchantWithdrawAfterBlocks,
            merchantWithdrawAfterBlocks,
            "Incorrect merchant withdraw after blocks stored"
        );
        assertEq(
            storedPayerWithdrawAfterBlocks, payerWithdrawAfterBlocks, "Incorrect payer withdraw after blocks stored"
        );
    }

    function testCreateChannelIncorrectAmount() public {
        // Setup parameters
        bytes32 trustAnchor = 0x7cacb8c6cc65163d30a6c8ce47c0d284490d228d1d1aa7e9ae3f149f77b32b5d;
        uint256 amount = 1e18;
        uint256 numberOfTokens = 100;
        uint256 merchantWithdrawAfterBlocks = 1;
        uint256 payerWithdrawAfterBlocks = 1;

        uint256 incorrectAmount = 1e10;

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(MuPay.IncorrectAmount.selector, incorrectAmount, amount));

        // Execute the function call
        vm.prank(payer);
        muPay.createChannel{value: incorrectAmount}(
            merchant, trustAnchor, amount, numberOfTokens, merchantWithdrawAfterBlocks, payerWithdrawAfterBlocks
        );
    }

    function testCreateChannelDuplicateCheck() public {
        // Setup parameters
        bytes32 trustAnchor = 0x7cacb8c6cc65163d30a6c8ce47c0d284490d228d1d1aa7e9ae3f149f77b32b5d;
        uint256 amount = 1e18;
        uint256 numberOfTokens = 100;
        uint256 merchantWithdrawAfterBlocks = 1;
        uint256 payerWithdrawAfterBlocks = 1;

        // Execute the function call
        vm.prank(payer);
        muPay.createChannel{value: amount}(
            merchant, trustAnchor, amount, numberOfTokens, merchantWithdrawAfterBlocks, payerWithdrawAfterBlocks
        );

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(MuPay.ChannelAlreadyExist.selector, payer, merchant, amount, numberOfTokens)
        );

        // Execute the function call again
        vm.prank(payer);
        muPay.createChannel{value: amount}(
            merchant, trustAnchor, amount, numberOfTokens, merchantWithdrawAfterBlocks, payerWithdrawAfterBlocks
        );
    }

    function testCreateChannelZeroToken() public {
        // Setup parameters
        bytes32 trustAnchor = 0x7cacb8c6cc65163d30a6c8ce47c0d284490d228d1d1aa7e9ae3f149f77b32b5d;
        uint256 amount = 1e18;
        // Set number of token as 0
        uint256 numberOfTokens = 0;
        uint256 merchantWithdrawAfterBlocks = 1;
        uint256 payerWithdrawAfterBlocks = 1;

        vm.expectRevert(MuPay.ZeroTokensNotAllowed.selector);

        // Execute the function call
        vm.prank(payer);
        muPay.createChannel{value: amount}(
            merchant, trustAnchor, amount, numberOfTokens, merchantWithdrawAfterBlocks, payerWithdrawAfterBlocks
        );
    }

    function testCreateChannelFailsIfMerchantWithdrawAfterBlocksExceedsPayerWithdraw() public {
        // Setup parameters
        bytes32 trustAnchor = 0x7cacb8c6cc65163d30a6c8ce47c0d284490d228d1d1aa7e9ae3f149f77b32b5d;
        uint256 amount = 1e18;
        uint256 numberOfTokens = 100;
        // merchant withdraw after block > payer withdraw after block
        uint256 merchantWithdrawAfterBlocks = 10;
        uint256 payerWithdrawAfterBlocks = 5;

        vm.expectRevert(MuPay.MerchantWithdrawTimeTooShort.selector);

        // Execute the function call
        vm.prank(payer);
        muPay.createChannel{value: amount}(
            merchant, trustAnchor, amount, numberOfTokens, merchantWithdrawAfterBlocks, payerWithdrawAfterBlocks
        );
    }

    function testCreateChannelValidWithdrawTimes() public {
        // Setup parameters
        bytes32 trustAnchor = 0x7cacb8c6cc65163d30a6c8ce47c0d284490d228d1d1aa7e9ae3f149f77b32b5d;
        uint256 amount = 1e18;
        uint256 numberOfTokens = 100;

        // Test Case 1: Equal withdraw after blocks
        uint256 merchantWithdrawAfterBlocks1 = 5;
        uint256 payerWithdrawAfterBlocks1 = 5;

        // Test Case 1
        vm.expectEmit(true, true, false, true);
        emit MuPay.ChannelCreated(payer, merchant, amount, numberOfTokens, merchantWithdrawAfterBlocks1);

        vm.prank(payer);
        muPay.createChannel{value: amount}(
            merchant, trustAnchor, amount, numberOfTokens, merchantWithdrawAfterBlocks1, payerWithdrawAfterBlocks1
        );

        // Verify storage updates for Test Case 1
        (,,, uint256 storedMerchantWithdrawAfterBlocks1, uint256 storedPayerWithdrawAfterBlocks1) =
            muPay.channelsMapping(payer, merchant);

        assertEq(
            storedMerchantWithdrawAfterBlocks1,
            merchantWithdrawAfterBlocks1,
            "Test Case 1: Incorrect merchant withdraw after blocks stored"
        );
        assertEq(
            storedPayerWithdrawAfterBlocks1,
            payerWithdrawAfterBlocks1,
            "Test Case 1: Incorrect payer withdraw after blocks stored"
        );

        address merchant2 = address(0x3);

        // Test Case 2: Merchant withdraw after blocks < payer withdraw after blocks
        uint256 merchantWithdrawAfterBlocks2 = 1;
        uint256 payerWithdrawAfterBlocks2 = 5;

        // Test Case 2
        vm.expectEmit(true, true, false, true);
        emit MuPay.ChannelCreated(payer, merchant2, amount, numberOfTokens, merchantWithdrawAfterBlocks2);

        vm.prank(payer);
        muPay.createChannel{value: amount}(
            merchant2, trustAnchor, amount, numberOfTokens, merchantWithdrawAfterBlocks2, payerWithdrawAfterBlocks2
        );

        // Verify storage updates for Test Case 2
        (,,, uint256 storedMerchantWithdrawAfterBlocks2, uint256 storedPayerWithdrawAfterBlocks2) =
            muPay.channelsMapping(payer, merchant2);

        assertEq(
            storedMerchantWithdrawAfterBlocks2,
            merchantWithdrawAfterBlocks2,
            "Test Case 2: Incorrect merchant withdraw after blocks stored"
        );
        assertEq(
            storedPayerWithdrawAfterBlocks2,
            payerWithdrawAfterBlocks2,
            "Test Case 2: Incorrect payer withdraw after blocks stored"
        );
    }
}
