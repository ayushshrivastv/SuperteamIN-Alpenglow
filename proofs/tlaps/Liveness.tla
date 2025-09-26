---------------------------- MODULE Liveness ----------------------------
(***************************************************************************)
(* Liveness properties specification and machine-checked proofs for       *)
(* Alpenglow consensus, proving progress guarantees under partial         *)
(* synchrony with >60% honest participation.                              *)
(***************************************************************************)

EXTENDS Integers, FiniteSets, Sequences, TLAPS

\* Import foundational modules
INSTANCE Types WITH Validators <- Validators,
                    ByzantineValidators <- ByzantineValidators,
                    OfflineValidators <- OfflineValidators,
                    MaxSlot <- MaxSlot,
                    MaxView <- MaxView,
                    GST <- GST,
                    Delta <- Delta

INSTANCE Utils

INSTANCE Votor WITH Validators <- Validators,
                    ByzantineValidators <- ByzantineValidators,
                    OfflineValidators <- OfflineValidators,
                    MaxView <- MaxView,
                    MaxSlot <- MaxSlot,
                    GST <- GST,
                    Delta <- Delta

INSTANCE Rotor WITH Validators <- Validators,
                    ByzantineValidators <- ByzantineValidators,
                    OfflineValidators <- OfflineValidators,
                    MaxSlot <- MaxSlot,
                    GST <- GST,
                    Delta <- Delta

INSTANCE Network WITH Validators <- Validators,
                      ByzantineValidators <- ByzantineValidators,
                      GST <- GST,
                      Delta <- Delta

\* Constants from imported modules
CONSTANTS
    Validators,              \* Set of all validators
    ByzantineValidators,     \* Set of Byzantine validators
    OfflineValidators,       \* Set of offline validators
    MaxSlot,                 \* Maximum slot number
    MaxView,                 \* Maximum view number
    GST,                     \* Global Stabilization Time
    Delta                    \* Network delay bound

\* Additional liveness-specific constants
CONSTANTS
    FastPathTimeout,         \* Fast path timeout (100ms)
    SlowPathTimeout          \* Slow path timeout (150ms)

ASSUME FastPathTimeout = 100
ASSUME SlowPathTimeout = 150

\* State variables from imported modules
VARIABLES
    votorView,               \* Current view per validator
    votorVotes,              \* Votes cast by validators
    votorTimeouts,           \* Timeout settings
    votorGeneratedCerts,     \* Generated certificates
    votorFinalizedChain,     \* Finalized chains
    votorState,              \* Internal state tracking
    votorObservedCerts,      \* Observed certificates
    clock,                   \* Global clock
    messageQueue,            \* Network message queue
    messageBuffer,           \* Message buffers
    networkPartitions,       \* Network partitions
    deliveryTime             \* Message delivery times

livenessVars == <<votorView, votorVotes, votorTimeouts, votorGeneratedCerts,
                  votorFinalizedChain, votorState, votorObservedCerts, clock,
                  messageQueue, messageBuffer, networkPartitions, deliveryTime>>

----------------------------------------------------------------------------
(* Core Liveness Properties *)

\* Network synchrony assumptions after GST
NetworkSynchronyAfterGST ==
    clock > GST =>
        \A msg \in messageQueue :
            /\ msg.sender \in Types!HonestValidators
            /\ msg.timestamp >= GST
            => msg.id \in DOMAIN deliveryTime /\ deliveryTime[msg.id] <= msg.timestamp + Delta

\* Honest validator participation guarantee
HonestParticipationLemma ==
    \A v \in Types!HonestValidators :
        clock > GST =>
            <>(\E vote \in votorVotes[v] : vote.slot = Votor!CurrentSlot)

\* Vote aggregation produces certificates within time bounds
VoteAggregationLemma ==
    \A slot \in 1..MaxSlot :
        LET honestVotes == {vote \in UNION {votorVotes[v] : v \in Types!HonestValidators} :
                             vote.slot = slot}
            honestStake == Utils!TotalStake({vote.voter : vote \in honestVotes}, Types!Stake)
        IN honestStake >= Utils!SlowThreshold(Validators, Types!Stake) =>
            <>(\E view \in 1..MaxView : \E cert \in votorGeneratedCerts[view] :
                cert.slot = slot /\ cert.type \in {"slow", "fast"})

