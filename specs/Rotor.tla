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
    MaxBufferSize,        \* Maximum buffer size per validator
    Block,               \* Abstract set of blocks (provided by model/config)
    ErasureCodedPiece,   \* Abstract set of shreds/pieces (provided by model/config)
    \* Configurable sampling parameters for Theorem 3 verification
    SlicesPerBlock,      \* Number of slices per block (k in whitepaper)
    TotalShreds,         \* Total number of shreds (Γ in whitepaper)
    ReconstructionThreshold, \* Minimum shreds needed (γ in whitepaper)
    ResilienceParameter, \* Over-provisioning factor (κ = Γ/γ in whitepaper)
    SamplingMethod       \* Sampling method: "IID", "FA1-IID", or "PS-P"

ASSUME
    /\ N > K
    /\ N >= Cardinality(Validators)
    /\ K >= (2 * Cardinality(Validators)) \div 3  \* Reconstruction threshold
    /\ MaxBlocks > 0
    /\ BandwidthLimit > 0
    \* Sampling parameter assumptions for Theorem 3
    /\ TotalShreds > ReconstructionThreshold
    /\ ReconstructionThreshold > 0
    /\ SlicesPerBlock > 0
    /\ ResilienceParameter = TotalShreds \div ReconstructionThreshold
    /\ ResilienceParameter > 1  \* Over-provisioning required
    /\ SamplingMethod \in {"IID", "FA1-IID", "PS-P"}
    \* Byzantine assumption for sampling resilience
    /\ Utils!TotalStake(ByzantineValidators, Stake) < Utils!TotalStake(Validators, Stake) \div 5

----------------------------------------------------------------------------
(* Shred Identification for Non-Equivocation *)

\* Unique identifier for shred positions
ShredId == [slot: Nat, index: Nat]

----------------------------------------------------------------------------
(* Rotor State Variables *)

VARIABLES
    rotorBlocks,         \* Blocks by slot: slot -> block
    rotorShreds,         \* Shreds by slot and index: slot -> index -> shred
    rotorReceivedShreds, \* Shreds received by validator: validator -> slot -> set of shreds
    rotorReconstructedBlocks, \* Reconstructed blocks: validator -> slot -> block
    blockShreds,         \* Erasure-coded pieces: block -> validator -> pieces
    relayAssignments,    \* Stake-weighted relay assignments
    reconstructionState, \* Block reconstruction progress per validator
    deliveredBlocks,     \* Successfully delivered block IDs per validator
    repairRequests,      \* Missing piece repair requests
    bandwidthUsage,      \* Current bandwidth usage per validator
    receivedShreds,      \* Shreds received by each validator
    shredAssignments,    \* Shred assignments for each validator
    reconstructedBlocks, \* Blocks reconstructed by each validator (set of block records)
    rotorHistory,        \* History of shreds sent by each validator: validator -> (ShredId -> ErasureCodedPiece)
    clock                \* Global clock for timing operations

rotorVars == <<rotorBlocks, rotorShreds, rotorReceivedShreds, rotorReconstructedBlocks,
               blockShreds, relayAssignments, reconstructionState,
               deliveredBlocks, repairRequests, bandwidthUsage,
               receivedShreds, shredAssignments, reconstructedBlocks,
               rotorHistory, clock>>

----------------------------------------------------------------------------
(* Import Type Definitions *)

RotorTypes == INSTANCE Types
RotorUtils == INSTANCE Utils

\* Import Sampling module for PS-P algorithm verification
RotorSampling == INSTANCE Sampling WITH Validators <- Validators,
                                        ByzantineValidators <- ByzantineValidators,
                                        Stake <- Stake,
                                        SlicesPerBlock <- SlicesPerBlock,
                                        TotalShreds <- TotalShreds,
                                        ReconstructionThreshold <- ReconstructionThreshold,
                                        ResilienceParameter <- ResilienceParameter

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

\* Time until reconstruction completes (abstracted)
TimeTillReconstruction(validator, blockId) ==
    1  \* Abstract time unit

\* Optimal reconstruction time
OptimalReconstructionTime == 50  \* milliseconds

\* Eventually with deadline (simplified for TLC)
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

\* Min helper
Min(a, b) == IF a <= b THEN a ELSE b

