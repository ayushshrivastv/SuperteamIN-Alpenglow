---------------------------- MODULE CompleteSpecification ----------------------------
(***************************************************************************)
(* Complete Formal Specification of the Alpenglow Consensus Protocol      *)
(*                                                                         *)
(* This specification integrates all core components of the Alpenglow      *)
(* protocol into a single, comprehensive formal model for submission       *)
(* evaluation. It combines:                                                *)
(*                                                                         *)
(* 1. Votor: Dual-path consensus mechanism with fast (80% stake) and      *)
(*    slow (60% stake) finalization paths                                 *)
(* 2. Rotor: Erasure-coded block propagation with stake-weighted relay    *)
(*    selection for efficient bandwidth utilization                       *)
(* 3. Certificate generation and aggregation with BLS signatures          *)
(* 4. Timeout mechanisms and skip certificate handling                    *)
(* 5. Leader rotation with 4-slot windows and VRF-based selection         *)
(* 6. Network model with partial synchrony and GST assumptions            *)
(* 7. Cryptographic abstractions and type system                          *)
(*                                                                         *)
(* The protocol achieves 100-150ms finalization times while maintaining   *)
(* safety under up to 20% Byzantine stake and liveness under up to 20%    *)
(* offline stake, providing a combined "20+20" resilience model.          *)
(***************************************************************************)

EXTENDS Integers, Sequences, FiniteSets, TLC

(***************************************************************************)
(* CONSTANTS AND PARAMETERS                                                *)
(***************************************************************************)

CONSTANTS
    \* Validator Set Configuration
    Validators,          \* Set of all validators in the network
    ByzantineValidators, \* Set of Byzantine (malicious) validators
    OfflineValidators,   \* Set of offline (non-responsive) validators
    
    \* Protocol Bounds
    MaxSlot,             \* Maximum slot number for model checking
    MaxView,             \* Maximum view number for timeout handling
    
    \* Timing Parameters
    GST,                 \* Global Stabilization Time (partial synchrony)
    Delta,               \* Network delay bound after GST
    SlotDuration,        \* Duration of each slot in milliseconds
    
    \* Erasure Coding Parameters
    K,                   \* Number of data shreds (minimum for reconstruction)
    N,                   \* Total number of shreds (data + parity)
    
    \* Network and Performance Limits
    BandwidthLimit,      \* Per-validator bandwidth limit
    MaxRetries,          \* Maximum repair request retries
    MaxBufferSize        \* Maximum message buffer size per validator

(***************************************************************************)
(* PROTOCOL ASSUMPTIONS                                                    *)
(***************************************************************************)

ASSUME
    \* Validator set relationships
    /\ ByzantineValidators \subseteq Validators
    /\ OfflineValidators \subseteq Validators
    /\ ByzantineValidators \cap OfflineValidators = {}
    
    \* Timing constraints
    /\ GST >= 0
    /\ Delta > 0
    /\ SlotDuration > 0
    
    \* Erasure coding constraints
    /\ N > K
    /\ K > 0
    /\ K >= (2 * Cardinality(Validators)) \div 3  \* Reconstruction threshold
    
    \* Network constraints
    /\ BandwidthLimit > 0
    /\ MaxRetries > 0
    /\ MaxBufferSize > 0
    
    \* Protocol bounds
    /\ MaxSlot > 0
    /\ MaxView > 0

(***************************************************************************)
(* TYPE DEFINITIONS AND CRYPTOGRAPHIC ABSTRACTIONS                        *)
(***************************************************************************)

\* Basic type definitions
ValidatorId == Nat
SlotNumber == Nat
ViewNumber == Nat
TimeValue == Nat
Hash == Nat
MessageHash == Hash
BlockHash == Hash

\* Validator classifications
HonestValidators == Validators \ (ByzantineValidators \cup OfflineValidators)

\* Stake distribution (stake-weighted consensus)
Stake == [v \in Validators |->
    IF v \in ByzantineValidators THEN 150      \* 15% stake
    ELSE IF v \in OfflineValidators THEN 100   \* 10% stake  
    ELSE 200]                                  \* 20% stake for honest validators

\* Cryptographic signature abstraction
Signature == [
    signer: ValidatorId,
    message: MessageHash,
    valid: BOOLEAN
]

\* BLS signature for aggregation
BLSSignature == [
    signer: ValidatorId,
    message: MessageHash,
    valid: BOOLEAN,
    aggregatable: BOOLEAN
]

\* Aggregated signature collection
AggregatedSignature == [
    signers: SUBSET ValidatorId,
    message: MessageHash,
    signatures: SUBSET BLSSignature,
    valid: BOOLEAN
]

\* Transaction structure
Transaction == [
    id: Nat,
    sender: ValidatorId,
    data: Seq(Nat),
    signature: Signature
]

\* Block structure with all required fields
Block == [
    slot: SlotNumber,
    view: ViewNumber,
    hash: BlockHash,
    parent: BlockHash,
    proposer: ValidatorId,
    transactions: SUBSET Transaction,
    timestamp: TimeValue,
    signature: Signature,
    data: Seq(Nat)
]

\* Certificate types for dual-path consensus
CertificateType == {"fast", "slow", "skip"}

\* Certificate structure
Certificate == [
    slot: SlotNumber,
    view: ViewNumber,
    block: BlockHash,
    type: CertificateType,
    signatures: AggregatedSignature,
    validators: SUBSET ValidatorId,
    stake: Nat
]

\* Vote types for consensus phases
VoteType == {"notarization", "finalization", "skip"}

\* Vote structure
Vote == [
    voter: ValidatorId,
    slot: SlotNumber,
    view: ViewNumber,
    block: BlockHash,
    type: VoteType,
    signature: BLSSignature,
    timestamp: TimeValue
]

\* Erasure-coded piece for block propagation
ErasureCodedPiece == [
    blockId: BlockHash,
    slot: SlotNumber,
    index: Nat,
    data: Seq(Nat),
    isParity: BOOLEAN,
    merkleProof: Seq(Nat),
    signature: Signature
]

\* Repair request for missing shreds
RepairRequest == [
    requester: ValidatorId,
    blockId: BlockHash,
    slot: SlotNumber,
    missingIndices: SUBSET Nat,
    timestamp: TimeValue
]

\* Network message types
MessageType == {"block", "vote", "certificate", "shred", "repair_request", "repair_response"}

\* Network message structure
NetworkMessage == [
    type: MessageType,
    sender: ValidatorId,
    recipient: ValidatorId \cup {"broadcast"},
    payload: Nat,
    timestamp: TimeValue,
    signature: Signature
]

