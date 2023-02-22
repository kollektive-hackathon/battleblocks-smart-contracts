import NonFungibleToken from "../../contracts/standard/NonFungibleToken.cdc"
import BattleBlocksNFT from "../../contracts/nft/BattleBlocksNFT.cdc"

/// This script borrows an NFT from a collection and if it exists, 
/// it returns the nft's metadata field

pub fun main(address: Address, id: UInt64): {String: AnyStruct}? {
    let account = getAccount(address)

    let collectionRef = account
        .getCapability(BattleBlocksNFT.CollectionPublicPath)
        .borrow<&{BattleBlocksNFT.BattleBlocksNFTCollectionPublic}>()
        ?? panic("Could not borrow capability from public collection")

    // Borrow a reference to a specific NFT in the collection
    let _ = collectionRef.borrowBattleBlocksNFT(id: id)

    return _?.getMetadata()
}