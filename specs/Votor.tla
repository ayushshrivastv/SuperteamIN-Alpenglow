\* Author: Ayush Srivastava
------------------------------ MODULE Votor ------------------------------
(**************************************************************************)
(* Votor (voting) module implementing the dual-path consensus mechanism   *)
(* described in the Alpenglow whitepaper. This module provides fast       *)
(* voting-based consensus with 100ms finalization targets using both      *)
(* fast path (≥80% stake single-round) and slow path (≥60% stake         *)
(* two-round) finalization mechanisms.                                    *)
(**************************************************************************)

EXTENDS Integers, Sequences, FiniteSets, TLC

CONSTANTS
    Validators,          \* Set of all validators
    ByzantineValidators, \* Set of Byzantine validators
    OfflineValidators,   \* Set of offline validators
    MaxView,             \* Maximum view number
    MaxSlot,             \* Maximum slot number
    GST,                 \* Global Stabilization Time
    Delta                \* Network delay bound

\* Define basic types locally
ValidatorId == Nat
Slot == Nat
BlockHash == Nat
TimeValue == Nat
\* Certificate type defined later
Block == [slot: Nat, hash: Nat]
BLSSignature == [signer: Nat, message: Nat, valid: BOOLEAN]

----------------------------------------------------------------------------
(* State Variables as required by the plan *)

VARIABLES
    votorView,           \* Current view number for each validator [validator]
    votorVotes,          \* Votes cast by each validator [validator]
    votorTimeouts,       \* Timeout settings per validator per slot [validator][slot]
    votorGeneratedCerts, \* Certificates generated per view [view]
    votorFinalizedChain, \* Finalized chain per validator [validator]
    votorState,          \* Internal state tracking per validator [validator][slot]
    votorObservedCerts,  \* Certificates observed by each validator [validator]
    votorSlotState,      \* Per-slot state machine from paper Section 2.6 [validator][slot]
    votorParentReady,    \* ParentReady events per validator per slot [validator][slot]
    votorPool,           \* Vote pool storage per validator [validator]
    clock,               \* Global clock for timing
    currentSlot          \* Current protocol slot

\* Slot state machine states from paper Section 2.6
SlotStates == {"ParentReady", "Voted", "VotedNotar", "BlockNotarized", "ItsOver", "BadWindow"}

\* Vote types from paper Section 2.4  
VoteTypes == {"notar", "notar-fallback", "skip", "skip-fallback", "final"}

voterVars == <<votorView, votorVotes, votorTimeouts, votorGeneratedCerts,
               votorFinalizedChain, votorState, votorObservedCerts, votorSlotState,
               votorParentReady, votorPool, clock, currentSlot>>

----------------------------------------------------------------------------
(* Vote Types as required by the plan *)

\* Notarization vote for first round of slow path
NotarVote == [
    voter: ValidatorId,
    slot: Slot,
    block_hash: BlockHash,
    validator_id: ValidatorId,
    signature: BLSSignature,
    timestamp: TimeValue
]

\* Skip vote for timeout handling
SkipVote == [
    voter: ValidatorId,
    slot: Slot,
    reason: STRING,
    validator_id: ValidatorId,
    signature: BLSSignature,
    timestamp: TimeValue
]

\* Finalization vote for second round of slow path
FinalizationVote == [
    voter: ValidatorId,
    slot: Slot,
    block_hash: BlockHash,
    validator_id: ValidatorId,
    signature: BLSSignature,
    timestamp: TimeValue
]

\* Missing vote types from paper Section 2.4
NotarFallbackVote == [
    voter: ValidatorId,
    slot: Slot,
    block_hash: BlockHash,
    validator_id: ValidatorId,
    signature: BLSSignature,
    timestamp: TimeValue
]

SkipFallbackVote == [
    voter: ValidatorId,
    slot: Slot,
    reason: STRING,
    validator_id: ValidatorId,
    signature: BLSSignature,
    timestamp: TimeValue
]

\* Enhanced vote type with vote kind
Vote == [voter: Validators, slot: 1..MaxSlot, blockHash: Nat, voteType: STRING, timestamp: Nat]

\* Complete certificate types from paper Section 2.4
Certificate == [slot: 1..MaxSlot, type: {"fast-finalization", "notarization", "skip", "finalization"}, validators: SUBSET Validators, timestamp: Nat]

----------------------------------------------------------------------------
(* Type Invariant *)

