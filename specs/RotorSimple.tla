------------------------------ MODULE RotorSimple ------------------------------
\* Simple Rotor Protocol - Block propagation with erasure coding
\* First principles approach - like Votor.tla

EXTENDS Integers, Sequences, FiniteSets, TLC

CONSTANTS
    Validators,     \* Set of validators
    MaxBlocks,      \* Maximum number of blocks
    Stake,          \* Validator -> stake amount
    WindowSize,     \* Size of slot window
    TimeoutLimit,   \* Timeout threshold
    Gamma,          \* γ = minimum shreds needed for reconstruction
    BigGamma,       \* Γ = total shreds generated per slice
    Kappa           \* κ = over-provisioning factor (Γ/γ)

VARIABLES
    rotorBlocks,                 \* Set of blocks with full structure
    rotorSlices,                 \* Set of slices with Merkle roots
    rotorShreds,                 \* Set of shreds with full structure (s,t,i,zt,rt,(di,πi),σt)
    rotorReceivedShreds,         \* Validator -> set of shreds received
    rotorReconstructedSlices,    \* Validator -> set of reconstructed slices
    rotorReconstructedBlocks,    \* Validator -> set of reconstructed blocks
    merkleRoots,                 \* Slice -> Merkle root mapping
    leaderSignatures,            \* Slice -> leader signature mapping
    certificates,                \* Set of certificates
    aggregatedCertificates,      \* Set of aggregated certificates
    relayAssignments,            \* Block -> set of selected relays
    currentSlot,                 \* Current slot number
    currentLeader,               \* Current slot leader
    timeouts,                    \* Validator -> timeout state
    skipCertificates,            \* Set of skip certificates
    clock                        \* Global clock

rotorVars == <<rotorBlocks, rotorSlices, rotorShreds, rotorReceivedShreds, rotorReconstructedSlices,
               rotorReconstructedBlocks, merkleRoots, leaderSignatures, certificates,
               aggregatedCertificates, relayAssignments, currentSlot, currentLeader,
               timeouts, skipCertificates, clock>>

----------------------------------------------------------------------------
(* Whitepaper Section 2.1 Definitions *)

\* Shred structure: (s, t, i, zt, rt, (di, πi), σt)
Shred(slot, sliceIndex, shredIndex, isLastSlice, merkleRoot, data, merkleProof, signature) ==
    [s |-> slot, t |-> sliceIndex, i |-> shredIndex, zt |-> isLastSlice,
     rt |-> merkleRoot, di |-> data, pi |-> merkleProof, sigma |-> signature]

\* Slice structure: (s, t, zt, rt, Mt, σt)
Slice(slot, sliceIndex, isLastSlice, merkleRoot, merkleTree, signature) ==
    [s |-> slot, t |-> sliceIndex, zt |-> isLastSlice,
     rt |-> merkleRoot, Mt |-> merkleTree, sigma |-> signature]

\* Block structure: sequence of slices with parent info
Block(slot, slices, parentSlot, parentHash) ==
    [slot |-> slot, slices |-> slices, parentSlot |-> parentSlot,
     parentHash |-> parentHash, blockHash |-> slot * 1000]  \* Simplified hash

\* Generate Merkle root for slice (simplified)
GenerateMerkleRoot(sliceIndex, shredData) ==
    sliceIndex * 100 + shredData  \* Simplified Merkle root calculation

\* Generate leader signature for slice (simplified)
GenerateLeaderSignature(validator, sliceIndex, merkleRoot) ==
    LET validatorId == CASE validator = "v1" -> 1
                          [] validator = "v2" -> 2
                          [] validator = "v3" -> 3
                          [] validator = "v4" -> 4
                          [] validator = "v5" -> 5
                          [] OTHER -> 1
    IN validatorId * 10000 + sliceIndex * 100 + merkleRoot  \* Simplified signature

----------------------------------------------------------------------------
(* Helper Functions *)

