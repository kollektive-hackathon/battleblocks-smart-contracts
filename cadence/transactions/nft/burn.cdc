import NonFungibleToken from "../../contracts/standard/NonFungibleToken.cdc"
import BattleBlocksNFT from "../../contracts/nft/BattleBlocksNFT.cdc"

/// This transaction withdraws an NFT from the signers collection and destroys it
transaction(id: UInt64) {

    /// Reference that will be used for the owner's collection
    let collectionRef: &BattleBlocksNFT.Collection

    prepare(signer: AuthAccount) {

        // borrow a reference to the owner's collection
        self.collectionRef = signer.borrow<&BattleBlocksNFT.Collection>(from: BattleBlocksNFT.CollectionStoragePath)
            ?? panic("Account does not store an object at the specified path")

    }

    execute {

        // withdraw the NFT from the owner's collection
        let nft <- self.collectionRef.withdraw(withdrawID: id)

        destroy nft
    }

    post {
        !self.collectionRef.getIDs().contains(id): "The NFT with the specified ID should have been deleted"
    }
}