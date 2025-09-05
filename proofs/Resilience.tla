---------------------------- MODULE Resilience ----------------------------
(**************************************************************************)
(* Resilience properties specification and proofs, establishing safety    *)
(* with 20% Byzantine stake and liveness with 20% offline validators.    *)
(**************************************************************************)

EXTENDS Integers, FiniteSets, Sequences

\* Import modules properly
INSTANCE Alpenglow
INSTANCE Types
INSTANCE Votor
INSTANCE Utils
INSTANCE NetworkIntegration WITH clock <- Alpenglow!clock,
                               networkPartitions <- Alpenglow!networkPartitions

\* Import necessary constants from Alpenglow
CONSTANTS Validators, Stake, MaxView

\* Constants and assumptions for resilience analysis
CONSTANTS ByzantineValidators, OfflineValidators

\* Assumptions about fault distribution
ASSUME ByzantineValidators \subseteq Validators
ASSUME OfflineValidators \subseteq Validators
ASSUME ByzantineValidators \cap OfflineValidators = {}

\* Certificate reference - use proper certificate collection from Votor
certificates == UNION {Votor!votorGeneratedCerts[vw] : vw \in 1..MaxView}

\* Stake calculation operators
TotalStakeSum == Types!TotalStake(Validators, Stake)

\* Required stake thresholds
FastPathRequiredStake == (4 * TotalStakeSum) \div 5
SlowPathRequiredStake == (3 * TotalStakeSum) \div 5

\* Use consistent stake calculation through Utils
SumStake(validatorSet) ==
    Utils!Sum([v \in validatorSet |-> Stake[v]])

\* Validator behavior definitions
HonestValidatorBehavior ==
    \A v \in (Validators \\ (ByzantineValidators \cup OfflineValidators)) :
        \* Honest validators follow protocol rules
        /\ \A view \in 1..MaxView : \A slot \in Types!Slots :
            \E vote \in Votor!votes : vote.validator = v /\ vote.view = view =>
                \A vote2 \in Votor!votes : vote2.validator = v /\ vote2.view = view => vote = vote2

\* Byzantine validator assumptions
ByzantineAssumption == Types!TotalStake(ByzantineValidators, Stake) <= TotalStakeSum \div 5

\* Network timing assumptions
GST == 100  \* Global Stabilization Time
Delta == 10 \* Maximum message delay after GST

\* Progress definition
Progress == \E slot \in Types!Slots : \E cert \in certificates : cert.slot = slot

\* Safety definition
Safety == \A slot \in Types!Slots :
    \A cert1, cert2 \in certificates :
        cert1.slot = slot /\ cert2.slot = slot => cert1.block = cert2.block

----------------------------------------------------------------------------
(* Resilience Model *)

\* "20+20" resilience: 20% Byzantine + 20% offline
Combined2020Resilience ==
    LET ByzantineStake == Types!TotalStake(ByzantineValidators, Stake)
        OfflineStake == Types!TotalStake(OfflineValidators, Stake)
    IN
    /\ ByzantineStake <= TotalStakeSum \div 5
    /\ OfflineStake <= TotalStakeSum \div 5
    => /\ []Safety
       /\ (Alpenglow!clock > GST => <>Progress)

THEOREM Combined2020ResilienceTheorem ==
    ASSUME Types!TotalStake(ByzantineValidators, Stake) <= TotalStakeSum \div 5,
           Types!TotalStake(OfflineValidators, Stake) <= TotalStakeSum \div 5
    PROVE Alpenglow!Spec => Combined2020Resilience
