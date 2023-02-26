import BattleBlocksGame from "../../contracts/game/BattleBlocksGame.cdc"

transaction(gameID: UInt64, guessX: UInt64, guessY: UInt64, proof: [[UInt8]]?, isBlock: Bool, opponentGuessX: UInt64, opponentGuessY: UInt64, nonce: UInt64) {
    
    let gamePlayerRef: &BattleBlocksGame.GamePlayer

    prepare(acct: AuthAccount) {
        // Get the GamePlayer reference from the signing account's storage
        self.gamePlayerRef = acct
            .borrow<&BattleBlocksGame.GamePlayer>(
                from: BattleBlocksGame.GamePlayerStoragePath
            ) ?? panic("Could not borrow GamePlayer reference!")
    }

    execute {
        let reveal: BattleBlocksGame.Reveal = BattleBlocksGame.Reveal(BattleBlocksGame.Guess(BattleBlocksGame.Coordinates(x: opponentGuessX, y: opponentGuessY), isBlock: isBlock), nonce: nonce)
        let coordinates: BattleBlocksGame.Coordinates = BattleBlocksGame.Coordinates(x: guessX, y: guessY)

        // Submit moves for the game
        self.gamePlayerRef.submitMoveToGame(gameID: gameID, coordinates: coordinates, proof: proof, reveal: reveal)
    }
}
 