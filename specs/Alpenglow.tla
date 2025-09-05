---------------------------- MODULE Alpenglow ----------------------------
(***************************************************************************)
(* Formal specification of the Alpenglow consensus protocol, composing    *)
(* Votor (consensus) and Rotor (propagation) components to achieve        *)
(* 100-150ms finalization times.                                          *)
(***************************************************************************)

EXTENDS Integers, Sequences, FiniteSets, TLC

CONSTANTS
    Validators,          \* Set of all validators
    ByzantineValidators, \* Set of Byzantine validators
    OfflineValidators,   \* Set of offline validators
    MaxSlot,             \* Maximum slot number
    MaxView,             \* Maximum view number
    GST,                 \* Global Stabilization Time
    Delta,               \* Network delay bound
    InitialLeader,       \* Initial leader for Votor
    K,                   \* Erasure coding data shreds
    N,                   \* Erasure coding total shreds
    BandwidthLimit,      \* Bandwidth limit per validator
    MaxRetries           \* Maximum retries for Rotor

ASSUME
    /\ ByzantineValidators \subseteq Validators
    /\ OfflineValidators \subseteq Validators
    /\ ByzantineValidators \cap OfflineValidators = {}
    /\ GST >= 0
    /\ Delta > 0
    /\ N > K  \* Erasure coding constraint
    /\ K > 0

\* Import foundational modules with proper parameter mappings
INSTANCE Types WITH Validators <- Validators,
                    ByzantineValidators <- ByzantineValidators,
                    OfflineValidators <- OfflineValidators,
                    MaxSlot <- MaxSlot,
                    MaxView <- MaxView,
                    GST <- GST,
                    Delta <- Delta

INSTANCE Utils

\* Use stake mapping from Types module
HonestValidators == Types!HonestValidators
StakeMapping == Types!Stake

----------------------------------------------------------------------------
(* System State Variables *)

VARIABLES
    \* Time and scheduling
    clock,               \* Current global time
    currentSlot,         \* Current protocol slot

    \* Votor consensus state variables (aligned with Votor module)
    votorView,           \* Current view number for each validator [validator]
    votorVotes,          \* Votes cast by each validator [validator]
    votorTimeouts,       \* Timeout settings per validator per slot [validator][slot]
    votorGeneratedCerts, \* Certificates generated per view [view]
    votorFinalizedChain, \* Finalized chain per validator [validator]
    votorState,          \* Internal state tracking per validator [validator][slot]
    votorObservedCerts,  \* Certificates observed by each validator [validator]

    \* Rotor propagation state variables (aligned with Rotor module)
    rotorBlocks,         \* Blocks by slot: slot -> block
    rotorShreds,         \* Shreds by slot and index: slot -> index -> shred
    rotorReceivedShreds, \* Shreds received by validator: validator -> slot -> set of shreds
    rotorReconstructedBlocks, \* Reconstructed blocks: validator -> slot -> block
    blockShreds,         \* Erasure-coded pieces: block -> validator -> pieces
    relayAssignments,    \* Stake-weighted relay assignments
    reconstructionState, \* Block reconstruction progress per validator
    deliveredBlocks,     \* Successfully delivered blocks per validator
    repairRequests,      \* Missing piece repair requests
    bandwidthUsage,      \* Current bandwidth usage per validator
    receivedShreds,      \* Shreds received by each validator
    shredAssignments,    \* Shred assignments for each validator
    reconstructedBlocks, \* Blocks reconstructed by each validator
    rotorHistory,        \* History of shreds sent by each validator

    \* Network state
    networkMessageQueue,
    networkMessageBuffer,
    networkPartitions,   \* Set of network partitions
    networkDroppedMessages,
    networkDeliveryTime, \* Message delivery time mapping
    messages,            \* In-flight messages (as a set)

    \* Additional state
    finalizedBlocks,     \* Finalized blocks per slot
    finalizedBySlot,     \* Derived mapping slot -> block
    failureStates,       \* Validator failure states
    nonceCounter,        \* Counter for generating unique nonces
    latencyMetrics,      \* Finalization latencies
    bandwidthMetrics     \* Bandwidth consumption

vars == <<clock, currentSlot, votorView, votorVotes, votorTimeouts, votorGeneratedCerts,
          votorFinalizedChain, votorState, votorObservedCerts,
          rotorBlocks, rotorShreds, rotorReceivedShreds, rotorReconstructedBlocks,
          blockShreds, relayAssignments, reconstructionState, deliveredBlocks,
          repairRequests, bandwidthUsage, receivedShreds, shredAssignments,
          reconstructedBlocks, rotorHistory,
          networkMessageQueue, networkMessageBuffer, networkPartitions,
          networkDroppedMessages, networkDeliveryTime, messages,
          finalizedBlocks, finalizedBySlot, failureStates, nonceCounter,
          latencyMetrics, bandwidthMetrics>>

