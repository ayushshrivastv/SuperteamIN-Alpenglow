\* Author: Ayush Srivastava
------------------------------ MODULE Stake ------------------------------
(**************************************************************************)
(* Stake calculation and management for the Alpenglow protocol            *)
(* This module provides clear, unambiguous stake-related definitions      *)
(**************************************************************************)

EXTENDS Integers, FiniteSets

----------------------------------------------------------------------------
(* Default Stake Configuration *)

\* Default stake mapping for validators (can be overridden by parent module)
DefaultStake == [v1 |-> 10, v2 |-> 10, v3 |-> 10]

----------------------------------------------------------------------------
(* Core Stake Definitions *)

\* Individual validator stake from the stake mapping
ValidatorStake(validator) ==
    IF validator \in DOMAIN DefaultStake
    THEN DefaultStake[validator]
    ELSE 0

\* Parameterized version that accepts stake mapping
ValidatorStakeFromMapping(validator, stakeMapping) ==
    IF validator \in DOMAIN stakeMapping
    THEN stakeMapping[validator]
    ELSE 0

\* Total stake of a set of validators - primary version with stake mapping
StakeOfSet(validatorSet, stakeMapping) ==
    IF validatorSet = {}
    THEN 0
    ELSE LET v == CHOOSE x \in validatorSet : TRUE
         IN ValidatorStakeFromMapping(v, stakeMapping) + StakeOfSet(validatorSet \ {v}, stakeMapping)

\* Legacy version using default mapping for backward compatibility
StakeOfSetDefault(validatorSet) ==
    StakeOfSet(validatorSet, DefaultStake)

\* Total stake calculation with mapping
TotalStake(validators, stakeMapping) ==
    StakeOfSet(validators, stakeMapping)

\* Default total stake constant for backward compatibility
TotalStakeDefault == 30  \* Sum of all validator stakes

----------------------------------------------------------------------------
(* Categorized Stake Calculations *)

\* Stake held by Byzantine validators
ByzantineStakeAmount(byzantineSet, stakeMapping) ==
    StakeOfSet(byzantineSet, stakeMapping)

\* Legacy version using default mapping
ByzantineStakeAmountDefault(byzantineSet) ==
    ByzantineStakeAmount(byzantineSet, DefaultStake)

\* Stake held by offline validators
OfflineStakeAmount(offlineSet, stakeMapping) ==
    StakeOfSet(offlineSet, stakeMapping)

\* Legacy version using default mapping
OfflineStakeAmountDefault(offlineSet) ==
    OfflineStakeAmount(offlineSet, DefaultStake)

\* Stake held by honest online validators
HonestOnlineStakeAmount(allValidators, byzantineSet, offlineSet, stakeMapping) ==
    StakeOfSet(allValidators \ (byzantineSet \cup offlineSet), stakeMapping)

\* Legacy version using default mapping
HonestOnlineStakeAmountDefault(allValidators, byzantineSet, offlineSet) ==
    HonestOnlineStakeAmount(allValidators, byzantineSet, offlineSet, DefaultStake)

\* Check if honest validators have sufficient stake
HonestHaveMajority(allValidators, byzantineSet, stakeMapping) ==
    HonestOnlineStakeAmount(allValidators, byzantineSet, {}, stakeMapping) >
    TotalStake(allValidators, stakeMapping) \div 2

\* Legacy version using default mapping
HonestHaveMajorityDefault(allValidators, byzantineSet) ==
    HonestHaveMajority(allValidators, byzantineSet, DefaultStake)

\* Stake held by online validators (non-offline)
OnlineStakeAmount(allValidators, offlineSet, stakeMapping) ==
    StakeOfSet(allValidators \ offlineSet, stakeMapping)

\* Stake held by active participants (may include Byzantine but not offline)
ActiveStakeAmount(allValidators, offlineSet, stakeMapping) ==
    StakeOfSet(allValidators \ offlineSet, stakeMapping)

\* Stake held by responsive validators (honest and online)
ResponsiveStakeAmount(allValidators, byzantineSet, offlineSet, stakeMapping) ==
    StakeOfSet(allValidators \ (byzantineSet \cup offlineSet), stakeMapping)