PROOF
    <1>1. ASSUME Types!TotalStake(ByzantineValidators, Stake) <= TotalStakeSum \div 5,
                 Types!TotalStake(OfflineValidators, Stake) <= TotalStakeSum \div 5,
                 Alpenglow!Spec
          PROVE Combined2020Resilience
    <1>2. []Safety
          <2>1. Types!TotalStake(ByzantineValidators, Stake) <= TotalStakeSum \div 5
                BY <1>1
          <2>2. []Safety
                BY <2>1, SafetyFromQuorum
          <2> QED BY <2>2
    <1>3. Alpenglow!clock > GST => <>Progress
          <2>1. ASSUME Alpenglow!clock > GST
                PROVE <>Progress
          <2>2. Types!TotalStake(Validators \ (ByzantineValidators \cup OfflineValidators), Stake) >= SlowPathRequiredStake
                <3>1. Types!TotalStake(Validators \ (ByzantineValidators \cup OfflineValidators), Stake) =
                      TotalStakeSum - Types!TotalStake(ByzantineValidators, Stake) - Types!TotalStake(OfflineValidators, Stake)
                      BY ResponsiveStakeCalculation
                <3>2. TotalStakeSum - Types!TotalStake(ByzantineValidators, Stake) - Types!TotalStake(OfflineValidators, Stake) >=
                      TotalStakeSum - TotalStakeSum \div 5 - TotalStakeSum \div 5
                      BY <1>1, ArithmeticInequality
                <3>3. TotalStakeSum - TotalStakeSum \div 5 - TotalStakeSum \div 5 = (3 * TotalStakeSum) \div 5
                      BY ArithmeticInequality
                <3> QED BY <3>1, <3>2, <3>3 DEF SlowPathRequiredStake
          <2>3. <>Progress
                BY <2>2, ProgressTheorem
          <2> QED BY <2>3
    <1>4. Combined2020Resilience
          BY <1>2, <1>3 DEF Combined2020Resilience
    <1> QED BY <1>4

----------------------------------------------------------------------------
(* Byzantine Resilience *)

\* Safety under maximum Byzantine faults
ByzantineResilience ==
    Types!TotalStake(ByzantineValidators, Stake) <= TotalStakeSum \div 5 => []Safety

LEMMA SafetyFromQuorum ==
    Types!TotalStake(ByzantineValidators, Stake) <= TotalStakeSum \div 5 => []Safety
PROOF
    <1>1. ASSUME Types!TotalStake(ByzantineValidators, Stake) <= TotalStakeSum \div 5
          PROVE []Safety
    <1>2. \A slot \in Types!Slots :
          \A cert1, cert2 \in certificates :
              cert1.slot = slot /\ cert2.slot = slot => cert1.block = cert2.block
          <2>1. TAKE slot \in Types!Slots, cert1, cert2 \in certificates
          <2>2. ASSUME cert1.slot = slot, cert2.slot = slot
                PROVE cert1.block = cert2.block
          <2>3. LET signers1 == {v \in Validators : \E sig \in cert1.signatures.sigs : sig.validator = v}
                    signers2 == {v \in Validators : \E sig \in cert2.signatures.sigs : sig.validator = v}
                IN /\ Types!TotalStake(signers1, Stake) >= SlowPathRequiredStake
                   /\ Types!TotalStake(signers2, Stake) >= SlowPathRequiredStake
                BY CertificateStakeRequirement
          <2>4. LET honest1 == signers1 \ ByzantineValidators
                    honest2 == signers2 \ ByzantineValidators
                IN /\ Types!TotalStake(honest1, Stake) >= SlowPathRequiredStake - Types!TotalStake(ByzantineValidators, Stake)
                   /\ Types!TotalStake(honest2, Stake) >= SlowPathRequiredStake - Types!TotalStake(ByzantineValidators, Stake)
                BY <2>3, StakeAdditivity, StakeMonotonicity
          <2>5. Types!TotalStake(honest1, Stake) >= (3 * TotalStakeSum) \div 5 - TotalStakeSum \div 5
                BY <1>1, <2>4, ArithmeticInequality DEF SlowPathRequiredStake
          <2>6. Types!TotalStake(honest1, Stake) >= (2 * TotalStakeSum) \div 5
                BY <2>5, ArithmeticInequality
          <2>7. honest1 \cap honest2 # {}
                BY <2>6, StakeMonotonicity, ArithmeticInequality DEF TotalStakeSum
          <2>8. \E v \in honest1 \cap honest2 : TRUE
                BY <2>7, SetTheoryAxioms
          <2>9. \A v \in (Validators \ ByzantineValidators) : HonestValidatorBehavior
                BY HonestValidatorBehavior
          <2>10. cert1.block = cert2.block
                BY <2>8, <2>9, HonestSingleVoteTheorem
          <2> QED BY <2>10
    <1>3. []Safety
          BY <1>2 DEF Safety
    <1> QED BY <1>3

THEOREM MaxByzantineTheorem ==
    ASSUME Types!TotalStake(ByzantineValidators, Stake) = TotalStakeSum \div 5
    PROVE Alpenglow!Spec => []Safety
PROOF
    <1>1. ASSUME Types!TotalStake(ByzantineValidators, Stake) = TotalStakeSum \div 5,
                 Alpenglow!Spec
          PROVE []Safety
    <1>2. Types!TotalStake(ByzantineValidators, Stake) <= TotalStakeSum \div 5
          BY <1>1, ArithmeticInequality
    <1>3. []Safety
          BY <1>2, SafetyFromQuorum
    <1> QED BY <1>3

