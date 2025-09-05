------------------------------ MODULE EconomicModel ------------------------------
(**************************************************************************)
(* Economic Model for Alpenglow Protocol                                  *)
(* Includes reward distribution, slashing conditions, and fee handling    *)
(* Integrates with stake-based voting mechanisms from Votor.tla          *)
(**************************************************************************)

EXTENDS Integers, Sequences, FiniteSets, TLC

CONSTANTS
    Validators,              \* Set of all validators
    ByzantineValidators,     \* Set of Byzantine validators
    Stake,                   \* Initial stake distribution from Votor
    MaxEpoch,                \* Maximum epoch number
    MaxSlot,                 \* Maximum slot number
    BaseReward,              \* Base reward per slot
    SlashingRate,            \* Percentage of stake slashed for violations
    CommissionRate,          \* Commission rate for delegated stake
    MinStake,                \* Minimum stake required to be validator
    MaxInflation,            \* Maximum annual inflation rate
    EpochLength,             \* Number of slots per epoch
    TreasuryAddress          \* Address for protocol treasury

VARIABLES
    validatorBalances,       \* Current stake balances for validators
    delegatorBalances,       \* Balances for delegators
    rewardPool,              \* Available rewards for distribution
    slashedAmounts,          \* Total amounts slashed per validator
    commissionEarned,        \* Commission earned by validators
    treasuryBalance,         \* Protocol treasury balance
    feeCollected,            \* Transaction fees collected
    epochRewards,            \* Rewards distributed per epoch
    validatorPerformance,    \* Performance metrics per validator
    slashingEvents,          \* Record of slashing events
    currentEpoch,            \* Current epoch number
    totalSupply,             \* Total token supply
    inflationRate,           \* Current inflation rate
    validatorRewards,        \* Individual validator reward tracking
    slashedStake,            \* Slashed stake tracking per validator
    feePool                  \* Transaction fee pool for distribution

economicVars == <<validatorBalances, delegatorBalances, rewardPool, slashedAmounts,
                  commissionEarned, treasuryBalance, feeCollected, epochRewards,
                  validatorPerformance, slashingEvents, currentEpoch, totalSupply,
                  inflationRate, validatorRewards, slashedStake, feePool>>

----------------------------------------------------------------------------
(* Type Invariants *)

TypeInvariant ==
    /\ validatorBalances \in [Validators -> Nat]
    /\ delegatorBalances \in [Validators -> [Validators -> Nat]]  \* delegator -> validator -> amount
    /\ rewardPool \in Nat
    /\ slashedAmounts \in [Validators -> Nat]
    /\ commissionEarned \in [Validators -> Nat]
    /\ treasuryBalance \in Nat
    /\ feeCollected \in Nat
    /\ epochRewards \in [1..MaxEpoch -> Nat]
    /\ validatorPerformance \in [Validators -> [epoch: 1..MaxEpoch,
                                               slotsProposed: Nat,
                                               slotsVoted: Nat,
                                               fastCerts: Nat,
                                               slowCerts: Nat,
                                               skipCerts: Nat,
                                               uptime: Nat]]
    /\ slashingEvents \in [1..MaxEpoch -> SUBSET [validator: Validators,
                                                  reason: {"double_vote", "invalid_cert", "offline", "withhold_shreds"},
                                                  amount: Nat,
                                                  slot: 1..MaxSlot]]
    /\ currentEpoch \in 1..MaxEpoch
    /\ totalSupply \in Nat
    /\ inflationRate \in 0..MaxInflation
    /\ validatorRewards \in [Validators -> [1..MaxEpoch -> Nat]]
    /\ slashedStake \in [Validators -> Nat]
    /\ feePool \in Nat

----------------------------------------------------------------------------
(* Helper Functions *)

\* Calculate total stake for a validator (own + delegated)
TotalStake(v) ==
    validatorBalances[v] +
    LET delegatedToV == {d \in Validators : delegatorBalances[d][v] > 0}
    IN IF delegatedToV = {} THEN 0
       ELSE LET sumFunc == [d \in delegatedToV |-> delegatorBalances[d][v]]
            IN CHOOSE sum \in Nat :
               sum = (CHOOSE s \in Nat :
                     s = IF delegatedToV = {} THEN 0
                         ELSE LET seq == SetToSeq(delegatedToV)
                              IN FoldSeq(LAMBDA x, y: x + delegatorBalances[y][v], 0, seq))

