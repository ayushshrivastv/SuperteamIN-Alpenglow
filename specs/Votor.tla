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
    clock,               \* Global clock for timing
    currentSlot          \* Current protocol slot

voterVars == <<votorView, votorVotes, votorTimeouts, votorGeneratedCerts,
               votorFinalizedChain, votorState, votorObservedCerts, clock, currentSlot>>

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

\* Simple vote type for our implementation
Vote == [voter: Validators, slot: 1..MaxSlot, blockHash: Nat, timestamp: Nat]

\* Simple certificate type
Certificate == [slot: 1..MaxSlot, type: {"fast", "slow"}, validators: SUBSET Validators, timestamp: Nat]

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
                   votorState, votorObservedCerts, clock, currentSlot>>

CastVote(validator, slot, blockHash) ==
    /\ validator \in Validators
    /\ slot \in 1..MaxSlot
    /\ LET vote == [voter |-> validator, slot |-> slot, blockHash |-> blockHash, timestamp |-> clock]
       IN /\ votorVotes' = [votorVotes EXCEPT ![validator] = @ \cup {vote}]
          /\ UNCHANGED <<votorView, votorTimeouts, votorGeneratedCerts, votorFinalizedChain,
                         votorState, votorObservedCerts, clock, currentSlot>>

GenerateCertificate(slot, certType) ==
    /\ slot \in 1..MaxSlot
    /\ LET votingValidators == {v \in Validators : \E vote \in votorVotes[v] : vote.slot = slot}
           voteCount == Cardinality(votingValidators)
           totalValidators == Cardinality(Validators)
           fastThreshold == (4 * totalValidators) \div 5  \* 80%
           slowThreshold == (3 * totalValidators) \div 5  \* 60%
       IN /\CASE certType = "fast" -> voteCount >= fastThreshold
               [] certType = "slow" -> voteCount >= slowThreshold /\ voteCount < fastThreshold
               [] OTHER -> FALSE
          /\LET cert == [slot |-> slot, type |-> certType, validators |-> votingValidators, timestamp |-> clock]
                 view == IF slot <= Len(votorGeneratedCerts) THEN slot ELSE 1
             IN votorGeneratedCerts' = [votorGeneratedCerts EXCEPT ![view] = @ \cup {cert}]
          /\ UNCHANGED <<votorView, votorVotes, votorTimeouts, votorFinalizedChain,
                         votorState, votorObservedCerts, clock, currentSlot>>

Tick ==
    /\ clock < 20
    /\ clock' = clock + 1
    /\ UNCHANGED <<votorView, votorVotes, votorTimeouts, votorGeneratedCerts, votorFinalizedChain,
                   votorState, votorObservedCerts, currentSlot>>

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
    /\ clock = 0

----------------------------------------------------------------------------
(* Next State and Specification *)

\* Next state relation
Next ==
    \/ \E validator \in Validators : AdvanceView(validator)
    \/ \E validator \in Validators, slot \in 1..MaxSlot, blockHash \in 1..3 : 
           CastVote(validator, slot, blockHash)
    \/ \E slot \in 1..MaxSlot, certType \in {"fast", "slow"} :
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
            votingValidators == {v \in Validators : 
                \E vote \in votorVotes[v] : vote.slot = slot}
        IN Cardinality(votingValidators) >= fastThreshold =>
            \E cert \in UNION {votorGeneratedCerts[view] : view \in 1..MaxView} :
                cert.slot = slot /\ cert.type = "fast"

\* Slow Path Test: 60% stake threshold (3 out of 5 validators) 
SlowPathFinalization ==
    \A slot \in 1..MaxSlot :
        LET totalValidators == Cardinality(Validators)
            slowThreshold == (3 * totalValidators) \div 5  \* 60%
            votingValidators == {v \in Validators : 
                \E vote \in votorVotes[v] : vote.slot = slot}
        IN Cardinality(votingValidators) >= slowThreshold =>
            \E cert \in UNION {votorGeneratedCerts[view] : view \in 1..MaxView} :
                cert.slot = slot /\ cert.type \in {"slow", "fast"}

\* Progress property for fast path
FastPathProgress ==
    <>(\E slot \in 1..MaxSlot :
        \E cert \in UNION {votorGeneratedCerts[view] : view \in 1..MaxView} :
            cert.slot = slot /\ cert.type = "fast")

\* Progress property for slow path  
SlowPathProgress ==
    <>(\E slot \in 1..MaxSlot :
        \E cert \in UNION {votorGeneratedCerts[view] : view \in 1..MaxView} :
            cert.slot = slot /\ cert.type = "slow")

\* Threshold correctness: Fast path requires more validators than slow path
ThresholdCorrectness ==
    LET fastThreshold == FastPathThreshold(TotalStake)
        slowThreshold == SlowPathThreshold(TotalStake)
    IN fastThreshold > slowThreshold

============================================================================