(***************************************************************************)
(* HELPER FUNCTIONS AND OPERATORS                                         *)
(***************************************************************************)

\* Sum function for stake calculations
RECURSIVE SumSet(_)
SumSet(S) ==
    IF S = {} THEN 0
    ELSE LET x == CHOOSE x \in S : TRUE
         IN x + SumSet(S \ {x})

Sum(f) ==
    LET D == DOMAIN f
    IN IF D = {} THEN 0
       ELSE SumSet({f[x] : x \in D})

\* Total stake calculation
TotalStake(validators, stakeMap) ==
    Sum([v \in validators |-> stakeMap[v]])

\* Stake thresholds for dual-path consensus
FastPathThreshold == 
    LET totalStake == TotalStake(Validators, Stake)
    IN (4 * totalStake) \div 5  \* 80% of total stake

SlowPathThreshold ==
    LET totalStake == TotalStake(Validators, Stake)
    IN (3 * totalStake) \div 5  \* 60% of total stake

\* VRF-based deterministic leader selection
VRFEvaluate(seed, validator) ==
    LET hash1 == ((seed * 997 + validator * 991) % 1000000)
        hash2 == ((hash1 * 983 + seed * 977) % 1000000)
    IN ((hash1 + hash2) % 1000000)

\* Compute slot leader using stake-weighted VRF
ComputeLeader(slot, validators, stakeMap) ==
    IF validators = {} THEN 0
    ELSE IF Cardinality(validators) = 1 THEN CHOOSE v \in validators : TRUE
    ELSE
        LET totalStake == TotalStake(validators, stakeMap)
            vrfSeed == VRFEvaluate(slot, 0)
            targetValue == IF totalStake = 0 THEN 0 ELSE (vrfSeed % totalStake)
            ValidatorOrder == CHOOSE seq \in [1..Cardinality(validators) -> validators] :
                                \A i, j \in 1..Cardinality(validators) :
                                    i < j => seq[i] # seq[j]
            cumulativeStake == [i \in 1..Cardinality(validators) |->
                IF i = 1 THEN stakeMap[ValidatorOrder[1]]
                ELSE SumSet({stakeMap[ValidatorOrder[j]] : j \in 1..i})
            ]
            selectedIndex == IF totalStake = 0 THEN 1
                           ELSE CHOOSE i \in 1..Cardinality(validators) :
                               /\ cumulativeStake[i] > targetValue
                               /\ \A j \in 1..Cardinality(validators) :
                                   (j < i => cumulativeStake[j] <= targetValue) \/ j >= i
        IN ValidatorOrder[selectedIndex]

\* Window-based leader rotation (4-slot windows)
WindowSize == 4
ComputeWindowLeader(slot) ==
    LET windowIndex == slot \div WindowSize
    IN ComputeLeader(windowIndex, Validators, Stake)

\* Cryptographic operations
SignMessage(validator, message) ==
    [signer |-> validator,
     message |-> message,
     valid |-> TRUE,
     aggregatable |-> TRUE]

AggregateSignatures(sigs) ==
    [signers |-> {s.signer : s \in sigs},
     message |-> IF sigs = {} THEN 0 ELSE (CHOOSE s \in sigs : TRUE).message,
     signatures |-> sigs,
     valid |-> /\ Cardinality(sigs) > 0
               /\ \A sig \in sigs : sig.valid
               /\ \A s1, s2 \in sigs : s1.message = s2.message]

\* Timeout calculation with exponential backoff
ViewTimeout(view, baseTimeout) ==
    IF view = 1 THEN baseTimeout
    ELSE baseTimeout * (2 ^ ((view - 1) % 10))

\* Current slot from time
CurrentSlot(time) == time \div SlotDuration + 1

\* Check if after Global Stabilization Time
AfterGST(time) == time >= GST

(***************************************************************************)
(* ERASURE CODING OPERATIONS                                               *)
(***************************************************************************)

\* Reed-Solomon encode block into N shreds
ErasureEncode(block) ==
    LET dataShreds == {[blockId |-> block.hash,
                       slot |-> block.slot,
                       index |-> i,
                       data |-> <<"data", block, i>>,
                       isParity |-> FALSE,
                       merkleProof |-> <<"merkle", block.hash, i>>,
                       signature |-> [signer |-> block.proposer, 
                                     message |-> block.hash, 
                                     valid |-> TRUE]] : i \in 1..K}
        parityShreds == {[blockId |-> block.hash,
                         slot |-> block.slot,
                         index |-> i,
                         data |-> <<"parity", block, i>>,
                         isParity |-> TRUE,
                         merkleProof |-> <<"merkle", block.hash, i>>,
                         signature |-> [signer |-> block.proposer, 
                                       message |-> block.hash, 
                                       valid |-> TRUE]] : i \in (K+1)..N}
    IN dataShreds \cup parityShreds

\* Reed-Solomon decode shreds back to block
ErasureDecode(shreds) ==
    IF Cardinality(shreds) >= K
    THEN LET blockId == IF shreds = {} THEN 0 ELSE (CHOOSE s \in shreds : TRUE).blockId
             slot == IF shreds = {} THEN 0 ELSE (CHOOSE s \in shreds : TRUE).slot
         IN [hash |-> blockId,
             slot |-> slot,
             view |-> 0,
             proposer |-> CHOOSE v \in Validators : TRUE,
             parent |-> 0,
             data |-> <<"reconstructed">>,
             timestamp |-> 0,
             transactions |-> {},
             signature |-> [signer |-> 0, message |-> 0, valid |-> TRUE]]
    ELSE [hash |-> 0, slot |-> 0, view |-> 0, proposer |-> 0, parent |-> 0,
          data |-> <<"failed">>, timestamp |-> 0, transactions |-> {},
          signature |-> [signer |-> 0, message |-> 0, valid |-> FALSE]]

\* Stake-weighted relay selection
SelectRelays(validator, totalValidators) ==
    LET relayCount == Min(totalValidators \div 3, 10)  \* 1/3 of validators, max 10
        candidates == Validators \ {validator}
    IN CHOOSE relays \in SUBSET candidates :
        /\ Cardinality(relays) <= relayCount
        /\ \A r \in relays : Stake[r] > 0

(***************************************************************************)
(* STATE VARIABLES                                                         *)
(***************************************************************************)