\* Helper to convert set to sequence for folding
SetToSeq(S) ==
    CHOOSE seq \in Seq(S) :
        /\ Len(seq) = Cardinality(S)
        /\ \A i \in 1..Len(seq) : seq[i] \in S
        /\ \A x \in S : \E i \in 1..Len(seq) : seq[i] = x

\* Fold function for sequences
FoldSeq(op(_, _), base, seq) ==
    IF Len(seq) = 0 THEN base
    ELSE op(seq[1], FoldSeq(op, base, SubSeq(seq, 2, Len(seq))))

\* Calculate network total stake
NetworkTotalStake ==
    LET validatorStakes == [v \in Validators |-> TotalStake(v)]
    IN FoldSeq(LAMBDA x, y: x + y, 0, SetToSeq({validatorStakes[v] : v \in Validators}))

\* Check if validator meets minimum stake requirement
MeetsMinStake(v) ==
    TotalStake(v) >= MinStake

\* Calculate validator's voting power percentage
VotingPower(v) ==
    IF NetworkTotalStake = 0 THEN 0
    ELSE (TotalStake(v) * 100) \div NetworkTotalStake

\* Calculate epoch reward based on inflation
CalculateEpochReward(epoch) ==
    (totalSupply * inflationRate * EpochLength) \div (365 * 24 * 60 * 60 \div 400)  \* Assuming 400ms slots

\* Calculate validator performance score (0-100)
PerformanceScore(v, epoch) ==
    LET perf == validatorPerformance[v]
        expectedSlots == EpochLength \div Cardinality(Validators)  \* Expected slots per validator
        proposalScore == IF expectedSlots = 0 THEN 100
                        ELSE Min(100, (perf.slotsProposed * 100) \div expectedSlots)
        votingScore == IF EpochLength = 0 THEN 100
                      ELSE Min(100, (perf.slotsVoted * 100) \div EpochLength)
        certScore == IF perf.fastCerts + perf.slowCerts + perf.skipCerts = 0 THEN 0
                    ELSE (perf.fastCerts * 100) \div (perf.fastCerts + perf.slowCerts + perf.skipCerts)
        uptimeScore == perf.uptime
    IN (proposalScore + votingScore + certScore + uptimeScore) \div 4

\* Min function
Min(a, b) == IF a <= b THEN a ELSE b

\* Max function
Max(a, b) == IF a >= b THEN a ELSE b

----------------------------------------------------------------------------
(* Slashing Conditions *)

\* Double voting violation
DoubleVoteViolation(v, slot) ==
    /\ v \in ByzantineValidators
    /\ \* This would be detected by cross-referencing with Votor vote records
    TRUE  \* Simplified - in practice would check vote history

\* Invalid certificate creation
InvalidCertViolation(v, slot) ==
    /\ v \in ByzantineValidators
    /\ \* This would be detected by certificate validation failures
    TRUE  \* Simplified - in practice would check certificate validity

\* Offline/liveness violation
OfflineViolation(v, epoch) ==
    LET perf == validatorPerformance[v]
        expectedUptime == 95  \* 95% uptime requirement
    IN perf.uptime < expectedUptime

\* Withholding shreds violation (Rotor-related)
WithholdShredsViolation(v, slot) ==
    /\ v \in ByzantineValidators
    /\ \* This would be detected by monitoring shred distribution patterns
    TRUE  \* Simplified - in practice would check shred propagation metrics

\* Calculate slashing amount based on violation type
SlashingAmount(v, reason) ==
    LET stake == TotalStake(v)
    IN CASE reason = "double_vote" -> (stake * SlashingRate) \div 100
         [] reason = "invalid_cert" -> (stake * SlashingRate) \div 100
         [] reason = "offline" -> (stake * (SlashingRate \div 2)) \div 100
         [] reason = "withhold_shreds" -> (stake * (SlashingRate \div 4)) \div 100
         [] OTHER -> 0

----------------------------------------------------------------------------
(* Required Functions from Specification *)

