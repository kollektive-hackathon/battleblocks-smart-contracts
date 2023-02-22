# BattleBlocks Smart Contracts

This repository contains the smart contracts for BattleBlocks, a decentralized application (dapp) built on the Flow blockchain. The dapp includes various functionalities, each implemented as a separate smart contract in this repository.

## Contracts

### BattleBlocksNFT

BattleBlocksNFT is a simple implementation of a non-fungible token (NFT) contract. It is based on the ExampleNFT contract provided by the Flow team and is used for demonstrative purposes in the BattleBlocks hackathon.

### BattleBlocksChildAccount

BattleBlocksChildAccount is used for walletless account management. This contract allows users to create and manage child accounts within their main account, providing a more streamlined and user-friendly experience.

### BattleBlocksGame

BattleBlocksGame is the game smart contract for BattleBlocks. It provides the logic and functionality for players to compete against each other in a skill-based game, with the ability to earn rewards in the form of BattleBlocks NFTs.

## Development

The contracts in this repository are written in Cadence, the programming language for the Flow blockchain. To deploy and test the contracts, you will need to have the Flow CLI and emulator installed on your local machine.

## Deployment

To deploy the contracts to the Flow network, you will need access to a Flow account with sufficient funds. You can deploy the contracts using the `flow-cli` command-line tool, or any other preferred method.

## License

This project is licensed under the [MIT License](LICENSE).
