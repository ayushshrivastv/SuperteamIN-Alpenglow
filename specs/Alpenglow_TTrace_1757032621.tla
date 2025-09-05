---- MODULE Alpenglow_TTrace_1757032621 ----
EXTENDS Sequences, TLCExt, Alpenglow_TEConstants, Toolbox, Naturals, TLC, Alpenglow

_expression ==
    LET Alpenglow_TEExpression == INSTANCE Alpenglow_TEExpression
    IN Alpenglow_TEExpression!expression
----

_trace ==
    LET Alpenglow_TETrace == INSTANCE Alpenglow_TETrace
    IN Alpenglow_TETrace!trace
----

_inv ==
    ~(
        TLCGet("level") = Len(_TETrace)
        /\
        networkDroppedMessages = (0)
        /\
        currentSlot = (1)
        /\
        rotorRelayAssignments = ((v1 :> {} @@ v2 :> {} @@ v3 :> {}))
        /\
        votorVotedBlocks = ((v1 :> <<{[view |-> 1, slot |-> 1, timestamp |-> 0, signature |-> [signer |-> v1, message |-> 1, valid |-> TRUE], hash |-> 1, parent |-> 0, transactions |-> {}, data |-> <<>>, proposer |-> v1]}, {}>> @@ v2 :> <<{}, {}>> @@ v3 :> <<{}, {}>>))
        /\
        networkMessageBuffer = ((v1 :> {} @@ v2 :> {} @@ v3 :> {}))
        /\
        networkDeliveryTime = (<<>>)
        /\
        rotorReceivedShreds = ((v1 :> {} @@ v2 :> {} @@ v3 :> {}))
        /\
        networkMessageQueue = ({})
        /\
        failureStates = ((v1 :> "active" @@ v2 :> "active" @@ v3 :> "active"))
        /\
        votorTimeoutExpiry = ((v1 :> 3 @@ v2 :> 3 @@ v3 :> 3))
        /\
        votorView = ((v1 :> 1 @@ v2 :> 1 @@ v3 :> 1))
        /\
        networkPartitions = ({})
        /\
        votorSkipVotes = ((v1 :> <<{}, {}>> @@ v2 :> <<{}, {}>> @@ v3 :> <<{}, {}>>))
        /\
        votorGeneratedCerts = (<<{}, {}>>)
        /\
        bandwidthMetrics = ((v1 :> 0 @@ v2 :> 0 @@ v3 :> 0))
        /\
        rotorRepairRequests = ((v1 :> {} @@ v2 :> {} @@ v3 :> {}))
        /\
        deliveredBlocks = ({})
        /\
        rotorBlockShreds = (<<>>)
        /\
        clock = (0)
        /\
        rotorReconstructionState = ((v1 :> <<>> @@ v2 :> <<>> @@ v3 :> <<>>))
        /\
        rotorDeliveredBlocks = ({})
        /\
        votorReceivedVotes = ((v1 :> <<{}, {}>> @@ v2 :> <<{}, {}>> @@ v3 :> <<{}, {}>>))
        /\
        rotorBandwidthUsage = ((v1 :> 0 @@ v2 :> 0 @@ v3 :> 0))
        /\
        finalizedBlocks = (<<{}, {}>>)
        /\
        rotorReconstructedBlocks = ((v1 :> {} @@ v2 :> {} @@ v3 :> {}))
        /\
        latencyMetrics = (<<0, 0>>)
        /\
        finalizedBySlot = (<<{}, {}>>)
        /\
        votorFinalizedChain = (<<>>)
        /\
        messages = ({})
        /\
        rotorShredAssignments = ((v1 :> {} @@ v2 :> {} @@ v3 :> {}))
    )
----

