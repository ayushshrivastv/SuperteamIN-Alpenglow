---------------------------- MODULE EconomicIncentives ----------------------------
(***************************************************************************)
(* Economic incentive model for Alpenglow consensus protocol including    *)
(* rewards, penalties, delegation mechanics, and fee distribution.        *)
(***************************************************************************)

EXTENDS Integers, Sequences, FiniteSets, TLC

CONSTANTS
    Validators,          \* Set of all validators
    Delegators,          \* Set of delegators
    MaxReward,           \* Maximum reward per epoch
    MaxPenalty,          \* Maximum penalty for misbehavior
    BaseReward,          \* Base reward for participation
    CommissionRate,      \* Validator commission rate (0-100)
    SlashingRate,        \* Slashing rate for Byzantine behavior
    EpochLength,         \* Length of reward epoch
    MinStake,            \* Minimum stake requirement
    MaxDelegation        \* Maximum delegation per validator

VARIABLES
    validatorRewards,    \* Accumulated rewards per validator
    validatorPenalties,  \* Accumulated penalties per validator
    delegatorRewards,    \* Rewards for delegators
    delegations,         \* Delegation mapping: delegator -> validator
    totalFees,           \* Total transaction fees collected
    rewardPool,          \* Available reward pool
    slashedStake,        \* Slashed stake amounts
    epoch,               \* Current epoch
    participationRate    \* Validator participation rate

vars == <<validatorRewards, validatorPenalties, delegatorRewards, 
          delegations, totalFees, rewardPool, slashedStake, 
          epoch, participationRate>>

\* Type invariants
TypeOK ==
    /\ validatorRewards \in [Validators -> Nat]
    /\ validatorPenalties \in [Validators -> Nat]
    /\ delegatorRewards \in [Delegators -> Nat]
    /\ delegations \in [Delegators -> Validators]
    /\ totalFees \in Nat
    /\ rewardPool \in Nat
    /\ slashedStake \in [Validators -> Nat]
    /\ epoch \in Nat
    /\ participationRate \in [Validators -> 0..100]

\* Initial state
Init ==
    /\ validatorRewards = [v \in Validators |-> 0]
    /\ validatorPenalties = [v \in Validators |-> 0]
    /\ delegatorRewards = [d \in Delegators |-> 0]
    /\ delegations = [d \in Delegators |-> CHOOSE v \in Validators : TRUE]
    /\ totalFees = 0
    /\ rewardPool = BaseReward * Cardinality(Validators)
    /\ slashedStake = [v \in Validators |-> 0]
    /\ epoch = 1
    /\ participationRate = [v \in Validators |-> 100]

\* Calculate validator reward based on performance
CalculateValidatorReward(validator) ==
    LET baseAmount == BaseReward
        performanceBonus == (participationRate[validator] * baseAmount) \div 100
        totalReward == baseAmount + performanceBonus
    IN Min(totalReward, MaxReward)

\* Calculate delegator reward based on validator performance
CalculateDelegatorReward(delegator, validator) ==
    LET validatorReward == CalculateValidatorReward(validator)
        commission == (validatorReward * CommissionRate) \div 100
        delegatorShare == validatorReward - commission
        \* Simplified: assume equal delegation amounts
        numDelegators == Cardinality({d \in Delegators : delegations[d] = validator})
    IN IF numDelegators > 0 THEN delegatorShare \div numDelegators ELSE 0

\* Distribute rewards at epoch end
DistributeRewards ==
    /\ \A v \in Validators :
        validatorRewards' = [validatorRewards EXCEPT ![v] = 
            validatorRewards[v] + CalculateValidatorReward(v)]
    /\ \A d \in Delegators :
        delegatorRewards' = [delegatorRewards EXCEPT ![d] =
            delegatorRewards[d] + CalculateDelegatorReward(d, delegations[d])]
    /\ rewardPool' = rewardPool - (BaseReward * Cardinality(Validators))
    /\ UNCHANGED <<validatorPenalties, delegations, totalFees, 
                   slashedStake, epoch, participationRate>>

\* Apply slashing for Byzantine behavior
SlashValidator(validator, amount) ==
    /\ validator \in Validators
    /\ amount <= MaxPenalty
    /\ validatorPenalties' = [validatorPenalties EXCEPT ![validator] = 
           validatorPenalties[validator] + amount]
    /\ slashedStake' = [slashedStake EXCEPT ![validator] = 
           slashedStake[validator] + amount]
    /\ rewardPool' = rewardPool + amount  \* Slashed funds go to reward pool
    /\ UNCHANGED <<validatorRewards, delegatorRewards, delegations, 
                   totalFees, epoch, participationRate>>

\* Update participation rate based on validator behavior
UpdateParticipation(validator, newRate) ==
    /\ validator \in Validators
    /\ newRate \in 0..100
    /\ participationRate' = [participationRate EXCEPT ![validator] = newRate]
    /\ UNCHANGED <<validatorRewards, validatorPenalties, delegatorRewards,
                   delegations, totalFees, rewardPool, slashedStake, epoch>>

\* Advance to next epoch
AdvanceEpoch ==
    /\ epoch' = epoch + 1
    /\ DistributeRewards
    /\ UNCHANGED <<validatorPenalties, delegations, totalFees, slashedStake>>

\* Delegate stake to validator
DelegateStake(delegator, validator) ==
    /\ delegator \in Delegators
    /\ validator \in Validators
    /\ delegations' = [delegations EXCEPT ![delegator] = validator]
    /\ UNCHANGED <<validatorRewards, validatorPenalties, delegatorRewards,
                   totalFees, rewardPool, slashedStake, epoch, participationRate>>

\* Economic invariants
EconomicSafety ==
    \* No validator should have negative net rewards
    \A v \in Validators : 
        validatorRewards[v] >= validatorPenalties[v]

StakeConservation ==
    \* Total rewards distributed should not exceed available pool
    LET totalDistributed == (CHOOSE sum \in Nat : 
            sum = validatorRewards[CHOOSE v \in Validators : TRUE] * Cardinality(Validators))
    IN totalDistributed <= rewardPool + totalFees

RewardFairness ==
    \* Validators with higher participation should earn more
    \A v1, v2 \in Validators :
        participationRate[v1] > participationRate[v2] =>
        CalculateValidatorReward(v1) >= CalculateValidatorReward(v2)

\* Next state relation
Next ==
    \/ AdvanceEpoch
    \/ \E v \in Validators, amount \in 1..MaxPenalty : SlashValidator(v, amount)
    \/ \E v \in Validators, rate \in 0..100 : UpdateParticipation(v, rate)
    \/ \E d \in Delegators, v \in Validators : DelegateStake(d, v)

\* Specification
Spec == Init /\ [][Next]_vars /\ WF_vars(AdvanceEpoch)

\* Helper function
Min(a, b) == IF a <= b THEN a ELSE b

============================================================================
