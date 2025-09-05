------------------------------ MODULE AdaptiveTimeouts ------------------------------
(**************************************************************************)
(* Sophisticated adaptive timeout mechanisms for the Alpenglow protocol   *)
(* that extend basic timeout functionality with network-aware adaptations *)
(* and integrate with Votor consensus to maintain safety and liveness     *)
(* properties under varying network conditions.                           *)
(**************************************************************************)

EXTENDS Integers, Sequences, FiniteSets, TLC

CONSTANTS
    Validators,          \* Set of all validators
    ByzantineValidators, \* Set of Byzantine validators
    OfflineValidators,   \* Set of offline validators
    MaxView,             \* Maximum view number
    MaxSlot,             \* Maximum slot number
    GST,                 \* Global Stabilization Time
    Delta,               \* Network delay bound
    Stake                \* Stake distribution function

\* Import foundational modules
INSTANCE Types WITH Validators <- Validators,
                    ByzantineValidators <- ByzantineValidators,
                    OfflineValidators <- OfflineValidators,
                    MaxSlot <- MaxSlot,
                    MaxView <- MaxView,
                    GST <- GST,
                    Delta <- Delta

INSTANCE Timing WITH ByzantineValidators <- ByzantineValidators

INSTANCE Network WITH Validators <- Validators,
                      ByzantineValidators <- ByzantineValidators,
                      GST <- GST,
                      Delta <- Delta,
                      Stake <- Stake

INSTANCE Utils

----------------------------------------------------------------------------
(* Adaptive Timeout State Variables *)

VARIABLES
    adaptiveTimeouts,     \* Current adaptive timeout values [validator][slot]
    timeoutHistory,       \* Historical timeout performance [validator][slot]
    networkConditions,    \* Current network condition assessment [validator]
    performanceMetrics,   \* Performance tracking for timeout tuning [validator]
    timeoutAdjustments,   \* Recent timeout adjustments [validator][slot]
    consensusProgress,    \* Consensus progress tracking for timeout optimization
    partitionDetection,   \* Network partition detection state [validator]
    gstEstimation,        \* GST estimation per validator [validator]
    clock                 \* Global clock

adaptiveTimeoutVars == <<adaptiveTimeouts, timeoutHistory, networkConditions,
                        performanceMetrics, timeoutAdjustments, consensusProgress,
                        partitionDetection, gstEstimation, clock>>

----------------------------------------------------------------------------
(* Network Condition Types *)

NetworkCondition == [
    latency: Nat,           \* Average observed latency
    jitter: Nat,            \* Latency variance
    packetLoss: Nat,        \* Packet loss percentage (0-100)
    bandwidth: Nat,         \* Available bandwidth
    congestion: Nat,        \* Congestion level (0-100)
    stability: STRING       \* "stable", "degraded", "unstable"
]

PerformanceMetric == [
    successRate: Nat,       \* Success rate percentage (0-100)
    averageLatency: Nat,    \* Average response latency
    timeoutCount: Nat,      \* Number of timeouts experienced
    recoveryTime: Nat,      \* Time to recover from timeouts
    consensusDelay: Nat     \* Delay in consensus progression
]

TimeoutAdjustment == [
    oldTimeout: Nat,        \* Previous timeout value
    newTimeout: Nat,        \* New timeout value
    reason: STRING,         \* Reason for adjustment
    timestamp: Nat,         \* When adjustment was made
    effectiveness: Nat      \* Effectiveness score (0-100)
]

PartitionState == [
    detected: BOOLEAN,      \* Whether partition is detected
    startTime: Nat,         \* When partition was detected
    severity: STRING,       \* "minor", "major", "critical"
    affectedValidators: SUBSET Validators,
    recoveryEstimate: Nat   \* Estimated recovery time
]

----------------------------------------------------------------------------
(* Adaptive Timeout Constants *)

\* Base timeout values
BaseConsensusTimeout == 200     \* Base consensus timeout (ms)
BaseVotingTimeout == 100        \* Base voting timeout (ms)
BaseFinalizationTimeout == 150  \* Base finalization timeout (ms)

\* Adaptation parameters
MinAdaptiveTimeout == 50        \* Minimum adaptive timeout
MaxAdaptiveTimeout == 8000      \* Maximum adaptive timeout
AdaptationFactor == 1.5         \* Multiplication factor for adaptations
BackoffMultiplier == 2          \* Exponential backoff multiplier
MaxBackoffSteps == 10           \* Maximum backoff steps

