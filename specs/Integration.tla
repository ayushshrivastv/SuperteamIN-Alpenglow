---------------------------- MODULE Integration ----------------------------
(***************************************************************************)
(* Integration specification combining all Alpenglow components for       *)
(* comprehensive system verification and cross-component interactions.    *)
(***************************************************************************)

EXTENDS Integers, FiniteSets, Sequences, TLC

\* Import all component specifications
INSTANCE Alpenglow
INSTANCE Votor
INSTANCE Rotor
INSTANCE Network
INSTANCE Types
INSTANCE Stake
INSTANCE Utils

----------------------------------------------------------------------------
(* Integration State *)

VARIABLES
    \* Integrated system state
    systemState,          \* Overall system state
    componentHealth,      \* Health status of each component
    interactionLog,       \* Log of cross-component interactions
    performanceMetrics,   \* System-wide performance metrics
    integrationErrors     \* Integration-specific errors

integrationVars == <<systemState, componentHealth, interactionLog,
                     performanceMetrics, integrationErrors>>

----------------------------------------------------------------------------
(* Integration Type Definitions *)

SystemStates == {"initializing", "running", "degraded", "recovering", "halted"}

ComponentHealth == [
    votor: {"healthy", "degraded", "failed"},
    rotor: {"healthy", "degraded", "failed"},
    network: {"healthy", "partitioned", "congested", "failed"},
    crypto: {"healthy", "slow", "failed"}
]

InteractionType == [
    source: {"votor", "rotor", "network"},
    target: {"votor", "rotor", "network"},
    type: {"request", "response", "broadcast", "error"},
    timestamp: Nat
]

PerformanceMetric == [
    throughput: Nat,           \* Blocks per second
    latency: Nat,              \* Average finalization time
    bandwidth: Nat,            \* Network usage
    certificateRate: Nat,      \* Certificates per slot
    repairRate: Nat           \* Repair requests per slot
]

----------------------------------------------------------------------------
(* Integration Invariants *)

TypeInvariantIntegration ==
    /\ systemState \in SystemStates
    /\ componentHealth \in [votor: {"healthy","degraded","failed"},
                          rotor: {"healthy","degraded","failed"},
                          network: {"healthy","partitioned","congested","failed"},
                          crypto: {"healthy","slow","failed"}]
    /\ interactionLog \in Seq(InteractionType)
    /\ performanceMetrics \in PerformanceMetric
    /\ integrationErrors \in SUBSET STRING

\* Component consistency invariant
ComponentConsistency ==
    \* If Votor is failed, system cannot be running normally
    /\ componentHealth.votor = "failed" => systemState \in {"degraded", "halted", "recovering"}
    \* If network is failed, both Votor and Rotor are affected
    /\ componentHealth.network = "failed" =>
        /\ componentHealth.votor \in {"degraded", "failed"}
        /\ componentHealth.rotor \in {"degraded", "failed"}
        /\ systemState \in {"degraded", "halted", "recovering"}
    \* If crypto is failed, consensus cannot proceed
    /\ componentHealth.crypto = "failed" =>
        /\ componentHealth.votor = "failed"
        /\ systemState \in {"halted", "recovering"}
    \* Network partitions affect system state
    /\ componentHealth.network = "partitioned" =>
        /\ systemState \in {"degraded", "recovering"}
        /\ performanceMetrics.throughput <= performanceMetrics.throughput \div 2
    \* Rotor failure affects block propagation
    /\ componentHealth.rotor = "failed" =>
        /\ systemState \in {"degraded", "halted", "recovering"}
        /\ performanceMetrics.repairRate > MaxBlocks \div 2
    \* System state consistency with component health
    /\ systemState = "running" =>
        /\ componentHealth.votor \in {"healthy", "degraded"}
        /\ componentHealth.crypto = "healthy"
        /\ componentHealth.network \in {"healthy", "congested"}
    /\ systemState = "halted" =>
        \/ componentHealth.votor = "failed"
        \/ componentHealth.crypto = "failed"
        \/ componentHealth.network = "failed"

