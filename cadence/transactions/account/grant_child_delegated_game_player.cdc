import BattleBlocksAccounts from "../../contracts/accounts/BattleBlocksAccounts.cdc"
import BattleBlocksGame from "../../contracts/game/BattleBlocksGame.cdc"

/// Gives a GamePlayer capability to a child account via the signer's 
/// BattleBlocksAccountsManager. If a GamePlayer doesn't exist in the signer's
/// account, one is created & linked.
///
transaction(childAddress: Address) {

    prepare(signer: AuthAccount) {

        /** --- Set user up with GamePlayer --- */
        //
        // Check if a GamePlayer already exists, pass this block if it does
        if signer.borrow<&BattleBlocksGame.GamePlayer>(from: BattleBlocksGame.GamePlayerStoragePath) == nil {
            // Create GamePlayer resource
            let gamePlayer <- BattleBlocksGame.createGamePlayer()
            // Save it
            signer.save(<-gamePlayer, to: BattleBlocksGame.GamePlayerStoragePath)
        }

        if !signer.getCapability<&{BattleBlocksGame.GamePlayerPublic}>(BattleBlocksGame.GamePlayerPublicPath).check() {
            // Link GamePlayerPublic Capability so player can be added to Matches
            signer.link<&{
                BattleBlocksGame.GamePlayerPublic
            }>(
                BattleBlocksGame.GamePlayerPublicPath,
                target: BattleBlocksGame.GamePlayerStoragePath
            )
        }

        if !signer.getCapability<&{BattleBlocksGame.GamePlayerID, BattleBlocksGame.DelegatedGamePlayer}>(BattleBlocksGame.GamePlayerPrivatePath).check() {
            // Link GamePlayerID Capability
            signer.link<&{
                BattleBlocksGame.DelegatedGamePlayer,
                BattleBlocksGame.GamePlayerID
            }>(
                BattleBlocksGame.GamePlayerPrivatePath,
                target: BattleBlocksGame.GamePlayerStoragePath
            )
        }
        
        // Get the GamePlayer Capability
        let gamePlayerCap = signer.getCapability<&
                {BattleBlocksGame.DelegatedGamePlayer}
            >(
                BattleBlocksGame.GamePlayerPrivatePath
            )

        /** --- Add the Capability to the child's BattleBlocksAccount --- */
        //
        // Get a reference to the ChildAcccountManager resource
        let managerRef = signer
            .borrow<&
                BattleBlocksAccounts.BattleBlocksAccountManager
            >(from: BattleBlocksAccounts.BattleBlocksAccountManagerStoragePath)
            ?? panic("Signer does not have a BattleBlocksAccountsManager configured")
        
        // Grant the GamePlayer Capability to the child account
        managerRef.addCapability(to: childAddress, gamePlayerCap)
    }
}
 