\* Stake-proportional reward distribution function
DistributeRewards(validators, stakeMap) ==
    LET totalStake == FoldSeq(LAMBDA x, y: x + y, 0,
                             SetToSeq({stakeMap[v] : v \in validators}))
        epochReward == CalculateEpochReward(currentEpoch)
    IN [v \in validators |->
        IF totalStake = 0 THEN 0
        ELSE (epochReward * stakeMap[v]) \div totalStake]

\* Slashing function with specific signature
SlashValidator(validator, amount, reason) ==
    /\ validator \in Validators
    /\ amount > 0
    /\ reason \in {"double_vote", "invalid_cert", "offline", "withhold_shreds"}
    /\ CASE reason = "double_vote" -> DoubleVoteViolation(validator, 0)
         [] reason = "invalid_cert" -> InvalidCertViolation(validator, 0)
         [] reason = "offline" -> OfflineViolation(validator, currentEpoch)
         [] reason = "withhold_shreds" -> WithholdShredsViolation(validator, 0)
         [] OTHER -> FALSE
    /\ LET actualAmount == Min(amount, validatorBalances[validator])
       IN /\ validatorBalances' = [validatorBalances EXCEPT
                                   ![validator] = validatorBalances[validator] - actualAmount]
          /\ slashedStake' = [slashedStake EXCEPT ![validator] = slashedStake[validator] + actualAmount]
          /\ treasuryBalance' = treasuryBalance + actualAmount
          /\ slashingEvents' = [slashingEvents EXCEPT
                                ![currentEpoch] = slashingEvents[currentEpoch] \cup
                                {[validator |-> validator, reason |-> reason, amount |-> actualAmount, slot |-> 0]}]
          /\ totalSupply' = totalSupply - actualAmount
    /\ UNCHANGED <<delegatorBalances, rewardPool, commissionEarned, feeCollected,
                  epochRewards, validatorPerformance, currentEpoch, inflationRate, validatorRewards, feePool>>

\* Transaction fee collection function
CollectFees(transactions) ==
    LET totalFees == FoldSeq(LAMBDA x, y: x + y, 0,
                            SetToSeq({100 : t \in transactions}))  \* Simplified: 100 units per transaction
    IN /\ feePool' = feePool + totalFees
       /\ treasuryBalance' = treasuryBalance + (totalFees \div 2)  \* 50% to treasury
       /\ rewardPool' = rewardPool + (totalFees \div 2)  \* 50% to reward pool
       /\ feeCollected' = feeCollected + totalFees
       /\ UNCHANGED <<validatorBalances, delegatorBalances, slashedAmounts, commissionEarned,
                     epochRewards, validatorPerformance, slashingEvents, currentEpoch,
                     totalSupply, inflationRate, validatorRewards, slashedStake>>

----------------------------------------------------------------------------
(* Reward Distribution *)

\* Calculate validator reward based on performance and stake
ValidatorReward(v, epochReward) ==
    LET stake == TotalStake(v)
        networkStake == NetworkTotalStake
        stakeRatio == IF networkStake = 0 THEN 0 ELSE (stake * 100) \div networkStake
        perfScore == PerformanceScore(v, currentEpoch)
        baseReward == (epochReward * stakeRatio) \div 100
        performanceBonus == (baseReward * perfScore) \div 100
    IN (baseReward + performanceBonus) \div 2

\* Calculate commission for validator from delegated stake
CommissionReward(v, totalReward) ==
    LET delegatedStake == TotalStake(v) - validatorBalances[v]
        delegatedReward == IF TotalStake(v) = 0 THEN 0
                          ELSE (totalReward * delegatedStake) \div TotalStake(v)
    IN (delegatedReward * CommissionRate) \div 100

\* Calculate delegator reward
DelegatorReward(delegator, validator, totalReward) ==
    LET delegatedAmount == delegatorBalances[delegator][validator]
        totalDelegated == TotalStake(validator) - validatorBalances[validator]
        delegatedReward == IF TotalStake(validator) = 0 THEN 0
                          ELSE (totalReward * totalDelegated) \div TotalStake(validator)
        commission == CommissionReward(validator, totalReward)
        netDelegatedReward == delegatedReward - commission
    IN IF totalDelegated = 0 THEN 0
       ELSE (netDelegatedReward * delegatedAmount) \div totalDelegated

----------------------------------------------------------------------------
(* Initialization *)

