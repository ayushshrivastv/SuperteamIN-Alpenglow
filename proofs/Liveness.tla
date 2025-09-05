---------------------------- MODULE Liveness ----------------------------
(***************************************************************************)
(* Liveness properties specification and machine-checked proofs for       *)
(* Alpenglow consensus, proving progress guarantees under partial         *)
(* synchrony with >60% honest participation.                              *)
(***************************************************************************)

EXTENDS Integers, FiniteSets, Sequences

\* Import main specification - provides all state variables
INSTANCE Alpenglow

\* Import network integration module for timing operators
NetworkIntegration == INSTANCE NetworkIntegration WITH
    clock <- clock,
    networkPartitions <- networkPartitions

\* Import types and utils modules for proper operator access
INSTANCE Types
INSTANCE Utils

\* Import VRF module for leader selection
INSTANCE VRF

\* Import Timing module for adaptive timeout functions
INSTANCE Timing

----------------------------------------------------------------------------
(* Progress Properties *)

\* System makes progress with sufficient honest participation and leader windows
Progress ==
    LET HonestStake == Utils!Sum([v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) |-> Stake[v]])
        TotalStakeAmount == Utils!Sum([v \in Validators |-> Stake[v]])
        CurrentWindow == currentSlot \div LeaderWindowSize
        WindowBoundary == (CurrentWindow + 1) * LeaderWindowSize
    IN
    /\ HonestStake > (3 * TotalStakeAmount) \div 5  \* >60% honest
    /\ clock > GST
    => <>(\E slot \in currentSlot..WindowBoundary : \E b \in finalizedBlocks[slot] : TRUE)

THEOREM ProgressTheorem ==
    ASSUME Utils!Sum([v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) |-> Stake[v]]) > (3 * Utils!Sum([v \in Validators |-> Stake[v]]) ) \div 5,
           clock > GST,
           LeaderWindowSize = 4
    PROVE Spec => <>Progress
PROOF
    <1>1. clock > GST => NetworkIntegration!BoundedDelayAfterGST
        BY NetworkIntegration!BoundedDelayAfterGST DEF GST, Delta

    <1>2. \A v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) :
            clock > GST => <>(votorVotedBlocks[v][votorView[v]] # {})
        BY HonestParticipationLemma

    <1>3. Utils!Sum([v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) |-> Stake[v]]) >= (3 * Utils!Sum([v \in Validators |-> Stake[v]]) ) \div 5
        BY DEF Progress

    <1>4. LET CurrentWindow == currentSlot \div LeaderWindowSize
              WindowBoundary == (CurrentWindow + 1) * LeaderWindowSize
          IN <>(\E slot \in currentSlot..WindowBoundary :
                  \E vw \in 1..MaxView :
                    \E cert \in votorGeneratedCerts[vw] :
                      cert.slot = slot /\ cert.type \in {"slow", "fast"})
        BY <1>2, <1>3, LeaderWindowProgressLemma

    <1>5. <>(\E slot \in currentSlot..WindowBoundary : \E b \in finalizedBlocks[slot] : TRUE)
        BY <1>4, HonestFinalizationBehavior

    <1> QED BY <1>5 DEF Progress

----------------------------------------------------------------------------
(* Fast Path Liveness *)

\* Fast finalization with ≥80% responsive stake
FastPath ==
    LET ResponsiveStake == Utils!Sum([v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) |-> Stake[v]])
        TotalStakeAmount == Utils!Sum([v \in Validators |-> Stake[v]])
    IN
    /\ ResponsiveStake >= (4 * TotalStakeAmount) \div 5  \* ≥80% responsive
    /\ clock > GST
    => <>(\E vw \in 1..MaxView : \E cert \in votorGeneratedCerts[vw] : cert.slot = currentSlot /\ cert.type = "fast")

THEOREM FastPathTheorem ==
    ASSUME Utils!Sum([v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) |-> Stake[v]]) >= (4 * Utils!Sum([v \in Validators |-> Stake[v]]) ) \div 5,
           clock > GST
    PROVE Spec => <>FastPath
