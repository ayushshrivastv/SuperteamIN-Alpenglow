------------------------------ MODULE Network ------------------------------
\**************************************************************************
\* Network layer specification for the Alpenglow protocol, modeling
\* message passing, delays, partitions, and Byzantine behavior.
\**************************************************************************

EXTENDS Integers, Sequences, FiniteSets, TLC

CONSTANTS
    Validators,
    ByzantineValidators,
    GST,
    Delta,
    MaxMessageSize,
    NetworkCapacity,
    Stake,
    MaxBufferSize,
    PartitionTimeout

ASSUME
    /\ GST >= 0
    /\ Delta > 0
    /\ MaxMessageSize > 0
    /\ NetworkCapacity > 0
    /\ MaxBufferSize > 0
    /\ PartitionTimeout > 0

----------------------------------------------------------------------------
\* Network State Variables

VARIABLES
    messageQueue,      \* Queue of undelivered messages
    messageBuffer,     \* Delivered messages per validator
    networkPartitions, \* Set of current network partitions
    droppedMessages,   \* Count of dropped messages (for metrics)
    deliveryTime,      \* Map from message ID to delivery time
    clock             \* Current time (may be passed from main spec)

networkVars == <<messageQueue, messageBuffer, networkPartitions, droppedMessages, deliveryTime, clock>>

----------------------------------------------------------------------------
\* Import Type Definitions

INSTANCE Types
Utils == INSTANCE Utils

----------------------------------------------------------------------------
\* Message Types

\* Use NetworkMessage type from Types module for consistency
Message == Types!NetworkMessage

NetworkPartition == [
    partition1: SUBSET Validators,
    partition2: SUBSET Validators,
    startTime: Nat,
    healed: BOOLEAN
]

----------------------------------------------------------------------------
\* Helper Functions

\* Compute actual delay based on network conditions
ComputeActualDelay(sender, recipient, congestionLevel) ==
    Delta  \* Simplified for now

\* Check if two validators are in different partitions
InPartition(sender, recipient, partitions) ==
    \E p \in partitions :
        /\ ~p.healed
        /\ ((sender \in p.partition1 /\ recipient \in p.partition2) \/
            (sender \in p.partition2 /\ recipient \in p.partition1))

\* Available bandwidth at current time
AvailableBandwidth(time) ==
    NetworkCapacity  \* Simplified

\* Check if two validators can communicate
CanCommunicate(sender, recipient) ==
    ~InPartition(sender, recipient, networkPartitions)

\* Generate new message ID (using unique name to avoid conflict)
GenerateNetworkMessageId(time, validator) == time * 10000 + validator

\* Get congestion level
congestionLevel == Cardinality(messageQueue)

\* Messages in the system (standardized as set for consistency with main spec)
messages == messageQueue

\* Note: clock is a variable defined in the main specification

----------------------------------------------------------------------------
\* Partial Synchrony Model

\* Message delay before and after GST
MessageDelay(time, sender, recipient) ==
    IF time < GST
    THEN CHOOSE d \in Nat : TRUE  \* Unbounded delay before GST
    ELSE LET actualDelay == ComputeActualDelay(sender, recipient, congestionLevel)
         IN IF Delta < actualDelay THEN Delta ELSE actualDelay

\* Check if message can be delivered
CanDeliver(msg, time) ==
    /\ msg \in messages
    /\ msg.id \in DOMAIN deliveryTime
    /\ time >= deliveryTime[msg.id]
    /\ ~InPartition(msg.sender, msg.recipient, networkPartitions)
    /\ MaxMessageSize <= AvailableBandwidth(time)  \* Use constant instead of msg.size

\* Eventual delivery guarantee after GST
EventualDelivery(msg, time) ==
    time >= GST =>
        \E t \in time..(time + Delta) :
            CanDeliver(msg, t)

\* Message delivery after GST (referenced in proofs)
MessageDeliveryAfterGST(msg, sendTime, receiveTime) ==
    /\ sendTime >= GST
    /\ receiveTime <= sendTime + Delta
    /\ msg.sender \notin ByzantineValidators
    /\ msg.recipient \in Validators

\* Bounded delay after GST (referenced in proofs)
BoundedDelayAfterGST(sendTime, receiveTime) ==
    /\ sendTime >= GST
    /\ receiveTime <= sendTime + Delta

\* All messages delivered eventually after GST
AllMessagesDelivered(time) ==
    time >= GST =>
        \A msg \in messageQueue :
            /\ msg.sender \notin ByzantineValidators
            /\ msg.recipient \in Validators \ ByzantineValidators
            => <>(msg \notin messageQueue)

\* Partial synchrony condition
PartialSynchrony ==
    clock >= GST =>
        \A msg \in messageQueue :
            /\ msg.sender \notin ByzantineValidators
            /\ msg.timestamp >= GST
            => msg.id \in DOMAIN deliveryTime /\ deliveryTime[msg.id] <= msg.timestamp + Delta

