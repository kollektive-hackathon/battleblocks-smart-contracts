import NonFungibleToken from "../../contracts/standard/NonFungibleToken.cdc"
import BattleBlocksNFT from "../../contracts/nft/BattleBlocksNFT.cdc"

/// This transaction is what an account would run
/// to set itself up to receive NFTs

transaction {

    prepare(signer: AuthAccount) {
        // Return early if the account already has a collection
        if signer.borrow<&BattleBlocksNFT.Collection>(from: BattleBlocksNFT.CollectionStoragePath) != nil {
            return
        }

        // Create a new empty collection
        let collection <- BattleBlocksNFT.createEmptyCollection()

        // save it to the account
        signer.save(<-collection, to: BattleBlocksNFT.CollectionStoragePath)

        // create a public capability for the collection
        signer.link<&{NonFungibleToken.CollectionPublic, BattleBlocksNFT.BattleBlocksNFTCollectionPublic}>(
            BattleBlocksNFT.CollectionPublicPath,
            target: BattleBlocksNFT.CollectionStoragePath
        )
    }
}