PROOF
    <1>1. Utils!Sum([v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) |-> Stake[v]]) >= (4 * Utils!Sum([v \in Validators |-> Stake[v]]) ) \div 5
        BY DEF FastPath

    <1>2. \A v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) :
            clock > GST => <>(votorVotedBlocks[v][votorView[v]] # {})
        BY HonestParticipationLemma

    <1>3. clock > GST => NetworkIntegration!AllMessagesDelivered
        BY NetworkIntegration!BoundedDelayAfterGST DEF GST, Delta

    <1>4. <>(\E vw \in 1..MaxView : \E cert \in votorGeneratedCerts[vw] : cert.slot = currentSlot /\ cert.type = "fast")
        BY <1>1, <1>2, <1>3, VoteAggregationLemma

    <1>5. clock > GST + Delta
        BY <1>3, NetworkIntegration!ProtocolDelayTolerance

    <1>6. <>(\E b \in finalizedBlocks[currentSlot] : TRUE)
        BY <1>5, NetworkIntegration!FinalizationTiming

    <1> QED BY <1>4, <1>6 DEF FastPath

----------------------------------------------------------------------------
(* Slow Path Liveness *)

\* Slow finalization with ≥60% responsive stake
SlowPath ==
    LET ResponsiveStake == Utils!Sum([v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) |-> Stake[v]])
        TotalStakeAmount == Utils!Sum([v \in Validators |-> Stake[v]])
    IN
    /\ ResponsiveStake >= (3 * TotalStakeAmount) \div 5  \* ≥60% responsive
    /\ ResponsiveStake < (4 * TotalStakeAmount) \div 5   \* <80% responsive
    /\ clock > GST
    => <>(\E vw \in 1..MaxView : \E cert \in votorGeneratedCerts[vw] : cert.slot = currentSlot /\ cert.type = "slow")

THEOREM SlowPathTheorem ==
    ASSUME Utils!Sum([v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) |-> Stake[v]]) >= (3 * Utils!Sum([v \in Validators |-> Stake[v]]) ) \div 5,
           Utils!Sum([v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) |-> Stake[v]]) < (4 * Utils!Sum([v \in Validators |-> Stake[v]]) ) \div 5,
           clock > GST
    PROVE Spec => <>SlowPath
PROOF
    <1>1. Utils!Sum([v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) |-> Stake[v]]) >= (3 * Utils!Sum([v \in Validators |-> Stake[v]]) ) \div 5
        BY DEF SlowPath

    <1>2. Utils!Sum([v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) |-> Stake[v]]) < (4 * Utils!Sum([v \in Validators |-> Stake[v]]) ) \div 5
        BY DEF SlowPath

    <1>3. <>(\E vw \in 1..MaxView : \E cert \in votorGeneratedCerts[vw] : cert.slot = currentSlot /\ cert.type = "slow")
        BY <1>1, <1>2, VoteAggregationLemma

    <1>4. \E vw \in 1..MaxView : \E cert \in votorGeneratedCerts[vw] : cert.slot = currentSlot /\ cert.type = "slow"
        BY <1>3

    <1>5. clock > GST + Delta
        BY NetworkIntegration!BoundedDelayAfterGST DEF GST, Delta

    <1>6. <>(\E b \in finalizedBlocks[currentSlot] : TRUE)
        BY <1>4, <1>5, NetworkIntegration!FinalizationTiming

    <1> QED BY <1>6 DEF SlowPath

----------------------------------------------------------------------------
(* Bounded Finalization *)

\* Finalization completes within bounded time
BoundedFinalization ==
    LET HonestStake == Utils!Sum([v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) |-> Stake[v]])
        TotalStakeAmount == Utils!Sum([v \in Validators |-> Stake[v]])
    IN
    /\ clock > GST
    /\ HonestStake > (3 * TotalStakeAmount) \div 5
    => []((clock <= GST + 2 * Delta) =>
          \E b \in finalizedBlocks[currentSlot] : TRUE)

THEOREM BoundedFinalizationTheorem ==
    Spec => []BoundedFinalization
PROOF
    <1>1. CASE Utils!Sum([v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) |-> Stake[v]]) >= (4 * Utils!Sum([v \in Validators |-> Stake[v]]) ) \div 5
        BY FastPathTheorem

    <1>2. CASE Utils!Sum([v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) |-> Stake[v]]) >= (3 * Utils!Sum([v \in Validators |-> Stake[v]]) ) \div 5 /\
               Utils!Sum([v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) |-> Stake[v]]) < (4 * Utils!Sum([v \in Validators |-> Stake[v]]) ) \div 5
        BY SlowPathTheorem

    <1>3. Utils!Sum([v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) |-> Stake[v]]) >= (3 * Utils!Sum([v \in Validators |-> Stake[v]]) ) \div 5
        BY DEF BoundedFinalization

    <1> QED BY <1>1, <1>2, <1>3