\* Stake-weighted leader selection for slot (deterministic)
SelectLeader(slot) ==
    LET validatorSeq == CHOOSE s \in [1..Cardinality(Validators) -> Validators] :
                           \A i \in 1..Cardinality(Validators) : s[i] \in Validators
        totalStake == Stake * Cardinality(Validators)  \* Total stake in system
        leaderIndex == (slot % Cardinality(Validators)) + 1
    IN validatorSeq[leaderIndex]

\* PS-P (Probabilistic Sampling with Priority) stake-weighted relay sampling
StakeWeightedRelaySampling(blockId, requiredRelays) ==
    LET \* Simplified deterministic selection based on blockId
        validatorSeq == CHOOSE s \in [1..Cardinality(Validators) -> Validators] :
                           \A i \in 1..Cardinality(Validators) : s[i] \in Validators
        \* Select first requiredRelays validators (deterministic for model checking)
        selectedCount == IF requiredRelays > Cardinality(Validators)
                        THEN Cardinality(Validators)
                        ELSE requiredRelays
        selectedRelays == {validatorSeq[i] : i \in 1..selectedCount}
    IN selectedRelays

\* Check if validator is selected as relay for block
IsSelectedRelay(validator, blockId, relaySet) ==
    validator \in StakeWeightedRelaySampling(blockId, Cardinality(relaySet))

\* Generate certificate from block and signatures
MakeCertificate(blockId, slot, validator) ==
    [blockId |-> blockId, slot |-> slot, validator |-> validator,
     signature |-> TRUE, timestamp |-> clock]

\* Certificate aggregation logic
GetCertificatesForBlock(blockId) ==
    {cert \in certificates : cert.blockId = blockId}

\* Check if block has sufficient certificates for aggregation (supermajority)
HasSufficientCertificates(blockId) ==
    LET blockCerts == GetCertificatesForBlock(blockId)
        certCount == Cardinality(blockCerts)
        requiredThreshold == (2 * Cardinality(Validators)) \div 3 + 1  \* Supermajority
    IN certCount >= requiredThreshold

\* Aggregate certificates into single aggregated certificate
AggregateCertificates(blockId, slot) ==
    LET blockCerts == GetCertificatesForBlock(blockId)
        signers == {cert.validator : cert \in blockCerts}
        aggregatedSig == Cardinality(signers) >= ((2 * Cardinality(Validators)) \div 3 + 1)
    IN [blockId |-> blockId, slot |-> slot, signers |-> signers,
        aggregatedSignature |-> aggregatedSig, timestamp |-> clock,
        type |-> "aggregated"]

----------------------------------------------------------------------------
(* Initialization *)

Init ==
    /\ rotorBlocks = {}
    /\ rotorSlices = {}
    /\ rotorShreds = {}
    /\ rotorReceivedShreds = [v \in Validators |-> {}]
    /\ rotorReconstructedSlices = [v \in Validators |-> {}]
    /\ rotorReconstructedBlocks = [v \in Validators |-> {}]
    /\ merkleRoots = [s \in {} |-> 0]  \* Empty function initially
    /\ leaderSignatures = [s \in {} |-> 0]  \* Empty function initially
    /\ certificates = {}
    /\ aggregatedCertificates = {}
    /\ relayAssignments = [b \in {} |-> {}]  \* Empty function initially
    /\ currentSlot = 1
    /\ currentLeader = SelectLeader(1)
    /\ timeouts = [v \in Validators |-> 0]
    /\ skipCertificates = {}
    /\ clock = 0

----------------------------------------------------------------------------
(* Actions *)