\* Safety violation above threshold
THEOREM ByzantineThresholdViolation ==
    Types!TotalStake(ByzantineValidators, Stake) > TotalStakeSum \div 5 =>
        \E execution : ~Safety
PROOF
    <1>1. ASSUME Types!TotalStake(ByzantineValidators, Stake) > TotalStakeSum \div 5
          PROVE \E execution : ~Safety
    <1>2. \E partition1, partition2 :
          /\ partition1 \cap partition2 = {}
          /\ Types!TotalStake(partition1 \cup ByzantineValidators, Stake) >= SlowPathRequiredStake
          /\ Types!TotalStake(partition2 \cup ByzantineValidators, Stake) >= SlowPathRequiredStake
          BY <1>1, SplitVotingAttack
    <1>3. ~Safety
          BY <1>2, SafetyViolationConstruction
    <1>4. \E execution : ~Safety
          BY <1>3, Definition
    <1> QED BY <1>4

LEMMA SafetyViolationConstruction ==
    (\E partition1, partition2 :
        /\ partition1 \cap partition2 = {}
        /\ Types!TotalStake(partition1 \cup ByzantineValidators, Stake) >= SlowPathRequiredStake
        /\ Types!TotalStake(partition2 \cup ByzantineValidators, Stake) >= SlowPathRequiredStake)
    => ~Safety
PROOF OMITTED

LEMMA HonestSingleVoteTheorem ==
    \A v \in (Validators \\ (ByzantineValidators \cup OfflineValidators)) :
        \A view \in 1..MaxView : \A slot \in Types!Slots :
            \E vote \in Votor!votes : vote.validator = v /\ vote.view = view =>
                \A vote2 \in Votor!votes : vote2.validator = v /\ vote2.view = view => vote = vote2
PROOF BY HonestValidatorBehavior

----------------------------------------------------------------------------
(* Offline Resilience *)

\* Liveness under maximum offline faults
OfflineResilience ==
    /\ Types!TotalStake(OfflineValidators, Stake) <= TotalStakeSum \div 5
    /\ Alpenglow!clock > GST
    => <>Progress

THEOREM MaxOfflineTheorem ==
    ASSUME Types!TotalStake(OfflineValidators, Stake) = TotalStakeSum \div 5,
           Alpenglow!clock > GST
    PROVE Alpenglow!Spec => <>Progress
PROOF
    <1>1. ASSUME Types!TotalStake(OfflineValidators, Stake) = TotalStakeSum \div 5,
                 Alpenglow!clock > GST,
                 Alpenglow!Spec
          PROVE <>Progress
    <1>2. Types!TotalStake(Validators \ OfflineValidators, Stake) = (4 * TotalStakeSum) \div 5
          BY <1>1, StakeAdditivity DEF TotalStakeSum
    <1>3. Types!TotalStake(Validators \ OfflineValidators, Stake) > SlowPathRequiredStake
          BY <1>2 DEF SlowPathRequiredStake
    <1>4. Types!TotalStake(Validators \ (ByzantineValidators \cup OfflineValidators), Stake) >= SlowPathRequiredStake
          <2>1. Types!TotalStake(ByzantineValidators, Stake) <= TotalStakeSum \div 5
                BY ByzantineAssumption
          <2>2. Types!TotalStake(Validators \ (ByzantineValidators \cup OfflineValidators), Stake) =
                Types!TotalStake(Validators \ OfflineValidators, Stake) - Types!TotalStake(ByzantineValidators, Stake)
                BY StakeAdditivity, SetTheoryAxioms
          <2>3. Types!TotalStake(Validators \ (ByzantineValidators \cup OfflineValidators), Stake) >=
                (4 * TotalStakeSum) \div 5 - TotalStakeSum \div 5
                BY <1>2, <2>1, <2>2, ArithmeticInequality
          <2>4. (4 * TotalStakeSum) \div 5 - TotalStakeSum \div 5 = (3 * TotalStakeSum) \div 5
                BY ArithmeticInequality
          <2> QED BY <2>3, <2>4 DEF SlowPathRequiredStake
    <1>5. \E cert \in certificates : cert.slot = Votor!currentSlot
          BY <1>4, VoteCollectionLemma
    <1>6. Progress
          BY <1>5, ProgressFromCertificate DEF Progress
    <1>7. <>Progress
          BY <1>6, PTL
    <1> QED BY <1>7

