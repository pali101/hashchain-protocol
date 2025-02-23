// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

contract MuPay {
    struct Channel {
        bytes32 trustAnchor;
        uint256 amount;
        uint256 numberOfTokens;
        uint256 merchantWithdrawAfterBlocks;
        uint256 payerWithdrawAfterBlocks;
    }

    // user -> merchant -> channel
    mapping(address => mapping(address => Channel)) public channelsMapping;

    error IncorrectAmount(uint256 sent, uint256 expected);
    error MerchantCannotRedeemChannelYet(uint256 blockNumber);
    error ChannelDoesNotExistOrWithdrawn();
    error TokenVerificationFailed();
    error NothingPayable();
    error FailedToSendEther();
    error PayerCannotRedeemChannelYet(uint256 blockNumber);
    error ChannelAlreadyExist(
        address payer,
        address merchant,
        uint256 amount,
        uint256 numberOfTokens
    );
    error ZeroTokensNotAllowed();

    event ChannelCreated(
        address indexed payer,
        address indexed merchant,
        uint256 amount,
        uint256 numberOfTokens,
        uint256 merchantWithdrawAfterBlocks
    );
    event ChannelRedeemed(
        address indexed payer,
        address indexed merchant,
        uint256 amountPaid,
        bytes32 finalHashValue,
        uint256 numberOfTokensUsed
    );
    event ChannelReclaimed(
        address indexed payer,
        address indexed merchant,
        uint256 blockNumber
    );

    function verifyHashchain(
        bytes32 trustAnchor,
        bytes32 finalHashValue,
        uint256 numberOfTokensUsed
    ) public pure returns (bool) {
        for (uint256 i = 0; i < numberOfTokensUsed; i++) {
            finalHashValue = keccak256(abi.encode(finalHashValue));
        }
        return finalHashValue == trustAnchor;
    }

    function createChannel(
        address merchant,
        bytes32 trustAnchor,
        uint256 amount,
        uint256 numberOfTokens,
        uint256 merchantWithdrawAfterBlocks,
        uint256 payerWithdrawAfterBlocks
    ) public payable {
        if (msg.value != amount) {
            revert IncorrectAmount(msg.value, amount);
        }

        if (channelsMapping[msg.sender][merchant].amount != 0) {
            revert ChannelAlreadyExist(
                msg.sender,
                merchant,
                channelsMapping[msg.sender][merchant].amount,
                channelsMapping[msg.sender][merchant].numberOfTokens
            );
        }

        // require(
        //     numberOfTokens > 0,
        //     "Number of tokens must be greater than zero"
        // );

        if (numberOfTokens == 0) {
            revert ZeroTokensNotAllowed();
        }

        require(
            merchantWithdrawAfterBlocks <= payerWithdrawAfterBlocks,
            "Merchant should get sufficient time to withdraw before payer is allowed to withdraw."
        );

        channelsMapping[msg.sender][merchant] = Channel({
            trustAnchor: trustAnchor,
            amount: amount,
            numberOfTokens: numberOfTokens,
            merchantWithdrawAfterBlocks: merchantWithdrawAfterBlocks,
            payerWithdrawAfterBlocks: payerWithdrawAfterBlocks
        });

        emit ChannelCreated(
            msg.sender,
            merchant,
            amount,
            numberOfTokens,
            merchantWithdrawAfterBlocks
        );
    }

    function redeemChannel(
        address payer,
        bytes32 finalHashValue,
        uint256 numberOfTokensUsed
    ) public {
        Channel storage channel = channelsMapping[payer][msg.sender];
        if (channel.amount == 0) {
            revert ChannelDoesNotExistOrWithdrawn();
        }
        if (channel.merchantWithdrawAfterBlocks > block.number) {
            revert MerchantCannotRedeemChannelYet(
                channel.merchantWithdrawAfterBlocks
            );
        }

        require(
            numberOfTokensUsed <= channel.numberOfTokens,
            "Token count exceeded"
        );

        if (
            verifyHashchain(
                channel.trustAnchor,
                finalHashValue,
                numberOfTokensUsed
            ) == false
        ) {
            revert TokenVerificationFailed();
        }
        uint256 payableAmountMerchant = (channel.amount * numberOfTokensUsed) /
            channel.numberOfTokens;

        uint256 payableAmountPayer = channel.amount - payableAmountMerchant;
        if (payableAmountMerchant == 0) {
            revert NothingPayable();
        }
        delete channelsMapping[payer][msg.sender];
        (bool sentMerchant, ) = payable(msg.sender).call{
            value: payableAmountMerchant
        }("");
        (bool sentPayer, ) = payable(payer).call{value: payableAmountPayer}("");
        if (sentMerchant && sentPayer == false) {
            revert FailedToSendEther();
        }

        emit ChannelRedeemed(
            payer,
            msg.sender,
            payableAmountMerchant,
            finalHashValue,
            numberOfTokensUsed
        );
    }

    function reclaimChannel(address merchant) public {
        Channel storage channel = channelsMapping[msg.sender][merchant];
        if (channel.amount == 0) {
            revert ChannelDoesNotExistOrWithdrawn();
        }
        if (channel.payerWithdrawAfterBlocks < block.number) {
            uint256 amountToReclaim = channel.amount;
            delete channelsMapping[msg.sender][merchant];
            (bool sent, ) = payable(msg.sender).call{value: amountToReclaim}(
                ""
            );
            if (sent == false) {
                revert FailedToSendEther();
            }

            emit ChannelReclaimed(msg.sender, merchant, block.number);
        } else {
            revert PayerCannotRedeemChannelYet(
                channel.payerWithdrawAfterBlocks
            );
        }
    }

    receive() external payable {}

    fallback() external payable {}
}