_init ==
    /\ votorReceivedVotes = _TETrace[1].votorReceivedVotes
    /\ rotorReconstructedBlocks = _TETrace[1].rotorReconstructedBlocks
    /\ latencyMetrics = _TETrace[1].latencyMetrics
    /\ networkPartitions = _TETrace[1].networkPartitions
    /\ rotorBlockShreds = _TETrace[1].rotorBlockShreds
    /\ rotorReceivedShreds = _TETrace[1].rotorReceivedShreds
    /\ rotorDeliveredBlocks = _TETrace[1].rotorDeliveredBlocks
    /\ clock = _TETrace[1].clock
    /\ finalizedBySlot = _TETrace[1].finalizedBySlot
    /\ deliveredBlocks = _TETrace[1].deliveredBlocks
    /\ failureStates = _TETrace[1].failureStates
    /\ rotorBandwidthUsage = _TETrace[1].rotorBandwidthUsage
    /\ networkMessageBuffer = _TETrace[1].networkMessageBuffer
    /\ rotorRelayAssignments = _TETrace[1].rotorRelayAssignments
    /\ networkMessageQueue = _TETrace[1].networkMessageQueue
    /\ networkDroppedMessages = _TETrace[1].networkDroppedMessages
    /\ bandwidthMetrics = _TETrace[1].bandwidthMetrics
    /\ votorTimeoutExpiry = _TETrace[1].votorTimeoutExpiry
    /\ votorVotedBlocks = _TETrace[1].votorVotedBlocks
    /\ rotorReconstructionState = _TETrace[1].rotorReconstructionState
    /\ votorGeneratedCerts = _TETrace[1].votorGeneratedCerts
    /\ finalizedBlocks = _TETrace[1].finalizedBlocks
    /\ votorSkipVotes = _TETrace[1].votorSkipVotes
    /\ votorView = _TETrace[1].votorView
    /\ rotorShredAssignments = _TETrace[1].rotorShredAssignments
    /\ messages = _TETrace[1].messages
    /\ votorFinalizedChain = _TETrace[1].votorFinalizedChain
    /\ currentSlot = _TETrace[1].currentSlot
    /\ rotorRepairRequests = _TETrace[1].rotorRepairRequests
    /\ networkDeliveryTime = _TETrace[1].networkDeliveryTime
----

_next ==
    /\ \E i,j \in DOMAIN _TETrace:
        /\ \/ /\ j = i + 1
              /\ i = TLCGet("level")
        /\ votorReceivedVotes  = _TETrace[i].votorReceivedVotes
        /\ votorReceivedVotes' = _TETrace[j].votorReceivedVotes
        /\ rotorReconstructedBlocks  = _TETrace[i].rotorReconstructedBlocks
        /\ rotorReconstructedBlocks' = _TETrace[j].rotorReconstructedBlocks
        /\ latencyMetrics  = _TETrace[i].latencyMetrics
        /\ latencyMetrics' = _TETrace[j].latencyMetrics
        /\ networkPartitions  = _TETrace[i].networkPartitions
        /\ networkPartitions' = _TETrace[j].networkPartitions
        /\ rotorBlockShreds  = _TETrace[i].rotorBlockShreds
        /\ rotorBlockShreds' = _TETrace[j].rotorBlockShreds
        /\ rotorReceivedShreds  = _TETrace[i].rotorReceivedShreds
        /\ rotorReceivedShreds' = _TETrace[j].rotorReceivedShreds
        /\ rotorDeliveredBlocks  = _TETrace[i].rotorDeliveredBlocks
        /\ rotorDeliveredBlocks' = _TETrace[j].rotorDeliveredBlocks
        /\ clock  = _TETrace[i].clock
        /\ clock' = _TETrace[j].clock
        /\ finalizedBySlot  = _TETrace[i].finalizedBySlot
        /\ finalizedBySlot' = _TETrace[j].finalizedBySlot
        /\ deliveredBlocks  = _TETrace[i].deliveredBlocks
        /\ deliveredBlocks' = _TETrace[j].deliveredBlocks
        /\ failureStates  = _TETrace[i].failureStates
        /\ failureStates' = _TETrace[j].failureStates
        /\ rotorBandwidthUsage  = _TETrace[i].rotorBandwidthUsage
        /\ rotorBandwidthUsage' = _TETrace[j].rotorBandwidthUsage
        /\ networkMessageBuffer  = _TETrace[i].networkMessageBuffer
        /\ networkMessageBuffer' = _TETrace[j].networkMessageBuffer
        /\ rotorRelayAssignments  = _TETrace[i].rotorRelayAssignments
        /\ rotorRelayAssignments' = _TETrace[j].rotorRelayAssignments
        /\ networkMessageQueue  = _TETrace[i].networkMessageQueue
        /\ networkMessageQueue' = _TETrace[j].networkMessageQueue
        /\ networkDroppedMessages  = _TETrace[i].networkDroppedMessages
        /\ networkDroppedMessages' = _TETrace[j].networkDroppedMessages
        /\ bandwidthMetrics  = _TETrace[i].bandwidthMetrics
        /\ bandwidthMetrics' = _TETrace[j].bandwidthMetrics
        /\ votorTimeoutExpiry  = _TETrace[i].votorTimeoutExpiry
        /\ votorTimeoutExpiry' = _TETrace[j].votorTimeoutExpiry
        /\ votorVotedBlocks  = _TETrace[i].votorVotedBlocks
        /\ votorVotedBlocks' = _TETrace[j].votorVotedBlocks
        /\ rotorReconstructionState  = _TETrace[i].rotorReconstructionState
        /\ rotorReconstructionState' = _TETrace[j].rotorReconstructionState
        /\ votorGeneratedCerts  = _TETrace[i].votorGeneratedCerts
        /\ votorGeneratedCerts' = _TETrace[j].votorGeneratedCerts
        /\ finalizedBlocks  = _TETrace[i].finalizedBlocks
        /\ finalizedBlocks' = _TETrace[j].finalizedBlocks
        /\ votorSkipVotes  = _TETrace[i].votorSkipVotes
        /\ votorSkipVotes' = _TETrace[j].votorSkipVotes
        /\ votorView  = _TETrace[i].votorView
        /\ votorView' = _TETrace[j].votorView
        /\ rotorShredAssignments  = _TETrace[i].rotorShredAssignments
        /\ rotorShredAssignments' = _TETrace[j].rotorShredAssignments
        /\ messages  = _TETrace[i].messages
        /\ messages' = _TETrace[j].messages
        /\ votorFinalizedChain  = _TETrace[i].votorFinalizedChain
        /\ votorFinalizedChain' = _TETrace[j].votorFinalizedChain
        /\ currentSlot  = _TETrace[i].currentSlot
        /\ currentSlot' = _TETrace[j].currentSlot
        /\ rotorRepairRequests  = _TETrace[i].rotorRepairRequests
        /\ rotorRepairRequests' = _TETrace[j].rotorRepairRequests
        /\ networkDeliveryTime  = _TETrace[i].networkDeliveryTime
        /\ networkDeliveryTime' = _TETrace[j].networkDeliveryTime