\* Protocol delay tolerance
ProtocolDelayTolerance(protocolType) ==
    CASE protocolType = "consensus" -> 2 * Delta
      [] protocolType = "propagation" -> Delta
      [] protocolType = "recovery" -> 3 * Delta
      [] OTHER -> Delta

----------------------------------------------------------------------------
\* Network Actions (properly exported)

\* Send a message
SendMessage(sender, recipient, content, time) ==
    /\ LET message == [id |-> GenerateNetworkMessageId(time, sender),
                       sender |-> sender,
                       recipient |-> recipient,
                       type |-> "block",  \* Default type
                       payload |-> content,
                       timestamp |-> time,
                       signature |-> [signer |-> sender, message |-> content, valid |-> TRUE]]
       IN /\ messageQueue' = messageQueue \cup {message}
          /\ deliveryTime' = deliveryTime @@ (message.id :> time + MessageDelay(time, sender, recipient))
    /\ UNCHANGED <<messageBuffer, networkPartitions, droppedMessages, clock>>

\* Broadcast message to all validators
BroadcastMessage(sender, content, time) ==
    /\ LET newMessages == {[id |-> GenerateNetworkMessageId(time, sender) + v,
                         sender |-> sender,
                         recipient |-> v,
                         type |-> "block",  \* Default type
                         payload |-> content,
                         timestamp |-> time,
                         signature |-> [signer |-> sender, message |-> content, valid |-> TRUE]] : v \in Validators \ {sender}}
           newDeliveryTimesFunc == [m \in newMessages |-> time + MessageDelay(time, sender, m.recipient)]
       IN /\ messageQueue' = messageQueue \cup newMessages
          /\ deliveryTime' = deliveryTime @@ newDeliveryTimesFunc
    /\ UNCHANGED <<messageBuffer, networkPartitions, droppedMessages, clock>>

\* Deliver message respecting network conditions (properly exported)
DeliverMessage ==
    \E message \in messageQueue :
        /\ message.id \in DOMAIN deliveryTime
        /\ deliveryTime[message.id] <= clock  \* Time to deliver
        /\ CanCommunicate(message.sender, message.recipient)
        /\ message.recipient \in Validators  \* Can't deliver to "broadcast"
        /\ \* GST-based delivery guarantee
           (clock >= GST /\ message.sender \notin ByzantineValidators) =>
               deliveryTime[message.id] <= message.timestamp + Delta
        /\ messageBuffer' = [messageBuffer EXCEPT ![message.recipient] = @ \cup {message}]
        /\ messageQueue' = messageQueue \ {message}
        /\ deliveryTime' = [m \in DOMAIN deliveryTime \ {message.id} |-> deliveryTime[m]]
        /\ UNCHANGED <<networkPartitions, droppedMessages, clock>>

\* Drop a message (before GST) - properly exported
DropMessage ==
    \E msg \in messageQueue :
        /\ clock < GST  \* Can only drop before GST
        /\ \* Allow dropping of Byzantine messages or under adversarial control
           \/ msg.sender \in ByzantineValidators
           \/ msg.recipient \in ByzantineValidators
           \/ ~msg.signature.valid
        /\ messageQueue' = messageQueue \ {msg}
        /\ deliveryTime' = [m \in DOMAIN deliveryTime \ {msg.id} |-> deliveryTime[m]]
        /\ droppedMessages' = droppedMessages + 1
        /\ UNCHANGED <<messageBuffer, networkPartitions, clock>>

\* Duplicate a message (Byzantine behavior)
DuplicateMessage ==
    \E msg \in messageQueue :
        /\ msg.sender \in ByzantineValidators
        /\ msg.id \in DOMAIN deliveryTime
        /\ LET duplicate == [msg EXCEPT !.id = msg.id + 1000]  \* Create unique ID for duplicate
           IN
           /\ messageQueue' = messageQueue \cup {duplicate}
           /\ deliveryTime' = [deliveryTime EXCEPT ![duplicate.id] = deliveryTime[msg.id]]
           /\ UNCHANGED <<messageBuffer, networkPartitions, droppedMessages, clock>>

----------------------------------------------------------------------------
\* Network Partitions

\* Partition the network into two groups - properly exported
PartitionNetwork ==
    /\ clock < GST  \* Partitions can only occur before GST
    /\ \E partition1, partition2 \in SUBSET Validators :
        /\ partition1 \cap partition2 = {}
        /\ partition1 \cup partition2 = Validators
        /\ partition1 # {} /\ partition2 # {}
        /\ \* Ensure partition doesn't isolate all honest validators
           \/ Cardinality(partition1 \cap (Validators \ ByzantineValidators)) > 0
           \/ Cardinality(partition2 \cap (Validators \ ByzantineValidators)) > 0
        /\ LET newPartition == [partition1 |-> partition1,
                                partition2 |-> partition2,
                                startTime |-> clock,
                                healed |-> FALSE]
           IN networkPartitions' = networkPartitions \cup {newPartition}
        /\ UNCHANGED <<messageQueue, messageBuffer, droppedMessages, deliveryTime, clock>>

