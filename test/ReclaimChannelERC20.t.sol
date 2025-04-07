// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {MuPay} from "../src/MuPay.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract ReclaimChannelTest is Test {
    MuPay public muPay;
    address public payer = address(0x1);
    address public merchant = address(0x2);

    // Setup parameters
    ERC20Mock token;
    bytes32 trustAnchor = 0x7cacb8c6cc65163d30a6c8ce47c0d284490d228d1d1aa7e9ae3f149f77b32b5d;
    uint256 amount = 1e18;
    uint16 numberOfTokens = 100;
    uint64 merchantWithdrawAfterBlocks = 10;
    uint64 payerWithdrawAfterBlocks = 100;

    function setUp() external {
        muPay = new MuPay();
        token = new ERC20Mock();
        vm.deal(payer, 10 ether);

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

    function testReclaimChannelERC20Success() public {
        vm.roll(block.number + 101);

        uint256 payerBalanceBefore = token.balanceOf(payer);

        vm.expectEmit(true, true, false, true);
        emit MuPay.ChannelReclaimed(payer, merchant, address(token), uint64(block.number));

        vm.prank(payer);
        muPay.reclaimChannel(merchant, address(token));

        uint256 payerBalanceAfter = token.balanceOf(payer);

        assertEq(payerBalanceAfter - payerBalanceBefore, amount, "Incorrect amount sent to payer");
    }

    function testReclaimERC20BeforeAllowed() public {
        (,,,,, uint256 storedPayerWithdrawAfterBlocks) = muPay.channelsMapping(payer, merchant, address(token));

        vm.expectRevert(
            abi.encodeWithSelector(MuPay.PayerCannotRedeemChannelYet.selector, storedPayerWithdrawAfterBlocks)
        );
        vm.prank(payer);
        muPay.reclaimChannel(merchant, address(token));
    }

    function testReclaimERC20NotExistantChannel() public {
        address merchant2 = address(0x3);

        vm.expectRevert(MuPay.ChannelDoesNotExistOrWithdrawn.selector);

        vm.prank(payer);
        muPay.reclaimChannel(merchant2, address(token));
    }
}