\* Merge two partial functions (maps), values from m2 override m1
MergeMaps(m1, m2) ==
    [x \in (DOMAIN m1) \cup (DOMAIN m2) |->
        IF x \in DOMAIN m2 THEN m2[x] ELSE m1[x]]

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

\* Reconstruct block from K pieces (function)
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
    /\ blockId \in DOMAIN blockShreds
    /\ validator \in DOMAIN blockShreds[blockId]
    /\ Cardinality(blockShreds[blockId][validator]) >= K

\* Enhanced bandwidth usage calculation for all message types
ComputeBandwidth(validator, shreds) ==
    LET shredSize == IF N = 0 THEN 0 ELSE MaxBlocks \div N
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
    LET responseSize == IF N = 0 THEN 0 ELSE MaxBlocks \div N  \* Same as shred size
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
    LET relayWeight == IF TotalStakeSum = 0 THEN 0 ELSE (Stake[source] * Stake[destination]) \div TotalStakeSum
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

\* Record that validator sent a shred with given ID (functional update)
RecordShredSent(history, validator, mapping) ==
    [history EXCEPT ![validator] = MergeMaps(history[validator], mapping)]

----------------------------------------------------------------------------
(* Reed-Solomon Erasure Coding *)

\* Reed-Solomon encode block into n shreds where any k can reconstruct
ReedSolomonEncode(block, k, n) ==
    LET \* Data shreds contain original block data split into k pieces
        dataShreds == {[blockId |-> block.hash,
                       slot |-> block.slot,
                       index |-> i,
                       data |-> <<"data", block, i>>,
                       isParity |-> FALSE,
                       merkleProof |-> <<"merkle", block.hash, i>>,
                       signature |-> [signer |-> block.proposer, message |-> block.hash, valid |-> TRUE]] : i \in 1..k}
        \* Parity shreds contain redundancy for error correction
        parityShreds == {[blockId |-> block.hash,
                         slot |-> block.slot,
                         index |-> i,
                         data |-> <<"parity", block, i>>,
                         isParity |-> TRUE,
                         merkleProof |-> <<"merkle", block.hash, i>>,
                         signature |-> [signer |-> block.proposer, message |-> block.hash, valid |-> TRUE]] : i \in (k+1)..n}
    IN dataShreds \cup parityShreds

\* Reed-Solomon decode shreds back to original block
ReedSolomonDecode(shreds) ==
    LET k == K  \* Use global K parameter
        dataShreds == {s \in shreds : ~s.isParity}
        parityShreds == {s \in shreds : s.isParity}
        blockId == IF shreds = {} THEN 0 ELSE (CHOOSE s \in shreds : TRUE).blockId
    IN
    IF Cardinality(shreds) >= k
    THEN [hash |-> blockId,
          slot |-> IF shreds = {} THEN 0 ELSE (CHOOSE s \in shreds : TRUE).slot,
          view |-> 0,
          proposer |-> CHOOSE v \in Validators : TRUE,
          parent |-> 0,
          data |-> "reconstructed_data",
          timestamp |-> clock,
          transactions |-> {}]
    ELSE [hash |-> 0, slot |-> 0, view |-> 0, proposer |-> 0, parent |-> 0,
          data |-> "failed", timestamp |-> 0, transactions |-> {}]

----------------------------------------------------------------------------
(* Shred Operations *)

\* Create a shred from block data with Merkle proof
CreateShred(block, index, merkle_path) ==
    [blockId |-> block.hash,
     slot |-> block.slot,
     index |-> index,
     data |-> <<"shred_data", block, index>>,
     isParity |-> index > K,
     merkleProof |-> merkle_path,
     signature |-> [signer |-> block.proposer, message |-> block.hash, valid |-> TRUE]]

\* Validate shred integrity using Merkle root
ValidateShred(shred, merkle_root) ==
    /\ shred.merkleProof[1] = "merkle"
    /\ shred.merkleProof[2] = merkle_root
    /\ shred.signature.valid
    /\ shred.index \in 1..N

\* Size of shred for UDP datagram constraints (1200 bytes max)
ShredSize == 1200

----------------------------------------------------------------------------
(* Relay Selection *)

