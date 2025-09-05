---------------------------- MODULE Alpenglow ----------------------------
(***************************************************************************)
(* Formal specification of the Alpenglow consensus protocol, composing    *)
(* Votor (consensus) and Rotor (propagation) components to achieve        *)
(* 100-150ms finalization times.                                          *)
(***************************************************************************)

EXTENDS Integers, Sequences, FiniteSets, TLC

\* Import helper modules
Utils == INSTANCE Utils
Types == INSTANCE Types
Crypto == INSTANCE Crypto
NetworkIntegration == INSTANCE NetworkIntegration WITH
    TotalStake <- Utils!Sum([v \in Validators |-> Stake[v]]),
    FastPathStake <- (4 * Utils!Sum([v \in Validators |-> Stake[v]])) \div 5,
    SlowPathStake <- (3 * Utils!Sum([v \in Validators |-> Stake[v]])) \div 5

CONSTANTS
    Validators,          \* Set of all validators
    ByzantineValidators, \* Set of Byzantine validators
    OfflineValidators,   \* Set of offline validators
    MaxSlot,             \* Maximum slot number
    MaxView,             \* Maximum view number
    MaxTime,             \* Maximum time value
    GST,                 \* Global Stabilization Time
    Delta,               \* Network delay bound
    InitialLeader,       \* Initial leader for Votor
    K,                   \* Erasure coding data shreds
    N,                   \* Erasure coding total shreds
    MaxBlockSize,        \* Maximum block size
    BandwidthPerValidator, \* Bandwidth per validator
    MaxMessageSize,      \* Maximum message size
    NetworkCapacity,     \* Network capacity
    BandwidthLimit,      \* Bandwidth limit per validator
    TimeoutDelta,        \* Timeout delta for Votor
    MaxRetries           \* Maximum retries for Rotor

ASSUME
    /\ ByzantineValidators \subseteq Validators
    /\ OfflineValidators \subseteq Validators
    /\ ByzantineValidators \cap OfflineValidators = {}
    /\ GST >= 0
    /\ Delta > 0
    /\ N > K  \* Erasure coding constraint
    /\ K > 0

HonestValidators == Validators \ (ByzantineValidators \cup OfflineValidators)

\* Define stake mapping for all validators (equal stake for simplicity)
Stake == [v \in Validators |-> 10]
StakeMapping == Stake

----------------------------------------------------------------------------
(* System State Variables *)

VARIABLES
    \* Time and scheduling
    clock,               \* Current global time
    currentSlot,         \* Current protocol slot
    currentRotor,        \* Current rotor/leader used by propagation

    \* Votor consensus state (mapped from submodule)
    votorView,           \* View number for each validator
    votorVotedBlocks,    \* Blocks voted by each validator
    votorGeneratedCerts, \* Certificates generated
    votorFinalizedChain, \* Finalized blockchain
    votorSkipVotes,      \* Skip votes for view changes
    votorTimeoutExpiry,  \* Timeout expiry times
    votorReceivedVotes,  \* Votes received by validators
    \* certificates removed - use votorGeneratedCerts from Votor
    finalizedBlocks,     \* Finalized blocks per slot
    finalizedBySlot,     \* Derived mapping slot -> block

    \* Rotor propagation state (mapped from submodule)
    rotorBlockShreds,
    rotorRelayAssignments,
    rotorReconstructionState,
    rotorDeliveredBlocks,
    rotorRepairRequests,
    rotorBandwidthUsage,
    rotorShredAssignments,    \* Shred assignment mapping
    rotorReceivedShreds,       \* Received shreds per validator
    rotorReconstructedBlocks,  \* Reconstructed blocks from shreds

    \* Additional propagation state
    deliveredBlocks,     \* Global set of blocks that have been fully reconstructed from shreds
                         \* This is the union of all validators' reconstructedBlocks from Rotor
                         \* Used to track which blocks are available for voting/finalization

    \* Network state (mapped from submodule)
    networkMessageQueue,
    networkMessageBuffer,
    networkPartitions,   \* Set of network partitions
    networkDroppedMessages,
    networkDeliveryTime, \* Message delivery time mapping

    \* Additional network state
    messages,            \* In-flight messages (as a set)

    \* Failure state tracking
    failureStates,       \* Validator failure states

    \* Cryptographic state
    nonceCounter,        \* Counter for generating unique nonces (from Crypto module)

    \* Metrics
    latencyMetrics,      \* Finalization latencies
    bandwidthMetrics     \* Bandwidth consumption

