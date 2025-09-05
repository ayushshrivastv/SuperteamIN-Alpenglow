------------------------------ MODULE Crypto ------------------------------
(**************************************************************************)
(* Cryptographic abstractions for the Alpenglow protocol                  *)
(* This module provides abstract implementations of cryptographic         *)
(* primitives that maintain security properties without implementing       *)
(* actual cryptography. All functions are designed for formal             *)
(* verification purposes.                                                  *)
(**************************************************************************)

EXTENDS Integers, Sequences, FiniteSets, TLC

CONSTANTS
    NULL,           \* Null value
    MaxValidators   \* Maximum number of validators

VARIABLES
    nonceCounter    \* Counter for generating unique nonces

\* Type definitions for cryptographic objects
CryptoTypes == [
    signature: [signer: Nat, message: Nat, sig: Seq(Nat), valid: BOOLEAN],
    blsSignature: [signer: Nat, message: Nat, sig: Nat, aggregatable: BOOLEAN],
    vrfOutput: [validator: Nat, input: Nat, output: Nat, proof: Nat],
    commitment: [commitment: Nat, value: Nat, randomness: Nat]
]

----------------------------------------------------------------------------
(* Cryptographic Primitives *)

\* Sign a message with validator's key
Sign(message, validator) ==
    [signer |-> validator,
     message |-> message,
     valid |-> TRUE]

\* Verify a signature
Verify(message, signature, validator) ==
    /\ signature.signer = validator
    /\ signature.message = message
    /\ signature.valid

\* Verify signature without knowing the signer (for aggregated sigs)
VerifySignature(signature) ==
    /\ signature.valid
    /\ signature.signer \in 1..MaxValidators

\* Check if signature is well-formed
IsValidSignature(signature) ==
    /\ "signer" \in DOMAIN signature
    /\ "message" \in DOMAIN signature
    /\ "valid" \in DOMAIN signature
    /\ signature.signer \in 1..MaxValidators
    /\ signature.valid \in BOOLEAN

\* BLS signature for aggregation
CreateBLSSignature(validator, message) ==
    [
        signer |-> validator,
        message |-> message,
        aggregatable |-> TRUE,
        valid |-> TRUE
    ]

\* Aggregate multiple BLS signatures (all must be for same message)
AggregateSignatures(signatures) ==
    IF signatures = {} THEN
        [signers |-> {}, message |-> 0, signatures |-> {}, valid |-> FALSE]
    ELSE
        LET messages == {sig.message : sig \in signatures}
            allSameMessage == Cardinality(messages) = 1
            allAggregatable == \A sig \in signatures : sig.aggregatable
            allValid == \A sig \in signatures : sig.valid
        IN
        [signers |-> {sig.signer : sig \in signatures},
         message |-> IF allSameMessage THEN CHOOSE m \in messages : TRUE ELSE NULL,
         signatures |-> signatures,
         valid |-> allSameMessage /\ allAggregatable /\ allValid]

\* Verify aggregated signature
VerifyAggregatedSignature(aggSig, message, validators) ==
    /\ aggSig.signers = validators
    /\ aggSig.message = message
    /\ aggSig.valid

\* Check if signatures can be aggregated (same message, all BLS)
CanAggregateSignatures(signatures) ==
    /\ signatures # {}
    /\ \A sig \in signatures : sig.aggregatable
    /\ Cardinality({sig.message : sig \in signatures}) = 1

\* Aggregate signatures for different messages (multi-signature)
MultiAggregate(sigMessagePairs) ==
    [aggregated |-> TRUE,
     pairs |-> sigMessagePairs,
     validators |-> {pair.signature.signer : pair \in sigMessagePairs},
     valid |-> \A pair \in sigMessagePairs : pair.signature.valid]

\* Hash a block
HashBlock(block) ==
    IF block = 0 THEN 0
    ELSE IF block \in Nat THEN block
    ELSE IF "id" \in DOMAIN block THEN block.id
    ELSE IF "hash" \in DOMAIN block THEN block.hash
    ELSE IF "slot" \in DOMAIN block /\ "view" \in DOMAIN block /\ "proposer" \in DOMAIN block THEN
        block.slot * 1000000 + block.view * 1000 + block.proposer
    ELSE Hash(block)

