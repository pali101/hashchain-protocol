// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {MuPay} from "../src/MuPay.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {BaseTestHelper} from "./helper/BaseTestHelper.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract NotERC20 {}

contract CreateChannelERC20PermitTest is Test, BaseTestHelper {
    MuPay public muPay;
    MockERC20 public token;
    bytes32 public trustAnchor;
    uint16 public numberOfTokens;
    uint64 public merchantWithdrawAfterBlocks;
    uint64 public payerWithdrawAfterBlocks;
    uint256 public deadline;

    function setUp() public {
        muPay = new MuPay();
        token = new MockERC20("Test Token", "TTK");

        // Mint tokens to the payers
        token.mint(PAYER, INITIAL_BALANCE);
        token.mint(PAYER2, INITIAL_BALANCE);

        trustAnchor = 0x7cacb8c6cc65163d30a6c8ce47c0d284490d228d1d1aa7e9ae3f149f77b32b5d;
        numberOfTokens = 100;
        merchantWithdrawAfterBlocks = uint64(block.number) + 1;
        payerWithdrawAfterBlocks = uint64(block.number) + 1;
        deadline = block.timestamp + 1 hours;
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

    function testCreateChannelWithPermit() public {
        // Capture pre-deposit balance
        uint256 preDepositBalancePayer = token.balanceOf(PAYER);
        assertEq(preDepositBalancePayer, INITIAL_BALANCE, "Initial balance should match");

        uint256 predepositBalanceContract = token.balanceOf(address(muPay));
        assertEq(predepositBalanceContract, 0, "Contract should have no tokens before deposit");

        // Get the permit signature for the payer
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(PAYER1PK, PAYER, address(muPay), DEPOSIT_AMOUNT);

        vm.startPrank(PAYER);

        muPay.createChannelWithPermit(
            PAYER,
            PAYEE,
            address(token),
            trustAnchor,
            DEPOSIT_AMOUNT,
            numberOfTokens,
            merchantWithdrawAfterBlocks,
            payerWithdrawAfterBlocks,
            deadline,
            v,
            r,
            s
        );

        vm.stopPrank();

        // Capture post-deposit balance
        _assertDepositBalances(
            preDepositBalancePayer,
            token.balanceOf(PAYER),
            predepositBalanceContract,
            token.balanceOf(address(muPay)),
            DEPOSIT_AMOUNT
        );

        // Verify channel creation
        (
            address storedTokenAddress,
            bytes32 storedTrustAnchor,
            uint256 storedAmount,
            uint16 storedNumberOfTokens,
            uint64 storedMerchantWithdrawAfterBlocks,
            uint64 storedPayerWithdrawAfterBlocks
        ) = muPay.channelsMapping(PAYER, PAYEE, address(token));

        assertEq(storedTokenAddress, address(token), "Incorrect token address stored");
        assertEq(storedTrustAnchor, trustAnchor, "Incorrect trust anchor stored");
        assertEq(storedAmount, DEPOSIT_AMOUNT, "Incorrect amount stored");
        assertEq(storedNumberOfTokens, numberOfTokens, "Incorrect number of tokens stored");
        assertEq(
            storedMerchantWithdrawAfterBlocks,
            merchantWithdrawAfterBlocks + block.number,
            "Incorrect merchant withdraw after blocks"
        );
        assertEq(
            storedPayerWithdrawAfterBlocks,
            payerWithdrawAfterBlocks + block.number,
            "Incorrect payer withdraw after blocks"
        );
    }

    function testCreateChannelWithMultiplePermit() public {
        testCreateChannelWithPermit();
        // Capture pre-deposit balance
        uint256 preDepositBalancePayer = token.balanceOf(PAYER);
        assertEq(preDepositBalancePayer, INITIAL_BALANCE - DEPOSIT_AMOUNT, "Payer's balance should decrease");
        uint256 predepositBalanceContract = token.balanceOf(address(muPay));
        assertEq(predepositBalanceContract, DEPOSIT_AMOUNT, "Contract should have the deposit amount");

        // Get the permit signature for the payer again
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(PAYER1PK, PAYER, address(muPay), DEPOSIT_AMOUNT);
        vm.startPrank(PAYER);
        muPay.createChannelWithPermit(
            PAYER,
            PAYEE2,
            address(token),
            trustAnchor,
            DEPOSIT_AMOUNT,
            numberOfTokens,
            merchantWithdrawAfterBlocks,
            payerWithdrawAfterBlocks,
            deadline,
            v,
            r,
            s
        );
        vm.stopPrank();
        // Capture post-deposit balance
        uint256 postDepositBalancePayer = token.balanceOf(PAYER);
        uint256 postDepositBalanceContract = token.balanceOf(address(muPay));
        _assertDepositBalances(
            preDepositBalancePayer,
            postDepositBalancePayer,
            predepositBalanceContract,
            postDepositBalanceContract,
            DEPOSIT_AMOUNT
        );
    }

    function testCreateChannelWithExpiredPermit() public {
        // Capture pre-deposit balance
        uint256 preDepositBalancePayer = token.balanceOf(PAYER);
        assertEq(preDepositBalancePayer, INITIAL_BALANCE, "Initial balance should match");

        uint256 predepositBalanceContract = token.balanceOf(address(muPay));
        assertEq(predepositBalanceContract, 0, "Contract should have no tokens before deposit");

        // Get the permit signature for the payer
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(PAYER1PK, PAYER, address(muPay), DEPOSIT_AMOUNT);

        // Set the deadline to a past time to simulate an expired permit
        vm.warp(deadline + 10);

        vm.startPrank(PAYER);
        vm.expectRevert(abi.encodeWithSignature("ERC2612ExpiredSignature(uint256)", deadline));
        muPay.createChannelWithPermit(
            PAYER,
            PAYEE,
            address(token),
            trustAnchor,
            DEPOSIT_AMOUNT,
            numberOfTokens,
            merchantWithdrawAfterBlocks,
            payerWithdrawAfterBlocks,
            deadline,
            v,
            r,
            s
        );

        vm.stopPrank();

        // Capture post-deposit balance
        uint256 postDepositBalancePayer = token.balanceOf(PAYER);
        uint256 postDepositBalanceContract = token.balanceOf(address(muPay));
        _assertDepositBalances(
            preDepositBalancePayer, postDepositBalancePayer, predepositBalanceContract, postDepositBalanceContract, 0
        );
    }

    function testCreateChannelWithInvalidPermit() public {
        // Capture pre-deposit balance
        uint256 preDepositBalancePayer = token.balanceOf(PAYER);
        assertEq(preDepositBalancePayer, INITIAL_BALANCE, "Initial balance should match");

        uint256 predepositBalanceContract = token.balanceOf(address(muPay));
        assertEq(predepositBalanceContract, 0, "Contract should have no tokens before deposit");

        // Get the permit signature for the payer
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(PAYER2PK, PAYER, address(muPay), DEPOSIT_AMOUNT);

        vm.startPrank(PAYER);

        vm.expectRevert(abi.encodeWithSignature("ERC2612InvalidSigner(address,address)", PAYER2, PAYER));
        muPay.createChannelWithPermit(
            PAYER,
            PAYEE,
            address(token),
            trustAnchor,
            DEPOSIT_AMOUNT,
            numberOfTokens,
            merchantWithdrawAfterBlocks,
            payerWithdrawAfterBlocks,
            deadline,
            v,
            r,
            s
        );

        vm.stopPrank();

        // Capture post-deposit balance
        uint256 postDepositBalancePayer = token.balanceOf(PAYER);
        uint256 postDepositBalanceContract = token.balanceOf(address(muPay));
        _assertDepositBalances(
            preDepositBalancePayer, postDepositBalancePayer, predepositBalanceContract, postDepositBalanceContract, 0
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