\* Instance submodules with proper parameter mappings
Votor == INSTANCE Votor WITH
    Validators <- Validators,
    ByzantineValidators <- ByzantineValidators,
    OfflineValidators <- OfflineValidators,
    MaxView <- MaxView,
    MaxSlot <- MaxSlot,
    GST <- GST,
    Delta <- Delta,
    votorView <- votorView,
    votorVotes <- votorVotes,
    votorTimeouts <- votorTimeouts,
    votorGeneratedCerts <- votorGeneratedCerts,
    votorFinalizedChain <- votorFinalizedChain,
    votorState <- votorState,
    votorObservedCerts <- votorObservedCerts,
    clock <- clock

Rotor == INSTANCE Rotor WITH
    Validators <- Validators,
    Stake <- StakeMapping,
    ByzantineValidators <- ByzantineValidators,
    K <- K,
    N <- N,
    MaxBlocks <- 100,
    BandwidthLimit <- BandwidthLimit,
    RetryTimeout <- 10,
    MaxRetries <- MaxRetries,
    HighLatencyThreshold <- 1000,
    LowLatencyThreshold <- 100,
    LoadBalanceTolerance <- 2,
    MaxBufferSize <- 1000,
    rotorBlocks <- rotorBlocks,
    rotorShreds <- rotorShreds,
    rotorReceivedShreds <- rotorReceivedShreds,
    rotorReconstructedBlocks <- rotorReconstructedBlocks,
    blockShreds <- blockShreds,
    relayAssignments <- relayAssignments,
    reconstructionState <- reconstructionState,
    deliveredBlocks <- deliveredBlocks,
    repairRequests <- repairRequests,
    bandwidthUsage <- bandwidthUsage,
    receivedShreds <- receivedShreds,
    shredAssignments <- shredAssignments,
    reconstructedBlocks <- reconstructedBlocks,
    rotorHistory <- rotorHistory,
    clock <- clock

NW == INSTANCE Network WITH
    Validators <- Validators,
    messageQueue <- networkMessageQueue,
    messageBuffer <- networkMessageBuffer,
    networkPartitions <- networkPartitions,
    droppedMessages <- networkDroppedMessages,
    deliveryTime <- networkDeliveryTime,
    clock <- clock,
    MaxBufferSize <- 1000,
    PartitionTimeout <- 100

\* Symmetry permutations for model checking optimization
\* Only permute honest validators to preserve Byzantine behavior
SymPerms ==
    LET honestValidators == Validators \ (ByzantineValidators \cup OfflineValidators)
    IN Types!PermutationsCustom(honestValidators)

----------------------------------------------------------------------------
(* Type Invariants *)

TypeOK ==
    /\ clock \in Nat
    /\ currentSlot \in 1..MaxSlot
    /\ Votor!TypeInvariant  \* From Votor module
    /\ Rotor!TypeInvariant  \* From Rotor module
    /\ finalizedBlocks \in [1..MaxSlot -> SUBSET Types!Block]
    /\ finalizedBySlot \in [1..MaxSlot -> SUBSET Types!Block]
    /\ failureStates \in [Validators -> {"active", "byzantine", "offline"}]
    /\ messages \in SUBSET Types!NetworkMessage
    /\ bandwidthMetrics \in [Validators -> Nat]
    /\ latencyMetrics \in [1..MaxSlot -> Nat]
    /\ nonceCounter \in Nat

\* Integration invariants between modules
VotorRotorIntegration ==
    \* Blocks available for voting must come from Rotor delivery
    \A v \in Validators :
        \A vote \in votorVotes[v] :
            \E slot \in DOMAIN rotorReconstructedBlocks[v] :
                \E block \in rotorReconstructedBlocks[v][slot] :
                    vote.block_hash = block.hash

\* Delivered blocks consistency with reconstruction
DeliveredBlocksConsistency ==
    deliveredBlocks = UNION {Range(rotorReconstructedBlocks[v]) : v \in Validators}
    WHERE Range(f) == {f[x] : x \in DOMAIN f}

----------------------------------------------------------------------------
(* Initial State *)

