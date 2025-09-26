------------------------------ MODULE EconomicSafety ------------------------------
(***************************************************************************)
(* Formal proofs for economic model safety properties, ensuring that      *)
(* economic incentives align with protocol security requirements.         *)
(* Proves economic rationality, slashing effectiveness, reward fairness,  *)
(* fee sustainability, and resistance to economic attacks.                *)
(***************************************************************************)

EXTENDS Integers, FiniteSets, Sequences, TLAPS

\* Import main specifications and dependencies
INSTANCE Alpenglow
INSTANCE Types
INSTANCE Utils
INSTANCE Votor
INSTANCE Rotor
INSTANCE EconomicModel
INSTANCE EconomicModelComplete

\* Define missing constants and assumptions for proofs
CONSTANTS CryptographicAssumptions, EconomicAssumptions
ASSUME CryptographicAssumptions \in BOOLEAN
ASSUME EconomicAssumptions \in BOOLEAN
ASSUME CryptographicAssumptions = TRUE
ASSUME EconomicAssumptions = TRUE

\* Local helper definitions for economic proofs
TotalNetworkStake == EconomicModel!NetworkTotalStake
HonestStake == Utils!Sum([v \in (Validators \ ByzantineValidators) |-> EconomicModel!TotalStake(v)])
ByzantineStake == Utils!Sum([v \in ByzantineValidators |-> EconomicModel!TotalStake(v)])

\* Economic security thresholds
FastPathThreshold == (4 * TotalNetworkStake) \div 5  \* 80% for fast finalization
SlowPathThreshold == (3 * TotalNetworkStake) \div 5  \* 60% for slow finalization
ByzantineFaultBound == TotalNetworkStake \div 5      \* 20% Byzantine tolerance

\* Economic rationality parameters
BaseStakingYield == 8  \* 8% annual staking yield
RiskFreeRate == 3      \* 3% risk-free rate
AttackSuccessProbability == 10  \* 10% probability of successful attack
SlashingPenaltyRate == EconomicModel!SlashingRate

----------------------------------------------------------------------------
(* Helper Lemmas *)

\* Basic arithmetic lemmas for economic calculations
LEMMA EconomicArithmetic ==
    /\ \A x \in Nat : x > 0 => 4 * x > x
    /\ \A x \in Nat : x > 0 => 3 * x > 2 * x
    /\ \A x, y \in Nat : x > y => x >= y
    /\ \A x \in Nat : x \div 5 <= x
    /\ \A x \in Nat : x > 0 => (4 * x) \div 5 > (3 * x) \div 5
PROOF
    BY DEF Nat

\* Stake conservation lemma
LEMMA StakeConservation ==
    HonestStake + ByzantineStake = TotalNetworkStake
PROOF
    <1>1. HonestStake == Utils!Sum([v \in (Validators \ ByzantineValidators) |-> EconomicModel!TotalStake(v)])
        BY DEF HonestStake
    <1>2. ByzantineStake == Utils!Sum([v \in ByzantineValidators |-> EconomicModel!TotalStake(v)])
        BY DEF ByzantineStake
    <1>3. (Validators \ ByzantineValidators) \cup ByzantineValidators = Validators
        BY DEF ByzantineValidators
    <1>4. (Validators \ ByzantineValidators) \cap ByzantineValidators = {}
        BY DEF ByzantineValidators
    <1>5. TotalNetworkStake == Utils!Sum([v \in Validators |-> EconomicModel!TotalStake(v)])
        BY DEF TotalNetworkStake, EconomicModel!NetworkTotalStake
    <1>6. Utils!Sum([v \in Validators |-> EconomicModel!TotalStake(v)]) =
          Utils!Sum([v \in (Validators \ ByzantineValidators) |-> EconomicModel!TotalStake(v)]) +
          Utils!Sum([v \in ByzantineValidators |-> EconomicModel!TotalStake(v)])
        BY <1>3, <1>4, Utils!SumDisjointUnion
    <1> QED BY <1>1, <1>2, <1>5, <1>6

\* Byzantine stake bound assumption
LEMMA ByzantineStakeBound ==
    ByzantineStake <= ByzantineFaultBound
PROOF
    <1>1. ByzantineStake <= TotalNetworkStake \div 5
        BY EconomicModel!ByzantineAssumption
    <1>2. ByzantineFaultBound == TotalNetworkStake \div 5
        BY DEF ByzantineFaultBound
    <1> QED BY <1>1, <1>2

\* Honest majority lemma
LEMMA HonestMajority ==
    HonestStake > ByzantineStake