Init ==
    /\ validatorBalances = Stake  \* Initialize with Votor stake distribution
    /\ delegatorBalances = [d \in Validators |-> [v \in Validators |-> 0]]
    /\ rewardPool = BaseReward * EpochLength
    /\ slashedAmounts = [v \in Validators |-> 0]
    /\ commissionEarned = [v \in Validators |-> 0]
    /\ treasuryBalance = 0
    /\ feeCollected = 0
    /\ epochRewards = [e \in 1..MaxEpoch |-> 0]
    /\ validatorPerformance = [v \in Validators |->
                               [epoch |-> 1, slotsProposed |-> 0, slotsVoted |-> 0,
                                fastCerts |-> 0, slowCerts |-> 0, skipCerts |-> 0,
                                uptime |-> 100]]
    /\ slashingEvents = [e \in 1..MaxEpoch |-> {}]
    /\ currentEpoch = 1
    /\ totalSupply = FoldSeq(LAMBDA x, y: x + y, 0,
                            SetToSeq({validatorBalances[v] : v \in Validators}))
    /\ inflationRate = MaxInflation \div 2  \* Start at 50% of max inflation
    /\ validatorRewards = [v \in Validators |-> [e \in 1..MaxEpoch |-> 0]]
    /\ slashedStake = [v \in Validators |-> 0]
    /\ feePool = 0

----------------------------------------------------------------------------
(* State Transitions *)

\* Distribute rewards at epoch end (updated to use new variables)
DistributeEpochRewards(epoch) ==
    /\ epoch = currentEpoch
    /\ LET epochReward == CalculateEpochReward(epoch)
           stakeMap == [v \in Validators |-> TotalStake(v)]
           rewards == DistributeRewards(Validators, stakeMap)
       IN /\ epochRewards' = [epochRewards EXCEPT ![epoch] = epochReward]
          /\ rewardPool' = rewardPool + epochReward
          /\ validatorRewards' = [v \in Validators |->
                                  [validatorRewards[v] EXCEPT ![epoch] = rewards[v]]]
          /\ validatorBalances' = [v \in Validators |->
                                   validatorBalances[v] + rewards[v]]
          /\ commissionEarned' = [v \in Validators |->
                                  commissionEarned[v] + CommissionReward(v, rewards[v])]
          /\ totalSupply' = totalSupply + epochReward
    /\ UNCHANGED <<delegatorBalances, slashedAmounts, treasuryBalance, feeCollected,
                  validatorPerformance, slashingEvents, currentEpoch, inflationRate, slashedStake, feePool>>

\* Slash validator for violations (updated to use new variables)
SlashValidatorAction(v, reason, slot) ==
    /\ CASE reason = "double_vote" -> DoubleVoteViolation(v, slot)
         [] reason = "invalid_cert" -> InvalidCertViolation(v, slot)
         [] reason = "offline" -> OfflineViolation(v, currentEpoch)
         [] reason = "withhold_shreds" -> WithholdShredsViolation(v, slot)
         [] OTHER -> FALSE
    /\ LET slashAmount == SlashingAmount(v, reason)
       IN /\ validatorBalances' = [validatorBalances EXCEPT
                                   ![v] = Max(0, validatorBalances[v] - slashAmount)]
          /\ slashedAmounts' = [slashedAmounts EXCEPT ![v] = slashedAmounts[v] + slashAmount]
          /\ slashedStake' = [slashedStake EXCEPT ![v] = slashedStake[v] + slashAmount]
          /\ treasuryBalance' = treasuryBalance + slashAmount  \* Slashed funds go to treasury
          /\ slashingEvents' = [slashingEvents EXCEPT
                                ![currentEpoch] = slashingEvents[currentEpoch] \cup
                                {[validator |-> v, reason |-> reason, amount |-> slashAmount, slot |-> slot]}]
          /\ totalSupply' = totalSupply - slashAmount  \* Remove slashed tokens from supply
    /\ UNCHANGED <<delegatorBalances, rewardPool, commissionEarned, feeCollected,
                  epochRewards, validatorPerformance, currentEpoch, inflationRate, validatorRewards, feePool>>

\* Collect transaction fees (updated action)
CollectTransactionFees(transactions) ==
    /\ Cardinality(transactions) > 0
    /\ CollectFees(transactions)