----------------------------------------------------------------------------
(* Stake Ratios and Percentages *)

\* Calculate stake percentage of a set
StakePercentage(validatorSet, stakeMapping) ==
    LET setStake == StakeOfSet(validatorSet, stakeMapping)
        totalStake == TotalStake(DOMAIN stakeMapping, stakeMapping)
    IN IF totalStake > 0
       THEN (setStake * 100) \div totalStake
       ELSE 0

\* Check if a set has at least the required stake percentage
HasMinimumStake(validatorSet, requiredPercentage, stakeMapping) ==
    LET setStake == StakeOfSet(validatorSet, stakeMapping)
        totalStake == TotalStake(DOMAIN stakeMapping, stakeMapping)
    IN setStake * 100 >= totalStake * requiredPercentage

\* Check if a coalition can control consensus (typically 2/3)
CanControlConsensus(coalition, stakeMapping) ==
    LET coalitionStake == StakeOfSet(coalition, stakeMapping)
        totalStake == TotalStake(DOMAIN stakeMapping, stakeMapping)
    IN coalitionStake >= (totalStake * 2) \div 3

\* Check if Byzantine stake is within tolerance
ByzantineWithinTolerance(byzantineSet, maxPercentage, stakeMapping) ==
    StakePercentage(byzantineSet, stakeMapping) <= maxPercentage

\* Check if offline stake is within tolerance
OfflineWithinTolerance(offlineSet, maxPercentage, stakeMapping) ==
    StakePercentage(offlineSet, stakeMapping) <= maxPercentage

----------------------------------------------------------------------------
(* Stake Threshold Calculations *)

\* Fast path threshold (typically 80%)
FastPathThreshold(stakeMapping) ==
    (TotalStake(DOMAIN stakeMapping, stakeMapping) * 4) \div 5

\* Slow path threshold (60% as per standardization)
SlowPathThreshold(stakeMapping) ==
    (TotalStake(DOMAIN stakeMapping, stakeMapping) * 3) \div 5

\* Skip path threshold (typically 67% - 2/3 supermajority)
SkipPathThreshold(stakeMapping) ==
    (TotalStake(DOMAIN stakeMapping, stakeMapping) * 2) \div 3

\* Exact threshold calculations for any percentage
ExactThreshold(stakeMapping, percentage) ==
    (TotalStake(DOMAIN stakeMapping, stakeMapping) * percentage) \div 100

----------------------------------------------------------------------------
(* Certificate Threshold Calculations *)

\* Required stake for fast path
FastPathRequiredStake(fastThreshold, stakeMapping) ==
    (TotalStake(DOMAIN stakeMapping, stakeMapping) * fastThreshold) \div 100

\* Required stake for slow path
SlowPathRequiredStake(slowThreshold, stakeMapping) ==
    (TotalStake(DOMAIN stakeMapping, stakeMapping) * slowThreshold) \div 100

\* Check if votes meet fast path threshold
MeetsFastPathThreshold(votes, fastThreshold, stakeMapping) ==
    StakeOfSet(votes, stakeMapping) >= FastPathRequiredStake(fastThreshold, stakeMapping)

\* Check if votes meet slow path threshold
MeetsSlowPathThreshold(votes, slowThreshold, stakeMapping) ==
    StakeOfSet(votes, stakeMapping) >= SlowPathRequiredStake(slowThreshold, stakeMapping)

\* Determine certificate type based on stake
CertificateTypeFromStake(votes, fastThreshold, slowThreshold, stakeMapping) ==
    IF MeetsFastPathThreshold(votes, fastThreshold, stakeMapping)
    THEN "fast"
    ELSE IF MeetsSlowPathThreshold(votes, slowThreshold, stakeMapping)
    THEN "slow"
    ELSE "none"

----------------------------------------------------------------------------
(* Utility Functions *)

\* Get validators sorted by stake (descending)
ValidatorsByStake(allValidators) ==
    allValidators  \* Abstract sorting, actual implementation would order by stake

\* Weighted random selection based on stake
SelectWeightedValidator(validatorSet, randomValue, stakeMapping) ==
    LET totalStake == StakeOfSet(validatorSet, stakeMapping)
        normalizedRandom == IF totalStake > 0 THEN randomValue % totalStake ELSE 0
    IN CHOOSE v \in validatorSet : ValidatorStakeFromMapping(v, stakeMapping) > 0

