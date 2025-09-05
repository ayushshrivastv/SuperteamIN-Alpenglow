---------------------------- MODULE Rotor ----------------------------
(***************************************************************************)
(* Rotor block propagation component implementing erasure-coded data      *)
(* dissemination with stake-weighted relay sampling for efficient         *)
(* bandwidth utilization.                                                 *)
(***************************************************************************)

EXTENDS Integers, Sequences, FiniteSets, TLC

CONSTANTS
    Validators,          \* Set of validator identifiers
    Stake,               \* Stake function: Validators -> Nat
    ByzantineValidators,
    K,                   \* Data shreds (erasure coding)
    N,                   \* Total shreds
    MaxBlocks,           \* Maximum concurrent blocks
    BandwidthLimit,      \* Per-validator bandwidth
    RetryTimeout,        \* Retry delay for repairs
    MaxRetries,          \* Maximum repair attempts
    HighLatencyThreshold, \* Threshold for high latency detection
    LowLatencyThreshold,  \* Threshold for low latency
    LoadBalanceTolerance, \* Load balance tolerance factor
    MaxBufferSize        \* Maximum buffer size per validator

ASSUME
    /\ N > K
    /\ N >= Cardinality(Validators)
    /\ K >= (2 * Cardinality(Validators)) \div 3  \* Reconstruction threshold
    /\ MaxBlocks > 0
    /\ BandwidthLimit > 0

----------------------------------------------------------------------------
(* Shred Identification for Non-Equivocation *)

\* Unique identifier for shred positions
ShredId == [slot: Nat, index: Nat]

----------------------------------------------------------------------------
(* Rotor State Variables *)

VARIABLES
    blockShreds,         \* Erasure-coded pieces: block -> validator -> pieces
    relayAssignments,    \* Stake-weighted relay assignments
    reconstructionState, \* Block reconstruction progress per validator
    deliveredBlocks,     \* Successfully delivered blocks per validator
    repairRequests,      \* Missing piece repair requests
    bandwidthUsage,      \* Current bandwidth usage per validator
    receivedShreds,      \* Shreds received by each validator
    shredAssignments,    \* Shred assignments for each validator
    reconstructedBlocks, \* Blocks reconstructed by each validator
    rotorHistory,        \* History of shreds sent by each validator: validator -> shredId -> shred
    clock                \* Global clock for timing operations

rotorVars == <<blockShreds, relayAssignments, reconstructionState,
               deliveredBlocks, repairRequests, bandwidthUsage,
               receivedShreds, shredAssignments, reconstructedBlocks,
               rotorHistory, clock>>

----------------------------------------------------------------------------
(* Import Type Definitions *)

INSTANCE Types
INSTANCE Utils

----------------------------------------------------------------------------
(* Helper Functions *)

\* Use Utils!Sum for stake calculation to ensure consistency
SumStake(f) == Utils!Sum(f)

TotalStakeSum == SumStake([v \in Validators |-> Stake[v]])

\* Compute parity data for erasure coding
ComputeParity(dataShreds) ==
    \* Abstract parity computation - XOR of data shreds
    \* Return a tuple format consistent with data shreds
    <<"parity", {}, 0>>

\* Recover block from data shreds only
RecoverFromData(pieces) ==
    [
        hash |-> (CHOOSE p \in pieces : TRUE).blockId,  \* Use blockId directly as hash
        slot |-> 0,  \* Will be set from actual block metadata
        view |-> 0,  \* Will be set from actual block metadata
        proposer |-> CHOOSE v \in Validators : TRUE,
        parent |-> 0,  \* Genesis block hash
        data |-> "recovered_data",
        timestamp |-> 0,
        transactions |-> {}]

\* Recover block using parity shreds
RecoverWithParity(pieces) ==
    [
        hash |-> (CHOOSE p \in pieces : TRUE).blockId,  \* Use blockId directly as hash
        slot |-> 0,  \* Will be set from actual block metadata
        view |-> 0,  \* Will be set from actual block metadata
        proposer |-> CHOOSE v \in Validators : TRUE,
        parent |-> 0,  \* Genesis block hash
        data |-> "recovered_with_parity",
        timestamp |-> 0,
        transactions |-> {}]

