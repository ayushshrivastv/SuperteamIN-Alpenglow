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

\* Import foundational modules
INSTANCE Types WITH Validators <- Validators,
                    ByzantineValidators <- ByzantineValidators,
                    OfflineValidators <- OfflineValidators,
                    MaxSlot <- MaxSlot,
                    MaxView <- MaxView,
                    GST <- GST,
                    Delta <- Delta

INSTANCE Utils

\* Use consistent stake calculation
SumStake(f) == Utils!Sum(f)

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
    clock                \* Global clock for timing

voterVars == <<votorView, votorVotes, votorTimeouts, votorGeneratedCerts,
               votorFinalizedChain, votorState, votorObservedCerts, clock>>

----------------------------------------------------------------------------
(* Vote Types as required by the plan *)

\* Notarization vote for first round of slow path
NotarVote == [
    voter: Types!ValidatorId,
    slot: Types!Slot,
    block_hash: Types!BlockHash,
    validator_id: Types!ValidatorId,
    signature: Types!BLSSignature,
    timestamp: Types!TimeValue
]

\* Skip vote for timeout handling
SkipVote == [
    voter: Types!ValidatorId,
    slot: Types!Slot,
    reason: STRING,
    validator_id: Types!ValidatorId,
    signature: Types!BLSSignature,
    timestamp: Types!TimeValue
]

\* Finalization vote for second round of slow path
FinalizationVote == [
    voter: Types!ValidatorId,
    slot: Types!Slot,
    block_hash: Types!BlockHash,
    validator_id: Types!ValidatorId,
    signature: Types!BLSSignature,
    timestamp: Types!TimeValue
]

\* Union of all vote types
VoteUnion == NotarVote \cup SkipVote \cup FinalizationVote

----------------------------------------------------------------------------
(* Type Invariant *)

TypeInvariant ==
    /\ votorView \in [Validators -> 1..MaxView]
    /\ votorVotes \in [Validators -> SUBSET VoteUnion]
    /\ votorTimeouts \in [Validators -> [1..MaxSlot -> SUBSET Types!TimeValue]]
    /\ votorGeneratedCerts \in [1..MaxView -> SUBSET Types!Certificate]
    /\ votorFinalizedChain \in [Validators -> Seq(Types!Block)]
    /\ votorState \in [Validators -> [1..MaxSlot -> SUBSET STRING]]
    /\ votorObservedCerts \in [Validators -> SUBSET Types!Certificate]
    /\ clock \in Types!TimeValue

----------------------------------------------------------------------------
(* Timing and Threshold Functions *)

\* Fast path threshold (80% of total stake)
FastPathThreshold ==
    LET totalStake == Utils!TotalStake(Validators, Types!Stake)
    IN (4 * totalStake) \div 5

\* Slow path threshold (60% of total stake)
SlowPathThreshold ==
    LET totalStake == Utils!TotalStake(Validators, Types!Stake)
    IN (3 * totalStake) \div 5

\* Skip threshold (60% of total stake)
SkipThreshold == SlowPathThreshold

\* Timeout calculation with exponential backoff
ViewTimeout(view, baseTimeout) ==
    IF view = 1 THEN baseTimeout
    ELSE baseTimeout * (2 ^ ((view - 1) % 10))

\* Current slot calculation
CurrentSlot == clock \div Types!SlotDuration + 1

\* Check if timeout has expired
TimeoutExpired(validator, slot) ==
    \E timeout \in votorTimeouts[validator][slot] : clock >= timeout

----------------------------------------------------------------------------
(* Dual-Path Logic Implementation *)

\* Fast path voting for ≥80% stake single-round finalization
FastPathVoting(slot, block) ==
    LET notarVotes == {vote \in UNION {votorVotes[v] : v \in Validators} :
                        /\ vote \in NotarVote
                        /\ vote.slot = slot
                        /\ vote.block_hash = block.hash}
        voterStake == Utils!TotalStake({vote.voter : vote \in notarVotes}, Types!Stake)
    IN /\ voterStake >= FastPathThreshold
       /\ \A vote \in notarVotes : vote.signature.valid