VARIABLES
    \* Global state
    clock,               \* Global time counter
    currentSlot,         \* Current protocol slot
    
    \* Votor consensus state
    votorView,           \* Current view per validator [validator -> view]
    votorVotes,          \* Votes cast by validators [validator -> set of votes]
    votorTimeouts,       \* Timeout settings [validator -> slot -> timeout]
    votorGeneratedCerts, \* Generated certificates [view -> set of certificates]
    votorFinalizedChain, \* Finalized chain per validator [validator -> sequence of blocks]
    votorState,          \* Internal state tracking [validator -> slot -> set of states]
    votorObservedCerts,  \* Observed certificates [validator -> set of certificates]
    
    \* Rotor propagation state
    rotorBlocks,         \* Proposed blocks [slot -> block]
    rotorShreds,         \* Shredded blocks [slot -> index -> shred]
    rotorReceivedShreds, \* Received shreds [validator -> slot -> set of shreds]
    rotorReconstructedBlocks, \* Reconstructed blocks [validator -> slot -> block]
    blockShreds,         \* Shred assignments [blockId -> validator -> set of shreds]
    relayAssignments,    \* Relay assignments [validator -> set of indices]
    reconstructionState, \* Reconstruction progress [validator -> sequence of states]
    deliveredBlocks,     \* Delivered blocks [validator -> set of blockIds]
    repairRequests,      \* Active repair requests [set of requests]
    bandwidthUsage,      \* Bandwidth consumption [validator -> amount]
    
    \* Network state
    networkMessages,     \* In-flight messages [set of messages]
    networkPartitions,   \* Active network partitions [set of validator sets]
    networkDroppedMessages, \* Count of dropped messages
    
    \* Additional state
    finalizedBlocks,     \* Finalized blocks per slot [slot -> set of blocks]
    failureStates,       \* Validator failure states [validator -> status]
    latencyMetrics,      \* Finalization latencies [slot -> time]
    bandwidthMetrics     \* Bandwidth consumption metrics [validator -> amount]

\* All state variables
vars == <<clock, currentSlot, votorView, votorVotes, votorTimeouts, 
          votorGeneratedCerts, votorFinalizedChain, votorState, votorObservedCerts,
          rotorBlocks, rotorShreds, rotorReceivedShreds, rotorReconstructedBlocks,
          blockShreds, relayAssignments, reconstructionState, deliveredBlocks,
          repairRequests, bandwidthUsage, networkMessages, networkPartitions,
          networkDroppedMessages, finalizedBlocks, failureStates, 
          latencyMetrics, bandwidthMetrics>>

(***************************************************************************)
(* INITIAL STATE                                                           *)
(***************************************************************************)

Init ==
    \* Global state initialization
    /\ clock = 0
    /\ currentSlot = 1
    
    \* Votor consensus initialization
    /\ votorView = [v \in Validators |-> 1]
    /\ votorVotes = [v \in Validators |-> {}]
    /\ votorTimeouts = [v \in Validators |-> [s \in 1..MaxSlot |-> {}]]
    /\ votorGeneratedCerts = [view \in 1..MaxView |-> {}]
    /\ votorFinalizedChain = [v \in Validators |-> <<>>]
    /\ votorState = [v \in Validators |-> [s \in 1..MaxSlot |-> {}]]
    /\ votorObservedCerts = [v \in Validators |-> {}]
    
    \* Rotor propagation initialization
    /\ rotorBlocks = [s \in {} |-> []]
    /\ rotorShreds = [s \in {} |-> [i \in {} |-> []]]
    /\ rotorReceivedShreds = [v \in Validators |-> [s \in {} |-> {}]]
    /\ rotorReconstructedBlocks = [v \in Validators |-> [s \in {} |-> []]]
    /\ blockShreds = [b \in {} |-> [v \in Validators |-> {}]]
    /\ relayAssignments = [v \in Validators |-> {}]
    /\ reconstructionState = [v \in Validators |-> <<>>]
    /\ deliveredBlocks = [v \in Validators |-> {}]
    /\ repairRequests = {}
    /\ bandwidthUsage = [v \in Validators |-> 0]
    
    \* Network initialization
    /\ networkMessages = {}
    /\ networkPartitions = {}
    /\ networkDroppedMessages = 0
    
    \* Additional state initialization
    /\ finalizedBlocks = [s \in 1..MaxSlot |-> {}]
    /\ failureStates = [v \in Validators |-> "active"]
    /\ latencyMetrics = [s \in 1..MaxSlot |-> 0]
    /\ bandwidthMetrics = [v \in Validators |-> 0]

(***************************************************************************)
(* VOTOR CONSENSUS ACTIONS                                                 *)
(***************************************************************************)

\* Cast notarization vote (first round of slow path or fast path)
CastNotarVote(validator, slot, block) ==
    /\ validator \in HonestValidators
    /\ slot = currentSlot
    /\ slot \in 1..MaxSlot
    /\ ~\E vote \in votorVotes[validator] :
        /\ vote.type = "notarization"
        /\ vote.slot = slot
    /\ LET vote == [voter |-> validator,
                    slot |-> slot,
                    view |-> votorView[validator],
                    block |-> block.hash,
                    type |-> "notarization",
                    signature |-> SignMessage(validator, block.hash),
                    timestamp |-> clock]
       IN votorVotes' = [votorVotes EXCEPT ![validator] = @ \cup {vote}]
    /\ votorState' = [votorState EXCEPT ![validator][slot] = @ \cup {"Voted"}]
    /\ UNCHANGED <<clock, currentSlot, votorView, votorTimeouts, votorGeneratedCerts,
                   votorFinalizedChain, votorObservedCerts, rotorBlocks, rotorShreds,
                   rotorReceivedShreds, rotorReconstructedBlocks, blockShreds,
                   relayAssignments, reconstructionState, deliveredBlocks,
                   repairRequests, bandwidthUsage, networkMessages, networkPartitions,
                   networkDroppedMessages, finalizedBlocks, failureStates,
                   latencyMetrics, bandwidthMetrics>>

\* Cast finalization vote (second round of slow path)
CastFinalizationVote(validator, slot, block) ==
    /\ validator \in HonestValidators
    /\ slot = currentSlot
    /\ slot \in 1..MaxSlot
    /\ "Voted" \in votorState[validator][slot]  \* Must have notarized first
    /\ ~\E vote \in votorVotes[validator] :
        /\ vote.type = "finalization"
        /\ vote.slot = slot
    /\ LET vote == [voter |-> validator,
                    slot |-> slot,
                    view |-> votorView[validator],
                    block |-> block.hash,
                    type |-> "finalization",
                    signature |-> SignMessage(validator, block.hash),
                    timestamp |-> clock]
       IN votorVotes' = [votorVotes EXCEPT ![validator] = @ \cup {vote}]
    /\ votorState' = [votorState EXCEPT ![validator][slot] = @ \cup {"Finalized"}]
    /\ UNCHANGED <<clock, currentSlot, votorView, votorTimeouts, votorGeneratedCerts,
                   votorFinalizedChain, votorObservedCerts, rotorBlocks, rotorShreds,
                   rotorReceivedShreds, rotorReconstructedBlocks, blockShreds,
                   relayAssignments, reconstructionState, deliveredBlocks,
                   repairRequests, bandwidthUsage, networkMessages, networkPartitions,
                   networkDroppedMessages, finalizedBlocks, failureStates,
                   latencyMetrics, bandwidthMetrics>>