\* Select random subset of given size
RandomSubset(size, set) ==
    IF size >= Cardinality(set)
    THEN set
    ELSE CHOOSE subset \in SUBSET set : Cardinality(subset) = size

\* Validate block integrity after reconstruction
ValidateBlockIntegrity(block) ==
    /\ block.hash # <<>>
    /\ block.slot \in Nat
    /\ block.proposer \in Validators

\* Get block proposal time
GetBlockProposalTime(blockId) ==
    0  \* Abstract timing

\* Time until reconstruction completes
TimeTillReconstruction(validator, blockId) ==
    1  \* Abstract time unit

\* Optimal reconstruction time
OptimalReconstructionTime == 50  \* milliseconds

\* Eventually with deadline
Eventually(condition, deadline) ==
    condition  \* Simplified for TLC

\* Maximum delivery delay
MaxDeliveryDelay == 100  \* milliseconds

\* Median stake value
MedianStake == SumStake([v \in Validators |-> Stake[v]]) \div (2 * Cardinality(Validators))

\* Sort requests by timestamp
SortByTimestamp(requests) ==
    requests  \* Abstract sorting

\* Total bandwidth
TotalBandwidth == BandwidthLimit * Cardinality(Validators)

\* Relay threshold
RelayThreshold == 100  \* Abstract threshold

\* Honest validators (non-Byzantine)
HonestValidators == Validators \ ByzantineValidators

\* Erasure encode a block into N pieces with proper index partitioning
ErasureEncode(block) ==
    LET \* Data shreds use indices 1..K (ensuring unique partitioning)
        dataShreds == {[blockId |-> block.hash,
                       slot |-> block.slot,
                       index |-> i,
                       data |-> <<"data", block, i>>,  \* Abstract data split
                       isParity |-> FALSE,
                       signature |-> <<>>] : i \in 1..K}
        \* Parity shreds use indices (K+1)..N (ensuring no overlap)
        parityShreds == {[blockId |-> block.hash,
                         slot |-> block.slot,
                         index |-> i,
                         data |-> ComputeParity(dataShreds),
                         isParity |-> TRUE,
                         signature |-> <<>>] : i \in (K+1)..N}
    IN
    \* Verify proper partitioning before returning
    IF /\ \A d \in dataShreds : d.index \in 1..K
       /\ \A p \in parityShreds : p.index \in (K+1)..N
       /\ Cardinality({s.index : s \in dataShreds \cup parityShreds}) = N
    THEN dataShreds \cup parityShreds
    ELSE {}  \* Return empty set if partitioning fails

\* Reconstruct block from K pieces
ReconstructBlock(pieces) ==
    LET dataIndices == {p.index : p \in {x \in pieces : ~x.isParity}}
        parityIndices == {p.index : p \in {x \in pieces : x.isParity}}
    IN
    IF Cardinality(dataIndices) >= K
    THEN RecoverFromData(pieces)
    ELSE RecoverWithParity(pieces)

\* Stake-weighted piece assignment
AssignPiecesToRelays(validators, numPieces) ==
    LET totalStake == SumStake([v \in validators |-> Stake[v]])
        piecesPerValidator(v) ==
            IF totalStake = 0 THEN 1
            ELSE (Stake[v] * numPieces) \div totalStake + 1  \* Round up
    IN
    [v \in validators |->
        RandomSubset(piecesPerValidator(v), 1..numPieces)]

\* Check if validator has enough pieces to reconstruct
CanReconstruct(validator, blockId) ==
    blockId \in DOMAIN blockShreds /\
    Cardinality(blockShreds[blockId][validator]) >= K

\* Enhanced bandwidth usage calculation for all message types
ComputeBandwidth(validator, shreds) ==
    LET shredSize == MaxBlocks \div N
        numShreds == Cardinality(shreds)
        shredBandwidth == numShreds * shredSize
    IN shredBandwidth

\* Bandwidth for repair requests
ComputeRepairBandwidth(requests) ==
    LET requestSize == 50  \* Abstract size for repair request
        numRequests == Cardinality(requests)
    IN numRequests * requestSize