\* Slow path voting for ≥60% stake two-round finalization
SlowPathVoting(slot, block) ==
    LET notarVotes == {vote \in UNION {votorVotes[v] : v \in Validators} :
                        /\ vote \in NotarVote
                        /\ vote.slot = slot
                        /\ vote.block_hash = block.hash}
        finalizationVotes == {vote \in UNION {votorVotes[v] : v \in Validators} :
                               /\ vote \in FinalizationVote
                               /\ vote.slot = slot
                               /\ vote.block_hash = block.hash}
        notarStake == Utils!TotalStake({vote.voter : vote \in notarVotes}, Types!Stake)
        finalizationStake == Utils!TotalStake({vote.voter : vote \in finalizationVotes}, Types!Stake)
    IN /\ notarStake >= SlowPathThreshold
       /\ finalizationStake >= SlowPathThreshold
       /\ \A vote \in notarVotes \cup finalizationVotes : vote.signature.valid

----------------------------------------------------------------------------
(* Certificate Generation Functions *)

\* Generate fast certificate from ≥80% stake votes
GenerateFastCert(slot, votes) ==
    LET notarVotes == {vote \in votes : vote \in NotarVote /\ vote.slot = slot}
        voterStake == Utils!TotalStake({vote.voter : vote \in notarVotes}, Types!Stake)
        blockHash == IF notarVotes # {} THEN (CHOOSE vote \in notarVotes : TRUE).block_hash ELSE 0
        signatures == Types!AggregateSignatures({vote.signature : vote \in notarVotes})
    IN IF voterStake >= FastPathThreshold
       THEN [slot |-> slot,
             view |-> 1,
             block |-> blockHash,
             type |-> "fast",
             signatures |-> signatures,
             validators |-> {vote.voter : vote \in notarVotes},
             stake |-> voterStake]
       ELSE CHOOSE x : FALSE  \* No certificate if threshold not met

\* Generate slow certificate from ≥60% stake votes in two rounds
GenerateSlowCert(slot, votes) ==
    LET notarVotes == {vote \in votes : vote \in NotarVote /\ vote.slot = slot}
        finalizationVotes == {vote \in votes : vote \in FinalizationVote /\ vote.slot = slot}
        notarStake == Utils!TotalStake({vote.voter : vote \in notarVotes}, Types!Stake)
        finalizationStake == Utils!TotalStake({vote.voter : vote \in finalizationVotes}, Types!Stake)
        blockHash == IF notarVotes # {} THEN (CHOOSE vote \in notarVotes : TRUE).block_hash ELSE 0
        allSignatures == {vote.signature : vote \in notarVotes \cup finalizationVotes}
        signatures == Types!AggregateSignatures(allSignatures)
    IN IF /\ notarStake >= SlowPathThreshold
          /\ finalizationStake >= SlowPathThreshold
       THEN [slot |-> slot,
             view |-> 1,
             block |-> blockHash,
             type |-> "slow",
             signatures |-> signatures,
             validators |-> {vote.voter : vote \in notarVotes \cup finalizationVotes},
             stake |-> finalizationStake]
       ELSE CHOOSE x : FALSE  \* No certificate if threshold not met

\* Generate skip certificate from ≥60% stake skip votes
GenerateSkipCert(slot, votes) ==
    LET skipVotes == {vote \in votes : vote \in SkipVote /\ vote.slot = slot}
        voterStake == Utils!TotalStake({vote.voter : vote \in skipVotes}, Types!Stake)
        signatures == Types!AggregateSignatures({vote.signature : vote \in skipVotes})
    IN IF voterStake >= SkipThreshold
       THEN [slot |-> slot,
             view |-> 1,
             block |-> 0,  \* No block for skip
             type |-> "skip",
             signatures |-> signatures,
             validators |-> {vote.voter : vote \in skipVotes},
             stake |-> voterStake]
       ELSE CHOOSE x : FALSE  \* No certificate if threshold not met

----------------------------------------------------------------------------
(* Voting Actions Implementation *)