\* Network condition thresholds
HighLatencyThreshold == 200     \* High latency threshold (ms)
HighJitterThreshold == 100      \* High jitter threshold (ms)
HighLossThreshold == 5          \* High packet loss threshold (%)
LowBandwidthThreshold == 1000   \* Low bandwidth threshold
HighCongestionThreshold == 70   \* High congestion threshold (%)

\* Performance thresholds
MinSuccessRate == 80            \* Minimum acceptable success rate (%)
MaxTimeoutCount == 5            \* Maximum timeouts before adaptation
TargetConsensusDelay == 300     \* Target consensus delay (ms)

\* GST estimation parameters
GSTEstimationWindow == 10       \* Window for GST estimation
GSTConfidenceThreshold == 80    \* Confidence threshold for GST estimation

\* Partition detection parameters
PartitionDetectionWindow == 5   \* Window for partition detection
PartitionThreshold == 3         \* Threshold for partition detection

----------------------------------------------------------------------------
(* Network Condition Assessment *)

\* Assess current network conditions for a validator
AssessNetworkConditions(validator) ==
    LET recentMessages == {msg \in Network!messageBuffer[validator] :
                          msg.timestamp >= clock - 10}
        avgLatency == IF recentMessages = {} THEN Delta
                     ELSE Utils!Average({msg.timestamp - (msg.timestamp - Delta) : msg \in recentMessages})
        jitterValue == IF recentMessages = {} THEN 0
                      ELSE Utils!StandardDeviation({msg.timestamp - (msg.timestamp - Delta) : msg \in recentMessages})
        lossRate == IF Cardinality(recentMessages) = 0 THEN 0
                   ELSE (10 - Cardinality(recentMessages)) * 10  \* Simplified loss calculation
        congestionLevel == Min(Cardinality(Network!messageQueue) * 10, 100)
        stability == IF avgLatency <= HighLatencyThreshold /\ jitterValue <= HighJitterThreshold /\ lossRate <= HighLossThreshold
                    THEN "stable"
                    ELSE IF avgLatency <= HighLatencyThreshold * 2 /\ lossRate <= HighLossThreshold * 2
                    THEN "degraded"
                    ELSE "unstable"
    IN [latency |-> avgLatency,
        jitter |-> jitterValue,
        packetLoss |-> lossRate,
        bandwidth |-> Max(LowBandwidthThreshold, 10000 - congestionLevel * 100),
        congestion |-> congestionLevel,
        stability |-> stability]

\* Update network conditions for all validators
UpdateNetworkConditions ==
    networkConditions' = [v \in Validators |-> AssessNetworkConditions(v)]

----------------------------------------------------------------------------
(* Dynamic Timeout Calculation *)

\* Calculate base timeout based on network conditions
CalculateBaseTimeout(validator, timeoutType) ==
    LET conditions == networkConditions[validator]
        baseValue == CASE timeoutType = "consensus" -> BaseConsensusTimeout
                       [] timeoutType = "voting" -> BaseVotingTimeout
                       [] timeoutType = "finalization" -> BaseFinalizationTimeout
                       [] OTHER -> BaseConsensusTimeout
        latencyAdjustment == conditions.latency \div 2
        jitterAdjustment == conditions.jitter
        lossAdjustment == conditions.packetLoss * 5
        congestionAdjustment == conditions.congestion * 2
        stabilityMultiplier == CASE conditions.stability = "stable" -> 1
                                 [] conditions.stability = "degraded" -> 2
                                 [] conditions.stability = "unstable" -> 3
                                 [] OTHER -> 1
    IN Min(MaxAdaptiveTimeout,
           Max(MinAdaptiveTimeout,
               (baseValue + latencyAdjustment + jitterAdjustment + lossAdjustment + congestionAdjustment) * stabilityMultiplier))

