// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {MuPay} from "../src/MuPay.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract CreateChannelERC20Test is Test {
    MuPay public muPay;
    address public payer = address(0x1);
    address public merchant = address(0x2);
    ERC20Mock token;

    function setUp() external {
        muPay = new MuPay();
        token = new ERC20Mock();

        token.mint(payer, 1000 * 1e18);
        vm.deal(payer, 1 ether);

        vm.prank(payer);
        token.approve(address(muPay), 100 * 1e18);
    }

    function testCreateChannelERC20() public {
        // Setup parameters
        bytes32 trustAnchor = 0x7cacb8c6cc65163d30a6c8ce47c0d284490d228d1d1aa7e9ae3f149f77b32b5d;
        uint256 amount = 1e18;
        uint16 numberOfTokens = 100;
        uint64 merchantWithdrawAfterBlocks = uint64(block.number) + 1;
        uint64 payerWithdrawAfterBlocks = uint64(block.number) + 1;

        // Check balances before transaction
        uint256 payerBalanceBefore = token.balanceOf(payer);
        uint256 contractBalanceBefore = token.balanceOf(address(muPay));

        // Expect event emission
        vm.expectEmit(true, true, false, true);
        emit MuPay.ChannelCreated(payer, merchant, address(token), amount, numberOfTokens, merchantWithdrawAfterBlocks);

        // Execute the function call
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

        // Check balances after transaction
        uint256 payerBalanceAfter = token.balanceOf(payer);
        uint256 contractBalanceAfter = token.balanceOf(address(muPay));

        // Verify balance deductions
        assertEq(payerBalanceBefore - payerBalanceAfter, amount, "Incorrect amount deducted from payer");
        assertEq(contractBalanceAfter - contractBalanceBefore, amount, "Incorrect amount added to contract");

        // Verify storage updates
        (address storedToken, bytes32 storedTrustAnchor, uint256 storedAmount, uint256 storedNumberOfToken,,) =
            muPay.channelsMapping(payer, merchant, address(token));

        assertEq(storedToken, address(token), "Incorrect token address stored");
        assertEq(storedTrustAnchor, trustAnchor, "Incorrect trust anchor stored");
        assertEq(storedAmount, amount, "Incorrect amount stored");
        assertEq(storedNumberOfToken, numberOfTokens, "Incorrect number of tokens stored");
    }

    function testCreateChannelERC20IncorrectAmount() public {
        // Setup parameters
        bytes32 trustAnchor = 0x7cacb8c6cc65163d30a6c8ce47c0d284490d228d1d1aa7e9ae3f149f77b32b5d;
        uint256 amount = 1e18;
        uint16 numberOfTokens = 100;
        uint64 merchantWithdrawAfterBlocks = 1;
        uint64 payerWithdrawAfterBlocks = 1;

        uint256 incorrectAmount = 1e10;

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(MuPay.IncorrectAmount.selector, incorrectAmount, 0));

        // Execute the function call
        vm.prank(payer);
        muPay.createChannel{value: incorrectAmount}(
            merchant,
            address(token),
            trustAnchor,
            amount,
            numberOfTokens,
            merchantWithdrawAfterBlocks,
            payerWithdrawAfterBlocks
        );
    }

    function testCreateChannelERC20DuplicateCheck() public {
        // Setup parameters
        bytes32 trustAnchor = 0x7cacb8c6cc65163d30a6c8ce47c0d284490d228d1d1aa7e9ae3f149f77b32b5d;
        uint256 amount = 1e18;
        uint16 numberOfTokens = 100;
        uint64 merchantWithdrawAfterBlocks = 1;
        uint64 payerWithdrawAfterBlocks = 1;

        // Execute the function call
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

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                MuPay.ChannelAlreadyExist.selector, payer, merchant, address(token), amount, numberOfTokens
            )
        );

        // Execute the function call again
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

    function testCreateChannelERC20ZeroToken() public {
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
}
