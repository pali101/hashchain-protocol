// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MuPay - A Simple Payment Channel
 * @dev This contract enables a payment channel between a payer and a merchant
 * using a hashchain-based verification mechanism to track payments.
 */
contract MuPay is ReentrancyGuard {
    using SafeERC20 for IERC20;
    /**
     * @dev Represents a payment channel between a payer and a merchant.
     */

    struct Channel {
        address token; // Token address, address(0) for native currency
        bytes32 trustAnchor; // The initial hash value of the hashchain.
        uint256 amount; // Total deposit in the payment channel.
        uint16 numberOfTokens; // Number of tokens in the hashchain.
        uint64 merchantWithdrawAfterBlocks; // Block number after which the merchant can withdraw.
        uint64 payerWithdrawAfterBlocks; // Block number after which the payer can reclaim funds.
    }

    // Updated mapping to include token dimension
    // user -> merchant -> token -> channel
    mapping(address => mapping(address => mapping(address => Channel))) public channelsMapping;

    /**
     * @dev Custom errors to reduce contract size and improve clarity.
     */
    error IncorrectAmount(uint256 sent, uint256 expected);
    error MerchantCannotRedeemChannelYet(uint64 blockNumber);
    error ChannelDoesNotExistOrWithdrawn();
    error TokenVerificationFailed();
    error NothingPayable();
    error FailedToSendEther();
    error PayerCannotRedeemChannelYet(uint64 blockNumber);
    error ChannelAlreadyExist(address payer, address merchant, address token, uint256 amount, uint16 numberOfTokens);
    error ZeroTokensNotAllowed();
    error MerchantWithdrawTimeTooShort();
    error TokenCountExceeded(uint256 totalAvailable, uint256 used);
    error InsufficientAllowance(uint256 required, uint256 actual);
    error AddressIsNotContract(address token);
    error AddressIsNotERC20(address token);

    /**
     * @dev Events to log key contract actions.
     */
    event ChannelCreated(
        address indexed payer,
        address indexed merchant,
        address token,
        uint256 amount,
        uint16 numberOfTokens,
        uint64 merchantWithdrawAfterBlocks
    );
    event ChannelRedeemed(
        address indexed payer,
        address indexed merchant,
        address token,
        uint256 amountPaid,
        bytes32 finalHashValue,
        uint16 numberOfTokensUsed
    );
    event ChannelRefunded(address indexed payer, address indexed merchant, address token, uint256 refundAmount);
    event ChannelReclaimed(address indexed payer, address indexed merchant, address token, uint64 blockNumber);

    /**
     * @dev Verifies if the final hash value is valid given a trust anchor and the number of tokens used.
     * This ensures that payments were made according to the hashchain mechanism.
     * @param trustAnchor The initial hash value stored in the channel.
     * @param finalHashValue The hash value submitted for verification.
     * @param numberOfTokensUsed The number of tokens used in the hashchain.
     * @return True if the final hash value is valid, otherwise false.
     */
    function verifyHashchain(bytes32 trustAnchor, bytes32 finalHashValue, uint16 numberOfTokensUsed)
        public
        pure
        returns (bool)
    {
        for (uint256 i = 0; i < numberOfTokensUsed; i++) {
            finalHashValue = keccak256(abi.encode(finalHashValue));
        }
        return finalHashValue == trustAnchor;
    }

    /**
     * @dev Creates a new payment channel between a payer and a merchant.
     * @param merchant The merchant receiving payments.
     * @param token The ERC-20 token address used for payments, or address(0) to use the native currency.
     * @param trustAnchor The final hash value of the hashchain.
     * @param amount The total deposit amount for the channel.
     * @param numberOfTokens The number of tokens in the hashchain.
     * @param merchantWithdrawAfterBlocks The block number after which the merchant can withdraw.
     * @param payerWithdrawAfterBlocks The block number after which the payer can reclaim unused funds.
     */
    function createChannel(
        address merchant,
        address token,
        bytes32 trustAnchor,
        uint256 amount,
        uint16 numberOfTokens,
        uint64 merchantWithdrawAfterBlocks,
        uint64 payerWithdrawAfterBlocks
    ) public payable {
        // Validate merchant address
        require(merchant != address(0), "Invalid address");

        // Channel must contain at least one token in the hashchain
        if (numberOfTokens == 0) {
            revert ZeroTokensNotAllowed();
        }

        // Merchant should get sufficient time to withdraw before payer is allowed to withdraw.
        if ((11 * merchantWithdrawAfterBlocks) / 10 > payerWithdrawAfterBlocks) {
            revert MerchantWithdrawTimeTooShort();
        }

        // --- Native Currency Handling ---
        if (token == address(0)) {
            // Ensure the sent ETH matches the expected deposit amount
            if (msg.value != amount) {
                revert IncorrectAmount(msg.value, amount);
            }
        } else {
            // --- ERC-20 Token Handling ---

            // Ensure no ETH was sent for token-based payments
            if (msg.value != 0) {
                revert IncorrectAmount(msg.value, 0);
            }

            // Validate that the token address is a deployed contract
            if (token.code.length == 0) {
                revert AddressIsNotContract(token);
            }

            // Try calling a common ERC20 function to verify interface compliance
            // Using totalSupply() as a lightweight sanity check for ERC20 compatibility
            try IERC20(token).totalSupply() returns (uint256) {
                // Call succeeded — it's likely an ERC20 token.
            } catch {
                revert AddressIsNotERC20(token);
            }

            // Check that the contract has been approved to spend the specified token amount
            uint256 allowance = IERC20(token).allowance(msg.sender, address(this));
            if (allowance < amount) {
                revert InsufficientAllowance(amount, allowance);
            }

            // Transfer tokens from the payer to this contract
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        // --- Prevent Duplicate Channel Creation ---
        if (channelsMapping[msg.sender][merchant][token].amount != 0) {
            revert ChannelAlreadyExist(
                msg.sender,
                merchant,
                token,
                channelsMapping[msg.sender][merchant][token].amount,
                channelsMapping[msg.sender][merchant][token].numberOfTokens
            );
        }

        // --- Channel Initialization ---
        channelsMapping[msg.sender][merchant][token] = Channel({
            token: token,
            trustAnchor: trustAnchor,
            amount: amount,
            numberOfTokens: numberOfTokens,
            merchantWithdrawAfterBlocks: uint64(block.number) + merchantWithdrawAfterBlocks,
            payerWithdrawAfterBlocks: uint64(block.number) + payerWithdrawAfterBlocks
        });

        // Emit an event to notify the channel has been created
        emit ChannelCreated(msg.sender, merchant, token, amount, numberOfTokens, merchantWithdrawAfterBlocks);
    }

    /**
     * @dev Redeems a payment channel by verifying a final hash value.
     * @param payer The address of the payer.
     * @param token The ERC-20 token address used for payments, or address(0) to use the native currency.
     * @param finalHashValue The final hash value after consuming tokens.
     * @param numberOfTokensUsed The number of tokens used.
     */
    function redeemChannel(address payer, address token, bytes32 finalHashValue, uint16 numberOfTokensUsed)
        public
        nonReentrant
    {
        require(payer != address(0), "Invalid address");
        Channel storage channel = channelsMapping[payer][msg.sender][token];
        if (channel.amount == 0) {
            revert ChannelDoesNotExistOrWithdrawn();
        }
        if (channel.merchantWithdrawAfterBlocks > block.number) {
            revert MerchantCannotRedeemChannelYet(channel.merchantWithdrawAfterBlocks);
        }

        // require(numberOfTokensUsed <= channel.numberOfTokens, "Token count exceeded");
        if (numberOfTokensUsed > channel.numberOfTokens) {
            revert TokenCountExceeded(channel.numberOfTokens, numberOfTokensUsed);
        }

        if (!verifyHashchain(channel.trustAnchor, finalHashValue, numberOfTokensUsed)) {
            revert TokenVerificationFailed();
        }
        uint256 payableAmountMerchant = (channel.amount * numberOfTokensUsed) / channel.numberOfTokens;

        uint256 payableAmountPayer = channel.amount - payableAmountMerchant;
        if (payableAmountMerchant == 0) {
            revert NothingPayable();
        }
        delete channelsMapping[payer][msg.sender][token];

        if (token == address(0)) {
            (bool sentMerchant,) = payable(msg.sender).call{value: payableAmountMerchant}("");
            (bool sentPayer,) = payable(payer).call{value: payableAmountPayer}("");
            if (!sentMerchant || !sentPayer) {
                revert FailedToSendEther();
            }
        } else {
            // ERC-20 token transfer
            IERC20(token).safeTransfer(msg.sender, payableAmountMerchant);
            IERC20(token).safeTransfer(payer, payableAmountPayer);
        }

        emit ChannelRedeemed(payer, msg.sender, token, payableAmountMerchant, finalHashValue, numberOfTokensUsed);

        emit ChannelRefunded(payer, msg.sender, token, payableAmountPayer);
    }

    /**
     * @dev Allows the payer to reclaim their deposit after the withdrawal period expires.
     * @param merchant The address of the merchant.
     * @param token The ERC-20 token address used for payments, or address(0) to use the native currency.
     */
    function reclaimChannel(address merchant, address token) public nonReentrant {
        require(merchant != address(0), "Invalid address");
        Channel storage channel = channelsMapping[msg.sender][merchant][token];
        if (channel.amount == 0) {
            revert ChannelDoesNotExistOrWithdrawn();
        }
        if (channel.payerWithdrawAfterBlocks < block.number) {
            uint256 amountToReclaim = channel.amount;
            delete channelsMapping[msg.sender][merchant][token];

            if (token == address(0)) {
                (bool sent,) = payable(msg.sender).call{value: amountToReclaim}("");
                if (!sent) {
                    revert FailedToSendEther();
                }
            } else {
                IERC20(token).safeTransfer(msg.sender, amountToReclaim);
            }

            emit ChannelReclaimed(msg.sender, merchant, token, uint64(block.number));
        } else {
            revert PayerCannotRedeemChannelYet(channel.payerWithdrawAfterBlocks);
        }
    }

    /**
     * @dev Prevents accidental ETH deposits by reverting any direct ETH transfers.
     */
    receive() external payable {
        revert("MuPay: Direct ETH deposits are not allowed");
    }

    /**
     * @dev Fallback function to prevent unintended function calls or ether transfers.
     */
    fallback() external payable {
        revert("MuPay: Invalid function call or ETH transfer");
    }
}
