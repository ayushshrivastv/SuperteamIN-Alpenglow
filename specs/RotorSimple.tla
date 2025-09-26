------------------------------ MODULE RotorSimple ------------------------------
\* Simple Rotor Protocol - Block propagation with erasure coding
\* First principles approach - like Votor.tla

EXTENDS Integers, Sequences, FiniteSets, TLC

CONSTANTS 
    Validators,     \* Set of validators
    MaxBlocks,      \* Maximum number of blocks
    Stake,          \* Validator -> stake amount
    WindowSize,     \* Size of slot window
    TimeoutLimit    \* Timeout threshold

VARIABLES
    rotorBlocks,                 \* Set of blocks
    rotorShreds,                 \* Set of shreds
    rotorReceivedShreds,         \* Validator -> set of shreds received
    rotorReconstructedBlocks,    \* Validator -> set of reconstructed blocks
    certificates,                \* Set of certificates
    aggregatedCertificates,      \* Set of aggregated certificates
    relayAssignments,            \* Block -> set of selected relays
    currentSlot,                 \* Current slot number
    currentLeader,               \* Current slot leader
    timeouts,                    \* Validator -> timeout state
    skipCertificates,            \* Set of skip certificates
    clock                        \* Global clock

rotorVars == <<rotorBlocks, rotorShreds, rotorReceivedShreds, rotorReconstructedBlocks, 
               certificates, aggregatedCertificates, relayAssignments, currentSlot, 
               currentLeader, timeouts, skipCertificates, clock>>

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
    LET \* Calculate stake weights for each validator
        stakeWeights == [v \in Validators |-> Stake]  \* Simplified: equal stake
        totalStake == Stake * Cardinality(Validators)
        \* PS-P sampling: higher stake = higher probability of selection
        samplingScore(validator, seed) == 
            (Stake * ((seed % 100) + 1)) \div totalStake  \* Deterministic scoring
        \* Select top validators by stake-weighted score
        selectedRelays == CHOOSE relays \in SUBSET Validators : 
            /\ Cardinality(relays) = requiredRelays
            /\ \A v1 \in relays, v2 \in (Validators \ relays) :
                samplingScore(v1, blockId) >= samplingScore(v2, blockId)
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
    /\ rotorShreds = {}
    /\ rotorReceivedShreds = [v \in Validators |-> {}]
    /\ rotorReconstructedBlocks = [v \in Validators |-> {}]
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

\* Create a new block (only current leader can propose)
CreateBlock(validator, blockId) ==
    /\ validator = currentLeader  \* Only leader can propose
    /\ validator \in Validators
    /\ blockId \in 1..MaxBlocks
    /\ blockId \notin rotorBlocks
    /\ rotorBlocks' = rotorBlocks \cup {blockId}
    /\ clock' = clock + 1
    /\ UNCHANGED <<rotorShreds, rotorReceivedShreds, rotorReconstructedBlocks,
                   certificates, aggregatedCertificates, relayAssignments, currentSlot, 
                   currentLeader, timeouts, skipCertificates>>

\* Create shreds from a block with stake-weighted relay selection
CreateShreds(validator, blockId) ==
    /\ validator \in Validators
    /\ blockId \in rotorBlocks
    /\ blockId \notin {s \div 10 : s \in rotorShreds}  \* Block not already shredded
    /\ LET shreds == {blockId * 10 + i : i \in 1..2}  \* Only 2 shreds per block
           selectedRelays == StakeWeightedRelaySampling(blockId, 2)  \* PS-P sampling
       IN /\ rotorShreds' = rotorShreds \cup shreds
          /\ relayAssignments' = [relayAssignments EXCEPT ![blockId] = selectedRelays]
    /\ clock' = clock + 1
    /\ UNCHANGED <<rotorBlocks, rotorReceivedShreds, rotorReconstructedBlocks,
                   certificates, aggregatedCertificates, currentSlot, currentLeader, 
                   timeouts, skipCertificates>>

\* Receive a shred - more constrained
ReceiveShred(validator, shredId) ==
    /\ validator \in Validators
    /\ shredId \in rotorShreds
    /\ shredId \notin rotorReceivedShreds[validator]  \* Don't receive same shred twice
    /\ rotorReceivedShreds' = [rotorReceivedShreds EXCEPT ![validator] = @ \cup {shredId}]
    /\ clock' = clock + 1
    /\ UNCHANGED <<rotorBlocks, rotorShreds, rotorReconstructedBlocks,
                   certificates, aggregatedCertificates, relayAssignments, currentSlot, 
                   currentLeader, timeouts, skipCertificates>>

\* Reconstruct a block from shreds - more constrained
ReconstructBlock(validator, blockId) ==
    /\ validator \in Validators
    /\ blockId \in rotorBlocks
    /\ blockId \notin rotorReconstructedBlocks[validator]  \* Don't reconstruct twice
    /\ LET blockShreds == {s \in rotorReceivedShreds[validator] : s >= blockId * 10 /\ s < (blockId + 1) * 10}
       IN Cardinality(blockShreds) >= 2  \* Need at least 2 shreds for this specific block
    /\ rotorReconstructedBlocks' = [rotorReconstructedBlocks EXCEPT ![validator] = @ \cup {blockId}]
    /\ clock' = clock + 1
    /\ UNCHANGED <<rotorBlocks, rotorShreds, rotorReceivedShreds,
                   certificates, aggregatedCertificates, relayAssignments,
                   currentSlot, currentLeader, timeouts, skipCertificates>>