vars == <<clock, currentSlot, currentRotor, votorView, votorVotedBlocks, votorGeneratedCerts,
          votorFinalizedChain, votorSkipVotes, votorTimeoutExpiry, votorReceivedVotes,
          finalizedBlocks, finalizedBySlot,
          rotorBlockShreds, rotorRelayAssignments, rotorReconstructionState, rotorDeliveredBlocks,
          rotorRepairRequests, rotorBandwidthUsage, rotorShredAssignments, rotorReceivedShreds,
          rotorReconstructedBlocks, deliveredBlocks, networkMessageQueue, networkMessageBuffer,
          networkPartitions, networkDroppedMessages, networkDeliveryTime, messages,
          failureStates, nonceCounter, latencyMetrics, bandwidthMetrics>>

\* Instance submodules with parameter mappings (after variables are declared)
Votor == INSTANCE Votor WITH
    Stake <- StakeMapping,
    InitialLeader <- InitialLeader,
    view <- votorView,
    votedBlocks <- votorVotedBlocks,
    generatedCerts <- votorGeneratedCerts,
    finalizedChain <- votorFinalizedChain,
    TimeoutDelta <- TimeoutDelta,
    skipVotes <- votorSkipVotes,
    timeoutExpiry <- votorTimeoutExpiry,
    receivedVotes <- votorReceivedVotes,
    currentTime <- clock

Rotor == INSTANCE Rotor WITH
    Stake <- StakeMapping,
    MaxRetries <- MaxRetries,
    blockShreds <- rotorBlockShreds,
    relayAssignments <- rotorRelayAssignments,
    reconstructionState <- rotorReconstructionState,
    deliveredBlocks <- rotorDeliveredBlocks,
    repairRequests <- rotorRepairRequests,
    bandwidthUsage <- rotorBandwidthUsage,
    receivedShreds <- rotorReceivedShreds,
    shredAssignments <- rotorShredAssignments,
    reconstructedBlocks <- rotorReconstructedBlocks,
    RetryTimeout <- 10,
    LowLatencyThreshold <- 100,
    HighLatencyThreshold <- 1000,
    MaxBufferSize <- 1000,
    LoadBalanceTolerance <- 2,
    MaxBlocks <- 100

NW == INSTANCE Network WITH
    Stake <- StakeMapping,
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
    /\ currentRotor \in Validators
    /\ votorView \in [Validators -> 1..MaxView]
    /\ Votor!TypeInvariant  \* From Votor
    /\ Rotor!TypeInvariant  \* From Rotor
    /\ NW!NetworkTypeOK   \* From Network
    /\ votorGeneratedCerts \in [1..MaxView -> SUBSET Types!Certificate]
    /\ finalizedBlocks \in [1..MaxSlot -> SUBSET Types!Block]
    /\ finalizedBySlot \in [1..MaxSlot -> SUBSET Types!Block]
    /\ failureStates \in [Validators -> {"active", "byzantine", "offline"}]
    /\ deliveredBlocks \in SUBSET Types!Block  \* Set of delivered blocks
    /\ messages \in SUBSET Types!NetworkMessage  \* Standardized as set type
    /\ bandwidthMetrics \in [Validators -> Nat]

\* Consistency invariant: deliveredBlocks is derived from Rotor's reconstructedBlocks
\* deliveredBlocks represents the global view of all blocks that have been successfully
\* reconstructed by any validator in the network from received shreds
DeliveredBlocksConsistency ==
    deliveredBlocks = UNION {rotorReconstructedBlocks[v] : v \in Validators}