Init ==
    /\ clock = 0
    /\ currentSlot = 1
    \* Initialize using submodule Init predicates
    /\ Votor!Init
    /\ Rotor!Init
    \* Additional state initialization
    /\ finalizedBlocks = [slot \in 1..MaxSlot |-> {}]
    /\ finalizedBySlot = [slot \in 1..MaxSlot |-> {}]
    /\ messages = {}
    /\ failureStates = [v \in Validators |-> "active"]
    /\ nonceCounter = 0
    /\ latencyMetrics = [slot \in 1..MaxSlot |-> 0]
    /\ bandwidthMetrics = [v \in Validators |-> 0]
    \* Network state initialization
    /\ networkMessageQueue = {}
    /\ networkMessageBuffer = [v \in Validators |-> {}]
    /\ networkPartitions = {}
    /\ networkDroppedMessages = 0
    /\ networkDeliveryTime = [msg \in {} |-> 0]

----------------------------------------------------------------------------
(* Timing Functions *)

\* Slot timing
SlotDuration == 150  \* milliseconds

\* Current time helper
CurrentTime == clock

\* Compute current slot from clock
ComputeSlot(t) == t \div SlotDuration + 1

\* Check if in sync period
InSyncPeriod == clock >= GST

----------------------------------------------------------------------------
(* Helper Functions *)

\* Advance global clock
AdvanceClock ==
    /\ clock' = clock + 1
    /\ UNCHANGED <<currentSlot, currentRotor, votorView, votorVotedBlocks, votorReceivedVotes,
                   votorGeneratedCerts, votorFinalizedChain, votorTimeoutExpiry,
                   votorSkipVotes, finalizedBlocks, finalizedBySlot,
                   rotorBlockShreds, rotorRelayAssignments,
                   rotorReconstructionState, rotorDeliveredBlocks,
                   rotorRepairRequests, rotorBandwidthUsage,
                   rotorReceivedShreds, rotorReconstructedBlocks, rotorShredAssignments,
                   deliveredBlocks, failureStates,
                   networkMessageQueue, networkMessageBuffer, networkPartitions,
                   networkDroppedMessages, networkDeliveryTime, messages,
                   latencyMetrics, bandwidthMetrics>>

