// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

contract Multisig is ReentrancyGuard {
    using ECDSA for bytes32; // for recover()
    using MessageHashUtils for bytes32; // for toEthSignedMessageHash()
    using SafeERC20 for IERC20;

    /**
     * @dev Represents a payment channel between a payer and a merchant.
     */
    struct Channel {
        address token; // Token address, address(0) for native currency
        uint256 amount; // Total deposit in the payment channel
        uint64 expiration; // Block timestamp after which the channel expires and payer can reclaim amount
        uint64 reclaimAfter; // After this time (or block), payer can reclaim funds
        uint64 sessionId; // Unique identifier for the payment session
        uint256 lastNonce; // Last used nonce to prevent replay attacks and ensure order
    }

    // payer => payee => token => Channel
    mapping(address => mapping(address => mapping(address => Channel))) public channels;

    /**
     * @dev Custom errors to reduce contract size and improve clarity.
     */
    error IncorrectAmount(uint256 sentAmount, uint256 expectedAmount);
    error ChannelDoesNotExistOrWithdrawn();
    error ChannelExpired(uint64 expiration);
    error PayerCannotRedeemChannelYet(uint256 blockNumber, uint256 reclaimAfter);
    error ChannelAlreadyExist(address payer, address payee, address token, uint256 amount);
    error NothingPayable();
    error FailedToSendEther();
    error ZeroTokensNotAllowed();
    error AddressIsNotContract(address token);
    error AddressIsNotERC20(address token);
    error InsufficientAllowance(uint256 required, uint256 actual);
    error StaleNonce(uint256 supplied, uint256 current);
    error InvalidChannelSignature(address recovered, address expected);
    error ReclaimAfterMustBeAfterExpiration(uint64 expiration, uint64 reclaimAfter);
    error DepositWithPermitNotSupportedForNative();

    /**
     * @dev Events to log key contract actions.
     */
    event ChannelCreated(
        address indexed payer,
        address indexed payee,
        address indexed token,
        uint256 amount,
        uint64 expiration,
        uint256 sessionId,
        uint64 reclaimAfter
    );
    event ChannelRedeemed(
        address indexed payer,
        address indexed payee,
        address indexed token,
        uint256 amount,
        uint256 nonce,
        uint256 sessionId
    );
    event ChannelRefunded(address indexed payer, address indexed payee, address indexed token, uint256 refundAmount);
    event ChannelReclaimed(
        address indexed payer, address indexed payee, address indexed token, uint256 reclaimedAmount
    );

    /**
     * @dev Creates a new payment channel between a payer and a payee.
     * @param payee The address receiving payments.
     * @param token The ERC-20 token address used for payments, or address(0) to use the native currency.
     * @param amount The total deposit amount for the channel.
     * @param duration The channel lifetime in blocks (from current block).
     * @param reclaimDelay The time after which the payer can reclaim the funds.
     */
    function createChannel(address payee, address token, uint256 amount, uint64 duration, uint64 reclaimDelay)
        external
        payable
        nonReentrant
    {
        // Validate payee address
        require(payee != address(0), "Invalid address");
        require(
            duration < reclaimDelay,
            ReclaimAfterMustBeAfterExpiration(
                uint64(block.timestamp) + duration, uint64(block.timestamp) + reclaimDelay
            )
        );

        // Dispatch to the correct internal handler based on token type
        if (token == address(0)) {
            _createNativeChannel(payee, amount, duration, reclaimDelay);
        } else {
            _createERC20Channel(payee, token, amount, duration, reclaimDelay);
        }
    }

    /**
     * @dev Creates a new payment channel between a payer and a payee.
     * @param payer The address funding the channel.
     * @param payee The address receiving payments.
     * @param token The ERC-20 token address used for payments, or address(0) to use the native currency.
     * @param duration The channel lifetime in blocks (from current block).
     * @param reclaimDelay The time after which the payer can reclaim the funds.
     * @param amount The total deposit amount for the channel.
     * @param duration The channel lifetime in blocks (from current block).
     * @param v, r, s The EIP-2612 signature parameters.
     */
    function createChannelWithPermit(
        address payer,
        address payee,
        address token,
        uint256 amount,
        uint64 duration,
        uint64 reclaimDelay,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public nonReentrant {
        require(payee != address(0), "Invalid address");
        require(
            duration < reclaimDelay,
            ReclaimAfterMustBeAfterExpiration(
                uint64(block.timestamp) + duration, uint64(block.timestamp) + reclaimDelay
            )
        );
        // Validate the permit signature
        require(token != address(0), DepositWithPermitNotSupportedForNative());

        IERC20Permit(token).permit(payer, address(this), amount, deadline, v, r, s);

        _createERC20Channel(payee, token, amount, duration, reclaimDelay);
    }

    /**
     * @dev Handles channel creation when using native currency (ETH).
     * @param payee The address receiving ETH payments.
     * @param amount The exact ETH amount to lock in the channel.
     * @param duration Lifetime of the channel in blocks.
     */
    function _createNativeChannel(address payee, uint256 amount, uint64 duration, uint64 reclaimDelay) internal {
        // Ensure the ETH sent matches the declared deposit
        if (msg.value != amount) revert IncorrectAmount(msg.value, amount);

        // Initialize and record the channel
        _initChannel(msg.sender, payee, address(0), amount, duration, reclaimDelay);
    }

    /**
     * @dev Handles channel creation when using an ERC-20 token.
     * @param payee The address receiving token payments.
     * @param token The ERC-20 token contract address.
     * @param amount The token amount to lock in the channel.
     * @param duration Lifetime of the channel in blocks.
     */
    function _createERC20Channel(address payee, address token, uint256 amount, uint64 duration, uint64 reclaimDelay)
        internal
    {
        // Ensure no ETH was sent for token-based payments
        if (msg.value != 0) revert IncorrectAmount(msg.value, 0);

        // Validate that the token address is a deployed contract
        if (token.code.length == 0) revert AddressIsNotContract(token);

        // Try calling a common ERC20 function to verify interface compliance
        // Using totalSupply() as a lightweight sanity check for ERC20 compatibility
        try IERC20(token).totalSupply() returns (uint256) {
            // Call succeeded — it's likely an ERC20 token.
        } catch {
            revert AddressIsNotERC20(token);
        }

        // Check that the contract has been approved to spend the specified token amount
        uint256 allowance = IERC20(token).allowance(msg.sender, address(this));
        if (allowance < amount) revert InsufficientAllowance(amount, allowance);

        // Pull tokens from payer into this contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Initialize and record the channel
        _initChannel(msg.sender, payee, token, amount, duration, reclaimDelay);
    }

    /**
     * @dev Initializes the channel record and prevents duplicates.
     * @param payer The address opening the channel.
     * @param payee The address receiving payments.
     * @param token The token used (address(0) for ETH).
     * @param amount The locked deposit amount.
     * @param duration Number of blocks until expiration.
     */
    function _initChannel(
        address payer,
        address payee,
        address token,
        uint256 amount,
        uint64 duration,
        uint64 reclaimDelay
    ) private {
        // Channel initialization
        Channel storage channel = channels[payer][payee][token];

        // Prevent channel overwrite
        if (channel.amount != 0) {
            revert ChannelAlreadyExist(payer, payee, token, channel.amount);
        }

        channel.token = token;
        channel.amount = amount;
        channel.expiration = uint64(block.timestamp) + duration;
        channel.reclaimAfter = uint64(block.timestamp) + reclaimDelay;
        channel.sessionId += 1;
        channel.lastNonce += 1;

        emit ChannelCreated(payer, payee, token, amount, channel.expiration, channel.sessionId, channel.reclaimAfter);
    }

    /**
     * @dev Redeems a payment channel by verifying a final signature.
     * @param payer The address of the payer.
     * @param token The ERC-20 token address used for payments, or address(0) to use the native currency.
     * @param amount The amount the payee is claiming from the channel.
     * @param nonce A strictly increasing number to prevent replay of old vouchers.
     * @param signature The payer’s EIP-191 signature over the channel settlement parameters.
     */
    function redeemChannel(address payer, address token, uint256 amount, uint256 nonce, bytes calldata signature)
        external
        nonReentrant
    {
        // Validate, mark consumed and compute refund
        (uint256 refund, uint64 sessionId) =
            _validateAndConsumeChannel(payer, msg.sender, token, amount, nonce, signature);

        // Dispatch the two transfers via _transfer helper function
        _transfer(msg.sender, token, amount);
        _transfer(payer, token, refund);

        // Emit both events
        emit ChannelRedeemed(payer, msg.sender, token, amount, nonce, sessionId);
        emit ChannelRefunded(payer, msg.sender, token, refund);
    }

    function _validateAndConsumeChannel(
        address payer,
        address payee,
        address token,
        uint256 amount,
        uint256 nonce,
        bytes calldata signature
    ) internal returns (uint256 refund, uint64 sessionId) {
        Channel storage channel = channels[payer][payee][token];
        if (channel.amount == 0) revert ChannelDoesNotExistOrWithdrawn();
        if (block.timestamp > channel.expiration) revert ChannelExpired(channel.expiration);
        if (amount > channel.amount) revert IncorrectAmount(amount, channel.amount);
        if (nonce <= channel.lastNonce) revert StaleNonce(nonce, channel.lastNonce);

        // recreate EIP-191 hash
        bytes32 hash = keccak256(
            abi.encodePacked(address(this), payer, payee, channel.token, amount, nonce, channel.sessionId)
        ).toEthSignedMessageHash();

        // signature check
        address signer = hash.recover(signature);
        if (signer != payer) revert InvalidChannelSignature(signer, payer);

        // compute refund before zeroing out amount
        refund = channel.amount - amount;
        sessionId = channel.sessionId;

        // mark nonce used and clear channel
        channel.lastNonce = nonce;
        channel.amount = 0;
    }

    function _transfer(address recipient, address token, uint256 amount) internal {
        if (token == address(0)) {
            (bool ok,) = payable(recipient).call{value: amount}("");
            if (!ok) revert FailedToSendEther();
        } else {
            IERC20(token).safeTransfer(recipient, amount);
        }
    }

    /**
     * @dev Allows the payer to reclaim their deposit after the reclaim delay expires.
     * @param payee The address of the merchant or recipient.
     * @param token The ERC-20 token address used for payments, or address(0) for native currency.
     */
    function reclaimChannel(address payee, address token) external nonReentrant {
        require(payee != address(0), "Invalid payee address");

        Channel storage channel = channels[msg.sender][payee][token];

        if (channel.amount == 0) {
            revert ChannelDoesNotExistOrWithdrawn();
        }

        if (block.timestamp < channel.reclaimAfter) {
            revert PayerCannotRedeemChannelYet(block.timestamp, channel.reclaimAfter);
        }

        uint256 amountToReclaim = channel.amount;

        // Clean up storage
        delete channels[msg.sender][payee][token];

        // Send funds
        _transfer(msg.sender, token, amountToReclaim);

        emit ChannelReclaimed(msg.sender, payee, token, amountToReclaim);
    }
}