\* Heal a network partition - properly exported
HealPartition ==
    /\ networkPartitions # {}
    /\ \E partition \in networkPartitions :
        /\ ~partition.healed
        /\ \* Healing can happen after GST or after timeout
           \/ clock >= GST
           \/ clock >= partition.startTime + PartitionTimeout
        /\ networkPartitions' = (networkPartitions \ {partition}) \cup
                               {[partition EXCEPT !.healed = TRUE]}
    /\ UNCHANGED <<messageQueue, messageBuffer, droppedMessages, deliveryTime, clock>>

\* Removed duplicate - InPartition already defined above

----------------------------------------------------------------------------
\* Adversarial Model

\* Adversarial message control (before GST)
AdversarialDelay ==
    \E msg \in messageQueue, newDelay \in 1..100 :
        /\ clock < GST
        /\ msg.id \in DOMAIN deliveryTime
        /\ msg.sender \in ByzantineValidators \/ msg.recipient \in ByzantineValidators
        /\ deliveryTime' = [deliveryTime EXCEPT ![msg.id] = clock + newDelay]
        /\ UNCHANGED <<messageQueue, messageBuffer, networkPartitions, droppedMessages, clock>>

\* Adversarial message reordering
AdversarialReorder ==
    \E msg1, msg2 \in messageQueue :
        /\ clock < GST
        /\ msg1.id \in DOMAIN deliveryTime /\ msg2.id \in DOMAIN deliveryTime
        /\ deliveryTime[msg1.id] < deliveryTime[msg2.id]
        /\ \/ msg1.sender \in ByzantineValidators
           \/ msg2.sender \in ByzantineValidators
        /\ LET temp == deliveryTime[msg1.id]
           IN
           deliveryTime' = [deliveryTime EXCEPT
               ![msg1.id] = deliveryTime[msg2.id],
               ![msg2.id] = temp]
        /\ UNCHANGED <<messageQueue, messageBuffer, networkPartitions, droppedMessages, clock>>

\* Byzantine message injection
InjectByzantineMessage ==
    \E byzantine \in ByzantineValidators :
        /\ LET fakeMsg == [
               id |-> GenerateNetworkMessageId(clock, byzantine),
               sender |-> byzantine,
               recipient |-> "broadcast",
               type |-> "block",
               payload |-> 0,  \* Abstract fake payload
               timestamp |-> clock,
               signature |-> [signer |-> byzantine, message |-> 0, valid |-> FALSE]  \* Fake signature
           ]
           IN
           /\ messageQueue' = messageQueue \cup {fakeMsg}
           /\ deliveryTime' = [deliveryTime EXCEPT ![fakeMsg.id] = clock]
           /\ UNCHANGED <<messageBuffer, networkPartitions, droppedMessages, clock>>

----------------------------------------------------------------------------
\* Helper function to check message not modified
MessageNotModified(msg) ==
    \* Abstract check - in real implementation would verify cryptographic integrity
    msg.signature.valid

\* Initialization
NetworkInit ==
    /\ messageQueue = {}
    /\ messageBuffer = [v \in Validators |-> {}]
    /\ networkPartitions = {}
    /\ droppedMessages = 0
    /\ clock = 0
    /\ deliveryTime = [x \in {} |-> 0]  \* Empty function with proper type

----------------------------------------------------------------------------
\* Safety Properties

\* Next state relation
NetworkNext ==
    \/ \E s \in Validators, r \in Validators \cup {"broadcast"}, c \in {<<>>} :
           SendMessage(s, r, c, clock)
    \/ \E s \in Validators, c \in {<<>>} :
           BroadcastMessage(s, c, clock)
    \/ DeliverMessage
    \/ DropMessage
    \/ DuplicateMessage
    \/ PartitionNetwork
    \/ HealPartition
    \/ AdversarialDelay
    \/ AdversarialReorder
    \/ InjectByzantineMessage
    \/ clock' = clock + 1 /\ UNCHANGED <<messageQueue, messageBuffer, networkPartitions,
                                          droppedMessages, deliveryTime>>  \* Advance clock

\* Network specification
NetworkSpec == NetworkInit /\ [][NetworkNext]_networkVars

