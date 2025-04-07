// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {MuPay} from "../src/MuPay.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

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
    ERC20Mock token;

    // Setup parameters
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

        token = new ERC20Mock();
        token.mint(payer, 1000 * 1e18);
        vm.prank(payer);
        token.approve(address(muPay), 100 * 1e18);

        // Expect event emission
        vm.expectEmit(true, true, false, true);
        emit MuPay.ChannelCreated(payer, merchant, address(token), amount, numberOfTokens, merchantWithdrawAfterBlocks);

        vm.prank(payer);
        muPay.createChannel(
            merchant,
            address(token),
            trustAnchor,
            amount,
            numberOfTokens,
            merchantWithdrawAfterBlocks,
            payerWithdrawAfterBlocks
        );
    }

    function testRedeemChannelERC20Success() public {
        // Move forward by 11 block
        vm.roll(block.number + 11);

        (,, uint256 storedAmount, uint256 storedNumberOfToken,,) =
            muPay.channelsMapping(payer, merchant, address(token));

        uint256 payableAmountMerchant = (storedAmount * numberOfTokensUsed) / storedNumberOfToken;
        uint256 payableAmountPayer = storedAmount - payableAmountMerchant;

        uint256 payerBalanceBefore = token.balanceOf(payer);
        uint256 contractBalanceBefore = token.balanceOf(address(muPay));
        uint256 merchantBalanceBefore = token.balanceOf(merchant);

        vm.expectEmit(true, true, false, true);
        emit MuPay.ChannelRedeemed(
            payer, merchant, address(token), payableAmountMerchant, finalToken, numberOfTokensUsed
        );

        vm.expectEmit(true, true, false, true);
        emit MuPay.ChannelRefunded(payer, merchant, address(token), payableAmountPayer);

        vm.prank(merchant);
        muPay.redeemChannel(payer, address(token), finalToken, numberOfTokensUsed);

        // Check balances after transaction
        uint256 payerBalanceAfter = token.balanceOf(payer);
        uint256 contractBalanceAfter = token.balanceOf(address(muPay));
        uint256 merchantBalanceAfter = token.balanceOf(merchant);

        // Verify balance deductions
        assertEq(payerBalanceAfter - payerBalanceBefore, payableAmountPayer, "Incorrect amount refunded to payer");
        assertEq(contractBalanceBefore - contractBalanceAfter, amount, "Incorrect amount deducted from contract");
        assertEq(
            merchantBalanceAfter - merchantBalanceBefore, payableAmountMerchant, "Incorrect amount added to merchant"
        );

        (,, uint256 retrievedAmount,,,) = muPay.channelsMapping(payer, merchant, address(token));
        assertEq(retrievedAmount, 0, "Channel should be deleted after redeeming");
    }

    function testRedeemERC20BeforeAllowedBlocks() public {
        vm.expectRevert(
            abi.encodeWithSelector(MuPay.MerchantCannotRedeemChannelYet.selector, merchantWithdrawAfterBlocks + 1)
        );

        vm.prank(merchant);
        muPay.redeemChannel(payer, address(token), finalToken, numberOfTokensUsed);
    }
}