\* Cross-component safety
CrossComponentSafety ==
    \* Votor certificates must be propagated by Rotor
    /\ \A view \in DOMAIN Alpenglow!votorGeneratedCerts :
        \A cert \in Alpenglow!votorGeneratedCerts[view] :
            \* Certificate blocks must be available in Rotor for propagation
            /\ cert.block \in DOMAIN Alpenglow!rotorBlockShreds
            \* Certificate must be deliverable through network
            /\ \E msg \in Alpenglow!networkMessageQueue :
                /\ msg.type = "block"
                /\ msg.payload = cert.block
    \* Network must deliver all protocol messages within bounds
    /\ \A msg \in Alpenglow!messages :
        \* Messages sent before GST + Delta must be delivered
        /\ (msg.timestamp <= Network!GST /\ Alpenglow!clock > Network!GST) =>
            \/ \E v \in Alpenglow!Validators : msg \in Alpenglow!networkMessageBuffer[v]
            \/ msg.recipient \in Alpenglow!byzantineValidators
    \* Component health consistency with actual state
    /\ componentHealth.votor = "healthy" =>
        /\ \A v \in Alpenglow!honestValidators :
            Alpenglow!votorView[v] <= Votor!MaxView
        /\ Cardinality(DOMAIN Alpenglow!votorGeneratedCerts) > 0
    /\ componentHealth.rotor = "healthy" =>
        /\ Cardinality(DOMAIN Alpenglow!rotorBlockShreds) > 0
        /\ \A block \in DOMAIN Alpenglow!rotorBlockShreds :
            Cardinality(Alpenglow!rotorBlockShreds[block]) >= Rotor!K
    /\ componentHealth.network = "healthy" =>
        /\ Alpenglow!networkPartitions = {}
        /\ Cardinality(Alpenglow!networkMessageQueue) < Network!NetworkCapacity
    \* No conflicting states between components
    /\ ~(componentHealth.votor = "healthy" /\ componentHealth.network = "failed")
    /\ ~(componentHealth.rotor = "healthy" /\ componentHealth.network = "failed")

\* Integration performance bounds
PerformanceBounds ==
    /\ performanceMetrics.throughput <= Types!MaxBlockSize * Rotor!N
    /\ performanceMetrics.latency >= Network!Delta
    /\ performanceMetrics.bandwidth <= Network!NetworkCapacity
    /\ performanceMetrics.certificateRate <= Types!MaxSlot
    /\ performanceMetrics.repairRate <= Rotor!MaxBlocks * Rotor!MaxRetries

----------------------------------------------------------------------------
(* Integration Initial State *)

InitIntegration ==
    /\ systemState = "initializing"
    /\ componentHealth = [votor |-> "healthy", rotor |-> "healthy",
                          network |-> "healthy", crypto |-> "healthy"]
    /\ interactionLog = <<>>
    /\ performanceMetrics = [throughput |-> 0, latency |-> 0, bandwidth |-> 0,
                            certificateRate |-> 0, repairRate |-> 0]
    /\ integrationErrors = {}

----------------------------------------------------------------------------
(* Integration Actions *)

\* System initialization complete
SystemInitialized ==
    /\ systemState = "initializing"
    /\ Alpenglow!Init  \* All components initialized
    /\ systemState' = "running"
    /\ UNCHANGED <<componentHealth, interactionLog, performanceMetrics, integrationErrors>>

\* Votor-Rotor interaction
VotorRotorInteraction ==
    /\ systemState = "running"
    /\ \E v \in Validators :
        \E view \in DOMAIN Alpenglow!votorVotedBlocks[v] :
            \E block \in Alpenglow!votorVotedBlocks[v][view] :
        /\ \E cert \in Alpenglow!votorGeneratedCerts[view] :
            /\ cert.block = block
            \* Ensure Rotor has the block for propagation
            /\ block \in DOMAIN Alpenglow!rotorBlockShreds
            \* Verify certificate meets stake requirements
            /\ cert.stake >= Votor!FastPathStake \/ cert.stake >= Votor!SlowPathStake
            \* Update Rotor state to reflect certificate availability
            /\ Alpenglow!rotorBlockShreds' = [Alpenglow!rotorBlockShreds EXCEPT
                ![block] = @ \cup {[index |-> i, data |-> cert] : i \in 1..Rotor!N}]
            \* Log the successful interaction
            /\ interactionLog' = Append(interactionLog,
                [source |-> "votor", target |-> "rotor",
                 type |-> "request", timestamp |-> Alpenglow!clock])
    /\ UNCHANGED <<systemState, componentHealth, performanceMetrics, integrationErrors>>