\* Apply exponential backoff with network-aware adjustments
ExponentialBackoffWithNetworkAwareness(validator, slot, currentTimeout, failureCount) ==
    LET conditions == networkConditions[validator]
        backoffSteps == Min(failureCount, MaxBackoffSteps)
        exponentialTimeout == currentTimeout * (BackoffMultiplier ^ backoffSteps)
        networkMultiplier == CASE conditions.stability = "stable" -> 1
                               [] conditions.stability = "degraded" -> AdaptationFactor
                               [] conditions.stability = "unstable" -> AdaptationFactor * 2
                               [] OTHER -> 1
        partitionMultiplier == IF partitionDetection[validator].detected
                              THEN CASE partitionDetection[validator].severity = "minor" -> 2
                                     [] partitionDetection[validator].severity = "major" -> 3
                                     [] partitionDetection[validator].severity = "critical" -> 5
                                     [] OTHER -> 1
                              ELSE 1
    IN Min(MaxAdaptiveTimeout,
           Max(MinAdaptiveTimeout,
               exponentialTimeout * networkMultiplier * partitionMultiplier))

\* GST-based timeout optimization
GSTBasedTimeoutOptimization(validator, baseTimeout) ==
    LET estimatedGST == gstEstimation[validator]
        currentTime == clock
        gstAdjustment == IF currentTime < estimatedGST
                        THEN (estimatedGST - currentTime) \div 2  \* Increase timeout before GST
                        ELSE 0  \* No adjustment after GST
        postGSTOptimization == IF currentTime >= estimatedGST
                              THEN Max(baseTimeout \div 2, MinAdaptiveTimeout)  \* Optimize after GST
                              ELSE baseTimeout
    IN Min(MaxAdaptiveTimeout,
           Max(MinAdaptiveTimeout,
               postGSTOptimization + gstAdjustment))

\* Partition-aware timeout extensions
PartitionAwareTimeoutExtension(validator, baseTimeout) ==
    LET partition == partitionDetection[validator]
        extensionFactor == IF partition.detected
                          THEN CASE partition.severity = "minor" -> 2
                                 [] partition.severity = "major" -> 4
                                 [] partition.severity = "critical" -> 8
                                 [] OTHER -> 1
                          ELSE 1
        recoveryAdjustment == IF partition.detected /\ partition.recoveryEstimate > 0
                             THEN Min(partition.recoveryEstimate \div 2, MaxAdaptiveTimeout \div 4)
                             ELSE 0
    IN Min(MaxAdaptiveTimeout,
           Max(MinAdaptiveTimeout,
               baseTimeout * extensionFactor + recoveryAdjustment))

\* Performance-based timeout tuning
PerformanceBasedTimeoutTuning(validator, slot, baseTimeout) ==
    LET metrics == performanceMetrics[validator]
        successRateAdjustment == IF metrics.successRate < MinSuccessRate
                                THEN (MinSuccessRate - metrics.successRate) * 5
                                ELSE -(metrics.successRate - MinSuccessRate) \div 2
        latencyAdjustment == IF metrics.averageLatency > TargetConsensusDelay
                            THEN (metrics.averageLatency - TargetConsensusDelay) \div 2
                            ELSE 0
        timeoutCountPenalty == IF metrics.timeoutCount > MaxTimeoutCount
                              THEN metrics.timeoutCount * 20
                              ELSE 0
        recoveryBonus == IF metrics.recoveryTime < baseTimeout \div 2
                        THEN -(baseTimeout \div 10)
                        ELSE 0
    IN Min(MaxAdaptiveTimeout,
           Max(MinAdaptiveTimeout,
               baseTimeout + successRateAdjustment + latencyAdjustment + timeoutCountPenalty + recoveryBonus))

\* Comprehensive adaptive timeout calculation
CalculateAdaptiveTimeout(validator, slot, timeoutType) ==
    LET baseTimeout == CalculateBaseTimeout(validator, timeoutType)
        history == timeoutHistory[validator][slot]
        failureCount == IF history = {} THEN 0
                       ELSE Cardinality({h \in history : h.result = "timeout"})
        backoffTimeout == ExponentialBackoffWithNetworkAwareness(validator, slot, baseTimeout, failureCount)
        gstOptimizedTimeout == GSTBasedTimeoutOptimization(validator, backoffTimeout)
        partitionAwareTimeout == PartitionAwareTimeoutExtension(validator, gstOptimizedTimeout)
        performanceTunedTimeout == PerformanceBasedTimeoutTuning(validator, slot, partitionAwareTimeout)
    IN performanceTunedTimeout

----------------------------------------------------------------------------
(* Partition Detection and Recovery *)