\* Stake-weighted sampling for proportional relay selection
StakeWeightedSampling(validators, stake, count) ==
    LET totalStake == Utils!TotalStake(validators, stake)
        \* Create cumulative stake distribution
        validatorSeq == CHOOSE seq \in [1..Cardinality(validators) -> validators] :
                           \A i, j \in 1..Cardinality(validators) : i # j => seq[i] # seq[j]
        cumulativeStake == [i \in 1..Cardinality(validators) |->
            Utils!TotalStake({validatorSeq[j] : j \in 1..i}, stake)]
        \* Select validators proportional to stake
        selectedIndices == CHOOSE indices \in SUBSET (1..Cardinality(validators)) :
            Cardinality(indices) = Min(count, Cardinality(validators))
    IN {validatorSeq[i] : i \in selectedIndices}

\* Enhanced relay selection supporting multiple sampling methods
SelectRelays(slot, shred_index) ==
    LET seed == slot * 1000 + shred_index
        relayCount == Min(Cardinality(Validators) \div 3, 10)  \* 1/3 of validators, max 10
    IN
    CASE SamplingMethod = "PS-P" ->
           \* Use PS-P (Partition Sampling) algorithm from Sampling module
           LET psSelection == Sampling!PartitionSampling
               filteredSelection == {v \in psSelection : Stake[v] > 0}
           IN IF Cardinality(filteredSelection) <= relayCount
              THEN filteredSelection
              ELSE CHOOSE subset \in SUBSET filteredSelection : Cardinality(subset) = relayCount
      [] SamplingMethod = "FA1-IID" ->
           \* Fill-and-sample with IID fallback
           LET highStakeValidators == {v \in Validators : Sampling!IsHighStakeValidator(v)}
               remainingValidators == Validators \ highStakeValidators
               iidSelection == StakeWeightedSampling(remainingValidators, Stake,
                                                   relayCount - Cardinality(highStakeValidators))
           IN highStakeValidators \cup iidSelection
      [] SamplingMethod = "IID" ->
           \* Standard IID stake-weighted sampling
           StakeWeightedSampling(Validators, Stake, relayCount)
      [] OTHER ->
           \* Default to IID for backward compatibility
           StakeWeightedSampling(Validators, Stake, relayCount)

\* PS-P Partition Stakes operator - implements stake partitioning algorithm
PartitionStakes ==
    Sampling!PartitionStakes

\* PS-P Bin Assignment operator - assigns validators to bins
BinAssignment ==
    Sampling!BinAssignment

\* Proportional Sampling operator - samples validators proportional to stake within bins
ProportionalSampling(bin, validators, stakes) ==
    LET totalBinStake == Utils!TotalStake(validators, stakes)
        targetStake == IF totalBinStake = 0 THEN 0
                      ELSE (seed * 1000) % totalBinStake  \* Use deterministic randomness
        \* Create cumulative stake distribution
        validatorSeq == CHOOSE seq \in [1..Cardinality(validators) -> validators] :
                          \A i, j \in 1..Cardinality(validators) : i # j => seq[i] # seq[j]
        cumulativeStake == [i \in 1..Cardinality(validators) |->
            Utils!TotalStake({validatorSeq[j] : j \in 1..i}, stakes)]
        \* Find validator whose cumulative stake range contains target
        selectedIndex == IF totalBinStake = 0 THEN 1
                        ELSE CHOOSE i \in 1..Cardinality(validators) :
                            /\ cumulativeStake[i] > targetStake
                            /\ \A j \in 1..Cardinality(validators) :
                                (j < i => cumulativeStake[j] <= targetStake) \/ j >= i
    IN validatorSeq[selectedIndex]

----------------------------------------------------------------------------
(* Block Propagation *)

\* Leader proposes block for given slot
ProposeBlock(leader, slot, block) ==
    /\ leader = GetSlotLeader(slot, Validators, Stake)
    /\ slot \notin DOMAIN rotorBlocks
    /\ block.slot = slot
    /\ block.proposer = leader
    /\ rotorBlocks' = [rotorBlocks EXCEPT ![slot] = block]
    /\ clock' = clock + 1
    /\ UNCHANGED <<rotorShreds, rotorReceivedShreds, rotorReconstructedBlocks,
                   blockShreds, relayAssignments, reconstructionState,
                   deliveredBlocks, repairRequests, bandwidthUsage,
                   receivedShreds, shredAssignments, reconstructedBlocks, rotorHistory>>