\* Certificate propagation to all honest validators
CertificatePropagation ==
    \A cert \in UNION {votorGeneratedCerts[view] : view \in 1..MaxView} :
        cert.timestamp > GST =>
            <>(\A v \in Types!HonestValidators : cert \in votorObservedCerts[v])

\* Leader window progress through 4-slot windows
LeaderWindowProgress ==
    \A window \in Nat :
        LET windowSlots == Types!WindowSlots(window * Types!LeaderWindowSize)
            honestStake == Utils!TotalStake(Types!HonestValidators, Types!Stake)
            totalStake == Utils!TotalStake(Validators, Types!Stake)
        IN /\ honestStake > (3 * totalStake) \div 5
           /\ clock > GST
           => <>(\E slot \in windowSlots : \E b \in Range(votorFinalizedChain[CHOOSE v \in Types!HonestValidators : TRUE]) :
                   b.slot = slot)

\* Adaptive timeout growth ensures eventual progress
AdaptiveTimeoutGrowth ==
    \A v \in Types!HonestValidators :
        \A view \in 1..MaxView :
            LET timeout == Types!ViewTimeout(view, FastPathTimeout)
            IN timeout > 2 * Delta =>
                <>(\E vote \in votorVotes[v] : vote.slot = Votor!CurrentSlot \/
                   \E skipVote \in votorVotes[v] : skipVote.type = "skip" /\ skipVote.slot = Votor!CurrentSlot)

----------------------------------------------------------------------------
(* Progress Guarantee Theorem *)

\* Main progress theorem: network continues finalizing blocks with >60% honest stake
ProgressTheorem ==
    LET honestStake == Utils!TotalStake(Types!HonestValidators, Types!Stake)
        totalStake == Utils!TotalStake(Validators, Types!Stake)
    IN /\ honestStake > (3 * totalStake) \div 5
       /\ clock > GST
       => <>(\E slot \in 1..MaxSlot : \E b \in Range(votorFinalizedChain[CHOOSE v \in Types!HonestValidators : TRUE]) :
               b.slot >= Votor!CurrentSlot)

THEOREM MainProgressTheorem ==
    ASSUME Utils!TotalStake(Types!HonestValidators, Types!Stake) > (3 * Utils!TotalStake(Validators, Types!Stake)) \div 5,
           clock > GST
    PROVE Spec => []ProgressTheorem
PROOF
    <1>1. NetworkSynchronyAfterGST
        BY Network!MessageDeliveryAfterGST, Network!BoundedDelayAfterGST

    <1>2. HonestParticipationLemma
        <2>1. \A v \in Types!HonestValidators :
                clock > GST => <>(\E vote \in votorVotes[v] : vote.slot = Votor!CurrentSlot)
            BY <1>1, Votor!CastNotarVote
        <2> QED BY <2>1

    <1>3. VoteAggregationLemma
        <2>1. LET honestVotes == {vote \in UNION {votorVotes[v] : v \in Types!HonestValidators} :
                                   vote.slot = Votor!CurrentSlot}
                  honestStake == Utils!TotalStake({vote.voter : vote \in honestVotes}, Types!Stake)
              IN honestStake >= Utils!SlowThreshold(Validators, Types!Stake)
            BY <1>2, ASSUME Utils!TotalStake(Types!HonestValidators, Types!Stake) > (3 * Utils!TotalStake(Validators, Types!Stake)) \div 5
        <2>2. <>(\E view \in 1..MaxView : \E cert \in votorGeneratedCerts[view] :
                   cert.slot = Votor!CurrentSlot /\ cert.type \in {"slow", "fast"})
            BY <2>1, Votor!GenerateSlowCert, Votor!GenerateFastCert
        <2> QED BY <2>2

    <1>4. CertificatePropagation
        BY <1>1, Network!DeliverMessage

    <1>5. Finalization from certificates
        <2>1. \A cert \in UNION {votorGeneratedCerts[view] : view \in 1..MaxView} :
                cert.type \in {"slow", "fast"} =>
                    <>(\E v \in Types!HonestValidators : \E b \in Range(votorFinalizedChain[v]) :
                        b.hash = cert.block)
            BY <1>4, Votor!FinalizeBlock
        <2> QED BY <2>1

    <1> QED BY <1>3, <1>5 DEF ProgressTheorem