\* Advance view on timeout (per-validator) with Rotor integration
AdvanceView(v) ==
    /\ v \in Validators
    /\ votorView[v] < MaxView
    /\ Votor!TimeoutExpired(v, currentSlot)
    /\ \* Check if block delivery failed - if no block delivered for current slot, advance view
       LET currentDelivered == UNION {Range(rotorReconstructedBlocks[val]) : val \in Validators}
       IN ~(\E b \in currentDelivered : b.slot = currentSlot)
    /\ votorView' = [votorView EXCEPT ![v] = votorView[v] + 1]
    /\ Votor!SetTimeout(v, currentSlot, clock + Types!SlotDuration * (2 ^ votorView'[v]))
    /\ UNCHANGED <<clock, currentSlot, votorVotes, votorGeneratedCerts, votorFinalizedChain,
                   votorState, votorObservedCerts, finalizedBlocks, finalizedBySlot,
                   rotorBlocks, rotorShreds, rotorReceivedShreds, rotorReconstructedBlocks,
                   blockShreds, relayAssignments, reconstructionState, deliveredBlocks,
                   repairRequests, bandwidthUsage, receivedShreds, shredAssignments,
                   reconstructedBlocks, rotorHistory, networkMessageQueue, networkMessageBuffer,
                   networkPartitions, networkDroppedMessages, networkDeliveryTime, messages,
                   failureStates, nonceCounter, latencyMetrics, bandwidthMetrics>>

\* Helper function for sequence range
Range(f) == {f[x] : x \in DOMAIN f}

\* Advance to next slot when current slot is finalized
AdvanceSlot ==
    /\ \E b \in finalizedBlocks[currentSlot] : TRUE  \* Slot has finalized block
    /\ currentSlot < MaxSlot
    /\ currentSlot' = currentSlot + 1
    /\ UNCHANGED <<clock, currentRotor, votorView, votorVotedBlocks, votorReceivedVotes,
                   votorGeneratedCerts, votorFinalizedChain, votorTimeoutExpiry,
                   votorSkipVotes, finalizedBlocks,
                   finalizedBySlot, rotorBlockShreds, rotorShredAssignments,
                   rotorReceivedShreds, rotorReconstructedBlocks,
                   rotorRelayAssignments, rotorRepairRequests,
                   networkMessageBuffer, networkPartitions,
                   networkDroppedMessages, messages, latencyMetrics,
                   bandwidthMetrics>>

\* Generate certificate when sufficient votes collected
GenerateCertificate(block, voteSet) ==
    LET voteValidators == {vote.validator : vote \in voteSet}
        totalVoteStake == Utils!Sum([v \in voteValidators |-> Stake[v]])
        totalStake == Utils!Sum([v \in Validators |-> Stake[v]])
        fastPathStake == (4 * totalStake) \div 5  \* 80% for fast path
        slowPathStake == (3 * totalStake) \div 5  \* 60% for slow path
        \* Use deterministic leader selection based on minimum view
        minView == CHOOSE view \in {votorView[val] : val \in Validators} :
                   \A otherView \in {votorView[val] : val \in Validators} : view <= otherView
        leader == Types!ComputeLeader(minView, Validators, StakeMapping)  \* Deterministic view-based leader
        blockHash == block.hash
    IN
    /\ totalVoteStake >= slowPathStake  \* At least slow path threshold
    /\ \E v \in Validators :
        votorGeneratedCerts' = [votorGeneratedCerts EXCEPT ![votorView[v]] =
            votorGeneratedCerts[votorView[v]] \cup
        {[type |-> IF totalVoteStake >= fastPathStake THEN "fast" ELSE "slow",
          block |-> blockHash,
          votes |-> voteSet,
          stake |-> totalVoteStake,
          timestamp |-> clock,
          slot |-> block.slot]}]
    /\ UNCHANGED <<clock, currentSlot, currentRotor, votorView, votorVotedBlocks, votorReceivedVotes,
                   votorFinalizedChain, votorTimeoutExpiry,
                   votorSkipVotes, finalizedBlocks, finalizedBySlot,
                   rotorBlockShreds, rotorShredAssignments, rotorReceivedShreds,
                   rotorReconstructedBlocks, rotorRelayAssignments, rotorRepairRequests,
                   rotorBandwidthUsage, deliveredBlocks, networkMessageQueue, networkMessageBuffer,
                   networkPartitions, networkDroppedMessages, messages,
                   latencyMetrics, bandwidthMetrics>>

\* Votor consensus actions - delegate to Votor module
VotorAction ==
    \/ \E v \in Validators, slot \in 1..MaxSlot, block \in Types!Block :
        /\ Votor!CastNotarVote(v, slot, block)
        /\ UNCHANGED <<clock, currentSlot, finalizedBlocks, finalizedBySlot,
                       rotorBlocks, rotorShreds, rotorReceivedShreds, rotorReconstructedBlocks,
                       blockShreds, relayAssignments, reconstructionState, deliveredBlocks,
                       repairRequests, bandwidthUsage, receivedShreds, shredAssignments,
                       reconstructedBlocks, rotorHistory, networkMessageQueue, networkMessageBuffer,
                       networkPartitions, networkDroppedMessages, networkDeliveryTime, messages,
                       failureStates, nonceCounter, latencyMetrics, bandwidthMetrics>>
    \/ \E v \in Validators, slot \in 1..MaxSlot, reason \in STRING :
        /\ Votor!CastSkipVote(v, slot, reason)
        /\ UNCHANGED <<clock, currentSlot, finalizedBlocks, finalizedBySlot,
                       rotorBlocks, rotorShreds, rotorReceivedShreds, rotorReconstructedBlocks,
                       blockShreds, relayAssignments, reconstructionState, deliveredBlocks,
                       repairRequests, bandwidthUsage, receivedShreds, shredAssignments,
                       reconstructedBlocks, rotorHistory, networkMessageQueue, networkMessageBuffer,
                       networkPartitions, networkDroppedMessages, networkDeliveryTime, messages,
                       failureStates, nonceCounter, latencyMetrics, bandwidthMetrics>>
    \/ \E v \in Validators, slot \in 1..MaxSlot, block \in Types!Block :
        /\ Votor!CastFinalizationVote(v, slot, block)
        /\ UNCHANGED <<clock, currentSlot, finalizedBlocks, finalizedBySlot,
                       rotorBlocks, rotorShreds, rotorReceivedShreds, rotorReconstructedBlocks,
                       blockShreds, relayAssignments, reconstructionState, deliveredBlocks,
                       repairRequests, bandwidthUsage, receivedShreds, shredAssignments,
                       reconstructedBlocks, rotorHistory, networkMessageQueue, networkMessageBuffer,
                       networkPartitions, networkDroppedMessages, networkDeliveryTime, messages,
                       failureStates, nonceCounter, latencyMetrics, bandwidthMetrics>>
    \/ \E v \in Validators, slot \in 1..MaxSlot, block \in Types!Block, cert \in Types!Certificate :
        /\ Votor!FinalizeBlock(v, slot, block, cert)
        /\ finalizedBlocks' = [finalizedBlocks EXCEPT ![slot] = finalizedBlocks[slot] \cup {block}]
        /\ finalizedBySlot' = [finalizedBySlot EXCEPT ![slot] = {block}]
        /\ latencyMetrics' = [latencyMetrics EXCEPT ![slot] =
                             IF block.timestamp > 0 THEN clock - block.timestamp ELSE 0]
        /\ UNCHANGED <<clock, currentSlot, votorView, votorVotes, votorTimeouts,
                       votorGeneratedCerts, votorFinalizedChain, votorState, votorObservedCerts,
                       rotorBlocks, rotorShreds, rotorReceivedShreds, rotorReconstructedBlocks,
                       blockShreds, relayAssignments, reconstructionState, deliveredBlocks,
                       repairRequests, bandwidthUsage, receivedShreds, shredAssignments,
                       reconstructedBlocks, rotorHistory, networkMessageQueue, networkMessageBuffer,
                       networkPartitions, networkDroppedMessages, networkDeliveryTime, messages,
                       failureStates, nonceCounter, bandwidthMetrics>>
    \/ Votor!GenerateCertificates
        /\ UNCHANGED <<clock, currentSlot, finalizedBlocks, finalizedBySlot,
                       rotorBlocks, rotorShreds, rotorReceivedShreds, rotorReconstructedBlocks,
                       blockShreds, relayAssignments, reconstructionState, deliveredBlocks,
                       repairRequests, bandwidthUsage, receivedShreds, shredAssignments,
                       reconstructedBlocks, rotorHistory, networkMessageQueue, networkMessageBuffer,
                       networkPartitions, networkDroppedMessages, networkDeliveryTime, messages,
                       failureStates, nonceCounter, latencyMetrics, bandwidthMetrics>>