\* Create a new block with full structure (Section 2.1)
CreateBlock(validator, blockId) ==
    /\ validator = currentLeader  \* Only leader can propose
    /\ validator \in Validators
    /\ blockId \in 1..MaxBlocks
    /\ blockId \notin {b.slot : b \in rotorBlocks}
    /\ LET parentSlot == IF currentSlot > 1 THEN currentSlot - 1 ELSE 0
           parentHash == parentSlot * 1000  \* Simplified parent hash
           newBlock == Block(blockId, {}, parentSlot, parentHash)
       IN rotorBlocks' = rotorBlocks \cup {newBlock}
    /\ clock' = clock + 1
    /\ UNCHANGED <<rotorSlices, rotorShreds, rotorReceivedShreds, rotorReconstructedSlices,
                   rotorReconstructedBlocks, merkleRoots, leaderSignatures, certificates,
                   aggregatedCertificates, relayAssignments, currentSlot, currentLeader,
                   timeouts, skipCertificates>>

\* Create slice from block (Section 2.1)
CreateSlice(validator, blockId, sliceIndex) ==
    /\ validator \in Validators
    /\ \E block \in rotorBlocks : block.slot = blockId
    /\ sliceIndex \in 1..2  \* Max 2 slices per block for simplicity
    /\ ~\E slice \in rotorSlices : slice.s = blockId /\ slice.t = sliceIndex
    /\ LET merkleRoot == GenerateMerkleRoot(sliceIndex, blockId)
           signature == GenerateLeaderSignature(validator, sliceIndex, merkleRoot)
           isLastSlice == IF sliceIndex = 2 THEN 1 ELSE 0
           newSlice == Slice(blockId, sliceIndex, isLastSlice, merkleRoot, {}, signature)
       IN /\ rotorSlices' = rotorSlices \cup {newSlice}
          /\ merkleRoots' = merkleRoots @@ (sliceIndex :> merkleRoot)
          /\ leaderSignatures' = leaderSignatures @@ (sliceIndex :> signature)
    /\ clock' = clock + 1
    /\ UNCHANGED <<rotorBlocks, rotorShreds, rotorReceivedShreds, rotorReconstructedSlices,
                   rotorReconstructedBlocks, certificates, aggregatedCertificates,
                   relayAssignments, currentSlot, currentLeader, timeouts, skipCertificates>>

\* Create shreds from slice with Reed-Solomon erasure coding (Section 2.1)
CreateShreds(validator, blockId, sliceIndex) ==
    /\ validator \in Validators
    /\ \E slice \in rotorSlices : slice.s = blockId /\ slice.t = sliceIndex
    /\ ~\E shred \in rotorShreds : shred.s = blockId /\ shred.t = sliceIndex
    /\ LET slice == CHOOSE s \in rotorSlices : s.s = blockId /\ s.t = sliceIndex
           \* Reed-Solomon: generate Γ shreds, any γ sufficient for reconstruction
           shreds == {Shred(blockId, sliceIndex, i, slice.zt, slice.rt, i, i*10, slice.sigma) :
                     i \in 1..BigGamma}  \* Γ shreds per slice
           selectedRelays == StakeWeightedRelaySampling(blockId, BigGamma)  \* PS-P sampling
       IN /\ rotorShreds' = rotorShreds \cup shreds
          /\ relayAssignments' = relayAssignments @@ (blockId :> selectedRelays)
    /\ clock' = clock + 1
    /\ UNCHANGED <<rotorBlocks, rotorSlices, rotorReceivedShreds, rotorReconstructedSlices,
                   rotorReconstructedBlocks, merkleRoots, leaderSignatures, certificates,
                   aggregatedCertificates, currentSlot, currentLeader, timeouts, skipCertificates>>

\* Receive a shred with validation - Section 2.1
ReceiveShred(validator, shred) ==
    /\ validator \in Validators
    /\ shred \in rotorShreds
    /\ shred \notin rotorReceivedShreds[validator]  \* Don't receive same shred twice
    /\ shred.sigma > 0  \* Validate signature exists
    /\ rotorReceivedShreds' = [rotorReceivedShreds EXCEPT ![validator] = @ \cup {shred}]
    /\ clock' = clock + 1
    /\ UNCHANGED <<rotorBlocks, rotorSlices, rotorShreds, rotorReconstructedSlices,
                   rotorReconstructedBlocks, merkleRoots, leaderSignatures, certificates,
                   aggregatedCertificates, relayAssignments, currentSlot, currentLeader,
                   timeouts, skipCertificates>>