\* Detect network partitions based on communication patterns
DetectNetworkPartition(validator) ==
    LET recentCommunications == {msg \in Network!messageBuffer[validator] :
                                msg.timestamp >= clock - PartitionDetectionWindow}
        communicatingValidators == {msg.sender : msg \in recentCommunications}
        expectedCommunications == Cardinality(Validators \ ByzantineValidators \ OfflineValidators)
        actualCommunications == Cardinality(communicatingValidators)
        partitionSeverity == IF actualCommunications < expectedCommunications \div 3
                            THEN "critical"
                            ELSE IF actualCommunications < expectedCommunications \div 2
                            THEN "major"
                            ELSE IF actualCommunications < expectedCommunications * 2 \div 3
                            THEN "minor"
                            ELSE "none"
        isPartitioned == partitionSeverity # "none"
        affectedVals == Validators \ communicatingValidators
        recoveryEst == IF isPartitioned
                      THEN CASE partitionSeverity = "minor" -> Delta * 2
                             [] partitionSeverity = "major" -> Delta * 5
                             [] partitionSeverity = "critical" -> Delta * 10
                             [] OTHER -> Delta
                      ELSE 0
    IN [detected |-> isPartitioned,
        startTime |-> IF isPartitioned /\ ~partitionDetection[validator].detected THEN clock
                     ELSE partitionDetection[validator].startTime,
        severity |-> partitionSeverity,
        affectedValidators |-> affectedVals,
        recoveryEstimate |-> recoveryEst]

\* Update partition detection for all validators
UpdatePartitionDetection ==
    partitionDetection' = [v \in Validators |-> DetectNetworkPartition(v)]

----------------------------------------------------------------------------
(* GST Estimation *)

\* Estimate GST based on network stability patterns
EstimateGST(validator) ==
    LET recentConditions == {networkConditions[validator]}  \* Simplified - would track history
        stabilityPeriods == {c \in recentConditions : c.stability = "stable"}
        avgStableLatency == IF stabilityPeriods = {} THEN Delta * 2
                           ELSE Utils!Average({c.latency : c \in stabilityPeriods})
        confidenceLevel == IF Cardinality(stabilityPeriods) >= GSTEstimationWindow \div 2
                          THEN Min(100, Cardinality(stabilityPeriods) * 10)
                          ELSE 0
        estimatedGST == IF confidenceLevel >= GSTConfidenceThreshold
                       THEN clock + avgStableLatency
                       ELSE GST  \* Fall back to configured GST
    IN estimatedGST

\* Update GST estimation for all validators
UpdateGSTEstimation ==
    gstEstimation' = [v \in Validators |-> EstimateGST(v)]

----------------------------------------------------------------------------
(* Performance Metrics Tracking *)

\* Calculate performance metrics for a validator
CalculatePerformanceMetrics(validator) ==
    LET recentHistory == UNION {timeoutHistory[validator][slot] : slot \in 1..MaxSlot}
        recentEvents == {h \in recentHistory : h.timestamp >= clock - 10}
        totalEvents == Cardinality(recentEvents)
        successfulEvents == Cardinality({h \in recentEvents : h.result = "success"})
        timeoutEvents == Cardinality({h \in recentEvents : h.result = "timeout"})
        successRate == IF totalEvents = 0 THEN 100
                      ELSE (successfulEvents * 100) \div totalEvents
        avgLatency == IF recentEvents = {} THEN 0
                     ELSE Utils!Average({h.latency : h \in recentEvents})
        consensusDelay == IF consensusProgress = {} THEN 0
                         ELSE Utils!Average({cp.delay : cp \in consensusProgress})
        recoveryTime == IF timeoutEvents = 0 THEN 0
                       ELSE Utils!Average({h.recoveryTime : h \in recentEvents, h.result = "timeout"})
    IN [successRate |-> successRate,
        averageLatency |-> avgLatency,
        timeoutCount |-> timeoutEvents,
        recoveryTime |-> recoveryTime,
        consensusDelay |-> consensusDelay]

\* Update performance metrics for all validators
UpdatePerformanceMetrics ==
    performanceMetrics' = [v \in Validators |-> CalculatePerformanceMetrics(v)]

----------------------------------------------------------------------------
(* Timeout Adjustment Actions *)