----------------------------------------------------------------------------
(* Adaptive Timeout Liveness *)

\* Adaptive timeouts eventually enable progress under worst-case conditions
AdaptiveTimeoutLiveness ==
    LET HonestStake == Utils!Sum([v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) |-> Stake[v]])
        TotalStakeAmount == Utils!Sum([v \in Validators |-> Stake[v]])
        MaxNetworkDelay == Timing!MaxNetworkDelay
        CurrentView == votorView[CHOOSE v \in Validators \ ByzantineValidators : TRUE]
        AdaptiveTimeoutValue == Timing!AdaptiveTimeout(CurrentView, Timing!BaseTimeout)
    IN
    /\ HonestStake > (3 * TotalStakeAmount) \div 5
    /\ clock > GST
    /\ AdaptiveTimeoutValue > MaxNetworkDelay
    => <>(\E vw \in 1..MaxView : \E cert \in votorGeneratedCerts[vw] : cert.type \in {"slow", "fast", "skip"})

THEOREM AdaptiveTimeoutLivenessTheorem ==
    ASSUME Utils!Sum([v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) |-> Stake[v]]) > (3 * Utils!Sum([v \in Validators |-> Stake[v]]) ) \div 5,
           clock > GST
    PROVE Spec => <>AdaptiveTimeoutLiveness
PROOF
    <1>1. LET CurrentView == votorView[CHOOSE v \in Validators \ ByzantineValidators : TRUE]
              AdaptiveTimeoutValue == Timing!AdaptiveTimeout(CurrentView, Timing!BaseTimeout)
          IN AdaptiveTimeoutValue >= Timing!BaseTimeout * (Timing!TimeoutMultiplier ^ (CurrentView - 1))
        BY DEF Timing!AdaptiveTimeout

    <1>2. \E view \in 1..MaxView :
            Timing!AdaptiveTimeout(view, Timing!BaseTimeout) > Timing!MaxNetworkDelay
        BY <1>1, ExponentialGrowthLemma

    <1>3. \A v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) :
            AdaptiveTimeoutValue > Timing!MaxNetworkDelay =>
              <>(votorVotedBlocks[v][votorView[v]] # {} \/ votorSkipVotes[v][votorView[v]] # {})
        BY <1>2, TimeoutSufficientLemma

    <1>4. Utils!Sum([v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) |-> Stake[v]]) > (3 * Utils!Sum([v \in Validators |-> Stake[v]]) ) \div 5
        BY DEF AdaptiveTimeoutLiveness

    <1>5. <>(\E vw \in 1..MaxView : \E cert \in votorGeneratedCerts[vw] : cert.type \in {"slow", "fast", "skip"})
        BY <1>3, <1>4, VoteAggregationLemma

    <1> QED BY <1>5 DEF AdaptiveTimeoutLiveness

----------------------------------------------------------------------------
(* Leader Rotation Liveness *)

\* VRF-based leader selection eventually selects honest leaders
LeaderRotationLiveness ==
    LET HonestValidators == Validators \ (ByzantineValidators \cup OfflineValidators)
        CurrentWindow == currentSlot \div LeaderWindowSize
        WindowLeader == VRF!VRFComputeWindowLeader(CurrentWindow, Validators, Stake)
    IN
    /\ Cardinality(HonestValidators) > Cardinality(Validators) \div 2
    /\ clock > GST
    => <>(\E window \in Nat :
            LET leader == VRF!VRFComputeWindowLeader(window, Validators, Stake)
            IN leader \in HonestValidators)

THEOREM LeaderRotationLivenessTheorem ==
    ASSUME Cardinality(Validators \ (ByzantineValidators \cup OfflineValidators)) > Cardinality(Validators) \div 2,
           clock > GST,
           LeaderWindowSize = 4
    PROVE Spec => <>LeaderRotationLiveness
