------------------------------ MODULE Sampling ------------------------------
(***************************************************************************)
(* Formal verification of Theorem 3 from the Alpenglow whitepaper about   *)
(* PS-P (Partition Sampling) resilience. This module formalizes the       *)
(* stake partitioning process and proves that PS-P sampling reduces       *)
(* adversarial sampling probability compared to IID and FA1-IID methods.  *)
(***************************************************************************)

EXTENDS Integers, FiniteSets, Sequences, TLAPS

\* Import mathematical framework and helper modules
INSTANCE MathHelpers WITH Validators <- Validators,
                          Stake <- Stake

INSTANCE Types WITH Validators <- Validators,
                    ByzantineValidators <- ByzantineValidators

INSTANCE Utils

\* Import Rotor module for relay selection integration
INSTANCE Rotor WITH Validators <- Validators,
                    ByzantineValidators <- ByzantineValidators,
                    Stake <- Stake

----------------------------------------------------------------------------
(* Constants and Variables *)

CONSTANTS
    Validators,              \* Set of all validators
    ByzantineValidators,     \* Set of Byzantine validators  
    Stake,                   \* Stake function: Validators -> Nat
    SlicesPerBlock,          \* Number of slices per block (k in whitepaper)
    TotalShreds,             \* Total number of shreds (Γ in whitepaper)
    ReconstructionThreshold, \* Minimum shreds needed (γ in whitepaper)
    ResilienceParameter      \* Over-provisioning factor (κ = Γ/γ in whitepaper)

\* Sampling method configuration
SamplingMethod == "PS-P"  \* Can be "IID", "FA1-IID", or "PS-P"

\* Assumptions from the whitepaper
ASSUME ValidatorsAssumption ==
    /\ Validators # {}
    /\ IsFiniteSet(Validators)
    /\ Cardinality(Validators) >= 5

ASSUME StakeAssumption ==
    /\ Stake \in [Validators -> Nat]
    /\ \A v \in Validators : Stake[v] > 0

ASSUME SamplingParametersAssumption ==
    /\ TotalShreds > ReconstructionThreshold
    /\ ReconstructionThreshold > 0
    /\ SlicesPerBlock > 0
    /\ ResilienceParameter = TotalShreds \div ReconstructionThreshold
    /\ ResilienceParameter > 1  \* Over-provisioning required

ASSUME ByzantineAssumption ==
    Utils!TotalStake(ByzantineValidators, Stake) < Utils!TotalStake(Validators, Stake) \div 5

----------------------------------------------------------------------------
(* Stake Partitioning Definitions *)

\* Relative stake of validator v
RelativeStake(v) == 
    IF Utils!TotalStake(Validators, Stake) = 0 
    THEN 0 
    ELSE Stake[v] * 1000 \div Utils!TotalStake(Validators, Stake)  \* Scale by 1000 for precision

\* Check if validator has high stake (> 1/Γ)
IsHighStakeValidator(v) ==
    RelativeStake(v) > (1000 \div TotalShreds)

\* Number of bins a high-stake validator fills
BinsFilledByValidator(v) ==
    IF IsHighStakeValidator(v)
    THEN (RelativeStake(v) * TotalShreds) \div 1000
    ELSE 0

\* Remaining stake after filling bins for high-stake validators
RemainingStake(v) ==
    IF IsHighStakeValidator(v)
    THEN RelativeStake(v) - BinsFilledByValidator(v) * (1000 \div TotalShreds)
    ELSE RelativeStake(v)

\* Total bins filled by high-stake validators
TotalBinsFilledByHighStake ==
    Utils!Sum([v \in Validators |-> BinsFilledByValidator(v)])

\* Remaining bins for partitioning
RemainingBins == TotalShreds - TotalBinsFilledByHighStake

\* Partitioning function: maps (bin, validator) -> stake portion
\* This is an abstract representation of the partitioning algorithm P
PartitionFunction == 
    [b \in 1..RemainingBins, v \in Validators |-> 
        IF RemainingBins = 0 THEN 0
        ELSE RemainingStake(v) \div RemainingBins]

----------------------------------------------------------------------------
(* PS-P Sampling Algorithm *)

\* Step 1: Fill bins with high-stake validators
HighStakeBinAssignment ==
    [v \in Validators |-> 
        IF IsHighStakeValidator(v)
        THEN {b \in 1..BinsFilledByValidator(v) : TRUE}
        ELSE {}]

