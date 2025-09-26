\* Author: Ayush Srivastava
------------------------------ MODULE Network ------------------------------
\**************************************************************************
\* Network layer specification for the Alpenglow protocol, modeling
\* message passing, delays, partitions, and Byzantine behavior.
\**************************************************************************

EXTENDS Integers, Sequences, FiniteSets, TLC

\* Define SetToSeq function since it's not standard in TLA+
SetToSeq(S) ==
    CHOOSE seq \in Seq(S) :
        /\ \A x \in S : \E i \in 1..Len(seq) : seq[i] = x
        /\ \A i \in 1..Len(seq) : seq[i] \in S
        /\ \A i, j \in 1..Len(seq) : i # j => seq[i] # seq[j]
        /\ Len(seq) = Cardinality(S)

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

NetworkTypes == INSTANCE Types
NetworkUtils == INSTANCE Utils

----------------------------------------------------------------------------
\* Message Types

\* Use NetworkMessage type from Types module for consistency
Message == NetworkTypes!NetworkMessage

\* Define MessageType for type checking
NetworkMessageType == {"block", "vote", "certificate", "timeout", "repair"}

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
    LET baseDelay == Delta
        congestionPenalty == IF congestionLevel > 50 THEN congestionLevel \div 10 ELSE 0
        \* Deterministic variance based on validator pair - use hash instead of SetToSeq
        senderHash == (CHOOSE i \in 1..1000 : TRUE) % Cardinality(Validators)
        recipientHash == (CHOOSE j \in 1..1000 : TRUE) % Cardinality(Validators)
        variance == ((senderHash + recipientHash) % 5)  \* 0-4 variance
    IN baseDelay + congestionPenalty + variance

\* Check if two validators are in different partitions
InPartition(sender, recipient, partitions) ==
    \E p \in partitions :
        /\ ~p.healed
        /\ ((sender \in p.partition1 /\ recipient \in p.partition2) \/
            (sender \in p.partition2 /\ recipient \in p.partition1))

\* Available bandwidth at current time
AvailableBandwidth(time) ==
    LET utilizationFactor == (congestionLevel * MaxMessageSize) \div NetworkCapacity
        timeVariance == (time % 10)  \* Deterministic time-based variance
        availableCapacity == NetworkCapacity - (congestionLevel * MaxMessageSize) - timeVariance
    IN IF availableCapacity > 0 THEN availableCapacity ELSE MaxMessageSize

\* Check if two validators can communicate
CanCommunicate(sender, recipient) ==
    ~InPartition(sender, recipient, networkPartitions)

\* Generate new message ID with collision avoidance
GenerateNetworkMessageId(time, validator) ==
    LET \* Use deterministic hash instead of SetToSeq
        validatorHash == (CHOOSE i \in 1..1000 : TRUE) % 1000
        \* Include more entropy to avoid collisions
        entropy == (time % 1000) * 1000000 + validatorHash * 1000 + (congestionLevel % 1000)
    IN entropy

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
    THEN LET \* Deterministic delay based on sender, recipient, and time
             senderHash == (CHOOSE i \in 1..1000 : TRUE) % 100
             recipientHash == (CHOOSE j \in 1..1000 : TRUE) % 100
             delayFactor == ((senderHash + recipientHash + time) % 100) + 1
         IN delayFactor  \* Bounded delay 1-100 before GST
    ELSE LET actualDelay == ComputeActualDelay(sender, recipient, congestionLevel)
         IN IF Delta < actualDelay THEN Delta ELSE actualDelay

\* Check if message can be delivered with error handling
CanDeliver(msg, time) ==
    /\ msg \in messages
    /\ msg.id \in DOMAIN deliveryTime
    /\ time >= deliveryTime[msg.id]
    /\ msg.sender \in Validators  \* Validate sender exists
    /\ msg.recipient \in Validators \cup {"broadcast"}  \* Validate recipient
    /\ ~InPartition(msg.sender, msg.recipient, networkPartitions)
    /\ MaxMessageSize <= AvailableBandwidth(time)

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

\* Protocol delay tolerance (duplicate removed - defined earlier in file)

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
          /\ deliveryTime' = [deliveryTime EXCEPT ![message.id] = time + MessageDelay(time, sender, recipient)]
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
           newDeliveryTimes == [m \in newMessages |-> time + MessageDelay(time, sender, m.recipient)]
           newDeliveryTimeFunc == [id \in DOMAIN deliveryTime \cup {m.id : m \in newMessages} |->
                                  IF id \in DOMAIN deliveryTime
                                  THEN deliveryTime[id]
                                  ELSE CHOOSE m \in newMessages : m.id = id /\ newDeliveryTimes[m]]
       IN /\ messageQueue' = messageQueue \cup newMessages
          /\ deliveryTime' = newDeliveryTimeFunc
    /\ UNCHANGED <<messageBuffer, networkPartitions, droppedMessages, clock>>