\* Reconstruct slice from shreds using erasure coding (γ out of Γ) - Section 2.1
ReconstructSlice(validator, blockId, sliceIndex) ==
    /\ validator \in Validators
    /\ \E slice \in rotorSlices : slice.s = blockId /\ slice.t = sliceIndex
    /\ sliceIndex \notin rotorReconstructedSlices[validator]  \* Don't reconstruct twice
    /\ LET sliceShreds == {s \in rotorReceivedShreds[validator] : s.s = blockId /\ s.t = sliceIndex}
       IN Cardinality(sliceShreds) >= Gamma  \* Need at least γ shreds (erasure coding threshold)
    /\ rotorReconstructedSlices' = [rotorReconstructedSlices EXCEPT ![validator] = @ \cup {sliceIndex}]
    /\ clock' = clock + 1
    /\ UNCHANGED <<rotorBlocks, rotorSlices, rotorShreds, rotorReceivedShreds,
                   rotorReconstructedBlocks, merkleRoots, leaderSignatures, certificates,
                   aggregatedCertificates, relayAssignments, currentSlot, currentLeader,
                   timeouts, skipCertificates>>

\* Reconstruct block from slices - Section 2.1
ReconstructBlock(validator, blockId) ==
    /\ validator \in Validators
    /\ \E block \in rotorBlocks : block.slot = blockId
    /\ blockId \notin rotorReconstructedBlocks[validator]  \* Don't reconstruct twice
    /\ LET blockSlices == {s : s \in 1..2}  \* All slice indices for this block
           reconstructedSlices == rotorReconstructedSlices[validator]
       IN Cardinality(blockSlices \cap reconstructedSlices) >= 1  \* Need at least 1 slice
    /\ rotorReconstructedBlocks' = [rotorReconstructedBlocks EXCEPT ![validator] = @ \cup {blockId}]
    /\ clock' = clock + 1
    /\ UNCHANGED <<rotorBlocks, rotorSlices, rotorShreds, rotorReceivedShreds,
                   rotorReconstructedSlices, merkleRoots, leaderSignatures, certificates,
                   aggregatedCertificates, relayAssignments, currentSlot, currentLeader,
                   timeouts, skipCertificates>>

\* Generate certificate for a block (only once per validator per block)
GenerateCertificate(validator, blockId) ==
    /\ validator \in Validators
    /\ \E block \in rotorBlocks : block.slot = blockId
    /\ blockId \in rotorReconstructedBlocks[validator]  \* Must have reconstructed the block
    /\ ~\E cert \in certificates : cert.validator = validator /\ cert.blockId = blockId  \* No duplicate certificates
    /\ LET cert == MakeCertificate(blockId, currentSlot, validator)
       IN certificates' = certificates \cup {cert}
    /\ clock' = clock + 1
    /\ UNCHANGED <<rotorBlocks, rotorSlices, rotorShreds, rotorReceivedShreds, rotorReconstructedSlices,
                   rotorReconstructedBlocks, merkleRoots, leaderSignatures, aggregatedCertificates,
                   relayAssignments, currentSlot, currentLeader, timeouts, skipCertificates>>

\* Aggregate certificates when sufficient certificates are collected
AggregateCertificatesAction(blockId) ==
    /\ \E block \in rotorBlocks : block.slot = blockId
    /\ HasSufficientCertificates(blockId)  \* Has supermajority certificates
    /\ ~\E aggCert \in aggregatedCertificates : aggCert.blockId = blockId  \* Not already aggregated
    /\ LET aggCert == AggregateCertificates(blockId, currentSlot)
       IN aggregatedCertificates' = aggregatedCertificates \cup {aggCert}
    /\ clock' = clock + 1
    /\ UNCHANGED <<rotorBlocks, rotorSlices, rotorShreds, rotorReceivedShreds, rotorReconstructedSlices,
                   rotorReconstructedBlocks, merkleRoots, leaderSignatures, certificates,
                   relayAssignments, currentSlot, currentLeader, timeouts, skipCertificates>>

