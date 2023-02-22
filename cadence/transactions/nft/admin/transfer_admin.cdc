import NonFungibleToken from "../../../contracts/standard/NonFungibleToken.cdc"
import FungibleToken from "../../../contracts/standard/FungibleToken.cdc"
import FlowToken from "../../../contracts/standard/FlowToken.cdc"
import BattleBlocksNFT from "../../../contracts/nft/BattleBlocksNFT.cdc"

/// This transaction is for transferring and NFT from
/// the admin account, also transfering a small amount of FLOW for storage costs.

transaction(recipient: Address, withdrawID: UInt64) {

    /// Reference to the withdrawer's collection
    let withdrawRef: &BattleBlocksNFT.Collection

    /// Reference of the collection to deposit the NFT to
    let depositRef: &{NonFungibleToken.CollectionPublic}

    /// Reference to the fungible token receiver
    let recipientFungibleTokenReciever: &{FungibleToken.Receiver}

    /// Reference to the admin fungible token provider
    let senderFungibleTokenProvider: &{FungibleToken.Provider}

    /// Storage amount for a single NFT
    let transferAmount: UFix64

    prepare(signer: AuthAccount) {
        // amount needed for nft storage
        self.transferAmount = 0.00002;

        // borrow a reference to the signer's NFT collection
        self.withdrawRef = signer
            .borrow<&BattleBlocksNFT.Collection>(from: BattleBlocksNFT.CollectionStoragePath)
            ?? panic("Account does not store an object at the specified path")

        // get the recipients public account object
        let recipient = getAccount(recipient)

        // borrow a public reference to the receivers collection
        self.depositRef = recipient
            .getCapability(BattleBlocksNFT.CollectionPublicPath)
            .borrow<&{NonFungibleToken.CollectionPublic}>()
            ?? panic("Could not borrow a reference to the receiver's collection")

        // borrow a public reference to the receivers Flow Token receiver capability
        self.recipientFungibleTokenReciever = recipient
                .getCapability<&{FungibleToken.Receiver}>(/public/flowTokenReceiver)
                .borrow()
                ?? panic("Could not borrow a reference to the recipient's fungible token reciever")

        // reference to the admins' fungible token provider
        self.senderFungibleTokenProvider = signer
            .borrow<&{FungibleToken.Provider}>(from: /storage/flowTokenVault)
            ?? panic("Could not borrow a reference to the owner's fungible token provider")
    }

    execute {
        // withdraw the NFT from the owner's collection
        let nft <- self.withdrawRef.withdraw(withdrawID: withdrawID)

        // Withdraw the FLOW from admin
        let transferVault <- self.senderFungibleTokenProvider.withdraw(amount: self.transferAmount)
        
        // Deposit FLOW to user
        self.recipientFungibleTokenReciever.deposit(from: <- transferVault)

        // Deposit the NFT in the recipient's collection
        self.depositRef.deposit(token: <-nft)
    }

    post {
        !self.withdrawRef.getIDs().contains(withdrawID): "Original owner should not have the NFT anymore"
        self.depositRef.getIDs().contains(withdrawID): "The reciever should now own the NFT"
    }
}
 