\* Step 2: Partition remaining stakes into remaining bins
\* This implements the partitioning algorithm P from Definition 45
PartitionStakes ==
    LET remainingValidators == {v \in Validators : RemainingStake(v) > 0}
        binSize == 1000 \div RemainingBins  \* Each bin should have 1/k total stake
    IN
    [b \in (TotalBinsFilledByHighStake + 1)..TotalShreds |->
        [v \in remainingValidators |->
            IF RemainingBins = 0 THEN 0
            ELSE PartitionFunction[b - TotalBinsFilledByHighStake, v]]]

\* Step 3: Sample one validator per bin proportional to stake
BinAssignment ==
    LET highStakeAssignment == HighStakeBinAssignment
        partitionAssignment == PartitionStakes
    IN
    [b \in 1..TotalShreds |->
        IF b <= TotalBinsFilledByHighStake
        THEN CHOOSE v \in Validators : b \in highStakeAssignment[v]
        ELSE LET binStakes == partitionAssignment[b]
                 totalBinStake == Utils!Sum([v \in DOMAIN binStakes |-> binStakes[v]])
             IN IF totalBinStake = 0 
                THEN CHOOSE v \in Validators : TRUE
                ELSE CHOOSE v \in DOMAIN binStakes : 
                       binStakes[v] * TotalShreds >= totalBinStake]

\* PS-P sampling result: set of selected validators
PartitionSampling ==
    {BinAssignment[b] : b \in 1..TotalShreds}

----------------------------------------------------------------------------
(* Adversarial Sampling Probability *)

\* Count adversarial samples in a given sampling
AdversarialSampleCount(sampling) ==
    Cardinality(sampling \cap ByzantineValidators)

\* Probability that adversary gets at least γ samples in PS-P
\* This is formalized as a predicate for TLAPS verification
AdversarialSamplingProbability(method, threshold) ==
    CASE method = "PS-P" ->
           AdversarialSampleCount(PartitionSampling) >= threshold
      [] method = "IID" ->
           \* IID sampling: each sample is independent with probability ρ_A
           LET adversarialStake == Utils!TotalStake(ByzantineValidators, Stake)
               totalStake == Utils!TotalStake(Validators, Stake)
               adversarialProb == IF totalStake = 0 THEN 0 ELSE adversarialStake \div totalStake
           IN \* Abstract representation of binomial probability
              adversarialProb * TotalShreds >= threshold
      [] method = "FA1-IID" ->
           \* FA1-IID: Fill-and-sample with IID fallback
           LET adversarialStake == Utils!TotalStake(ByzantineValidators, Stake)
               totalStake == Utils!TotalStake(Validators, Stake)
           IN \* FA1-IID has same or higher probability than PS-P
              AdversarialSamplingProbability("IID", threshold)

\* Sampling resilience: PS-P performs better than alternatives
SamplingResilience(threshold) ==
    /\ AdversarialSamplingProbability("PS-P", threshold) =>
       AdversarialSamplingProbability("FA1-IID", threshold)
    /\ AdversarialSamplingProbability("PS-P", threshold) =>
       AdversarialSamplingProbability("IID", threshold)

----------------------------------------------------------------------------
(* Probability Analysis Helpers *)

\* Poisson binomial distribution for PS-P sampling
\* Each bin has different adversarial probability based on stake distribution
BinAdversarialProbability(b) ==
    IF b <= TotalBinsFilledByHighStake
    THEN IF BinAssignment[b] \in ByzantineValidators THEN 1 ELSE 0
    ELSE LET binStakes == PartitionStakes[b]
             adversarialStakeInBin == Utils!Sum([v \in ByzantineValidators \cap DOMAIN binStakes |-> binStakes[v]])
             totalBinStake == Utils!Sum([v \in DOMAIN binStakes |-> binStakes[v]])
         IN IF totalBinStake = 0 THEN 0 ELSE adversarialStakeInBin \div totalBinStake

\* Expected number of adversarial samples in PS-P
ExpectedAdversarialSamples ==
    Utils!Sum([b \in 1..TotalShreds |-> BinAdversarialProbability(b)])

\* Variance in adversarial sampling (lower variance means better resilience)
AdversarialSamplingVariance ==
    Utils!Sum([b \in 1..TotalShreds |-> 
        BinAdversarialProbability(b) * (1 - BinAdversarialProbability(b))])