\* Adjust timeout for a specific validator and slot
AdjustTimeout(validator, slot, timeoutType, reason) ==
    /\ validator \in Validators
    /\ slot \in 1..MaxSlot
    /\ timeoutType \in {"consensus", "voting", "finalization"}
    /\ LET oldTimeout == IF <<validator, slot>> \in DOMAIN adaptiveTimeouts
                        THEN adaptiveTimeouts[validator][slot]
                        ELSE CalculateBaseTimeout(validator, timeoutType)
           newTimeout == CalculateAdaptiveTimeout(validator, slot, timeoutType)
           adjustment == [oldTimeout |-> oldTimeout,
                         newTimeout |-> newTimeout,
                         reason |-> reason,
                         timestamp |-> clock,
                         effectiveness |-> 0]  \* Will be updated based on results
       IN /\ adaptiveTimeouts' = [adaptiveTimeouts EXCEPT ![validator][slot] = newTimeout]
          /\ timeoutAdjustments' = [timeoutAdjustments EXCEPT ![validator][slot] = 
                                   timeoutAdjustments[validator][slot] \cup {adjustment}]
    /\ UNCHANGED <<timeoutHistory, networkConditions, performanceMetrics,
                   consensusProgress, partitionDetection, gstEstimation, clock>>

\* Record timeout event in history
RecordTimeoutEvent(validator, slot, result, latency, recoveryTime) ==
    /\ validator \in Validators
    /\ slot \in 1..MaxSlot
    /\ result \in {"success", "timeout", "failure"}
    /\ LET event == [result |-> result,
                    latency |-> latency,
                    recoveryTime |-> recoveryTime,
                    timestamp |-> clock]
       IN timeoutHistory' = [timeoutHistory EXCEPT ![validator][slot] = 
                            timeoutHistory[validator][slot] \cup {event}]
    /\ UNCHANGED <<adaptiveTimeouts, networkConditions, performanceMetrics,
                   timeoutAdjustments, consensusProgress, partitionDetection, gstEstimation, clock>>

\* Update consensus progress tracking
UpdateConsensusProgress(slot, delay, success) ==
    /\ slot \in 1..MaxSlot
    /\ LET progressEvent == [slot |-> slot,
                            delay |-> delay,
                            success |-> success,
                            timestamp |-> clock]
       IN consensusProgress' = consensusProgress \cup {progressEvent}
    /\ UNCHANGED <<adaptiveTimeouts, timeoutHistory, networkConditions, performanceMetrics,
                   timeoutAdjustments, partitionDetection, gstEstimation, clock>>

----------------------------------------------------------------------------
(* Integration with Votor Consensus *)

\* Check if timeout should be applied for Votor voting
ShouldApplyVotorTimeout(validator, slot) ==
    /\ validator \in Validators
    /\ slot \in 1..MaxSlot
    /\ LET currentTimeout == adaptiveTimeouts[validator][slot]
           votingStartTime == slot * Types!SlotDuration  \* Simplified
           elapsedTime == clock - votingStartTime
       IN elapsedTime >= currentTimeout

\* Get adaptive timeout for Votor consensus operations
GetVotorTimeout(validator, slot, operation) ==
    /\ validator \in Validators
    /\ slot \in 1..MaxSlot
    /\ operation \in {"notarization", "finalization", "skip"}
    /\ LET timeoutType == CASE operation = "notarization" -> "voting"
                            [] operation = "finalization" -> "finalization"
                            [] operation = "skip" -> "consensus"
                            [] OTHER -> "consensus"
       IN IF <<validator, slot>> \in DOMAIN adaptiveTimeouts
          THEN adaptiveTimeouts[validator][slot]
          ELSE CalculateAdaptiveTimeout(validator, slot, timeoutType)

\* Trigger timeout adaptation based on Votor consensus results
TriggerVotorTimeoutAdaptation(validator, slot, operation, success, latency) ==
    /\ validator \in Validators
    /\ slot \in 1..MaxSlot
    /\ operation \in {"notarization", "finalization", "skip"}
    /\ success \in BOOLEAN
    /\ LET result == IF success THEN "success" ELSE "timeout"
           recoveryTime == IF success THEN 0 ELSE latency * 2
           reason == "votor_" \o operation \o "_" \o result
       IN /\ RecordTimeoutEvent(validator, slot, result, latency, recoveryTime)
          /\ AdjustTimeout(validator, slot, "consensus", reason)

----------------------------------------------------------------------------
(* Safety and Liveness Properties *)

\* Timeout bounds invariant - all timeouts within valid bounds
TimeoutBoundsInvariant ==
    \A validator \in Validators :
        \A slot \in 1..MaxSlot :
            <<validator, slot>> \in DOMAIN adaptiveTimeouts =>
                /\ adaptiveTimeouts[validator][slot] >= MinAdaptiveTimeout
                /\ adaptiveTimeouts[validator][slot] <= MaxAdaptiveTimeout