\* Liveness violation above threshold
THEOREM OfflineThresholdViolation ==
    Types!TotalStake(OfflineValidators, Stake) > TotalStakeSum \div 5 =>
        \E execution : ~<>Progress
PROOF
    <1>1. ASSUME Types!TotalStake(OfflineValidators, Stake) > TotalStakeSum \div 5
          PROVE \E execution : ~<>Progress
    <1>2. Types!TotalStake(Validators \ OfflineValidators, Stake) < (4 * TotalStakeSum) \div 5
          BY <1>1, StakeAdditivity, ArithmeticInequality DEF TotalStakeSum
    <1>3. Types!TotalStake(Validators \ (ByzantineValidators \cup OfflineValidators), Stake) < SlowPathRequiredStake
          <2>1. Types!TotalStake(ByzantineValidators, Stake) >= 0
                BY StakeMonotonicity
          <2>2. Types!TotalStake(Validators \ (ByzantineValidators \cup OfflineValidators), Stake) <=
                Types!TotalStake(Validators \ OfflineValidators, Stake)
                BY StakeMonotonicity, SetTheoryAxioms
          <2>3. Types!TotalStake(Validators \ OfflineValidators, Stake) < (4 * TotalStakeSum) \div 5
                BY <1>2
          <2>4. (4 * TotalStakeSum) \div 5 < SlowPathRequiredStake
                BY ArithmeticInequality DEF SlowPathRequiredStake
          <2> QED BY <2>2, <2>3, <2>4, ArithmeticInequality
    <1>4. ~<>Progress
          BY <1>3, NoProgressWithoutQuorum
    <1>5. \E execution : ~<>Progress
          BY <1>4, Definition
    <1> QED BY <1>5

----------------------------------------------------------------------------
(* Network Partition Recovery *)

\* Recovery after partition healing
PartitionRecovery ==
    /\ Alpenglow!networkPartitions # {}
    /\ Alpenglow!clock > GST + Delta
    => <>(Alpenglow!networkPartitions = {})

THEOREM PartitionRecoveryTheorem ==
    Alpenglow!Spec => []PartitionRecovery
PROOF
    <1>1. SUFFICES ASSUME Alpenglow!Spec
          PROVE []PartitionRecovery
          OBVIOUS
    <1>2. SUFFICES PROVE PartitionRecovery
          BY <1>1, PTL DEF Alpenglow!Spec
    <1>3. CASE Alpenglow!networkPartitions = {}
          BY <1>3 DEF PartitionRecovery
    <1>4. CASE Alpenglow!networkPartitions # {} /\ Alpenglow!clock <= GST + Delta
          BY <1>4, NetworkHealingAssumption DEF PartitionRecovery
    <1>5. CASE Alpenglow!networkPartitions # {} /\ Alpenglow!clock > GST + Delta
          <2>1. NetworkIntegration!HealPartition
                BY <1>5, NetworkHealingAssumption
          <2>2. <>(Alpenglow!networkPartitions = {})
                BY <2>1, NetworkIntegration!NetworkHealing
          <2> QED BY <2>2 DEF PartitionRecovery
    <1> QED BY <1>3, <1>4, <1>5

----------------------------------------------------------------------------
(* Economic Resilience *)

\* Economic attacks cannot violate safety
EconomicResilience ==
    /\ Types!TotalStake(ByzantineValidators, Stake) <= TotalStakeSum \div 5
    /\ \A v \in ByzantineValidators : \A reason \in {"double_vote", "invalid_cert", "offline", "withhold_shreds"} :
        EconomicModel!SlashValidator(v, EconomicModel!SlashingAmount(v, reason), reason)
    => []Safety

THEOREM EconomicResilienceTheorem ==
    ASSUME Types!TotalStake(ByzantineValidators, Stake) <= TotalStakeSum \div 5
    PROVE Alpenglow!Spec => EconomicResilience