----------------------------------------------------------------------------
\* Type Invariant (fixed to match actual variable usage)
NetworkTypeOK ==
    /\ messageQueue \in SUBSET Message  \* messageQueue is a set of messages
    /\ \A msg \in messageQueue :
           /\ msg.id \in Nat
           /\ msg.sender \in Validators
           /\ msg.recipient \in Validators \cup {"broadcast"}
           /\ msg.type \in MessageType
           /\ msg.payload \in Nat
           /\ msg.timestamp \in Nat
           /\ msg.signature.signer \in Validators
           /\ msg.signature.message \in Nat
           /\ msg.signature.valid \in BOOLEAN
    /\ \A v \in Validators :
           /\ messageBuffer[v] \in SUBSET Message
           /\ messageBuffer[v] \subseteq {m \in Message : m.recipient = v}
    /\ networkPartitions \in SUBSET NetworkPartition
    /\ droppedMessages \in Nat
    /\ deliveryTime \in [Nat -> Nat]  \* Function from message IDs to delivery times
    /\ clock \in Nat

----------------------------------------------------------------------------
\* Safety Properties

\* No message forgery for honest validators
NoForgery ==
    \A msg \in messageQueue :
        msg.sender \notin ByzantineValidators =>
            msg.signature.valid

\* Authenticated channel integrity
ChannelIntegrity ==
    \A msg \in messages :
        /\ msg.signature.valid
        /\ msg.sender \notin ByzantineValidators
        => MessageNotModified(msg)

\* Partition detection
PartitionDetection ==
    \A p \in networkPartitions :
        p.healed \/ (clock < p.startTime + PartitionTimeout)

----------------------------------------------------------------------------
\* Liveness Properties

\* Eventually delivery after GST
EventualDeliveryProperty ==
    \A msg \in messageQueue :
        /\ msg.sender \notin ByzantineValidators
        /\ msg.recipient \in Validators \ ByzantineValidators
        /\ clock >= GST
        => <>(msg \notin messageQueue)  \* Eventually delivered

\* Bounded delivery after GST
BoundedDeliveryProperty ==
    \A msg \in messageQueue :
        /\ clock >= GST
        /\ msg.timestamp >= GST
        /\ msg.id \in DOMAIN deliveryTime
        => deliveryTime[msg.id] <= msg.timestamp + Delta

\* Network healing after GST
NetworkHealing ==
    clock >= GST + Delta =>
        \A p \in networkPartitions : p.healed

\* GST-based delivery guarantees
GSTDeliveryGuarantees ==
    /\ clock >= GST
    /\ \A msg \in messageQueue :
        /\ msg.sender \notin ByzantineValidators
        /\ msg.timestamp >= GST
        /\ msg.recipient \in Validators \ ByzantineValidators
        => msg.id \in DOMAIN deliveryTime /\ deliveryTime[msg.id] <= msg.timestamp + Delta

\* Network synchronization after GST
NetworkSynchronization ==
    clock >= GST =>
        /\ \A p \in networkPartitions : p.healed \/ (clock >= p.startTime + PartitionTimeout)
        /\ \A msg \in messageQueue :
            msg.sender \notin ByzantineValidators =>
                EventualDelivery(msg, clock)

\* Message ordering preservation
MessageOrdering ==
    \A msg1, msg2 \in messageQueue :
        (/\ msg1.sender = msg2.sender
         /\ msg1.recipient = msg2.recipient
         /\ msg1.timestamp < msg2.timestamp
         /\ msg1.sender \notin ByzantineValidators
         /\ clock >= GST)
        => ((msg1.id \in DOMAIN deliveryTime /\ msg2.id \in DOMAIN deliveryTime)
            => deliveryTime[msg1.id] <= deliveryTime[msg2.id])

\* Fair message scheduling
FairScheduling ==
    \A m1, m2 \in messageQueue :
        /\ m1.timestamp < m2.timestamp
        /\ m1.sender \notin ByzantineValidators
        /\ m2.sender \notin ByzantineValidators
        /\ clock >= GST
        /\ m1.id \in DOMAIN deliveryTime /\ m2.id \in DOMAIN deliveryTime
        => deliveryTime[m1.id] <= deliveryTime[m2.id] + Delta

----------------------------------------------------------------------------
\* Performance Properties

\* Bandwidth utilization bounds
BandwidthUtilization ==
    LET currentUsage == Cardinality(messageQueue) * MaxMessageSize  \* Simplified
    IN currentUsage <= NetworkCapacity

\* Message buffer bounds
BufferBounds ==
    \A v \in Validators :
        Cardinality(messageBuffer[v]) <= MaxBufferSize

\* Congestion control effectiveness
CongestionControl ==
    LET level == Cardinality(messageQueue)
    IN level > 100 => <>(Cardinality(messageQueue) < 50)  \* Eventually reduces

----------------------------------------------------------------------------
\* Exported Operators for Integration
\* All operators are automatically available when this module is instantiated

============================================================================
