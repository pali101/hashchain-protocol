// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {MuPay} from "../src/MuPay.sol";

contract ReclaimChannelTest is Test {
    MuPay public muPay;
    address public payer = address(0x1);
    address public merchant = address(0x2);

    // Setup parameters
    bytes32 trustAnchor =
        0x7cacb8c6cc65163d30a6c8ce47c0d284490d228d1d1aa7e9ae3f149f77b32b5d;
    uint256 amount = 1e18;
    uint256 numberOfTokens = 100;
    uint256 merchantWithdrawAfterBlocks = 10;
    uint256 payerWithdrawAfterBlocks = 100;
    uint256 numberOfTokensUsed = 50;

    function setUp() external {
        muPay = new MuPay();
        vm.deal(payer, 10 ether);

        // Expect event emission
        vm.expectEmit(true, true, false, true);
        emit MuPay.ChannelCreated(
            payer,
            merchant,
            amount,
            numberOfTokens,
            merchantWithdrawAfterBlocks
        );

        vm.prank(payer);
        muPay.createChannel{value: amount}(
            merchant,
            trustAnchor,
            amount,
            numberOfTokens,
            merchantWithdrawAfterBlocks,
            payerWithdrawAfterBlocks
        );
    }

    function testReclaimChannelSuccess() public {
        vm.roll(block.number + 100);

        uint256 payerBalanceBefore = payer.balance;

        vm.expectEmit(true, true, false, true);
        emit MuPay.ChannelReclaimed(payer, merchant, block.number);

        vm.prank(payer);
        muPay.reclaimChannel(merchant);

        uint256 payerBalanceAfter = payer.balance;

        assertEq(
            payerBalanceAfter - payerBalanceBefore,
            amount,
            "Incorrect amount sent to payer"
        );
    }
}