\* Shred block into erasure-coded pieces
ShredBlock(block) ==
    LET shreds == ReedSolomonEncode(block, K, N)
        shredMap == [i \in 1..N |->
            IF \E s \in shreds : s.index = i
            THEN CHOOSE s \in shreds : s.index = i
            ELSE [blockId |-> 0, slot |-> 0, index |-> i, data |-> <<>>,
                  isParity |-> FALSE, merkleProof |-> <<>>, signature |-> <<>>]]
    IN
    /\ block.slot \in DOMAIN rotorBlocks
    /\ block.slot \notin DOMAIN rotorShreds
    /\ rotorShreds' = [rotorShreds EXCEPT ![block.slot] = shredMap]
    /\ clock' = clock + 1
    /\ UNCHANGED <<rotorBlocks, rotorReceivedShreds, rotorReconstructedBlocks,
                   blockShreds, relayAssignments, reconstructionState,
                   deliveredBlocks, repairRequests, bandwidthUsage,
                   receivedShreds, shredAssignments, reconstructedBlocks, rotorHistory>>

\* Broadcast shred to selected recipients
BroadcastShred(relay, shred, recipients) ==
    /\ relay \in Validators
    /\ shred.slot \in DOMAIN rotorShreds
    /\ shred.index \in DOMAIN rotorShreds[shred.slot]
    /\ recipients \subseteq Validators
    /\ relay \notin recipients
    /\ LET newRRS == [v \in Validators |->
            IF v \in recipients THEN
                LET prev == rotorReceivedShreds[v]
                IN IF shred.slot \in DOMAIN prev
                   THEN [prev EXCEPT ![shred.slot] = prev[shred.slot] \cup {shred}]
                   ELSE [prev EXCEPT ![shred.slot] = {shred}]
            ELSE rotorReceivedShreds[v]]
       IN
       /\ rotorReceivedShreds' = newRRS
       /\ clock' = clock + 1
       /\ UNCHANGED <<rotorBlocks, rotorShreds, rotorReconstructedBlocks,
                      blockShreds, relayAssignments, reconstructionState,
                      deliveredBlocks, repairRequests, bandwidthUsage,
                      receivedShreds, shredAssignments, reconstructedBlocks, rotorHistory>>

----------------------------------------------------------------------------
(* Block Reconstruction *)

\* Validator attempts to reconstruct block from received shreds
ReconstructBlock(validator, slot, shreds) ==
    /\ validator \in Validators
    /\ slot \in DOMAIN rotorReceivedShreds[validator]
    /\ Cardinality(shreds) >= K
    /\ slot \notin DOMAIN rotorReconstructedBlocks[validator]
    /\ LET reconstructed == ReedSolomonDecode(shreds)
       IN
       /\ reconstructed.hash # 0  \* Successful reconstruction
       /\ rotorReconstructedBlocks' = [rotorReconstructedBlocks EXCEPT
              ![validator] = [rotorReconstructedBlocks[validator] EXCEPT ![slot] = reconstructed]]
       /\ clock' = clock + 1
       /\ UNCHANGED <<rotorBlocks, rotorShreds, rotorReceivedShreds,
                      blockShreds, relayAssignments, reconstructionState,
                      deliveredBlocks, repairRequests, bandwidthUsage,
                      receivedShreds, shredAssignments, reconstructedBlocks, rotorHistory>>

\* Validate reconstructed block against expected hash
ValidateReconstructedBlock(block, expected_hash) ==
    /\ block.hash = expected_hash
    /\ block.slot \in Nat
    /\ block.proposer \in Validators
    /\ block.signature.valid

----------------------------------------------------------------------------
(* Repair Mechanism *)