\* Network-Component interaction
NetworkComponentInteraction ==
    /\ systemState \in {"running", "degraded"}
    /\ \E msg \in Alpenglow!networkMessageQueue :
        /\ msg.type \in {"vote", "block", "shred", "repair"}
        /\ LET target == IF msg.type \in {"vote", "block"} THEN "votor"
                        ELSE "rotor"
           IN
           \* Process message delivery based on type
           /\ CASE msg.type = "vote" ->
                /\ msg.recipient \in Alpenglow!Validators
                /\ Alpenglow!votorReceivedVotes' = [Alpenglow!votorReceivedVotes EXCEPT
                    ![msg.recipient] = @ \cup {[block |-> msg.payload.block,
                                                 view |-> msg.payload.view,
                                                 validator |-> msg.payload.validator,
                                                 signature |-> msg.payload.signature]}]
                /\ Alpenglow!networkMessageBuffer' = [Alpenglow!networkMessageBuffer EXCEPT
                    ![msg.recipient] = @ \cup {msg}]
              [] msg.type = "block" ->
                /\ Alpenglow!rotorDeliveredBlocks' = Alpenglow!rotorDeliveredBlocks \cup {msg.payload}
                /\ Alpenglow!networkMessageBuffer' = [Alpenglow!networkMessageBuffer EXCEPT
                    ![msg.recipient] = @ \cup {msg}]
              [] msg.type = "shred" ->
                /\ msg.payload.block \in DOMAIN Alpenglow!rotorBlockShreds
                /\ Alpenglow!rotorBlockShreds' = [Alpenglow!rotorBlockShreds EXCEPT
                    ![msg.payload.block] = @ \cup {msg.payload}]
                /\ Alpenglow!networkMessageBuffer' = [Alpenglow!networkMessageBuffer EXCEPT
                    ![msg.recipient] = @ \cup {msg}]
              [] msg.type = "repair" ->
                /\ Alpenglow!rotorRepairRequests' = Alpenglow!rotorRepairRequests \cup {msg.payload}
                /\ Alpenglow!networkMessageBuffer' = [Alpenglow!networkMessageBuffer EXCEPT
                    ![msg.recipient] = @ \cup {msg}]
           \* Remove processed message from queue
           /\ Alpenglow!networkMessageQueue' = Alpenglow!networkMessageQueue \ {msg}
           \* Log the successful delivery
           /\ interactionLog' = Append(interactionLog,
               [source |-> "network", target |-> target,
                type |-> "response", timestamp |-> Alpenglow!clock])
    /\ UNCHANGED <<systemState, componentHealth, performanceMetrics, integrationErrors>>