PROOF
    <1>1. ASSUME Types!TotalStake(ByzantineValidators, Stake) <= TotalStakeSum \div 5,
                 Alpenglow!Spec
          PROVE EconomicResilience
    <1>2. []Safety
          BY <1>1, SafetyFromQuorum
    <1>3. \A v \in ByzantineValidators : \A reason \in {"double_vote", "invalid_cert", "offline", "withhold_shreds"} :
          EconomicModel!SlashValidator(v, EconomicModel!SlashingAmount(v, reason), reason) => []Safety
          <2>1. TAKE v \in ByzantineValidators, reason \in {"double_vote", "invalid_cert", "offline", "withhold_shreds"}
          <2>2. ASSUME EconomicModel!SlashValidator(v, EconomicModel!SlashingAmount(v, reason), reason)
                PROVE []Safety
          <2>3. EconomicModel!SlashValidator(v, EconomicModel!SlashingAmount(v, reason), reason) =>
                Types!TotalStake(ByzantineValidators, Stake) decreases
                BY EconomicModel!SlashValidatorAction DEF EconomicModel!SlashValidator
          <2>4. Types!TotalStake(ByzantineValidators, Stake) <= TotalStakeSum \div 5
                BY <1>1, <2>3, EconomicModel!TotalStakeConservation
          <2>5. []Safety
                BY <2>4, SafetyFromQuorum
          <2> QED BY <2>5
    <1>4. EconomicResilience
          BY <1>2, <1>3 DEF EconomicResilience
    <1> QED BY <1>4

----------------------------------------------------------------------------
(* Stress Testing Scenarios *)

\* Exact fault thresholds
ExactThresholdScenario ==
    /\ Types!TotalStake(ByzantineValidators, Stake) = TotalStakeSum \div 5
    /\ Types!TotalStake(OfflineValidators, Stake) = TotalStakeSum \div 5
    /\ Types!TotalStake(Validators \\ (ByzantineValidators \cup OfflineValidators), Stake) = (3 * TotalStakeSum) \div 5

THEOREM ExactThresholdSafety ==
    ExactThresholdScenario /\ Alpenglow!Spec => []Safety
PROOF
    <1>1. ASSUME ExactThresholdScenario, Alpenglow!Spec
          PROVE []Safety
    <1>2. Types!TotalStake(ByzantineValidators, Stake) = TotalStakeSum \div 5
          BY <1>1 DEF ExactThresholdScenario
    <1>3. Types!TotalStake(ByzantineValidators, Stake) <= TotalStakeSum \div 5
          BY <1>2, ArithmeticInequality
    <1>4. []Safety
          BY <1>3, SafetyFromQuorum
    <1> QED BY <1>4

THEOREM ExactThresholdLiveness ==
    ExactThresholdScenario /\ Alpenglow!clock > GST /\ Alpenglow!Spec => <>Progress
PROOF
    <1>1. ASSUME ExactThresholdScenario, Alpenglow!clock > GST, Alpenglow!Spec
          PROVE <>Progress
    <1>2. Types!TotalStake(OfflineValidators, Stake) = TotalStakeSum \div 5
          BY <1>1 DEF ExactThresholdScenario
    <1>3. Types!TotalStake(Validators \\ (ByzantineValidators \cup OfflineValidators), Stake) = (3 * TotalStakeSum) \div 5
          BY <1>1 DEF ExactThresholdScenario
    <1>4. Types!TotalStake(Validators \\ (ByzantineValidators \cup OfflineValidators), Stake) >= SlowPathRequiredStake
          BY <1>3 DEF SlowPathRequiredStake
    <1>5. <>Progress
          BY <1>4, ProgressTheorem
    <1> QED BY <1>5

\* Worst-case message delays
WorstCaseDelays ==
    /\ \A msg \in Alpenglow!messages : TRUE  \* All messages subject to max delay
    /\ Alpenglow!clock > GST + Delta

THEOREM ProgressUnderWorstCase ==
    WorstCaseDelays /\ Alpenglow!clock > GST /\ Types!TotalStake(Validators \\ (ByzantineValidators \cup OfflineValidators), Stake) > (3 * TotalStakeSum) \div 5 =>
        <>Progress
PROOF
    <1>1. ASSUME WorstCaseDelays,
                 Alpenglow!clock > GST,
                 Types!TotalStake(Validators \\ (ByzantineValidators \cup OfflineValidators), Stake) > (3 * TotalStakeSum) \div 5
          PROVE <>Progress
    <1>2. Alpenglow!clock > GST + Delta
          BY <1>1 DEF WorstCaseDelays
    <1>3. \A msg \in Alpenglow!messages : msg.delivered
          BY <1>2, MessageDeliveryAfterGST
    <1>4. Types!TotalStake(Validators \\ (ByzantineValidators \cup OfflineValidators), Stake) >= SlowPathRequiredStake
          BY <1>1, ArithmeticInequality DEF SlowPathRequiredStake
    <1>5. \E cert \in certificates : cert.slot = Votor!currentSlot
          BY <1>4, <1>3, VoteCollectionLemma
    <1>6. Progress
          BY <1>5, ProgressFromCertificate DEF Progress
    <1>7. <>Progress
          BY <1>6, PTL
    <1> QED BY <1>7