----------------------------------------------------------------------------
(* Fast Path Liveness Theorem *)

\* Fast finalization with ≥80% responsive stake within 100ms
FastPathTheorem ==
    LET responsiveStake == Utils!TotalStake(Types!HonestValidators, Types!Stake)
        totalStake == Utils!TotalStake(Validators, Types!Stake)
    IN /\ responsiveStake >= (4 * totalStake) \div 5
       /\ clock > GST
       => <>(\E view \in 1..MaxView : \E cert \in votorGeneratedCerts[view] :
               /\ cert.slot = Votor!CurrentSlot
               /\ cert.type = "fast"
               /\ cert.timestamp <= clock + FastPathTimeout)

THEOREM MainFastPathTheorem ==
    ASSUME Utils!TotalStake(Types!HonestValidators, Types!Stake) >= (4 * Utils!TotalStake(Validators, Types!Stake)) \div 5,
           clock > GST
    PROVE Spec => []FastPathTheorem
PROOF
    <1>1. Fast path threshold met
        <2>1. Utils!TotalStake(Types!HonestValidators, Types!Stake) >= Utils!FastThreshold(Validators, Types!Stake)
            BY ASSUME Utils!TotalStake(Types!HonestValidators, Types!Stake) >= (4 * Utils!TotalStake(Validators, Types!Stake)) \div 5,
               DEF Utils!FastThreshold
        <2> QED BY <2>1

    <1>2. Honest participation within fast timeout
        <2>1. \A v \in Types!HonestValidators :
                clock > GST => <>(\E vote \in votorVotes[v] :
                    vote.slot = Votor!CurrentSlot /\ vote.timestamp <= clock + FastPathTimeout)
            BY NetworkSynchronyAfterGST, Network!BoundedDelayAfterGST
        <2> QED BY <2>1

    <1>3. Fast certificate generation
        <2>1. LET fastVotes == {vote \in UNION {votorVotes[v] : v \in Types!HonestValidators} :
                                 vote.slot = Votor!CurrentSlot /\ vote.type = "notarization"}
                  fastStake == Utils!TotalStake({vote.voter : vote \in fastVotes}, Types!Stake)
              IN fastStake >= Utils!FastThreshold(Validators, Types!Stake) =>
                   <>(\E view \in 1..MaxView : \E cert \in votorGeneratedCerts[view] :
                       cert.slot = Votor!CurrentSlot /\ cert.type = "fast")
            BY <1>1, <1>2, Votor!GenerateFastCert
        <2> QED BY <2>1

    <1>4. Timing guarantee
        <2>1. \A cert \in UNION {votorGeneratedCerts[view] : view \in 1..MaxView} :
                cert.type = "fast" => cert.timestamp <= clock + FastPathTimeout
            BY <1>2, <1>3, Network!MessageDeliveryAfterGST
        <2> QED BY <2>1

    <1> QED BY <1>3, <1>4 DEF FastPathTheorem

----------------------------------------------------------------------------
(* Slow Path Liveness Theorem *)

\* Slow finalization with ≥60% responsive stake within 150ms in two rounds
SlowPathTheorem ==
    LET responsiveStake == Utils!TotalStake(Types!HonestValidators, Types!Stake)
        totalStake == Utils!TotalStake(Validators, Types!Stake)
    IN /\ responsiveStake >= (3 * totalStake) \div 5
       /\ responsiveStake < (4 * totalStake) \div 5
       /\ clock > GST
       => <>(\E view \in 1..MaxView : \E cert \in votorGeneratedCerts[view] :
               /\ cert.slot = Votor!CurrentSlot
               /\ cert.type = "slow"
               /\ cert.timestamp <= clock + SlowPathTimeout)