\* Update validator performance metrics
UpdatePerformance(v, slotsProposed, slotsVoted, fastCerts, slowCerts, skipCerts, uptime) ==
    /\ validatorPerformance' = [validatorPerformance EXCEPT
                                ![v] = [epoch |-> currentEpoch,
                                       slotsProposed |-> slotsProposed,
                                       slotsVoted |-> slotsVoted,
                                       fastCerts |-> fastCerts,
                                       slowCerts |-> slowCerts,
                                       skipCerts |-> skipCerts,
                                       uptime |-> uptime]]
    /\ UNCHANGED <<validatorBalances, delegatorBalances, rewardPool, slashedAmounts,
                  commissionEarned, treasuryBalance, feeCollected, epochRewards,
                  slashingEvents, currentEpoch, totalSupply, inflationRate, validatorRewards, slashedStake, feePool>>

\* Advance to next epoch
AdvanceEpoch ==
    /\ currentEpoch < MaxEpoch
    /\ currentEpoch' = currentEpoch + 1
    /\ \* Reset performance metrics for new epoch
       validatorPerformance' = [v \in Validators |->
                                [epoch |-> currentEpoch + 1, slotsProposed |-> 0, slotsVoted |-> 0,
                                 fastCerts |-> 0, slowCerts |-> 0, skipCerts |-> 0, uptime |-> 100]]
    /\ \* Adjust inflation rate based on network conditions
       inflationRate' = Max(0, Min(MaxInflation,
                                   IF NetworkTotalStake > (totalSupply * 2 \div 3)
                                   THEN inflationRate - 1
                                   ELSE inflationRate + 1))
    /\ UNCHANGED <<validatorBalances, delegatorBalances, rewardPool, slashedAmounts,
                  commissionEarned, treasuryBalance, feeCollected, epochRewards,
                  slashingEvents, totalSupply, validatorRewards, slashedStake, feePool>>

\* Delegate stake to validator
DelegateStake(delegator, validator, amount) ==
    /\ delegator \in Validators
    /\ validator \in Validators
    /\ validatorBalances[delegator] >= amount
    /\ amount > 0
    /\ MeetsMinStake(validator)  \* Can only delegate to qualified validators
    /\ validatorBalances' = [validatorBalances EXCEPT ![delegator] = validatorBalances[delegator] - amount]
    /\ delegatorBalances' = [delegatorBalances EXCEPT
                             ![delegator][validator] = delegatorBalances[delegator][validator] + amount]
    /\ UNCHANGED <<rewardPool, slashedAmounts, commissionEarned, treasuryBalance, feeCollected,
                  epochRewards, validatorPerformance, slashingEvents, currentEpoch, totalSupply, inflationRate, validatorRewards, slashedStake, feePool>>

\* Undelegate stake from validator
UndelegateStake(delegator, validator, amount) ==
    /\ delegator \in Validators
    /\ validator \in Validators
    /\ delegatorBalances[delegator][validator] >= amount
    /\ amount > 0
    /\ delegatorBalances' = [delegatorBalances EXCEPT
                             ![delegator][validator] = delegatorBalances[delegator][validator] - amount]
    /\ validatorBalances' = [validatorBalances EXCEPT ![delegator] = validatorBalances[delegator] + amount]
    /\ UNCHANGED <<rewardPool, slashedAmounts, commissionEarned, treasuryBalance, feeCollected,
                  epochRewards, validatorPerformance, slashingEvents, currentEpoch, totalSupply, inflationRate, validatorRewards, slashedStake, feePool>>

----------------------------------------------------------------------------
(* Next State Relation *)

Next ==
    \/ \E epoch \in 1..MaxEpoch : DistributeEpochRewards(epoch)
    \/ \E v \in Validators, reason \in {"double_vote", "invalid_cert", "offline", "withhold_shreds"}, slot \in 1..MaxSlot :
        SlashValidatorAction(v, reason, slot)
    \/ \E v \in Validators, amount \in 1..1000, reason \in {"double_vote", "invalid_cert", "offline", "withhold_shreds"} :
        SlashValidator(v, amount, reason)
    \/ \E transactions \in SUBSET (1..100) : CollectTransactionFees(transactions)
    \/ \E v \in Validators, sp, sv, fc, sc, skc, up \in Nat :
        UpdatePerformance(v, sp, sv, fc, sc, skc, up)
    \/ AdvanceEpoch
    \/ \E delegator, validator \in Validators, amount \in 1..1000 :
        DelegateStake(delegator, validator, amount)
    \/ \E delegator, validator \in Validators, amount \in 1..1000 :
        UndelegateStake(delegator, validator, amount)

