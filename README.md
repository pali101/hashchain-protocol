## Hashchain Protocol

In today's world, one can find oneself stuck in service contracts which are defined by the corporate greed rather than your requirements. We intend to solve this by giving back control to you, the user. Our micro-transactions solution lets you granularise and adapt these service contracts to your needs, whether your need is for a few seconds or a couple of hours. Take your WiFi service contract for example, you are forced to pay on a monthly/yearly basis even though you might use it for a few minutes/hours. Our solution allows you to track this usage at a very granular level and pay only for what you have used. This provides you with the freedom you deserve, while ensuring more trust between you and the service provider.

## Contract

The key insight behind the scheme is to replace resource-hungry PKI operations with hash functions to reduce on-chain cost. Our contract facilitates decentralized payments using hashchains for token validation between payers and merchants.

##### Core Features:

- Channel creation: Users create channels with a trust anchor, locked Ether, and token parameters.
- Channel Redemption: Merchants redeem tokens, validated by the Utility contract. Contract sends proportional payment and refunds any remaining balance.
- Token Validation: Uses hashchains for secure, trustless token verification.

The process flow of interactions between the client, server, and smart contract is described in the following diagrams:

<img src="InteractionDiagram.png" alt="Hash Chain-Based Scheme" width="500"/>

This contract ensures secure, efficient, and trustless micro transactions for decentralized applications.

## Local Development & Deployment

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (`forge`, `cast`)
- A valid Ethereum/FEVM keystore file and password
- RPC endpoint (e.g. Filecoin Calibration, Mainnet, etc.)

### Build and test

```sh
make build
```

## Deployment

### Deploy MuPay contract 

```sh
make deploy-mupay
```

### Deploy Multisig contract

```sh
make deploy-multisig
```

### Deploy both

```sh
make deploy-all
```

By default, deployment targets the Filecoin Calibration (calibnet) network (`chain_id: 314159`).  
You can adjust the `chain_id` or RPC endpoint in the Makefile or deployment script for other networks.

## Environment Setup

Copy `.env.example` to `.env` and fill in your values before deploying:
```sh
cp .env.example .env
```

Then edit `.env` as needed.

You can generate a keystore file from a private key using:
```sh
cast wallet import --private-key $PRIVATE_KEY keystoreName
# File will be saved to ~/.foundry/keystores/
```