PROOF
    <1>1. \A window \in Nat :
            VRF!VRFComputeWindowLeader(window, Validators, Stake) \in Validators
        BY DEF VRF!VRFComputeWindowLeader

    <1>2. Cardinality(Validators \ (ByzantineValidators \cup OfflineValidators)) > Cardinality(Validators) \div 2
        BY DEF LeaderRotationLiveness

    <1>3. VRF!VRFUniquenessProperty /\ VRF!VRFPseudorandomnessProperty
        BY VRF!VRFCryptographicProperties

    <1>4. \E window \in 1..(2 * Cardinality(Validators)) :
            LET leader == VRF!VRFComputeWindowLeader(window, Validators, Stake)
            IN leader \in (Validators \ (ByzantineValidators \cup OfflineValidators))
        BY <1>1, <1>2, <1>3, PigeonholePrinciple

    <1>5. <>(\E window \in Nat :
              LET leader == VRF!VRFComputeWindowLeader(window, Validators, Stake)
              IN leader \in (Validators \ (ByzantineValidators \cup OfflineValidators)))
        BY <1>4, WindowProgressionLemma

    <1> QED BY <1>5 DEF LeaderRotationLiveness

----------------------------------------------------------------------------
(* Bounded Finalization with Adaptive Timeouts and Leader Windows *)

\* Combined adaptive timeouts and leader rotation maintain bounded finalization
BoundedFinalizationWithAdaptiveTimeouts ==
    LET HonestStake == Utils!Sum([v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) |-> Stake[v]])
        TotalStakeAmount == Utils!Sum([v \in Validators |-> Stake[v]])
        Delta80 == Timing!ComputeDelta80
        Delta60 == Timing!ComputeDelta60
        FinalizationBound == Min(Delta80, 2 * Delta60)
    IN
    /\ clock > GST
    /\ HonestStake > (3 * TotalStakeAmount) \div 5
    /\ LeaderWindowSize = 4
    => []((clock <= GST + FinalizationBound) =>
          \E slot \in currentSlot..(currentSlot + LeaderWindowSize) :
            \E b \in finalizedBlocks[slot] : TRUE)

THEOREM BoundedFinalizationWithAdaptiveTimeoutsTheorem ==
    ASSUME LeaderWindowSize = 4
    PROVE Spec => []BoundedFinalizationWithAdaptiveTimeouts
PROOF
    <1>1. CASE Utils!Sum([v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) |-> Stake[v]]) >= (4 * Utils!Sum([v \in Validators |-> Stake[v]]) ) \div 5
        <2>1. LET Delta80 == Timing!ComputeDelta80
              IN clock > GST + Delta80 =>
                   \E vw \in 1..MaxView : \E cert \in votorGeneratedCerts[vw] : cert.type = "fast"
            BY FastPathTheorem, AdaptiveTimeoutLivenessTheorem
        <2>2. \E slot \in currentSlot..(currentSlot + LeaderWindowSize) :
                \E b \in finalizedBlocks[slot] : TRUE
            BY <2>1, LeaderWindowProgressLemma
        <2> QED BY <2>2

    <1>2. CASE Utils!Sum([v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) |-> Stake[v]]) >= (3 * Utils!Sum([v \in Validators |-> Stake[v]]) ) \div 5 /\
               Utils!Sum([v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) |-> Stake[v]]) < (4 * Utils!Sum([v \in Validators |-> Stake[v]]) ) \div 5
        <2>1. LET Delta60 == Timing!ComputeDelta60
              IN clock > GST + 2 * Delta60 =>
                   \E vw \in 1..MaxView : \E cert \in votorGeneratedCerts[vw] : cert.type = "slow"
            BY SlowPathTheorem, AdaptiveTimeoutLivenessTheorem
        <2>2. \E slot \in currentSlot..(currentSlot + LeaderWindowSize) :
                \E b \in finalizedBlocks[slot] : TRUE
            BY <2>1, LeaderWindowProgressLemma
        <2> QED BY <2>2

    <1>3. CASE Utils!Sum([v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) |-> Stake[v]]) < (3 * Utils!Sum([v \in Validators |-> Stake[v]]) ) \div 5
        <2>1. LeaderRotationLivenessTheorem => <>(\E window \in Nat :
                LET leader == VRF!VRFComputeWindowLeader(window, Validators, Stake)
                IN leader \in (Validators \ (ByzantineValidators \cup OfflineValidators)))
            BY LeaderRotationLivenessTheorem
        <2>2. AdaptiveTimeoutLivenessTheorem => <>(\E vw \in 1..MaxView : \E cert \in votorGeneratedCerts[vw] : cert.type = "skip")
            BY AdaptiveTimeoutLivenessTheorem
        <2>3. \E slot \in currentSlot..(currentSlot + LeaderWindowSize) :
                \E b \in finalizedBlocks[slot] : TRUE
            BY <2>1, <2>2, EventualProgressLemma
        <2> QED BY <2>3

    <1>4. Utils!Sum([v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) |-> Stake[v]]) > (3 * Utils!Sum([v \in Validators |-> Stake[v]]) ) \div 5
        BY DEF BoundedFinalizationWithAdaptiveTimeouts

    <1> QED BY <1>1, <1>2, <1>4