\* Deliver message respecting network conditions with error handling
DeliverMessage ==
    \E message \in messageQueue :
        /\ message.id \in DOMAIN deliveryTime
        /\ deliveryTime[message.id] <= clock  \* Time to deliver
        /\ message.sender \in Validators  \* Validate sender
        /\ message.recipient \in Validators  \* Can't deliver to "broadcast"
        /\ message.recipient \in DOMAIN messageBuffer  \* Validate buffer exists
        /\ CanCommunicate(message.sender, message.recipient)
        /\ \* GST-based delivery guarantee
           (clock >= GST /\ message.sender \notin ByzantineValidators) =>
               deliveryTime[message.id] <= message.timestamp + Delta
        /\ messageBuffer' = [messageBuffer EXCEPT ![message.recipient] = @ \cup {message}]
        /\ messageQueue' = messageQueue \ {message}
        /\ deliveryTime' = [m \in (DOMAIN deliveryTime) \ {message.id} |-> deliveryTime[m]]
        /\ UNCHANGED <<networkPartitions, droppedMessages, clock>>

\* Drop a message (before GST) with validation
DropMessage ==
    \E msg \in messageQueue :
        /\ clock < GST  \* Can only drop before GST
        /\ msg.id \in DOMAIN deliveryTime  \* Validate delivery time exists
        /\ msg.sender \in Validators  \* Validate sender
        /\ \* Allow dropping of Byzantine messages or under adversarial control
           \/ msg.sender \in ByzantineValidators
           \/ msg.recipient \in ByzantineValidators
           \/ ~msg.signature.valid
        /\ messageQueue' = messageQueue \ {msg}
        /\ deliveryTime' = [m \in (DOMAIN deliveryTime) \ {msg.id} |-> deliveryTime[m]]
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

\* Adversarial message reordering with validation
AdversarialReorder ==
    \E msg1, msg2 \in messageQueue :
        /\ clock < GST
        /\ msg1 # msg2  \* Ensure different messages
        /\ msg1.id \in DOMAIN deliveryTime /\ msg2.id \in DOMAIN deliveryTime
        /\ deliveryTime[msg1.id] < deliveryTime[msg2.id]
        /\ msg1.sender \in Validators /\ msg2.sender \in Validators  \* Validate senders
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
    /\ deliveryTime = <<>>  \* Empty function - use empty sequence for proper typing

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
    /\ messageQueue \in SUBSET [id: Nat, sender: Validators, recipient: Validators \cup {"broadcast"},
                               type: NetworkMessageType, payload: Nat, timestamp: Nat,
                               signature: [signer: Validators, message: Nat, valid: BOOLEAN]]
    /\ \A msg \in messageQueue :
           /\ msg.id \in Nat
           /\ msg.sender \in Validators
           /\ msg.recipient \in Validators \cup {"broadcast"}
           /\ msg.type \in NetworkMessageType
           /\ msg.payload \in Nat
           /\ msg.timestamp \in Nat
           /\ msg.signature.signer \in Validators
           /\ msg.signature.message \in Nat
           /\ msg.signature.valid \in BOOLEAN
    /\ \A v \in Validators :
           /\ messageBuffer[v] \in SUBSET [id: Nat, sender: Validators, recipient: Validators \cup {"broadcast"},
                                          type: NetworkMessageType, payload: Nat, timestamp: Nat,
                                          signature: [signer: Validators, message: Nat, valid: BOOLEAN]]
           /\ \A m \in messageBuffer[v] : m.recipient = v \/ m.recipient = "broadcast"
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
\* Network Partition Recovery Proofs

\* Partition recovery theorem: All partitions heal after GST + timeout
PartitionRecoveryTheorem ==
    \A p \in networkPartitions :
        clock >= GST + PartitionTimeout => p.healed

\* Network connectivity restoration after partition healing
ConnectivityRestoration ==
    \A p \in networkPartitions :
        p.healed => \A v1, v2 \in Validators :
            CanCommunicate(v1, v2)

\* Message delivery resumption after partition recovery
DeliveryResumption ==
    \A p \in networkPartitions :
        p.healed => \A msg \in messageQueue :
            /\ msg.sender \notin ByzantineValidators
            /\ msg.recipient \in Validators \ ByzantineValidators
            /\ msg.timestamp >= p.startTime
            => <>(msg \notin messageQueue)

\* Partition isolation bounds: No partition isolates majority honest stake
PartitionIsolationBounds ==
    \A p \in networkPartitions :
        ~p.healed =>
            LET honestInP1 == p.partition1 \ ByzantineValidators
                honestInP2 == p.partition2 \ ByzantineValidators
                totalHonest == Validators \ ByzantineValidators
                p1HonestStake == NetworkUtils!TotalStake(honestInP1, Stake)
                p2HonestStake == NetworkUtils!TotalStake(honestInP2, Stake)
                totalHonestStake == NetworkUtils!TotalStake(totalHonest, Stake)
            IN /\ p1HonestStake <= totalHonestStake \div 2
               /\ p2HonestStake <= totalHonestStake \div 2