\* Uncomment the ASSUME below to write the states of the error trace
\* to the given file in Json format. Note that you can pass any tuple
\* to `JsonSerialize`. For example, a sub-sequence of _TETrace.
    \* ASSUME
    \*     LET J == INSTANCE Json
    \*         IN J!JsonSerialize("Alpenglow_TTrace_1757032621.json", _TETrace)

=============================================================================

 Note that you can extract this module `Alpenglow_TEExpression`
  to a dedicated file to reuse `expression` (the module in the 
  dedicated `Alpenglow_TEExpression.tla` file takes precedence 
  over the module `Alpenglow_TEExpression` below).

---- MODULE Alpenglow_TEExpression ----
EXTENDS Sequences, TLCExt, Alpenglow_TEConstants, Toolbox, Naturals, TLC, Alpenglow

expression == 
    [
        \* To hide variables of the `Alpenglow` spec from the error trace,
        \* remove the variables below.  The trace will be written in the order
        \* of the fields of this record.
        votorReceivedVotes |-> votorReceivedVotes
        ,rotorReconstructedBlocks |-> rotorReconstructedBlocks
        ,latencyMetrics |-> latencyMetrics
        ,networkPartitions |-> networkPartitions
        ,rotorBlockShreds |-> rotorBlockShreds
        ,rotorReceivedShreds |-> rotorReceivedShreds
        ,rotorDeliveredBlocks |-> rotorDeliveredBlocks
        ,clock |-> clock
        ,finalizedBySlot |-> finalizedBySlot
        ,deliveredBlocks |-> deliveredBlocks
        ,failureStates |-> failureStates
        ,rotorBandwidthUsage |-> rotorBandwidthUsage
        ,networkMessageBuffer |-> networkMessageBuffer
        ,rotorRelayAssignments |-> rotorRelayAssignments
        ,networkMessageQueue |-> networkMessageQueue
        ,networkDroppedMessages |-> networkDroppedMessages
        ,bandwidthMetrics |-> bandwidthMetrics
        ,votorTimeoutExpiry |-> votorTimeoutExpiry
        ,votorVotedBlocks |-> votorVotedBlocks
        ,rotorReconstructionState |-> rotorReconstructionState
        ,votorGeneratedCerts |-> votorGeneratedCerts
        ,finalizedBlocks |-> finalizedBlocks
        ,votorSkipVotes |-> votorSkipVotes
        ,votorView |-> votorView
        ,rotorShredAssignments |-> rotorShredAssignments
        ,messages |-> messages
        ,votorFinalizedChain |-> votorFinalizedChain
        ,currentSlot |-> currentSlot
        ,rotorRepairRequests |-> rotorRepairRequests
        ,networkDeliveryTime |-> networkDeliveryTime
        
        \* Put additional constant-, state-, and action-level expressions here:
        \* ,_stateNumber |-> _TEPosition
        \* ,_votorReceivedVotesUnchanged |-> votorReceivedVotes = votorReceivedVotes'
        
        \* Format the `votorReceivedVotes` variable as Json value.
        \* ,_votorReceivedVotesJson |->
        \*     LET J == INSTANCE Json
        \*     IN J!ToJson(votorReceivedVotes)
        
        \* Lastly, you may build expressions over arbitrary sets of states by
        \* leveraging the _TETrace operator.  For example, this is how to
        \* count the number of times a spec variable changed up to the current
        \* state in the trace.
        \* ,_votorReceivedVotesModCount |->
        \*     LET F[s \in DOMAIN _TETrace] ==
        \*         IF s = 1 THEN 0
        \*         ELSE IF _TETrace[s].votorReceivedVotes # _TETrace[s-1].votorReceivedVotes
        \*             THEN 1 + F[s-1] ELSE F[s-1]
        \*     IN F[_TEPosition - 1]
    ]