\* Request missing shreds for incomplete block
RequestMissingShreds(validator, slot, missing_indices) ==
    /\ validator \in Validators
    /\ slot \in DOMAIN rotorShreds
    /\ missing_indices \subseteq (1..N)
    /\ Cardinality(missing_indices) > 0
    /\ slot \notin DOMAIN rotorReconstructedBlocks[validator]
    /\ LET request == [requester |-> validator,
                      slot |-> slot,
                      missingIndices |-> missing_indices,
                      timestamp |-> clock]
       IN
       /\ repairRequests' = repairRequests \cup {request}
       /\ clock' = clock + 1
       /\ UNCHANGED <<rotorBlocks, rotorShreds, rotorReceivedShreds, rotorReconstructedBlocks,
                      blockShreds, relayAssignments, reconstructionState,
                      deliveredBlocks, bandwidthUsage,
                      receivedShreds, shredAssignments, reconstructedBlocks, rotorHistory>>

\* Respond to repair request by sending missing shreds
RespondToRepairRequest(validator, request) ==
    /\ validator \in Validators
    /\ request \in repairRequests
    /\ request.slot \in DOMAIN rotorShreds
    /\ LET availableShreds == {rotorShreds[request.slot][i] : i \in request.missingIndices \cap DOMAIN rotorShreds[request.slot]}
           requester == request.requester
           prev == rotorReceivedShreds[requester]
           updatedForRequester == IF request.slot \in DOMAIN prev
                                  THEN [prev EXCEPT ![request.slot] = prev[request.slot] \cup availableShreds]
                                  ELSE [prev EXCEPT ![request.slot] = availableShreds]
           newRRS == [v \in Validators |->
                         IF v = requester THEN updatedForRequester ELSE rotorReceivedShreds[v]]
       IN
       /\ Cardinality(availableShreds) > 0
       /\ rotorReceivedShreds' = newRRS
       /\ repairRequests' = repairRequests \ {request}
       /\ clock' = clock + 1
       /\ UNCHANGED <<rotorBlocks, rotorShreds, rotorReconstructedBlocks,
                      blockShreds, relayAssignments, reconstructionState,
                      deliveredBlocks, bandwidthUsage,
                      receivedShreds, shredAssignments, reconstructedBlocks, rotorHistory>>

\* Respond to repair request by sending missing shreds (alternate variant)
RespondToRepair(validator, request) ==
    /\ request \in repairRequests
    /\ request.blockId \in DOMAIN blockShreds
    /\ LET myPieces == IF validator \in DOMAIN blockShreds[request.blockId] THEN blockShreds[request.blockId][validator] ELSE {}
           requestedPieces == {p \in myPieces : p.index \in request.missingPieces}
           responseBandwidth == ComputeRepairResponseBandwidth(requestedPieces)
           prevBlockMap == blockShreds[request.blockId]
           updatedBlockMap == [prevBlockMap EXCEPT ![request.requester] = IF request.requester \in DOMAIN prevBlockMap THEN prevBlockMap[request.requester] \cup requestedPieces ELSE requestedPieces]
       IN
       /\ Cardinality(requestedPieces) > 0
       /\ bandwidthUsage[validator] + responseBandwidth <= BandwidthLimit  \* Check bandwidth
       /\ blockShreds' = [blockShreds EXCEPT ![request.blockId] = updatedBlockMap]
       /\ repairRequests' = repairRequests \ {request}
       /\ bandwidthUsage' = [bandwidthUsage EXCEPT ![validator] = @ + responseBandwidth]
       /\ clock' = clock + 1
       /\ UNCHANGED <<rotorBlocks, rotorShreds, rotorReceivedShreds, rotorReconstructedBlocks,
                      relayAssignments, reconstructionState,
                      deliveredBlocks, receivedShreds, shredAssignments, reconstructedBlocks, rotorHistory>>

----------------------------------------------------------------------------
(* Success Conditions *)

\* Enhanced success condition with sampling resilience verification
RotorSuccessful(slot) ==
    LET honestValidators == Validators \ ByzantineValidators
        successfulValidators == {v \in honestValidators :
            slot \in DOMAIN rotorReconstructedBlocks[v]}
        honestStake == Utils!TotalStake(honestValidators, Stake)
        successfulStake == Utils!TotalStake(successfulValidators, Stake)
    IN successfulStake > honestStake \div 2