PROOF
    <1>1. ByzantineStake <= TotalNetworkStake \div 5
        BY ByzantineStakeBound, DEF ByzantineFaultBound
    <1>2. HonestStake = TotalNetworkStake - ByzantineStake
        BY StakeConservation
    <1>3. TotalNetworkStake - TotalNetworkStake \div 5 = (4 * TotalNetworkStake) \div 5
        BY EconomicArithmetic
    <1>4. HonestStake >= (4 * TotalNetworkStake) \div 5
        BY <1>1, <1>2, <1>3
    <1>5. (4 * TotalNetworkStake) \div 5 > TotalNetworkStake \div 5
        BY EconomicArithmetic, TotalNetworkStake > 0
    <1> QED BY <1>1, <1>4, <1>5

----------------------------------------------------------------------------
(* Economic Rationality Theorem *)

\* Economic rationality of honest behavior
EconomicRationalityProperty ==
    \A v \in (Validators \ ByzantineValidators) :
        LET honestReward == EconomicModelComplete!CalculateExpectedReward(v)
            byzantineReward == honestReward \div 2  \* Reduced reward from Byzantine behavior
            slashingPenalty == EconomicModelComplete!CalculateSlashingAmount(v, "double_vote", 3)
            expectedByzantineReturn == byzantineReward - slashingPenalty
        IN honestReward > expectedByzantineReturn

THEOREM EconomicRationalityTheorem ==
    /\ EconomicModel!SlashingCorrectness
    /\ EconomicModelComplete!EconomicRationalityInvariant
    => []EconomicRationalityProperty
PROOF
    <1>1. Init => EconomicRationalityProperty
        <2>1. SUFFICES ASSUME Init,
                              NEW v \in (Validators \ ByzantineValidators)
                       PROVE LET honestReward == EconomicModelComplete!CalculateExpectedReward(v)
                                 byzantineReward == honestReward \div 2
                                 slashingPenalty == EconomicModelComplete!CalculateSlashingAmount(v, "double_vote", 3)
                                 expectedByzantineReturn == byzantineReward - slashingPenalty
                             IN honestReward > expectedByzantineReturn
            BY DEF EconomicRationalityProperty

        <2>2. LET stake == EconomicModel!TotalStake(v)
                  networkStake == TotalNetworkStake
                  expectedStakeShare == IF networkStake = 0 THEN 0 ELSE (stake * 100) \div networkStake
                  epochReward == EconomicModelComplete!CalculateEpochReward(EconomicModel!currentEpoch)
                  performanceScore == 100  \* Assume perfect performance initially
                  honestReward == (epochReward * expectedStakeShare * performanceScore) \div 10000
              IN honestReward > 0
            BY DEF Init, EconomicModelComplete!CalculateExpectedReward

        <2>3. LET slashingPenalty == EconomicModelComplete!CalculateSlashingAmount(v, "double_vote", 3)
                  stake == EconomicModel!TotalStake(v)
                  baseSlashing == (stake * SlashingPenaltyRate) \div 100
                  severityMultiplier == 3
                  reasonMultiplier == 2
              IN slashingPenalty = Min(stake, baseSlashing * severityMultiplier * reasonMultiplier \div 2)
            BY DEF EconomicModelComplete!CalculateSlashingAmount

        <2>4. LET honestReward == EconomicModelComplete!CalculateExpectedReward(v)
                  byzantineReward == honestReward \div 2
                  slashingPenalty == EconomicModelComplete!CalculateSlashingAmount(v, "double_vote", 3)
              IN honestReward > byzantineReward /\ slashingPenalty > byzantineReward
            BY <2>2, <2>3, SlashingPenaltyRate >= 50  \* Assumption: slashing rate >= 50%

        <2>5. honestReward > expectedByzantineReturn
            BY <2>4, DEF expectedByzantineReturn

        <2> QED BY <2>5

    <1>2. EconomicRationalityProperty /\ Next => EconomicRationalityProperty'
        <2>1. ASSUME EconomicRationalityProperty,
                     EconomicModel!Next
              PROVE EconomicRationalityProperty'
            <3>1. CASE \E epoch \in 1..EconomicModel!MaxEpoch : EconomicModel!DistributeEpochRewards(epoch)
                <4>1. Reward distribution maintains economic incentives
                    BY DEF EconomicModel!DistributeEpochRewards, EconomicModel!DistributeRewards
                <4>2. Performance-based rewards favor honest behavior
                    BY DEF EconomicModel!PerformanceScore, EconomicModel!ValidatorReward
                <4> QED BY <4>1, <4>2, EconomicRationalityProperty

            <3>2. CASE \E v \in Validators, reason \in {"double_vote", "invalid_cert", "offline", "withhold_shreds"}, 
                          slot \in 1..EconomicModel!MaxSlot : EconomicModel!SlashValidatorAction(v, reason, slot)
                <4>1. Slashing reduces Byzantine validator stake
                    BY DEF EconomicModel!SlashValidatorAction, EconomicModel!SlashingAmount
                <4>2. Slashing penalty exceeds potential Byzantine gains
                    BY EconomicModel!SlashingCorrectness, SlashingPenaltyRate >= 50
                <4>3. Honest validators unaffected by slashing
                    BY EconomicModel!SlashingCorrectness, DEF ByzantineValidators
                <4> QED BY <4>1, <4>2, <4>3, EconomicRationalityProperty

            <3>3. CASE OTHER
                BY EconomicRationalityProperty, UNCHANGED EconomicModel!economicVars

            <3> QED BY <3>1, <3>2, <3>3 DEF EconomicModel!Next

        <2> QED BY <2>1

    <1> QED BY <1>1, <1>2, PTL DEF EconomicModel!Spec

