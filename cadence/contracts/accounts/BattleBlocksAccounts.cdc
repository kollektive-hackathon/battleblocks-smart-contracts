import FungibleToken from "../standard/FungibleToken.cdc"
import FlowToken from "../standard/FlowToken.cdc"

pub contract BattleBlocksAccounts {

    //-----Events-----//

    pub event AccountCreated(originatingPublicKey: String, address: Address)
    pub event AccountDelegated(address: Address, originatingPublicKey: String, parent: Address)

    //--------------//

    //-----Paths-----//

    pub let AuthAccountCapabilityPath: CapabilityPath
    pub let BattleBlocksAccountManagerStoragePath: StoragePath
    pub let BattleBlocksAccountManagerPublicPath: PublicPath
    pub let BattleBlocksAccountManagerPrivatePath: PrivatePath
    pub let BattleBlocksAccountStoragePath: StoragePath
    pub let BattleBlocksAccountPublicPath: PublicPath
    pub let BattleBlocksAccountPrivatePath: PrivatePath
    pub let BattleBlocksAccountCreatorStoragePath: StoragePath
    pub let BattleBlocksAccountCreatorPublicPath: PublicPath

    //--------------//

    //-----Interfaces-----//

    /// Account
    ///
    pub resource interface BattleBlocksAccountPublic {
        pub let originatingPublicKey: String
        pub var parentAddress: Address?
        pub let address: Address
        pub fun getGrantedCapabilityTypes(): [Type]
        pub fun isCurrentlyActive(): Bool
    }

    /// Manager
    ///
    ///
    pub resource interface BattleBlocksAccountManagerPublic {
        pub fun getBattleBlocksAccountAddresses(): [Address]
        pub fun getBattleBlocksAccountMetadata(address: Address): {String: AnyStruct}?
    }

    //--------------------//

    //-----Resources-----//

    /// (Child) Account Resource
    /// 
    pub resource BattleBlocksAccount : BattleBlocksAccountPublic {
        pub let originatingPublicKey: String
        pub var parentAddress: Address?
        pub let address: Address
        access(contract) let grantedCapabilities: {Type: Capability}
        access(contract) var isActive: Bool

        init(
            originatingPublicKey: String,
            parentAddress: Address?,
            address: Address,
        ) {
            self.originatingPublicKey = originatingPublicKey
            self.parentAddress = parentAddress
            self.address = address
            self.grantedCapabilities = {}
            self.isActive = true
        }

        pub fun getGrantedCapabilityTypes(): [Type] {
            return self.grantedCapabilities.keys
        }
        
        pub fun isCurrentlyActive(): Bool {
            return self.isActive
        }


        pub fun getGrantedCapabilityAsRef(_ type: Type): &Capability? {
            pre {
                self.isActive: "BattleBlocksAccount has been de-permissioned by parent!"
            }
            return &self.grantedCapabilities[type] as &Capability?
        }

        access(contract) fun assignParent(address: Address) {
            pre {
                self.parentAddress == nil:
                    "Parent has already been assigned to this BattleBlocksAccount as ".concat(self.parentAddress!.toString())
            }
            self.parentAddress = address
        }

        access(contract) fun grantCapability(_ cap: Capability) {
            pre {
                !self.grantedCapabilities.containsKey(cap.getType()):
                    "Already granted Capability of given type!"
            }
            self.grantedCapabilities.insert(key: cap.getType(), cap)
        }

        access(contract) fun revokeCapability(_ type: Type): Capability? {
            return self.grantedCapabilities.remove(key: type)
        }

        access(contract) fun setInactive() {
            self.isActive = false
        }
    }

    /// Account Controller
    ///
    pub resource BattleBlocksAccountController {
        
        access(self) let authAccountCapability: Capability<&AuthAccount>
        access(self) var BattleBlocksAccountCapability: Capability<&BattleBlocksAccount>

        init(
            authAccountCap: Capability<&AuthAccount>,
            BattleBlocksAccountCap: Capability<&BattleBlocksAccount>
        ) {
            self.authAccountCapability = authAccountCap
            self.BattleBlocksAccountCapability = BattleBlocksAccountCap
        }

        /// Store the child account capability
        ///
        pub fun setChildCapability (childCapability: Capability<&BattleBlocksAccount>) {
            self.BattleBlocksAccountCapability = childCapability
        }

        /// Get a reference to the child AuthAccount object.
        ///
        pub fun getAuthAcctRef(): &AuthAccount? {
            return self.authAccountCapability.borrow()
        }

        pub fun getAccountRef(): &BattleBlocksAccount? {
            return self.BattleBlocksAccountCapability.borrow()
        }

        pub fun getPublicRef(): &{BattleBlocksAccountPublic}? {
            return self.BattleBlocksAccountCapability.borrow()
        }
    }

    // Account Creator
    // 
    pub resource BattleBlocksAccountCreator {
        /// Creates a BattleBlocksAccount from the publicKey 
        /// and funds it with the initial funding amount
        pub fun createBattleBlocksAccount(
            signer: AuthAccount,
            initialFundingAmount: UFix64,
            originatingPublicKey: String): AuthAccount {
            
            // Create the child account
            let newAccount = AuthAccount(payer: signer)

            // Create a public key for the proxy account from the passed in string
            let key = PublicKey(
                publicKey: originatingPublicKey.decodeHex(),
                signatureAlgorithm: SignatureAlgorithm.ECDSA_P256
            )
            
            // Add the key to the new account
            newAccount.keys.add(
                publicKey: key,
                hashAlgorithm: HashAlgorithm.SHA2_256,
                weight: 1000.0
            )

            // Add some initial funds to the new account, pulled from the signing account.  Amount determined by initialFundingAmount
            newAccount.getCapability<&FlowToken.Vault{FungibleToken.Receiver}>(/public/flowTokenReceiver)
                .borrow()!
                .deposit(
                    from: <- signer.borrow<&{
                        FungibleToken.Provider
                    }>(
                        from: /storage/flowTokenVault
                    )!.withdraw(amount: initialFundingAmount)
                )

            // Create the BattleBlocksAccount for the new account
            let child <-create BattleBlocksAccount(
                    originatingPublicKey: originatingPublicKey,
                    parentAddress: nil,
                    address: newAccount.address
                )

            // Save the BattleBlocksAccount in the child account's storage & link
            newAccount.save(<-child, to: BattleBlocksAccounts.BattleBlocksAccountStoragePath)

            newAccount.link<&{BattleBlocksAccountPublic}>(
                BattleBlocksAccounts.BattleBlocksAccountPublicPath,
                target: BattleBlocksAccounts.BattleBlocksAccountStoragePath
            )
            newAccount.link<&BattleBlocksAccount>(
                BattleBlocksAccounts.BattleBlocksAccountPrivatePath,
                target: BattleBlocksAccounts.BattleBlocksAccountStoragePath
            )

            emit AccountCreated(originatingPublicKey: originatingPublicKey, address: newAccount.address)

            return newAccount
        }
    }

    // Account Manager
    //
    pub resource BattleBlocksAccountManager: BattleBlocksAccountManagerPublic {

        pub let BattleBlocksAccounts: @{Address: BattleBlocksAccountController}

        init() {
            self.BattleBlocksAccounts <- {}
        }

        pub fun getBattleBlocksAccountAddresses(): [Address] {
            return self.BattleBlocksAccounts.keys
        }

        pub fun getBattleBlocksAccountControllerRef(address: Address): &BattleBlocksAccountController? {
            return &self.BattleBlocksAccounts[address] as &BattleBlocksAccountController?
        }

        pub fun getBattleBlocksAccountAuthRef(address: Address): &AuthAccount? {
            if let controllerRef = self.getBattleBlocksAccountControllerRef(address: address) {
                return controllerRef.getAuthAcctRef()
            }
            return nil
        }

        pub fun getBattleBlocksAccountRef(address: Address): &BattleBlocksAccount? {
            if let controllerRef = self.getBattleBlocksAccountControllerRef(address: address) {
                return controllerRef.getAccountRef()
            }
            return nil
        }

        /// Add an existing account as a child account to this manager resource. This would be done in
        /// a multisig transaction which should be possible if the parent account controls both
        ///
        pub fun addAsBattleBlocksAccount(battleBlocksAccountCap: Capability<&AuthAccount>, battleBlocksAccount: &BattleBlocksAccount) {
            pre {
                battleBlocksAccountCap.check():
                    "Problem with given AuthAccount Capability!"
                !self.BattleBlocksAccounts.containsKey(battleBlocksAccountCap.borrow()!.address):
                    "Child account with given address already exists!"
            }
            // Get a &AuthAccount reference from the the given AuthAccount Capability
            let battleBlocksAccountRef: &AuthAccount = battleBlocksAccountCap.borrow()!

            // Ensure public Capability linked
            if !battleBlocksAccountRef.getCapability<&{BattleBlocksAccountPublic}>(BattleBlocksAccounts.BattleBlocksAccountPublicPath).check() {
                battleBlocksAccountRef.link<&{BattleBlocksAccountPublic}>(
                    BattleBlocksAccounts.BattleBlocksAccountPublicPath,
                    target: BattleBlocksAccounts.BattleBlocksAccountStoragePath
                )
            }
            // Ensure private Capability linked
            if !battleBlocksAccountRef.getCapability<&BattleBlocksAccount>(BattleBlocksAccounts.BattleBlocksAccountPrivatePath).check() {
                battleBlocksAccountRef.link<&BattleBlocksAccount>(
                    BattleBlocksAccounts.BattleBlocksAccountPrivatePath,
                    target: BattleBlocksAccounts.BattleBlocksAccountStoragePath
                )
            }
            // Get a Capability to the linked BattleBlocksAccount Cap in child's private storage
            let childCap = battleBlocksAccountRef
                .getCapability<&
                    BattleBlocksAccount
                >(
                    BattleBlocksAccounts.BattleBlocksAccountPrivatePath
                )

            // Ensure the capability is valid before inserting it in manager's BattleBlocksAccounts mapping
            assert(childCap.check(), message: "Problem linking ChildAccoutChild Capability in new child account!")
            // Assign the manager's owner as the Child's parentAddress
            childCap.borrow()!.assignParent(address: self.owner?.address!)

            // Create a BattleBlocksAccountController & insert to BattleBlocksAccounts mapping
            let controller <-create BattleBlocksAccountController(
                    authAccountCap: battleBlocksAccountCap,
                    BattleBlocksAccountCap: childCap
                )

            self.BattleBlocksAccounts[battleBlocksAccountRef.address] <-! controller

            emit AccountDelegated(address: battleBlocksAccount.address, originatingPublicKey: battleBlocksAccount.originatingPublicKey, parent: self.owner?.address!)
        }

        /// Adds the given Capability to the BattleBlocksAccount at the provided Address
        ///
        /// @param to: Address which is the key for the BattleBlocksAccount Cap
        /// @param cap: Capability to be added to the BattleBlocksAccount
        ///
        pub fun addCapability(to: Address, _ cap: Capability) {
            pre {
                self.BattleBlocksAccounts.containsKey(to):
                    "No Child with given Address!"
            }
            // Get ref to Child & grant cap
            let ChildRef = self.getBattleBlocksAccountRef(
                    address: to
                ) ?? panic("Problem with BattleBlocksAccount Capability for given address: ".concat(to.toString()))
            ChildRef.grantCapability(cap)
        }

        /// Removes the capability of the given type from the BattleBlocksAccount with the given Address
        ///
        /// @param from: Address indexing the BattleBlocksAccount Capability
        /// @param type: The Type of Capability to be removed from the BattleBlocksAccount
        ///
        pub fun removeCapability(from: Address, type: Type) {
            pre {
                self.BattleBlocksAccounts.containsKey(from):
                    "No BattleBlocksAccounts with given Address!"
            }
            // Get ref to Child and remove
            let ChildRef = self.getBattleBlocksAccountRef(
                    address: from
                ) ?? panic("Problem with BattleBlocksAccount Capability for given address: ".concat(from.toString()))
            ChildRef.revokeCapability(type)
                ?? panic("Capability not properly revoked")
        }

        /// Remove BattleBlocksAccount, returning its Capability if it exists. Note, doing so
        /// does not revoke the key on the child account if it has been added. This should 
        /// be done in the same transaction in which this method is called.
        ///
        pub fun removeBattleBlocksAccount(withAddress: Address) {
            if let controller: @BattleBlocksAccountController <-self.BattleBlocksAccounts.remove(key: withAddress) {
                // Get a reference to the BattleBlocksAccount from the Capability
                let accountRef = controller.getAccountRef()
                // Set the Child as inactive
                accountRef?.setInactive()

                // Remove all capabilities from the BattleBlocksAccount
                for capType in accountRef?.getGrantedCapabilityTypes()! {
                    accountRef?.revokeCapability(capType)
                }
                destroy controller
            }
        }

        destroy () {
            pre {
                self.BattleBlocksAccounts.length == 0:
                    "Attempting to destroy BattleBlocksAccountManager with remaining BattleBlocksAccountControllers!"
            }
            destroy self.BattleBlocksAccounts
        }
        
    
        pub fun getBattleBlocksAccountMetadata(address: Address): {String: AnyStruct}? {
            if let controllerRef = self.getBattleBlocksAccountControllerRef(address: address) {
                return { 
                    "address" : controllerRef.getAccountRef()?.address,
                    "parentAddress" : controllerRef.getAccountRef()?.parentAddress,
                    "originatingPublicKey": controllerRef.getAccountRef()?.originatingPublicKey
                }
            } else {
                return nil
            }
        }
    }

    //-------------------//

    //-----Public-----//

    // Returns true if the provided public key (provided as String) has not been
    // revoked on the given account address
    pub fun isKeyActiveOnAccount(publicKey: String, address: Address): Bool {
        // Public key strings must have even length
        if publicKey.length % 2 == 0 {
            var keyIndex = 0
            var keysRemain = true
            // Iterate over keys on given account address
            while keysRemain {
                // Get the key as byte array
                if let keyArray = getAccount(address).keys.get(keyIndex: keyIndex)?.publicKey?.publicKey {
                    // Encode the key as a string and compare
                    if publicKey == String.encodeHex(keyArray) {
                        return !getAccount(address).keys.get(keyIndex: keyIndex)!.isRevoked
                    }
                    keyIndex = keyIndex + 1
                } else {
                    keysRemain = false
                }
            }
            return false
        }
        return false
    }

    pub fun createBattleBlocksAccountManager(): @BattleBlocksAccountManager {
        return <-create BattleBlocksAccountManager()
    }

    //----------------//

    init() {
        // Paths

        self.AuthAccountCapabilityPath = /private/AuthAccountCapability
        self.BattleBlocksAccountManagerStoragePath = /storage/BattleBlocksAccountManager
        self.BattleBlocksAccountManagerPublicPath = /public/BattleBlocksAccountManager
        self.BattleBlocksAccountManagerPrivatePath = /private/BattleBlocksAccountManager

        self.BattleBlocksAccountStoragePath = /storage/BattleBlocksAccount
        self.BattleBlocksAccountPublicPath = /public/BattleBlocksAccount
        self.BattleBlocksAccountPrivatePath = /private/BattleBlocksAccount

        self.BattleBlocksAccountCreatorStoragePath = /storage/BattleBlocksAccountCreator
        self.BattleBlocksAccountCreatorPublicPath = /public/BattleBlocksAccountCreator

        // Creator
        self.account.save(<-create BattleBlocksAccountCreator(), to: BattleBlocksAccounts.BattleBlocksAccountCreatorStoragePath)
    }
}
 