\* Cast notarization vote for first round of slow path or fast path
CastNotarVote(validator, slot, block) ==
    /\ validator \in Validators
    /\ slot \in 1..MaxSlot
    /\ validator \in Types!HonestValidators  \* Only honest validators follow protocol
    /\ ~\E vote \in votorVotes[validator] :
        vote \in NotarVote /\ vote.slot = slot  \* One vote per slot
    /\ LET notarVote == [voter |-> validator,
                         slot |-> slot,
                         block_hash |-> block.hash,
                         validator_id |-> validator,
                         signature |-> Types!SignMessage(validator, block.hash),
                         timestamp |-> clock]
       IN votorVotes' = [votorVotes EXCEPT ![validator] = votorVotes[validator] \cup {notarVote}]
    /\ votorState' = [votorState EXCEPT ![validator][slot] = votorState[validator][slot] \cup {"Voted"}]
    /\ UNCHANGED <<votorView, votorTimeouts, votorGeneratedCerts, votorFinalizedChain, votorObservedCerts, clock>>

\* Cast skip vote for timeout handling
CastSkipVote(validator, slot, reason) ==
    /\ validator \in Validators
    /\ slot \in 1..MaxSlot
    /\ validator \in Types!HonestValidators
    /\ TimeoutExpired(validator, slot)  \* Only after timeout
    /\ ~\E vote \in votorVotes[validator] :
        vote \in SkipVote /\ vote.slot = slot  \* One skip vote per slot
    /\ LET skipVote == [voter |-> validator,
                        slot |-> slot,
                        reason |-> reason,
                        validator_id |-> validator,
                        signature |-> Types!SignMessage(validator, slot),
                        timestamp |-> clock]
       IN votorVotes' = [votorVotes EXCEPT ![validator] = votorVotes[validator] \cup {skipVote}]
    /\ votorState' = [votorState EXCEPT ![validator][slot] = votorState[validator][slot] \cup {"Skipped"}]
    /\ UNCHANGED <<votorView, votorTimeouts, votorGeneratedCerts, votorFinalizedChain, votorObservedCerts, clock>>

\* Cast finalization vote for second round of slow path
CastFinalizationVote(validator, slot, block) ==
    /\ validator \in Validators
    /\ slot \in 1..MaxSlot
    /\ validator \in Types!HonestValidators
    /\ "BlockNotarized" \in votorState[validator][slot]  \* Requires prior notarization
    /\ ~\E vote \in votorVotes[validator] :
        vote \in FinalizationVote /\ vote.slot = slot  \* One finalization vote per slot
    /\ LET finalizationVote == [voter |-> validator,
                                slot |-> slot,
                                block_hash |-> block.hash,
                                validator_id |-> validator,
                                signature |-> Types!SignMessage(validator, block.hash),
                                timestamp |-> clock]
       IN votorVotes' = [votorVotes EXCEPT ![validator] = votorVotes[validator] \cup {finalizationVote}]
    /\ votorState' = [votorState EXCEPT ![validator][slot] = votorState[validator][slot] \cup {"Finalized"}]
    /\ UNCHANGED <<votorView, votorTimeouts, votorGeneratedCerts, votorFinalizedChain, votorObservedCerts, clock>>

----------------------------------------------------------------------------
(* Timeout Mechanisms *)

\* Set timeout for a validator and slot
SetTimeout(validator, slot, timeout) ==
    /\ validator \in Validators
    /\ slot \in 1..MaxSlot
    /\ timeout \in Types!TimeValue
    /\ votorTimeouts' = [votorTimeouts EXCEPT ![validator][slot] = votorTimeouts[validator][slot] \cup {timeout}]
    /\ UNCHANGED <<votorView, votorVotes, votorGeneratedCerts, votorFinalizedChain, votorState, votorObservedCerts, clock>>

\* Handle timeout expiration
HandleTimeout(validator, slot) ==
    /\ validator \in Validators
    /\ slot \in 1..MaxSlot
    /\ TimeoutExpired(validator, slot)
    /\ "Voted" \notin votorState[validator][slot]  \* Haven't voted yet
    /\ CastSkipVote(validator, slot, "timeout")

----------------------------------------------------------------------------
(* Finalization Logic *)