\* Invariant: All delivered blocks must have been properly reconstructed
\* Every block in deliveredBlocks must have been reconstructed by at least one validator
\* This ensures blocks aren't added to deliveredBlocks without going through proper shred reconstruction
DeliveredBlocksValidity ==
    \A b \in deliveredBlocks :
        \E v \in Validators : b \in rotorReconstructedBlocks[v]

\* Invariant: Delivered blocks must correspond to actual block IDs in Rotor
\* Each delivered block must have a corresponding blockId that was marked as delivered
\* in at least one validator's rotorDeliveredBlocks set, ensuring proper tracking
DeliveredBlocksCorrespondence ==
    \A b \in deliveredBlocks :
        \E blockId \in DOMAIN rotorBlockShreds :
            blockId \in rotorDeliveredBlocks[CHOOSE v \in Validators : b \in rotorReconstructedBlocks[v]]

----------------------------------------------------------------------------
(* Initial State *)

Init ==
    /\ clock = 0
    /\ currentSlot = 1
    /\ currentRotor = InitialLeader
    \* Votor state initialization
    /\ votorView = [v \in Validators |-> 1]
    /\ votorVotedBlocks = [v \in Validators |-> [vw \in 1..MaxView |-> {}]]
    /\ votorFinalizedChain = [v \in Validators |-> <<>>]
    /\ votorSkipVotes = [v \in Validators |-> [vw \in 1..MaxView |-> {}]]
    /\ votorTimeoutExpiry = [v \in Validators |-> TimeoutDelta]
    /\ votorReceivedVotes = [v \in Validators |-> [vw \in 1..MaxView |-> {}]]
    /\ votorGeneratedCerts = [vw \in 1..MaxView |-> {}]
    \* Rotor state initialization
    /\ rotorBlockShreds = [b \in {} |-> {}]  \* Empty initially
    /\ rotorRelayAssignments = [v \in Validators |-> {}]
    /\ rotorReconstructionState = [v \in Validators |-> [b \in {} |-> 0]]
    /\ rotorDeliveredBlocks = {}
    /\ rotorRepairRequests = [v \in Validators |-> {}]
    /\ rotorBandwidthUsage = [v \in Validators |-> 0]
    /\ rotorShredAssignments = [v \in Validators |-> {}]
    /\ rotorReceivedShreds = [v \in Validators |-> {}]
    /\ rotorReconstructedBlocks = [v \in Validators |-> {}]
    \* Network state initialization
    /\ networkMessageQueue = {}
    /\ networkMessageBuffer = [v \in Validators |-> {}]
    /\ networkPartitions = {}
    /\ networkDroppedMessages = 0
    /\ networkDeliveryTime = <<>>  \* Empty function
    \* Additional state
    /\ finalizedBlocks = [slot \in 1..MaxSlot |-> {}]
    /\ finalizedBySlot = [slot \in 1..MaxSlot |-> {}]  \* Changed from <<>> to {} for proper type
    /\ deliveredBlocks = {}  \* Initially no blocks delivered
    /\ messages = {}
    /\ failureStates = [v \in Validators |-> "active"]
    /\ nonceCounter = 0  \* Initialize cryptographic nonce counter
    /\ latencyMetrics = [slot \in 1..MaxSlot |-> 0]
    /\ bandwidthMetrics = [v \in Validators |-> 0]

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
    /\ votorView[v] < MaxView
    /\ clock >= votorTimeoutExpiry[v]  \* Timeout expired for validator v
    /\ \* Check if block delivery failed - if no block delivered for current slot, advance view
       LET currentDelivered == UNION {rotorReconstructedBlocks[val] : val \in Validators}
       IN ~(\E b \in currentDelivered : b.slot = currentSlot)
    /\ votorView' = [votorView EXCEPT ![v] = votorView[v] + 1]
    /\ votorTimeoutExpiry' = [votorTimeoutExpiry EXCEPT ![v] = clock + TimeoutDelta * (2 ^ votorView'[v]) * Utils!Min(2 ^ votorView'[v], 2^10)]  \* Exponential backoff with cap
    /\ votorSkipVotes' = [votorSkipVotes EXCEPT ![v] = [votorSkipVotes[v] EXCEPT ![votorView'[v]] = {}]]  \* Reset skip votes for new view
    /\ UNCHANGED <<clock, currentSlot, currentRotor, votorVotedBlocks, votorReceivedVotes,
                   votorGeneratedCerts, votorFinalizedChain,
                   finalizedBlocks, finalizedBySlot, rotorBlockShreds, rotorShredAssignments,
                   rotorReceivedShreds, rotorReconstructedBlocks, rotorRelayAssignments,
                   rotorReconstructionState, rotorDeliveredBlocks,
                   rotorRepairRequests, rotorBandwidthUsage, deliveredBlocks, networkMessageQueue,
                   networkMessageBuffer, networkPartitions, networkDroppedMessages, messages,
                   latencyMetrics, bandwidthMetrics>>

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
        leader == Types!ComputeLeader(votorView[CHOOSE v \in Validators : TRUE], Validators, StakeMapping)  \* View-based leader
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