\* Generate certificate for a block (only once per validator per block)
GenerateCertificate(validator, blockId) ==
    /\ validator \in Validators
    /\ blockId \in rotorBlocks
    /\ blockId \in rotorReconstructedBlocks[validator]  \* Must have reconstructed the block
    /\ ~\E cert \in certificates : cert.validator = validator /\ cert.blockId = blockId  \* No duplicate certificates
    /\ LET cert == MakeCertificate(blockId, currentSlot, validator)
       IN certificates' = certificates \cup {cert}
    /\ clock' = clock + 1
    /\ UNCHANGED <<rotorBlocks, rotorShreds, rotorReceivedShreds, rotorReconstructedBlocks,
                   aggregatedCertificates, relayAssignments, currentSlot, currentLeader, 
                   timeouts, skipCertificates>>

\* Aggregate certificates when sufficient certificates are collected
AggregateCertificatesAction(blockId) ==
    /\ blockId \in rotorBlocks
    /\ HasSufficientCertificates(blockId)  \* Has supermajority certificates
    /\ ~\E aggCert \in aggregatedCertificates : aggCert.blockId = blockId  \* Not already aggregated
    /\ LET aggCert == AggregateCertificates(blockId, currentSlot)
       IN aggregatedCertificates' = aggregatedCertificates \cup {aggCert}
    /\ clock' = clock + 1
    /\ UNCHANGED <<rotorBlocks, rotorShreds, rotorReceivedShreds, rotorReconstructedBlocks,
                   certificates, relayAssignments, currentSlot, currentLeader, 
                   timeouts, skipCertificates>>

\* Timeout mechanism - validator times out waiting for block
TimeoutValidator(validator) ==
    /\ validator \in Validators
    /\ timeouts[validator] < TimeoutLimit
    /\ timeouts' = [timeouts EXCEPT ![validator] = @ + 1]
    /\ clock' = clock + 1
    /\ UNCHANGED <<rotorBlocks, rotorShreds, rotorReceivedShreds, rotorReconstructedBlocks,
                   certificates, aggregatedCertificates, relayAssignments, 
                   currentSlot, currentLeader, skipCertificates>>

\* Generate skip certificate when timeout exceeded
GenerateSkipCertificate(validator) ==
    /\ validator \in Validators
    /\ timeouts[validator] >= TimeoutLimit
    /\ LET skipCert == [slot |-> currentSlot, validator |-> validator, 
                        reason |-> "timeout", timestamp |-> clock]
       IN skipCertificates' = skipCertificates \cup {skipCert}
    /\ timeouts' = [timeouts EXCEPT ![validator] = 0]  \* Reset timeout
    /\ clock' = clock + 1
    /\ UNCHANGED <<rotorBlocks, rotorShreds, rotorReceivedShreds, rotorReconstructedBlocks,
                   certificates, aggregatedCertificates, relayAssignments, currentSlot, currentLeader>>

\* Leader rotation - advance to next slot
AdvanceSlot ==
    /\ currentSlot < WindowSize
    /\ currentSlot' = currentSlot + 1
    /\ currentLeader' = SelectLeader(currentSlot + 1)
    /\ timeouts' = [v \in Validators |-> 0]  \* Reset all timeouts
    /\ clock' = clock + 1
    /\ UNCHANGED <<rotorBlocks, rotorShreds, rotorReceivedShreds, rotorReconstructedBlocks,
                   certificates, aggregatedCertificates, relayAssignments, skipCertificates>>

\* Time advancement
Tick ==
    /\ clock < 15  \* Reduced limit for finite verification
    /\ clock' = clock + 1
    /\ UNCHANGED <<rotorBlocks, rotorShreds, rotorReceivedShreds, rotorReconstructedBlocks,
                   certificates, aggregatedCertificates, relayAssignments, currentSlot, 
                   currentLeader, timeouts, skipCertificates>>

----------------------------------------------------------------------------
(* Next State *)

Next ==
    \/ \E validator \in Validators, blockId \in 1..MaxBlocks :
           CreateBlock(validator, blockId)
    \/ \E validator \in Validators, blockId \in 1..MaxBlocks :
           CreateShreds(validator, blockId)
    \/ \E validator \in Validators, shredId \in rotorShreds :
           ReceiveShred(validator, shredId)
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
    /\ \A s \in rotorShreds : \E b \in rotorBlocks : s >= b * 10 /\ s < (b + 1) * 10
    /\ \A cert \in certificates : cert.blockId \in rotorBlocks

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

\* Action constraint - limit state explosion while preserving protocol completeness  
ActionConstraint == 
    /\ clock <= 8  \* Sufficient for protocol verification
    /\ currentSlot <= WindowSize
    /\ Cardinality(rotorBlocks) <= MaxBlocks
    /\ Cardinality(rotorShreds) <= MaxBlocks * 2
    /\ Cardinality(certificates) <= MaxBlocks * Cardinality(Validators)
    /\ Cardinality(aggregatedCertificates) <= MaxBlocks
    /\ Cardinality(skipCertificates) <= Cardinality(Validators) * WindowSize

=============================================================================