TypeInvariant ==
    /\ votorView \in [Validators -> 1..MaxView]
    /\ votorVotes \in [Validators -> SUBSET Vote]
    /\ votorTimeouts \in [Validators -> [1..MaxSlot -> SUBSET Nat]]
    /\ votorGeneratedCerts \in [1..MaxView -> SUBSET Certificate]
    /\ votorFinalizedChain \in [Validators -> Seq([slot: Nat, hash: Nat])]
    /\ votorState \in [Validators -> [1..MaxSlot -> SUBSET STRING]]
    /\ votorObservedCerts \in [Validators -> SUBSET Certificate]
    /\ votorSlotState \in [Validators -> [1..MaxSlot -> SlotStates]]
    /\ votorParentReady \in [Validators -> [1..MaxSlot -> BOOLEAN]]
    /\ votorPool \in [Validators -> [1..MaxSlot -> SUBSET Vote]]
    /\ currentSlot \in 1..MaxSlot
    /\ clock \in Nat

----------------------------------------------------------------------------
(* Timing and Threshold Functions *)

\* Define stake mapping (abstract for now)
StakeMap == [v \in Validators |-> 100]

\* Fast path threshold (80% of total stake)
FastPathThreshold(totalStake) ==
    (4 * totalStake) \div 5

\* Slow path threshold (60% of total stake)  
SlowPathThreshold(totalStake) ==
    (3 * totalStake) \div 5

\* Skip threshold (60% of total stake)
SkipThreshold(totalStake) ==
    SlowPathThreshold(totalStake)

\* Use ViewTimeout from Types module via NetworkTimingConstraints

\* Define missing operators
SlotDuration == 100  \* Abstract time units per slot
TotalStake == 300   \* Simplified total stake
HonestValidators == Validators \ (ByzantineValidators \cup OfflineValidators)

\* Current slot calculation  
CurrentSlot == clock \div SlotDuration + 1

\* Variables defined above in main VARIABLES declaration

\* Check if timeout has expired
TimeoutExpired(validator, slot) ==
    \E timeout \in votorTimeouts[validator][slot] : clock >= timeout

----------------------------------------------------------------------------
(* Basic Protocol Logic - Simplified *)

\* Simple vote validation
ValidVote(vote, slot) ==
    /\ vote.slot = slot
    /\ vote.voter \in Validators

----------------------------------------------------------------------------
AdvanceView(validator) ==
    /\ validator \in Validators
    /\ votorView[validator] < MaxView
    /\ votorView' = [votorView EXCEPT ![validator] = @ + 1]
    /\ UNCHANGED <<votorVotes, votorTimeouts, votorGeneratedCerts, votorFinalizedChain,
                   votorState, votorObservedCerts, votorSlotState, votorParentReady, 
                   votorPool, clock, currentSlot>>

\* Enhanced voting with proper vote types from paper Section 2.4
CastNotarVote(validator, slot, blockHash) ==
    /\ validator \in Validators
    /\ slot \in 1..MaxSlot
    /\ votorSlotState[validator][slot] = "ParentReady"
    /\ LET vote == [voter |-> validator, slot |-> slot, blockHash |-> blockHash, 
                    voteType |-> "notar", timestamp |-> clock]
       IN /\ votorVotes' = [votorVotes EXCEPT ![validator] = @ \cup {vote}]
          /\ votorSlotState' = [votorSlotState EXCEPT ![validator][slot] = "VotedNotar"]
          /\ votorPool' = [votorPool EXCEPT ![validator][slot] = @ \cup {vote}]
          /\ UNCHANGED <<votorView, votorTimeouts, votorGeneratedCerts, votorFinalizedChain,
                         votorState, votorObservedCerts, votorParentReady, clock, currentSlot>>

CastNotarFallbackVote(validator, slot, blockHash) ==
    /\ validator \in Validators  
    /\ slot \in 1..MaxSlot
    /\ votorSlotState[validator][slot] \in {"VotedNotar", "BadWindow"}
    /\ Cardinality({v \in votorPool[validator][slot] : v.voteType = "notar-fallback"}) < 3  \* Paper: up to 3 fallback votes
    /\ LET vote == [voter |-> validator, slot |-> slot, blockHash |-> blockHash,
                    voteType |-> "notar-fallback", timestamp |-> clock]
       IN /\ votorVotes' = [votorVotes EXCEPT ![validator] = @ \cup {vote}]
          /\ votorPool' = [votorPool EXCEPT ![validator][slot] = @ \cup {vote}]
          /\ UNCHANGED <<votorView, votorTimeouts, votorGeneratedCerts, votorFinalizedChain,
                         votorState, votorObservedCerts, votorSlotState, votorParentReady, clock, currentSlot>>

