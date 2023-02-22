import NonFungibleToken from "../../contracts/standard/NonFungibleToken.cdc"
import BattleBlocksNFT from "../../contracts/nft/BattleBlocksNFT.cdc"

/// Script to get NFT IDs in an account's collection

pub fun main(address: Address, collectionPublicPath: PublicPath): [UInt64] {
    let account = getAccount(address)

    let collectionRef = account
        .getCapability(collectionPublicPath)
        .borrow<&{NonFungibleToken.CollectionPublic}>()
        ?? panic("Could not borrow capability from public collection at specified path")

    return collectionRef.getIDs()
}