\* Votor consensus actions
VotorAction ==
    \/ /\ \E v \in Validators :
           /\ v = Types!ComputeLeader(votorView[v], Validators, StakeMapping)  \* View-based leader selection
           /\ Votor!ProposeBlock(v, votorView[v])
       /\ UNCHANGED <<clock, currentRotor, currentSlot, finalizedBlocks, finalizedBySlot,
                      rotorBlockShreds, rotorRelayAssignments,
                      rotorReconstructionState, rotorDeliveredBlocks,
                      rotorRepairRequests, rotorBandwidthUsage,
                      rotorReceivedShreds, rotorReconstructedBlocks, rotorShredAssignments,
                      deliveredBlocks, failureStates,
                      networkMessageQueue, networkMessageBuffer, networkPartitions,
                      networkDroppedMessages, networkDeliveryTime, messages,
                      latencyMetrics, bandwidthMetrics>>
    \/ /\ \E v \in Validators, slot \in 1..MaxSlot :
           /\ slot = votorView[v]
           /\ votorVotedBlocks[v][slot] # {}
           /\ \E b \in votorVotedBlocks[v][slot] :
               Votor!CastVote(v, b, slot)
       /\ UNCHANGED <<clock, currentRotor, currentSlot, finalizedBlocks, finalizedBySlot,
                      rotorBlockShreds, rotorRelayAssignments,
                      rotorReconstructionState, rotorDeliveredBlocks,
                      rotorRepairRequests, rotorBandwidthUsage,
                      rotorReceivedShreds, rotorReconstructedBlocks, rotorShredAssignments,
                      deliveredBlocks, failureStates,
                      networkMessageQueue, networkMessageBuffer, networkPartitions,
                      networkDroppedMessages, networkDeliveryTime, messages,
                      latencyMetrics, bandwidthMetrics>>
    \/ /\ \E v \in Validators : Votor!CollectVotes(v, votorView[v])
       /\ UNCHANGED <<clock, currentRotor, currentSlot, finalizedBlocks, finalizedBySlot,
                      rotorBlockShreds, rotorRelayAssignments,
                      rotorReconstructionState, rotorDeliveredBlocks,
                      rotorRepairRequests, rotorBandwidthUsage,
                      rotorReceivedShreds, rotorReconstructedBlocks, rotorShredAssignments,
                      deliveredBlocks, failureStates,
                      networkMessageQueue, networkMessageBuffer, networkPartitions,
                      networkDroppedMessages, networkDeliveryTime, messages,
                      latencyMetrics, bandwidthMetrics>>
    \/ /\ \E v \in Validators :
           Votor!CollectSkipVotes(v, votorView[v])
       /\ UNCHANGED <<clock, currentRotor, currentSlot, finalizedBlocks, finalizedBySlot,
                      rotorBlockShreds, rotorRelayAssignments,
                      rotorReconstructionState, rotorDeliveredBlocks,
                      rotorRepairRequests, rotorBandwidthUsage,
                      rotorReceivedShreds, rotorReconstructedBlocks, rotorShredAssignments,
                      deliveredBlocks, failureStates,
                      networkMessageQueue, networkMessageBuffer, networkPartitions,
                      networkDroppedMessages, networkDeliveryTime, messages,
                      latencyMetrics, bandwidthMetrics>>
    \/ \E v \in Validators : \E cert \in votorGeneratedCerts[votorView[v]] :
        /\ cert.type \in {"fast", "slow"}
        /\ Votor!FinalizeBlock(v, cert)
        /\ LET blk == CHOOSE b \in UNION {votorVotedBlocks[val][votorView[val]] : val \in Validators} : b.hash = cert.block
           IN /\ finalizedBlocks' = [finalizedBlocks EXCEPT ![blk.slot] =
                                     finalizedBlocks[blk.slot] \cup {blk}]
              /\ finalizedBySlot' = [finalizedBySlot EXCEPT ![blk.slot] = {blk}]
              /\ latencyMetrics' = [latencyMetrics EXCEPT ![blk.slot] = clock - blk.timestamp]
        /\ UNCHANGED <<clock, currentSlot, currentRotor, deliveredBlocks,
                   rotorBlockShreds, rotorRelayAssignments,
                   rotorReconstructionState, rotorDeliveredBlocks,
                   rotorRepairRequests, rotorBandwidthUsage,
                   rotorShredAssignments, rotorReceivedShreds,
                   rotorReconstructedBlocks, failureStates,
                   networkMessageQueue, networkMessageBuffer,
                   networkPartitions, networkDroppedMessages, networkDeliveryTime, messages,
                   bandwidthMetrics>>
    \/ /\ \E v \in Validators : Votor!SubmitSkipVote(v, votorView[v])
       /\ UNCHANGED <<clock, currentRotor, currentSlot, finalizedBlocks, finalizedBySlot,
                      rotorBlockShreds, rotorRelayAssignments,
                      rotorReconstructionState, rotorDeliveredBlocks,
                      rotorRepairRequests, rotorBandwidthUsage,
                      rotorReceivedShreds, rotorReconstructedBlocks, rotorShredAssignments,
                      deliveredBlocks, failureStates,
                      networkMessageQueue, networkMessageBuffer, networkPartitions,
                      networkDroppedMessages, networkDeliveryTime, messages,
                      latencyMetrics, bandwidthMetrics>>