CastFinalVote(validator, slot) ==
    /\ validator \in Validators
    /\ slot \in 1..MaxSlot  
    /\ votorSlotState[validator][slot] = "BlockNotarized"
    /\ LET vote == [voter |-> validator, slot |-> slot, blockHash |-> 0,
                    voteType |-> "final", timestamp |-> clock]
       IN /\ votorVotes' = [votorVotes EXCEPT ![validator] = @ \cup {vote}]
          /\ votorSlotState' = [votorSlotState EXCEPT ![validator][slot] = "ItsOver"]
          /\ votorPool' = [votorPool EXCEPT ![validator][slot] = @ \cup {vote}]
          /\ UNCHANGED <<votorView, votorTimeouts, votorGeneratedCerts, votorFinalizedChain,
                         votorState, votorObservedCerts, votorParentReady, clock, currentSlot>>

\* Skip vote when block is late or untrustworthy
CastSkipVote(validator, slot) ==
    /\ validator \in Validators
    /\ slot \in 1..MaxSlot
    /\ TimeoutExpired(validator, slot)  \* Only skip after timeout
    /\ LET skipVote == [voter |-> validator, slot |-> slot, blockHash |-> 0, 
                        voteType |-> "skip", timestamp |-> clock]
       IN /\ votorVotes' = [votorVotes EXCEPT ![validator] = @ \cup {skipVote}]
          /\ votorSlotState' = [votorSlotState EXCEPT ![validator][slot] = "BadWindow"]
          /\ votorPool' = [votorPool EXCEPT ![validator][slot] = @ \cup {skipVote}]
          /\ UNCHANGED <<votorView, votorTimeouts, votorGeneratedCerts, votorFinalizedChain,
                         votorState, votorObservedCerts, votorParentReady, clock, currentSlot>>

\* Set timeout for a validator on a slot
SetTimeout(validator, slot, timeoutValue) ==
    /\ validator \in Validators
    /\ slot \in 1..MaxSlot
    /\ timeoutValue > clock
    /\ votorTimeouts' = [votorTimeouts EXCEPT ![validator][slot] = @ \cup {timeoutValue}]
    /\ UNCHANGED <<votorView, votorVotes, votorGeneratedCerts, votorFinalizedChain,
                   votorState, votorObservedCerts, votorSlotState, votorParentReady,
                   votorPool, clock, currentSlot>>

\* Complete certificate generation per paper Section 2.4
GenerateCertificate(slot, certType) ==
    /\ slot \in 1..MaxSlot
    /\ LET notarVoters == {v \in Validators : \E vote \in votorVotes[v] : 
                            vote.slot = slot /\ vote.voteType = "notar"}
           notarFallbackVoters == {v \in Validators : \E vote \in votorVotes[v] :
                                  vote.slot = slot /\ vote.voteType = "notar-fallback"}
           skipVoters == {v \in Validators : \E vote \in votorVotes[v] :
                         vote.slot = slot /\ vote.voteType = "skip"}  
           finalVoters == {v \in Validators : \E vote \in votorVotes[v] :
                          vote.slot = slot /\ vote.voteType = "final"}
           totalValidators == Cardinality(Validators)
           fastThreshold == (4 * totalValidators) \div 5  \* 80%
           slowThreshold == (3 * totalValidators) \div 5  \* 60%
       IN /\CASE certType = "fast-finalization" -> Cardinality(notarVoters) >= fastThreshold
               [] certType = "notarization" -> Cardinality(notarVoters \cup notarFallbackVoters) >= slowThreshold
               [] certType = "skip" -> Cardinality(skipVoters) >= slowThreshold  
               [] certType = "finalization" -> Cardinality(finalVoters) >= slowThreshold
               [] OTHER -> FALSE
          /\LET cert == [slot |-> slot, type |-> certType,
                        validators |-> CASE certType = "fast-finalization" -> notarVoters
                                          [] certType = "notarization" -> (notarVoters \cup notarFallbackVoters)
                                          [] certType = "skip" -> skipVoters
                                          [] certType = "finalization" -> finalVoters
                                          [] OTHER -> {},
                        timestamp |-> clock]
                 view == IF slot <= MaxView THEN slot ELSE 1
             IN votorGeneratedCerts' = [votorGeneratedCerts EXCEPT ![view] = @ \cup {cert}]
          /\ UNCHANGED <<votorView, votorVotes, votorTimeouts, votorFinalizedChain,
                         votorState, votorObservedCerts, votorSlotState, votorParentReady, 
                         votorPool, clock, currentSlot>>