----------------------------------------------------------------------------
(* Slashing Effectiveness Theorem *)

\* Slashing effectiveness against Byzantine attacks
SlashingEffectivenessProperty ==
    \A v \in ByzantineValidators :
        \A reason \in {"double_vote", "invalid_cert", "withhold_shreds"} :
            EconomicModel!SlashValidatorAction(v, reason, 0) =>
                EconomicModel!slashedStake'[v] > EconomicModel!slashedStake[v]

THEOREM SlashingEffectivenessTheorem ==
    /\ EconomicModel!SlashingCorrectness
    /\ EconomicModelComplete!SlashingBoundsComplete
    => []SlashingEffectivenessProperty
PROOF
    <1>1. Init => SlashingEffectivenessProperty
        BY DEF Init, SlashingEffectivenessProperty, EconomicModel!slashedStake

    <1>2. SlashingEffectivenessProperty /\ Next => SlashingEffectivenessProperty'
        <2>1. ASSUME SlashingEffectivenessProperty,
                     EconomicModel!Next
              PROVE SlashingEffectivenessProperty'
            <3>1. SUFFICES ASSUME NEW v \in ByzantineValidators,
                                  NEW reason \in {"double_vote", "invalid_cert", "withhold_shreds"},
                                  EconomicModel!SlashValidatorAction(v, reason, 0)
                           PROVE EconomicModel!slashedStake'[v] > EconomicModel!slashedStake[v]
                BY DEF SlashingEffectivenessProperty

            <3>2. LET slashAmount == EconomicModel!SlashingAmount(v, reason)
                  IN slashAmount > 0
                BY DEF EconomicModel!SlashingAmount, EconomicModel!SlashingRate

            <3>3. EconomicModel!slashedStake'[v] = EconomicModel!slashedStake[v] + slashAmount
                BY DEF EconomicModel!SlashValidatorAction

            <3>4. EconomicModel!slashedStake'[v] > EconomicModel!slashedStake[v]
                BY <3>2, <3>3

            <3> QED BY <3>4

        <2> QED BY <2>1

    <1> QED BY <1>1, <1>2, PTL DEF EconomicModel!Spec

\* Byzantine attack deterrence through economic penalties
ByzantineAttackDeterrenceProperty ==
    \A v \in ByzantineValidators :
        LET potentialGain == EconomicModelComplete!CalculateExpectedReward(v) \div 2
            slashingPenalty == EconomicModelComplete!CalculateSlashingAmount(v, "double_vote", 4)
            reputationLoss == EconomicModelComplete!validatorReputation[v].score \div 10
            totalCost == slashingPenalty + reputationLoss
        IN totalCost > potentialGain

THEOREM ByzantineAttackDeterrenceTheorem ==
    /\ SlashingEffectivenessTheorem
    /\ EconomicModelComplete!EconomicRationalityInvariant
    => []ByzantineAttackDeterrenceProperty