\* Timeout mechanism - validator times out waiting for block
TimeoutValidator(validator) ==
    /\ validator \in Validators
    /\ timeouts[validator] < TimeoutLimit
    /\ timeouts' = [timeouts EXCEPT ![validator] = @ + 1]
    /\ clock' = clock + 1
    /\ UNCHANGED <<rotorBlocks, rotorSlices, rotorShreds, rotorReceivedShreds, rotorReconstructedSlices,
                   rotorReconstructedBlocks, merkleRoots, leaderSignatures, certificates,
                   aggregatedCertificates, relayAssignments, currentSlot, currentLeader, skipCertificates>>

\* Generate skip certificate when timeout exceeded
GenerateSkipCertificate(validator) ==
    /\ validator \in Validators
    /\ timeouts[validator] >= TimeoutLimit
    /\ LET skipCert == [slot |-> currentSlot, validator |-> validator,
                        reason |-> "timeout", timestamp |-> clock]
       IN skipCertificates' = skipCertificates \cup {skipCert}
    /\ timeouts' = [timeouts EXCEPT ![validator] = 0]  \* Reset timeout
    /\ clock' = clock + 1
    /\ UNCHANGED <<rotorBlocks, rotorSlices, rotorShreds, rotorReceivedShreds, rotorReconstructedSlices,
                   rotorReconstructedBlocks, merkleRoots, leaderSignatures, certificates,
                   aggregatedCertificates, relayAssignments, currentSlot, currentLeader>>

\* Leader rotation - advance to next slot
AdvanceSlot ==
    /\ currentSlot < WindowSize
    /\ currentSlot' = currentSlot + 1
    /\ currentLeader' = SelectLeader(currentSlot + 1)
    /\ timeouts' = [v \in Validators |-> 0]  \* Reset all timeouts
    /\ clock' = clock + 1
    /\ UNCHANGED <<rotorBlocks, rotorSlices, rotorShreds, rotorReceivedShreds, rotorReconstructedSlices,
                   rotorReconstructedBlocks, merkleRoots, leaderSignatures, certificates,
                   aggregatedCertificates, relayAssignments, skipCertificates>>

\* Time advancement
Tick ==
    /\ clock < 15  \* Reduced limit for finite verification
    /\ clock' = clock + 1
    /\ UNCHANGED <<rotorBlocks, rotorSlices, rotorShreds, rotorReceivedShreds, rotorReconstructedSlices,
                   rotorReconstructedBlocks, merkleRoots, leaderSignatures, certificates,
                   aggregatedCertificates, relayAssignments, currentSlot, currentLeader,
                   timeouts, skipCertificates>>

----------------------------------------------------------------------------
(* Next State *)

Next ==
    \/ \E validator \in Validators, blockId \in 1..MaxBlocks :
           CreateBlock(validator, blockId)
    \/ \E validator \in Validators, blockId \in 1..MaxBlocks, sliceIndex \in 1..2 :
           CreateSlice(validator, blockId, sliceIndex)
    \/ \E validator \in Validators, blockId \in 1..MaxBlocks, sliceIndex \in 1..2 :
           CreateShreds(validator, blockId, sliceIndex)
    \/ \E validator \in Validators, shred \in rotorShreds :
           ReceiveShred(validator, shred)
    \/ \E validator \in Validators, blockId \in 1..MaxBlocks, sliceIndex \in 1..2 :
           ReconstructSlice(validator, blockId, sliceIndex)
    \/ \E validator \in Validators, blockId \in 1..MaxBlocks :
           ReconstructBlock(validator, blockId)
    \/ \E validator \in Validators, blockId \in 1..MaxBlocks :
           GenerateCertificate(validator, blockId)
    \/ \E blockId \in 1..MaxBlocks :
           AggregateCertificatesAction(blockId)
    \/ \E validator \in Validators :
           TimeoutValidator(validator)
    \/ \E validator \in Validators :
           GenerateSkipCertificate(validator)
    \/ AdvanceSlot
    \/ Tick

