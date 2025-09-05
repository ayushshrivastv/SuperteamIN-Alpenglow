------------------------------ MODULE Utils ------------------------------
(* Common utility functions used across specifications *)
EXTENDS Sequences, Integers, FiniteSets, TLC

(**************************************************************************)
(* Basic Math Operations                                                   *)
(**************************************************************************)

\* Minimum of two values
Min(a, b) == IF a < b THEN a ELSE b

\* Maximum of two values
Max(a, b) == IF a > b THEN a ELSE b

\* Minimum of a set (requires non-empty set)
MinSet(S) ==
    IF S = {} THEN 0
    ELSE CHOOSE x \in S : \A y \in S : x <= y

\* Maximum of a set (requires non-empty set)
MaxSet(S) ==
    IF S = {} THEN 0
    ELSE CHOOSE x \in S : \A y \in S : x >= y

\* Recursive helper for summing sets
RECURSIVE SumSetRec(_)
SumSetRec(S) ==
    IF S = {} THEN 0
    ELSE LET x == CHOOSE y \in S : TRUE
         IN x + SumSetRec(S \ {x})

\* Sum of a set of integers
SumSet(S) == SumSetRec(S)

\* Recursive helper for summing sequences
RECURSIVE SumSeqHelper(_, _)
SumSeqHelper(seq, i) ==
    IF i = 0 THEN 0
    ELSE SumSeqHelper(seq, i-1) + seq[i]

\* Sum of sequence elements
SumSeq(seq) == SumSeqHelper(seq, Len(seq))

\* Recursive helper for summing function values
RECURSIVE SumRec(_, _)
SumRec(f, S) ==
    IF S = {} THEN 0
    ELSE LET x == CHOOSE y \in S : TRUE
         IN f[x] + SumRec(f, S \ {x})

\* Sum of function values over domain
Sum(f) == SumRec(f, DOMAIN f)

(**************************************************************************)
(* Set Operations                                                          *)
(**************************************************************************)

\* Check if set is subset of another
IsSubset(A, B) == A \subseteq B

\* Set intersection
Intersect(A, B) == A \cap B

\* Set union
Union(A, B) == A \cup B

\* Set difference
Difference(A, B) == A \ B

\* Power set (all subsets)
PowerSet(S) == SUBSET S

\* Cartesian product of two sets
CartesianProduct(A, B) == A \X B

(**************************************************************************)
(* Sequence Operations                                                     *)
(**************************************************************************)

\* Find unique elements in sequence
Unique(seq) == {seq[i] : i \in DOMAIN seq}

\* Get first element of sequence
Head(seq) ==
    IF Len(seq) = 0 THEN CHOOSE x : FALSE ELSE seq[1]

\* Get last element of sequence
Last(seq) ==
    IF Len(seq) = 0 THEN CHOOSE x : FALSE ELSE seq[Len(seq)]

\* Get tail of sequence (all but first element)
Tail(seq) ==
    IF Len(seq) <= 1 THEN <<>> ELSE SubSeq(seq, 2, Len(seq))

\* Reverse a sequence
Reverse(seq) ==
    [i \in DOMAIN seq |-> seq[Len(seq) + 1 - i]]

\* Check if sequence is empty
IsEmpty(seq) == Len(seq) = 0

----------------------------------------------------------------------------
(* General Helper Functions *)

\* Absolute difference between two numbers
AbsoluteDifference(a, b) ==
    IF a >= b THEN a - b ELSE b - a

\* Generate unique message identifier
GenerateMessageId(timestamp, sender) ==
    timestamp * 10000 + sender

\* Check if element exists in sequence
Contains(seq, elem) ==
    \E i \in DOMAIN seq : seq[i] = elem