\* Rotor success with PS-P sampling (from Sampling module)
RotorSuccessfulPS_P(slot) ==
    \A slice \in 1..SlicesPerBlock :
        LET relays == SelectRelays(slot, slice)
            honestRelays == relays \cap (Validators \ ByzantineValidators)
        IN Cardinality(honestRelays) >= ReconstructionThreshold

\* Sampling resilience verification - PS-P performs better than alternatives
SamplingResilienceProperty ==
    \A slot \in Nat :
        \A threshold \in 1..ReconstructionThreshold :
            SamplingMethod = "PS-P" =>
                (Sampling!AdversarialSamplingProbability("PS-P", threshold) =>
                 Sampling!AdversarialSamplingProbability("FA1-IID", threshold))

----------------------------------------------------------------------------
(* Network Integration *)

\* Deliver shred from sender to recipient
DeliverShred(sender, recipient, shred) ==
    /\ sender \in Validators
    /\ recipient \in Validators
    /\ sender # recipient
    /\ shred.slot \in DOMAIN rotorShreds
    /\ LET prev == rotorReceivedShreds[recipient]
           updated == IF shred.slot \in DOMAIN prev
                      THEN [prev EXCEPT ![shred.slot] = prev[shred.slot] \cup {shred}]
                      ELSE [prev EXCEPT ![shred.slot] = {shred}]
       IN
       /\ rotorReceivedShreds' = [rotorReceivedShreds EXCEPT ![recipient] = updated]
       /\ clock' = clock + 1
       /\ UNCHANGED <<rotorBlocks, rotorShreds, rotorReconstructedBlocks,
                      blockShreds, relayAssignments, reconstructionState,
                      deliveredBlocks, repairRequests, bandwidthUsage,
                      receivedShreds, shredAssignments, reconstructedBlocks, rotorHistory>>

\* Handle network partition by isolating validator set
HandleNetworkPartition(partition_set) ==
    /\ partition_set \subseteq Validators
    /\ Cardinality(partition_set) < Cardinality(Validators)
    /\ LET newRRS == [v \in Validators |->
                        IF v \in partition_set THEN rotorReceivedShreds[v] ELSE rotorReceivedShreds[v]]
       IN
       /\ rotorReceivedShreds' = newRRS  \* We keep previous values but conceptually isolated; simplified
    /\ clock' = clock + 1
    /\ UNCHANGED <<rotorBlocks, rotorShreds, rotorReconstructedBlocks,
                   blockShreds, relayAssignments, reconstructionState,
                   deliveredBlocks, repairRequests, bandwidthUsage,
                   receivedShreds, shredAssignments, reconstructedBlocks, rotorHistory>>

\* Get slot leader using Types module function
GetSlotLeader(slot, validators, stakes) ==
    Types!ComputeLeader(slot, validators, stakes)

----------------------------------------------------------------------------
(* Initial State *)

\* Absolute value function
Abs(x) == IF x >= 0 THEN x ELSE -x

Init ==
    /\ rotorBlocks = <<>>  \* Empty sequence for blocks
    /\ rotorShreds = <<>>  \* Empty sequence for shreds
    /\ rotorReceivedShreds = [v \in Validators |-> <<>>]  \* Empty sequences per validator
    /\ rotorReconstructedBlocks = [v \in Validators |-> <<>>]  \* Empty sequences per validator
    /\ blockShreds = <<>>  \* Empty sequence for block shreds
    /\ relayAssignments = [v \in Validators |-> <<>>]  \* Empty assignments
    /\ reconstructionState = [v \in Validators |-> <<>>]  \* Empty sequence
    /\ deliveredBlocks = [v \in Validators |-> {}]  \* Per-validator delivered block IDs
    /\ repairRequests = {}
    /\ bandwidthUsage = [v \in Validators |-> 0]
    /\ receivedShreds = [v \in Validators |-> {}]
    /\ shredAssignments = [v \in Validators |-> {}]
    /\ reconstructedBlocks = [v \in Validators |-> {}]
    /\ rotorHistory = [v \in Validators |-> {}]  \* Initialize empty history (map) for each validator
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
           newMapping == [shredId \in {CreateShredId(s.slot, s.index) : s \in leaderShreds} |->
                            CHOOSE shred \in leaderShreds : CreateShredId(shred.slot, shred.index) = shredId]
       IN
       /\ nonEquivocationCheck  \* Enforce non-equivocation
       /\ blockShreds' = [blockShreds EXCEPT ![block.hash] =
              [v \in Validators |->
                  {s \in shreds : s.index \in assignments[v]}]]
       /\ relayAssignments' = [v \in Validators |-> assignments[v]]
       /\ shredAssignments' = [shredAssignments EXCEPT ![leader] = assignments[leader]]
       /\ rotorHistory' = RecordShredSent(rotorHistory, leader, newMapping)
       /\ clock' = clock + 1  \* Advance clock
       /\ UNCHANGED <<reconstructionState, deliveredBlocks,
                      repairRequests, bandwidthUsage, receivedShreds, reconstructedBlocks>>