\* Rotor propagation actions - delegate to Rotor module
RotorAction ==
    \/ \E leader \in Validators, slot \in Nat, block \in Types!Block :
        /\ Rotor!ProposeBlock(leader, slot, block)
        /\ UNCHANGED <<clock, currentSlot, votorView, votorVotes, votorTimeouts,
                       votorGeneratedCerts, votorFinalizedChain, votorState, votorObservedCerts,
                       finalizedBlocks, finalizedBySlot, networkMessageQueue, networkMessageBuffer,
                       networkPartitions, networkDroppedMessages, networkDeliveryTime, messages,
                       failureStates, nonceCounter, latencyMetrics, bandwidthMetrics>>
    \/ \E block \in Types!Block :
        /\ Rotor!ShredBlock(block)
        /\ UNCHANGED <<clock, currentSlot, votorView, votorVotes, votorTimeouts,
                       votorGeneratedCerts, votorFinalizedChain, votorState, votorObservedCerts,
                       finalizedBlocks, finalizedBySlot, networkMessageQueue, networkMessageBuffer,
                       networkPartitions, networkDroppedMessages, networkDeliveryTime, messages,
                       failureStates, nonceCounter, latencyMetrics, bandwidthMetrics>>
    \/ \E v \in Validators, slot \in Nat, shreds \in SUBSET Types!ErasureCodedPiece :
        /\ Rotor!ReconstructBlock(v, slot, shreds)
        /\ UNCHANGED <<clock, currentSlot, votorView, votorVotes, votorTimeouts,
                       votorGeneratedCerts, votorFinalizedChain, votorState, votorObservedCerts,
                       finalizedBlocks, finalizedBySlot, networkMessageQueue, networkMessageBuffer,
                       networkPartitions, networkDroppedMessages, networkDeliveryTime, messages,
                       failureStates, nonceCounter, latencyMetrics, bandwidthMetrics>>
    \/ \E leader \in Validators, blockId \in Nat :
        /\ Rotor!ShredAndDistribute(leader, [hash |-> blockId, slot |-> currentSlot,
                                            proposer |-> leader, view |-> 0, parent |-> 0,
                                            data |-> "test", timestamp |-> clock, transactions |-> {}])
        /\ UNCHANGED <<clock, currentSlot, votorView, votorVotes, votorTimeouts,
                       votorGeneratedCerts, votorFinalizedChain, votorState, votorObservedCerts,
                       finalizedBlocks, finalizedBySlot, networkMessageQueue, networkMessageBuffer,
                       networkPartitions, networkDroppedMessages, networkDeliveryTime, messages,
                       failureStates, nonceCounter, latencyMetrics, bandwidthMetrics>>