\* Finalize block with certificate
FinalizeBlock(validator, slot, block, certificate) ==
    /\ validator \in Validators
    /\ slot \in 1..MaxSlot
    /\ certificate \in Types!Certificate
    /\ certificate.slot = slot
    /\ certificate.block = block.hash
    /\ certificate.type \in {"fast", "slow"}
    /\ ~\E b \in Range(votorFinalizedChain[validator]) : b.slot = slot  \* No duplicate slots
    /\ votorFinalizedChain' = [votorFinalizedChain EXCEPT ![validator] = Append(votorFinalizedChain[validator], block)]
    /\ votorState' = [votorState EXCEPT ![validator][slot] = votorState[validator][slot] \cup {"ItsOver"}]
    /\ UNCHANGED <<votorView, votorVotes, votorTimeouts, votorGeneratedCerts, votorObservedCerts, clock>>

\* Update finalized chain for validator
UpdateFinalizedChain(validator, block) ==
    /\ validator \in Validators
    /\ block \in Types!Block
    /\ ~\E b \in Range(votorFinalizedChain[validator]) : b.slot = block.slot
    /\ votorFinalizedChain' = [votorFinalizedChain EXCEPT ![validator] = Append(votorFinalizedChain[validator], block)]
    /\ UNCHANGED <<votorView, votorVotes, votorTimeouts, votorGeneratedCerts, votorState, votorObservedCerts, clock>>

----------------------------------------------------------------------------
(* Initialization *)

Init ==
    /\ clock = 0
    /\ votorView = [validator \in Validators |-> 1]
    /\ votorVotes = [validator \in Validators |-> {}]
    /\ votorTimeouts = [validator \in Validators |-> [slot \in 1..MaxSlot |-> {}]]
    /\ votorGeneratedCerts = [view \in 1..MaxView |-> {}]
    /\ votorFinalizedChain = [validator \in Validators |-> <<>>]
    /\ votorState = [validator \in Validators |-> [slot \in 1..MaxSlot |-> {}]]
    /\ votorObservedCerts = [validator \in Validators |-> {}]

----------------------------------------------------------------------------
(* Certificate Generation and Observation *)

\* Generate certificates when sufficient votes are collected
GenerateCertificates ==
    /\ \E slot \in 1..MaxSlot, view \in 1..MaxView :
        LET allVotes == UNION {votorVotes[v] : v \in Validators}
            slotVotes == {vote \in allVotes : vote.slot = slot}
        IN \/ /\ \E cert \in Types!Certificate : cert = GenerateFastCert(slot, slotVotes)
              /\ votorGeneratedCerts' = [votorGeneratedCerts EXCEPT ![view] = votorGeneratedCerts[view] \cup {cert}]
           \/ /\ \E cert \in Types!Certificate : cert = GenerateSlowCert(slot, slotVotes)
              /\ votorGeneratedCerts' = [votorGeneratedCerts EXCEPT ![view] = votorGeneratedCerts[view] \cup {cert}]
           \/ /\ \E cert \in Types!Certificate : cert = GenerateSkipCert(slot, slotVotes)
              /\ votorGeneratedCerts' = [votorGeneratedCerts EXCEPT ![view] = votorGeneratedCerts[view] \cup {cert}]
    /\ UNCHANGED <<votorView, votorVotes, votorTimeouts, votorFinalizedChain, votorState, votorObservedCerts, clock>>

\* Observe certificates from other validators
ObserveCertificate(validator, cert) ==
    /\ validator \in Validators
    /\ cert \in UNION {votorGeneratedCerts[view] : view \in 1..MaxView}
    /\ cert \notin votorObservedCerts[validator]
    /\ votorObservedCerts' = [votorObservedCerts EXCEPT ![validator] = votorObservedCerts[validator] \cup {cert}]
    /\ UNCHANGED <<votorView, votorVotes, votorTimeouts, votorGeneratedCerts, votorFinalizedChain, votorState, clock>>

\* Advance clock
AdvanceClock ==
    /\ clock' = clock + 1
    /\ UNCHANGED <<votorView, votorVotes, votorTimeouts, votorGeneratedCerts, votorFinalizedChain, votorState, votorObservedCerts>>

----------------------------------------------------------------------------
(* Next State Relation *)

