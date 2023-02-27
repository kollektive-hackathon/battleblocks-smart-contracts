import NonFungibleToken from "../../contracts/standard/NonFungibleToken.cdc"
import FungibleToken from "../../contracts/standard/FungibleToken.cdc"
import FlowToken from "../../contracts/standard/FlowToken.cdc"
import BattleBlocksGame from "../../contracts/game/BattleBlocksGame.cdc"

transaction(wagerAmount: UFix64, merkleRoot: [UInt8], payload: UInt64) {
    
    let gamePlayerRef: &BattleBlocksGame.GamePlayer
    let wagerVault: @FlowToken.Vault
    
    prepare(acct: AuthAccount) {
        // Get a reference to the GamePlayer resource in the signing account's storage
        self.gamePlayerRef = acct
            .borrow<&BattleBlocksGame.GamePlayer>(
                from: BattleBlocksGame.GamePlayerStoragePath
            ) ?? panic("Could not borrow GamePlayer reference!")

        // Get a reference to the account's FlowToken.Vault
        let vaultRef = acct.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)
			?? panic("Could not borrow reference to the owner's Vault!")

        // Withdraw tokens from the signer's stored vault
        self.wagerVault <- vaultRef.withdraw(amount: wagerAmount) as! @FlowToken.Vault
    }

    execute {
        self.gamePlayerRef.createGame(wager: <-self.wagerVault, merkleRoot: merkleRoot, payload: payload)
    }
}
 