\* Send message through network
SendMessage(msg) ==
    /\ networkMessageQueue' = networkMessageQueue \cup {msg}
    /\ messages' = messages \cup {msg}
    /\ UNCHANGED <<clock, currentRotor, currentSlot, votorView, votorVotedBlocks, votorReceivedVotes,
                   votorGeneratedCerts, votorFinalizedChain, votorTimeoutExpiry,
                   votorSkipVotes, finalizedBlocks, finalizedBySlot,
                   rotorBlockShreds, rotorRelayAssignments,
                   rotorReconstructionState, rotorDeliveredBlocks, rotorRepairRequests,
                   rotorBandwidthUsage, deliveredBlocks, networkMessageBuffer, networkPartitions,
                   networkDroppedMessages, latencyMetrics, bandwidthMetrics>>

\* Broadcast message to all validators
BroadcastMessage(sender, msgType, content) ==
    LET msg == [type |-> msgType,
                sender |-> sender,
                recipient |-> "broadcast",
                payload |-> content,
                timestamp |-> clock,
                signature |-> [signer |-> sender, message |-> 0, valid |-> TRUE]]
    IN SendMessage(msg)

\* Network actions
NetworkAction ==
    \/ /\ NW!DeliverMessage
       /\ UNCHANGED <<currentRotor, currentSlot, votorView, votorVotedBlocks, votorReceivedVotes,
                      votorGeneratedCerts, votorFinalizedChain, votorTimeoutExpiry,
                      votorSkipVotes, finalizedBlocks, finalizedBySlot,
                      rotorBlockShreds, rotorRelayAssignments,
                      rotorReconstructionState, rotorDeliveredBlocks, rotorRepairRequests,
                      rotorBandwidthUsage, rotorShredAssignments, rotorReceivedShreds,
                      rotorReconstructedBlocks, deliveredBlocks, failureStates,
                      messages, latencyMetrics, bandwidthMetrics>>
    \/ /\ NW!DropMessage
       /\ UNCHANGED <<currentRotor, currentSlot, votorView, votorVotedBlocks, votorReceivedVotes,
                      votorGeneratedCerts, votorFinalizedChain, votorTimeoutExpiry,
                      votorSkipVotes, finalizedBlocks, finalizedBySlot,
                      rotorBlockShreds, rotorRelayAssignments,
                      rotorReconstructionState, rotorDeliveredBlocks, rotorRepairRequests,
                      rotorBandwidthUsage, rotorShredAssignments, rotorReceivedShreds,
                      rotorReconstructedBlocks, deliveredBlocks, failureStates,
                      messages, latencyMetrics, bandwidthMetrics>>
    \/ /\ NW!PartitionNetwork
       /\ UNCHANGED <<currentRotor, currentSlot, votorView, votorVotedBlocks, votorReceivedVotes,
                      votorGeneratedCerts, votorFinalizedChain, votorTimeoutExpiry,
                      votorSkipVotes, finalizedBlocks, finalizedBySlot,
                      rotorBlockShreds, rotorRelayAssignments,
                      rotorReconstructionState, rotorDeliveredBlocks, rotorRepairRequests,
                      rotorBandwidthUsage, rotorShredAssignments, rotorReceivedShreds,
                      rotorReconstructedBlocks, deliveredBlocks, failureStates,
                      messages, latencyMetrics, bandwidthMetrics>>
    \/ /\ NW!HealPartition
       /\ UNCHANGED <<currentRotor, currentSlot, votorView, votorVotedBlocks, votorReceivedVotes,
                      votorGeneratedCerts, votorFinalizedChain, votorTimeoutExpiry,
                      votorSkipVotes, finalizedBlocks, finalizedBySlot,
                      rotorBlockShreds, rotorRelayAssignments,
                      rotorReconstructionState, rotorDeliveredBlocks, rotorRepairRequests,
                      rotorBandwidthUsage, rotorShredAssignments, rotorReceivedShreds,
                      rotorReconstructedBlocks, deliveredBlocks, failureStates,
                      messages, latencyMetrics, bandwidthMetrics>>