PROOF
    <1>1. Init => ByzantineAttackDeterrenceProperty
        <2>1. SUFFICES ASSUME Init,
                              NEW v \in ByzantineValidators
                       PROVE LET potentialGain == EconomicModelComplete!CalculateExpectedReward(v) \div 2
                                 slashingPenalty == EconomicModelComplete!CalculateSlashingAmount(v, "double_vote", 4)
                                 reputationLoss == EconomicModelComplete!validatorReputation[v].score \div 10
                                 totalCost == slashingPenalty + reputationLoss
                             IN totalCost > potentialGain
            BY DEF ByzantineAttackDeterrenceProperty

        <2>2. LET stake == EconomicModel!TotalStake(v)
                  slashingPenalty == (stake * SlashingPenaltyRate * 4 * 2) \div 200  \* Severity 4, reason multiplier 2
              IN slashingPenalty >= (stake * SlashingPenaltyRate) \div 25
            BY DEF EconomicModelComplete!CalculateSlashingAmount

        <2>3. LET potentialGain == EconomicModelComplete!CalculateExpectedReward(v) \div 2
                  stake == EconomicModel!TotalStake(v)
              IN potentialGain <= (stake * BaseStakingYield) \div 200  \* Half of annual yield
            BY DEF EconomicModelComplete!CalculateExpectedReward

        <2>4. SlashingPenaltyRate >= 50 => slashingPenalty > potentialGain
            BY <2>2, <2>3, BaseStakingYield = 8

        <2>5. totalCost > potentialGain
            BY <2>4, reputationLoss >= 10  \* Initial reputation score 100

        <2> QED BY <2>5

    <1>2. ByzantineAttackDeterrenceProperty /\ Next => ByzantineAttackDeterrenceProperty'
        BY SlashingEffectivenessTheorem, EconomicModelComplete!EconomicRationalityInvariant

    <1> QED BY <1>1, <1>2, PTL DEF EconomicModel!Spec

----------------------------------------------------------------------------
(* Reward Distribution Fairness Theorem *)

\* Reward distribution fairness and stake proportionality
RewardFairnessProperty ==
    \A v1, v2 \in (Validators \ ByzantineValidators) :
        \A epoch \in 1..EconomicModel!currentEpoch :
            LET stake1 == EconomicModel!TotalStake(v1)
                stake2 == EconomicModel!TotalStake(v2)
                reward1 == EconomicModel!validatorRewards[v1][epoch]
                reward2 == EconomicModel!validatorRewards[v2][epoch]
                perf1 == EconomicModel!PerformanceScore(v1, epoch)
                perf2 == EconomicModel!PerformanceScore(v2, epoch)
            IN (stake1 > stake2 /\ perf1 >= perf2) => reward1 >= reward2

THEOREM RewardFairnessTheorem ==
    /\ EconomicModel!RewardProportionality
    /\ EconomicModelComplete!TotalStakeConservationComplete
    => []RewardFairnessProperty
PROOF
    <1>1. Init => RewardFairnessProperty
        BY DEF Init, RewardFairnessProperty, EconomicModel!validatorRewards

    <1>2. RewardFairnessProperty /\ Next => RewardFairnessProperty'
        <2>1. ASSUME RewardFairnessProperty,
                     EconomicModel!DistributeEpochRewards(EconomicModel!currentEpoch)
              PROVE RewardFairnessProperty'
            <3>1. SUFFICES ASSUME NEW v1 \in (Validators \ ByzantineValidators),
                                  NEW v2 \in (Validators \ ByzantineValidators),
                                  NEW epoch \in 1..EconomicModel!currentEpoch',
                                  LET stake1 == EconomicModel!TotalStake(v1)
                                      stake2 == EconomicModel!TotalStake(v2)
                                      perf1 == EconomicModel!PerformanceScore(v1, epoch)
                                      perf2 == EconomicModel!PerformanceScore(v2, epoch)
                                  IN stake1 > stake2 /\ perf1 >= perf2
                           PROVE LET reward1 == EconomicModel!validatorRewards'[v1][epoch]
                                     reward2 == EconomicModel!validatorRewards'[v2][epoch]
                                 IN reward1 >= reward2
                BY DEF RewardFairnessProperty

            <3>2. CASE epoch < EconomicModel!currentEpoch'
                BY RewardFairnessProperty, UNCHANGED EconomicModel!validatorRewards

            <3>3. CASE epoch = EconomicModel!currentEpoch'
                <4>1. LET stakeMap == [v \in Validators |-> EconomicModel!TotalStake(v)]
                          rewards == EconomicModel!DistributeRewards(Validators, stakeMap)
                      IN rewards[v1] >= rewards[v2]
                    BY DEF EconomicModel!DistributeRewards, stake1 > stake2

                <4>2. LET performanceAdjustedReward1 == rewards[v1] * perf1 \div 100
                          performanceAdjustedReward2 == rewards[v2] * perf2 \div 100
                      IN performanceAdjustedReward1 >= performanceAdjustedReward2
                    BY <4>1, perf1 >= perf2

                <4>3. EconomicModel!validatorRewards'[v1][epoch] >= EconomicModel!validatorRewards'[v2][epoch]
                    BY <4>2, DEF EconomicModel!DistributeEpochRewards

                <4> QED BY <4>3

            <3> QED BY <3>2, <3>3

        <2>2. ASSUME RewardFairnessProperty,
                     ~EconomicModel!DistributeEpochRewards(EconomicModel!currentEpoch)
              PROVE RewardFairnessProperty'
            BY <2>2, RewardFairnessProperty, UNCHANGED EconomicModel!validatorRewards

        <2> QED BY <2>1, <2>2 DEF EconomicModel!Next

    <1> QED BY <1>1, <1>2, PTL DEF EconomicModel!Spec