\* Timeout progression invariant - timeouts adapt reasonably
TimeoutProgressionInvariant ==
    \A validator \in Validators :
        \A slot \in 1..MaxSlot :
            LET adjustments == timeoutAdjustments[validator][slot]
            IN \A adj \in adjustments :
                /\ adj.newTimeout >= MinAdaptiveTimeout
                /\ adj.newTimeout <= MaxAdaptiveTimeout
                /\ adj.newTimeout <= adj.oldTimeout * 10  \* Reasonable adaptation bounds

\* Network responsiveness invariant - timeouts respond to network conditions
NetworkResponsivenessInvariant ==
    \A validator \in Validators :
        LET conditions == networkConditions[validator]
        IN conditions.stability = "unstable" =>
            \E slot \in 1..MaxSlot :
                <<validator, slot>> \in DOMAIN adaptiveTimeouts =>
                    adaptiveTimeouts[validator][slot] > CalculateBaseTimeout(validator, "consensus")

\* Partition resilience invariant - timeouts extend during partitions
PartitionResilienceInvariant ==
    \A validator \in Validators :
        partitionDetection[validator].detected =>
            \E slot \in 1..MaxSlot :
                <<validator, slot>> \in DOMAIN adaptiveTimeouts =>
                    adaptiveTimeouts[validator][slot] >= CalculateBaseTimeout(validator, "consensus") * 2

\* GST optimization invariant - timeouts optimize after GST
GSTOptimizationInvariant ==
    \A validator \in Validators :
        clock >= gstEstimation[validator] /\ networkConditions[validator].stability = "stable" =>
            \E slot \in 1..MaxSlot :
                <<validator, slot>> \in DOMAIN adaptiveTimeouts =>
                    adaptiveTimeouts[validator][slot] <= CalculateBaseTimeout(validator, "consensus") * 2

\* Performance improvement invariant - timeouts improve with good performance
PerformanceImprovementInvariant ==
    \A validator \in Validators :
        performanceMetrics[validator].successRate >= MinSuccessRate + 10 =>
            \E slot \in 1..MaxSlot :
                LET adjustments == timeoutAdjustments[validator][slot]
                IN \E adj \in adjustments :
                    adj.newTimeout <= adj.oldTimeout \/ adj.reason = "performance_improvement"

\* Liveness under adaptive timeouts - consensus eventually progresses
LivenessUnderAdaptiveTimeouts ==
    \A slot \in 1..MaxSlot :
        <>(\E validator \in Validators \ ByzantineValidators :
            \E progress \in consensusProgress :
                /\ progress.slot = slot
                /\ progress.success = TRUE)

\* Safety under adaptive timeouts - no conflicting decisions
SafetyUnderAdaptiveTimeouts ==
    \A slot \in 1..MaxSlot :
        \A v1, v2 \in Validators \ ByzantineValidators :
            \A p1, p2 \in consensusProgress :
                /\ p1.slot = slot /\ p2.slot = slot
                /\ p1.success = TRUE /\ p2.success = TRUE
                => p1 = p2  \* Same consensus decision

\* Timeout convergence property - timeouts eventually stabilize
TimeoutConvergenceProperty ==
    \A validator \in Validators :
        networkConditions[validator].stability = "stable" =>
            <>(\A slot \in 1..MaxSlot :
                LET recentAdjustments == {adj \in timeoutAdjustments[validator][slot] :
                                        adj.timestamp >= clock - 5}
                IN Cardinality(recentAdjustments) <= 1)

\* Adaptive efficiency property - adaptations improve performance
AdaptiveEfficiencyProperty ==
    \A validator \in Validators :
        \A slot \in 1..MaxSlot :
            LET adjustments == timeoutAdjustments[validator][slot]
                recentAdjustments == {adj \in adjustments : adj.timestamp >= clock - 10}
            IN Cardinality(recentAdjustments) > 0 =>
                <>(\E adj \in recentAdjustments : adj.effectiveness >= 70)

----------------------------------------------------------------------------
(* Initialization *)