\* Rotor propagation actions
RotorAction ==
    \/ \E leader \in Validators : \E block \in votorVotedBlocks[leader][votorView[leader]] :
        /\ leader = Types!ComputeLeader(votorView[leader], Validators, StakeMapping)  \* View-based leader
        /\ Rotor!ShredAndDistribute(leader, block)
        \* Update global deliveredBlocks to reflect all blocks reconstructed by any validator
        \* This aggregates the network-wide view of available blocks for consensus
        /\ deliveredBlocks' = UNION {rotorReconstructedBlocks[v] : v \in Validators}
        /\ UNCHANGED <<clock, currentRotor, currentSlot, votorView, votorVotedBlocks, votorReceivedVotes,
                       votorGeneratedCerts, votorFinalizedChain, votorTimeoutExpiry,
                       votorSkipVotes, finalizedBlocks, finalizedBySlot,
                       networkMessageQueue, networkMessageBuffer, networkPartitions,
                       networkDroppedMessages, networkDeliveryTime, messages,
                       failureStates, latencyMetrics, bandwidthMetrics>>
    \/ \E v \in Validators, blockId \in DOMAIN rotorBlockShreds :
        /\ Rotor!RelayShreds(v, blockId)
        /\ UNCHANGED <<deliveredBlocks, clock, currentRotor, currentSlot, votorView, votorVotedBlocks, votorReceivedVotes,
                       votorGeneratedCerts, votorFinalizedChain, votorTimeoutExpiry,
                       votorSkipVotes, finalizedBlocks, finalizedBySlot,
                       networkMessageQueue, networkMessageBuffer, networkPartitions,
                       networkDroppedMessages, networkDeliveryTime, messages,
                       failureStates, latencyMetrics, bandwidthMetrics>>
    \/ \E v \in Validators, blockId \in DOMAIN rotorBlockShreds :
        /\ Rotor!AttemptReconstruction(v, blockId)
        /\ deliveredBlocks' = UNION {rotorReconstructedBlocks[v] : v \in Validators}  \* Derive from reconstructed blocks
        /\ UNCHANGED <<clock, currentRotor, currentSlot, votorView, votorVotedBlocks, votorReceivedVotes,
                       votorGeneratedCerts, votorFinalizedChain, votorTimeoutExpiry,
                       votorSkipVotes, finalizedBlocks, finalizedBySlot,
                       networkMessageQueue, networkMessageBuffer, networkPartitions,
                       networkDroppedMessages, networkDeliveryTime, messages,
                       failureStates, latencyMetrics, bandwidthMetrics>>
    \/ \E v \in Validators, blockId \in DOMAIN rotorBlockShreds :
        /\ Rotor!RequestRepair(v, blockId)
        /\ UNCHANGED <<deliveredBlocks, clock, currentRotor, currentSlot, votorView, votorVotedBlocks, votorReceivedVotes,
                       votorGeneratedCerts, votorFinalizedChain, votorTimeoutExpiry,
                       votorSkipVotes, finalizedBlocks, finalizedBySlot,
                       networkMessageQueue, networkMessageBuffer, networkPartitions,
                       networkDroppedMessages, networkDeliveryTime, messages,
                       failureStates, latencyMetrics, bandwidthMetrics>>

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