\* Cast skip vote on timeout
CastSkipVote(validator, slot, reason) ==
    /\ validator \in HonestValidators
    /\ slot = currentSlot
    /\ slot \in 1..MaxSlot
    /\ \E timeout \in votorTimeouts[validator][slot] : clock >= timeout
    /\ ~\E vote \in votorVotes[validator] :
        /\ vote.type = "skip"
        /\ vote.slot = slot
    /\ LET vote == [voter |-> validator,
                    slot |-> slot,
                    view |-> votorView[validator],
                    block |-> 0,  \* No block for skip
                    type |-> "skip",
                    signature |-> SignMessage(validator, slot),
                    timestamp |-> clock]
       IN votorVotes' = [votorVotes EXCEPT ![validator] = @ \cup {vote}]
    /\ votorState' = [votorState EXCEPT ![validator][slot] = @ \cup {"Skipped"}]
    /\ UNCHANGED <<clock, currentSlot, votorView, votorTimeouts, votorGeneratedCerts,
                   votorFinalizedChain, votorObservedCerts, rotorBlocks, rotorShreds,
                   rotorReceivedShreds, rotorReconstructedBlocks, blockShreds,
                   relayAssignments, reconstructionState, deliveredBlocks,
                   repairRequests, bandwidthUsage, networkMessages, networkPartitions,
                   networkDroppedMessages, finalizedBlocks, failureStates,
                   latencyMetrics, bandwidthMetrics>>

\* Set timeout for validator and slot
SetTimeout(validator, slot, timeout) ==
    /\ validator \in Validators
    /\ slot \in 1..MaxSlot
    /\ timeout > clock
    /\ votorTimeouts' = [votorTimeouts EXCEPT ![validator][slot] = @ \cup {timeout}]
    /\ UNCHANGED <<clock, currentSlot, votorView, votorVotes, votorGeneratedCerts,
                   votorFinalizedChain, votorState, votorObservedCerts, rotorBlocks,
                   rotorShreds, rotorReceivedShreds, rotorReconstructedBlocks,
                   blockShreds, relayAssignments, reconstructionState, deliveredBlocks,
                   repairRequests, bandwidthUsage, networkMessages, networkPartitions,
                   networkDroppedMessages, finalizedBlocks, failureStates,
                   latencyMetrics, bandwidthMetrics>>

\* Generate certificates when sufficient votes collected
GenerateCertificates ==
    /\ \E slot \in 1..currentSlot, view \in 1..MaxView :
        LET allVotes == UNION {votorVotes[v] : v \in Validators}
            slotVotes == {vote \in allVotes : vote.slot = slot}
            notarVotes == {vote \in slotVotes : vote.type = "notarization"}
            finalizationVotes == {vote \in slotVotes : vote.type = "finalization"}
            skipVotes == {vote \in slotVotes : vote.type = "skip"}
            
            \* Fast path: ≥80% stake notarization votes
            notarStake == TotalStake({vote.voter : vote \in notarVotes}, Stake)
            fastCert == [slot |-> slot,
                        view |-> view,
                        block |-> IF notarVotes = {} THEN 0 ELSE (CHOOSE v \in notarVotes : TRUE).block,
                        type |-> "fast",
                        signatures |-> AggregateSignatures({vote.signature : vote \in notarVotes}),
                        validators |-> {vote.voter : vote \in notarVotes},
                        stake |-> notarStake]
            
            \* Slow path: ≥60% stake notarization + finalization votes
            finalizationStake == TotalStake({vote.voter : vote \in finalizationVotes}, Stake)
            slowCert == [slot |-> slot,
                        view |-> view,
                        block |-> IF notarVotes = {} THEN 0 ELSE (CHOOSE v \in notarVotes : TRUE).block,
                        type |-> "slow",
                        signatures |-> AggregateSignatures({vote.signature : vote \in notarVotes \cup finalizationVotes}),
                        validators |-> {vote.voter : vote \in notarVotes \cup finalizationVotes},
                        stake |-> finalizationStake]
            
            \* Skip path: ≥60% stake skip votes
            skipStake == TotalStake({vote.voter : vote \in skipVotes}, Stake)
            skipCert == [slot |-> slot,
                        view |-> view,
                        block |-> 0,
                        type |-> "skip",
                        signatures |-> AggregateSignatures({vote.signature : vote \in skipVotes}),
                        validators |-> {vote.voter : vote \in skipVotes},
                        stake |-> skipStake]
        IN
        \/ /\ notarStake >= FastPathThreshold
           /\ votorGeneratedCerts' = [votorGeneratedCerts EXCEPT ![view] = @ \cup {fastCert}]
        \/ /\ notarStake >= SlowPathThreshold
           /\ finalizationStake >= SlowPathThreshold
           /\ votorGeneratedCerts' = [votorGeneratedCerts EXCEPT ![view] = @ \cup {slowCert}]
        \/ /\ skipStake >= SlowPathThreshold
           /\ votorGeneratedCerts' = [votorGeneratedCerts EXCEPT ![view] = @ \cup {skipCert}]
    /\ UNCHANGED <<clock, currentSlot, votorView, votorVotes, votorTimeouts,
                   votorFinalizedChain, votorState, votorObservedCerts, rotorBlocks,
                   rotorShreds, rotorReceivedShreds, rotorReconstructedBlocks,
                   blockShreds, relayAssignments, reconstructionState, deliveredBlocks,
                   repairRequests, bandwidthUsage, networkMessages, networkPartitions,
                   networkDroppedMessages, finalizedBlocks, failureStates,
                   latencyMetrics, bandwidthMetrics>>