\* Component failure detection
ComponentFailure ==
    /\ systemState \in {"running", "degraded"}
    /\ \/ \* Votor failure: excessive view changes or no progress
          (\E v \in Alpenglow!honestValidators :
            Alpenglow!votorView[v] > Votor!MaxView \/
            Alpenglow!clock > Network!GST /\
             Cardinality(DOMAIN Alpenglow!votorGeneratedCerts) = 0))
          /\ componentHealth' = [componentHealth EXCEPT !.votor = "failed"]
          /\ integrationErrors' = integrationErrors \cup {"votor_timeout", "votor_view_overflow"}
       \/ \* Rotor failure: no blocks propagated or excessive repair requests
          (Cardinality(DOMAIN Alpenglow!rotorBlockShreds) = 0 /\ Alpenglow!clock > Network!GST)
          \/ (Cardinality(Alpenglow!rotorRepairRequests) > Rotor!MaxBlocks * Rotor!MaxRetries)
          /\ componentHealth' = [componentHealth EXCEPT !.rotor = "failed"]
          /\ integrationErrors' = integrationErrors \cup {"rotor_no_blocks", "rotor_excessive_repairs"}
       \/ \* Network failure: persistent partitions or message queue overflow
          ((Alpenglow!networkPartitions # {} /\ Alpenglow!clock > Network!GST + Network!PartitionTimeout)
           \/ Cardinality(Alpenglow!networkMessageQueue) > Network!NetworkCapacity)
          /\ componentHealth' = [componentHealth EXCEPT !.network =
              IF Alpenglow!networkPartitions # {} THEN "partitioned" ELSE "congested"]
          /\ integrationErrors' = integrationErrors \cup {"network_partition", "network_congestion"}
       \/ \* Crypto failure: signature verification failures
          (\E cert \in UNION {Alpenglow!votorGeneratedCerts[view] : view \in DOMAIN Alpenglow!votorGeneratedCerts} :
            ~Types!ValidBLSAggregate(cert.signature, cert.signers))
          /\ componentHealth' = [componentHealth EXCEPT !.crypto = "failed"]
          /\ integrationErrors' = integrationErrors \cup {"crypto_verification_failure"}
    /\ systemState' = CASE \E c \in {"votor", "crypto"} : componentHealth'[c] = "failed" -> "halted"
                      [] componentHealth'.network = "partitioned" -> "degraded"
                      [] \E c \in {"rotor", "network"} : componentHealth'[c] \in {"failed", "congested"} -> "degraded"
                      [] OTHER -> systemState
    /\ UNCHANGED <<interactionLog, performanceMetrics>>

\* System recovery attempt
SystemRecovery ==
    /\ systemState \in {"degraded", "halted"}
    /\ Alpenglow!clock > Network!GST
    /\ \* Recovery conditions based on actual protocol state
       /\ Alpenglow!networkPartitions = {}  \* Network healed
       /\ Cardinality(Alpenglow!networkMessageQueue) < Network!NetworkCapacity \div 2  \* Queue drained
       /\ \A v \in Alpenglow!honestValidators : Alpenglow!votorView[v] <= Votor!MaxView  \* Views stabilized
       /\ Cardinality(Alpenglow!rotorRepairRequests) < Rotor!MaxBlocks  \* Repairs manageable
    /\ \* Gradual component health recovery based on actual state
       componentHealth' = [
           votor |-> IF \E view \in DOMAIN Alpenglow!votorGeneratedCerts :
                        Alpenglow!votorGeneratedCerts[view] # {}
                     THEN "healthy" ELSE "degraded",
           rotor |-> IF Cardinality(DOMAIN Alpenglow!rotorBlockShreds) > 0
                     THEN "healthy" ELSE "degraded",
           network |-> IF Alpenglow!networkPartitions = {} /\
                          Cardinality(Alpenglow!networkMessageQueue) < Network!NetworkCapacity \div 4
                       THEN "healthy" ELSE "degraded",
           crypto |-> IF \A cert \in UNION {Alpenglow!votorGeneratedCerts[view] :
                                           view \in DOMAIN Alpenglow!votorGeneratedCerts} :
                         Types!ValidBLSAggregate(cert.signature, cert.signers)
                      THEN "healthy" ELSE "degraded"
       ]
    /\ systemState' = IF \A c \in {"votor", "rotor", "network", "crypto"} :
                         componentHealth'[c] = "healthy"
                      THEN "running"
                      ELSE "recovering"
    /\ \* Clear only resolved errors
       integrationErrors' = {error \in integrationErrors :
           \/ (error = "votor_timeout" /\ componentHealth'.votor # "healthy")
           \/ (error = "rotor_no_blocks" /\ componentHealth'.rotor # "healthy")
           \/ (error = "network_partition" /\ componentHealth'.network # "healthy")
           \/ (error = "crypto_verification_failure" /\ componentHealth'.crypto # "healthy")}
    /\ \* Log recovery attempt
       interactionLog' = Append(interactionLog,
           [source |-> "system", target |-> "all",
            type |-> "recovery", timestamp |-> Alpenglow!clock])
    /\ UNCHANGED <<performanceMetrics>>

\* Performance metric update
UpdatePerformanceMetrics ==
    /\ systemState = "running"
    /\ LET \* Calculate actual finalized blocks with proper timing
           finalizedBlocks == {slot \in DOMAIN Alpenglow!finalizedBlocks :
                              Alpenglow!finalizedBlocks[slot] # {}}
           finalizedCount == Cardinality(finalizedBlocks)
           \* Calculate weighted average latency based on finalization times
           totalLatency == LET finalizationTimes == {Alpenglow!clock - slot * Types!SlotDuration :
                                                   slot \in finalizedBlocks}
                          IN IF finalizationTimes # {}
                             THEN Utils!Sum(finalizationTimes)
                             ELSE 0
           avgLatency == IF finalizedCount > 0
                        THEN totalLatency \div finalizedCount
                        ELSE 0
           \* Throughput in blocks per time unit (normalized)
           timeWindow == IF Alpenglow!clock > Types!SlotDuration THEN Alpenglow!clock ELSE Types!SlotDuration
           throughput == IF timeWindow > 0
                        THEN (finalizedCount * Types!SlotDuration) \div timeWindow
                        ELSE 0
           \* Bandwidth calculation including all message types and sizes
           messageSize == [vote |-> 96, block |-> Types!MaxBlockSize, shred |-> Types!MaxBlockSize \div Rotor!K, repair |-> 32]
           totalBandwidth == LET msgTypes == {"vote", "block", "shred", "repair"}
                            msgCounts == [t \in msgTypes |->
                                        Cardinality({msg \in Alpenglow!networkMessageQueue : msg.type = t})]
                            IN Utils!Sum({msgCounts[t] * messageSize[t] : t \in msgTypes})
           bandwidth == totalBandwidth
           \* Certificate rate per slot with quality weighting
           activeCerts == {view \in DOMAIN Alpenglow!votorGeneratedCerts :
                          Alpenglow!votorGeneratedCerts[view] # {}}
           certRate == IF Alpenglow!currentSlot > 0
                      THEN Cardinality(activeCerts) \div Alpenglow!currentSlot
                      ELSE 0
           \* Repair rate indicating network health
           activeRepairs == Cardinality(Alpenglow!rotorRepairRequests)
           repairRate == IF Alpenglow!currentSlot > 0
                        THEN activeRepairs \div Alpenglow!currentSlot
                        ELSE 0
       IN
       performanceMetrics' = [throughput |-> throughput,
                              latency |-> avgLatency,
                              bandwidth |-> bandwidth,
                              certificateRate |-> certRate,
                              repairRate |-> repairRate]
    /\ UNCHANGED <<systemState, componentHealth, interactionLog, integrationErrors>>

----------------------------------------------------------------------------
(* Integration Next State *)

NextIntegration ==
    \/ SystemInitialized
    \/ VotorRotorInteraction
    \/ NetworkComponentInteraction
    \/ ComponentFailure
    \/ SystemRecovery
    \/ UpdatePerformanceMetrics
    /\ Alpenglow!Next  \* Original system actions

----------------------------------------------------------------------------
(* Integration Properties *)

\* Eventually the system initializes and runs
EventuallyRunning ==
    <>(systemState = "running")

\* System recovers from degraded states
RecoveryProperty ==
    [](systemState = "degraded" => <>(systemState \in {"running", "recovering"}))

\* No permanent failures under assumptions
NoPermamentFailure ==
    []((Alpenglow!clock > Network!GST /\ Alpenglow!networkPartitions = {}) =>
       <>(systemState \in {"running", "recovering"}))

\* Performance degrades gracefully
GracefulPerformanceDegradation ==
    [](componentHealth.votor = "degraded" =>
       performanceMetrics.throughput <= performanceMetrics'.throughput * 2)

\* Cross-component liveness
CrossComponentLiveness ==
    []<>(\E interaction \in interactionLog :
        interaction.source = "votor" /\ interaction.target = "rotor")

\* Integration efficiency
IntegrationEfficiency ==
    [](systemState = "running" =>
       performanceMetrics.throughput >= Types!MaxBlockSize \div (2 * Network!Delta))

----------------------------------------------------------------------------
(* Integration Specification *)

SpecIntegration ==
    /\ InitIntegration
    /\ [][NextIntegration]_<<vars, integrationVars>>
    /\ WF_vars(NextIntegration)

\* Properties to verify
THEOREM IntegrationCorrectness ==
    SpecIntegration =>
        /\ []TypeInvariantIntegration
        /\ []ComponentConsistency
        /\ []CrossComponentSafety
        /\ []PerformanceBounds
        /\ EventuallyRunning
        /\ RecoveryProperty
        /\ NoPermamentFailure
        /\ CrossComponentLiveness

============================================================================
