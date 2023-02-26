import NonFungibleToken from "../../../contracts/standard/NonFungibleToken.cdc"
import BattleBlocksNFT from "../../../contracts/nft/BattleBlocksNFT.cdc"
import FungibleToken from "../../../contracts/standard/FungibleToken.cdc"
import MetadataViews from "../../../contracts/standard/MetadataViews.cdc"

/// This script uses the NFTMinter resource to mint a new NFT
/// It must be run with the account that has the minter resource
/// stored in /storage/NFTMinter

transaction(
    recipient: Address,
    name: String,
    description: String,
    thumbnail: String,
    metdata: {String: AnyStruct}
) {

    /// local variable for storing the minter reference
    let minter: &BattleBlocksNFT.NFTMinter

    /// Reference to the receiver's collection
    let recipientCollectionRef: &{NonFungibleToken.CollectionPublic}

    /// Previous NFT ID before the transaction executes
    let mintingIDBefore: UInt64

    /// Reference to the fungible token receiver
    let recipientFungibleTokenReciever: &{FungibleToken.Receiver}

    /// Reference to the admin fungible token provider
    let senderFungibleTokenProvider: &{FungibleToken.Provider}

    /// Storage amount for a single NFT
    let transferAmount: UFix64

    prepare(signer: AuthAccount) {
        self.mintingIDBefore = BattleBlocksNFT.totalSupply

        // borrow a reference to the NFTMinter resource in storage
        self.minter = signer.borrow<&BattleBlocksNFT.NFTMinter>(from: BattleBlocksNFT.MinterStoragePath)
            ?? panic("Account does not store an object at the specified path")

        // Borrow the recipient's public NFT collection reference
        self.recipientCollectionRef = getAccount(recipient)
            .getCapability(BattleBlocksNFT.CollectionPublicPath)
            .borrow<&{NonFungibleToken.CollectionPublic}>()
            ?? panic("Could not get receiver reference to the NFT Collection")

        // amount needed for nft storage
        self.transferAmount = 0.00002;

        // get the recipients public account object
        let recipient = getAccount(recipient)

        // borrow a public reference to the receivers Flow Token receiver capability
        self.recipientFungibleTokenReciever = recipient.getCapability<&{FungibleToken.Receiver}>(/public/flowTokenReceiver)
                .borrow()
                ?? panic("Could not borrow a reference to the recipient's fungible token reciever")

        // reference to the admins' fungible token provider
        self.senderFungibleTokenProvider = signer
            .borrow<&{FungibleToken.Provider}>(from: /storage/flowTokenVault)
            ?? panic("Could not borrow a reference to the owner's fungible token provider")
    }

    execute {
        // Withdraw the FLOW from admin
        let transferVault <- self.senderFungibleTokenProvider.withdraw(amount: self.transferAmount)
        
        // Deposit FLOW to user
        self.recipientFungibleTokenReciever.deposit(from: <- transferVault)

        // Mint the NFT and deposit it to the recipient's collection
        self.minter.mintNFT(
            recipient: self.recipientCollectionRef,
            name: name
            )
    }

    post {
        self.recipientCollectionRef.getIDs().contains(self.mintingIDBefore): "The next NFT ID should have been minted and delivered"
        BattleBlocksNFT.totalSupply == self.mintingIDBefore + 1: "The total supply should have been increased by 1"
    }
}