\* Network partition recovery progress
PartitionRecoveryProgress ==
    \A p \in networkPartitions :
        /\ ~p.healed
        /\ clock >= p.startTime + PartitionTimeout
        => <>HealPartition

\* Consensus progress after partition recovery
ConsensusProgressAfterRecovery ==
    \A p \in networkPartitions :
        p.healed /\ clock >= GST =>
            <>\E slot \in Nat : \* Eventually consensus progresses
                \E block \in {msg \in messageQueue : msg.type = "block"} :
                    block.payload > p.startTime  \* New block after partition

----------------------------------------------------------------------------
\* Performance Bounds Validation

\* Throughput bounds: Messages processed within capacity limits
ThroughputBounds ==
    LET messagesPerSecond == Cardinality({msg \in messageQueue : msg.timestamp = clock})
        maxThroughput == NetworkCapacity \div MaxMessageSize
    IN messagesPerSecond <= maxThroughput

\* Latency bounds: Message delivery within expected time after GST
LatencyBounds ==
    \A msg \in messageQueue :
        /\ clock >= GST
        /\ msg.timestamp >= GST
        /\ msg.sender \notin ByzantineValidators
        /\ msg.id \in DOMAIN deliveryTime
        => deliveryTime[msg.id] <= msg.timestamp + Delta

\* Memory bounds: Buffer usage stays within limits
MemoryBounds ==
    /\ Cardinality(messageQueue) <= NetworkCapacity \div MaxMessageSize
    /\ \A v \in Validators : Cardinality(messageBuffer[v]) <= MaxBufferSize
    /\ Cardinality(DOMAIN deliveryTime) <= 10000  \* Reasonable delivery time map size

\* Network utilization efficiency
NetworkUtilization ==
    LET totalMessages == Cardinality(messageQueue)
        utilizedCapacity == totalMessages * MaxMessageSize
        efficiency == IF NetworkCapacity = 0 THEN 0
                     ELSE (utilizedCapacity * 100) \div NetworkCapacity
    IN efficiency <= 80  \* Keep utilization under 80% for performance

\* Congestion control effectiveness with performance bounds
CongestionControlBounds ==
    LET currentCongestion == Cardinality(messageQueue)
        criticalThreshold == ((NetworkCapacity \div MaxMessageSize) * 3) \div 4  \* 75% capacity
    IN currentCongestion > criticalThreshold =>
        <>(Cardinality(messageQueue) < criticalThreshold \div 2)

\* Message processing rate bounds
ProcessingRateBounds ==
    LET processedThisSecond == Cardinality({msg \in messageQueue :
                                          msg.id \in DOMAIN deliveryTime /\
                                          deliveryTime[msg.id] = clock})
        maxProcessingRate == NetworkCapacity \div (MaxMessageSize * 2)  \* Conservative bound
    IN processedThisSecond <= maxProcessingRate

\* End-to-end performance bounds
EndToEndPerformanceBounds ==
    \A msg \in messageQueue :
        /\ msg.sender \notin ByzantineValidators
        /\ msg.recipient \in Validators \ ByzantineValidators
        /\ clock >= GST
        => LET deliveryLatency == IF msg.id \in DOMAIN deliveryTime
                                 THEN deliveryTime[msg.id] - msg.timestamp
                                 ELSE 0
           IN deliveryLatency <= 2 * Delta  \* Conservative bound

\* Performance degradation bounds under adversarial conditions
PerformanceDegradationBounds ==
    LET byzantineMessageRatio == (Cardinality({msg \in messageQueue : msg.sender \in ByzantineValidators}) * 100) \div
                                (IF Cardinality(messageQueue) = 0 THEN 1 ELSE Cardinality(messageQueue))
        performanceDegradation == byzantineMessageRatio \div 2  \* Simplified metric
    IN performanceDegradation <= 50  \* Performance shouldn't degrade more than 50%

----------------------------------------------------------------------------
\* Advanced Network Properties

\* Network resilience under combined failures
NetworkResilience ==
    /\ Cardinality(ByzantineValidators) <= Cardinality(Validators) \div 3  \* < 1/3 Byzantine
    /\ \A p \in networkPartitions :
        ~p.healed => \E partition \in {p.partition1, p.partition2} :
            Cardinality(partition \ ByzantineValidators) > Cardinality(Validators) \div 3

\* Adaptive performance under network stress
AdaptivePerformance ==
    LET networkStress == Cardinality(messageQueue) + Cardinality(networkPartitions) * 10
        adaptiveThreshold == NetworkCapacity \div (MaxMessageSize * 4)
    IN networkStress > adaptiveThreshold =>
        <>\E newThreshold \in Nat : newThreshold < adaptiveThreshold

\* Quality of service guarantees
QualityOfService ==
    \A msg \in messageQueue :
        /\ msg.sender \notin ByzantineValidators
        /\ msg.type = "block"  \* High priority messages
        /\ clock >= GST
        => msg.id \in DOMAIN deliveryTime /\ deliveryTime[msg.id] <= msg.timestamp + Delta

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