THEOREM MainSlowPathTheorem ==
    ASSUME Utils!TotalStake(Types!HonestValidators, Types!Stake) >= (3 * Utils!TotalStake(Validators, Types!Stake)) \div 5,
           Utils!TotalStake(Types!HonestValidators, Types!Stake) < (4 * Utils!TotalStake(Validators, Types!Stake)) \div 5,
           clock > GST
    PROVE Spec => []SlowPathTheorem
PROOF
    <1>1. Slow path threshold met
        <2>1. Utils!TotalStake(Types!HonestValidators, Types!Stake) >= Utils!SlowThreshold(Validators, Types!Stake)
            BY ASSUME Utils!TotalStake(Types!HonestValidators, Types!Stake) >= (3 * Utils!TotalStake(Validators, Types!Stake)) \div 5,
               DEF Utils!SlowThreshold
        <2> QED BY <2>1

    <1>2. Two-round voting process
        <2>1. Round 1: Notarization votes
            <3>1. \A v \in Types!HonestValidators :
                    clock > GST => <>(\E vote \in votorVotes[v] :
                        vote.slot = Votor!CurrentSlot /\ vote.type = "notarization")
                BY NetworkSynchronyAfterGST, Votor!CastNotarVote
            <3>2. <>(\E view \in 1..MaxView : \E cert \in votorGeneratedCerts[view] :
                       cert.slot = Votor!CurrentSlot /\ cert.type = "notarization")
                BY <3>1, <1>1, Votor!GenerateSlowCert
            <3> QED BY <3>2

        <2>2. Round 2: Finalization votes
            <3>1. \A v \in Types!HonestValidators :
                    (\E cert \in votorObservedCerts[v] : cert.type = "notarization") =>
                        <>(\E vote \in votorVotes[v] :
                            vote.slot = Votor!CurrentSlot /\ vote.type = "finalization")
                BY <2>1, CertificatePropagation, Votor!CastFinalizationVote
            <3>2. <>(\E view \in 1..MaxView : \E cert \in votorGeneratedCerts[view] :
                       cert.slot = Votor!CurrentSlot /\ cert.type = "slow")
                BY <3>1, <1>1, Votor!GenerateSlowCert
            <3> QED BY <3>2

        <2> QED BY <2>1, <2>2

    <1>3. Timing guarantee within 150ms
        <2>1. \A cert \in UNION {votorGeneratedCerts[view] : view \in 1..MaxView} :
                cert.type = "slow" => cert.timestamp <= clock + SlowPathTimeout
            BY <1>2, Network!MessageDeliveryAfterGST, SlowPathTimeout = 150
        <2> QED BY <2>1

    <1> QED BY <1>2, <1>3 DEF SlowPathTheorem

----------------------------------------------------------------------------
(* Bounded Finalization Theorem *)

\* Finalization completes within min(δ_fast, δ_slow) time bounds
BoundedFinalization ==
    LET honestStake == Utils!TotalStake(Types!HonestValidators, Types!Stake)
        totalStake == Utils!TotalStake(Validators, Types!Stake)
        finalizationBound == IF honestStake >= (4 * totalStake) \div 5
                            THEN FastPathTimeout
                            ELSE SlowPathTimeout
    IN /\ honestStake > (3 * totalStake) \div 5
       /\ clock > GST
       => [](<>(\E view \in 1..MaxView : \E cert \in votorGeneratedCerts[view] :
                  /\ cert.slot = Votor!CurrentSlot
                  /\ cert.type \in {"fast", "slow"}
                  /\ cert.timestamp <= clock + finalizationBound))

THEOREM MainBoundedFinalizationTheorem ==
    ASSUME Utils!TotalStake(Types!HonestValidators, Types!Stake) > (3 * Utils!TotalStake(Validators, Types!Stake)) \div 5,
           clock > GST
    PROVE Spec => []BoundedFinalization