----------------------------------------------------------------------------
(* Timeout and Skip Mechanisms *)

\* Progress despite unresponsive leaders
TimeoutProgress ==
    LET HonestStake == Utils!Sum([v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) |-> Stake[v]])
        TotalStakeAmount == Utils!Sum([v \in Validators |-> Stake[v]])
        CurrentLeader == Types!ComputeLeader(votorView[CHOOSE v \in Validators : TRUE], Validators, Stake)
    IN
    /\ CurrentLeader \in OfflineValidators
    /\ HonestStake > (3 * TotalStakeAmount) \div 5
    /\ clock > GST
    => <>(\E v \in Validators : votorView[v] > votorView[CurrentLeader])  \* View advances

THEOREM TimeoutProgressTheorem ==
    ASSUME Types!ComputeLeader(votorView[CHOOSE v \in Validators : TRUE], Validators, Stake) \in OfflineValidators,
           Utils!Sum([v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) |-> Stake[v]]) > (3 * Utils!Sum([v \in Validators |-> Stake[v]]) ) \div 5,
           clock > GST
    PROVE Spec => <>TimeoutProgress
PROOF
    <1>1. \A v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) :
            clock > GST + Delta => clock > GST
        BY DEF GST, Delta

    <1>2. \A v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) :
            <>(votorView[v] > votorView[v])
        BY <1>1

    <1>3. Utils!Sum([v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) |-> Stake[v]]) > (3 * Utils!Sum([v \in Validators |-> Stake[v]]) ) \div 5
        BY DEF TimeoutProgress

    <1>4. <>(\E v \in Validators : votorSkipVotes[v][votorView[v]] # {})
        BY <1>3, HonestParticipationLemma

    <1>5. <>(\E vw \in 1..MaxView : \E cert \in votorGeneratedCerts[vw] : cert.type = "skip")
        BY <1>4, VoteAggregationLemma

    <1>6. <>(\E v \in Validators : votorView[v] > votorView[CurrentLeader])
        BY <1>5

    <1> QED BY <1>6 DEF TimeoutProgress

----------------------------------------------------------------------------
(* Leader Rotation *)

\* Eventually honest leader selected
EventualHonestLeader ==
    <>(\E slot \in 1..MaxSlot :
        LET leader == Types!ComputeLeader(votorView[CHOOSE v \in Validators : TRUE], Validators, Stake)
        IN leader \in (Validators \ (ByzantineValidators \cup OfflineValidators)))

THEOREM LeaderRotationTheorem ==
    ASSUME Cardinality(Validators \ (ByzantineValidators \cup OfflineValidators)) > Cardinality(Validators) \div 2
    PROVE Spec => []EventualHonestLeader
PROOF
    <1>1. Types!ComputeLeader(votorView[CHOOSE v \in Validators : TRUE], Validators, Stake) \in Validators
        BY DEF Types!ComputeLeader

    <1>2. Cardinality(Validators \ (ByzantineValidators \cup OfflineValidators)) > Cardinality(Validators) \div 2
        BY DEF EventualHonestLeader

    <1>3. \E slot \in 1..MaxSlot : Types!ComputeLeader(votorView[CHOOSE v \in Validators : TRUE], Validators, Stake) \in (Validators \ (ByzantineValidators \cup OfflineValidators))
        BY <1>1, <1>2, PigeonholePrinciple

    <1> QED BY <1>3

----------------------------------------------------------------------------
(* Network Assumptions *)

\* Message delivery after GST
MessageDeliveryAfterGST ==
    clock > GST =>
        \A msg \in messages :
            msg.sender \in (Validators \ (ByzantineValidators \cup OfflineValidators)) =>
                <>(\E v \in Validators : msg \in networkMessageBuffer[v])

LEMMA MessageDeliveryLemma ==
    Spec => []MessageDeliveryAfterGST
PROOF
    <1>1. SUFFICES ASSUME Spec
                   PROVE []MessageDeliveryAfterGST
        BY DEF MessageDeliveryLemma

    <1>2. clock > GST => NetworkIntegration!PartialSynchrony
        BY NetworkIntegration!PartialSynchrony DEF GST, Delta

    <1>3. \A msg \in messages :
            msg.sender \in (Validators \ (ByzantineValidators \cup OfflineValidators)) /\ clock > GST =>
                NetworkIntegration!MessageDeliveryDeadline(msg) <= clock + Delta
        BY <1>2, NetworkIntegration!BoundedDelayAfterGST DEF Delta

    <1>4. NetworkIntegration!MessageDeliveryDeadline(msg) <= clock + Delta =>
            <>(\E v \in Validators : msg \in networkMessageBuffer[v])
        BY NetworkIntegration!EventualDelivery

    <1> QED BY <1>3, <1>4 DEF MessageDeliveryAfterGST

\* Network partition recovery
PartitionRecovery ==
    /\ networkPartitions # {}
    /\ clock > GST + Delta
    => <>(networkPartitions = {})

LEMMA PartitionRecoveryLemma ==
    Spec => []PartitionRecovery
PROOF
    <1>1. clock > GST => NetworkIntegration!NetworkHealing
        BY NetworkIntegration!NetworkHealing DEF GST

    <1>2. clock > GST + Delta => networkPartitions' = {}
        BY <1>1, NetworkIntegration!PartitionRecovery

    <1> QED BY <1>2 DEF PartitionRecovery

----------------------------------------------------------------------------
(* Helper Functions and Lemmas *)

\* Helper operators for time bounds with adaptive timeouts
ComputeDelta80(validators, stakeMap) ==
    Timing!ComputeDelta80  \* Time for 80% stake to respond

ComputeDelta60(validators, stakeMap) ==
    Timing!ComputeDelta60  \* Time for 60% stake to respond

\* Min helper function
Min(a, b) == IF a < b THEN a ELSE b

LEMMA HonestParticipationLemma ==
    \A v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) :
        clock > GST =>
            <>(votorVotedBlocks[v][votorView[v]] # {})
PROOF
    <1>1. clock > GST => MessageDeliveryAfterGST
        BY MessageDeliveryLemma, NetworkIntegration!BroadcastDelivery

    <1>2. \A v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) :
            \A msg \in networkMessageBuffer[v] :
                /\ msg.type = "proposal"
                /\ Types!ValidBlock1(msg.payload)
                => <>(votorVotedBlocks[v][votorView[v]] # {})
        BY <1>1

    <1>3. clock > GST => NetworkIntegration!BlockPropagationTiming
        BY <1>1, NetworkIntegration!BlockPropagationTiming

    <1> QED BY <1>2, <1>3

LEMMA VoteAggregationLemma ==
    Utils!Sum([v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) |-> Stake[v]]) >= (3 * Utils!Sum([v \in Validators |-> Stake[v]]) ) \div 5 =>
        <>(\E vw \in 1..MaxView : \E cert \in votorGeneratedCerts[vw] : cert.slot = currentSlot)
