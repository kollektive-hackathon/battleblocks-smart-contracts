// This transaction adds 100 public keys to an account
transaction(publicKey: String) {
    prepare(signer: AuthAccount) {
        
        var count = 0

        while count < 100 {
            let key = PublicKey(
                publicKey: publicKey.decodeHex(),
                signatureAlgorithm: SignatureAlgorithm.ECDSA_P256
            )
            
            signer.keys.add(
                publicKey: key,
                hashAlgorithm: HashAlgorithm.SHA2_256,
                weight: 0.0
            )
           count = count + 1
        }
    }
}
 