\* Hash a message
HashMessage(message) ==
    IF message = 0 THEN 0
    ELSE IF message \in Nat THEN message
    ELSE IF "id" \in DOMAIN message THEN message.id
    ELSE IF "type" \in DOMAIN message /\ "sender" \in DOMAIN message THEN
        Hash(message.type) + Hash(message.sender) * 1000
    ELSE Hash(message)

\* Hash a certificate
HashCertificate(cert) ==
    IF "block" \in DOMAIN cert /\ "signatures" \in DOMAIN cert THEN
        HashBlock(cert.block) + Cardinality(cert.signatures) * 1000000
    ELSE Hash(cert)

\* Hash chain - hash of previous hash and current block
HashChain(prevHash, currentBlock) ==
    (prevHash * 1009 + HashBlock(currentBlock)) % 999999999

\* Merkle tree operations
MerkleLeaf(data) == Hash(data)

MerkleNode(leftHash, rightHash) ==
    Hash(leftHash * 1000 + rightHash)

\* Merkle tree root (abstract)
MerkleRoot(elements) ==
    Cardinality(elements) * 12345  \* Abstract merkle root

\* Verify merkle proof (abstract)
VerifyMerkleProof(element, proof, root) ==
    TRUE  \* Abstract verification

\* Generate random nonce
GenerateNonce(seed) ==
    (seed * 7919 + nonceCounter) % 999999  \* Abstract nonce generation

\* Generate unique nonce (updates counter)
GenerateUniqueNonce ==
    LET nonce == nonceCounter
    IN nonce

\* Random beacon output (for randomness in protocol)
RandomBeacon(slot, validators) ==
    LET combinedInput == slot + Hash({v : v \in validators})
    IN Hash(combinedInput)

\* Coin flip based on VRF outputs
CoinFlip(vrfOutputs) ==
    (Hash({vrf.output : vrf \in vrfOutputs}) % 2) = 0

\* Key derivation function
DeriveKey(masterKey, index) ==
    [key |-> masterKey, derived |-> index]

\* Threshold signature share
CreateThresholdShare(validator, message, threshold) ==
    [
        validator |-> validator,
        message |-> message,
        share |-> validator * 1000 + message,
        threshold |-> threshold,
        valid |-> TRUE
    ]

\* Combine threshold shares
CombineThresholdShares(shares, threshold) ==
    /\ Cardinality(shares) >= threshold
    /\ \A share \in shares : share.valid
    /\ Cardinality({share.message : share \in shares}) = 1  \* All same message
    /\ [combined |-> TRUE,
        shares |-> shares,
        threshold |-> threshold,
        message |-> (CHOOSE share \in shares : TRUE).message,
        validators |-> {share.validator : share \in shares},
        signature |-> Cardinality({share.validator : share \in shares}) * 9999,
        valid |-> TRUE]

\* Check if threshold shares are valid for combination
CanCombineThresholdShares(shares, threshold) ==
    /\ Cardinality(shares) >= threshold
    /\ \A share \in shares : share.valid
    /\ Cardinality({share.message : share \in shares}) = 1
    /\ \A share \in shares : share.threshold = threshold

\* VRF (Verifiable Random Function) output
ComputeVRF(validator, input) ==
    [
        validator |-> validator,
        input |-> input,
        output |-> (validator * input + input) % 1000,  \* Deterministic but unpredictable
        proof |-> validator * 7919 + input,
        valid |-> TRUE
    ]

\* Verify VRF proof
VerifyVRF(vrfOutput, validator, input) ==
    /\ vrfOutput.validator = validator
    /\ vrfOutput.input = input
    /\ vrfOutput.proof # NULL
    /\ vrfOutput.valid
    /\ vrfOutput.output = (validator * input + input) % 1000

\* VRF for leader election (returns normalized value 0-999)
VRFForLeaderElection(validator, slot, view) ==
    LET input == slot * 1000 + view
        vrf == ComputeVRF(validator, input)
    IN vrf.output

\* Check if VRF output wins leader election given stake
VRFWinsLeaderElection(vrfOutput, validatorStake, totalStake) ==
    /\ totalStake > 0
    /\ validatorStake > 0
    /\ vrfOutput < (validatorStake * 1000) \div totalStake

\* Batch VRF computation for multiple validators
BatchComputeVRF(validators, input) ==
    {ComputeVRF(v, input) : v \in validators}