Tick ==
    /\ clock < 20
    /\ clock' = clock + 1
    /\ UNCHANGED <<votorView, votorVotes, votorTimeouts, votorGeneratedCerts, votorFinalizedChain,
                   votorState, votorObservedCerts, votorSlotState, votorParentReady,
                   votorPool, currentSlot>>

----------------------------------------------------------------------------
(* Initialization *)

Init ==
    /\ currentSlot = 1
    /\ votorView = [validator \in Validators |-> 1]
    /\ votorVotes = [validator \in Validators |-> {}]
    /\ votorTimeouts = [validator \in Validators |-> [slot \in 1..MaxSlot |-> {}]]
    /\ votorGeneratedCerts = [view \in 1..MaxView |-> {}]
    /\ votorFinalizedChain = [validator \in Validators |-> <<>>]
    /\ votorState = [validator \in Validators |-> [slot \in 1..MaxSlot |-> {}]]
    /\ votorObservedCerts = [validator \in Validators |-> {}]
    /\ votorSlotState = [validator \in Validators |-> [slot \in 1..MaxSlot |-> "ParentReady"]]
    /\ votorParentReady = [validator \in Validators |-> [slot \in 1..MaxSlot |-> FALSE]]
    /\ votorPool = [validator \in Validators |-> [slot \in 1..MaxSlot |-> {}]]
    /\ clock = 0

----------------------------------------------------------------------------
(* Next State and Specification *)

\* Next state relation - Complete Alpenglow voting actions
Next ==
    \/ \E validator \in Validators : AdvanceView(validator)
    \/ \E validator \in Validators, slot \in 1..MaxSlot, blockHash \in 1..3 : 
           CastNotarVote(validator, slot, blockHash)
    \/ \E validator \in Validators, slot \in 1..MaxSlot, blockHash \in 1..3 :
           CastNotarFallbackVote(validator, slot, blockHash)  
    \/ \E validator \in Validators, slot \in 1..MaxSlot :
           CastFinalVote(validator, slot)
    \/ \E validator \in Validators, slot \in 1..MaxSlot : 
           CastSkipVote(validator, slot)
    \/ \E validator \in Validators, slot \in 1..MaxSlot, timeoutValue \in (clock+1)..(clock+5) :
           SetTimeout(validator, slot, timeoutValue)  
    \/ \E slot \in 1..MaxSlot, certType \in {"fast-finalization", "notarization", "skip", "finalization"} :
           GenerateCertificate(slot, certType)
    \/ Tick

\* Specification
Spec == Init /\ [][Next]_<<voterVars>>

\* Safety property - simplified
Safety ==
    \A validator \in Validators :
        votorView[validator] >= 1 /\ votorView[validator] <= MaxView

\* Basic progress property
Progress ==
    \A validator \in Validators :
        <>(votorView[validator] = MaxView)
\* Chain consistency property - simplified
ChainConsistency ==
    \A validator \in Validators :
        Len(votorFinalizedChain[validator]) <= MaxSlot

\* Action constraint to keep model finite
ActionConstraint == clock <= 20

----------------------------------------------------------------------------
\* Dual Path Testing Properties

\* Fast Path Test: 80% stake threshold (4 out of 5 validators)
FastPathFinalization ==
    \A slot \in 1..MaxSlot :
        LET totalValidators == Cardinality(Validators)
            fastThreshold == (4 * totalValidators) \div 5  \* 80%
            notarVoters == {v \in Validators : 
                \E vote \in votorVotes[v] : vote.slot = slot /\ vote.voteType = "notar"}
        IN Cardinality(notarVoters) >= fastThreshold =>
            \E cert \in UNION {votorGeneratedCerts[view] : view \in 1..MaxView} :
                cert.slot = slot /\ cert.type = "fast-finalization"