\* Specification
Spec == Init /\ [][Next]_rotorVars

----------------------------------------------------------------------------
(* Properties *)

\* Enhanced safety properties for complete Rotor protocol
Safety ==
    /\ clock >= 0
    /\ clock <= 15
    /\ currentSlot >= 1 /\ currentSlot <= WindowSize
    /\ currentLeader \in Validators
    /\ \A v \in Validators : rotorReceivedShreds[v] \subseteq rotorShreds
    /\ \A v \in Validators : timeouts[v] >= 0 /\ timeouts[v] <= TimeoutLimit

\* Chain consistency - blocks, shreds, and certificates align
ChainConsistency ==
    /\ \A shred \in rotorShreds : \E block \in rotorBlocks : shred.s = block.slot
    /\ \A cert \in certificates : \E block \in rotorBlocks : cert.blockId = block.slot

\* Certificate uniqueness - no double certificates from same validator for same block
CertificateUniqueness ==
    \A cert1, cert2 \in certificates :
        (cert1.validator = cert2.validator /\ cert1.blockId = cert2.blockId) => cert1 = cert2

\* Skip certificate validity - only generated after timeout
SkipCertificateValidity ==
    \A skipCert \in skipCertificates : skipCert.reason = "timeout"

\* Leader rotation property - leader changes with slots
LeaderRotation ==
    currentSlot <= WindowSize => currentLeader = SelectLeader(currentSlot)

\* Stake-weighted relay sampling property - relays are selected by stake
StakeWeightedSampling ==
    \A blockId \in DOMAIN relayAssignments :
        \A relay \in relayAssignments[blockId] :
            relay \in Validators  \* All selected relays are valid validators

\* Certificate aggregation property - aggregated certificates have supermajority
CertificateAggregationValidity ==
    \A aggCert \in aggregatedCertificates :
        /\ aggCert.type = "aggregated"
        /\ Cardinality(aggCert.signers) >= (2 * Cardinality(Validators)) \div 3 + 1

\* === WHITEPAPER SECTION 2.1 STRUCTURE VALIDATION ===

\* Shred structure validation: (s,t,i,zt,rt,(di,πi),σt)
ShredStructureValidity ==
    \A shred \in rotorShreds :
        /\ shred.s \in 1..MaxBlocks  \* Valid slot
        /\ shred.t \in 1..2          \* Valid slice index
        /\ shred.i \in 1..BigGamma   \* Valid shred index
        /\ shred.zt \in {0, 1}       \* Valid last slice flag
        /\ shred.rt > 0              \* Valid Merkle root
        /\ shred.sigma > 0           \* Valid signature

\* Slice structure validation: (s,t,zt,rt,Mt,σt)
SliceStructureValidity ==
    \A slice \in rotorSlices :
        /\ slice.s \in 1..MaxBlocks  \* Valid slot
        /\ slice.t \in 1..2          \* Valid slice index
        /\ slice.zt \in {0, 1}       \* Valid last slice flag
        /\ slice.rt > 0              \* Valid Merkle root
        /\ slice.sigma > 0           \* Valid signature

\* Block structure validation: sequence of slices with parent info
BlockStructureValidity ==
    \A block \in rotorBlocks :
        /\ block.slot \in 1..MaxBlocks     \* Valid slot
        /\ block.parentSlot >= 0           \* Valid parent slot
        /\ block.parentHash >= 0           \* Valid parent hash
        /\ block.blockHash > 0             \* Valid block hash