----------------------------------------------------------------------------
(* Invariants and Properties *)

\* Economic safety: No negative balances
NoNegativeBalances ==
    /\ \A v \in Validators : validatorBalances[v] >= 0
    /\ \A d, v \in Validators : delegatorBalances[d][v] >= 0
    /\ rewardPool >= 0
    /\ treasuryBalance >= 0
    /\ feePool >= 0
    /\ \A v \in Validators : slashedStake[v] >= 0

\* Total stake conservation (including new variables)
TotalStakeConservation ==
    LET totalValidatorBalance == FoldSeq(LAMBDA x, y: x + y, 0,
                                        SetToSeq({validatorBalances[v] : v \in Validators}))
        totalDelegatedBalance == FoldSeq(LAMBDA x, y: x + y, 0,
                                        SetToSeq({delegatorBalances[d][v] : d, v \in Validators}))
        totalSlashed == FoldSeq(LAMBDA x, y: x + y, 0,
                               SetToSeq({slashedStake[v] : v \in Validators}))
    IN totalValidatorBalance + totalDelegatedBalance + rewardPool + treasuryBalance + feePool + totalSlashed = totalSupply

\* Conservation of tokens (excluding inflation and slashing) - legacy invariant
TokenConservation ==
    LET totalValidatorBalance == FoldSeq(LAMBDA x, y: x + y, 0,
                                        SetToSeq({validatorBalances[v] : v \in Validators}))
        totalDelegatedBalance == FoldSeq(LAMBDA x, y: x + y, 0,
                                        SetToSeq({delegatorBalances[d][v] : d, v \in Validators}))
        totalSlashed == FoldSeq(LAMBDA x, y: x + y, 0,
                               SetToSeq({slashedAmounts[v] : v \in Validators}))
    IN totalValidatorBalance + totalDelegatedBalance + rewardPool + treasuryBalance + totalSlashed = totalSupply

\* Minimum stake requirement maintained
MinStakeInvariant ==
    \A v \in Validators :
        (validatorBalances[v] > 0 \/ \E d \in Validators : delegatorBalances[d][v] > 0) =>
        TotalStake(v) >= MinStake

\* Slashing bounds: ensure slashing amounts are within reasonable limits
SlashingBounds ==
    \A v \in Validators :
        slashedStake[v] <= TotalStake(v)

\* Slashing only affects Byzantine validators for double vote and invalid cert
SlashingCorrectness ==
    \A epoch \in 1..MaxEpoch :
        \A event \in slashingEvents[epoch] :
            event.reason \in {"double_vote", "invalid_cert", "withhold_shreds"} => event.validator \in ByzantineValidators

\* Rewards are distributed proportionally to stake and performance
RewardProportionality ==
    \A v1, v2 \in Validators :
        (TotalStake(v1) > TotalStake(v2) /\ PerformanceScore(v1, currentEpoch) >= PerformanceScore(v2, currentEpoch)) =>
        ValidatorReward(v1, CalculateEpochReward(currentEpoch)) >= ValidatorReward(v2, CalculateEpochReward(currentEpoch))

\* Commission rates are within bounds
CommissionBounds ==
    \A v \in Validators : CommissionRate >= 0 /\ CommissionRate <= 100

\* Inflation rate stays within bounds
InflationBounds ==
    inflationRate >= 0 /\ inflationRate <= MaxInflation

\* Liveness: Eventually rewards are distributed
EventualRewardDistribution ==
    <>[](currentEpoch > 1 => \E epoch \in 1..(currentEpoch-1) : epochRewards[epoch] > 0)

\* Liveness: Byzantine validators are eventually slashed
EventualSlashing ==
    <>[]\A v \in ByzantineValidators : slashedAmounts[v] > 0

\* Performance tracking accuracy
PerformanceTracking ==
    \A v \in Validators :
        LET perf == validatorPerformance[v]
        IN /\ perf.slotsProposed <= EpochLength
           /\ perf.slotsVoted <= EpochLength
           /\ perf.uptime <= 100
           /\ perf.fastCerts + perf.slowCerts + perf.skipCerts <= EpochLength

============================================================================