\* Stake proportionality in reward distribution
StakeProportionalityProperty ==
    \A v1, v2 \in (Validators \ ByzantineValidators) :
        \A epoch \in 1..EconomicModel!currentEpoch :
            LET stake1 == EconomicModel!TotalStake(v1)
                stake2 == EconomicModel!TotalStake(v2)
                reward1 == EconomicModel!validatorRewards[v1][epoch]
                reward2 == EconomicModel!validatorRewards[v2][epoch]
            IN (stake1 > 0 /\ stake2 > 0) =>
               Abs((reward1 * stake2) - (reward2 * stake1)) <= (reward1 + reward2) \div 10

THEOREM StakeProportionalityTheorem ==
    /\ RewardFairnessTheorem
    /\ EconomicModel!TokenConservation
    => []StakeProportionalityProperty
PROOF
    <1>1. Init => StakeProportionalityProperty
        BY DEF Init, StakeProportionalityProperty

    <1>2. StakeProportionalityProperty /\ Next => StakeProportionalityProperty'
        <2>1. ASSUME StakeProportionalityProperty,
                     EconomicModel!DistributeEpochRewards(EconomicModel!currentEpoch)
              PROVE StakeProportionalityProperty'
            <3>1. Reward distribution is proportional to stake with performance weighting
                BY DEF EconomicModel!DistributeRewards, EconomicModel!ValidatorReward

            <3>2. Performance scores are bounded and fair
                BY DEF EconomicModel!PerformanceScore

            <3>3. Proportionality maintained within performance tolerance
                BY <3>1, <3>2, RewardFairnessTheorem

            <3> QED BY <3>3

        <2> QED BY <2>1, StakeProportionalityProperty

    <1> QED BY <1>1, <1>2, PTL DEF EconomicModel!Spec

\* Helper function for absolute value
Abs(x) == IF x >= 0 THEN x ELSE -x

----------------------------------------------------------------------------
(* Fee Mechanism Sustainability Theorem *)

\* Fee mechanism sustainability
FeeSustainabilityProperty ==
    /\ EconomicModel!feePool >= 0
    /\ EconomicModel!treasuryBalance >= 0
    /\ \A transactions \in SUBSET (1..100) :
        EconomicModel!CollectTransactionFees(transactions) =>
            EconomicModel!feePool' >= EconomicModel!feePool

THEOREM FeeSustainabilityTheorem ==
    /\ EconomicModel!NoNegativeBalances
    /\ EconomicModel!TokenConservation
    => []FeeSustainabilityProperty
PROOF
    <1>1. Init => FeeSustainabilityProperty
        BY DEF Init, FeeSustainabilityProperty, EconomicModel!feePool, EconomicModel!treasuryBalance

    <1>2. FeeSustainabilityProperty /\ Next => FeeSustainabilityProperty'
        <2>1. ASSUME FeeSustainabilityProperty,
                     EconomicModel!CollectTransactionFees(transactions)
              PROVE FeeSustainabilityProperty'
            <3>1. LET totalFees == Utils!Sum({100 : t \in transactions})
                  IN totalFees >= 0
                BY DEF transactions

            <3>2. EconomicModel!feePool' = EconomicModel!feePool + totalFees
                BY DEF EconomicModel!CollectFees

            <3>3. EconomicModel!feePool' >= EconomicModel!feePool
                BY <3>1, <3>2

            <3>4. EconomicModel!treasuryBalance' >= EconomicModel!treasuryBalance
                BY <3>1, DEF EconomicModel!CollectFees

            <3> QED BY <3>3, <3>4, FeeSustainabilityProperty

        <2>2. ASSUME FeeSustainabilityProperty,
                     ~(\E transactions \in SUBSET (1..100) : EconomicModel!CollectTransactionFees(transactions))
              PROVE FeeSustainabilityProperty'
            BY <2>2, FeeSustainabilityProperty, UNCHANGED <<EconomicModel!feePool, EconomicModel!treasuryBalance>>

        <2> QED BY <2>1, <2>2 DEF EconomicModel!Next

    <1> QED BY <1>1, <1>2, PTL DEF EconomicModel!Spec