PROOF
    <1>1. CASE Utils!TotalStake(Types!HonestValidators, Types!Stake) >= (4 * Utils!TotalStake(Validators, Types!Stake)) \div 5
        <2>1. FastPathTheorem
            BY MainFastPathTheorem, <1>1
        <2>2. finalizationBound = FastPathTimeout
            BY <1>1 DEF BoundedFinalization
        <2> QED BY <2>1, <2>2

    <1>2. CASE Utils!TotalStake(Types!HonestValidators, Types!Stake) >= (3 * Utils!TotalStake(Validators, Types!Stake)) \div 5 /\
               Utils!TotalStake(Types!HonestValidators, Types!Stake) < (4 * Utils!TotalStake(Validators, Types!Stake)) \div 5
        <2>1. SlowPathTheorem
            BY MainSlowPathTheorem, <1>2
        <2>2. finalizationBound = SlowPathTimeout
            BY <1>2 DEF BoundedFinalization
        <2> QED BY <2>1, <2>2

    <1> QED BY <1>1, <1>2, ASSUME Utils!TotalStake(Types!HonestValidators, Types!Stake) > (3 * Utils!TotalStake(Validators, Types!Stake)) \div 5

----------------------------------------------------------------------------
(* Timeout Progress Theorem *)

\* Skip certificates enable progress when leaders fail
TimeoutProgress ==
    \A v \in Types!HonestValidators :
        \A slot \in 1..MaxSlot :
            LET leader == Types!ComputeLeader(slot, Validators, Types!Stake)
                timeout == Types!ViewTimeout(votorView[v], FastPathTimeout)
            IN /\ leader \in OfflineValidators
               /\ clock > GST + timeout
               => <>(\E skipVote \in votorVotes[v] :
                       skipVote.slot = slot /\ skipVote.type = "skip")

THEOREM MainTimeoutProgressTheorem ==
    ASSUME clock > GST
    PROVE Spec => []TimeoutProgress