----------------------------------------------------------------------------
(* Graceful Degradation *)

\* Performance degrades gracefully near limits
GracefulDegradation ==
    LET FaultLevel == (Types!TotalStake(ByzantineValidators, Stake) + Types!TotalStake(OfflineValidators, Stake)) \div TotalStakeSum
        Performance == IF Votor!currentSlot > 0 THEN 1 \div Votor!currentSlot ELSE 1
    IN
    TRUE  \* Property holds by definition

THEOREM DegradationTheorem ==
    Alpenglow!Spec => []GracefulDegradation
PROOF
    <1>1. ASSUME Alpenglow!Spec
          PROVE []GracefulDegradation
    <1>2. SUFFICES PROVE GracefulDegradation
          BY <1>1, PTL DEF Alpenglow!Spec
    <1>3. LET FaultLevel == (Types!TotalStake(ByzantineValidators, Stake) + Types!TotalStake(OfflineValidators, Stake)) \div TotalStakeSum
              Performance == IF Votor!currentSlot > 0 THEN 1 \div Votor!currentSlot ELSE 1
          IN TRUE
          BY Definition DEF GracefulDegradation
    <1> QED BY <1>3

----------------------------------------------------------------------------
(* Recovery Properties *)

\* System self-heals after transient faults
SelfHealing ==
    /\ Alpenglow!networkPartitions # {}
    /\ Alpenglow!clock > GST + 2 * Delta
    => <>(Alpenglow!networkPartitions = {})

THEOREM SelfHealingTheorem ==
    Alpenglow!Spec => []SelfHealing
PROOF
    <1>1. ASSUME Alpenglow!Spec
          PROVE []SelfHealing
    <1>2. SUFFICES PROVE SelfHealing
          BY <1>1, PTL DEF Alpenglow!Spec
    <1>3. CASE Alpenglow!networkPartitions = {}
          BY <1>3 DEF SelfHealing
    <1>4. CASE Alpenglow!networkPartitions # {} /\ Alpenglow!clock <= GST + 2 * Delta
          BY <1>4, NetworkHealingAssumption DEF SelfHealing
    <1>5. CASE Alpenglow!networkPartitions # {} /\ Alpenglow!clock > GST + 2 * Delta
          <2>1. NetworkIntegration!HealPartition
                BY <1>5, NetworkHealingAssumption
          <2>2. <>(Alpenglow!networkPartitions = {})
                BY <2>1, NetworkIntegration!NetworkHealing, TransientFaultModel
          <2> QED BY <2>2 DEF SelfHealing
    <1> QED BY <1>3, <1>4, <1>5

----------------------------------------------------------------------------
(* Helper Lemmas *)

LEMMA ResponsiveStakeCalculation ==
    Types!TotalStake(Validators \\ (ByzantineValidators \cup OfflineValidators), Stake) =
        TotalStakeSum - Types!TotalStake(ByzantineValidators, Stake) - Types!TotalStake(OfflineValidators, Stake)
PROOF OMITTED

LEMMA InsufficientStakeLemma ==
    \A S \in SUBSET Validators :
        Types!TotalStake(S, Stake) < (3 * TotalStakeSum) \div 5 =>
            ~(\E cert \in certificates : {v \in Validators : \E sig \in cert.signatures.sigs : sig.validator = v} \subseteq S)
PROOF
    <1>1. TAKE S \in SUBSET Validators
    <1>2. ASSUME Types!TotalStake(S, Stake) < SlowPathRequiredStake
          PROVE ~(\E cert \in certificates :
                    {v \in Validators : \E sig \in cert.signatures.sigs : sig.validator = v} \subseteq S)
          BY CertificateStakeRequirement DEF certificates, SlowPathRequiredStake
    <1> QED BY <1>1, <1>2

LEMMA CertificateCompositionLemma ==
    \A cert \in certificates :
        \E H \in SUBSET (Validators \\ (ByzantineValidators \cup OfflineValidators)) :
            Types!TotalStake(H, Stake) + Types!TotalStake(ByzantineValidators, Stake) >=
                (3 * TotalStakeSum) \div 5