Spec == Init /\ [][Next]_vars /\ WF_vars(AdvanceClock) /\ WF_vars(AdvanceSlot)

----------------------------------------------------------------------------
(* Safety Properties *)

\* No conflicting blocks finalized in same slot
Safety ==
    \A slot \in 1..MaxSlot :
        \A b1, b2 \in finalizedBlocks[slot] :
            b1 = b2  \* At most one block per slot

\* Certificate uniqueness per slot
CertificateUniqueness ==
    \A slot \in 1..MaxSlot :
        \A vw \in 1..MaxView :
            \A c1, c2 \in votorGeneratedCerts[vw] :
                /\ c1.slot = slot
                /\ c2.slot = slot
                /\ c1.type = c2.type
                /\ c1.block = c2.block
                => c1 = c2

\* Chain consistency across honest validators
ChainConsistency ==
    \A v1, v2 \in HonestValidators :
        \A slot \in 1..currentSlot :
            \* Validators agree on finalized blocks
            slot \in DOMAIN finalizedBySlot /\ finalizedBySlot[slot] # {} =>
                (\E b1 \in votorFinalizedChain[v1], b2 \in votorFinalizedChain[v2] :
                    b1.slot = slot /\ b2.slot = slot => b1 = b2)

\* Consistent finalization
ConsistentFinalization ==
    \A slot \in 1..MaxSlot :
        Cardinality(finalizedBlocks[slot]) <= 1

----------------------------------------------------------------------------
(* Liveness Properties *)

\* Progress with sufficient honest participation
Progress ==
    LET honestStake == Utils!Sum([v \in HonestValidators |-> Stake[v]])
        totalStake == Utils!Sum([v \in Validators |-> Stake[v]])
    IN
    /\ honestStake * 5 >= totalStake * 3  \* >=60% honest
    /\ clock > GST
    => <>(\E b \in finalizedBlocks[currentSlot] : TRUE)