\* Remove element from sequence
Remove(seq, elem) ==
    SelectSeq(seq, LAMBDA x: x # elem)

\* Merge two sets
Merge(set1, set2) ==
    set1 \cup set2

\* Count occurrences in sequence
Count(seq, elem) ==
    Cardinality({i \in DOMAIN seq : seq[i] = elem})


\* Recursive helper for flattening sequences
RECURSIVE FlattenHelper(_, _)
FlattenHelper(seqOfSeqs, i) ==
    IF i = 0 THEN <<>>
    ELSE FlattenHelper(seqOfSeqs, i-1) \o seqOfSeqs[i]

\* Flatten sequence of sequences (improved implementation)
Flatten(seqOfSeqs) == FlattenHelper(seqOfSeqs, Len(seqOfSeqs))

\* Take first n elements from sequence
Take(seq, n) ==
    SubSeq(seq, 1, Min(n, Len(seq)))

\* Drop first n elements from sequence
Drop(seq, n) ==
    SubSeq(seq, n+1, Len(seq))

\* Zip two sequences into sequence of pairs
Zip(seq1, seq2) ==
    [i \in 1..Min(Len(seq1), Len(seq2)) |-> <<seq1[i], seq2[i]>>]

\* Map function over sequence
Map(f(_), seq) ==
    [i \in DOMAIN seq |-> f(seq[i])]

\* Filter sequence by predicate
Filter(pred(_), seq) ==
    SelectSeq(seq, pred)

\* Recursive helper for fold/reduce
RECURSIVE FoldHelper(_, _, _, _)
FoldHelper(f(_, _), seq, init, i) ==
    IF i = 0 THEN init
    ELSE f(FoldHelper(f, seq, init, i-1), seq[i])

\* Fold/reduce over sequence (improved implementation)
Fold(f(_, _), init, seq) == FoldHelper(f, seq, init, Len(seq))

\* Check if all elements satisfy predicate
All(pred(_), seq) ==
    \A i \in DOMAIN seq : pred(seq[i])


\* Partition sequence by predicate
Partition(pred(_), seq) ==
    <<Filter(pred, seq), Filter(LAMBDA x: ~pred(x), seq)>>

\* Group elements by key function
GroupBy(keyFunc(_), seq) ==
    LET keys == Unique(Map(keyFunc, seq))
    IN [k \in keys |-> Filter(LAMBDA x: keyFunc(x) = k, seq)]

\* Sort sequence (insertion sort for small sequences)
Sort(seq, lessThan(_, _)) ==
    IF Len(seq) <= 1 THEN seq
    ELSE seq  \* For model checking, we keep it abstract

\* Binary search in sorted sequence (simplified)
BinarySearch(seq, elem) ==
    IF \E i \in DOMAIN seq : seq[i] = elem
    THEN CHOOSE i \in DOMAIN seq : seq[i] = elem
    ELSE 0

\* Clamp value between min and max
Clamp(value, minVal, maxVal) ==
    Min(Max(value, minVal), maxVal)

\* Absolute value
Abs(x) == IF x >= 0 THEN x ELSE -x

\* Sign function
Sign(x) == IF x > 0 THEN 1 ELSE IF x < 0 THEN -1 ELSE 0

\* Greatest Common Divisor
GCD(a, b) ==
    IF b = 0 THEN a
    ELSE GCD(b, a % b)

\* Least Common Multiple
LCM(a, b) == (a * b) \div GCD(a, b)

\* Power of two check (improved)
IsPowerOfTwo(n) ==
    /\ n > 0
    /\ \E k \in 0..20 : n = 2^k  \* Bounded for model checking

\* Next power of two (bounded)
NextPowerOfTwo(n) ==
    IF n <= 1 THEN 1
    ELSE CHOOSE p \in {2^k : k \in 1..20} : p >= n /\ \A q \in {2^j : j \in 1..20} : q >= n => p <= q

\* Check if number is even
IsEven(n) == n % 2 = 0

\* Check if number is odd
IsOdd(n) == n % 2 = 1

\* Recursive helper for factorial
RECURSIVE FactHelper(_)
FactHelper(i) ==
    IF i <= 1 THEN 1
    ELSE i * FactHelper(i-1)

\* Factorial (bounded for model checking)
Factorial(n) ==
    IF n <= 1 THEN 1
    ELSE FactHelper(n)

\* Binomial coefficient (n choose k)
Choose(n, k) ==
    IF k > n \/ k < 0 THEN 0
    ELSE Factorial(n) \div (Factorial(k) * Factorial(n - k))

(**************************************************************************)
(* String and Formatting Operations                                        *)
(**************************************************************************)

\* Convert number to string representation (abstract)
ToString(n) == n  \* Abstract for model checking

\* String concatenation (abstract)
Concat(s1, s2) == s1  \* Abstract for model checking

(**************************************************************************)
(* Consensus and Protocol Helper Functions                                *)
(**************************************************************************)

\* Select leader for a given view using round-robin
SelectLeader(view, validators) ==
    LET validatorList == CHOOSE seq \in Seq(validators) :
                             /\ Len(seq) = Cardinality(validators)
                             /\ \A v \in validators : \E i \in DOMAIN seq : seq[i] = v
                             /\ \A i, j \in DOMAIN seq : i # j => seq[i] # seq[j]
        n == Cardinality(validators)
        idx == ((view - 1) % n) + 1
    IN IF n = 0 THEN CHOOSE v : FALSE ELSE validatorList[idx]

\* Timeout duration with exponential backoff
TimeoutDuration(view, baseTimeout) ==
    baseTimeout * (2 ^ Min(view - 1, 10))  \* Cap exponential growth at 2^10

\* Calculate majority threshold
MajorityThreshold(total) == (total \div 2) + 1

\* Calculate supermajority threshold (2/3)
SupermajorityThreshold(total) == ((total * 2) \div 3) + 1

\* Calculate Byzantine fault tolerance threshold (1/3)
ByzantineThreshold(total) == total \div 3

\* Check if value is within tolerance
WithinTolerance(value, target, tolerance) ==
    Abs(value - target) <= tolerance

\* Linear interpolation between two values
Lerp(a, b, t) == a + (b - a) * t

\* Map value from one range to another
MapRange(value, fromMin, fromMax, toMin, toMax) ==
    toMin + ((value - fromMin) * (toMax - toMin)) \div (fromMax - fromMin)

(**************************************************************************)
(* Validation and Type Checking Helpers                                   *)
(**************************************************************************)

\* Check if value is in valid range
InRange(value, minVal, maxVal) ==
    /\ value >= minVal
    /\ value <= maxVal

\* Validate that set contains only elements of expected type
ValidateSetType(S, typeCheck(_)) ==
    \A x \in S : typeCheck(x)

\* Check if sequence has valid structure
ValidateSequence(seq, elementCheck(_)) ==
    \A i \in DOMAIN seq : elementCheck(seq[i])

\* Safe division (returns 0 if divisor is 0)
SafeDiv(a, b) == IF b = 0 THEN 0 ELSE a \div b

\* Safe modulo (returns 0 if divisor is 0)
SafeMod(a, b) == IF b = 0 THEN 0 ELSE a % b

(**************************************************************************)
(* Alpenglow Protocol Specific Functions                                  *)
(**************************************************************************)

\* Stake calculation functions (parameterized to work with any validator set and stake mapping)
TotalStake(validators, stake) == Sum([v \in validators |-> stake[v]])

HonestStake(validators, byzantineValidators, offlineValidators, stake) ==
    LET honestValidators == validators \ (byzantineValidators \cup offlineValidators)
    IN Sum([v \in honestValidators |-> stake[v]])

ByzantineStake(byzantineValidators, stake) == Sum([v \in byzantineValidators |-> stake[v]])

OfflineStake(offlineValidators, stake) == Sum([v \in offlineValidators |-> stake[v]])

\* Threshold calculation functions
FastThreshold(validators, stake) ==
    (4 * TotalStake(validators, stake)) \div 5  \* 80% threshold

SlowThreshold(validators, stake) ==
    (3 * TotalStake(validators, stake)) \div 5  \* 60% threshold

NotarizationThreshold(validators, stake) ==
    (3 * TotalStake(validators, stake)) \div 5  \* 60% threshold

SkipThreshold(validators, stake) ==
    (3 * TotalStake(validators, stake)) \div 5  \* 60% threshold

\* Generic threshold function for different certificate types
RequiredStake(certType, validators, stake) ==
    CASE certType = "fast" -> FastThreshold(validators, stake)
      [] certType = "slow" -> SlowThreshold(validators, stake)
      [] certType = "notarization" -> NotarizationThreshold(validators, stake)
      [] certType = "skip" -> SkipThreshold(validators, stake)
      [] OTHER -> 0

\* Percentage calculation functions
PercentageOf(part, total) ==
    IF total = 0 THEN 0 ELSE (part * 100) \div total

StakePercentage(validatorStake, totalStake) ==
    PercentageOf(validatorStake, totalStake)

\* Validation helper functions
IsValidStakeDistribution(validators, stake) ==
    /\ \A v \in validators : stake[v] >= 0  \* Non-negative stakes
    /\ TotalStake(validators, stake) > 0    \* Positive total stake

SatisfiesThreshold(votes, threshold, stake) ==
    LET voteStake == Sum([vote \in votes |-> stake[vote.validator]])
    IN voteStake >= threshold

SatisfiesFastThreshold(votes, validators, stake) ==
    SatisfiesThreshold(votes, FastThreshold(validators, stake), stake)

SatisfiesSlowThreshold(votes, validators, stake) ==
    SatisfiesThreshold(votes, SlowThreshold(validators, stake), stake)

\* Time helper functions
CurrentTime(clock) == clock

TimeoutExpired(timeout, currentTime) == currentTime >= timeout

WithinBounds(time, lowerBound, upperBound) ==
    /\ time >= lowerBound
    /\ time <= upperBound

TimeElapsed(startTime, currentTime) == currentTime - startTime

IsAfterGST(currentTime, gst) == currentTime > gst

\* Network timing helpers
MessageDeliveryTime(sendTime, currentTime, delta) ==
    IF currentTime >= sendTime + delta THEN TRUE ELSE FALSE

WithinNetworkBounds(sendTime, receiveTime, delta) ==
    receiveTime <= sendTime + delta

\* Additional set operations for protocol use
Cardinality(S) == Cardinality(S)  \* Already defined in TLA+, but explicit for clarity

IsSubset(S1, S2) == S1 \subseteq S2  \* Already defined above, keeping for consistency

Union(S1, S2) == S1 \cup S2  \* Already defined above, keeping for consistency

Intersection(S1, S2) == S1 \cap S2

SetDifference(S1, S2) == S1 \ S2

\* Validator set operations
HonestValidators(validators, byzantineValidators, offlineValidators) ==
    validators \ (byzantineValidators \cup offlineValidators)

ResponsiveValidators(validators, offlineValidators) ==
    validators \ offlineValidators

ActiveValidators(validators, byzantineValidators, offlineValidators) ==
    validators \ (byzantineValidators \cup offlineValidators)

\* Stake-weighted operations
StakeWeightedMajority(validatorSet, validators, stake) ==
    Sum([v \in validatorSet |-> stake[v]]) > TotalStake(validators, stake) \div 2

StakeWeightedSupermajority(validatorSet, validators, stake) ==
    Sum([v \in validatorSet |-> stake[v]]) >= (2 * TotalStake(validators, stake)) \div 3

HasByzantineMajority(byzantineValidators, validators, stake) ==
    ByzantineStake(byzantineValidators, stake) > TotalStake(validators, stake) \div 3

\* Certificate validation helpers
ValidCertificateStake(certStake, certType, validators, stake) ==
    certStake >= RequiredStake(certType, validators, stake)

CertificateHasValidThreshold(certificate, validators, stake) ==
    ValidCertificateStake(certificate.stake, certificate.type, validators, stake)

\* Vote aggregation helpers
AggregateVoteStake(votes, stake) ==
    Sum([vote \in votes |-> stake[vote.validator]])

VotesFromValidators(votes, validatorSet) ==
    {vote \in votes : vote.validator \in validatorSet}

HonestVotes(votes, validators, byzantineValidators, offlineValidators) ==
    VotesFromValidators(votes, HonestValidators(validators, byzantineValidators, offlineValidators))

\* Arithmetic helpers for protocol calculations
RoundUp(numerator, denominator) ==
    (numerator + denominator - 1) \div denominator

RoundDown(numerator, denominator) ==
    numerator \div denominator

\* Percentage threshold checks
ExceedsPercentage(part, total, percentage) ==
    part * 100 >= total * percentage

MeetsPercentage(part, total, percentage) ==
    part * 100 >= total * percentage

\* Byzantine fault tolerance calculations
MaxByzantineFaults(validators, stake) ==
    TotalStake(validators, stake) \div 3

RemainingByzantineTolerance(byzantineValidators, validators, stake) ==
    MaxByzantineFaults(validators, stake) - ByzantineStake(byzantineValidators, stake)

IsByzantineToleranceExceeded(byzantineValidators, validators, stake) ==
    ByzantineStake(byzantineValidators, stake) > MaxByzantineFaults(validators, stake)

\* Liveness condition checks
HasLivenessCondition(validators, byzantineValidators, offlineValidators, stake) ==
    LET honestStake == HonestStake(validators, byzantineValidators, offlineValidators, stake)
        totalStake == TotalStake(validators, stake)
    IN honestStake * 5 >= totalStake * 3  \* >= 60% honest stake

HasFastPathCondition(validators, byzantineValidators, offlineValidators, stake) ==
    LET responsiveStake == HonestStake(validators, byzantineValidators, offlineValidators, stake)
        totalStake == TotalStake(validators, stake)
    IN responsiveStake * 5 >= totalStake * 4  \* >= 80% responsive stake

\* Utility functions for bounds checking
StakeWithinBounds(stake, minStake, maxStake) ==
    WithinBounds(stake, minStake, maxStake)

ViewWithinBounds(view, maxView) ==
    WithinBounds(view, 1, maxView)

SlotWithinBounds(slot, maxSlot) ==
    WithinBounds(slot, 1, maxSlot)

============================================================================