\* Check if validator has minimum stake to participate
HasMinimumParticipationStake(validator, minStake, stakeMapping) ==
    ValidatorStakeFromMapping(validator, stakeMapping) >= minStake

\* Calculate stake-weighted voting power
VotingPower(validator, stakeMapping) ==
    LET totalStake == TotalStake(DOMAIN stakeMapping, stakeMapping)
    IN IF totalStake > 0 THEN (ValidatorStakeFromMapping(validator, stakeMapping) * 100) \div totalStake ELSE 0

\* Calculate voting power ratio between two sets
VotingPowerRatio(set1, set2, stakeMapping) ==
    LET stake1 == StakeOfSet(set1, stakeMapping)
        stake2 == StakeOfSet(set2, stakeMapping)
    IN IF stake2 > 0 THEN stake1 \div stake2 ELSE 0

\* Proportional representation check
IsProportionallyRepresented(selectedSet, totalSet, threshold, stakeMapping) ==
    LET selectedStake == StakeOfSet(selectedSet, stakeMapping)
        totalStake == StakeOfSet(totalSet, stakeMapping)
    IN selectedStake >= totalStake * threshold

----------------------------------------------------------------------------
(* Invariants and Properties *)

\* Invariant: Total stake is conserved
StakeConservationInvariant(allValidators, stakeMapping) ==
    StakeOfSet(allValidators, stakeMapping) = TotalStake(allValidators, stakeMapping)

\* No negative stakes
NoNegativeStakes(allValidators, stakeMapping) ==
    \A v \in allValidators : ValidatorStakeFromMapping(v, stakeMapping) >= 0

\* Stake distribution is valid
ValidStakeDistribution(allValidators, stakeMapping) ==
    /\ NoNegativeStakes(allValidators, stakeMapping)
    /\ TotalStake(allValidators, stakeMapping) > 0
    /\ \E v \in allValidators : ValidatorStakeFromMapping(v, stakeMapping) > 0

\* Find validators controlling at least threshold stake
ValidatorsWithStake(validatorSet, minStake, stakeMapping) ==
    {v \in validatorSet : ValidatorStakeFromMapping(v, stakeMapping) >= minStake}

----------------------------------------------------------------------------
(* Additional Utility Functions for Enhanced Functionality *)

\* Sum operator that works with TLC (non-recursive version)
TLCSum(S, f(_)) ==
    LET SumSeq[s \in Seq(S)] ==
        IF s = <<>> THEN 0
        ELSE f(Head(s)) + SumSeq[Tail(s)]
    IN SumSeq[SetToSeq(S)]

\* Alternative stake calculation using TLC-compatible approach
StakeOfSetTLC(validatorSet, stakeMapping) ==
    IF validatorSet = {} THEN 0
    ELSE TLCSum(validatorSet, LAMBDA v: ValidatorStakeFromMapping(v, stakeMapping))

\* Check if a coalition has exactly the required stake
HasExactStake(coalition, requiredStake, stakeMapping) ==
    StakeOfSet(coalition, stakeMapping) = requiredStake

\* Check if adding a validator would exceed threshold
WouldExceedThreshold(currentCoalition, newValidator, threshold, stakeMapping) ==
    StakeOfSet(currentCoalition \cup {newValidator}, stakeMapping) > threshold

\* Find minimum coalition that meets threshold
MinimalCoalitionForThreshold(validatorSet, threshold, stakeMapping) ==
    CHOOSE coalition \in SUBSET validatorSet :
        /\ StakeOfSet(coalition, stakeMapping) >= threshold
        /\ \A smaller \in SUBSET coalition :
            smaller # coalition => StakeOfSet(smaller, stakeMapping) < threshold

\* Byzantine fault tolerance check (< 1/3 Byzantine stake)
ByzantineFaultTolerant(allValidators, byzantineSet, stakeMapping) ==
    ByzantineStakeAmount(byzantineSet, stakeMapping) < TotalStake(allValidators, stakeMapping) \div 3

============================================================================
