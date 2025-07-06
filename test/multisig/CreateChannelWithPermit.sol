// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {Multisig} from "../../src/Multisig_2of2.sol";
import {BaseTestHelper} from "../helper/BaseTestHelper.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract CreateChannelERC20PermitTest is Test, BaseTestHelper {
    Multisig public multisig;
    MockERC20 public token;
    uint256 deadline;

    function setUp() public {
        multisig = new Multisig();
        token = new MockERC20("Test Token", "TTK");
        deadline = block.timestamp + 1 hours;

        // Mint tokens to the payers
        token.mint(PAYER, INITIAL_BALANCE);
        token.mint(PAYER2, INITIAL_BALANCE);
    }

    function getPermitSignature(uint256 privateKey, address owner, address spender, uint256 value)
        public
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        uint256 nonce = MockERC20(address(token)).nonces(owner);
        bytes32 DOMAIN_SEPARATOR = MockERC20(address(token)).DOMAIN_SEPARATOR();

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                spender,
                value,
                nonce,
                deadline
            )
        );

        bytes32 digest = MessageHashUtils.toTypedDataHash(DOMAIN_SEPARATOR, structHash);

        // Sign the exact digest that `permit` expects using the provided private key
        (v, r, s) = vm.sign(privateKey, digest);
    }

    function testMultisigCreateChannelWithERC20Permit() public {
        // Capture pre-deposit balance
        uint256 preDepositBalancePayer = token.balanceOf(PAYER);
        assertEq(preDepositBalancePayer, INITIAL_BALANCE, "Initial balance should match");

        uint256 predepositBalanceContract = token.balanceOf(address(multisig));
        assertEq(predepositBalanceContract, 0, "Contract should have no tokens before deposit");

        // Get the permit signature for the payer
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(PAYER1PK, PAYER, address(multisig), DEPOSIT_AMOUNT);

        vm.startPrank(PAYER);
        // Create the channel with permit
        multisig.createChannelWithPermit(
            PAYER, PAYEE, address(token), DEPOSIT_AMOUNT, DURATION, RECLAIM_DELAY, deadline, v, r, s
        );

        // Capture post-deposit balance
        _assertDepositBalances(
            preDepositBalancePayer,
            token.balanceOf(PAYER),
            predepositBalanceContract,
            token.balanceOf(address(multisig)),
            DEPOSIT_AMOUNT
        );
        (address storedToken, uint256 storedAmount, uint64 storedDuration, uint64 storedReclaimDelay,,) =
            multisig.channels(PAYER, PAYEE, address(token));

        assertEq(storedToken, address(token), "Stored token address should match");
        assertEq(storedAmount, DEPOSIT_AMOUNT, "Stored amount should match the deposit amount");
        assertEq(storedDuration, DURATION + block.timestamp, "Stored duration should match the specified duration");
        assertEq(storedReclaimDelay, RECLAIM_DELAY + block.timestamp, "Stored reclaim delay should match the specified reclaim delay");
    }

    function testMultisigCreateChannelWithExpiredPermit() public {
        // Capture pre-deposit balance
        uint256 preDepositBalancePayer = token.balanceOf(PAYER);
        assertEq(preDepositBalancePayer, INITIAL_BALANCE, "Initial balance should match");

        uint256 predepositBalanceContract = token.balanceOf(address(multisig));
        assertEq(predepositBalanceContract, 0, "Contract should have no tokens before deposit");

        // Get the permit signature for the payer
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(PAYER1PK, PAYER, address(multisig), DEPOSIT_AMOUNT);

        // Warp to a time after the deadline
        vm.warp(deadline + 10);

        vm.startPrank(PAYER);
        vm.expectRevert(abi.encodeWithSignature("ERC2612ExpiredSignature(uint256)", deadline));
        multisig.createChannelWithPermit(
            PAYER, PAYEE, address(token), DEPOSIT_AMOUNT, DURATION, RECLAIM_DELAY, deadline, v, r, s
        );
        vm.stopPrank();
        // Capture post-deposit balance
        uint256 postDepositBalancePayer = token.balanceOf(PAYER);
        uint256 postDepositBalanceContract = token.balanceOf(address(multisig));
        _assertDepositBalances(
            preDepositBalancePayer,
            postDepositBalancePayer,
            predepositBalanceContract,
            postDepositBalanceContract,
            0 // No deposit should have occurred
        );
    }

    function testMultisigCreateChannelWithInvalidPermit() public {
        // Capture pre-deposit balance
        uint256 preDepositBalancePayer = token.balanceOf(PAYER);
        assertEq(preDepositBalancePayer, INITIAL_BALANCE, "Initial balance should match");

        uint256 predepositBalanceContract = token.balanceOf(address(multisig));
        assertEq(predepositBalanceContract, 0, "Contract should have no tokens before deposit");

        // Get the permit signature for the payer
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(PAYER2PK, PAYER, address(multisig), DEPOSIT_AMOUNT);

        vm.startPrank(PAYER);
        vm.expectRevert(abi.encodeWithSignature("ERC2612InvalidSigner(address,address)", PAYER2, PAYER));
        multisig.createChannelWithPermit(
            PAYER, PAYEE, address(token), DEPOSIT_AMOUNT, DURATION, RECLAIM_DELAY, deadline, v, r, s
        );
        vm.stopPrank();

        // Capture post-deposit balance
        uint256 postDepositBalancePayer = token.balanceOf(PAYER);
        uint256 postDepositBalanceContract = token.balanceOf(address(multisig));
        _assertDepositBalances(
            preDepositBalancePayer,
            postDepositBalancePayer,
            predepositBalanceContract,
            postDepositBalanceContract,
            0 // No deposit should have occurred
        );
    }

    function _assertDepositBalances(
        uint256 preDepositBalancePayer,
        uint256 postDepositBalancePayer,
        uint256 preDepositBalanceContract,
        uint256 postDepositBalanceContract,
        uint256 depositAmount
    ) internal pure {
        assertEq(
            postDepositBalancePayer,
            preDepositBalancePayer - depositAmount,
            "Payer's balance should decrease by the deposit amount"
        );
        assertEq(
            postDepositBalanceContract,
            preDepositBalanceContract + depositAmount,
            "Contract should have received the deposit amount"
        );
    }
}