\* Finalize block with valid certificate
FinalizeBlock(validator, slot, block, certificate) ==
    /\ validator \in Validators
    /\ slot \in 1..MaxSlot
    /\ certificate.slot = slot
    /\ certificate.block = block.hash
    /\ certificate.type \in {"fast", "slow"}
    /\ ~\E b \in Range(votorFinalizedChain[validator]) : b.slot = slot
    /\ votorFinalizedChain' = [votorFinalizedChain EXCEPT ![validator] = Append(@, block)]
    /\ finalizedBlocks' = [finalizedBlocks EXCEPT ![slot] = @ \cup {block}]
    /\ latencyMetrics' = [latencyMetrics EXCEPT ![slot] = 
                         IF block.timestamp > 0 THEN clock - block.timestamp ELSE 0]
    /\ votorState' = [votorState EXCEPT ![validator][slot] = @ \cup {"Finalized"}]
    /\ UNCHANGED <<clock, currentSlot, votorView, votorVotes, votorTimeouts,
                   votorGeneratedCerts, votorObservedCerts, rotorBlocks, rotorShreds,
                   rotorReceivedShreds, rotorReconstructedBlocks, blockShreds,
                   relayAssignments, reconstructionState, deliveredBlocks,
                   repairRequests, bandwidthUsage, networkMessages, networkPartitions,
                   networkDroppedMessages, failureStates, bandwidthMetrics>>

\* Helper function for sequence range
Range(seq) == {seq[i] : i \in DOMAIN seq}

(***************************************************************************)
(* ROTOR PROPAGATION ACTIONS                                               *)
(***************************************************************************)

\* Leader proposes block for current slot
ProposeBlock(leader, block) ==
    /\ leader = ComputeWindowLeader(currentSlot)
    /\ currentSlot \notin DOMAIN rotorBlocks
    /\ block.slot = currentSlot
    /\ block.proposer = leader
    /\ block.timestamp = clock
    /\ rotorBlocks' = rotorBlocks @@ (currentSlot :> block)
    /\ UNCHANGED <<clock, currentSlot, votorView, votorVotes, votorTimeouts,
                   votorGeneratedCerts, votorFinalizedChain, votorState, votorObservedCerts,
                   rotorShreds, rotorReceivedShreds, rotorReconstructedBlocks,
                   blockShreds, relayAssignments, reconstructionState, deliveredBlocks,
                   repairRequests, bandwidthUsage, networkMessages, networkPartitions,
                   networkDroppedMessages, finalizedBlocks, failureStates,
                   latencyMetrics, bandwidthMetrics>>

\* Shred block into erasure-coded pieces
ShredBlock(block) ==
    /\ block.slot \in DOMAIN rotorBlocks
    /\ block.slot \notin DOMAIN rotorShreds
    /\ LET shreds == ErasureEncode(block)
           shredMap == [i \in 1..N |->
               IF \E s \in shreds : s.index = i
               THEN CHOOSE s \in shreds : s.index = i
               ELSE [blockId |-> 0, slot |-> 0, index |-> i, data |-> <<>>,
                     isParity |-> FALSE, merkleProof |-> <<>>, 
                     signature |-> [signer |-> 0, message |-> 0, valid |-> FALSE]]]
       IN rotorShreds' = rotorShreds @@ (block.slot :> shredMap)
    /\ UNCHANGED <<clock, currentSlot, votorView, votorVotes, votorTimeouts,
                   votorGeneratedCerts, votorFinalizedChain, votorState, votorObservedCerts,
                   rotorBlocks, rotorReceivedShreds, rotorReconstructedBlocks,
                   blockShreds, relayAssignments, reconstructionState, deliveredBlocks,
                   repairRequests, bandwidthUsage, networkMessages, networkPartitions,
                   networkDroppedMessages, finalizedBlocks, failureStates,
                   latencyMetrics, bandwidthMetrics>>

\* Distribute shreds to stake-weighted relays
DistributeShreds(leader, blockId) ==
    /\ blockId \in DOMAIN blockShreds \/ blockId \notin DOMAIN blockShreds
    /\ LET block == IF currentSlot \in DOMAIN rotorBlocks 
                   THEN rotorBlocks[currentSlot] 
                   ELSE [hash |-> blockId, slot |-> currentSlot, proposer |-> leader,
                         view |-> 0, parent |-> 0, data |-> <<"test">>, timestamp |-> clock,
                         transactions |-> {}, signature |-> [signer |-> leader, message |-> blockId, valid |-> TRUE]]
           shreds == IF block.slot \in DOMAIN rotorShreds
                    THEN {rotorShreds[block.slot][i] : i \in DOMAIN rotorShreds[block.slot]}
                    ELSE ErasureEncode(block)
           assignments == [v \in Validators |-> SelectRelays(v, Cardinality(Validators))]
       IN
       /\ blockShreds' = [blockShreds EXCEPT ![blockId] =
              [v \in Validators |->
                  {s \in shreds : s.index \in 1..N /\ v \in assignments[s.index % Cardinality(Validators) + 1]}]]
       /\ relayAssignments' = [v \in Validators |-> assignments[v]]
    /\ UNCHANGED <<clock, currentSlot, votorView, votorVotes, votorTimeouts,
                   votorGeneratedCerts, votorFinalizedChain, votorState, votorObservedCerts,
                   rotorBlocks, rotorShreds, rotorReceivedShreds, rotorReconstructedBlocks,
                   reconstructionState, deliveredBlocks, repairRequests, bandwidthUsage,
                   networkMessages, networkPartitions, networkDroppedMessages,
                   finalizedBlocks, failureStates, latencyMetrics, bandwidthMetrics>>

\* Validator attempts block reconstruction
AttemptReconstruction(validator, blockId) ==
    /\ validator \in Validators
    /\ blockId \in DOMAIN blockShreds
    /\ blockId \notin deliveredBlocks[validator]
    /\ Cardinality(blockShreds[blockId][validator]) >= K
    /\ LET pieces == blockShreds[blockId][validator]
           block == ErasureDecode(pieces)
       IN
       /\ block.hash # 0  \* Successful reconstruction
       /\ reconstructionState' = [reconstructionState EXCEPT ![validator] =
              Append(@, [blockId |-> blockId, complete |-> TRUE])]
       /\ deliveredBlocks' = [deliveredBlocks EXCEPT ![validator] = @ \cup {blockId}]
       /\ IF block.slot \in DOMAIN rotorReconstructedBlocks[validator]
          THEN rotorReconstructedBlocks' = [rotorReconstructedBlocks EXCEPT 
                   ![validator][block.slot] = block]
          ELSE rotorReconstructedBlocks' = [rotorReconstructedBlocks EXCEPT 
                   ![validator] = @ @@ (block.slot :> block)]
    /\ UNCHANGED <<clock, currentSlot, votorView, votorVotes, votorTimeouts,
                   votorGeneratedCerts, votorFinalizedChain, votorState, votorObservedCerts,
                   rotorBlocks, rotorShreds, rotorReceivedShreds, blockShreds,
                   relayAssignments, repairRequests, bandwidthUsage, networkMessages,
                   networkPartitions, networkDroppedMessages, finalizedBlocks,
                   failureStates, latencyMetrics, bandwidthMetrics>>