\* Fast path completion with high participation
FastPath ==
    LET ResponsiveStake == Utils!Sum([v \in (HonestValidators \ OfflineValidators) |-> Stake[v]])
        totalStake == Utils!Sum([v \in Validators |-> Stake[v]])
    IN
    /\ ResponsiveStake >= (4 * totalStake) \div 5  \* >=80% responsive
    /\ clock > GST
    => <>(\E vw \in 1..MaxView : \E cert \in votorGeneratedCerts[vw] : cert.type = "fast" /\ cert.slot = currentSlot)

\* Bounded finalization time
BoundedFinalization ==
    LET ResponsiveStake == Utils!Sum([v \in (HonestValidators \ OfflineValidators) |-> Stake[v]])
        totalStake == Utils!Sum([v \in Validators |-> Stake[v]])
        FinalizationBound == IF ResponsiveStake >= (4 * totalStake) \div 5
                             THEN Delta  \* Fast path bound
                             ELSE 2 * Delta  \* Slow path bound
    IN
    /\ clock > GST
    => [](clock <= GST + FinalizationBound =>
          \E b \in finalizedBlocks[currentSlot] : TRUE)

----------------------------------------------------------------------------
(* Resilience Properties *)

\* Maintain safety under maximum Byzantine faults
ByzantineResilience ==
    LET ByzantineStake == Utils!Sum([v \in ByzantineValidators |-> Stake[v]])
        totalStake == Utils!Sum([v \in Validators |-> Stake[v]])
    IN
    ByzantineStake <= totalStake \div 5 => []Safety

\* Maintain liveness under maximum offline faults
OfflineResilience ==
    LET OfflineStake == Utils!Sum([v \in OfflineValidators |-> Stake[v]])
        totalStake == Utils!Sum([v \in Validators |-> Stake[v]])
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
    LET ByzantineStake == Utils!Sum([v \in ByzantineValidators |-> Stake[v]])
        OfflineStake == Utils!Sum([v \in OfflineValidators |-> Stake[v]])
        totalStake == Utils!Sum([v \in Validators |-> Stake[v]])
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
            \* If a block is proposed for a slot, it should be delivered before timeout
            (\E b \in votorVotedBlocks[v][votorView[v]] : b.slot = slot) =>
                \* Either the block is delivered through Rotor
                <>(\E d \in deliveredBlocks : d.slot = slot) \/
                \* Or the validator times out and advances view
                <>(clock >= votorTimeoutExpiry[v] /\ votorView'[v] = votorView[v] + 1) \/
                \* Or the block gets finalized through consensus
                <>(\E cert \in votorGeneratedCerts[votorView[v]] : cert.slot = slot)

\* Bandwidth utilization is stake-proportional
StakeProportionalBandwidth ==
    \A v \in HonestValidators :
        LET ExpectedBandwidth == (Stake[v] * BandwidthPerValidator * Cardinality(Validators)) \div Utils!Sum([val \in Validators |-> Stake[val]])
        IN rotorBandwidthUsage[v] \in (ExpectedBandwidth * 9) \div 10..(ExpectedBandwidth * 11) \div 10

----------------------------------------------------------------------------
(* Model Checking Constraints *)

\* State space reduction for model checking
StateConstraint ==
    /\ clock <= 100
    /\ currentSlot <= 10
    /\ Cardinality(messages) <= 1000  \* messages is correctly used as a set
    /\ Cardinality(deliveredBlocks) <= 50  \* Limit delivered blocks for model checking
    /\ \A v \in Validators : votorView[v] <= 5  \* Limit view progression

\* Action constraint for model checking
ActionConstraint ==
    /\ currentSlot' <= MaxSlot
    /\ \A v \in Validators : votorView'[v] <= MaxView
    /\ Cardinality(votorGeneratedCerts') <= MaxView * 3

\* Symmetry reduction using SymPerms defined above
Symmetry == SymPerms

============================================================================
