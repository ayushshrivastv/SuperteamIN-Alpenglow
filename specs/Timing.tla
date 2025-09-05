------------------------------ MODULE Timing ------------------------------
(**************************************************************************)
(* Timing constants and functions for the Alpenglow protocol              *)
(**************************************************************************)

EXTENDS Integers, Sequences

----------------------------------------------------------------------------
(* Timing Constants *)

\* Slot timing
SlotDuration == 400         \* milliseconds per slot
MinSlotTime == 100          \* minimum slot duration
MaxSlotTime == 1000         \* maximum slot duration

\* View timing
ViewTimeout == 200          \* base view timeout
ViewTimeoutMultiplier == 2  \* exponential backoff multiplier
MaxViewTimeout == 10000     \* maximum view timeout

\* Network timing
NetworkLatency == 50        \* average network latency
MaxNetworkDelay == 200      \* maximum network delay
PropagationDelay == 10      \* message propagation delay

\* Consensus timing
FastPathTimeout == 100      \* fast path timeout (80% stake)
SlowPathTimeout == 200      \* slow path timeout (60% stake)
SkipTimeout == 300          \* skip/timeout threshold

\* Adaptive timeout constants
MinTimeout == 50            \* minimum timeout value
MaxTimeout == 8000          \* maximum timeout value
TimeoutMultiplier == 2      \* multiplier for exponential backoff
BaseTimeout == 100          \* base timeout for adaptive calculations

\* Rotor timing
ShredDistributionTime == 20 \* time to distribute shreds
ReconstructionTime == 30    \* time to reconstruct block
RepairRequestTimeout == 100 \* timeout for repair requests

\* Byzantine timing
ByzantineDelay == 500       \* delay introduced by Byzantine validators

\* Latency thresholds
HighLatencyThreshold == 150 \* threshold for high latency
LowLatencyThreshold == 50   \* threshold for low latency

\* Bandwidth constants
BandwidthPerValidator == 1000  \* bandwidth per validator (abstract units)
MinBandwidth == 100            \* minimum required bandwidth
MaxBandwidth == 10000          \* maximum bandwidth capacity

----------------------------------------------------------------------------
(* Timing Functions *)

\* Calculate view timeout with exponential backoff
CalculateViewTimeout(view) ==
    Min(ViewTimeout * (ViewTimeoutMultiplier ^ (view - 1)), MaxViewTimeout)

\* Adaptive timeout with exponential backoff strategy
AdaptiveTimeout(view, baseTimeout) ==
    LET exponentialTimeout == baseTimeout * (TimeoutMultiplier ^ (view - 1))
        boundedTimeout == Min(exponentialTimeout, MaxTimeout)
    IN Max(boundedTimeout, MinTimeout)

\* Extend timeout during network instability
ExtendTimeout(currentTimeout, factor) ==
    LET extendedTimeout == currentTimeout * factor
    IN Min(extendedTimeout, MaxTimeout)

\* Calculate slot start time
GetSlotStartTime(slot) ==
    (slot - 1) * SlotDuration

\* Calculate slot end time
GetSlotEndTime(slot) ==
    slot * SlotDuration

\* Check if time is within slot
IsWithinSlot(time, slot) ==
    /\ time >= GetSlotStartTime(slot)
    /\ time < GetSlotEndTime(slot)

\* Calculate next timeout
NextTimeout(currentTime, baseTimeout) ==
    currentTime + baseTimeout

\* Check if timeout expired
IsTimedOut(currentTime, timeoutTime) ==
    currentTime >= timeoutTime

\* Calculate message delivery time
MessageDeliveryTime(sender, receiver, messageSize) ==
    NetworkLatency + (messageSize \div BandwidthPerValidator) + PropagationDelay

\* Calculate Byzantine delay
CalculateByzantineDelay(validator, action) ==
    IF validator \in ByzantineValidators
    THEN ByzantineDelay
    ELSE 0

\* Estimate reconstruction time
EstimateReconstructionTime(numShreds, bandwidth) ==
    ReconstructionTime + (numShreds * 10 \div bandwidth)

\* Calculate repair time
CalculateRepairTime(missingShreds) ==
    RepairRequestTimeout + (Cardinality(missingShreds) * 10)

\* Compute fast path deadline
ComputeDelta80 ==
    FastPathTimeout

\* Compute slow path deadline
ComputeDelta60 ==
    SlowPathTimeout

\* Check if within fast path window
IsWithinFastPath(currentTime, startTime) ==
    currentTime <= startTime + FastPathTimeout

\* Check if within slow path window
IsWithinSlowPath(currentTime, startTime) ==
    /\ currentTime > startTime + FastPathTimeout
    /\ currentTime <= startTime + SlowPathTimeout

\* Calculate jitter (random delay)
CalculateJitter(seed) ==
    (seed % 10) * 5  \* 0-45ms jitter

\* Synchronization threshold
SyncThreshold ==
    NetworkLatency * 2

\* Check if validators are synchronized
AreSynchronized(time1, time2) ==
    AbsoluteDifference(time1, time2) <= SyncThreshold

\* Absolute difference helper
AbsoluteDifference(a, b) ==
    IF a >= b THEN a - b ELSE b - a

\* Min helper
Min(a, b) == IF a < b THEN a ELSE b

\* Max helper
Max(a, b) == IF a > b THEN a ELSE b

\* View-dependent timeout calculation
ViewDependentTimeout(view) ==
    AdaptiveTimeout(view, BaseTimeout)

\* Check if timeout is within valid bounds
IsValidTimeout(timeout) ==
    /\ timeout >= MinTimeout
    /\ timeout <= MaxTimeout

\* Calculate timeout with network condition adjustment
NetworkAdjustedTimeout(baseTimeout, networkCondition) ==
    CASE networkCondition = "good" -> baseTimeout
      [] networkCondition = "degraded" -> ExtendTimeout(baseTimeout, 2)
      [] networkCondition = "poor" -> ExtendTimeout(baseTimeout, 4)
      [] OTHER -> baseTimeout

\* Timeout stabilization check
TimeoutStabilized(currentTimeout, previousTimeout) ==
    AbsoluteDifference(currentTimeout, previousTimeout) <= (MinTimeout \div 2)

\* Calculate adaptive timeout for leader windows
LeaderWindowTimeout(windowNumber, baseTimeout) ==
    AdaptiveTimeout(windowNumber, baseTimeout)

\* Timeout progression invariant
TimeoutProgressionInvariant(timeouts) ==
    \A i \in DOMAIN timeouts :
        /\ IsValidTimeout(timeouts[i])
        /\ (i > 1) => (timeouts[i] >= timeouts[i-1])

\* Timeout bounds invariant
TimeoutBoundsInvariant(timeout) ==
    /\ timeout >= MinTimeout
    /\ timeout <= MaxTimeout

\* Timeout convergence property
TimeoutConvergence(timeoutSequence) ==
    \E stabilizationPoint \in DOMAIN timeoutSequence :
        \A i \in stabilizationPoint..Len(timeoutSequence) :
            TimeoutStabilized(timeoutSequence[i],
                             IF i > 1 THEN timeoutSequence[i-1] ELSE timeoutSequence[i])

\* Constants needed by other modules
CONSTANTS ByzantineValidators

============================================================================
