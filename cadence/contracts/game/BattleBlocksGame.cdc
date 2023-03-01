import FungibleToken from "../standard/FungibleToken.cdc"
import FlowToken from "../standard/FlowToken.cdc"

pub contract BattleBlocksGame {

    //-----Paths-----//

    pub let GamePlayerStoragePath: StoragePath
    pub let GamePlayerPublicPath: PublicPath
    pub let GamePlayerPrivatePath: PrivatePath

    pub let GameStorageBasePathString: String
    pub let GamePrivateBasePathString: String

    //--------------//

    //-----Variables-----//

    //------------------//

    //-----Events-----//

    pub event GameCreated(
        gameID: UInt64,
        creatorID: UInt64,
        creatorAddress: Address,
        wager: UFix64,
        payload: UInt64,
        )

    pub event GameEnded (
        gameID: UInt64,
        playerA: Address,
        playerB: Address,
        winner: Address?,
        playerHitCount: {Address: UInt8}
        )

    pub event PlayerJoined(
        gameID: UInt64,
        startTime: UInt64,
        wager: UFix64,
        playerA: Address,
        playerB: Address?,
        winner: Address?,
        playerHitCount: {Address: UInt8},
        gameState: UInt8,
        turn: UInt8,
        playerAMerkleRoot: [UInt8],
        playerBMerkleRoot: [UInt8]
        )
    
    pub event PlayerAdded(
        gameID: UInt64,
        addedPlayerID: UInt64
        )

    pub event BlockRevealed(
        gameID: UInt64,
        coordinateX: UInt64,
        coordinateY: UInt64,
        blockOwner: Address?,
        reveal: String
    )

    pub event PlayerSignedUp(
        gameID: UInt64, 
        addedPlayerID: UInt64
        )

    pub event PlayerMoved(
        gameID: UInt64,
        gamePlayerID: UInt64,
        playerAddress: Address,
        coordinateX: UInt64,
        coordinateY: UInt64,
        turn: UInt8
        )

    //----------------//

    //-----Enums-----//

    pub enum GameState: UInt8 {
        pub case pending
        pub case active
        pub case completed
    }

    pub enum TurnState: UInt8 {
        pub case inactive
        pub case playerA
        pub case playerB
    }

    pub enum MoveState: UInt8 {
        pub case unkown
        pub case pending
        pub case hit
        pub case miss
    }

    //---------------//

    //-----Structs-----//

    pub struct Coordinates {
        pub let x: UInt64
        pub let y: UInt64

        init (x: UInt64, y: UInt64) {
            self.x = x
            self.y = y
        }
    }

    pub struct Guess {
        pub let coodinates: Coordinates
        pub let isBlock: Bool

        init (coodinates: Coordinates, isBlock: Bool) {
            self.coodinates = coodinates
            self.isBlock = isBlock
        }
    }

    pub struct Reveal {
        pub let guess: Guess
        pub let nonce: UInt64

        init (guess: Guess, nonce: UInt64) {
            self.guess = guess
            self.nonce = nonce
        }

        pub fun toString(): String{
            return (self.guess.isBlock ? "1" : "0")
                .concat(self.guess.coodinates.x.toString())
                .concat(self.guess.coodinates.y.toString())
                .concat(self.nonce.toString())
        }
    }

    pub struct GameData {
        pub let startTime: UInt64
        pub let wager: UFix64
        pub var playerA: Address
        pub var playerB: Address?
        pub var winner: Address?
        pub var gameState: GameState
        pub var turn: TurnState
        pub let playerAMerkleRoot: [UInt8]
        access(contract) var playerHitCount: {Address: UInt8}
        access(contract) var playerBMerkleRoot: [UInt8]
        // playerAddress => [X,Y] MoveState
        access(contract) var playerMoves : {Address: [[MoveState]]}
        // playerAddress => Coodinates in order
        access(contract) var playerGuesses: {Address: [Coordinates]}

        init(wager: UFix64, playerA: Address, playerAMerkleRoot: [UInt8]){
            self.startTime = UInt64(getCurrentBlock().timestamp)
            self.wager = wager
            self.playerA = playerA
            self.playerB = nil
            self.turn = TurnState.inactive
            self.gameState = GameState.pending
            self.playerAMerkleRoot = playerAMerkleRoot
            self.playerBMerkleRoot = []

            self.winner = nil
            self.playerHitCount = {}
            self.playerMoves = {}
            self.playerGuesses = {}
        }

        access(contract) fun setPlayerB(_ playerB: Address) {
            self.playerB = playerB
        }

        access(contract) fun setPlayerA(_ playerA: Address) {
            self.playerA = playerA
        }

        access(contract) fun setPlayerBMerkleRoot(_ playerBMerkleRoot: [UInt8]) {
            self.playerBMerkleRoot = playerBMerkleRoot
        }

        access(contract) fun setTurn(_ nextTurn: TurnState){
            self.turn = nextTurn
        }
        
        access(contract) fun setPlayerMoves (player: Address, moves: [[MoveState]]) {
            self.playerMoves[player] = moves
        }

        access(contract) fun setPlayerMove (player: Address, move: MoveState, coordinates: Coordinates) {
            let xAxis = self.playerMoves[player]![coordinates.y]
            xAxis.insert(at: coordinates.x, move)
            xAxis.remove(at: coordinates.x + 1)
            self.playerMoves[player]!.insert(at: coordinates.y, xAxis)
            self.playerMoves[player]!.remove(at: coordinates.y+1)
        }

        access(contract) fun playerGuess (player: Address, guess: Coordinates){
            if (self.playerGuesses[player] != nil ) {
                self.playerGuesses[player]!.append(guess)
            } else {
                self.playerGuesses[player] = [guess]
            }
        }

        // Returns TRUE if game is over, otherwise FALSE
        access(contract) fun increaseHitCount (player: Address): Bool{
            if (self.playerHitCount[player] != nil ) {
                self.playerHitCount[player] = self.playerHitCount[player]! + 1
            } else {
                self.playerHitCount[player] = 1
            }
            if (self.playerHitCount[player] == 10) {

                // Game Over

                self.winner = player
                self.gameState = GameState.completed
                self.turn = TurnState.inactive

                return true
            } else {
                return false
            }
        }

        pub fun getLatestPlayerGuess(player: Address): Coordinates? {
            if (self.playerGuesses[player] != nil ) {
                return self.playerGuesses[player]![self.playerGuesses[player]!.length - 1]
            } else {
                return nil
            }
        } 
    }

    //-----------------//

    //-----Interfaces-----//

    pub resource interface GameActions {
        pub let id: UInt64
        pub fun getWinningPlayerAddress(): Address?
        pub fun joinGame(
            wager: @FlowToken.Vault,
            merkleRoot: [UInt8],
            gamePlayerIDRef: &{GamePlayerID}
        ): Capability<&{PlayerActions}>
        pub fun getPrizePool(): UFix64
        pub fun getGamePlayerIds(): {UInt8: {Address: UInt64}}
        pub fun getGameData(): GameData
    }

    pub resource interface GamePlayerID {
        pub let id: UInt64
    }

    pub resource interface PlayerActions {
        pub let id: UInt64
        pub fun getWinningPlayerAddress(): Address?
        pub fun getPlayerGameMoves(playerAddress: Address): [[MoveState]]? 
        pub fun submitMove(
            coordinates: Coordinates,
            gamePlayerIDRef: &{GamePlayerID},
            proof: [[UInt8]]?,
            reveal: Reveal?
            )
    }

    pub resource interface GamePlayerPublic {
        pub let id: UInt64
        pub fun addGameActionsCapability(
            gameID: UInt64,
            _ cap: Capability<&{GameActions}>
        )
        pub fun getGames(): [UInt64]
        pub fun getPlayers(): [UInt64]
    }

    pub resource interface DelegatedGamePlayer {
        pub let id: UInt64
        pub fun getGamePlayerIDRef(): &{GamePlayerID}
        pub fun getGames(): [UInt64]
        pub fun getPlayers(): [UInt64]
        pub fun getGameCapabilities(): {UInt64: Capability<&{GameActions}>}
        pub fun getPlayerCapabilities(): {UInt64: Capability<&{PlayerActions}>}
        pub fun deleteGameActionsCapability(gameID: UInt64) 
        pub fun deletePlayerActionsCapability(gameID: UInt64)
        pub fun createGame(wager: @FlowToken.Vault, merkleRoot: [UInt8], payload: UInt64): UInt64
        pub fun joinGame(wager: @FlowToken.Vault, merkleRoot: [UInt8], gameID: UInt64) 
        pub fun submitMoveToGame(gameID: UInt64, coordinates: Coordinates, proof: [[UInt8]]?, reveal: Reveal?) 
        pub fun signUpForGame(gameID: UInt64)
        pub fun addPlayerToGame(gameID: UInt64, gamePlayerRef: &AnyResource{GamePlayerPublic}) 
        pub fun addGameActionsCapability(gameID: UInt64, _ cap: Capability<&{GameActions}>)
    }

    //--------------------//

    //-----Resources-----//

    pub resource Game : GameActions, PlayerActions {
        pub let id: UInt64
        access(contract) var data: GameData
        access(self) var prizePool: @FlowToken.Vault
        access(contract) var gamePlayerIDs: {UInt8: {Address: UInt64}}

        init(data: GameData) {
            self.data = data
            self.id = self.uuid
            self.gamePlayerIDs = {}
            self.prizePool <- FlowToken.createEmptyVault() as! @FlowToken.Vault
        }

        pub fun getGamePlayerIds(): {UInt8: {Address: UInt64}} {
            return self.gamePlayerIDs
        }

        pub fun getPrizePool(): UFix64 {
            return self.prizePool.balance
        }

        pub fun getGameData(): GameData {
            return self.data
        }

        pub fun joinGame(wager: @FlowToken.Vault, merkleRoot: [UInt8], gamePlayerIDRef: &{GamePlayerID}): Capability<&{PlayerActions}> {
            pre {
                gamePlayerIDRef.owner?.address != nil:
                    "GamePlayerID can't be nil"
                !((self.data.playerA != gamePlayerIDRef.owner?.address) && (self.data.playerB != nil)) || ((self.data.playerA == gamePlayerIDRef.owner?.address) && (self.gamePlayerIDs.containsKey(1) == false)):
                    "Player has already joined this Game!"
                wager.balance == self.data.wager:
                    "Invalid wager amount!"
                self.prizePool.balance != self.data.wager * 2.0:
                    "Prize pool has already been filled"
                self.data.gameState == GameState.pending:
                    "Game already started!"
            }

            let gamePrivatePath = BattleBlocksGame.getGamePrivatePath(self.id)

            let gamePlayerActionsCap = BattleBlocksGame.account
                .getCapability<&{
                    PlayerActions
                }>(
                    gamePrivatePath
                )
            
            assert(
                gamePlayerActionsCap.check(),
                message: "Invalid PlayerActions Capability!"
            )

            let playerAddress = gamePlayerIDRef.owner?.address!

            let gamePlayerIDtoAddress = {playerAddress: gamePlayerIDRef.id}

            var playerIndex: UInt8 = 0

            var emptyXAxis: [MoveState] = []
            let emptyPlayerMoves: [[MoveState]] = [[]]

            var i = 0
            while i < 10 {
                emptyXAxis.append(MoveState.unkown)
                i = i + 1
            }

            var j: Int = 0
            while j < 10 {
                emptyPlayerMoves.appendAll([emptyXAxis])
                j = j + 1
            }

            if (playerAddress == self.data.playerA) {
                playerIndex = TurnState.playerA.rawValue
                self.data.setPlayerA(gamePlayerIDRef.owner?.address!)
      
            } else {
                playerIndex = TurnState.playerB.rawValue
                self.data.setPlayerB(gamePlayerIDRef.owner?.address!)
                self.data.setPlayerBMerkleRoot(merkleRoot)
                self.data.setTurn(TurnState.playerA)
            }

            self.data.setPlayerMoves(player: playerAddress, moves: emptyPlayerMoves)
            
            self.prizePool.deposit(from: <- wager)

            self.gamePlayerIDs.insert(key: playerIndex, gamePlayerIDtoAddress)

            // Update Game data

            emit PlayerJoined(
                gameID: self.id,
                startTime: self.data.startTime,
                wager: self.data.wager,
                playerA: self.data.playerA,
                playerB: self.data.playerB,
                winner: self.data.winner,
                playerHitCount: self.data.playerHitCount,
                gameState: self.data.gameState.rawValue,
                turn: self.data.turn.rawValue,
                playerAMerkleRoot: self.data.playerAMerkleRoot,
                playerBMerkleRoot: self.data.playerBMerkleRoot,
            )

            return gamePlayerActionsCap
        }

        pub fun getWinningPlayerAddress(): Address? {
            pre {
                self.data.gameState == GameState.completed:
                    "Match must be resolved before a winner is determined"
            }
            return self.data.winner
        }

        pub fun getPlayerGameMoves(playerAddress: Address): [[MoveState]]? {
            return self.data.playerMoves[playerAddress]
        }

        pub fun submitMove(coordinates: Coordinates, gamePlayerIDRef: &{GamePlayerID}, proof: [[UInt8]]?, reveal: Reveal?) {
            pre {
                !(self.data.gameState == GameState.active):
                    "You can only submit moves to active games!"

                self.gamePlayerIDs[self.data.turn.rawValue]!.keys[0] == gamePlayerIDRef.owner?.address:
                    "It's not your turn to play!"
            }
            
            let playerAddress = gamePlayerIDRef.owner?.address!

            var previousPlayer: Address? = nil

            var currentPlayerMerkleRoot: [UInt8] = []

            if (playerAddress == self.data.playerA) {
                previousPlayer = self.data.playerB
                currentPlayerMerkleRoot = self.data.playerAMerkleRoot
                self.data.setTurn(TurnState.playerB)
            } else if (playerAddress == self.data.playerB) {
                previousPlayer = self.data.playerA
                currentPlayerMerkleRoot = self.data.playerBMerkleRoot
                self.data.setTurn(TurnState.playerA)
            } else {
                panic ("Invalid player address")
            }

            // Move
            self.data.setPlayerMove(player: playerAddress, move: MoveState.pending, coordinates: coordinates)

            if (self.data.playerGuesses[self.data.playerA]?.length != nil || self.data.playerGuesses[self.data.playerB!]?.length != nil) {
                // Not First

                // Proof for Last Guess
                let guessCoordinates = self.data.getLatestPlayerGuess(player: previousPlayer!)!
                if !(reveal!.guess.coodinates.x == guessCoordinates.x && reveal!.guess.coodinates.y == guessCoordinates.y) {
                    panic ("Invalid coordinates revealed")
                } else {
                    if !(self.proveGuess(playerMerkleRoot: currentPlayerMerkleRoot, proof: proof!, reveal: reveal!)) {
                        panic ("Failed prooving guess")
                    } else {
                        if (reveal!.guess.isBlock) {
                            // Hit
                            self.data.setPlayerMove(player: previousPlayer!, move: MoveState.hit, coordinates: coordinates)
                            emit BlockRevealed(gameID: self.id, coordinateX:  guessCoordinates.x, coordinateY: guessCoordinates.y, blockOwner: previousPlayer, reveal: "hit",  )
                            if (self.data.increaseHitCount(player: previousPlayer!)) {
                                // Game Over
                                self.completeMatch()
                            } 
                        } else {
                            // Miss
                            self.data.setPlayerMove(player: previousPlayer!, move: MoveState.miss, coordinates: coordinates)
                            emit BlockRevealed(gameID: self.id, coordinateX:  guessCoordinates.x, coordinateY: guessCoordinates.y, blockOwner: previousPlayer, reveal: "miss")
                        }
                    }
                }       
            } else {
                // First

                // No need proof Last Guess
            }

            // Guess
            self.data.playerGuess(player: playerAddress, guess: coordinates)  

            emit PlayerMoved(
                gameID: self.id,
                gamePlayerID: gamePlayerIDRef.id,
                playerAddress: playerAddress,
                coordinateX: coordinates.x,
                coordinateY: coordinates.y,
                turn: self.data.turn.rawValue
                )
        }

        access(contract) fun completeMatch() {
            pre {
                self.data.gameState == GameState.completed : "The game has to be completed"
                self.data.winner != nil : "The game needs to have a winner"
            }
            
            // Send rewards
            let winnerFlowReciever = getAccount(self.data.winner!)
                .getCapability(/public/flowTokenReceiver)
                .borrow<&{FungibleToken.Receiver}>()
                ?? panic("Could not borrow receiver reference to the recipient's Vault")
            let prizeVault: @FlowToken.Vault <- self.prizePool <- FlowToken.createEmptyVault() as! @FlowToken.Vault
            winnerFlowReciever.deposit(from: <- prizeVault)

            // Set Turn
            self.data.setTurn(TurnState.inactive)

            // Send event
            emit GameEnded(
                gameID: self.id,
                playerA: self.data.playerA,
                playerB: self.data.playerB!,
                winner: self.data.winner,
                playerHitCount: self.data.playerHitCount
                )

            // Delete game from storage
            let gameStoragePath = BattleBlocksGame.getGameStoragePath(self.id)
            let completedGame <- BattleBlocksGame.account.load<@Game>(from: gameStoragePath)

            destroy completedGame
        }

        priv fun proveGuess(playerMerkleRoot: [UInt8], proof: [[UInt8]], reveal: Reveal): Bool {
            let leaf = HashAlgorithm.KECCAK_256.hash((String.encodeHex(reveal.toString().utf8).utf8))
            return self.verifyProof(proof: proof, root: playerMerkleRoot, leaf: leaf)
        }

        priv fun verifyProof(proof: [[UInt8]], root: [UInt8], leaf: [UInt8]): Bool {
            pre {
                proof.length > 0: "invalid proof"
                root.length == 32: "invalid root"
                leaf.length == 32: "invalid leaf"
            }

            for p in proof {
                if p.length != 32 {
                    panic("invalid proof")
                }
            }

            let hasher = HashAlgorithm(rawVaule: HashAlgorithm.KECCAK_256.rawValue)!

            var computedHash = leaf
            var counter = 0
            while counter < proof.length {
                let proofElement = proof[counter]
                if self.compareBytes(proofElement, computedHash) == 1 {
                    computedHash = hasher.hash(computedHash.concat(proofElement))
                } else {
                    computedHash = hasher.hash(proofElement.concat(computedHash))
                }

                counter = counter + 1
            }

            return self.compareBytes(computedHash, root) == 0
        }

        priv fun compareBytes(_ b1: [UInt8], _ b2: [UInt8]): Int8 {
            pre {
                b1.length == 32: "invalid params"
                b2.length == 32: "invalid params"
            }
            
            var counter = 0
            while counter < b1.length {
                let diff = Int32(b1[counter]) - Int32(b2[counter])
                if diff > 0 {
                    return 1
                }

                if diff < 0 {
                    return -1
                }

                counter = counter + 1
            }

            return 0
        }

        access(contract) fun getPlayerMoves(): {Address: [[MoveState]]} {
            return self.data.playerMoves
        }

        access(contract) fun getPlayerGuesses(): {Address: [Coordinates]} {
            return self.data.playerGuesses
        }

        destroy() {
            pre {
                self.data.gameState != GameState.completed: 
                    "Cannot destroy while Gatch is still in play!"
            }
            destroy self.prizePool
        }
    }

    pub resource GamePlayer : GamePlayerID, GamePlayerPublic, DelegatedGamePlayer {
        pub let id: UInt64
        access(self) let gameCapabilities: {UInt64: Capability<&{GameActions}>}
        access(self) let playerCapabilities: {UInt64: Capability<&{PlayerActions}>}

        init() {
            self.id = self.uuid
            self.gameCapabilities = {}
            self.playerCapabilities = {}
        }
        
        pub fun getGamePlayerIDRef(): &{GamePlayerID} {
            return &self as &{GamePlayerID}
        }

        pub fun getGames(): [UInt64] {
            return self.gameCapabilities.keys
        }

        pub fun getPlayers(): [UInt64] {
            return self.playerCapabilities.keys
        }

        pub fun getGameCapabilities(): {UInt64: Capability<&{GameActions}>} {
            return self.gameCapabilities
        }

        pub fun getPlayerCapabilities(): {UInt64: Capability<&{PlayerActions}>} {
            return self.playerCapabilities
        }

        pub fun deleteGameActionsCapability(gameID: UInt64) {
            self.gameCapabilities.remove(key: gameID)
        }

        pub fun deletePlayerActionsCapability(gameID: UInt64) {
            self.playerCapabilities.remove(key: gameID)
        }

        pub fun createGame(wager: @FlowToken.Vault, merkleRoot: [UInt8], payload: UInt64): UInt64 {
            let gamePlayerIDRef = self.getGamePlayerIDRef()

            let stake = wager.balance

            let data = GameData(
                wager: wager.balance,
                playerA: gamePlayerIDRef.owner?.address!,
                playerAMerkleRoot: merkleRoot
            )

            let newGame <- create Game(data: data)
        
            let newGameID = newGame.id
            
            // Derive paths using matchID
            let gameStoragePath = BattleBlocksGame.getGameStoragePath(newGameID)
            let gamePrivatePath = BattleBlocksGame.getGamePrivatePath(newGameID)
            
            // Save the match to game contract account's storage
            BattleBlocksGame.account.save(<-newGame, to: gameStoragePath)
            
            // Link each Capability to game contract account's private
            BattleBlocksGame.account.link<&{
                GameActions,
                PlayerActions
            }>(
                gamePrivatePath,
                target: gameStoragePath
            )

            // Get the MatchLobbyActions Capability we just linked
            let lobbyCap = BattleBlocksGame.account
                .getCapability<&{
                    GameActions
                }>(
                    gamePrivatePath
                )

            // Add that Capability to the GamePlayer's mapping
            self.gameCapabilities[newGameID] = lobbyCap

            self.joinGame(wager: <- wager, merkleRoot: merkleRoot, gameID: newGameID)

            // Remove the GameActions now that the wager has been deposited
            self.gameCapabilities.remove(key: newGameID)

            emit GameCreated(
                gameID: newGameID,
                creatorID: self.id,
                creatorAddress: self.owner?.address!,
                wager: stake,
                payload: payload
            )

            return newGameID
        }

        pub fun joinGame(wager: @FlowToken.Vault, merkleRoot: [UInt8], gameID: UInt64) {
            pre {
                self.gameCapabilities.containsKey(gameID) &&
                !self.playerCapabilities.containsKey(gameID):
                    "GamePlayer does not have the Capability to play this Game!"
            }
            post {
                self.playerCapabilities.containsKey(gameID):
                    "PlayerActions Capability not successfully added!"
                !self.gameCapabilities.containsKey(gameID) &&
                self.playerCapabilities.containsKey(gameID):
                    "GamePlayer does not have the Capability to play this Game!"
            }
            
            // Get the MatchPlayerActions Capability from this GamePlayer's mapping
            let gameCap: Capability<&{GameActions}> = self.gameCapabilities[gameID]!
            let gameActionsRef = gameCap
                .borrow()
                ?? panic("Could not borrow reference to GameActions")

            // Join the game, getting back a Capability
            let playerCap: Capability<&{PlayerActions}> = gameActionsRef
                .joinGame(wager: <- wager, merkleRoot: merkleRoot, gamePlayerIDRef: &self as &{GamePlayerID})

            // Add that Capability to the GamePlayer's mapping & remove from
            // mapping of MatchLobbyCapabilities
            self.playerCapabilities.insert(key: gameID, playerCap)
            self.gameCapabilities.remove(key: gameID)
        }

        pub fun submitMoveToGame(gameID: UInt64, coordinates: Coordinates, proof: [[UInt8]]?, reveal: Reveal?) {
            pre {
                self.playerCapabilities.containsKey(gameID):
                    "Player does not have the ability to play this Game!"
                self.playerCapabilities[gameID]!.check():
                    "Problem with the PlayerActions Capability for given Game!"
            }
            let matchRef = self.playerCapabilities[gameID]!.borrow()!
            let gamePlayerIDRef = self.getGamePlayerIDRef()
            matchRef.submitMove(coordinates: coordinates, gamePlayerIDRef: gamePlayerIDRef, proof: proof, reveal: reveal)
        }

        pub fun addPlayerToGame(gameID: UInt64, gamePlayerRef: &AnyResource{GamePlayerPublic}) {
            let gamePrivatePath = BattleBlocksGame.getGamePrivatePath(gameID)
            let gameActionsCap: Capability<&AnyResource{GameActions}> = BattleBlocksGame.account
                .getCapability<&{GameActions}>(gamePrivatePath)

            assert(
                gameActionsCap.check(),
                message: "Not able to retrieve GamePlayerActions Capability for given gameID"
            )

            gamePlayerRef.addGameActionsCapability(gameID: gameID, gameActionsCap)
        }

        pub fun signUpForGame(gameID: UInt64) {
            // Derive path to capability
            let gamePrivatePath = PrivatePath(identifier: BattleBlocksGame
                .GamePrivateBasePathString.concat(gameID.toString()))!
            // Get the Capability
            let gameActionsCap = BattleBlocksGame.account
                .getCapability<&{GameActions}>(gamePrivatePath)

            // Ensure Capability is not nil
            assert(
                gameActionsCap.check(),
                message: "Not able to retrieve GameLobbyActions Capability for given gameID!"
            )

            // Add it to the mapping
            self.gameCapabilities.insert(key: gameID, gameActionsCap)

            emit PlayerSignedUp(gameID: gameID, addedPlayerID: self.id)
        }

        pub fun addGameActionsCapability(gameID: UInt64, _ cap: Capability<&{GameActions}>) {
            pre {
                !self.gameCapabilities.containsKey(gameID) && !self.playerCapabilities.containsKey(gameID):
                    "Player alpending has capability for this Game!"
            }
            post {
                self.gameCapabilities.containsKey(gameID): "Capability for game has not been saved into player"
            }

            self.gameCapabilities.insert(key: gameID, cap)
            emit PlayerAdded(gameID: gameID, addedPlayerID: self.id)
        }
    }

    //-------------------//

    //-----Public-----//

    pub fun createGamePlayer(): @GamePlayer {
        return <- create GamePlayer()
    }

    pub fun getGameMoveHistory(id: UInt64): {Address: [[MoveState]]}? {
        let gamePath = self.getGameStoragePath(id)!
        if let gameRef = self.account.borrow<&Game>(from: gamePath) {
            return gameRef.getPlayerMoves()
        }
        return nil
    }

    pub fun getGameStoragePath(_ matchID: UInt64): StoragePath {
        let identifier = self.GameStorageBasePathString.concat(matchID.toString())
        return StoragePath(identifier: identifier)!
    }

    pub fun getGamePrivatePath(_ gameID: UInt64): PrivatePath {
        let identifier = self.GameStorageBasePathString.concat(gameID.toString())
        return PrivatePath(identifier: identifier)!
    }

    pub fun getGameRef(_ id: UInt64): &Game? {
        let gamePath = self.getGameStoragePath(id)
        return self.account.borrow<&Game>(from: gamePath)
    }

    //----------------//

    init() {
        // Assign canonical paths
        self.GamePlayerStoragePath = /storage/BattleBlocksGamePlayer
        self.GamePlayerPublicPath = /public/BattleBlocksGamePlayer
        self.GamePlayerPrivatePath = /private/BattleBlocksGamePlayer
        // Assign base paths for later concatenation
        self.GameStorageBasePathString = "Match"
        self.GamePrivateBasePathString = "Match"
    }
}
 