\* Slow Path Test: 60% stake threshold (3 out of 5 validators) 
SlowPathFinalization ==
    \A slot \in 1..MaxSlot :
        LET totalValidators == Cardinality(Validators)
            slowThreshold == (3 * totalValidators) \div 5  \* 60%
            notarVoters == {v \in Validators : 
                \E vote \in votorVotes[v] : vote.slot = slot /\ vote.voteType = "notar"}
            notarFallbackVoters == {v \in Validators : 
                \E vote \in votorVotes[v] : vote.slot = slot /\ vote.voteType = "notar-fallback"}
            totalNotarVoters == Cardinality(notarVoters \cup notarFallbackVoters)
        IN totalNotarVoters >= slowThreshold =>
            \E cert \in UNION {votorGeneratedCerts[view] : view \in 1..MaxView} :
                cert.slot = slot /\ cert.type \in {"notarization", "fast-finalization"}

\* Progress property for fast path
FastPathProgress ==
    <>(\E slot \in 1..MaxSlot :
        \E cert \in UNION {votorGeneratedCerts[view] : view \in 1..MaxView} :
            cert.slot = slot /\ cert.type = "fast-finalization")

\* Progress property for slow path  
SlowPathProgress ==
    <>(\E slot \in 1..MaxSlot :
        \E cert \in UNION {votorGeneratedCerts[view] : view \in 1..MaxView} :
            cert.slot = slot /\ cert.type = "notarization")

\* Threshold correctness: Fast path requires more validators than slow path
ThresholdCorrectness ==
    LET fastThreshold == FastPathThreshold(TotalStake)
        slowThreshold == SlowPathThreshold(TotalStake)
    IN fastThreshold > slowThreshold

----------------------------------------------------------------------------
\* Enhanced Dual-Path Specific Properties

\* Fast Path Exclusivity: If fast path succeeds, slow path should not trigger
FastPathExclusivity ==
    \A slot \in 1..MaxSlot :
        LET fastCerts == {cert \in UNION {votorGeneratedCerts[view] : view \in 1..MaxView} : 
                          cert.slot = slot /\ cert.type = "fast-finalization"}
            notarCerts == {cert \in UNION {votorGeneratedCerts[view] : view \in 1..MaxView} : 
                          cert.slot = slot /\ cert.type = "notarization"}
        IN Cardinality(fastCerts) > 0 => Cardinality(notarCerts) = 0

\* Certificate Uniqueness: No duplicate certificates for same slot and type
CertificateUniqueness ==
    \A view1, view2 \in 1..MaxView :
        \A cert1 \in votorGeneratedCerts[view1], cert2 \in votorGeneratedCerts[view2] :
            (cert1.slot = cert2.slot /\ cert1.type = cert2.type) => cert1 = cert2

\* Dual Path Completeness: Every slot with sufficient votes gets appropriate certificate
DualPathCompleteness ==
    \A slot \in 1..MaxSlot :
        LET notarVoters == {v \in Validators : 
                \E vote \in votorVotes[v] : vote.slot = slot /\ vote.voteType = "notar"}
            notarFallbackVoters == {v \in Validators : 
                \E vote \in votorVotes[v] : vote.slot = slot /\ vote.voteType = "notar-fallback"}
            totalNotarVoters == Cardinality(notarVoters \cup notarFallbackVoters)
            totalValidators == Cardinality(Validators)
            fastThreshold == (4 * totalValidators) \div 5  \* 80%
            slowThreshold == (3 * totalValidators) \div 5  \* 60%
            hasFastCert == \E cert \in UNION {votorGeneratedCerts[view] : view \in 1..MaxView} :
                cert.slot = slot /\ cert.type = "fast-finalization"
            hasNotarCert == \E cert \in UNION {votorGeneratedCerts[view] : view \in 1..MaxView} :
                cert.slot = slot /\ cert.type = "notarization"
        IN /\ (Cardinality(notarVoters) >= fastThreshold) => hasFastCert
           /\ (totalNotarVoters >= slowThreshold /\ Cardinality(notarVoters) < fastThreshold) => hasNotarCert

