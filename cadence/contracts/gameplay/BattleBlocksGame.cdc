import FungibleToken from "../standard/FungibleToken.cdc"
import FlowToken from "../standard/FlowToken.cdc"

pub contract BattleBlocksGame {

    //-----Paths-----//

    pub let GamePlayerStoragePath: StoragePath
    pub let GamePlayerPublicPath: PublicPath
    pub let GamePlayerPrivatePath: PrivatePath

    pub let MatchStorageBasePathString: String
    pub let MatchPrivateBasePathString: String

    //--------------//

    //-----Variables-----//

    //------------------//

    //-----Events-----//

    pub event PlayerJoinedGame(
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

    pub event GameOver (
        gameID: UInt64,
        playerA: Address,
        playerB: Address,
        winner: Address?,
        playerHitCount: {Address: UInt8}
    )

    pub event Moved(
        gameID: UInt64,
        gamePlayerID: UInt64,
        playerAddress: Address,
        coordinateX: UInt64,
        coordinateY: UInt64
    )

    pub event NewMatchCreated(gameName: String, matchID: UInt64, creatorID: UInt64)

    pub event PlayerSignedUpForMatch(gameName: String, matchID: UInt64, addedPlayerID: UInt64)

    pub event MatchOver(
        gameName: String,
        matchID: UInt64,
        player1ID: UInt64,
        player1MoveRawValue: UInt8,
        player2ID: UInt64,
        player2MoveRawValue: UInt8,
        winningGamePlayer: UInt64?,
        winningNFTID: UInt64?
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

        access(contract) fun setPlayerBMerkpleRoot(_ playerBMerkleRoot: [UInt8]) {
            self.playerBMerkleRoot = playerBMerkleRoot
        }

        access(contract) fun setTurn(_ nextTurn: TurnState){
            self.turn = nextTurn
        }
        
        access(contract) fun setPlayerMoves (player: Address, moves: [[MoveState]]) {
            self.playerMoves[player] = moves
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
        pub fun addMatchLobbyActionsCapability(
            matchID: UInt64,
            _ cap: Capability<&{GameActions}>
        )
        pub fun getMatchesInLobby(): [UInt64]
        pub fun getMatchesInPlay(): [UInt64]
    }

    //--------------------//

    //-----Resources-----//

    pub resource Game : GameActions, PlayerActions {
        pub let id: UInt64
        access(contract) var data: GameData
        access(self) let prizePool: @FlowToken.Vault
        access(contract) var gamePlayerIDs: {UInt8: {Address: UInt64}}

        init(
            wager: @FlowToken.Vault,
            playerAMerkleRoot: [UInt8],
            gamePlayerIDRef: &{GamePlayerID}
            ) {
            self.data = GameData(
                wager: wager.balance,
                playerA: gamePlayerIDRef.owner?.address!,
                playerAMerkleRoot: playerAMerkleRoot
                )
            self.prizePool <- wager
            self.id = self.uuid
            self.gamePlayerIDs = {}
            let gamePlayerIDtoAddress = {gamePlayerIDRef.owner?.address!: gamePlayerIDRef.id}
            self.gamePlayerIDs.insert(key: 1, gamePlayerIDtoAddress)
        }

        pub fun getGamePlayerIds(): {UInt8: {Address: UInt64}} {
            return self.gamePlayerIDs
        }

        pub fun getPrizePool(): UFix64 {
            return self.prizePool.balance
        }

        pub fun joinGame(wager: @FlowToken.Vault, merkleRoot: [UInt8], gamePlayerIDRef: &{GamePlayerID}): Capability<&{PlayerActions}> {
            pre {
                !(self.data.playerA == gamePlayerIDRef.owner?.address || self.data.playerB == gamePlayerIDRef.owner?.address):
                    "Player has alpending joined this Game!"
                wager.balance == self.data.wager:
                    "Invalid wager amount!"
                self.prizePool.balance != self.data.wager * 2.0:
                    "Prize pool has alpending been filled"
                self.data.gameState == GameState.pending:
                    "Game alpending started!"
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

            if (playerAddress == self.data.playerA) {
                playerIndex = TurnState.playerA.rawValue
                self.data.setPlayerA(gamePlayerIDRef.owner?.address!)
            } else if (playerAddress == self.data.playerB) {
                playerIndex = TurnState.playerB.rawValue
                self.data.setPlayerB(gamePlayerIDRef.owner?.address!)
                self.data.setTurn(TurnState.playerA)
            } else {
                panic ("Invalid player address")
            }
            
            self.prizePool.deposit(from: <- wager)

            self.gamePlayerIDs.insert(key: playerIndex, gamePlayerIDtoAddress)

            // Update Game data

            emit PlayerJoinedGame(
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
            } else if (playerAddress == self.data.playerB) {
                previousPlayer = self.data.playerA
                currentPlayerMerkleRoot = self.data.playerBMerkleRoot
            } else {
                panic ("Invalid player address")
            }

            // Move
            let playerMoves:[[MoveState]] = self.data.playerMoves[playerAddress] == nil ? [[]] : self.data.playerMoves[playerAddress]!
            playerMoves[coordinates.y][coordinates.x] = MoveState.pending
            self.data.setPlayerMoves(player: playerAddress, moves: playerMoves)

            if !(self.data.playerMoves[self.data.playerMoves.keys[0]]?.length != nil && self.data.playerMoves[self.data.playerMoves.keys[1]]?.length != nil) {
                // Not First

                // Proof for Last Guess
                let guessCoordinates = self.data.getLatestPlayerGuess(player: previousPlayer!)!
                if !(reveal!.guess.coodinates.x == guessCoordinates.x && reveal!.guess.coodinates.y == guessCoordinates.y) {
                    panic ("Invalid coordinates revealed")
                } else {
                    if !(self.proveGuess(playerMerkleRoot: currentPlayerMerkleRoot, proof: proof!, reveal: reveal!)) {
                        panic ("Failed prooving guess")
                    } else {
                        let previousPlayerMoves:[[MoveState]] = self.data.playerMoves[previousPlayer!] == nil ? [[]] : self.data.playerMoves[previousPlayer!]!
                        if (reveal!.guess.isBlock) {
                            previousPlayerMoves[coordinates.y][coordinates.x] = MoveState.hit
                            if (self.data.increaseHitCount(player: previousPlayer!)) {
                                // Game Over
                                emit GameOver(
                                    gameID: self.id,
                                    playerA: self.data.playerA,
                                    playerB: self.data.playerB!,
                                    winner: self.data.winner,
                                    playerHitCount: self.data.playerHitCount
                                )
                            } 
                        } else {
                            previousPlayerMoves[coordinates.y][coordinates.x] = MoveState.miss
                        }
                    }
                }       
            } else {
                // First

                // No need proof Last Guess
            }

            // Guess
            self.data.playerGuess(player: playerAddress, guess: coordinates)  

            emit Moved(
                gameID: self.id,
                gamePlayerID: gamePlayerIDRef.id,
                playerAddress: playerAddress,
                coordinateX: coordinates.x,
                coordinateY: coordinates.y
                )
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

    //-------------------//

    //-----Public-----//

    //----------------//

    /// A resource interface allowing a user to delegate use of their GamePlayer
    /// via Capability
    ///
    pub resource interface DelegatedGamePlayer {
        pub let id: UInt64
        pub fun getGamePlayerIDRef(): &{GamePlayerID}
        pub fun getMatchesInLobby(): [UInt64]
        pub fun getMatchesInPlay(): [UInt64]
        pub fun getMatchLobbyCaps(): {UInt64: Capability<&{GameActions}>}
        pub fun getMatchPlayerCaps(): {UInt64: Capability<&{PlayerActions}>}
        pub fun deleteLobbyActionsCapability(matchID: UInt64)
        pub fun deletePlayerActionsCapability(matchID: UInt64)
        pub fun createMatch(
            multiPlayer: Bool,
            matchTimeLimit: UFix64,
            nft: @AnyResource{NonFungibleToken.INFT},
            receiverCap: Capability<&{NonFungibleToken.Receiver}>
        ): UInt64
        pub fun signUpForMatch(matchID: UInt64)
        pub fun depositNFTToMatchEscrow(
            nft: @AnyResource{NonFungibleToken.INFT, DynamicNFT.Dynamic},
            matchID: UInt64,
            receiverCap: Capability<&{NonFungibleToken.Receiver}>
        )
        pub fun submitMoveToMatch(matchID: UInt64, move: Moves)
        pub fun addPlayerToMatch(matchID: UInt64, gamePlayerRef: &AnyResource{GamePlayerPublic})
        pub fun resolveMatchByID(_ id: UInt64)
        pub fun addMatchLobbyActionsCapability(matchID: UInt64, _ cap: Capability<&{MatchLobbyActions}>)
    }

    pub resource GamePlayer : GamePlayerID, GamePlayerPublic {
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

        pub fun getPlayerCapibilities(): {UInt64: Capability<&{PlayerActions}>} {
            return self.playerCapabilities
        }

        pub fun deleteGameActionsCapability(matchID: UInt64) {
            self.gameCapabilities.remove(key: matchID)
        }

        pub fun deletePlayerActionsCapability(matchID: UInt64) {
            self.playerCapabilities.remove(key: matchID)
        }

        pub fun createMatch(wager: @FlowToken.Vault, playerAMerkleRoot: [UInt8]): UInt64 {
            let gamePlayerIDRef = self.getGamePlayerIDRef()

            let newGame <- create Game(data: game)
        
            let newGameID = newGame.id
            
            // Derive paths using matchID
            let gameStoragePath = BattleBlocksGame.getMatchStoragePath(newGameID)
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

            let gameCap: Capability<&{GameActions}> = self.gameCapabilities[newGameID]!
            let gameActionsRef = gameCap
                .borrow()
                ?? panic("Could not borrow reference to GameActions")

            let playerActionsCap: Capability<&{PlayerActions}> = gameActionsRef.joinGame(wager: <- wager, merkleRoot: merkleRoot, gamePlayerIDRef: gamePlayerIDRef)
                    
            // Add that Capability to the GamePlayer's mapping & remove from
            // mapping of MatchLobbyCapabilities
            self.matchPlayerCapabilities.insert(key: matchID, playerActionsCap)
            self.matchLobbyCapabilities.remove(key: matchID)
                
            // Get the GameActions Capability from this GamePlayer's mapping
            let gameActionsCap: Capability<&{GameActions}> = self.gameCapabilities[newGameID]!
            let gameActionsRef = gameActionsCap
                .borrow()
                ?? panic("Could not borrow reference to GamePlayerActions")


            let playerActionsCap: Capability<&{PlayerActions}> = gameActionsRef
    
            // Add that Capability to the GamePlayer's mapping & remove from
            // mapping of MatchLobbyCapabilities
            self.matchPlayerCapabilities.insert(key: matchID, playerActionsCap)
            self.matchLobbyCapabilities.remove(key: matchID)

            // Remove the MatchLobbyActions now that the NFT has been escrowed & return the Match.id
            self.matchLobbyCapabilities.remove(key: newMatchID)



            emit NewMatchCreated(
                gameName: RockPaperScissorsGame.name,
                matchID: newMatchID,
                creatorID: self.id,
                isMultiPlayer: multiPlayer
            )
            return newMatchID
        }

        pub fun signUpForGame(gameID: UInt64) {

            // Derive path to capability
            let gamePrivatePath = PrivatePath(identifier: BattleBlocksGame
                .GamePrivateBasePathString.concat(gameID.toString()))!

            // Get the Capability
            let matchLobbyActionsCap = BattleBlocksGame.account
                .getCapability<&{GameActions}>(gamePrivatePath)

            // Ensure Capability is not nil
            assert(
                matchLobbyActionsCap.check(),
                message: "Not able to retrieve GameActions Capability for given gameID!"
            )

            // Add it to the mapping
            self.gameCapabilities.insert(key: gameID, gameActionsCap)

            emit PlayerSignedUpForMatch(matchID: matchID, addedPlayerID: self.id)
        }

        

        /// Allows the GamePlayer to submit a move to the provided Match.id
        ///
        /// @param matchID: Match.id of the Match into which the move will be submitted
        /// @param move: The move to be played
        ///
        pub fun submitMoveToMatch(matchID: UInt64, move: Moves) {
            pre {
                self.matchPlayerCapabilities.containsKey(matchID):
                    "Player does not have the ability to play this Match!"
                self.matchPlayerCapabilities[matchID]!.check():
                    "Problem with the MatchPlayerActions Capability for given Match!"
            }
            let matchRef = self.matchPlayerCapabilities[matchID]!.borrow()!
            let gamePlayerIDRef = self.getGamePlayerIDRef()
            matchRef.submitMove(move: move, gamePlayerIDRef: gamePlayerIDRef)
        }

        /// Adds the referenced GamePlayer to the Match defined by the given Match.id by retrieving
        /// the associated Match's MatchPlayerActions Capability and passing it as a parameter to
        /// GamePlayerPublic.addMatchPlayerActionsCapability() along with the Match.id
        ///
        /// @param matchID: The id of the associated Match
        /// @param gamePlayerRef: Reference to GamePlayerPublic that will receive
        /// a MatchPlayerResource Capability
        ///
        pub fun addPlayerToMatch(matchID: UInt64, gamePlayerRef: &AnyResource{GamePlayerPublic}) {
            // Derive match's private path from matchID
            let matchPrivatePath = RockPaperScissorsGame.getGamePrivatePath(matchID)
            // Get the capability
            let matchLobbyActionsCap: Capability<&AnyResource{MatchLobbyActions}> = RockPaperScissorsGame.account
                .getCapability<&{MatchLobbyActions}>(matchPrivatePath)

            // Ensure we actually got the Capability we need
            assert(
                matchLobbyActionsCap.check(),
                message: "Not able to retrieve MatchPlayerActions Capability for given matchID"
            )

            // Add it to the player's matchPlayerCapabilities
            gamePlayerRef.addMatchLobbyActionsCapability(matchID: matchID, matchLobbyActionsCap)
        }

        /// This method allows a player to call for a match to be resolved. Note that the called 
        /// method Match.resolveMatch() requires that both moves be submitted for resolution to occur
        /// and that the method be called at least one block after the last move was submitted.
        ///
        /// @param id: The id of the Match to be resolved.
        ///
        pub fun resolveMatchByID(_ id: UInt64) {
            pre {
                self.matchPlayerCapabilities.containsKey(id):
                    "Player does not have the ability to play this Match!"
                self.matchPlayerCapabilities[id]!.check():
                    "Problem with the MatchPlayerActions Capability for given Match!"
            }
            let matchRef = self.matchPlayerCapabilities[id]!.borrow()!
            let gamePlayerIDRef = self.getGamePlayerIDRef()
            matchRef.resolveMatch()
        }

        /** --- GamePlayerPublic --- */

        /// Allows others to add MatchPlayerActions Capabilities to their mapping for ease of Match setup.
        ///
        /// @param matchID: The id associated with the MatchPlayerActions the GamePlayer is being given access
        /// @param cap: The MatchPlayerActions Capability for which the GamePlayer is being given access
        ///
        pub fun addMatchLobbyActionsCapability(matchID: UInt64, _ cap: Capability<&{MatchLobbyActions}>) {
            pre {
                !self.matchLobbyCapabilities.containsKey(matchID) && !self.matchPlayerCapabilities.containsKey(matchID):
                    "Player alpending has capability for this Match!"
            }
            post {
                self.matchLobbyCapabilities.containsKey(matchID): "Capability for match has not been saved into player"
            }

            self.matchLobbyCapabilities.insert(key: matchID, cap)
            // Event that could be used to notify player they were added
            emit PlayerAddedToMatch(gameName: RockPaperScissorsGame.name, matchID: matchID, addedPlayerID: self.id)
        }
    }

    /** --- Contract helper functions --- */

    /// Getter to identify the contract's automated GamePlayer.id
    ///
    /// @return the id of the contract's GamePlayer used for singleplayer Matches
    ///    
    pub fun getAutomatedPlayerID(): UInt64 {
        return self.automatedGamePlayer.id
    }

    /// Getter to identify the contract's dummyNFTID
    ///
    /// @return the contract's dummyNFTID used for singleplayer Matches
    ///
    pub fun getDummyNFTID(): UInt64 {
        return self.dummyNFTID
    }

    /// Create a GamePlayer resource
    ///
    /// @return a fresh GamePlayer resource
    ///
    pub fun createGamePlayer(): @GamePlayer {
        return <- create GamePlayer()
    }

    /// Method to determine outcome of a RockPaperScissors with given moves
    /// Exposing game logic allows for some degree of composability with other
    /// games and match types
    ///
    /// @param moves: a mapping of GamePlayer.id to Moves (rock, paper, or scissors)
    /// with the expectation that there are exactly two entries
    ///
    /// @return the id of the winning GamePlayer or nil if result is a tie
    ///
    pub fun determineRockPaperScissorsWinner(moves: {UInt64: SubmittedMove}): UInt64? {
        pre {
            moves.length == 2: "RockPaperScissors requires two moves"
        }
        
        let player1 = moves.keys[0]
        let player2 = moves.keys[1]

        // Choose one move to compare against other
        switch moves[player1]!.move {
            case RockPaperScissorsGame.Moves.rock:
                if moves[player2]!.move == RockPaperScissorsGame.Moves.paper {
                    return player2
                } else if moves[player2]!.move == RockPaperScissorsGame.Moves.scissors {
                    return player1
                }
            case RockPaperScissorsGame.Moves.paper:
                if moves[player2]!.move == RockPaperScissorsGame.Moves.rock {
                    return player1
                } else if moves[player2]!.move == RockPaperScissorsGame.Moves.scissors {
                    return player2
                }
            case RockPaperScissorsGame.Moves.scissors:
                if moves[player2]!.move == RockPaperScissorsGame.Moves.rock {
                    return player2
                } else if moves[player2]!.move == RockPaperScissorsGame.Moves.paper {
                    return player1
                }
        }
        // If they played the same move, it's a tie -> return nil
        return nil
    }

    /// Get GamingMetadataViews.BasicWinLoss for a certain NFT 
    ///
    /// @param: nftUUID: uuid of associated NFT in winLossRecords (nft.id based on updated NFTv2 standard)
    ///
    pub fun getWinLossRecord(nftUUID: UInt64): GamingMetadataViews.BasicWinLoss? {
        return self.winLossRecords[nftUUID]
    }

    /// Getter method for winLossRecords
    ///
    /// @return A Mapping of GamingMetadataViews.BasicWinLoss struct defining the
    /// total win/loss/tie record of the nft.uuid (nft.id based on updated NFTv2 standard)
    /// on which it's indexed
    ///
    pub fun getTotalWinLossRecords(): {UInt64: GamingMetadataViews.BasicWinLoss} {
        return self.winLossRecords
    }

    /// Getter method for historical gameplay history on a specified Match
    ///
    /// @param id: the Match.id for which the mapping is to be retrieved
    ///
    /// @return a mapping of GamePlayerID to SubmittedMove for the given Match or nil
    /// if the Match does not exist in storage
    ///
    pub fun getMatchMoveHistory(id: UInt64): {UInt64: SubmittedMove}? {
        let matchPath = self.getMatchStoragePath(id)!
        if let matchRef = self.account.borrow<&Match>(from: matchPath) {
            return matchRef.getSubmittedMoves()
        }
        return nil
    }

    /// Function for easy derivation of a Match's StoragePath. Provides no guarantees
    /// that a Match is stored there.
    ///
    /// @param matchID: the id of the target Match
    ///
    /// @return the StoragePath where that Match would be stored
    ///
    pub fun getMatchStoragePath(_ matchID: UInt64): StoragePath {
        let identifier = self.MatchStorageBasePathString.concat(matchID.toString())
        return StoragePath(identifier: identifier)!
    }

    /// Function for easy derivation of a Match's PrivatePath. Provides no guarantees
    /// that a Match is stored there.
    ///
    /// @param matchID: the id of the target Match
    ///
    /// @return the PrivatePath where that Match would be stored
    ///
    pub fun getGamePrivatePath(_ matchID: UInt64): PrivatePath {
        let identifier = self.MatchStorageBasePathString.concat(matchID.toString())
        return PrivatePath(identifier: identifier)!
    }

    /// Utility function allowing the public to clean up Matches that are no 
    /// longer necessary, helping to reduce contract's storage usage
    ///
    pub fun destroyCompletedMatches(): [UInt64] {
        
        let destroyedMatchIDs: [UInt64] = []
        // Iterate through completedMatchIDs
        for matchID in self.completedMatchIDs {
            // Derive the StoragePath of the Match with given id
            let matchStoragePath = self.getMatchStoragePath(matchID)
                
            // Load and destroy the Match
            let completedMatch <- self.account.load<@Match>(from: matchStoragePath)
            destroy completedMatch
            
            // Remove the id of the destroyed Match, adding to array
            // maintaining destroyed IDs
            destroyedMatchIDs.append(self.completedMatchIDs.removeFirst())
        }
        // Return the IDs of the destroyed Matches
        return destroyedMatchIDs
    }

    init() {
        // Initialize variables
        self.name = "RockPaperScissors"
        // TODO: Replace with actual values
        self.info = GamingMetadataViews.GameContractMetadata(
            name: self.name,
            description: "Rock, Paper, Scissors on-chain!",
            icon: MetadataViews.HTTPFile(
                url: "https://static.vecteezy.com/system/resources/previews/000/691/500/large_2x/rock-paper-scissors-vector-icons.jpg"
            ),
            thumbnail: MetadataViews.HTTPFile(
                url: "https://miro.medium.com/max/1400/0*pwDqZoXvHo79MoT7.webp"
            ),
            contractAddress: self.account.address,
            externalURL: MetadataViews.ExternalURL(
                "https://www.cheezewizards.com/"
            )
        )
        self.winLossRecords = {}
        self.completedMatchIDs = []

        // Assign canonical paths
        self.GamePlayerStoragePath = /storage/RockPaperScissorsGamePlayer
        self.GamePlayerPublicPath = /public/RockPaperScissorsGamePlayer
        self.GamePlayerPrivatePath = /private/RockPaperScissorsGamePlayer
        // Assign base paths for later concatenation
        self.MatchStorageBasePathString = "Match"
        self.MatchPrivateBasePathString = "Match"

        // Create a contract GamePlayer to automate second player moves in single player modes
        self.automatedGamePlayer <-create GamePlayer()
        self.dummyNFTID = 0
    }
}
 