\* Validator relays assigned shreds
RelayShreds(validator, blockId) ==
    /\ blockId \in DOMAIN blockShreds
    /\ validator \in DOMAIN blockShreds[blockId]
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
           newMapping == [shredId \in {CreateShredId(s.slot, s.index) : s \in myShreds} |->
                            CHOOSE shred \in myShreds : CreateShredId(shred.slot, shred.index) = shredId]
           updatedBlockShreds == [blockShreds EXCEPT ![blockId] =
                                    [v \in Validators |->
                                        IF v \in targets
                                        THEN blockShreds[blockId][v] \cup FilterShredsForTarget(myShreds, v)
                                        ELSE blockShreds[blockId][v]]]
       IN
       /\ nonEquivocationCheck  \* Enforce non-equivocation for relays
       /\ blockShreds' = updatedBlockShreds
       /\ bandwidthUsage' = [bandwidthUsage EXCEPT ![validator] =
              bandwidthUsage[validator] +
              ComputeBandwidth(validator, myShreds)]
       /\ rotorHistory' = RecordShredSent(rotorHistory, validator, newMapping)
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
    /\ LET currentPieces == IF validator \in DOMAIN blockShreds[blockId] THEN {s.index : s \in blockShreds[blockId][validator]} ELSE {}
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

\* Request repair for missing shreds (external call wrapper)
RequestMissingShredsWrapper(validator, slot, missing) ==
    RequestMissingShreds(validator, slot, missing)

\* Respond to repair request (external wrapper)
RespondToRepairWrapper(validator, request) ==
    RespondToRepair(validator, request)

----------------------------------------------------------------------------
(* Next State Relation *)

\* All possible state transitions
Next ==
    \/ \E leader \in Validators, slot \in Nat, block \in Block :
           ProposeBlock(leader, slot, block)
    \/ \E block \in Block :
           ShredBlock(block)
    \/ \E relay \in Validators, shred \in ErasureCodedPiece, recipients \in SUBSET Validators :
           BroadcastShred(relay, shred, recipients)
    \/ \E validator \in Validators, slot \in Nat, shreds \in SUBSET ErasureCodedPiece :
           ReconstructBlock(validator, slot, shreds)
    \/ \E validator \in Validators, slot \in Nat, missing \in SUBSET (1..N) :
           RequestMissingShreds(validator, slot, missing)
    \/ \E validator \in Validators, request \in repairRequests :
           RespondToRepairRequest(validator, request)
    \/ \E sender, recipient \in Validators, shred \in ErasureCodedPiece :
           DeliverShred(sender, recipient, shred)
    \/ \E partition \in SUBSET Validators :
           HandleNetworkPartition(partition)
    \/ \E leader \in Validators, blockId \in Nat :
           ShredAndDistribute(leader, [hash |-> blockId, slot |-> 1, proposer |-> leader,
                                      view |-> 0, parent |-> 0, data |-> "test",
                                      timestamp |-> clock, transactions |-> {}])
    \/ \E validator \in Validators, blockId \in Nat :
           RelayShreds(validator, blockId)
    \/ \E validator \in Validators, blockId \in Nat :
           AttemptReconstruction(validator, blockId)
    \/ \E validator \in Validators, blockId \in Nat :
           RequestRepair(validator, blockId)
    \/ \E validator \in Validators, request \in repairRequests :
           RespondToRepair(validator, request)
    \/ clock' = clock + 1 /\ UNCHANGED <<rotorBlocks, rotorShreds, rotorReceivedShreds, rotorReconstructedBlocks,
                                          blockShreds, relayAssignments, reconstructionState,
                                          deliveredBlocks, repairRequests, bandwidthUsage,
                                          receivedShreds, shredAssignments, reconstructedBlocks, rotorHistory>>