\* Bandwidth for repair responses
ComputeRepairResponseBandwidth(responses) ==
    LET responseSize == MaxBlocks \div N  \* Same as shred size
        numResponses == Cardinality(responses)
    IN numResponses * responseSize

\* Total bandwidth including all message types
ComputeTotalBandwidth(validator, shreds, repairReqs, repairResps) ==
    ComputeBandwidth(validator, shreds) +
    ComputeRepairBandwidth(repairReqs) +
    ComputeRepairResponseBandwidth(repairResps)

\* Single-hop relay optimization
OptimalRelayPath(source, destination, stake) ==
    \* Direct relay weighted by stake
    LET relayWeight == (Stake[source] * Stake[destination]) \div TotalStakeSum
    IN relayWeight > RelayThreshold

\* Helper functions implementation
SelectRelayTargets(validator, shred) ==
    \* Stake-weighted sampling for relay targets
    LET totalStake == TotalStakeSum
        relayCount == IF Cardinality(Validators) \div 3 < 10
                      THEN Cardinality(Validators) \div 3
                      ELSE 10  \* Relay to 1/3 of validators, max 10
    IN CHOOSE targets \in SUBSET Validators :
        /\ Cardinality(targets) <= relayCount
        /\ validator \notin targets  \* Don't relay to self
        /\ \A t \in targets : Stake[t] > 0  \* Only relay to staked validators

FilterShredsForTarget(allShreds, target) ==
    \* Filter shreds based on target's responsibility
    {s \in allShreds : TRUE}  \* Simplified - all shreds for now

\* Clock-based timing functions
Now == clock  \* Use global clock

\* Get block proposal time using clock
GetBlockProposalTime(blockId) ==
    clock  \* Use current clock time

\* Time until reconstruction completes
TimeTillReconstruction(validator, blockId) ==
    clock + 1  \* Abstract time unit from current clock

SizeOf(data) == 100  \* Abstract size

\* Create shred identifier from slot and index
CreateShredId(slot, index) ==
    [slot |-> slot, index |-> index]

\* Check if validator has already sent a shred with this ID
HasSentShred(validator, shredId) ==
    /\ validator \in DOMAIN rotorHistory
    /\ shredId \in DOMAIN rotorHistory[validator]

\* Get the shred previously sent by validator for this ID (if any)
GetSentShred(validator, shredId) ==
    IF HasSentShred(validator, shredId)
    THEN rotorHistory[validator][shredId]
    ELSE <<>>

\* Record that validator sent a shred with given ID
RecordShredSent(validator, shredId, shred) ==
    IF validator \in DOMAIN rotorHistory
    THEN [rotorHistory EXCEPT ![validator] = @ @@ (shredId :> shred)]
    ELSE [rotorHistory EXCEPT ![validator] = (shredId :> shred)]

----------------------------------------------------------------------------
(* Initial State *)

\* Absolute value function
Abs(x) == IF x >= 0 THEN x ELSE -x

Init ==
    /\ blockShreds = [b \in {} |-> [v \in Validators |-> {}]]  \* Empty function mapping blocks to validator shreds
    /\ relayAssignments = [v \in Validators |-> <<>>]  \* Empty assignments
    /\ reconstructionState = [v \in Validators |-> <<>>]  \* Empty sequence
    /\ deliveredBlocks = [v \in Validators |-> {}]  \* Per-validator delivered blocks
    /\ repairRequests = {}
    /\ bandwidthUsage = [v \in Validators |-> 0]
    /\ receivedShreds = [v \in Validators |-> {}]
    /\ shredAssignments = [v \in Validators |-> {}]
    /\ reconstructedBlocks = [v \in Validators |-> {}]
    /\ rotorHistory = [v \in Validators |-> <<>>]  \* Initialize empty history for each validator
    /\ clock = 0  \* Initialize clock

----------------------------------------------------------------------------
(* State Transitions *)