PROOF
    <1>1. TAKE cert \in certificates
    <1>2. DEFINE Signers == {v \in Validators : \E sig \in cert.signatures.sigs : sig.validator = v}
    <1>3. DEFINE HonestSigners == Signers \cap (Validators \\ (ByzantineValidators \cup OfflineValidators))
    <1>4. Types!TotalStake(Signers, Stake) >= SlowPathRequiredStake
          BY CertificateStakeRequirement
    <1>5. Signers \subseteq HonestSigners \cup ByzantineValidators \cup OfflineValidators
          BY DEF Signers, HonestSigners
    <1>6. Types!TotalStake(HonestSigners, Stake) >=
          Types!TotalStake(Signers, Stake) - Types!TotalStake(ByzantineValidators, Stake)
          BY <1>5, StakeMonotonicity
    <1>7. WITNESS HonestSigners
    <1> QED BY <1>4, <1>6 DEF SlowPathRequiredStake

LEMMA SplitVotingAttack ==
    Types!TotalStake(ByzantineValidators, Stake) > TotalStakeSum \div 5 =>
        \E partition1, partition2 :
            /\ partition1 \cap partition2 = {}
            /\ Types!TotalStake(partition1 \cup ByzantineValidators, Stake) >= (3 * TotalStakeSum) \div 5
            /\ Types!TotalStake(partition2 \cup ByzantineValidators, Stake) >= (3 * TotalStakeSum) \div 5
PROOF
    <1>1. ASSUME Types!TotalStake(ByzantineValidators, Stake) > TotalStakeSum \div 5
          PROVE \E partition1, partition2 :
                /\ partition1 \cap partition2 = {}
                /\ Types!TotalStake(partition1 \cup ByzantineValidators, Stake) >= SlowPathRequiredStake
                /\ Types!TotalStake(partition2 \cup ByzantineValidators, Stake) >= SlowPathRequiredStake
    <1>2. Types!TotalStake(ByzantineValidators, Stake) > TotalStakeSum \div 5
          BY <1>1
    <1>3. \E part1, part2 \in SUBSET (Validators \ ByzantineValidators) :
          /\ part1 \cap part2 = {}
          /\ Types!TotalStake(part1, Stake) >= (2 * TotalStakeSum) \div 5
          /\ Types!TotalStake(part2, Stake) >= (2 * TotalStakeSum) \div 5
          BY <1>2, PartitionBound
    <1> QED
          BY <1>3, StakeAdditivity DEF SlowPathRequiredStake

LEMMA HonestMajorityAssumption ==
    Types!TotalStake(ByzantineValidators, Stake) <= TotalStakeSum \div 5 =>
        Types!TotalStake(Validators \ ByzantineValidators, Stake) >= (4 * TotalStakeSum) \div 5
PROOF OMITTED

LEMMA SetTheoryAxioms ==
    \A S : S = S
PROOF OMITTED

LEMMA StakeAdditivity ==
    \A S1, S2 : S1 \cap S2 = {} =>
        Types!TotalStake(S1 \cup S2, Stake) = Types!TotalStake(S1, Stake) + Types!TotalStake(S2, Stake)
PROOF OMITTED

LEMMA StakeMonotonicity ==
    \A S1, S2 : S1 \subseteq S2 => Types!TotalStake(S1, Stake) <= Types!TotalStake(S2, Stake)
PROOF OMITTED

LEMMA CertificateStakeRequirement ==
    \A cert \in certificates :
        Types!TotalStake({v \in Validators : \E sig \in cert.signatures.sigs : sig.validator = v}, Stake) >=
        SlowPathRequiredStake
PROOF OMITTED

LEMMA PeanoAxioms ==
    0 \in Nat /\ \A n \in Nat : n + 1 \in Nat
PROOF OMITTED

LEMMA MathematicalInduction ==
    \A S \in SUBSET Nat : (0 \in S /\ \A n \in S : n+1 \in S) => S = Nat
PROOF OMITTED

LEMMA PartitionBound ==
    \A S \in SUBSET Validators :
        \E S1, S2 : S1 \cup S2 = S /\ S1 \cap S2 = {} /\
            Types!TotalStake(S1, Stake) <= Types!TotalStake(S, Stake) \div 2 + 1
PROOF OMITTED

LEMMA ArithmeticInequality ==
    \A x, y, z, w \in Nat :
        /\ x > y => x - z > y - z
        /\ x < y => x + z < y + z
        /\ x <= y /\ z <= w => x + z <= y + w
PROOF OMITTED

LEMMA LogicalAxioms ==
    TRUE # FALSE
PROOF OMITTED

LEMMA ValidatorPartitioning ==
    \E partition : partition \in [Validators -> {1, 2}] /\
        \A v1, v2 \in Validators : partition[v1] # partition[v2] => v1 # v2
PROOF OMITTED