Next ==
    \/ \E validator \in Validators, slot \in 1..MaxSlot, block \in Types!Block :
        CastNotarVote(validator, slot, block)
    \/ \E validator \in Validators, slot \in 1..MaxSlot, reason \in STRING :
        CastSkipVote(validator, slot, reason)
    \/ \E validator \in Validators, slot \in 1..MaxSlot, block \in Types!Block :
        CastFinalizationVote(validator, slot, block)
    \/ \E validator \in Validators, slot \in 1..MaxSlot, timeout \in Types!TimeValue :
        SetTimeout(validator, slot, timeout)
    \/ \E validator \in Validators, slot \in 1..MaxSlot :
        HandleTimeout(validator, slot)
    \/ \E validator \in Validators, slot \in 1..MaxSlot, block \in Types!Block, cert \in Types!Certificate :
        FinalizeBlock(validator, slot, block, cert)
    \/ \E validator \in Validators, block \in Types!Block :
        UpdateFinalizedChain(validator, block)
    \/ GenerateCertificates
    \/ \E validator \in Validators, cert \in Types!Certificate :
        ObserveCertificate(validator, cert)
    \/ AdvanceClock

----------------------------------------------------------------------------
(* Invariants as required by the plan *)

\* Voting protocol invariant - honest validators follow protocol rules
VotingProtocolInvariant ==
    \A validator \in Types!HonestValidators :
        \A vote \in votorVotes[validator] :
            /\ vote \in FinalizationVote =>
                \E priorVote \in votorVotes[validator] :
                    /\ priorVote \in NotarVote
                    /\ priorVote.slot = vote.slot
                    /\ "BlockNotarized" \in votorState[validator][vote.slot]
            /\ vote \in SkipVote =>
                TimeoutExpired(validator, vote.slot)

\* One vote per slot invariant - honest validators vote at most once per slot per type
OneVotePerSlot ==
    \A validator \in Types!HonestValidators :
        \A slot \in 1..MaxSlot :
            /\ Cardinality({vote \in votorVotes[validator] : vote \in NotarVote /\ vote.slot = slot}) <= 1
            /\ Cardinality({vote \in votorVotes[validator] : vote \in SkipVote /\ vote.slot = slot}) <= 1
            /\ Cardinality({vote \in votorVotes[validator] : vote \in FinalizationVote /\ vote.slot = slot}) <= 1

\* Valid certificate thresholds invariant
ValidCertificateThresholds ==
    \A view \in 1..MaxView :
        \A cert \in votorGeneratedCerts[view] :
            /\ cert.type = "fast" => cert.stake >= FastPathThreshold
            /\ cert.type = "slow" => cert.stake >= SlowPathThreshold
            /\ cert.type = "skip" => cert.stake >= SkipThreshold

\* Safety invariant - no conflicting blocks finalized in same slot
SafetyInvariant ==
    \A validator \in Validators :
        \A i, j \in DOMAIN votorFinalizedChain[validator] :
            votorFinalizedChain[validator][i].slot = votorFinalizedChain[validator][j].slot => i = j

\* Chain consistency invariant - finalized chains are consistent
ChainConsistencyInvariant ==
    \A v1, v2 \in Types!HonestValidators :
        \A i \in DOMAIN votorFinalizedChain[v1] :
            \A j \in DOMAIN votorFinalizedChain[v2] :
                /\ votorFinalizedChain[v1][i].slot = votorFinalizedChain[v2][j].slot
                => votorFinalizedChain[v1][i] = votorFinalizedChain[v2][j]

\* Liveness property - progress under good conditions
LivenessProperty ==
    \A slot \in 1..MaxSlot :
        \A validator \in Types!HonestValidators :
            <>(\E block \in Types!Block :
                /\ block.slot = slot
                /\ \E cert \in UNION {votorGeneratedCerts[view] : view \in 1..MaxView} :
                    /\ cert.slot = slot
                    /\ cert.type \in {"fast", "slow"}
                    => block \in Range(votorFinalizedChain[validator]))

\* Byzantine resilience property
ByzantineResilienceProperty ==
    LET byzantineStake == Utils!TotalStake(ByzantineValidators, Types!Stake)
        totalStake == Utils!TotalStake(Validators, Types!Stake)
    IN byzantineStake * 5 < totalStake => SafetyInvariant

\* Helper function for sequence range
Range(seq) == {seq[i] : i \in DOMAIN seq}

============================================================================