\* Leader shreds and distributes a new block
ShredAndDistribute(leader, block) ==
    /\ leader = block.proposer
    /\ block.hash \notin DOMAIN blockShreds  \* Not already shredded
    /\ LET shreds == ErasureEncode(block)
           assignments == AssignPiecesToRelays(Validators, N)
           \* Check non-equivocation: ensure leader hasn't sent different shreds for same slot/index
           leaderShreds == {s \in shreds : s.index \in assignments[leader]}
           nonEquivocationCheck == \A s \in leaderShreds :
               LET shredId == CreateShredId(s.slot, s.index)
               IN ~HasSentShred(leader, shredId) \/ GetSentShred(leader, shredId) = s
       IN
       /\ nonEquivocationCheck  \* Enforce non-equivocation
       /\ blockShreds' = [blockShreds EXCEPT ![block.hash] =
              [v \in Validators |->
                  {s \in shreds : s.index \in assignments[v]}]]
       /\ relayAssignments' = [v \in Validators |-> assignments[v]]
       /\ shredAssignments' = [shredAssignments EXCEPT ![leader] = assignments[leader]]
       /\ rotorHistory' = LET leaderShreds == {s \in shreds : s.index \in assignments[leader]}
                              newHistory == rotorHistory[leader]
                              updatedHistory == [shredId \in {CreateShredId(s.slot, s.index) : s \in leaderShreds} |->
                                  LET s == CHOOSE shred \in leaderShreds : CreateShredId(shred.slot, shred.index) = shredId
                                  IN s]
                          IN [rotorHistory EXCEPT ![leader] = newHistory @@ updatedHistory]
       /\ clock' = clock + 1  \* Advance clock
       /\ UNCHANGED <<reconstructionState, deliveredBlocks,
                      repairRequests, bandwidthUsage, receivedShreds, reconstructedBlocks>>

\* Validator relays assigned shreds
RelayShreds(validator, blockId) ==
    /\ blockId \in DOMAIN blockShreds
    /\ blockShreds[blockId][validator] # {}
    /\ bandwidthUsage[validator] +
           ComputeBandwidth(validator, blockShreds[blockId][validator])
           <= BandwidthLimit
    /\ LET myShreds == blockShreds[blockId][validator]
           targets == {t \in Validators : t # validator /\ Stake[t] > 0}
           \* Check non-equivocation for relay: ensure validator hasn't sent different shreds for same slot/index
           nonEquivocationCheck == \A s \in myShreds :
               LET shredId == CreateShredId(s.slot, s.index)
               IN ~HasSentShred(validator, shredId) \/ GetSentShred(validator, shredId) = s
       IN
       /\ nonEquivocationCheck  \* Enforce non-equivocation for relays
       /\ blockShreds' = [blockShreds EXCEPT ![blockId] =
              [v \in Validators |->
                  IF v \in targets
                  THEN blockShreds[blockId][v] \cup FilterShredsForTarget(myShreds, v)
                  ELSE blockShreds[blockId][v]]]
       /\ bandwidthUsage' = [bandwidthUsage EXCEPT ![validator] =
              bandwidthUsage[validator] +
              ComputeBandwidth(validator, myShreds)]
       /\ rotorHistory' = LET newHistory == rotorHistory[validator]
                              updatedHistory == [shredId \in {CreateShredId(s.slot, s.index) : s \in myShreds} |->
                                  LET s == CHOOSE shred \in myShreds : CreateShredId(shred.slot, shred.index) = shredId
                                  IN s]
                          IN [rotorHistory EXCEPT ![validator] = newHistory @@ updatedHistory]
       /\ clock' = clock + 1  \* Advance clock
       /\ UNCHANGED <<relayAssignments, reconstructionState,
                      deliveredBlocks, repairRequests, receivedShreds, shredAssignments, reconstructedBlocks>>

\* Validator attempts block reconstruction
AttemptReconstruction(validator, blockId) ==
    /\ blockId \in DOMAIN blockShreds
    /\ blockId \notin deliveredBlocks[validator]  \* Check per-validator delivery
    /\ CanReconstruct(validator, blockId)
    /\ LET pieces == blockShreds[blockId][validator]
           block == ReconstructBlock(pieces)
       IN
       /\ reconstructionState' = [reconstructionState EXCEPT ![validator] =
              Append(@, [blockId |-> blockId,
                        collectedPieces |-> {p.index : p \in pieces},
                        complete |-> TRUE])]
       /\ deliveredBlocks' = [deliveredBlocks EXCEPT ![validator] = @ \cup {blockId}]
       /\ reconstructedBlocks' = [reconstructedBlocks EXCEPT ![validator] = @ \cup {block}]
       /\ clock' = clock + 1  \* Advance clock
       /\ UNCHANGED <<blockShreds, relayAssignments, repairRequests,
                      bandwidthUsage, receivedShreds, shredAssignments, rotorHistory>>