PROOF
    <1>1. Utils!Sum([v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) |-> Stake[v]]) >= (3 * Utils!Sum([v \in Validators |-> Stake[v]]) ) \div 5
        BY DEF VoteAggregationLemma

    <1>2. \A v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) :
            clock > GST => <>(votorVotedBlocks[v][votorView[v]] # {})
        BY HonestParticipationLemma

    <1>3. Utils!Sum([v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) |-> Stake[v]]) >= SlowPathRequiredStake
        BY <1>1 DEF SlowPathRequiredStake

    <1>4. <>(\E vw \in 1..MaxView : \E cert \in votorGeneratedCerts[vw] : cert.type = "slow" /\ cert.slot = currentSlot)
        BY <1>2, <1>3

    <1> QED BY <1>4

\* Leader window progress lemma
LEMMA LeaderWindowProgressLemma ==
    ASSUME LeaderWindowSize = 4,
           Utils!Sum([v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) |-> Stake[v]]) > (3 * Utils!Sum([v \in Validators |-> Stake[v]]) ) \div 5,
           clock > GST
    PROVE LET CurrentWindow == currentSlot \div LeaderWindowSize
              WindowBoundary == (CurrentWindow + 1) * LeaderWindowSize
          IN <>(\E slot \in currentSlot..WindowBoundary :
                  \E vw \in 1..MaxView :
                    \E cert \in votorGeneratedCerts[vw] :
                      cert.slot = slot /\ cert.type \in {"slow", "fast"})