\* Request repair for missing shreds
RequestRepair(validator, blockId, missingIndices) ==
    /\ validator \in Validators
    /\ blockId \in DOMAIN blockShreds
    /\ Cardinality(blockShreds[blockId][validator]) < K
    /\ missingIndices \subseteq (1..N)
    /\ Cardinality(missingIndices) > 0
    /\ LET request == [requester |-> validator,
                      blockId |-> blockId,
                      slot |-> currentSlot,
                      missingIndices |-> missingIndices,
                      timestamp |-> clock]
       IN repairRequests' = repairRequests \cup {request}
    /\ UNCHANGED <<clock, currentSlot, votorView, votorVotes, votorTimeouts,
                   votorGeneratedCerts, votorFinalizedChain, votorState, votorObservedCerts,
                   rotorBlocks, rotorShreds, rotorReceivedShreds, rotorReconstructedBlocks,
                   blockShreds, relayAssignments, reconstructionState, deliveredBlocks,
                   bandwidthUsage, networkMessages, networkPartitions,
                   networkDroppedMessages, finalizedBlocks, failureStates,
                   latencyMetrics, bandwidthMetrics>>

\* Respond to repair request
RespondToRepair(validator, request) ==
    /\ validator \in Validators
    /\ request \in repairRequests
    /\ request.blockId \in DOMAIN blockShreds
    /\ LET myPieces == blockShreds[request.blockId][validator]
           requestedPieces == {p \in myPieces : p.index \in request.missingIndices}
       IN
       /\ Cardinality(requestedPieces) > 0
       /\ blockShreds' = [blockShreds EXCEPT
              ![request.blockId][request.requester] = @ \cup requestedPieces]
       /\ repairRequests' = repairRequests \ {request}
    /\ UNCHANGED <<clock, currentSlot, votorView, votorVotes, votorTimeouts,
                   votorGeneratedCerts, votorFinalizedChain, votorState, votorObservedCerts,
                   rotorBlocks, rotorShreds, rotorReceivedShreds, rotorReconstructedBlocks,
                   relayAssignments, reconstructionState, deliveredBlocks, bandwidthUsage,
                   networkMessages, networkPartitions, networkDroppedMessages,
                   finalizedBlocks, failureStates, latencyMetrics, bandwidthMetrics>>

(***************************************************************************)
(* NETWORK AND TIMING ACTIONS                                              *)
(***************************************************************************)

\* Advance global clock
AdvanceClock ==
    /\ clock' = clock + 1
    /\ UNCHANGED <<currentSlot, votorView, votorVotes, votorTimeouts,
                   votorGeneratedCerts, votorFinalizedChain, votorState, votorObservedCerts,
                   rotorBlocks, rotorShreds, rotorReceivedShreds, rotorReconstructedBlocks,
                   blockShreds, relayAssignments, reconstructionState, deliveredBlocks,
                   repairRequests, bandwidthUsage, networkMessages, networkPartitions,
                   networkDroppedMessages, finalizedBlocks, failureStates,
                   latencyMetrics, bandwidthMetrics>>

\* Advance to next slot when current slot finalized or timed out
AdvanceSlot ==
    /\ \/ \E block \in finalizedBlocks[currentSlot] : TRUE  \* Slot finalized
       \/ clock >= currentSlot * SlotDuration + SlotDuration  \* Slot timed out
    /\ currentSlot < MaxSlot
    /\ currentSlot' = currentSlot + 1
    /\ UNCHANGED <<clock, votorView, votorVotes, votorTimeouts, votorGeneratedCerts,
                   votorFinalizedChain, votorState, votorObservedCerts, rotorBlocks,
                   rotorShreds, rotorReceivedShreds, rotorReconstructedBlocks,
                   blockShreds, relayAssignments, reconstructionState, deliveredBlocks,
                   repairRequests, bandwidthUsage, networkMessages, networkPartitions,
                   networkDroppedMessages, finalizedBlocks, failureStates,
                   latencyMetrics, bandwidthMetrics>>