=============================================================================



Parsing and semantic processing can take forever if the trace below is long.
 In this case, it is advised to uncomment the module below to deserialize the
 trace from a generated binary file.

\*
\*---- MODULE Alpenglow_TETrace ----
\*EXTENDS IOUtils, Alpenglow_TEConstants, TLC, Alpenglow
\*
\*trace == IODeserialize("Alpenglow_TTrace_1757032621.bin", TRUE)
\*
\*=============================================================================
\*

---- MODULE Alpenglow_TETrace ----
EXTENDS Alpenglow_TEConstants, TLC, Alpenglow

trace == 
    <<
    ([networkDroppedMessages |-> 0,currentSlot |-> 1,rotorRelayAssignments |-> (v1 :> {} @@ v2 :> {} @@ v3 :> {}),votorVotedBlocks |-> (v1 :> <<{}, {}>> @@ v2 :> <<{}, {}>> @@ v3 :> <<{}, {}>>),networkMessageBuffer |-> (v1 :> {} @@ v2 :> {} @@ v3 :> {}),networkDeliveryTime |-> <<>>,rotorReceivedShreds |-> (v1 :> {} @@ v2 :> {} @@ v3 :> {}),networkMessageQueue |-> {},failureStates |-> (v1 :> "active" @@ v2 :> "active" @@ v3 :> "active"),votorTimeoutExpiry |-> (v1 :> 3 @@ v2 :> 3 @@ v3 :> 3),votorView |-> (v1 :> 1 @@ v2 :> 1 @@ v3 :> 1),networkPartitions |-> {},votorSkipVotes |-> (v1 :> <<{}, {}>> @@ v2 :> <<{}, {}>> @@ v3 :> <<{}, {}>>),votorGeneratedCerts |-> <<{}, {}>>,bandwidthMetrics |-> (v1 :> 0 @@ v2 :> 0 @@ v3 :> 0),rotorRepairRequests |-> (v1 :> {} @@ v2 :> {} @@ v3 :> {}),deliveredBlocks |-> {},rotorBlockShreds |-> <<>>,clock |-> 0,rotorReconstructionState |-> (v1 :> <<>> @@ v2 :> <<>> @@ v3 :> <<>>),rotorDeliveredBlocks |-> {},votorReceivedVotes |-> (v1 :> <<{}, {}>> @@ v2 :> <<{}, {}>> @@ v3 :> <<{}, {}>>),rotorBandwidthUsage |-> (v1 :> 0 @@ v2 :> 0 @@ v3 :> 0),finalizedBlocks |-> <<{}, {}>>,rotorReconstructedBlocks |-> (v1 :> {} @@ v2 :> {} @@ v3 :> {}),latencyMetrics |-> <<0, 0>>,finalizedBySlot |-> <<{}, {}>>,votorFinalizedChain |-> <<>>,messages |-> {},rotorShredAssignments |-> (v1 :> {} @@ v2 :> {} @@ v3 :> {})]),
    ([networkDroppedMessages |-> 0,currentSlot |-> 1,rotorRelayAssignments |-> (v1 :> {} @@ v2 :> {} @@ v3 :> {}),votorVotedBlocks |-> (v1 :> <<{[view |-> 1, slot |-> 1, timestamp |-> 0, signature |-> [signer |-> v1, message |-> 1, valid |-> TRUE], hash |-> 1, parent |-> 0, transactions |-> {}, data |-> <<>>, proposer |-> v1]}, {}>> @@ v2 :> <<{}, {}>> @@ v3 :> <<{}, {}>>),networkMessageBuffer |-> (v1 :> {} @@ v2 :> {} @@ v3 :> {}),networkDeliveryTime |-> <<>>,rotorReceivedShreds |-> (v1 :> {} @@ v2 :> {} @@ v3 :> {}),networkMessageQueue |-> {},failureStates |-> (v1 :> "active" @@ v2 :> "active" @@ v3 :> "active"),votorTimeoutExpiry |-> (v1 :> 3 @@ v2 :> 3 @@ v3 :> 3),votorView |-> (v1 :> 1 @@ v2 :> 1 @@ v3 :> 1),networkPartitions |-> {},votorSkipVotes |-> (v1 :> <<{}, {}>> @@ v2 :> <<{}, {}>> @@ v3 :> <<{}, {}>>),votorGeneratedCerts |-> <<{}, {}>>,bandwidthMetrics |-> (v1 :> 0 @@ v2 :> 0 @@ v3 :> 0),rotorRepairRequests |-> (v1 :> {} @@ v2 :> {} @@ v3 :> {}),deliveredBlocks |-> {},rotorBlockShreds |-> <<>>,clock |-> 0,rotorReconstructionState |-> (v1 :> <<>> @@ v2 :> <<>> @@ v3 :> <<>>),rotorDeliveredBlocks |-> {},votorReceivedVotes |-> (v1 :> <<{}, {}>> @@ v2 :> <<{}, {}>> @@ v3 :> <<{}, {}>>),rotorBandwidthUsage |-> (v1 :> 0 @@ v2 :> 0 @@ v3 :> 0),finalizedBlocks |-> <<{}, {}>>,rotorReconstructedBlocks |-> (v1 :> {} @@ v2 :> {} @@ v3 :> {}),latencyMetrics |-> <<0, 0>>,finalizedBySlot |-> <<{}, {}>>,votorFinalizedChain |-> <<>>,messages |-> {},rotorShredAssignments |-> (v1 :> {} @@ v2 :> {} @@ v3 :> {})])
    >>