Init ==
    /\ clock = 0
    /\ adaptiveTimeouts = [v \in Validators |-> [s \in 1..MaxSlot |-> BaseConsensusTimeout]]
    /\ timeoutHistory = [v \in Validators |-> [s \in 1..MaxSlot |-> {}]]
    /\ networkConditions = [v \in Validators |-> [latency |-> Delta,
                                                 jitter |-> 0,
                                                 packetLoss |-> 0,
                                                 bandwidth |-> 10000,
                                                 congestion |-> 0,
                                                 stability |-> "stable"]]
    /\ performanceMetrics = [v \in Validators |-> [successRate |-> 100,
                                                  averageLatency |-> Delta,
                                                  timeoutCount |-> 0,
                                                  recoveryTime |-> 0,
                                                  consensusDelay |-> 0]]
    /\ timeoutAdjustments = [v \in Validators |-> [s \in 1..MaxSlot |-> {}]]
    /\ consensusProgress = {}
    /\ partitionDetection = [v \in Validators |-> [detected |-> FALSE,
                                                  startTime |-> 0,
                                                  severity |-> "none",
                                                  affectedValidators |-> {},
                                                  recoveryEstimate |-> 0]]
    /\ gstEstimation = [v \in Validators |-> GST]

----------------------------------------------------------------------------
(* Next State Relation *)

Next ==
    \/ UpdateNetworkConditions /\ UNCHANGED <<adaptiveTimeouts, timeoutHistory, performanceMetrics,
                                             timeoutAdjustments, consensusProgress, partitionDetection, gstEstimation, clock>>
    \/ UpdatePartitionDetection /\ UNCHANGED <<adaptiveTimeouts, timeoutHistory, networkConditions, performanceMetrics,
                                              timeoutAdjustments, consensusProgress, gstEstimation, clock>>
    \/ UpdateGSTEstimation /\ UNCHANGED <<adaptiveTimeouts, timeoutHistory, networkConditions, performanceMetrics,
                                         timeoutAdjustments, consensusProgress, partitionDetection, clock>>
    \/ UpdatePerformanceMetrics /\ UNCHANGED <<adaptiveTimeouts, timeoutHistory, networkConditions,
                                              timeoutAdjustments, consensusProgress, partitionDetection, gstEstimation, clock>>
    \/ \E validator \in Validators, slot \in 1..MaxSlot, timeoutType \in {"consensus", "voting", "finalization"}, reason \in STRING :
        AdjustTimeout(validator, slot, timeoutType, reason)
    \/ \E validator \in Validators, slot \in 1..MaxSlot, result \in {"success", "timeout", "failure"}, latency, recoveryTime \in Nat :
        RecordTimeoutEvent(validator, slot, result, latency, recoveryTime)
    \/ \E slot \in 1..MaxSlot, delay \in Nat, success \in BOOLEAN :
        UpdateConsensusProgress(slot, delay, success)
    \/ \E validator \in Validators, slot \in 1..MaxSlot, operation \in {"notarization", "finalization", "skip"}, success \in BOOLEAN, latency \in Nat :
        TriggerVotorTimeoutAdaptation(validator, slot, operation, success, latency)
    \/ clock' = clock + 1 /\ UNCHANGED <<adaptiveTimeouts, timeoutHistory, networkConditions, performanceMetrics,
                                        timeoutAdjustments, consensusProgress, partitionDetection, gstEstimation>>

----------------------------------------------------------------------------
(* Specification *)

Spec == Init /\ [][Next]_adaptiveTimeoutVars

----------------------------------------------------------------------------
(* Type Invariant *)

TypeInvariant ==
    /\ adaptiveTimeouts \in [Validators -> [1..MaxSlot -> Nat]]
    /\ timeoutHistory \in [Validators -> [1..MaxSlot -> SUBSET [result: STRING, latency: Nat, recoveryTime: Nat, timestamp: Nat]]]
    /\ networkConditions \in [Validators -> NetworkCondition]
    /\ performanceMetrics \in [Validators -> PerformanceMetric]
    /\ timeoutAdjustments \in [Validators -> [1..MaxSlot -> SUBSET TimeoutAdjustment]]
    /\ consensusProgress \in SUBSET [slot: 1..MaxSlot, delay: Nat, success: BOOLEAN, timestamp: Nat]
    /\ partitionDetection \in [Validators -> PartitionState]
    /\ gstEstimation \in [Validators -> Nat]
    /\ clock \in Nat

----------------------------------------------------------------------------
(* Helper Functions *)

Min(a, b) == IF a < b THEN a ELSE b
Max(a, b) == IF a > b THEN a ELSE b

============================================================================