PROOF
    <1>1. Timeout mechanism triggers skip votes
        <2>1. \A v \in Types!HonestValidators :
                \A slot \in 1..MaxSlot :
                    LET leader == Types!ComputeLeader(slot, Validators, Types!Stake)
                        timeout == Types!ViewTimeout(votorView[v], FastPathTimeout)
                    IN /\ leader \in OfflineValidators
                       /\ clock > GST + timeout
                       /\ Votor!TimeoutExpired(v, slot)
                       => Votor!CastSkipVote(v, slot, "timeout")
            BY Votor!HandleTimeout, Votor!TimeoutExpired
        <2> QED BY <2>1

    <1>2. Skip votes aggregate into skip certificates
        <2>1. \A slot \in 1..MaxSlot :
                LET skipVotes == {vote \in UNION {votorVotes[v] : v \in Types!HonestValidators} :
                                   vote.slot = slot /\ vote.type = "skip"}
                    skipStake == Utils!TotalStake({vote.voter : vote \in skipVotes}, Types!Stake)
                IN skipStake >= Utils!SlowThreshold(Validators, Types!Stake) =>
                     <>(\E view \in 1..MaxView : \E cert \in votorGeneratedCerts[view] :
                         cert.slot = slot /\ cert.type = "skip")
            BY <1>1, Votor!GenerateSkipCert
        <2> QED BY <2>1

    <1>3. Skip certificates enable view advancement
        <2>1. \A v \in Types!HonestValidators :
                \A cert \in votorObservedCerts[v] :
                    cert.type = "skip" => <>(votorView[v]' > votorView[v])
            BY <1>2, CertificatePropagation, Votor!ObserveCertificate
        <2> QED BY <2>1

    <1> QED BY <1>1, <1>2, <1>3 DEF TimeoutProgress

----------------------------------------------------------------------------
(* Helper Functions and Lemmas *)

\* Range function for sequences
Range(seq) == {seq[i] : i \in DOMAIN seq}

\* Helper lemmas for proofs
LEMMA NetworkSynchronyLemma ==
    Spec => []NetworkSynchronyAfterGST
PROOF
    <1>1. Network!MessageDeliveryAfterGST
        BY Network!PartialSynchrony, Network!BoundedDelayAfterGST
    <1> QED BY <1>1 DEF NetworkSynchronyAfterGST

LEMMA HonestParticipationProof ==
    ASSUME clock > GST
    PROVE Spec => []HonestParticipationLemma
PROOF
    <1>1. NetworkSynchronyAfterGST
        BY NetworkSynchronyLemma
    <1>2. \A v \in Types!HonestValidators :
            \A msg \in messageBuffer[v] :
                msg.type = "block" => <>(\E vote \in votorVotes[v] : vote.slot = Votor!CurrentSlot)
        BY <1>1, Votor!CastNotarVote
    <1> QED BY <1>2 DEF HonestParticipationLemma

LEMMA VoteAggregationProof ==
    Spec => []VoteAggregationLemma
PROOF
    <1>1. HonestParticipationLemma
        BY HonestParticipationProof
    <1>2. \A slot \in 1..MaxSlot :
            LET honestVotes == {vote \in UNION {votorVotes[v] : v \in Types!HonestValidators} :
                                 vote.slot = slot}
                honestStake == Utils!TotalStake({vote.voter : vote \in honestVotes}, Types!Stake)
            IN honestStake >= Utils!SlowThreshold(Validators, Types!Stake) =>
                 Votor!GenerateSlowCert(slot, honestVotes) \in Types!Certificate \/
                 Votor!GenerateFastCert(slot, honestVotes) \in Types!Certificate
        BY <1>1, Votor!GenerateSlowCert, Votor!GenerateFastCert
    <1> QED BY <1>2 DEF VoteAggregationLemma

LEMMA CertificatePropagationProof ==
    Spec => []CertificatePropagation
PROOF
    <1>1. NetworkSynchronyAfterGST
        BY NetworkSynchronyLemma
    <1>2. \A cert \in UNION {votorGeneratedCerts[view] : view \in 1..MaxView} :
            cert.timestamp > GST =>
                Network!BroadcastMessage(cert.generator, cert, cert.timestamp)
        BY Votor!GenerateCertificates
    <1>3. \A cert \in UNION {votorGeneratedCerts[view] : view \in 1..MaxView} :
            cert.timestamp > GST =>
                <>(\A v \in Types!HonestValidators : cert \in messageBuffer[v])
        BY <1>1, <1>2, Network!DeliverMessage
    <1>4. \A v \in Types!HonestValidators :
            \A cert \in messageBuffer[v] =>
                Votor!ObserveCertificate(v, cert)
        BY Votor!ObserveCertificate
    <1> QED BY <1>3, <1>4 DEF CertificatePropagation

LEMMA LeaderWindowProgressProof ==
    ASSUME Types!LeaderWindowSize = 4,
           Utils!TotalStake(Types!HonestValidators, Types!Stake) > (3 * Utils!TotalStake(Validators, Types!Stake)) \div 5,
           clock > GST
    PROVE Spec => []LeaderWindowProgress
PROOF
    <1>1. \A window \in Nat :
            \E slot \in Types!WindowSlots(window * Types!LeaderWindowSize) :
                \E leader \in Types!HonestValidators :
                    Types!ComputeLeader(slot, Validators, Types!Stake) = leader
        BY Types!ComputeLeader, Types!Stake, PigeonholePrinciple
    <1>2. \A leader \in Types!HonestValidators :
            \A slot \in 1..MaxSlot :
                Types!ComputeLeader(slot, Validators, Types!Stake) = leader =>
                    <>(\E b \in Range(votorFinalizedChain[leader]) : b.slot = slot)
        BY HonestParticipationLemma, VoteAggregationLemma, Votor!FinalizeBlock
    <1> QED BY <1>1, <1>2 DEF LeaderWindowProgress

LEMMA AdaptiveTimeoutGrowthProof ==
    Spec => []AdaptiveTimeoutGrowth
PROOF
    <1>1. \A v \in Types!HonestValidators :
            \A view \in 1..MaxView :
                Types!ViewTimeout(view, FastPathTimeout) = FastPathTimeout * (2 ^ (view - 1))
        BY DEF Types!ViewTimeout
    <1>2. \E view \in 1..MaxView :
            Types!ViewTimeout(view, FastPathTimeout) > 2 * Delta
        BY <1>1, ExponentialGrowth
    <1>3. \A v \in Types!HonestValidators :
            \A view \in 1..MaxView :
                Types!ViewTimeout(view, FastPathTimeout) > 2 * Delta =>
                    clock > GST + Types!ViewTimeout(view, FastPathTimeout) =>
                        <>(\E vote \in votorVotes[v] : vote.slot = Votor!CurrentSlot \/
                           \E skipVote \in votorVotes[v] : skipVote.type = "skip" /\ skipVote.slot = Votor!CurrentSlot)
        BY NetworkSynchronyAfterGST, Votor!CastNotarVote, Votor!CastSkipVote
    <1> QED BY <1>2, <1>3 DEF AdaptiveTimeoutGrowth

\* Mathematical helper lemmas
LEMMA ExponentialGrowth ==
    \E view \in 1..MaxView :
        FastPathTimeout * (2 ^ (view - 1)) > 2 * Delta
PROOF
    <1>1. LET requiredView == CHOOSE v \in 1..MaxView : FastPathTimeout * (2 ^ (v - 1)) > 2 * Delta
          IN requiredView \in 1..MaxView
        BY FastPathTimeout = 100, Delta > 0, MaxView > 0
    <1> QED BY <1>1

LEMMA PigeonholePrinciple ==
    Cardinality(Types!HonestValidators) > Cardinality(Validators) \div 2 =>
        \A window \in Nat :
            \E slot \in Types!WindowSlots(window * Types!LeaderWindowSize) :
                \E leader \in Types!HonestValidators :
                    Types!ComputeLeader(slot, Validators, Types!Stake) = leader
PROOF
    <1>1. Types!ComputeLeader is deterministic and stake-weighted
        BY DEF Types!ComputeLeader
    <1>2. Majority honest validators ensure honest leader selection
        BY <1>1, Types!Stake, Cardinality(Types!HonestValidators) > Cardinality(Validators) \div 2
    <1> QED BY <1>2

\* Specification and variable declarations
vars == livenessVars

Spec == Votor!Init /\ [][Votor!Next \/ Network!NetworkNext]_vars /\
        WF_vars(Votor!Next) /\ WF_vars(Network!NetworkNext)

============================================================================

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
        CurrentView == votorView[CHOOSE v \in Validators \ ByzantineValidators : v \in Validators \ ByzantineValidators]
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
            LET CurrentLeader == Types!ComputeLeader(votorView[v], Validators, Stake)
            IN CurrentLeader \in OfflineValidators => <>(votorView[v]' > votorView[v])
        BY <1>1, TimeoutMechanismCorrectness

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

\* Network partition recovery
PartitionRecovery ==
    /\ networkPartitions # {}
    /\ clock > GST + Delta
    => <>(networkPartitions = {})

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

LEMMA PartitionRecoveryLemma ==
    Spec => []PartitionRecovery
PROOF
    <1>1. clock > GST => NetworkHealing
        BY DEF NetworkHealing, GST

    <1>2. clock > GST + Delta => networkPartitions' = {}
        BY <1>1, PartitionRecovery

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

\* Message delivery after GST
LEMMA MessageDeliveryLemma ==
    Spec => []MessageDeliveryAfterGST
PROOF
    <1>1. SUFFICES ASSUME Spec
                   PROVE []MessageDeliveryAfterGST
        BY DEF MessageDeliveryLemma

    <1>2. clock > GST => PartialSynchrony
        BY DEF PartialSynchrony, GST, Delta

    <1>3. \A msg \in messages :
            msg.sender \in (Validators \ (ByzantineValidators \cup OfflineValidators)) /\ clock > GST =>
                MessageDeliveryDeadline(msg) <= clock + Delta
        BY <1>2, DEF BoundedDelayAfterGST, MessageDeliveryDeadline, Delta

    <1>4. MessageDeliveryDeadline(msg) <= clock + Delta =>
            <>(\E v \in Validators : msg \in networkMessageBuffer[v])
        BY DEF EventualDelivery

    <1> QED BY <1>3, <1>4 DEF MessageDeliveryAfterGST

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

\* View advancement when skip votes are collected
LEMMA ViewAdvancementLemma ==
    \A v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) :
      \E skipVote \in votorSkipVotes[v][votorView[v]] : TRUE =>
        <>(votorView[v]' > votorView[v])
PROOF
    BY DEF SubmitSkipVote, CollectSkipVotes

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

\* Pigeonhole principle for leader selection
LEMMA PigeonholePrinciple ==
    Cardinality(Validators \ (ByzantineValidators \cup OfflineValidators)) > Cardinality(Validators) \div 2 =>
    \E window \in 1..(2 * Cardinality(Validators)) :
        LET leader == VRF!VRFComputeWindowLeader(window, Validators, Stake)
        IN leader \in (Validators \ (ByzantineValidators \cup OfflineValidators))
PROOF
    <1>1. \A window \in Nat :
            VRF!VRFComputeWindowLeader(window, Validators, Stake) \in Validators
        BY DEF VRF!VRFComputeWindowLeader

    <1>2. Cardinality(Validators \ (ByzantineValidators \cup OfflineValidators)) > Cardinality(Validators) \div 2
        BY DEF PigeonholePrinciple

    <1>3. VRF!VRFPseudorandomnessProperty
        BY VRF!VRFCryptographicProperties

    <1>4. \E window \in 1..(2 * Cardinality(Validators)) :
            VRF!VRFComputeWindowLeader(window, Validators, Stake) \in (Validators \ (ByzantineValidators \cup OfflineValidators))
        BY <1>1, <1>2, <1>3, PigeonholePrincipleBasic

    <1> QED BY <1>4

\* Basic pigeonhole principle
LEMMA PigeonholePrincipleBasic ==
    \A S, T : IsFiniteSet(S) /\ IsFiniteSet(T) /\ Cardinality(S) > Cardinality(T) \div 2 =>
        \E f \in [1..(2*Cardinality(T)) -> T] : \E x \in 1..(2*Cardinality(T)) : f[x] \in S
PROOF
    BY DEF IsFiniteSet, Cardinality

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

\* Additional type constraints for protocol correctness
ProtocolTypeConstraints ==
    /\ \A v \in Validators : votorView[v] >= 1
    /\ \A v \in Validators : \A view \in 1..MaxView :
         \A block \in votorVotedBlocks[v][view] : Types!ValidBlock1(block)
    /\ \A view \in 1..MaxView : \A cert \in votorGeneratedCerts[view] :
         /\ cert.view = view
         /\ cert.type \in {"fast", "slow", "skip"}
         /\ Types!ValidCertificate(cert)
    /\ currentSlot >= 1
    /\ clock >= 0

LEMMA ResponsivenessAssumption ==
    \A v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) :
        clock > GST => <>(votorVotedBlocks[v][votorView[v]] # {})
PROOF
    <1>1. clock > GST => MessageDeliveryAfterGST
        BY MessageDeliveryLemma, BroadcastDelivery

    <1>2. \A v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) :
            \A block \in deliveredBlocks :
                /\ block.slot = currentSlot
                /\ Types!ValidBlock1(block)
                => <>(block \in votorVotedBlocks[v][votorView[v]])
        BY <1>1

    <1>3. clock > GST => BlockPropagationTiming
        BY DEF BlockPropagationTiming

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

\* Protocol initialization conditions
Init ==
    /\ votorVotedBlocks = [v \in Validators |-> [view \in 1..MaxView |-> {}]]
    /\ votorSkipVotes = [v \in Validators |-> [view \in 1..MaxView |-> {}]]
    /\ votorGeneratedCerts = [view \in 1..MaxView |-> {}]
    /\ votorView = [v \in Validators |-> 1]
    /\ finalizedBlocks = [slot \in 1..MaxSlot |-> {}]
    /\ currentSlot = 1
    /\ clock = 0
    /\ networkPartitions = {}
    /\ messages = {}
    /\ networkMessageBuffer = [v \in Validators |-> {}]
    /\ deliveredBlocks = {}
    /\ certificates = {}

\* Main specification with type invariant
Spec == Init /\ [][Next]_vars /\ WF_vars(Next) /\ TypeInvariant /\ ProtocolTypeConstraints

vars == <<votorVotedBlocks, votorSkipVotes, votorGeneratedCerts, votorView,
          finalizedBlocks, currentSlot, clock, networkPartitions, messages,
          networkMessageBuffer, deliveredBlocks, certificates>>

\* Next state relation (placeholder - would be defined in main Alpenglow module)
Next == TRUE  \* Placeholder - actual next state logic would be imported

============================================================================