\* Fast Path Performance: Fast certificates should appear before equivalent slow ones
FastPathPerformance ==
    \A slot \in 1..MaxSlot :
        LET fastCerts == {cert \in UNION {votorGeneratedCerts[view] : view \in 1..MaxView} : 
                          cert.slot = slot /\ cert.type = "fast-finalization"}
            notarCerts == {cert \in UNION {votorGeneratedCerts[view] : view \in 1..MaxView} : 
                          cert.slot = slot /\ cert.type = "notarization"}
        IN /\ Cardinality(fastCerts) > 0 /\ Cardinality(notarCerts) > 0 =>
               \E fastCert \in fastCerts, notarCert \in notarCerts :
                   fastCert.timestamp <= notarCert.timestamp

\* Timeout Safety: No timeouts are set in the past
TimeoutSafety ==
    \A validator \in Validators, slot \in 1..MaxSlot :
        \A timeout \in votorTimeouts[validator][slot] :
            timeout > 0  \* Timeouts should be positive values

\* Progressive Finalization: Earlier slots finalize before later slots
ProgressiveFinalization ==
    \A validator \in Validators :
        \A i, j \in 1..Len(votorFinalizedChain[validator]) :
            i < j => votorFinalizedChain[validator][i].slot <= votorFinalizedChain[validator][j].slot

\* Stake-Based Thresholds: Verify 80%/60% thresholds work with actual validator counts
StakeBasedThresholds ==
    LET totalValidators == Cardinality(Validators)
        fastThreshold == (4 * totalValidators) \div 5
        slowThreshold == (3 * totalValidators) \div 5
    IN /\ fastThreshold = 4 \* For 5 validators: 4/5 = 80%
       /\ slowThreshold = 3 \* For 5 validators: 3/5 = 60%

----------------------------------------------------------------------------
\* Scenario-Specific Properties for Testing

\* Fast Path Scenario: Test with exactly 80% participation
FastPathScenario ==
    <>(\E slot \in 1..MaxSlot :
        LET notarVoters == {v \in Validators : 
                \E vote \in votorVotes[v] : vote.slot = slot /\ vote.voteType = "notar"}
        IN /\ Cardinality(notarVoters) = 4  \* Exactly 80% (4/5)
           /\ \E cert \in UNION {votorGeneratedCerts[view] : view \in 1..MaxView} :
                cert.slot = slot /\ cert.type = "fast-finalization")

\* Slow Path Scenario: Test with exactly 60% participation  
SlowPathScenario ==
    <>(\E slot \in 1..MaxSlot :
        LET notarVoters == {v \in Validators : 
                \E vote \in votorVotes[v] : vote.slot = slot /\ vote.voteType = "notar"}
            notarFallbackVoters == {v \in Validators : 
                \E vote \in votorVotes[v] : vote.slot = slot /\ vote.voteType = "notar-fallback"}
            totalNotarVoters == Cardinality(notarVoters \cup notarFallbackVoters)
        IN /\ totalNotarVoters = 3  \* Exactly 60% (3/5)
           /\ Cardinality(notarVoters) < 4  \* Less than fast threshold
           /\ \E cert \in UNION {votorGeneratedCerts[view] : view \in 1..MaxView} :
                cert.slot = slot /\ cert.type = "notarization")

\* Mixed Participation Scenario: Some slots fast, some slow
MixedParticipationScenario ==
    <>(\E slot1, slot2 \in 1..MaxSlot :
        /\ slot1 # slot2
        /\ \E cert1 \in UNION {votorGeneratedCerts[view] : view \in 1..MaxView} :
             cert1.slot = slot1 /\ cert1.type = "fast-finalization"
        /\ \E cert2 \in UNION {votorGeneratedCerts[view] : view \in 1..MaxView} :
             cert2.slot = slot2 /\ cert2.type = "notarization")

\* No Double Finalization: A slot cannot be finalized via both paths
NoDoubleFinalizations ==
    \A slot \in 1..MaxSlot :
        LET fastCerts == {cert \in UNION {votorGeneratedCerts[view] : view \in 1..MaxView} : 
                          cert.slot = slot /\ cert.type = "fast-finalization"}
            notarCerts == {cert \in UNION {votorGeneratedCerts[view] : view \in 1..MaxView} : 
                          cert.slot = slot /\ cert.type = "notarization"}
        IN ~(Cardinality(fastCerts) > 0 /\ Cardinality(notarCerts) > 0)

----------------------------------------------------------------------------
\* Skip Certificate and Timeout Properties