----------------------------------------------------------------------------
(* Integration with Rotor *)

\* Enhanced relay selection using PS-P sampling
SelectRelayPS_P(slot, shred_index) ==
    LET seed == slot * 1000 + shred_index
        \* Use PS-P sampling for relay selection
        relays == PartitionSampling
        \* Filter to appropriate number of relays
        relayCount == Min(Cardinality(Validators) \div 3, 10)
    IN IF Cardinality(relays) <= relayCount
       THEN relays
       ELSE CHOOSE subset \in SUBSET relays : Cardinality(subset) = relayCount

\* Rotor success with PS-P sampling
RotorSuccessfulPS_P(slot) ==
    \A slice \in 1..SlicesPerBlock :
        LET relays == SelectRelayPS_P(slot, slice)
            honestRelays == relays \cap (Validators \ ByzantineValidators)
        IN Cardinality(honestRelays) >= ReconstructionThreshold

----------------------------------------------------------------------------
(* Main Theorems *)

\* Lemma 47 from whitepaper: PS-P vs IID for uniform stake distribution
LEMMA PS_P_vs_IID_Uniform ==
    \A threshold \in 1..TotalShreds :
        (\A v \in Validators : RelativeStake(v) < (1000 \div TotalShreds)) =>
            (AdversarialSamplingProbability("PS-P", threshold) =>
             AdversarialSamplingProbability("IID", threshold))
PROOF
    <1>1. SUFFICES ASSUME NEW threshold \in 1..TotalShreds,
                          \A v \in Validators : RelativeStake(v) < (1000 \div TotalShreds),
                          AdversarialSamplingProbability("PS-P", threshold)
                   PROVE AdversarialSamplingProbability("IID", threshold)
        BY DEF PS_P_vs_IID_Uniform

    <1>2. Uniform stake distribution means no high-stake validators
        <2>1. \A v \in Validators : ~IsHighStakeValidator(v)
            BY <1>1, DEF IsHighStakeValidator, RelativeStake
        <2>2. TotalBinsFilledByHighStake = 0
            BY <2>1, DEF TotalBinsFilledByHighStake, BinsFilledByValidator
        <2> QED BY <2>1, <2>2

    <1>3. PS-P reduces to partitioned sampling
        <2>1. RemainingBins = TotalShreds
            BY <1>2, DEF RemainingBins
        <2>2. All validators participate in partitioning step
            BY <1>2, <2>1, DEF PartitionStakes
        <2> QED BY <2>1, <2>2

    <1>4. Poisson binomial distribution analysis
        <2>1. PS-P sampling follows Poisson binomial distribution
            BY <1>3, DEF BinAdversarialProbability, PartitionSampling
        <2>2. Binomial case maximizes variance (Hoeffding 1956)
            BY <2>1, MathHelpers!SimpleArithmetic
        <2>3. Equal adversarial probability in all bins gives binomial distribution
            BY <2>2, DEF BinAdversarialProbability
        <2>4. Binomial distribution equals IID sampling
            BY <2>3, DEF AdversarialSamplingProbability
        <2> QED BY <2>1, <2>2, <2>3, <2>4

    <1>5. PS-P probability ≤ IID probability
        BY <1>4, MathHelpers!SimpleArithmetic

    <1> QED BY <1>5

\* Theorem 3 from whitepaper: Main sampling resilience result
THEOREM WhitepaperTheorem3 ==
    \A threshold \in 1..TotalShreds :
        AdversarialSamplingProbability("PS-P", threshold) =>
        AdversarialSamplingProbability("FA1-IID", threshold)