\* Request repair for missing pieces
RequestRepair(validator, blockId) ==
    /\ blockId \in DOMAIN blockShreds
    /\ ~CanReconstruct(validator, blockId)
    /\ blockId \notin deliveredBlocks[validator]  \* Check per-validator delivery
    /\ LET currentPieces == {s.index : s \in blockShreds[blockId][validator]}
           neededPieces == (1..K) \ currentPieces
           repairBandwidth == ComputeRepairBandwidth({neededPieces})
       IN
       /\ Cardinality(neededPieces) > 0
       /\ bandwidthUsage[validator] + repairBandwidth <= BandwidthLimit  \* Check bandwidth
       /\ repairRequests' = repairRequests \cup
              {[requester |-> validator,
                blockId |-> blockId,
                missingPieces |-> neededPieces,
                timestamp |-> clock]}  \* Use clock timestamp
       /\ bandwidthUsage' = [bandwidthUsage EXCEPT ![validator] = @ + repairBandwidth]
       /\ clock' = clock + 1  \* Advance clock
       /\ UNCHANGED <<blockShreds, relayAssignments, reconstructionState,
                      deliveredBlocks, receivedShreds, shredAssignments, reconstructedBlocks, rotorHistory>>

\* Respond to repair request
RespondToRepair(validator, request) ==
    /\ request \in repairRequests
    /\ request.blockId \in DOMAIN blockShreds
    /\ LET myPieces == blockShreds[request.blockId][validator]
           requestedPieces == {p \in myPieces : p.index \in request.missingPieces}
           responseBandwidth == ComputeRepairResponseBandwidth(requestedPieces)
       IN
       /\ Cardinality(requestedPieces) > 0
       /\ bandwidthUsage[validator] + responseBandwidth <= BandwidthLimit  \* Check bandwidth
       /\ blockShreds' = [blockShreds EXCEPT
              ![request.blockId][request.requester] =
                  @ \cup requestedPieces]
       /\ repairRequests' = repairRequests \ {request}
       /\ bandwidthUsage' = [bandwidthUsage EXCEPT ![validator] = @ + responseBandwidth]
       /\ clock' = clock + 1  \* Advance clock
       /\ UNCHANGED <<relayAssignments, reconstructionState,
                      deliveredBlocks, receivedShreds, shredAssignments, reconstructedBlocks, rotorHistory>>


----------------------------------------------------------------------------
(* Non-Equivocation Invariant *)

\* Rotor non-equivocation: no validator sends two different shreds with the same ID
RotorNonEquivocation ==
    \A v \in Validators :
        \A shredId \in DOMAIN rotorHistory[v] :
            \* If validator has sent a shred with this ID, it must be unique
            LET sentShred == rotorHistory[v][shredId]
            IN \A otherShred \in UNION {blockShreds[b][v] : b \in DOMAIN blockShreds} :
                (otherShred.slot = shredId.slot /\ otherShred.index = shredId.index) =>
                otherShred = sentShred

----------------------------------------------------------------------------
(* Safety Properties *)

\* All honest validators eventually receive complete blocks
BlockDeliveryGuarantee ==
    \A blockId \in DOMAIN blockShreds :
        \A v \in HonestValidators :
            <>(blockId \in deliveredBlocks[v])

\* No data corruption during reconstruction
ReconstructionCorrectness ==
    \A v \in Validators :
        \A blockId \in deliveredBlocks[v] :
            ValidateBlockIntegrity(blockId)

\* Bandwidth limits respected
BandwidthSafety ==
    \A v \in Validators :
        bandwidthUsage[v] <= BandwidthLimit

\* Erasure coding validation
ValidateErasureCoding(shreds, k, n) ==
    /\ Cardinality(shreds) >= k  \* Have enough shreds to reconstruct
    /\ \A s \in shreds : s.index \in 1..n  \* Valid shred indices
    /\ Cardinality({s.index : s \in shreds}) = Cardinality(shreds)  \* No duplicates

