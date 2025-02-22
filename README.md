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

## Getting Started

1. Clone this repository.
2. Install Forge using the instructions found at [https://github.com/foundry-rs/foundry](https://github.com/foundry-rs/foundry).
3. Run the following command to compile the contract:

```bash
forge build
```

4. Run the following command to deploy the contract to a test network:

```bash
forge create
```

5. Interact with the contract using Forge's interactive console.

```bash
forge console
```