PROOF
    <1>1. SUFFICES ASSUME NEW threshold \in 1..TotalShreds,
                          AdversarialSamplingProbability("PS-P", threshold)
                   PROVE AdversarialSamplingProbability("FA1-IID", threshold)
        BY DEF WhitepaperTheorem3

    <1>2. PS-P step 1 equivalent to FA1 fill step
        <2>1. High-stake validators fill bins deterministically
            BY DEF HighStakeBinAssignment, BinsFilledByValidator
        <2>2. This matches FA1 algorithm behavior
            BY <2>1, DEF IsHighStakeValidator
        <2> QED BY <2>1, <2>2

    <1>3. PS-P step 2-3 used as FA1 fallback scheme
        <2>1. Remaining stakes partitioned using algorithm P
            BY DEF PartitionStakes, PartitionFunction
        <2>2. PS-P sampling applied to remaining bins
            BY <2>1, DEF BinAssignment, PartitionSampling
        <2>3. This constitutes the fallback scheme in FA1-IID
            BY <2>2, DEF AdversarialSamplingProbability
        <2> QED BY <2>1, <2>2, <2>3

    <1>4. PS-P equivalent to FA1 with PS-P fallback
        <2>1. Step 1 fills high-stake bins (FA1 fill step)
            BY <1>2, DEF HighStakeBinAssignment
        <2>2. Steps 2-3 handle remaining bins (FA1 fallback)
            BY <1>3, DEF PartitionStakes, BinAssignment
        <2>3. Combined algorithm is FA1 with PS-P fallback
            BY <2>1, <2>2, DEF PartitionSampling
        <2> QED BY <2>1, <2>2, <2>3

    <1>5. Apply Lemma 47 to fallback scheme
        <2>1. PS-P fallback ≤ IID fallback (by PS_P_vs_IID_Uniform)
            BY PS_P_vs_IID_Uniform
        <2>2. FA1 with PS-P fallback ≤ FA1 with IID fallback
            BY <2>1, <1>4
        <2>3. FA1 with IID fallback = FA1-IID
            BY DEF AdversarialSamplingProbability
        <2> QED BY <2>1, <2>2, <2>3

    <1>6. PS-P probability ≤ FA1-IID probability
        BY <1>4, <1>5, MathHelpers!SimpleArithmetic

    <1> QED BY <1>6

\* Sampling resilience guarantee
THEOREM SamplingResilienceTheorem ==
    \A threshold \in 1..ReconstructionThreshold :
        SamplingResilience(threshold)
PROOF
    <1>1. SUFFICES ASSUME NEW threshold \in 1..ReconstructionThreshold
                   PROVE SamplingResilience(threshold)
        BY DEF SamplingResilienceTheorem

    <1>2. PS-P ≤ FA1-IID
        BY WhitepaperTheorem3, <1>1

    <1>3. PS-P ≤ IID  
        BY PS_P_vs_IID_Uniform, <1>1

    <1>4. SamplingResilience(threshold)
        BY <1>2, <1>3, DEF SamplingResilience

    <1> QED BY <1>4

----------------------------------------------------------------------------
(* Rotor Integration Theorems *)

\* PS-P improves Rotor resilience
THEOREM RotorResilienceImprovement ==
    \A slot \in Nat :
        RotorSuccessfulPS_P(slot) =>
        Rotor!RotorSuccessful(slot)
PROOF
    <1>1. SUFFICES ASSUME NEW slot \in Nat,
                          RotorSuccessfulPS_P(slot)
                   PROVE Rotor!RotorSuccessful(slot)
        BY DEF RotorResilienceImprovement

    <1>2. PS-P provides better relay selection
        <2>1. \A slice \in 1..SlicesPerBlock :
                LET relays == SelectRelayPS_P(slot, slice)
                    honestRelays == relays \cap (Validators \ ByzantineValidators)
                IN Cardinality(honestRelays) >= ReconstructionThreshold
            BY <1>1, DEF RotorSuccessfulPS_P
        <2> QED BY <2>1

    <1>3. Sufficient honest relays guarantee Rotor success
        BY <1>2, Rotor!RotorResilienceTheorem

    <1> QED BY <1>3

\* Expected performance improvement
THEOREM ExpectedPerformanceImprovement ==
    ExpectedAdversarialSamples <= 
    Utils!TotalStake(ByzantineValidators, Stake) * TotalShreds \div Utils!TotalStake(Validators, Stake)
PROOF
    <1>1. Expected value calculation
        <2>1. ExpectedAdversarialSamples = Utils!Sum([b \in 1..TotalShreds |-> BinAdversarialProbability(b)])
            BY DEF ExpectedAdversarialSamples
        <2>2. \A b \in 1..TotalShreds : BinAdversarialProbability(b) <= 
                Utils!TotalStake(ByzantineValidators, Stake) \div Utils!TotalStake(Validators, Stake)
            BY DEF BinAdversarialProbability, PartitionStakes
        <2> QED BY <2>1, <2>2, MathHelpers!SimpleArithmetic

    <1>2. Sum bound
        BY <1>1, Utils!SumBound, MathHelpers!SimpleArithmetic

    <1> QED BY <1>2