\* Byzantine double voting behavior
ByzantineDoubleVote(v) ==
    \* Byzantine validator votes for multiple blocks in same view
    /\ v \in ByzantineValidators
    /\ \E b1, b2 \in Types!Block :
        /\ b1 # b2
        /\ b1.slot = currentSlot
        /\ b2.slot = currentSlot
        /\ Votor!CastVote(v, b1, votorView[v])
        /\ Votor!CastVote(v, b2, votorView[v])
        \* Byzantine votes are handled through Votor module
        /\ UNCHANGED <<clock, currentRotor, currentSlot, votorView, votorVotedBlocks,
                       votorReceivedVotes, votorGeneratedCerts, votorFinalizedChain,
                       votorTimeoutExpiry, votorSkipVotes,
                       finalizedBlocks, finalizedBySlot, rotorBlockShreds,
                       rotorShredAssignments, rotorReceivedShreds,
                       rotorReconstructedBlocks, rotorRelayAssignments,
                       rotorReconstructionState, rotorDeliveredBlocks,
                       rotorRepairRequests, rotorBandwidthUsage,
                       deliveredBlocks, networkMessageQueue, networkMessageBuffer,
                       networkPartitions, networkDroppedMessages, messages,
                       latencyMetrics, bandwidthMetrics>>

\* Byzantine invalid block proposal
ByzantineInvalidBlock(v) ==
    /\ v \in ByzantineValidators
    /\ v = Types!ComputeLeader(votorView[v], Validators, StakeMapping)  \* View-based leader check
    /\ LET invalidBlock == [slot |-> currentSlot,
                            hash |-> "invalid_block",
                            parent |-> "null",
                            timestamp |-> clock,
                            transactions |-> {}]
       IN Votor!ProposeBlock(v, votorView[v])  \* Propose invalid block

\* Byzantine withholding shreds
ByzantineWithholdShreds(v) ==
    /\ v \in ByzantineValidators
    /\ v \in DOMAIN rotorShredAssignments
    /\ rotorShredAssignments[v] # {}
    /\ UNCHANGED vars  \* Do nothing, withholding shreds

\* Byzantine equivocation
ByzantineEquivocate(v) ==
    /\ v \in ByzantineValidators
    /\ LET msg1 == [type |-> "vote",
                    sender |-> v,
                    recipient |-> "broadcast",
                    payload |-> "fake_vote_1",
                    timestamp |-> clock,
                    signature |-> [signer |-> v, message |-> 1, valid |-> FALSE]]
           msg2 == [type |-> "vote",
                    sender |-> v,
                    recipient |-> "broadcast",
                    payload |-> "fake_vote_2",
                    timestamp |-> clock,
                    signature |-> [signer |-> v, message |-> 2, valid |-> FALSE]]
       IN
       /\ SendMessage(msg1)
       /\ SendMessage(msg2)

\* Byzantine validator actions
ByzantineAction ==
    \E v \in ByzantineValidators :
        \/ ByzantineDoubleVote(v)
        \/ ByzantineInvalidBlock(v)
        \/ ByzantineWithholdShreds(v)
        \/ ByzantineEquivocate(v)

Next ==
    \/ AdvanceClock
    \/ AdvanceSlot
    \/ \E v \in Validators : AdvanceView(v)
    \/ VotorAction
    \/ RotorAction
    \/ NetworkAction
    \/ ByzantineAction
    \/ Votor!AdvanceClock
    \/ Rotor!Next

Spec == Init /\ [][Next]_vars /\ WF_vars(AdvanceClock) /\ WF_vars(AdvanceSlot) /\ WF_vars(Votor!Next) /\ WF_vars(Rotor!Next)

----------------------------------------------------------------------------
(* Safety Properties *)

\* Import safety properties from Votor module
Safety == Votor!SafetyInvariant

\* Certificate uniqueness per slot
CertificateUniqueness == Votor!ValidCertificateThresholds

\* Chain consistency across honest validators
ChainConsistency == Votor!ChainConsistencyInvariant

\* Consistent finalization
ConsistentFinalization ==
    \A slot \in 1..MaxSlot :
        Cardinality(finalizedBlocks[slot]) <= 1

\* Rotor non-equivocation
RotorNonEquivocation == Rotor!RotorNonEquivocation

----------------------------------------------------------------------------
(* Liveness Properties *)

\* Import liveness properties from Votor module
Progress == Votor!LivenessProperty

\* Fast path completion with high participation
FastPath ==
    LET ResponsiveStake == Utils!TotalStake(HonestValidators \ OfflineValidators, StakeMapping)
        totalStake == Utils!TotalStake(Validators, StakeMapping)
    IN
    /\ ResponsiveStake >= (4 * totalStake) \div 5  \* >=80% responsive
    /\ clock > GST
    => <>(\E vw \in 1..MaxView : \E cert \in votorGeneratedCerts[vw] : cert.type = "fast" /\ cert.slot = currentSlot)