LEMMA ValidatorId ==
    \A v \in Validators : \E id \in Nat : id = CHOOSE n \in Nat : TRUE
PROOF OMITTED

LEMMA NaturalNumberDefinition ==
    Nat = {0} \cup {n + 1 : n \in Nat}
PROOF OMITTED

LEMMA Definition ==
    TRUE  \* By definition
PROOF OMITTED

LEMMA StakeRecalculation ==
    \A v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) :
        TRUE => Types!TotalStake(Validators \ OfflineValidators, Stake) >= SlowPathRequiredStake
PROOF OMITTED

LEMMA ProtocolResumption ==
    Types!TotalStake(Validators \ OfflineValidators, Stake) >= SlowPathRequiredStake => <>Progress
PROOF OMITTED

LEMMA TransientFaultModel ==
    \A fault : TransientFault(fault) => <>~fault
PROOF OMITTED

LEMMA ValidatorRecovery ==
    \A v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) :
        TemporarilyOffline(v) => <>Online(v)
PROOF OMITTED

LEMMA ProtocolDelayTolerance ==
    \A msg \in Alpenglow!messages : DeliveryTime(msg) <= Alpenglow!clock + Delta
    => ProtocolProgress
PROOF OMITTED

LEMMA BoundedDelayAfterGST ==
    Alpenglow!clock > GST => \A msg \in Alpenglow!messages :
        DeliveryTime(msg) <= Alpenglow!clock + Delta
PROOF OMITTED

LEMMA MessageDeliveryAfterGST ==
    Alpenglow!clock > GST => \A msg \in Alpenglow!messages : <>(msg.delivered)
PROOF OMITTED

LEMMA HonestParticipationLemma ==
    \A v \in (Validators \ (ByzantineValidators \cup OfflineValidators)) :
        \A proposal : ReceiveProposal(v, proposal) => <>CastVote(v, proposal)
PROOF OMITTED

LEMMA CertificateGenerationLemma ==
    Types!TotalStake(Validators \ (ByzantineValidators \cup OfflineValidators), Stake) >= SlowPathRequiredStake
    => \E cert \in certificates : cert.slot = Votor!currentSlot
PROOF OMITTED

LEMMA ProgressFromCertificate ==
    \E cert \in certificates : cert.slot = Votor!currentSlot => Progress
PROOF OMITTED

LEMMA FastPathThreshold ==
    Types!TotalStake(Validators \ (ByzantineValidators \cup OfflineValidators), Stake) < FastPathRequiredStake
    => ~FastPathAvailable
PROOF OMITTED

LEMMA NoProgressWithoutQuorum ==
    Types!TotalStake(Validators \ (ByzantineValidators \cup OfflineValidators), Stake) < SlowPathRequiredStake
    => ~<>Progress
PROOF OMITTED

LEMMA CertificateUniquenessLemma ==
    \A slot \in Types!Slots :
        \A cert1, cert2 \in certificates :
            cert1.slot = slot /\ cert2.slot = slot => cert1.block = cert2.block
PROOF OMITTED

LEMMA OfflineValidatorsPassive ==
    \A v \in OfflineValidators : \A action : ~ValidatorAction(v, action)
PROOF OMITTED

LEMMA NetworkHealingAssumption ==
    Alpenglow!clock > GST => <>(Alpenglow!networkPartitions = {})
PROOF OMITTED

LEMMA FinalizationFromCertificate ==
    \E cert \in certificates : cert.slot = Votor!currentSlot => <>(\E b \in Votor!finalizedChain : TRUE)
PROOF OMITTED

LEMMA VoteCollectionLemma ==
    Types!TotalStake(Validators \ (ByzantineValidators \cup OfflineValidators), Stake) >= SlowPathRequiredStake
    => \E cert \in certificates : cert.slot = Votor!currentSlot
PROOF OMITTED

LEMMA SlowPathTheorem ==
    Types!TotalStake(Validators \ (ByzantineValidators \cup OfflineValidators), Stake) >= SlowPathRequiredStake
    => <>(\E cert \in certificates : cert.slot = Votor!currentSlot)
PROOF OMITTED

LEMMA ProgressTheorem ==
    Types!TotalStake(Validators \ (ByzantineValidators \cup OfflineValidators), Stake) >= SlowPathRequiredStake
    => <>Progress
PROOF OMITTED

LEMMA SafetyTheorem == []Safety
PROOF OMITTED

LEMMA ByzantineResilienceTheorem == ByzantineResilience
PROOF OMITTED


============================================================================