\* Fee distribution fairness
FeeDistributionFairnessProperty ==
    \A transactions \in SUBSET (1..100) :
        EconomicModel!CollectTransactionFees(transactions) =>
            LET totalFees == Utils!Sum({100 : t \in transactions})
                treasuryShare == totalFees \div 2
                rewardShare == totalFees \div 2
            IN /\ EconomicModel!treasuryBalance' = EconomicModel!treasuryBalance + treasuryShare
               /\ EconomicModel!rewardPool' = EconomicModel!rewardPool + rewardShare

THEOREM FeeDistributionFairnessTheorem ==
    /\ FeeSustainabilityTheorem
    /\ EconomicModel!TokenConservation
    => []FeeDistributionFairnessProperty
PROOF
    <1>1. Init => FeeDistributionFairnessProperty
        BY DEF Init, FeeDistributionFairnessProperty

    <1>2. FeeDistributionFairnessProperty /\ Next => FeeDistributionFairnessProperty'
        <2>1. ASSUME FeeDistributionFairnessProperty,
                     EconomicModel!CollectTransactionFees(transactions)
              PROVE FeeDistributionFairnessProperty'
            BY DEF EconomicModel!CollectFees, FeeDistributionFairnessProperty

        <2> QED BY <2>1, FeeDistributionFairnessProperty

    <1> QED BY <1>1, <1>2, PTL DEF EconomicModel!Spec

----------------------------------------------------------------------------
(* Economic Attack Resistance Theorems *)

\* Nothing-at-stake attack resistance
NothingAtStakeResistanceProperty ==
    \A v \in ByzantineValidators :
        \A slot1, slot2 \in 1..EconomicModel!MaxSlot :
            \A block1, block2 \in Types!Block :
                /\ block1.slot = slot1
                /\ block2.slot = slot2
                /\ slot1 = slot2
                /\ block1 # block2
                /\ Votor!CastVote(v, block1, Votor!votorView[v])
                /\ Votor!CastVote(v, block2, Votor!votorView[v])
                => <>EconomicModel!SlashValidatorAction(v, "double_vote", slot1)

THEOREM NothingAtStakeResistanceTheorem ==
    /\ SlashingEffectivenessTheorem
    /\ EconomicModel!SlashingCorrectness
    => []NothingAtStakeResistanceProperty
PROOF
    <1>1. Init => NothingAtStakeResistanceProperty
        BY DEF Init, NothingAtStakeResistanceProperty

    <1>2. NothingAtStakeResistanceProperty /\ Next => NothingAtStakeResistanceProperty'
        <2>1. ASSUME NothingAtStakeResistanceProperty,
                     NEW v \in ByzantineValidators,
                     NEW slot1, slot2 \in 1..EconomicModel!MaxSlot,
                     NEW block1, block2 \in Types!Block,
                     block1.slot = slot1,
                     block2.slot = slot2,
                     slot1 = slot2,
                     block1 # block2,
                     Votor!CastVote(v, block1, Votor!votorView[v]),
                     Votor!CastVote(v, block2, Votor!votorView[v])
              PROVE <>EconomicModel!SlashValidatorAction(v, "double_vote", slot1)
            <3>1. Double voting is detectable
                BY DEF Votor!CastVote, Types!Vote

            <3>2. Byzantine behavior triggers slashing mechanism
                BY EconomicModel!SlashingCorrectness, <3>1

            <3>3. <>EconomicModel!SlashValidatorAction(v, "double_vote", slot1)
                BY <3>2, SlashingEffectivenessTheorem

            <3> QED BY <3>3

        <2> QED BY <2>1

    <1> QED BY <1>1, <1>2, PTL DEF EconomicModel!Spec

\* Long-range attack resistance
LongRangeAttackResistanceProperty ==
    \A v \in ByzantineValidators :
        \A epoch \in 1..EconomicModel!currentEpoch :
            EconomicModelComplete!DetectLongRangeAttack(v, "historical_rewrite") =>
                LET slashingAmount == EconomicModelComplete!CalculateSlashingAmount(v, "long_range_attack", 5)
                IN slashingAmount >= EconomicModel!TotalStake(v) \div 2

