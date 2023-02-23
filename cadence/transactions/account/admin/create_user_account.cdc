import BattleBlocksAccounts from "../../../contracts/accounts/BattleBlocksAccounts.cdc"
import BattleBlocksNFT from "../../../contracts/nft/BattleBlocksNFT.cdc"
import FungibleToken from "../../../contracts/standard/FungibleToken.cdc"
import NonFungibleToken from "../../../contracts/standard/NonFungibleToken.cdc"

/// This transaction creates an account from the given public key, using the
/// BattleBlocksAccountCreator with the signer as the account's payer, additionally
/// funding the new account with the specified amount of Flow from the signer's
/// account.
transaction(
        pubKey: String,
        fundingAmt: UFix64,
    ) {

    prepare(signer: AuthAccount) {

        /* --- Create a new account --- */
        //
        // Get a reference to the signer's BattleBlocksAccountCreator
        let creatorRef = signer.borrow<
                &BattleBlocksAccounts.BattleBlocksAccountCreator
            >(
                from: BattleBlocksAccounts.BattleBlocksAccountCreatorStoragePath
            ) ?? panic(
                "No BattleBlocksAccountCreator in signer's account at "
                .concat(BattleBlocksAccounts.BattleBlocksAccountCreatorStoragePath.toString())
            )

        // Create the BattleBlocksAccount Resource
        let newAccount = creatorRef.createBattleBlocksAccount(
            signer: signer,
            initialFundingAmount: fundingAmt,
            originatingPublicKey: pubKey
        )

        /* --- Set up BattleBlocksNFT.Collection --- */
        //
        // Create & save it to the account
        newAccount.save(<-BattleBlocksNFT.createEmptyCollection(), to: BattleBlocksNFT.CollectionStoragePath)

        // Link the public capability for the collection
        newAccount.link<
            &BattleBlocksNFT.Collection{NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic, BattleBlocksNFT.BattleBlocksNFTCollectionPublic}
            >(
                BattleBlocksNFT.CollectionPublicPath,
                target: BattleBlocksNFT.CollectionStoragePath
            )

        // Link the Provider Capability in private storage
        newAccount.link<
            &BattleBlocksNFT.Collection{NonFungibleToken.Provider}
        >(
            BattleBlocksNFT.ProviderPrivatePath,
            target: BattleBlocksNFT.CollectionStoragePath
        )

    }
}