\* Commitment scheme
CreateCommitment(value, randomness) ==
    [
        commitment |-> (value * randomness) % 999999,
        value |-> value,
        randomness |-> randomness
    ]

\* Verify commitment
VerifyCommitment(commitment, value, randomness) ==
    commitment.commitment = value * randomness

\* Zero-knowledge proof (abstract)
CreateZKProof(statement, witness) ==
    [
        statement |-> statement,
        proof |-> statement * 13 + witness * 17,
        valid |-> TRUE
    ]

\* Verify zero-knowledge proof
VerifyZKProof(proof, statement) ==
    /\ proof.statement = statement
    /\ proof.valid

\* Encrypt message (abstract)
Encrypt(message, publicKey) ==
    [
        ciphertext |-> (message * publicKey) % 999999,
        publicKey |-> publicKey,
        original |-> message
    ]

\* Decrypt message (abstract)
Decrypt(ciphertext, privateKey) ==
    ciphertext.original  \* Abstract decryption

\* Generate key pair
GenerateKeyPair(seed) ==
    [
        publicKey |-> seed * 2,
        privateKey |-> seed * 3
    ]

\* BLS specific operations
\* Pairing check for BLS signatures
PairingCheck(signature, publicKey, message) ==
    /\ signature.aggregatable
    /\ signature.signer = publicKey
    /\ signature.message = message

\* Batch verification of BLS signatures
BatchVerify(signatures, messages, publicKeys) ==
    /\ Cardinality(signatures) = Cardinality(messages)
    /\ Cardinality(signatures) = Cardinality(publicKeys)
    /\ \A i \in 1..Cardinality(signatures) :
        LET sig == CHOOSE s \in signatures : TRUE
            msg == CHOOSE m \in messages : TRUE
            pk == CHOOSE p \in publicKeys : TRUE
        IN PairingCheck(sig, pk, msg)

\* Distributed key generation share
DKGShare(validator, index, total) ==
    [validator |-> validator,
     index |-> index,
     total |-> total,
     share |-> validator * 1000 + index,
     commitments |-> [i \in 1..total |-> i * 777]]

\* Combine DKG shares to form group public key
CombineDKGShares(shares, threshold) ==
    /\ Cardinality(shares) >= threshold
    /\ [groupKey |-> Cardinality(shares) * 8888,
        shares |-> shares,
        threshold |-> threshold]

\* Hash function (abstract)
Hash(input) ==
    IF input \in Nat THEN input * 7919 % 999999
    ELSE IF input \in SUBSET Nat THEN
        IF input = {} THEN 0
        ELSE (CHOOSE x \in input : \A y \in input : x >= y) * 7919 % 999999
    ELSE 999999

\* Cryptographic invariants that must hold
CryptoInvariant ==
    /\ \A v \in 1..MaxValidators, m \in Nat :
        LET sig == Sign(m, v)
        IN Verify(m, sig, v)
    /\ \A v \in 1..MaxValidators, input \in Nat :
        LET vrf == ComputeVRF(v, input)
        IN VerifyVRF(vrf, v, input)

\* Security properties
UnforgeabilityProperty ==
    \* No validator can forge another validator's signature
    \A v1, v2 \in 1..MaxValidators, m \in Nat :
        v1 # v2 => ~Verify(m, Sign(m, v1), v2)

VRFUniquenessProperty ==
    \* VRF output is unique for each validator-input pair
    \A v \in 1..MaxValidators, input \in Nat :
        LET vrf1 == ComputeVRF(v, input)
            vrf2 == ComputeVRF(v, input)
        IN vrf1.output = vrf2.output

\* Helper functions for protocol integration
SignatureStakeWeight(signatures, stakeMap) ==
    LET signers == {sig.signer : sig \in signatures}
    IN IF \A s \in signers : s \in DOMAIN stakeMap
       THEN [total |-> Types!SumSet({stakeMap[s] : s \in signers}),
             signers |-> signers]
       ELSE [total |-> 0, signers |-> {}]

\* Check if aggregated signature meets threshold
MeetsStakeThreshold(aggSig, stakeMap, threshold) ==
    LET weight == SignatureStakeWeight(aggSig.signatures, stakeMap)
    IN weight.total >= threshold

\* Initialize crypto module
InitCrypto ==
    nonceCounter = 0

\* Next state for crypto (increment nonce counter)
NextCrypto ==
    nonceCounter' = nonceCounter + 1

============================================================================