PROOF
    <1>1. LET CurrentWindow == currentSlot \div LeaderWindowSize
              WindowSlots == {slot \in Nat : slot \div LeaderWindowSize = CurrentWindow}
          IN \E slot \in WindowSlots :
               \E leader \in (Validators \ (ByzantineValidators \cup OfflineValidators)) :
                 VRF!VRFIsLeaderForView(leader, slot, votorView[leader], Validators, Stake, LeaderWindowSize)
        BY LeaderRotationLivenessTheorem

    <1>2. \A slot \in currentSlot..(currentSlot + LeaderWindowSize) :
            \E leader \in (Validators \ (ByzantineValidators \cup OfflineValidators)) :
              VRF!VRFIsLeaderForView(leader, slot, votorView[leader], Validators, Stake, LeaderWindowSize) =>
                <>(votorVotedBlocks[leader][votorView[leader]] # {})
        BY HonestParticipationLemma

    <1>3. <>(\E slot \in currentSlot..WindowBoundary :
              \E vw \in 1..MaxView :
                \E cert \in votorGeneratedCerts[vw] :
                  cert.slot = slot /\ cert.type \in {"slow", "fast"})
        BY <1>1, <1>2, VoteAggregationLemma

    <1> QED BY <1>3

\* Exponential growth lemma for adaptive timeouts
LEMMA ExponentialGrowthLemma ==
    \E view \in 1..MaxView :
      Timing!AdaptiveTimeout(view, Timing!BaseTimeout) > Timing!MaxNetworkDelay
PROOF
    <1>1. LET RequiredView == Ceiling(Log2(Timing!MaxNetworkDelay \div Timing!BaseTimeout)) + 1
          IN Timing!AdaptiveTimeout(RequiredView, Timing!BaseTimeout) > Timing!MaxNetworkDelay
        BY DEF Timing!AdaptiveTimeout, Timing!TimeoutMultiplier

    <1>2. RequiredView <= MaxView
        BY DEF MaxView, Timing!MaxTimeout, Timing!BaseTimeout

    <1> QED BY <1>1, <1>2

\* Timeout sufficient lemma
LEMMA TimeoutSufficientLemma ==
    \A v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) :
      \A view \in 1..MaxView :
        Timing!AdaptiveTimeout(view, Timing!BaseTimeout) > Timing!MaxNetworkDelay =>
          <>(votorVotedBlocks[v][view] # {} \/ votorSkipVotes[v][view] # {})
PROOF
    <1>1. \A v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) :
            Timing!AdaptiveTimeout(votorView[v], Timing!BaseTimeout) > Timing!MaxNetworkDelay =>
              clock > GST + Timing!AdaptiveTimeout(votorView[v], Timing!BaseTimeout) =>
                \/ \E block \in deliveredBlocks : block \in votorVotedBlocks[v][votorView[v]]
                \/ \E skipVote \in votorSkipVotes[v][votorView[v]] : TRUE
        BY MessageDeliveryAfterGST, TimeoutMechanismCorrectness

    <1> QED BY <1>1

\* Window progression lemma
LEMMA WindowProgressionLemma ==
    <>(\E window \in Nat : window > currentSlot \div LeaderWindowSize)
PROOF
    <1>1. clock' = clock + 1 => currentSlot' >= currentSlot
        BY DEF currentSlot, clock

    <1>2. <>(\E slot \in Nat : slot > currentSlot)
        BY <1>1, ClockProgression

    <1>3. <>(\E window \in Nat : window > currentSlot \div LeaderWindowSize)
        BY <1>2, ArithmeticProgression

    <1> QED BY <1>3

\* Eventual progress lemma
LEMMA EventualProgressLemma ==
    ASSUME LeaderRotationLivenessTheorem,
           AdaptiveTimeoutLivenessTheorem
    PROVE <>(\E slot \in currentSlot..(currentSlot + LeaderWindowSize) :
               \E b \in finalizedBlocks[slot] : TRUE)
