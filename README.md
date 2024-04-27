## Stablecoin Defi Protocol

This project aims to create a stablecoin where users can deposit Wrapped Ether (WETH) and Wrapped Bitcoin (WBTC) in exchange for a token pegged to the USD.

Used : Solidity , Foundry, Openzeppelin, Chainlink vrf, Chainlink automation

### Requirements
- #### Foundry

To get started with Foundry, run the following commands:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
git clone https://github.com/HemaDeviU/StableCoin-Defi-Protocol
cd StableCoin-Defi-Protocol
forge build
```

### Usage
- #### For local Deployment

1.  Start a local node
```make anvil```
2.  Deploy
```make deploy```

- #### For testnet deployment

1. Setup environment variables
You'll want to set your SEPOLIA_RPC_URL and PRIVATE_KEY as environment variables. You can add them to a .env file.

- PRIVATE_KEY: The private key of your account (like from metamask) which has testnet ETH.
- SEPOLIA_RPC_URL: This is url of the sepolia testnet node you're working with. You can get setup with one for free from Alchemy.
- ETHERSCAN_API_KEY: To verify the contract,get the api key from etherscan account.

2. Deploy
make deploy ARGS="--network sepolia"