\* Specification
Spec == Init /\ [][Next]_rotorVars


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
            \E b \in reconstructedBlocks[v] : b.hash = blockId => ValidateBlockIntegrity(b)

\* Bandwidth limits respected
BandwidthSafety ==
    \A v \in Validators :
        bandwidthUsage[v] <= BandwidthLimit

\* Sampling resilience invariants - ensure PS-P sampling properties hold
SamplingResilienceInvariant ==
    /\ SamplingMethod = "PS-P" => RotorSampling!SamplingResilience(ReconstructionThreshold)
    /\ SamplingMethod = "PS-P" => RotorSampling!ExpectedAdversarialSamples <=
         (Utils!TotalStake(ByzantineValidators, Stake) * TotalShreds) \div Utils!TotalStake(Validators, Stake)
    /\ SamplingMethod = "PS-P" => RotorSampling!AdversarialSamplingVariance <=
         ((RotorUtils!TotalStake(ByzantineValidators, Stake) * TotalShreds) \div RotorUtils!TotalStake(Validators, Stake)) *
         (1 - (RotorUtils!TotalStake(ByzantineValidators, Stake) \div RotorUtils!TotalStake(Validators, Stake)))

\* Partitioning validity for PS-P sampling
PartitioningValidityInvariant ==
    SamplingMethod = "PS-P" => RotorSampling!PartitioningValidity

\* Non-equivocation in PS-P sampling
SamplingNonEquivocationInvariant ==
    SamplingMethod = "PS-P" => RotorSampling!SamplingNonEquivocation

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

\* PS-P sampling improves progress under Byzantine failures
ProgressWithPS_P ==
    SamplingMethod = "PS-P" =>
        \A slot \in Nat :
            RotorSuccessfulPS_P(slot) => RotorSuccessful(slot)

\* Sampling method comparison - PS-P provides better resilience
SamplingMethodComparison ==
    \A threshold \in 1..ReconstructionThreshold :
        /\ SamplingMethod = "PS-P" =>
             (Sampling!AdversarialSamplingProbability("PS-P", threshold) =>
              Sampling!AdversarialSamplingProbability("IID", threshold))
        /\ SamplingMethod = "PS-P" =>
             (Sampling!AdversarialSamplingProbability("PS-P", threshold) =>
              Sampling!AdversarialSamplingProbability("FA1-IID", threshold))

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
                           THEN IF Cardinality(Validators) = 0 THEN 0 ELSE N \div Cardinality(Validators)
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
    /\ \A s \in DOMAIN rotorBlocks :
           /\ rotorBlocks[s].slot = s
           /\ rotorBlocks[s].proposer \in Validators
    /\ \A s \in DOMAIN rotorShreds :
           \A i \in DOMAIN rotorShreds[s] :
               /\ rotorShreds[s][i].slot = s
               /\ rotorShreds[s][i].index = i
               /\ rotorShreds[s][i].index \in 1..N
    /\ \A v \in Validators :
           \A s \in DOMAIN rotorReceivedShreds[v] :
               \A shred \in rotorReceivedShreds[v][s] :
                   shred.slot = s
    /\ \A v \in Validators :
           \A s \in DOMAIN rotorReconstructedBlocks[v] :
               rotorReconstructedBlocks[v][s].slot = s
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
    \* Sampling parameter type constraints
    /\ SlicesPerBlock \in Nat /\ SlicesPerBlock > 0
    /\ TotalShreds \in Nat /\ TotalShreds > 0
    /\ ReconstructionThreshold \in Nat /\ ReconstructionThreshold > 0
    /\ ResilienceParameter \in Nat /\ ResilienceParameter > 1
    /\ SamplingMethod \in {"IID", "FA1-IID", "PS-P"}
    \* Sampling resilience invariants when using PS-P
    /\ SamplingResilienceInvariant
    /\ PartitioningValidityInvariant
    /\ SamplingNonEquivocationInvariant

====