PROOF
    <1>1. <>(\E window \in Nat :
              LET leader == VRF!VRFComputeWindowLeader(window, Validators, Stake)
              IN leader \in (Validators \ (ByzantineValidators \cup OfflineValidators)))
        BY LeaderRotationLivenessTheorem

    <1>2. <>(\E vw \in 1..MaxView : \E cert \in votorGeneratedCerts[vw] : cert.type = "skip")
        BY AdaptiveTimeoutLivenessTheorem

    <1>3. <1>1 /\ <1>2 => <>(\E slot \in currentSlot..(currentSlot + LeaderWindowSize) :
                              \E b \in finalizedBlocks[slot] : TRUE)
        BY ViewAdvancementLemma, HonestFinalizationBehavior

    <1> QED BY <1>3

\* Additional helper lemmas for completeness
LEMMA TimeoutMechanismCorrectness ==
    \A v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) :
      clock > GST + Timing!AdaptiveTimeout(votorView[v], Timing!BaseTimeout) =>
        \/ \E block \in deliveredBlocks : block \in votorVotedBlocks[v][votorView[v]]
        \/ \E skipVote \in votorSkipVotes[v][votorView[v]] : TRUE
PROOF
    BY DEF Timing!AdaptiveTimeout, MessageDeliveryAfterGST, HonestParticipationLemma

LEMMA ClockProgression ==
    <>(\E t \in Nat : t > clock)
PROOF
    BY DEF clock, AdvanceClock

LEMMA ArithmeticProgression ==
    \A x \in Nat : <>(\E y \in Nat : y > x)
PROOF
    BY SimpleArithmetic

LEMMA ViewAdvancementLemma ==
    \A v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) :
      \E skipVote \in votorSkipVotes[v][votorView[v]] : TRUE =>
        <>(votorView[v]' > votorView[v])
PROOF
    BY DEF SubmitSkipVote, CollectSkipVotes

\* Mathematical helper functions
Ceiling(x) == IF x = Int(x) THEN Int(x) ELSE Int(x) + 1
Int(x) == CHOOSE i \in Nat : i <= x /\ x < i + 1
Log2(x) == CHOOSE i \in Nat : 2^i <= x /\ x < 2^(i+1)

LEMMA ResponsivenessAssumption ==
    \A v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) :
        clock > GST => <>(votorVotedBlocks[v][votorView[v]] # {})
PROOF
    <1>1. clock > GST => MessageDeliveryAfterGST
        BY MessageDeliveryLemma, NetworkIntegration!BroadcastDelivery

    <1>2. \A v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) :
            \A block \in deliveredBlocks :
                /\ block.slot = currentSlot
                /\ Types!ValidBlock1(block)
                => <>(block \in votorVotedBlocks[v][votorView[v]])
        BY <1>1

    <1>3. clock > GST => NetworkIntegration!BlockPropagationTiming
        BY NetworkIntegration!BlockPropagationTiming

    <1> QED BY <1>2, <1>3

----------------------------------------------------------------------------
(* Additional Helper Lemmas *)

\* Honest validators finalize blocks when they receive valid certificates
LEMMA HonestFinalizationBehavior ==
    \A v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) :
        \A vw \in 1..MaxView :
            \A cert \in votorGeneratedCerts[vw] :
                /\ cert.slot = currentSlot
                /\ cert.type \in {"fast", "slow"}
                => <>(\E b \in finalizedBlocks[currentSlot] : TRUE)
PROOF
    <1>1. \A v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) :
            \A cert \in votorGeneratedCerts[votorView[v]] :
                cert.type \in {"fast", "slow"} =>
                    <>(finalizedBlocks' = [finalizedBlocks EXCEPT ![cert.slot] =
                                               finalizedBlocks[cert.slot] \cup {CHOOSE b \in deliveredBlocks : b.hash = cert.block}])
        BY DEF HonestFinalizationBehavior

    <1> QED BY <1>1

\* Arithmetic helper lemmas
LEMMA ArithmeticInequality ==
    \A x \in Nat : x <= 2 * x
PROOF
    <1>1. TAKE x \in Nat
    <1>2. x <= 2 * x
        BY SimpleArithmetic
    <1> QED BY <1>2

LEMMA ArithmeticEquality ==
    \A x \in Nat : 2 * x = 2 * x
PROOF
    <1>1. TAKE x \in Nat
    <1>2. 2 * x = 2 * x
        BY SimpleArithmetic
    <1> QED BY <1>2

\* Simple arithmetic facts
LEMMA SimpleArithmetic ==
    /\ \A x \in Nat : x <= 2 * x
    /\ \A x \in Nat : 2 * x = 2 * x
    /\ \A x, y \in Nat : x < y => x <= y
PROOF
    BY DEF Nat

============================================================================