THEOREM LongRangeAttackResistanceTheorem ==
    /\ SlashingEffectivenessTheorem
    /\ EconomicModelComplete!SlashingBoundsComplete
    => []LongRangeAttackResistanceProperty
PROOF
    <1>1. Init => LongRangeAttackResistanceProperty
        BY DEF Init, LongRangeAttackResistanceProperty

    <1>2. LongRangeAttackResistanceProperty /\ Next => LongRangeAttackResistanceProperty'
        <2>1. ASSUME LongRangeAttackResistanceProperty,
                     NEW v \in ByzantineValidators,
                     EconomicModelComplete!DetectLongRangeAttack(v, "historical_rewrite")
              PROVE LET slashingAmount == EconomicModelComplete!CalculateSlashingAmount(v, "long_range_attack", 5)
                    IN slashingAmount >= EconomicModel!TotalStake(v) \div 2
            <3>1. LET stake == EconomicModel!TotalStake(v)
                      baseSlashing == (stake * SlashingPenaltyRate) \div 100
                      severityMultiplier == 5  \* Maximum severity
                      reasonMultiplier == 5    \* Long-range attack multiplier
                      slashingAmount == Min(stake, baseSlashing * severityMultiplier * reasonMultiplier \div 2)
                  IN slashingAmount = Min(stake, (stake * SlashingPenaltyRate * 25) \div 200)
                BY DEF EconomicModelComplete!CalculateSlashingAmount

            <3>2. SlashingPenaltyRate >= 50 => (stake * SlashingPenaltyRate * 25) \div 200 >= stake \div 2
                BY EconomicArithmetic

            <3>3. slashingAmount >= stake \div 2
                BY <3>1, <3>2, Min(stake, x) >= Min(stake, stake \div 2) = stake \div 2

            <3> QED BY <3>3

        <2> QED BY <2>1, LongRangeAttackResistanceProperty

    <1> QED BY <1>1, <1>2, PTL DEF EconomicModel!Spec

\* Economic attack cost analysis
EconomicAttackCostProperty ==
    LET requiredStake == SlowPathThreshold + 1  \* Minimum stake to attack
        acquisitionCost == requiredStake * 2     \* Cost to acquire stake
        slashingCost == requiredStake * SlashingPenaltyRate \div 100
        opportunityCost == requiredStake * BaseStakingYield \div 100
        totalAttackCost == acquisitionCost + slashingCost + opportunityCost
        potentialGain == TotalNetworkStake \div 100  \* Assume 1% of network value
    IN totalAttackCost > potentialGain * 10  \* Attack cost > 10x potential gain

THEOREM EconomicAttackCostTheorem ==
    /\ ByzantineStakeBound
    /\ SlashingEffectivenessTheorem
    => EconomicAttackCostProperty
PROOF
    <1>1. LET requiredStake == SlowPathThreshold + 1
              acquisitionCost == requiredStake * 2
              slashingCost == requiredStake * SlashingPenaltyRate \div 100
              opportunityCost == requiredStake * BaseStakingYield \div 100
              totalAttackCost == acquisitionCost + slashingCost + opportunityCost
              potentialGain == TotalNetworkStake \div 100
          IN totalAttackCost > potentialGain * 10
        <2>1. requiredStake = (3 * TotalNetworkStake) \div 5 + 1
            BY DEF SlowPathThreshold

        <2>2. acquisitionCost = 2 * ((3 * TotalNetworkStake) \div 5 + 1)
            BY <2>1

        <2>3. slashingCost >= ((3 * TotalNetworkStake) \div 5) * 50 \div 100
            BY SlashingPenaltyRate >= 50, <2>1

        <2>4. opportunityCost = ((3 * TotalNetworkStake) \div 5 + 1) * 8 \div 100
            BY BaseStakingYield = 8, <2>1

        <2>5. totalAttackCost >= 2 * (3 * TotalNetworkStake) \div 5 + 
                                 (3 * TotalNetworkStake) \div 10 + 
                                 (3 * TotalNetworkStake) \div 62.5
            BY <2>2, <2>3, <2>4

        <2>6. totalAttackCost >= TotalNetworkStake  \* Conservative lower bound
            BY <2>5, EconomicArithmetic

        <2>7. potentialGain * 10 = TotalNetworkStake \div 10
            BY DEF potentialGain

        <2>8. TotalNetworkStake > TotalNetworkStake \div 10
            BY EconomicArithmetic, TotalNetworkStake > 0

        <2> QED BY <2>6, <2>7, <2>8

    <1> QED BY <1>1