\* Advance view on timeout
AdvanceView(validator) ==
    /\ validator \in Validators
    /\ votorView[validator] < MaxView
    /\ \E timeout \in votorTimeouts[validator][currentSlot] : clock >= timeout
    /\ votorView' = [votorView EXCEPT ![validator] = @ + 1]
    /\ LET newTimeout == clock + ViewTimeout(votorView'[validator], SlotDuration)
       IN votorTimeouts' = [votorTimeouts EXCEPT ![validator][currentSlot] = @ \cup {newTimeout}]
    /\ UNCHANGED <<clock, currentSlot, votorVotes, votorGeneratedCerts,
                   votorFinalizedChain, votorState, votorObservedCerts, rotorBlocks,
                   rotorShreds, rotorReceivedShreds, rotorReconstructedBlocks,
                   blockShreds, relayAssignments, reconstructionState, deliveredBlocks,
                   repairRequests, bandwidthUsage, networkMessages, networkPartitions,
                   networkDroppedMessages, finalizedBlocks, failureStates,
                   latencyMetrics, bandwidthMetrics>>

\* Send network message
SendMessage(sender, recipient, msgType, payload) ==
    /\ sender \in Validators
    /\ recipient \in Validators \cup {"broadcast"}
    /\ LET message == [type |-> msgType,
                      sender |-> sender,
                      recipient |-> recipient,
                      payload |-> payload,
                      timestamp |-> clock,
                      signature |-> [signer |-> sender, message |-> payload, valid |-> TRUE]]
       IN networkMessages' = networkMessages \cup {message}
    /\ UNCHANGED <<clock, currentSlot, votorView, votorVotes, votorTimeouts,
                   votorGeneratedCerts, votorFinalizedChain, votorState, votorObservedCerts,
                   rotorBlocks, rotorShreds, rotorReceivedShreds, rotorReconstructedBlocks,
                   blockShreds, relayAssignments, reconstructionState, deliveredBlocks,
                   repairRequests, bandwidthUsage, networkPartitions,
                   networkDroppedMessages, finalizedBlocks, failureStates,
                   latencyMetrics, bandwidthMetrics>>

\* Create network partition
CreatePartition(partition) ==
    /\ partition \subseteq Validators
    /\ Cardinality(partition) > 0
    /\ Cardinality(partition) < Cardinality(Validators)
    /\ networkPartitions' = networkPartitions \cup {partition}
    /\ UNCHANGED <<clock, currentSlot, votorView, votorVotes, votorTimeouts,
                   votorGeneratedCerts, votorFinalizedChain, votorState, votorObservedCerts,
                   rotorBlocks, rotorShreds, rotorReceivedShreds, rotorReconstructedBlocks,
                   blockShreds, relayAssignments, reconstructionState, deliveredBlocks,
                   repairRequests, bandwidthUsage, networkMessages,
                   networkDroppedMessages, finalizedBlocks, failureStates,
                   latencyMetrics, bandwidthMetrics>>

\* Heal network partition
HealPartition(partition) ==
    /\ partition \in networkPartitions
    /\ networkPartitions' = networkPartitions \ {partition}
    /\ UNCHANGED <<clock, currentSlot, votorView, votorVotes, votorTimeouts,
                   votorGeneratedCerts, votorFinalizedChain, votorState, votorObservedCerts,
                   rotorBlocks, rotorShreds, rotorReceivedShreds, rotorReconstructedBlocks,
                   blockShreds, relayAssignments, reconstructionState, deliveredBlocks,
                   repairRequests, bandwidthUsage, networkMessages,
                   networkDroppedMessages, finalizedBlocks, failureStates,
                   latencyMetrics, bandwidthMetrics>>

(***************************************************************************)
(* BYZANTINE ACTIONS                                                       *)
(***************************************************************************)

\* Byzantine validator double votes
ByzantineDoubleVote(validator) ==
    /\ validator \in ByzantineValidators
    /\ \E block1, block2 \in Block :
        /\ block1 # block2
        /\ block1.slot = currentSlot
        /\ block2.slot = currentSlot
        /\ LET vote1 == [voter |-> validator, slot |-> currentSlot,
                        view |-> votorView[validator], block |-> block1.hash,
                        type |-> "notarization", signature |-> SignMessage(validator, block1.hash),
                        timestamp |-> clock]
               vote2 == [voter |-> validator, slot |-> currentSlot,
                        view |-> votorView[validator], block |-> block2.hash,
                        type |-> "notarization", signature |-> SignMessage(validator, block2.hash),
                        timestamp |-> clock]
           IN votorVotes' = [votorVotes EXCEPT ![validator] = @ \cup {vote1, vote2}]
    /\ UNCHANGED <<clock, currentSlot, votorView, votorTimeouts, votorGeneratedCerts,
                   votorFinalizedChain, votorState, votorObservedCerts, rotorBlocks,
                   rotorShreds, rotorReceivedShreds, rotorReconstructedBlocks,
                   blockShreds, relayAssignments, reconstructionState, deliveredBlocks,
                   repairRequests, bandwidthUsage, networkMessages, networkPartitions,
                   networkDroppedMessages, finalizedBlocks, failureStates,
                   latencyMetrics, bandwidthMetrics>>

\* Byzantine validator withholds shreds
ByzantineWithholdShreds(validator) ==
    /\ validator \in ByzantineValidators
    /\ \E blockId \in DOMAIN blockShreds :
        /\ blockShreds[blockId][validator] # {}
        /\ blockShreds' = [blockShreds EXCEPT ![blockId][validator] = {}]
    /\ UNCHANGED <<clock, currentSlot, votorView, votorVotes, votorTimeouts,
                   votorGeneratedCerts, votorFinalizedChain, votorState, votorObservedCerts,
                   rotorBlocks, rotorShreds, rotorReceivedShreds, rotorReconstructedBlocks,
                   relayAssignments, reconstructionState, deliveredBlocks,
                   repairRequests, bandwidthUsage, networkMessages, networkPartitions,
                   networkDroppedMessages, finalizedBlocks, failureStates,
                   latencyMetrics, bandwidthMetrics>>

(***************************************************************************)
(* NEXT STATE RELATION                                                     *)
(***************************************************************************)

Next ==
    \* Timing actions
    \/ AdvanceClock
    \/ AdvanceSlot
    \/ \E v \in Validators : AdvanceView(v)
    
    \* Votor consensus actions
    \/ \E v \in HonestValidators, b \in Block : 
        /\ b.slot = currentSlot
        /\ CastNotarVote(v, currentSlot, b)
    \/ \E v \in HonestValidators, b \in Block :
        /\ b.slot = currentSlot
        /\ CastFinalizationVote(v, currentSlot, b)
    \/ \E v \in HonestValidators, reason \in STRING :
        CastSkipVote(v, currentSlot, reason)
    \/ \E v \in Validators, s \in 1..MaxSlot, t \in TimeValue :
        SetTimeout(v, s, t)
    \/ GenerateCertificates
    \/ \E v \in Validators, s \in 1..MaxSlot, b \in Block, c \in Certificate :
        FinalizeBlock(v, s, b, c)
    
    \* Rotor propagation actions
    \/ \E leader \in Validators, b \in Block :
        /\ leader = ComputeWindowLeader(currentSlot)
        /\ ProposeBlock(leader, b)
    \/ \E b \in Block : ShredBlock(b)
    \/ \E leader \in Validators, blockId \in Nat :
        DistributeShreds(leader, blockId)
    \/ \E v \in Validators, blockId \in Nat :
        AttemptReconstruction(v, blockId)
    \/ \E v \in Validators, blockId \in Nat, missing \in SUBSET (1..N) :
        RequestRepair(v, blockId, missing)
    \/ \E v \in Validators, req \in repairRequests :
        RespondToRepair(v, req)
    
    \* Network actions
    \/ \E sender \in Validators, recipient \in Validators \cup {"broadcast"}, 
          msgType \in MessageType, payload \in Nat :
        SendMessage(sender, recipient, msgType, payload)
    \/ \E partition \in SUBSET Validators :
        CreatePartition(partition)
    \/ \E partition \in networkPartitions :
        HealPartition(partition)
    
    \* Byzantine actions
    \/ \E v \in ByzantineValidators : ByzantineDoubleVote(v)
    \/ \E v \in ByzantineValidators : ByzantineWithholdShreds(v)

(***************************************************************************)
(* SPECIFICATION                                                           *)
(***************************************************************************)

Spec == Init /\ [][Next]_vars /\ WF_vars(AdvanceClock) /\ WF_vars(AdvanceSlot)

(***************************************************************************)
(* TYPE INVARIANTS                                                         *)
(***************************************************************************)

TypeOK ==
    /\ clock \in Nat
    /\ currentSlot \in 1..MaxSlot
    /\ votorView \in [Validators -> 1..MaxView]
    /\ votorVotes \in [Validators -> SUBSET Vote]
    /\ votorTimeouts \in [Validators -> [1..MaxSlot -> SUBSET TimeValue]]
    /\ votorGeneratedCerts \in [1..MaxView -> SUBSET Certificate]
    /\ votorFinalizedChain \in [Validators -> Seq(Block)]
    /\ votorState \in [Validators -> [1..MaxSlot -> SUBSET STRING]]
    /\ votorObservedCerts \in [Validators -> SUBSET Certificate]
    /\ finalizedBlocks \in [1..MaxSlot -> SUBSET Block]
    /\ failureStates \in [Validators -> STRING]
    /\ latencyMetrics \in [1..MaxSlot -> Nat]
    /\ bandwidthMetrics \in [Validators -> Nat]

(***************************************************************************)
(* SAFETY PROPERTIES                                                       *)
(***************************************************************************)

\* No conflicting blocks finalized in same slot
SafetyInvariant ==
    \A slot \in 1..MaxSlot :
        Cardinality(finalizedBlocks[slot]) <= 1

\* Chain consistency across honest validators
ChainConsistency ==
    \A v1, v2 \in HonestValidators :
        \A i \in DOMAIN votorFinalizedChain[v1] :
            \A j \in DOMAIN votorFinalizedChain[v2] :
                /\ votorFinalizedChain[v1][i].slot = votorFinalizedChain[v2][j].slot
                => votorFinalizedChain[v1][i] = votorFinalizedChain[v2][j]

\* Certificate validity
ValidCertificates ==
    \A view \in 1..MaxView :
        \A cert \in votorGeneratedCerts[view] :
            /\ cert.type = "fast" => cert.stake >= FastPathThreshold
            /\ cert.type = "slow" => cert.stake >= SlowPathThreshold
            /\ cert.type = "skip" => cert.stake >= SlowPathThreshold

\* Honest validators vote at most once per slot per type
OneVotePerSlot ==
    \A v \in HonestValidators :
        \A slot \in 1..MaxSlot :
            \A voteType \in VoteType :
                Cardinality({vote \in votorVotes[v] : 
                    vote.slot = slot /\ vote.type = voteType}) <= 1

(***************************************************************************)
(* LIVENESS PROPERTIES                                                     *)
(***************************************************************************)

\* Progress guarantee under good conditions
Progress ==
    /\ AfterGST(clock)
    /\ TotalStake(HonestValidators \ OfflineValidators, Stake) > SlowPathThreshold
    => <>(\E slot \in 1..currentSlot : finalizedBlocks[slot] # {})

\* Fast path completion with high participation
FastPath ==
    LET responsiveStake == TotalStake(HonestValidators \ OfflineValidators, Stake)
    IN
    /\ responsiveStake >= FastPathThreshold
    /\ AfterGST(clock)
    => <>(\E view \in 1..MaxView, cert \in votorGeneratedCerts[view] : 
          cert.type = "fast" /\ cert.slot = currentSlot)

\* Bounded finalization time
BoundedFinalization ==
    LET responsiveStake == TotalStake(HonestValidators \ OfflineValidators, Stake)
        bound == IF responsiveStake >= FastPathThreshold 
                THEN Delta 
                ELSE 2 * Delta
    IN
    /\ AfterGST(clock)
    => [](clock <= GST + bound => 
          \E block \in finalizedBlocks[currentSlot] : TRUE)

(***************************************************************************)
(* RESILIENCE PROPERTIES                                                   *)
(***************************************************************************)

\* Byzantine resilience (safety under ≤20% Byzantine stake)
ByzantineResilience ==
    LET byzantineStake == TotalStake(ByzantineValidators, Stake)
        totalStake == TotalStake(Validators, Stake)
    IN byzantineStake * 5 <= totalStake => SafetyInvariant

\* Offline resilience (liveness under ≤20% offline stake)
OfflineResilience ==
    LET offlineStake == TotalStake(OfflineValidators, Stake)
        totalStake == TotalStake(Validators, Stake)
    IN
    /\ offlineStake * 5 <= totalStake
    /\ AfterGST(clock)
    => <>Progress

\* Combined 20+20 resilience model
Combined2020Resilience ==
    LET byzantineStake == TotalStake(ByzantineValidators, Stake)
        offlineStake == TotalStake(OfflineValidators, Stake)
        totalStake == TotalStake(Validators, Stake)
    IN
    /\ byzantineStake * 5 <= totalStake
    /\ offlineStake * 5 <= totalStake
    => /\ []SafetyInvariant
       /\ (AfterGST(clock) => <>Progress)

(***************************************************************************)
(* INTEGRATION PROPERTIES                                                  *)
(***************************************************************************)

\* Rotor delivers blocks before Votor timeout
RotorVotorIntegration ==
    \A slot \in 1..currentSlot :
        \A v \in HonestValidators :
            (\E vote \in votorVotes[v] : vote.slot = slot) =>
                \/ <>(\E s \in DOMAIN rotorReconstructedBlocks[v] :
                      \E b \in {rotorReconstructedBlocks[v][s]} : b.slot = slot)
                \/ <>(\E timeout \in votorTimeouts[v][slot] : clock >= timeout)
                \/ <>(\E cert \in UNION {votorGeneratedCerts[view] : view \in 1..MaxView} : 
                      cert.slot = slot)

\* Block delivery guarantee
BlockDeliveryGuarantee ==
    \A blockId \in DOMAIN blockShreds :
        \A v \in HonestValidators :
            <>(blockId \in deliveredBlocks[v])

(***************************************************************************)
(* MODEL CHECKING CONSTRAINTS                                              *)
(***************************************************************************)

\* State space reduction for model checking
StateConstraint ==
    /\ clock <= 50
    /\ currentSlot <= 5
    /\ Cardinality(networkMessages) <= 100
    /\ \A v \in Validators : votorView[v] <= 3
    /\ \A v \in Validators : Cardinality(votorVotes[v]) <= 10

\* Action constraint
ActionConstraint ==
    /\ currentSlot' <= MaxSlot
    /\ \A v \in Validators : votorView'[v] <= MaxView

\* Fairness conditions
Fairness ==
    /\ WF_vars(AdvanceClock)
    /\ WF_vars(AdvanceSlot)
    /\ \A v \in HonestValidators : WF_vars(AdvanceView(v))

============================================================================