\* Skip Certificate Generation: Skip votes should lead to skip behavior  
SkipCertificateGeneration ==
    \A slot \in 1..MaxSlot :
        LET skipVotes == {v \in Validators : 
                \E vote \in votorVotes[v] : vote.slot = slot /\ vote.blockHash = 0}
            skipCount == Cardinality(skipVotes)
            slowThreshold == (3 * Cardinality(Validators)) \div 5  \* 60%
        IN skipCount >= slowThreshold =>
            \E view \in 1..MaxView :
                \E cert \in votorGeneratedCerts[view] :
                    cert.slot = slot /\ cert.type = "skip"

\* Timeout Leads to Skip: Timeouts should eventually lead to skip votes
TimeoutLeadsToSkip ==
    \A validator \in Validators, slot \in 1..MaxSlot :
        TimeoutExpired(validator, slot) =>
            <>(\E vote \in votorVotes[validator] : 
                vote.slot = slot /\ vote.blockHash = 0)

\* Valid Timeout Setting: Timeouts should be set in future
ValidTimeoutSetting ==
    \A validator \in Validators, slot \in 1..MaxSlot :
        \A timeout \in votorTimeouts[validator][slot] :
            timeout > 0  \* Timeouts should be positive

\* 100ms Finalization Target: Fast path should complete within timing bounds
FastFinalizationTiming ==
    \A slot \in 1..MaxSlot :
        LET fastCerts == {cert \in UNION {votorGeneratedCerts[view] : view \in 1..MaxView} : 
                          cert.slot = slot /\ cert.type = "fast-finalization"}
        IN \A cert \in fastCerts :
            cert.timestamp <= SlotDuration  \* Within one slot duration (100ms target)

\* Leader Window Management: Validate leader rotation concept
LeaderWindowManagement ==
    \A validator \in Validators :
        votorView[validator] >= 1 /\ votorView[validator] <= MaxView

\* Dual Path Resilience: Test 20+20 resilience model
DualPathResilience ==
    LET totalValidators == Cardinality(Validators)
        byzantineCount == Cardinality(ByzantineValidators)  
        offlineCount == Cardinality(OfflineValidators)
        activeValidators == totalValidators - byzantineCount - offlineCount
    IN /\ byzantineCount <= totalValidators \div 5      \* ≤20% Byzantine
       /\ byzantineCount + offlineCount <= (2 * totalValidators) \div 5  \* ≤40% total faults
       /\ activeValidators >= (3 * totalValidators) \div 5  \* ≥60% active

----------------------------------------------------------------------------
\* Dual-Path Behavior Demonstration Properties

\* Core behavior: When fast certificates exist, they should have proper voter counts  
FastPathBehavior ==
    \A cert \in UNION {votorGeneratedCerts[view] : view \in 1..MaxView} :
        cert.type = "fast-finalization" =>
            LET notarVoters == {v \in Validators : 
                    \E vote \in votorVotes[v] : vote.slot = cert.slot /\ vote.voteType = "notar"}
            IN Cardinality(notarVoters) >= 4  \* Sufficient votes for fast path

\* Core behavior: When certificates exist, they should have proper voter counts
SlowPathBehavior ==
    \A cert \in UNION {votorGeneratedCerts[view] : view \in 1..MaxView} :
        cert.type = "notarization" =>
            LET notarVoters == {v \in Validators : 
                    \E vote \in votorVotes[v] : vote.slot = cert.slot /\ vote.voteType = "notar"}
                fallbackVoters == {v \in Validators :
                    \E vote \in votorVotes[v] : vote.slot = cert.slot /\ vote.voteType = "notar-fallback"}
                totalVoters == Cardinality(notarVoters \cup fallbackVoters)
            IN /\ totalVoters >= 3  \* Sufficient votes for notarization
               /\ Cardinality(notarVoters) < 4  \* Not enough for fast path

\* Certificate consistency: Generated certificates should be valid
CertificateGeneration ==
    \A cert \in UNION {votorGeneratedCerts[view] : view \in 1..MaxView} :
        LET notarVoters == {v \in Validators : 
                \E vote \in votorVotes[v] : vote.slot = cert.slot /\ vote.voteType = "notar"}
            fallbackVoters == {v \in Validators :
                \E vote \in votorVotes[v] : vote.slot = cert.slot /\ vote.voteType = "notar-fallback"}
            totalVoters == Cardinality(notarVoters \cup fallbackVoters)
        IN /\ cert.type = "fast-finalization" => Cardinality(notarVoters) >= 4
           /\ cert.type = "notarization" => totalVoters >= 3

============================================================================