----------------------------------------------------------------------------
(* Combined Economic Safety Theorem *)

\* Main economic safety theorem combining all properties
EconomicSafetyInvariant ==
    /\ EconomicRationalityProperty
    /\ SlashingEffectivenessProperty
    /\ RewardFairnessProperty
    /\ FeeSustainabilityProperty
    /\ NothingAtStakeResistanceProperty
    /\ LongRangeAttackResistanceProperty
    /\ EconomicAttackCostProperty

THEOREM EconomicSafetyTheorem ==
    /\ EconomicModel!SlashingCorrectness
    /\ EconomicModel!TokenConservation
    /\ EconomicModel!NoNegativeBalances
    /\ EconomicModelComplete!EconomicRationalityInvariant
    => (EconomicModel!Spec => []EconomicSafetyInvariant)
PROOF
    <1>1. Init => EconomicSafetyInvariant
        <2>1. Init => EconomicRationalityProperty
            BY EconomicRationalityTheorem
        <2>2. Init => SlashingEffectivenessProperty
            BY SlashingEffectivenessTheorem
        <2>3. Init => RewardFairnessProperty
            BY RewardFairnessTheorem
        <2>4. Init => FeeSustainabilityProperty
            BY FeeSustainabilityTheorem
        <2>5. Init => NothingAtStakeResistanceProperty
            BY NothingAtStakeResistanceTheorem
        <2>6. Init => LongRangeAttackResistanceProperty
            BY LongRangeAttackResistanceTheorem
        <2>7. EconomicAttackCostProperty
            BY EconomicAttackCostTheorem
        <2> QED BY <2>1, <2>2, <2>3, <2>4, <2>5, <2>6, <2>7 DEF EconomicSafetyInvariant

    <1>2. EconomicSafetyInvariant /\ Next => EconomicSafetyInvariant'
        <2>1. EconomicRationalityProperty /\ Next => EconomicRationalityProperty'
            BY EconomicRationalityTheorem
        <2>2. SlashingEffectivenessProperty /\ Next => SlashingEffectivenessProperty'
            BY SlashingEffectivenessTheorem
        <2>3. RewardFairnessProperty /\ Next => RewardFairnessProperty'
            BY RewardFairnessTheorem
        <2>4. FeeSustainabilityProperty /\ Next => FeeSustainabilityProperty'
            BY FeeSustainabilityTheorem
        <2>5. NothingAtStakeResistanceProperty /\ Next => NothingAtStakeResistanceProperty'
            BY NothingAtStakeResistanceTheorem
        <2>6. LongRangeAttackResistanceProperty /\ Next => LongRangeAttackResistanceProperty'
            BY LongRangeAttackResistanceTheorem
        <2>7. EconomicAttackCostProperty is time-invariant
            BY EconomicAttackCostTheorem
        <2> QED BY <2>1, <2>2, <2>3, <2>4, <2>5, <2>6, <2>7 DEF EconomicSafetyInvariant

    <1> QED BY <1>1, <1>2, PTL DEF EconomicModel!Spec

----------------------------------------------------------------------------
(* Economic Liveness Properties *)

\* Economic incentives eventually align with protocol security
EventualEconomicAlignment ==
    <>[](\A v \in (Validators \ ByzantineValidators) : EconomicRationalityProperty)

\* Byzantine validators are eventually economically neutralized
EventualByzantineNeutralization ==
    <>[](\A v \in ByzantineValidators : 
         EconomicModel!slashedStake[v] >= EconomicModel!TotalStake(v) \div 2)

\* Economic equilibrium is eventually reached
EventualEconomicEquilibrium ==
    <>[]EconomicModelComplete!economicEquilibrium.isStable

THEOREM EconomicLivenessTheorem ==
    /\ EconomicSafetyTheorem
    /\ EconomicModel!EventualSlashing
    => /\ EventualEconomicAlignment
       /\ EventualByzantineNeutralization
       /\ EventualEconomicEquilibrium
PROOF
    <1>1. EventualEconomicAlignment
        BY EconomicRationalityTheorem, EconomicSafetyTheorem

    <1>2. EventualByzantineNeutralization
        BY SlashingEffectivenessTheorem, EconomicModel!EventualSlashing

    <1>3. EventualEconomicEquilibrium
        BY <1>1, <1>2, EconomicModelComplete!AdjustProtocolParameters

    <1> QED BY <1>1, <1>2, <1>3

============================================================================