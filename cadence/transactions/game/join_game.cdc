import NonFungibleToken from "../../contracts/standard/NonFungibleToken.cdc"
import FungibleToken from "../../contracts/standard/FungibleToken.cdc"
import FlowToken from "../../contracts/standard/FlowToken.cdc"
import BattleBlocksGame from "../../contracts/game/BattleBlocksGame.cdc"

transaction(gameID: UInt64, wagerAmount: UFix64, merkleRoot: [UInt8]) {

    let gamePlayerRef: &BattleBlocksGame.GamePlayer
    let wagerVault: @FlowToken.Vault

    prepare(signer: AuthAccount) {
        // Create GamePlayer resource if it doesn't already exist
        if signer.borrow<&BattleBlocksGame.GamePlayer>(from: BattleBlocksGame.GamePlayerStoragePath) == nil {
            let gamePlayer <- BattleBlocksGame.createGamePlayer()
            signer.save(<-gamePlayer, to: BattleBlocksGame.GamePlayerStoragePath)
        }

        // Check GamePlayerPublic capability
        if !signer.getCapability<
                &{BattleBlocksGame.GamePlayerPublic}
            >(BattleBlocksGame.GamePlayerPublicPath).check() {
            signer.unlink(BattleBlocksGame.GamePlayerPublicPath)
            signer.link<&{
                BattleBlocksGame.GamePlayerPublic
            }>(
                BattleBlocksGame.GamePlayerPublicPath,
                target: BattleBlocksGame.GamePlayerStoragePath
            )
        }

        // Check GamePlayerID && DelegatedGamePlayer
        if !signer.getCapability<
                &{BattleBlocksGame.GamePlayerID, BattleBlocksGame.DelegatedGamePlayer}
            >(BattleBlocksGame.GamePlayerPrivatePath).check() {
            signer.unlink(BattleBlocksGame.GamePlayerPrivatePath)
            signer.link<&{
                BattleBlocksGame.GamePlayerID
            }>(
                BattleBlocksGame.GamePlayerPrivatePath,
                target: BattleBlocksGame.GamePlayerStoragePath
            )
        }

        // Get a reference to the game player
        self.gamePlayerRef = signer.borrow<
                &BattleBlocksGame.GamePlayer
            >(
                from: BattleBlocksGame.GamePlayerStoragePath
            )!
        
        // Get a reference to the account's FlowToken.Vault
        let vaultRef = signer.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)
			?? panic("Could not borrow reference to the owner's Vault!")

        // Withdraw tokens from the signer's stored vault
        self.wagerVault <- vaultRef.withdraw(amount: wagerAmount) as! @FlowToken.Vault
    }

    execute {
        self.gamePlayerRef.signUpForGame(gameID: gameID)
        self.gamePlayerRef.joinGame(wager: <- self.wagerVault, merkleRoot: merkleRoot, gameID: gameID)
    }
}
 