\* Bounded finalization time
BoundedFinalization ==
    LET ResponsiveStake == Utils!TotalStake(HonestValidators \ OfflineValidators, StakeMapping)
        totalStake == Utils!TotalStake(Validators, StakeMapping)
        FinalizationBound == IF ResponsiveStake >= (4 * totalStake) \div 5
                             THEN Delta  \* Fast path bound
                             ELSE 2 * Delta  \* Slow path bound
    IN
    /\ clock > GST
    => [](clock <= GST + FinalizationBound =>
          \E b \in finalizedBlocks[currentSlot] : TRUE)

\* Block delivery guarantee from Rotor
BlockDeliveryGuarantee == Rotor!BlockDeliveryGuarantee

----------------------------------------------------------------------------
(* Resilience Properties *)

\* Import resilience properties from Votor module
ByzantineResilience == Votor!ByzantineResilienceProperty

\* Maintain liveness under maximum offline faults
OfflineResilience ==
    LET OfflineStake == Utils!TotalStake(OfflineValidators, StakeMapping)
        totalStake == Utils!TotalStake(Validators, StakeMapping)
    IN
    /\ OfflineStake <= totalStake \div 5
    /\ clock > GST
    => <>Progress

\* Recovery after network partition
PartitionRecovery ==
    /\ networkPartitions = {}  \* No active partitions
    /\ clock > GST + Delta
    => <>(\E b \in finalizedBlocks[currentSlot] : TRUE)

\* Combined "20+20" resilience
Combined2020Resilience ==
    LET ByzantineStake == Utils!TotalStake(ByzantineValidators, StakeMapping)
        OfflineStake == Utils!TotalStake(OfflineValidators, StakeMapping)
        totalStake == Utils!TotalStake(Validators, StakeMapping)
    IN
    /\ ByzantineStake <= totalStake \div 5
    /\ OfflineStake <= totalStake \div 5
    => /\ []Safety
       /\ (clock > GST => <>Progress)

----------------------------------------------------------------------------
(* Integration Properties *)

\* Rotor delivers blocks before Votor timeout with proper integration
RotorVotorIntegration ==
    \A slot \in 1..currentSlot :
        \A v \in HonestValidators :
            \* If a vote exists for a slot, the corresponding block should be available
            (\E vote \in votorVotes[v] : vote.slot = slot) =>
                \* Either the block is delivered through Rotor
                <>(\E s \in DOMAIN rotorReconstructedBlocks[v] :
                    \E b \in rotorReconstructedBlocks[v][s] : b.slot = slot) \/
                \* Or the validator times out and advances view
                <>(Votor!TimeoutExpired(v, slot)) \/
                \* Or the block gets finalized through consensus
                <>(\E cert \in votorGeneratedCerts[votorView[v]] : cert.slot = slot)

\* Bandwidth utilization is stake-proportional
StakeProportionalBandwidth ==
    \A v \in HonestValidators :
        LET ExpectedBandwidth == (StakeMapping[v] * BandwidthLimit * Cardinality(Validators)) \div Utils!TotalStake(Validators, StakeMapping)
        IN bandwidthUsage[v] \in (ExpectedBandwidth * 9) \div 10..(ExpectedBandwidth * 11) \div 10

----------------------------------------------------------------------------
(* Model Checking Constraints *)

\* State space reduction for model checking
StateConstraint ==
    /\ clock <= 100
    /\ currentSlot <= 10
    /\ Cardinality(messages) <= 1000
    /\ Cardinality(deliveredBlocks) <= 50
    /\ \A v \in Validators : votorView[v] <= 5
    /\ \A v \in Validators : bandwidthUsage[v] <= BandwidthLimit * 2

\* Action constraint for model checking
ActionConstraint ==
    /\ currentSlot' <= MaxSlot
    /\ \A v \in Validators : votorView'[v] <= MaxView
    /\ Cardinality(UNION {votorGeneratedCerts[vw] : vw \in 1..MaxView}) <= MaxView * 3

\* Symmetry reduction using SymPerms defined above
Symmetry == SymPerms

\* Fairness conditions to ensure progress
Fairness ==
    /\ WF_vars(AdvanceClock)
    /\ WF_vars(AdvanceSlot)
    /\ \A v \in HonestValidators : WF_vars(AdvanceView(v))
    /\ WF_vars(VotorAction)
    /\ WF_vars(RotorAction)

============================================================================