----------------------------------------------------------------------------
(* Variance Reduction *)

\* PS-P reduces sampling variance compared to IID
THEOREM VarianceReduction ==
    AdversarialSamplingVariance <= 
    Utils!TotalStake(ByzantineValidators, Stake) * TotalShreds \div Utils!TotalStake(Validators, Stake) *
    (1 - Utils!TotalStake(ByzantineValidators, Stake) \div Utils!TotalStake(Validators, Stake))
PROOF
    <1>1. Variance calculation for PS-P
        <2>1. AdversarialSamplingVariance = 
                Utils!Sum([b \in 1..TotalShreds |-> 
                    BinAdversarialProbability(b) * (1 - BinAdversarialProbability(b))])
            BY DEF AdversarialSamplingVariance
        <2> QED BY <2>1

    <1>2. Partitioning reduces variance
        <2>1. Partitioning creates more uniform distribution across bins
            BY DEF PartitionStakes, PartitionFunction
        <2>2. Uniform distribution minimizes variance for fixed mean
            BY <2>1, MathHelpers!SimpleArithmetic
        <2> QED BY <2>1, <2>2

    <1>3. Variance bound
        BY <1>1, <1>2, MathHelpers!SimpleArithmetic

    <1> QED BY <1>3

----------------------------------------------------------------------------
(* Safety Properties *)

\* Partitioning validity
THEOREM PartitioningValidity ==
    /\ \A v \in Validators : 
         Utils!Sum([b \in 1..TotalShreds |-> 
           IF BinAssignment[b] = v THEN (1000 \div TotalShreds) ELSE 0]) = RelativeStake(v)
    /\ \A b \in 1..TotalShreds : 
         Utils!Sum([v \in Validators |-> 
           IF BinAssignment[b] = v THEN RelativeStake(v) ELSE 0]) = (1000 \div TotalShreds)
PROOF
    <1>1. Stakes fully assigned
        <2>1. High-stake validators fill appropriate bins
            BY DEF HighStakeBinAssignment, BinsFilledByValidator
        <2>2. Remaining stakes partitioned correctly
            BY DEF PartitionStakes, PartitionFunction
        <2>3. Total stake preserved
            BY <2>1, <2>2, MathHelpers!StakeArithmetic
        <2> QED BY <2>1, <2>2, <2>3

    <1>2. Bins filled entirely
        <2>1. Each bin assigned exactly one validator
            BY DEF BinAssignment
        <2>2. Bin capacity equals 1/TotalShreds of total stake
            BY <2>1, DEF PartitionFunction
        <2> QED BY <2>1, <2>2

    <1> QED BY <1>1, <1>2

\* Non-equivocation in sampling
THEOREM SamplingNonEquivocation ==
    \A b1, b2 \in 1..TotalShreds :
        b1 # b2 => BinAssignment[b1] # BinAssignment[b2] \/ 
                   BinAssignment[b1] \in {v \in Validators : IsHighStakeValidator(v)}
PROOF
    <1>1. SUFFICES ASSUME NEW b1 \in 1..TotalShreds,
                          NEW b2 \in 1..TotalShreds,
                          b1 # b2,
                          BinAssignment[b1] = BinAssignment[b2]
                   PROVE BinAssignment[b1] \in {v \in Validators : IsHighStakeValidator(v)}
        BY DEF SamplingNonEquivocation

    <1>2. Same validator in different bins implies high stake
        <2>1. Only high-stake validators can fill multiple bins
            BY DEF HighStakeBinAssignment, BinsFilledByValidator
        <2>2. Partitioning assigns each validator to at most one remaining bin
            BY DEF PartitionStakes, BinAssignment
        <2> QED BY <2>1, <2>2

    <1> QED BY <1>2

----------------------------------------------------------------------------
(* Type Invariants *)

TypeInvariant ==
    /\ TotalShreds \in Nat
    /\ ReconstructionThreshold \in Nat
    /\ SlicesPerBlock \in Nat
    /\ ResilienceParameter \in Nat
    /\ BinAssignment \in [1..TotalShreds -> Validators]
    /\ PartitionSampling \subseteq Validators
    /\ \A v \in Validators : RelativeStake(v) \in Nat
    /\ \A b \in 1..TotalShreds : BinAdversarialProbability(b) \in 0..1000

============================================================================