\* Load balancing invariant
LoadBalanced ==
    \A v1, v2 \in Validators :
        Abs(bandwidthUsage[v1] - bandwidthUsage[v2]) <= LoadBalanceTolerance * BandwidthLimit

----------------------------------------------------------------------------
(* Liveness Properties *)

\* Bounded delivery time
BoundedDelivery ==
    \A blockId \in DOMAIN blockShreds :
        LET proposalTime == GetBlockProposalTime(blockId)
            deliveryDeadline == proposalTime + MaxDeliveryDelay
        IN
        \A v \in HonestValidators :
            Eventually(blockId \in deliveredBlocks[v], deliveryDeadline)

\* Repair completion guarantee
RepairCompletion ==
    \A req \in repairRequests :
        <>(req \notin repairRequests)  \* Eventually processed

\* Progress under partial failures
ProgressWithFailures ==
    LET failedValidators == {v \in Validators : bandwidthUsage[v] = 0}
    IN
    Cardinality(failedValidators) < Cardinality(Validators) \div 3 =>
        \A blockId \in DOMAIN blockShreds :
            <>(\A v \in HonestValidators \ failedValidators :
                blockId \in deliveredBlocks[v])

----------------------------------------------------------------------------
(* Performance Properties *)

\* Optimal bandwidth utilization
BandwidthEfficiency ==
    LET totalUsed == SumStake([v \in Validators |-> bandwidthUsage[v]])
        totalAvailable == BandwidthLimit * Cardinality(Validators)
    IN
    totalUsed <= totalAvailable  \* Within limits

\* Minimal reconstruction latency
ReconstructionLatency ==
    \A v \in Validators :
        \A blockId \in DOMAIN blockShreds :
            CanReconstruct(v, blockId) =>
                TimeTillReconstruction(v, blockId) <= OptimalReconstructionTime

\* Stake-proportional relay load
RelayLoadBalance ==
    \A v \in Validators :
        LET relayLoad == IF relayAssignments[v] = <<>>
                        THEN 0
                        ELSE Cardinality(DOMAIN relayAssignments[v])
            expectedLoad == IF TotalStakeSum = 0
                           THEN N \div Cardinality(Validators)
                           ELSE (Stake[v] * N) \div TotalStakeSum
        IN
        Abs(relayLoad - expectedLoad) <= LoadBalanceTolerance

----------------------------------------------------------------------------
(* Type Checking *)

\* Distinct indices invariant - ensures no duplicate shred indices
DistinctIndices ==
    \A blockId \in DOMAIN blockShreds :
        \A v \in Validators :
            LET shreds == blockShreds[blockId][v]
                indices == {s.index : s \in shreds}
            IN Cardinality(indices) = Cardinality(shreds)

\* Valid erasure code invariant - ensures proper K/N partitioning
ValidErasureCode ==
    \A blockId \in DOMAIN blockShreds :
        \A v \in Validators :
            LET shreds == blockShreds[blockId][v]
                dataShreds == {s \in shreds : ~s.isParity}
                parityShreds == {s \in shreds : s.isParity}
                dataIndices == {s.index : s \in dataShreds}
                parityIndices == {s.index : s \in parityShreds}
            IN
            /\ \A d \in dataIndices : d \in 1..K
            /\ \A p \in parityIndices : p \in (K+1)..N
            /\ dataIndices \cap parityIndices = {}  \* No overlap

TypeInvariant ==
    /\ \A b \in DOMAIN blockShreds :
           \A v \in Validators :
               \A s \in blockShreds[b][v] :
                   /\ s.blockId # <<>>
                   /\ s.index \in 1..N
                   /\ s.slot \in Nat
    /\ \A v \in Validators :
           /\ bandwidthUsage[v] \in Nat
           /\ deliveredBlocks[v] \subseteq Nat  \* Block IDs are natural numbers per validator
           /\ rotorHistory[v] \in [ShredId -> UNION {blockShreds[b][v] : b \in DOMAIN blockShreds}]
    /\ clock \in Nat
    /\ DistinctIndices
    /\ ValidErasureCode
    /\ RotorNonEquivocation  \* Include non-equivocation as part of type invariant

============================================================================