----


=============================================================================

---- MODULE Alpenglow_TEConstants ----
EXTENDS Alpenglow

CONSTANTS v1, v2, v3

=============================================================================

---- CONFIG Alpenglow_TTrace_1757032621 ----
CONSTANTS
    Validators = { v1 , v2 , v3 }
    ByzantineValidators = { }
    OfflineValidators = { }
    MaxSlot = 2
    MaxView = 2
    MaxTime = 5
    GST = 0
    Delta = 1
    MaxMessageSize = 100
    NetworkCapacity = 1000
    MaxBufferSize = 50
    PartitionTimeout = 5
    K = 2
    N = 3
    MaxBlocks = 3
    BandwidthLimit = 1000
    RetryTimeout = 2
    MaxRetries = 2
    MaxBlockSize = 100
    BandwidthPerValidator = 500
    MaxTransactions = 5
    TimeoutDelta = 3
    InitialLeader = v1
    FastPathStake = 24
    SlowPathStake = 18
    SkipPathStake = 18
    MaxSignatures = 10
    MaxCertificates = 5
    v1 = v1
    v2 = v2
    v3 = v3

INVARIANT
    _inv

CHECK_DEADLOCK
    \* CHECK_DEADLOCK off because of PROPERTY or INVARIANT above.
    FALSE

INIT
    _init

NEXT
    _next

CONSTANT
    _TETrace <- _trace

ALIAS
    _expression
=============================================================================
\* Generated on Fri Sep 05 06:07:03 IST 2025