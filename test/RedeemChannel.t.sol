// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {MuPay} from "../src/MuPay.sol";

contract RedeemChannelTest is Test {
    MuPay public muPay;
    address public payer = address(0x1);
    address public merchant = address(0x2);

    // Setup parameters
    bytes32 trustAnchor = 0x7cacb8c6cc65163d30a6c8ce47c0d284490d228d1d1aa7e9ae3f149f77b32b5d;
    bytes32 finalToken = 0x484f839e58e0b400163856f9b4d2c6254e142d89d8b03f1e33a6717620170f30;
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
        emit MuPay.ChannelCreated(payer, merchant, amount, numberOfTokens, merchantWithdrawAfterBlocks);

        vm.prank(payer);
        muPay.createChannel{value: amount}(
            merchant, trustAnchor, amount, numberOfTokens, merchantWithdrawAfterBlocks, payerWithdrawAfterBlocks
        );
    }

    function testRedeemChannelSuccess() public {
        // Move forward by 10 block
        vm.roll(block.number + 10);

        (, uint256 storedAmount, uint256 storedNumberOfToken,,) = muPay.channelsMapping(payer, merchant);

        uint256 payableAmountMerchant = (storedAmount * numberOfTokensUsed) / storedNumberOfToken;
        uint256 payableAmountPayer = storedAmount - payableAmountMerchant;

        vm.expectEmit(true, true, false, true);
        emit MuPay.ChannelRedeemed(payer, merchant, payableAmountMerchant, finalToken, numberOfTokensUsed);

        vm.expectEmit(true, true, false, true);
        emit MuPay.ChannelRefunded(payer, merchant, payableAmountPayer);

        vm.prank(merchant);
        muPay.redeemChannel(payer, finalToken, numberOfTokensUsed);

        (, uint256 retrievedAmount,,,) = muPay.channelsMapping(payer, merchant);
        assertEq(retrievedAmount, 0, "Channel should be deleted after redeeming");
    }

    function testRedeemBeforeAllowedBlocks() public {
        vm.expectRevert(
            abi.encodeWithSelector(MuPay.MerchantCannotRedeemChannelYet.selector, merchantWithdrawAfterBlocks)
        );

        vm.prank(merchant);
        muPay.redeemChannel(payer, finalToken, numberOfTokensUsed);
    }

    function testRedeemWithIncorrectToken() public {
        bytes32 incorrectFinalToken = 0x484f839e58e0b400163856f9b4d2c6254e142d89d8b03f1e33a6717620170f31;

        vm.roll(block.number + 10);
        vm.expectRevert(MuPay.TokenVerificationFailed.selector);

        vm.prank(merchant);
        muPay.redeemChannel(payer, incorrectFinalToken, numberOfTokensUsed);
    }

    function testRedeemWithTokenCountExceeded() public {
        (,, uint256 storedNumberOfToken,,) = muPay.channelsMapping(payer, merchant);
        uint256 incorrectNumberOfTokensUsed = storedNumberOfToken + 10;
        vm.roll(block.number + 10);
        vm.expectRevert(
            abi.encodeWithSelector(MuPay.TokenCountExceeded.selector, storedNumberOfToken, incorrectNumberOfTokensUsed)
        );

        vm.prank(merchant);
        muPay.redeemChannel(payer, finalToken, incorrectNumberOfTokensUsed);
    }
}