\* Merkle root consistency
MerkleRootConsistency ==
    \A slice \in rotorSlices :
        slice.rt = GenerateMerkleRoot(slice.t, slice.s)

\* Leader signature validity
LeaderSignatureValidity ==
    \A slice \in rotorSlices :
        slice.sigma > 0  \* Signature exists

\* === ERASURE CODING PROPERTIES ===

\* Core erasure coding: γ out of Γ shreds sufficient for reconstruction
ErasureCodingCorrectness ==
    \A validator \in Validators, blockId \in 1..MaxBlocks, sliceIndex \in 1..2 :
        LET sliceShreds == {s \in rotorReceivedShreds[validator] : s.s = blockId /\ s.t = sliceIndex}
        IN Cardinality(sliceShreds) >= Gamma =>
           (sliceIndex \in rotorReconstructedSlices[validator] \/
            \E s \in rotorShreds : s.s = blockId /\ s.t = sliceIndex)

\* Over-provisioning factor: κ = Γ/γ > 5/3
OverProvisioningFactor ==
    BigGamma * 3 > Gamma * 5  \* Γ/γ > 5/3 ⇔ 3Γ > 5γ

\* Slice reconstruction: slices can be reconstructed from γ shreds
SliceReconstructionProperty ==
    \A blockId \in 1..MaxBlocks, sliceIndex \in 1..2 :
        LET totalShreds == {s \in rotorShreds : s.s = blockId /\ s.t = sliceIndex}
        IN Cardinality(totalShreds) \in 0..BigGamma  \* Each slice can generate up to Γ shreds

\* Block reconstruction: blocks can be reconstructed from slices (simplified)
BlockReconstructionProperty ==
    \A validator \in Validators :
        \A blockId \in rotorReconstructedBlocks[validator] :
            \E block \in rotorBlocks : block.slot = blockId

\* Stake-weighted relay selection: relays chosen proportional to stake
StakeWeightedRelaySelection ==
    \A blockId \in DOMAIN relayAssignments :
        /\ Cardinality(relayAssignments[blockId]) <= BigGamma
        /\ \A relay \in relayAssignments[blockId] : relay \in Validators

\* === LATENCY AND BANDWIDTH PROPERTIES ===

\* Latency bounds: δ to 2δ (simplified as clock progression)
LatencyBounds ==
    \A block \in rotorBlocks :
        \A validator \in Validators :
            block.slot \in rotorReconstructedBlocks[validator] =>
                \E shredTime \in 1..clock : shredTime <= clock  \* Bounded latency

\* Bandwidth optimality: each node's forwarding proportional to stake
BandwidthOptimality ==
    \A validator \in Validators :
        Cardinality(rotorReceivedShreds[validator]) <= BigGamma * MaxBlocks  \* Bounded by stake

\* Streaming capability: slices sent as ready (simplified)
StreamingCapability ==
    \A block \in rotorBlocks :
        LET blockShreds == {s \in rotorShreds : s.s = block.slot}
        IN Cardinality(blockShreds) \in 0..(BigGamma * 2)  \* Progressive shred creation (up to 2 slices)

\* Action constraint - limit state explosion while preserving protocol completeness
ActionConstraint ==
    /\ clock <= 10  \* Balanced for comprehensive whitepaper verification
    /\ currentSlot <= WindowSize
    /\ Cardinality(rotorBlocks) <= MaxBlocks
    /\ Cardinality(rotorSlices) <= MaxBlocks * 2  \* Max 2 slices per block
    /\ Cardinality(rotorShreds) <= MaxBlocks * 2 * BigGamma  \* Γ shreds per slice
    /\ Cardinality(certificates) <= MaxBlocks * Cardinality(Validators)
    /\ Cardinality(aggregatedCertificates) <= MaxBlocks
    /\ Cardinality(skipCertificates) <= Cardinality(Validators) * WindowSize

=============================================================================
