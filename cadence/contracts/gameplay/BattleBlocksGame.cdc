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
        challenger: Address,
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
        pub let playerA: Address
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
        pub fun depositWager(
            wager: @FlowToken.Vault,
            receiver: Capability<&FlowToken.Vault{FungibleToken.Receiver}>,
            playerAddress: Address
        ): Capability<&{PlayerActions}>
        pub fun getPricePools(): UFix64
        pub fun getGamePlayerIds(): {Address: UInt64}
    }

    pub resource interface GamePlayerID {
        pub let id: UInt64
    }

    pub resource interface PlayerActions {
        pub let id: UInt64
        pub fun getWinningPlayerAddress(): Address?
        pub fun getPlayerGameMoves(playerAddress: Address): {UInt8: MoveState}?
        pub fun submitMove(move: Coordinates, playerAddress: Address)
        pub fun resolveMatch()
    }

    //--------------------//

    //-----Resources-----//

    pub resource Game : GameActions, PlayerActions {
        pub let id: UInt64
        access(contract) var data: GameData
        access(self) let prizePool: @FlowToken.Vault
        access(contract) var gamePlayerIDs: {UInt8: {Address: UInt64}}

        init(data: GameData) {
            self.prizePool <- FlowToken.createEmptyVault() as! @FlowToken.Vault
            self.data = data
            self.id = self.uuid
            self.gamePlayerIDs = {}
        }

        pub fun getGamePlayerIds(): {UInt8: {Address: UInt64}} {
            return self.gamePlayerIDs
        }

        pub fun depositWager(wager: @FlowToken.Vault, merkleRoot: [UInt8], gamePlayerIDRef: &{GamePlayerID}): Capability<&{PlayerActions}> {
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

            let playerB = gamePlayerIDRef.owner?.address!

            let gamePlayerIDtoAddress = {playerB: gamePlayerIDRef.id}

            self.gamePlayerIDs.insert(key: 2, gamePlayerIDtoAddress)

            // Update Game data

            self.data.setPlayerB(gamePlayerIDRef.owner?.address!)
            self.prizePool.deposit(from: <- wager)
            self.data.setTurn(TurnState.playerA)

            emit PlayerJoinedGame(
                gameID: self.id,
                challenger: playerB,
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
                    }
                }       
            } else {
                // First
            }

            // Move
            let playerMoves:[[MoveState]] = self.data.playerMoves[playerAddress] == nil ? [[]] : self.data.playerMoves[playerAddress]!
            playerMoves[coordinates.y][coordinates.x] = MoveState.pending
            self.data.setPlayerMoves(player: playerAddress, moves: playerMoves)

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

        /// This function resolves the Match, demanding that both player moves have been
        /// submitted for resolution to occur
        ///
        pub fun resolveMatch() {
            pre {
                self.submittedMoves.length == 2:
                    "Both players must submit moves before the Match can be resolved!"
                self.inPlay == true:
                    "Match is not in play any longer!"
            }

            // Ensure that match resolution is not called in the same transaction as either move submission
            // to prevent cheating
            assert(
                getCurrentBlock().height > self.submittedMoves[self.submittedMoves.keys[0]]!.submittedHeight &&
                getCurrentBlock().height > self.submittedMoves[self.submittedMoves.keys[1]]!.submittedHeight,
                message: "Too soon after move submission to resolve the match!"
            )
            // Determine the ids of winning GamePlayer.id & NFT.id
            self.winningPlayerID = RockPaperScissorsGame
                .determineRockPaperScissorsWinner(
                    moves: self.submittedMoves
                )
            // Assign winningNFTID to NFT submitted by the winning GamePlayer
            if self.winningPlayerID != nil && self.winningPlayerID != RockPaperScissorsGame.automatedGamePlayer.id {
                self.winningNFTID = self.gamePlayerIDToNFTUUID[self.winningPlayerID!]!
            // If the winning player is the contract's automated player, assign the winningNFTID 
            // to the contract's dummyNFTID
            } else if self.winningPlayerID == RockPaperScissorsGame.automatedGamePlayer.id {
                self.winningNFTID = RockPaperScissorsGame.dummyNFTID
            }

            // Ammend NFTs win/loss data
            for nftID in self.escrowedNFTs.keys {
                RockPaperScissorsGame.updateWinLossRecord(
                    nftUUID: nftID,
                    winner: self.winningNFTID
                )
            }

            // Mark the Match as no longer in play
            self.inPlay = false

            // Announce the Match results
            let player1ID = self.submittedMoves.keys[0]
            let player2ID = self.submittedMoves.keys[1]
            emit MatchOver(
                gameName: RockPaperScissorsGame.name,
                matchID: self.id,
                player1ID: player1ID,
                player1MoveRawValue: self.submittedMoves[player1ID]!.move.rawValue,
                player2ID: player2ID,
                player2MoveRawValue: self.submittedMoves[player2ID]!.move.rawValue,
                winningGamePlayer: self.winningPlayerID,
                winningNFTID: self.winningNFTID
            )
        }

        /** --- MatchLobbyActions & MatchPlayerActions --- */

        /// Can be called by any interface if there's a timeLimit or assets weren't returned
        /// for some reason
        ///
        /// @return An array containing the nft.ids of all NFTs returned to their owners
        ///
        pub fun returnPlayerNFTs(): [UInt64] {
            pre {
                getCurrentBlock().timestamp >= self.createdTimestamp + self.timeLimit ||
                self.inPlay == false:
                    "Cannot return NFTs while Match is still in play!"
            }

            let returnedNFTs: [UInt64] = []
            // Written so that issues with one player's Receiver won't affect the return of
            // any other player's NFT
            for id in self.nftReceivers.keys {
                if let receiverCap: Capability<&{NonFungibleToken.Receiver}> = self.nftReceivers[id] {
                    if let receiverRef = receiverCap.borrow() {
                        // We know we have the proper Receiver reference, so we'll now move the token & deposit
                        if let token <- self.escrowedNFTs.remove(key: id) as! @NonFungibleToken.NFT? {
                            receiverRef.deposit(token: <- token)
                            returnedNFTs.append(id)
                        }
                    }
                }
            }
            // Set inPlay to false in case Match timed out
            self.inPlay = false
            // Add the id of this Match to the history of completed Matches
            // as long as all it does not contain NFTs. Doing so allows the Match to be
            // destroyed to clean up contract account storage
            if self.escrowedNFTs.length == 0 {
                RockPaperScissorsGame.completedMatchIDs.append(self.id)
            }

            emit ReturnedPlayerNFTs(
                gameName: RockPaperScissorsGame.name,
                matchID: self.id,
                returnedNFTs: returnedNFTs
            )
            
            // Return an array containing ids of the successfully returned NFTs
            return returnedNFTs
        }

        /// Function to enable a player to retrieve their NFT should they need to due to failure in
        /// the returnPlayerNFTs() method
        ///
        /// @param gamePlayerIDRef: Reference to the player's GamePlayerID
        /// @param receiver: A Receiver Capability to a resource the NFT will be deposited to
        ///
        pub fun retrieveUnclaimedNFT(
            gamePlayerIDRef: &{GamePlayerID},
            receiver: Capability<&{NonFungibleToken.Receiver}>
        ): UInt64 {
            pre {
                getCurrentBlock().timestamp >= self.createdTimestamp + self.timeLimit ||
                self.inPlay == false:
                    "Cannot return NFTs while Match is still in play!"
                self.gamePlayerIDToNFTUUID.containsKey(gamePlayerIDRef.id):
                    "This GamePlayer is not associated with this Match!"
                self.escrowedNFTs.containsKey(self.gamePlayerIDToNFTUUID[gamePlayerIDRef.id]!):
                    "Player does not have any NFTs escrowed in this Match!"
                receiver.check():
                    "Could not borrow reference to provided Receiver in retrieveUnclaimedNFT()!"
            }
            // Get the NFT from escrow
            let nftID = self.gamePlayerIDToNFTUUID[gamePlayerIDRef.id]!
            let nft <- (self.escrowedNFTs.remove(key: nftID) as! @NonFungibleToken.NFT?)!
            
            // Return the NFT to the given Receiver
            receiver.borrow()!.deposit(token: <-nft)

            // Set inPlay to false in case Match timed out and it wasn't marked
            self.inPlay = false
            // Add the id of this Match to the history of completed Matches
            // as long as all it does not contain NFTs. Doing so allows the Match to be
            // destroyed to clean up contract account storage
            if self.escrowedNFTs.length == 0 {
                RockPaperScissorsGame.completedMatchIDs.append(self.id)
            }

            emit ReturnedPlayerNFTs(
                gameName: RockPaperScissorsGame.name,
                matchID: self.id,
                returnedNFTs: [nftID]
            )

            return nftID
        }

        /** --- Match --- */

        /// Retrieves the submitted moves for the Match, allowing for review of historical gameplay
        ///
        /// @return the mapping of GamePlayerID to SubmittedMove
        ///
        access(contract) fun getSubmittedMoves(): {UInt64: SubmittedMove} {
            pre {
                !self.inPlay:
                    "Cannot get submitted moves until Match is complete!"
            }
            return self.submittedMoves
        }

        destroy() {
            pre {
                self.data.gameState != GameState.complete: 
                    "Cannot destroy while Match is still in play!"
            }
            destroy self.prizePool
        }
    }

    //-------------------//

    //-----Public-----//

    //----------------//






    /** --- Player Related Interfaces --- */

    /// A simple interface a player would use to demonstrate that they are
    /// the given ID
    ///
    pub resource interface GamePlayerID {
        pub let id: UInt64
    }

    /// Public interface allowing others to add GamePlayer to matches. Of course, there is
    /// no obligation for matches to be played, but this makes it so that other players
    /// each other to a Match       
    ///
    pub resource interface GamePlayerPublic {
        pub let id: UInt64
        pub fun addMatchLobbyActionsCapability(
            matchID: UInt64,
            _ cap: Capability<&{MatchLobbyActions}>
        )
        pub fun getAvailableMoves(matchID: UInt64): [Moves]?
        pub fun getMatchesInLobby(): [UInt64]
        pub fun getMatchesInPlay(): [UInt64]
    }

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

    /** --- Receiver for Match Capabilities --- */

    /// Resource that maintains all the player's MatchPlayerActions capabilities
    /// Players can add themselves to games or be added if they expose GamePlayerPublic
    /// capability
    ///
    pub resource GamePlayer : GamePlayerID, GamePlayerPublic {
        pub let id: UInt64
        access(self) let matchLobbyCapabilities: {UInt64: Capability<&{MatchLobbyActions}>}
        access(self) let matchPlayerCapabilities: {UInt64: Capability<&{MatchPlayerActions}>}

        init() {
            self.id = self.uuid
            self.matchPlayerCapabilities = {}
            self.matchLobbyCapabilities = {}
        }
        
        /** --- GamePlayer --- */

        /// Returns a reference to this resource as GamePlayerID
        ///
        /// @return reference to this GamePlayer's GamePlayerID Capability
        ///
        pub fun getGamePlayerIDRef(): &{GamePlayerID} {
            return &self as &{GamePlayerID}
        }

        /// Getter for the GamePlayer's available moves assigned to their escrowed NFT
        ///
        /// @param matchID: Match.id for which they are querying
        ///
        /// @return the Moves assigned to their escrowed NFT
        ///
        pub fun getAvailableMoves(matchID: UInt64): [Moves]? {
            pre {
                self.matchPlayerCapabilities[matchID] != nil:
                    "Player is not engaged with the given Match"
                self.matchPlayerCapabilities[matchID]!.check():
                    "Problem with MatchPlayerMoves Capability for given Match.id!"
            }
            let matchCap = self.matchPlayerCapabilities[matchID]!
            return matchCap.borrow()!.getNFTGameMoves(forPlayerID: self.id)
        }

        /// Getter for the ids of Matches for which player has MatchLobbyActions Capabilies
        ///
        /// @return ids of Matches for which player has MatchLobbyActions Capabilies
        ///
        pub fun getMatchesInLobby(): [UInt64] {
            return self.matchLobbyCapabilities.keys
        }

        /// Getter for the ids of Matches for which player has MatchPlayerActions Capabilies
        ///
        /// @return ids of Matches for which player has MatchPlayerActions Capabilies
        ///
        pub fun getMatchesInPlay(): [UInt64] {
            return self.matchPlayerCapabilities.keys
        }

        /// Simple getter for mapping of MatchLobbyActions Capabilities
        ///
        /// @return mapping of Match.id to MatchLobbyActions Capabilities
        ///
        pub fun getMatchLobbyCaps(): {UInt64: Capability<&{MatchLobbyActions}>} {
            return self.matchLobbyCapabilities
        }

        /// Simple getter for mapping of MatchPlayerActions Capabilities
        ///
        /// @return mapping of Match.id to MatchPlayerActions Capabilities
        ///
        pub fun getMatchPlayerCaps(): {UInt64: Capability<&{MatchPlayerActions}>} {
            return self.matchPlayerCapabilities
        }

        /// Allows GamePlayer to delete capabilities from their mapping to free up space used
        /// by old matches.
        ///
        /// @param matchID: The id for the MatchLobbyActions Capability that the GamePlayer 
        /// would like to delete from their matchLobbyCapabilities
        ///
        pub fun deleteLobbyActionsCapability(matchID: UInt64) {
            self.matchLobbyCapabilities.remove(key: matchID)
        }

        /// Allows GamePlayer to delete capabilities from their mapping to free up space used
        /// by old matches.
        ///
        /// @param matchID: The id for the MatchPlayerActions Capability that the GamePlayer 
        /// would like to delete from their matchPlayerCapabilities
        ///
        pub fun deletePlayerActionsCapability(matchID: UInt64) {
            self.matchPlayerCapabilities.remove(key: matchID)
        }

        /// Creates a new Match resource, saving it in the contract account's storage
        /// and linking MatchPlayerActions at a dynamic path derived with the Match.id.
        /// Creating a match requires an NFT and Receiver Capability to mitigate spam
        /// vector where an attacker creates an exorbitant number of Matches.
        ///
        /// @param matchTimeLimit: Time before players have right to retrieve their
        /// escrowed NFTs
        /// 
        /// @return: Match.id of the newly created Match
        ///
        pub fun createMatch(
            multiPlayer: Bool,
            matchTimeLimit: UFix64,
            nft: @AnyResource{NonFungibleToken.INFT, DynamicNFT.Dynamic},
            receiverCap: Capability<&{NonFungibleToken.Receiver}>
        ): UInt64 {
            pre {
                receiverCap.check(): 
                    "Problem with provided Receiver Capability!"
            }
            // Create the new match & preserve its ID
            let newMatch <- create Match(matchTimeLimit: matchTimeLimit, multiPlayer: multiPlayer)
            let newMatchID = newMatch.id
            
            // Derive paths using matchID
            let matchStoragePath = RockPaperScissorsGame.getMatchStoragePath(newMatchID)
            let matchPrivatePath = RockPaperScissorsGame.getGamePrivatePath(newMatchID)
            
            // Save the match to game contract account's storage
            RockPaperScissorsGame.account.save(<-newMatch, to: matchStoragePath)
            
            // Link each Capability to game contract account's private
            RockPaperScissorsGame.account.link<&{
                MatchLobbyActions,
                MatchPlayerActions
            }>(
                matchPrivatePath,
                target: matchStoragePath
            )

            // Get the MatchLobbyActions Capability we just linked
            let lobbyCap = RockPaperScissorsGame.account
                .getCapability<&{
                    MatchLobbyActions
                }>(
                    matchPrivatePath
                )
            // Add that Capability to the GamePlayer's mapping
            self.matchLobbyCapabilities[newMatchID] = lobbyCap

            // Deposit the specified NFT to the new Match & return the Match.id
            self.depositNFTToMatchEscrow(nft: <-nft, matchID: newMatchID, receiverCap: receiverCap)

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

        /// Allows for GamePlayer to sign up for a match that alpending exists. Doing so retrieves the 
        /// MatchPlayerActions Capability from the contract account's private storage and add
        /// it to the GamePlayers mapping of Capabilities.
        ///
        /// @param matchID: The id of the Match for which they want to retrieve the
        /// MatchPlayerActions Capability
        ///
        pub fun signUpForMatch(matchID: UInt64) {
            // Derive path to capability
            let matchPrivatePath = PrivatePath(identifier: RockPaperScissorsGame
                .MatchPrivateBasePathString.concat(matchID.toString()))!
            // Get the Capability
            let matchLobbyActionsCap = RockPaperScissorsGame.account
                .getCapability<&{MatchLobbyActions}>(matchPrivatePath)

            // Ensure Capability is not nil
            assert(
                matchLobbyActionsCap.check(),
                message: "Not able to retrieve MatchLobbyActions Capability for given matchID!"
            )

            // Add it to the mapping
            self.matchLobbyCapabilities.insert(key: matchID, matchLobbyActionsCap)

            emit PlayerSignedUpForMatch(gameName: RockPaperScissorsGame.name, matchID: matchID, addedPlayerID: self.id)
        }

        /// Allows for NFTs to be taken from GamePlayer's Collection and escrowed into the given Match.id
        /// using the MatchPlayerActions Capability alpending in their mapping
        ///
        /// @param nft: The NFT to be escrowed
        /// @param matchID: The id of the Match into which the NFT will be escrowed
        /// @param receiverCap: The Receiver Capability to which the NFT will be returned
        ///
        pub fun depositNFTToMatchEscrow(
            nft: @AnyResource{NonFungibleToken.INFT, DynamicNFT.Dynamic},
            matchID: UInt64,
            receiverCap: Capability<&{NonFungibleToken.Receiver}>
        ) {
            pre {
                receiverCap.check(): 
                    "Problem with provided Receiver Capability!"
                self.matchLobbyCapabilities.containsKey(matchID) &&
                !self.matchPlayerCapabilities.containsKey(matchID):
                    "GamePlayer does not have the Capability to play this Match!"
            }
            post {
                self.matchPlayerCapabilities.containsKey(matchID):
                    "MatchPlayerActions Capability not successfully added!"
                !self.matchLobbyCapabilities.containsKey(matchID) &&
                self.matchPlayerCapabilities.containsKey(matchID):
                    "GamePlayer does not have the Capability to play this Match!"
            }
            
            // Ensure the Capability is valid
            assert(
                receiverCap.check(),
                message: "Could not access Receiver Capability at the given path for this account!"
            )
            
            // Get the MatchPlayerActions Capability from this GamePlayer's mapping
            let matchLobbyCap: Capability<&{MatchLobbyActions}> = self.matchLobbyCapabilities[matchID]!
            let matchLobbyActionsRef = matchLobbyCap
                .borrow()
                ?? panic("Could not borrow reference to MatchPlayerActions")

            // Escrow the NFT to the Match, getting back a Capability
            let playerActionsCap: Capability<&{MatchPlayerActions}> = matchLobbyActionsRef
                .escrowNFTToMatch(
                    nft: <-nft,
                    receiver: receiverCap,
                    gamePlayerIDRef: &self as &{GamePlayerID}
                )
            // Add that Capability to the GamePlayer's mapping & remove from
            // mapping of MatchLobbyCapabilities
            self.matchPlayerCapabilities.insert(key: matchID, playerActionsCap)
            self.matchLobbyCapabilities.remove(key: matchID)
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
 