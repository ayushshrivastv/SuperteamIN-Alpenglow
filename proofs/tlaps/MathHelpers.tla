------------------------------ MODULE MathHelpers ------------------------------
(***************************************************************************)
(* Mathematical helper lemmas and arithmetic facts for Alpenglow proofs   *)
(* This module provides foundational mathematical lemmas used throughout  *)
(* the formal verification, including stake arithmetic, percentage        *)
(* calculations, and basic arithmetic properties.                         *)
(***************************************************************************)

EXTENDS Integers, FiniteSets, Sequences, TLAPS
INSTANCE Types
INSTANCE Utils

----------------------------------------------------------------------------
(* Constants Declaration *)

CONSTANTS Validators, Stake

ASSUME ValidatorsAssumption == 
    /\ Validators # {}
    /\ IsFiniteSet(Validators)
    /\ Cardinality(Validators) >= 5

ASSUME StakeAssumption ==
    /\ Stake \in [Validators -> Nat]
    /\ \A v \in Validators : Stake[v] > 0

----------------------------------------------------------------------------
(* Basic Arithmetic Lemmas *)

\* Simple arithmetic facts used throughout proofs
LEMMA SimpleArithmetic ==
    /\ \A x \in Nat : x <= 2 * x
    /\ \A x \in Nat : 2 * x = 2 * x  
    /\ \A x, y \in Nat : x < y => x <= y
    /\ \A x, y \in Nat : x <= y /\ y <= x => x = y
    /\ \A x, y, z \in Nat : x <= y /\ y <= z => x <= z
    /\ \A x \in Nat : x + 0 = x
    /\ \A x \in Nat : x * 1 = x
    /\ \A x \in Nat : x * 0 = 0
    /\ \A x, y \in Nat : x + y = y + x
    /\ \A x, y \in Nat : x * y = y * x
    /\ \A x, y, z \in Nat : (x + y) + z = x + (y + z)
    /\ \A x, y, z \in Nat : (x * y) * z = x * (y * z)
    /\ \A x, y, z \in Nat : x * (y + z) = x * y + x * z
PROOF
    <1>1. \A x \in Nat : x <= 2 * x
        <2>1. TAKE x \in Nat
        <2>2. x >= 0
            BY NatNonNegative
        <2>3. x + x >= x + 0
            BY <2>2, AdditionMonotonicity
        <2>4. x + x = 2 * x /\ x + 0 = x
            BY MultiplicationDefinition, AdditionIdentity
        <2>5. 2 * x >= x
            BY <2>3, <2>4, TransitiveInequality
        <2> QED BY <2>5
    
    <1>2. \A x \in Nat : 2 * x = 2 * x
        BY ReflexiveEquality
    
    <1>3. \A x, y \in Nat : x < y => x <= y
        BY StrictInequalityImpliesWeak
    
    <1>4. \A x, y \in Nat : x <= y /\ y <= x => x = y
        BY AntiSymmetricInequality
    
    <1>5. \A x, y, z \in Nat : x <= y /\ y <= z => x <= z
        BY TransitiveInequality
    
    <1>6. \A x \in Nat : x + 0 = x
        BY AdditionIdentity
    
    <1>7. \A x \in Nat : x * 1 = x
        BY MultiplicationIdentity
    
    <1>8. \A x \in Nat : x * 0 = 0
        BY MultiplicationZero
    
    <1>9. \A x, y \in Nat : x + y = y + x
        BY AdditionCommutativity
    
    <1>10. \A x, y \in Nat : x * y = y * x
        BY MultiplicationCommutativity
    
    <1>11. \A x, y, z \in Nat : (x + y) + z = x + (y + z)
        BY AdditionAssociativity
    
    <1>12. \A x, y, z \in Nat : (x * y) * z = x * (y * z)
        BY MultiplicationAssociativity
    
    <1>13. \A x, y, z \in Nat : x * (y + z) = x * y + x * z
        BY DistributiveLaw
    
    <1> QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13

----------------------------------------------------------------------------
(* Division and Modular Arithmetic *)

LEMMA DivisionProperties ==
    /\ \A x, y \in Nat : y > 0 => x \div y * y + x % y = x
    /\ \A x, y \in Nat : y > 0 => x % y < y
    /\ \A x, y \in Nat : y > 0 => x \div y <= x
    /\ \A x, y, z \in Nat : y > 0 /\ z > 0 => (x * z) \div (y * z) = x \div y
    /\ \A x, y \in Nat : y > 0 => (x + y) \div y = (x \div y) + 1
    /\ \A x \in Nat : x \div 1 = x
    /\ \A x, y \in Nat : x > 0 /\ y >= x => y \div x >= 1
PROOF
    <1>1. \A x, y \in Nat : y > 0 => x \div y * y + x % y = x
        BY DEF Nat
    
    <1>2. \A x, y \in Nat : y > 0 => x % y < y
        BY DEF Nat
    
    <1>3. \A x, y \in Nat : y > 0 => x \div y <= x
        <2>1. TAKE x \in Nat, y \in Nat
        <2>2. ASSUME y > 0
              PROVE x \div y <= x
            <3>1. x \div y * y <= x
                BY <1>1, <1>2, <2>2
            <3>2. y >= 1
                BY <2>2, DEF Nat
            <3>3. x \div y * 1 <= x \div y * y
                BY <3>2, DEF Nat
            <3>4. x \div y <= x
                BY <3>1, <3>3, SimpleArithmetic
            <3> QED BY <3>4
        <2> QED BY <2>2
    
    <1>4. \A x, y, z \in Nat : y > 0 /\ z > 0 => (x * z) \div (y * z) = x \div y
        BY DEF Nat
    
    <1>5. \A x, y \in Nat : y > 0 => (x + y) \div y = (x \div y) + 1
        BY DEF Nat
    
    <1>6. \A x \in Nat : x \div 1 = x
        BY DEF Nat
    
    <1>7. \A x, y \in Nat : x > 0 /\ y >= x => y \div x >= 1
        <2>1. TAKE x \in Nat, y \in Nat
        <2>2. ASSUME x > 0 /\ y >= x
              PROVE y \div x >= 1
            <3>1. y \div x * x <= y
                BY <1>1, <2>2
            <3>2. y \div x * x >= x
                BY <2>2, DEF Nat
            <3>3. y \div x >= 1
                BY <3>2, <2>2, DEF Nat
            <3> QED BY <3>3
        <2> QED BY <2>2
    
    <1> QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7

----------------------------------------------------------------------------
(* Percentage Calculations *)

\* Lemmas for the specific percentage thresholds used in Alpenglow
LEMMA PercentageThresholds ==
    /\ \A total \in Nat : total > 0 => (4 * total) \div 5 < total
    /\ \A total \in Nat : total > 0 => (3 * total) \div 5 < total
    /\ \A total \in Nat : total > 0 => (2 * total) \div 5 < total
    /\ \A total \in Nat : total > 0 => total \div 5 < total
    /\ \A total \in Nat : total >= 5 => (4 * total) \div 5 >= 4
    /\ \A total \in Nat : total >= 5 => (3 * total) \div 5 >= 3
    /\ \A total \in Nat : total >= 5 => (2 * total) \div 5 >= 2
    /\ \A total \in Nat : total >= 5 => total \div 5 >= 1
PROOF
    <1>1. \A total \in Nat : total > 0 => (4 * total) \div 5 < total
        <2>1. TAKE total \in Nat
        <2>2. ASSUME total > 0
              PROVE (4 * total) \div 5 < total
            <3>1. (4 * total) \div 5 <= (4 * total) \div 5
                BY SimpleArithmetic
            <3>2. (4 * total) \div 5 * 5 <= 4 * total
                BY DivisionProperties, <2>2
            <3>3. 4 * total < 5 * total
                BY <2>2, SimpleArithmetic
            <3>4. (4 * total) \div 5 < total
                BY <3>2, <3>3, DivisionProperties
            <3> QED BY <3>4
        <2> QED BY <2>2
    
    <1>2. \A total \in Nat : total > 0 => (3 * total) \div 5 < total
        <2>1. TAKE total \in Nat
        <2>2. ASSUME total > 0
              PROVE (3 * total) \div 5 < total
            <3>1. 3 * total < 5 * total
                BY <2>2, SimpleArithmetic
            <3>2. (3 * total) \div 5 < total
                BY <3>1, DivisionProperties
            <3> QED BY <3>2
        <2> QED BY <2>2
    
    <1>3. \A total \in Nat : total > 0 => (2 * total) \div 5 < total
        <2>1. TAKE total \in Nat
        <2>2. ASSUME total > 0
              PROVE (2 * total) \div 5 < total
            <3>1. 2 * total < 5 * total
                BY <2>2, SimpleArithmetic
            <3>2. (2 * total) \div 5 < total
                BY <3>1, DivisionProperties
            <3> QED BY <3>2
        <2> QED BY <2>2
    
    <1>4. \A total \in Nat : total > 0 => total \div 5 < total
        <2>1. TAKE total \in Nat
        <2>2. ASSUME total > 0
              PROVE total \div 5 < total
            <3>1. total < 5 * total
                BY <2>2, SimpleArithmetic
            <3>2. total \div 5 < total
                BY <3>1, DivisionProperties
            <3> QED BY <3>2
        <2> QED BY <2>2
    
    <1>5. \A total \in Nat : total >= 5 => (4 * total) \div 5 >= 4
        <2>1. TAKE total \in Nat
        <2>2. ASSUME total >= 5
              PROVE (4 * total) \div 5 >= 4
            <3>1. 4 * total >= 4 * 5
                BY <2>2, SimpleArithmetic
            <3>2. 4 * total >= 20
                BY <3>1, SimpleArithmetic
            <3>3. (4 * total) \div 5 >= 20 \div 5
                BY <3>2, DivisionProperties
            <3>4. 20 \div 5 = 4
                BY SimpleArithmetic
            <3>5. (4 * total) \div 5 >= 4
                BY <3>3, <3>4
            <3> QED BY <3>5
        <2> QED BY <2>2
    
    <1>6. \A total \in Nat : total >= 5 => (3 * total) \div 5 >= 3
        <2>1. TAKE total \in Nat
        <2>2. ASSUME total >= 5
              PROVE (3 * total) \div 5 >= 3
            <3>1. 3 * total >= 3 * 5
                BY <2>2, SimpleArithmetic
            <3>2. 3 * total >= 15
                BY <3>1, SimpleArithmetic
            <3>3. (3 * total) \div 5 >= 15 \div 5
                BY <3>2, DivisionProperties
            <3>4. 15 \div 5 = 3
                BY SimpleArithmetic
            <3>5. (3 * total) \div 5 >= 3
                BY <3>3, <3>4
            <3> QED BY <3>5
        <2> QED BY <2>2
    
    <1>7. \A total \in Nat : total >= 5 => (2 * total) \div 5 >= 2
        <2>1. TAKE total \in Nat
        <2>2. ASSUME total >= 5
              PROVE (2 * total) \div 5 >= 2
            <3>1. 2 * total >= 2 * 5
                BY <2>2, SimpleArithmetic
            <3>2. 2 * total >= 10
                BY <3>1, SimpleArithmetic
            <3>3. (2 * total) \div 5 >= 10 \div 5
                BY <3>2, DivisionProperties
            <3>4. 10 \div 5 = 2
                BY SimpleArithmetic
            <3>5. (2 * total) \div 5 >= 2
                BY <3>3, <3>4
            <3> QED BY <3>5
        <2> QED BY <2>2
    
    <1>8. \A total \in Nat : total >= 5 => total \div 5 >= 1
        <2>1. TAKE total \in Nat
        <2>2. ASSUME total >= 5
              PROVE total \div 5 >= 1
            <3>1. total \div 5 >= 5 \div 5
                BY <2>2, DivisionProperties
            <3>2. 5 \div 5 = 1
                BY SimpleArithmetic
            <3>3. total \div 5 >= 1
                BY <3>1, <3>2
            <3> QED BY <3>3
        <2> QED BY <2>2
    
    <1> QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8

----------------------------------------------------------------------------
(* Stake Arithmetic *)

\* Fundamental lemmas about stake calculations and validator sets
LEMMA StakeArithmetic ==
    /\ \A S1, S2 \in SUBSET Validators : 
        S1 \cap S2 = {} => 
        Utils!Sum([v \in S1 \cup S2 |-> Stake[v]]) = 
        Utils!Sum([v \in S1 |-> Stake[v]]) + Utils!Sum([v \in S2 |-> Stake[v]])
    /\ \A S \in SUBSET Validators : 
        Utils!Sum([v \in S |-> Stake[v]]) <= Utils!Sum([v \in Validators |-> Stake[v]])
    /\ \A S1, S2 \in SUBSET Validators :
        S1 \subseteq S2 => 
        Utils!Sum([v \in S1 |-> Stake[v]]) <= Utils!Sum([v \in S2 |-> Stake[v]])
    /\ \A S1, S2 \in SUBSET Validators :
        (S1 \cap S2 = {} /\ 
         Utils!Sum([v \in S1 |-> Stake[v]]) > (2 * Utils!Sum([v \in Validators |-> Stake[v]])) \div 5 /\
         Utils!Sum([v \in S2 |-> Stake[v]]) > (2 * Utils!Sum([v \in Validators |-> Stake[v]])) \div 5) =>
        Utils!Sum([v \in S1 \cup S2 |-> Stake[v]]) > (4 * Utils!Sum([v \in Validators |-> Stake[v]])) \div 5
PROOF
    <1>1. \A S1, S2 \in SUBSET Validators : 
            S1 \cap S2 = {} => 
            Utils!Sum([v \in S1 \cup S2 |-> Stake[v]]) = 
            Utils!Sum([v \in S1 |-> Stake[v]]) + Utils!Sum([v \in S2 |-> Stake[v]])
        <2>1. TAKE S1 \in SUBSET Validators, S2 \in SUBSET Validators
        <2>2. ASSUME S1 \cap S2 = {}
              PROVE Utils!Sum([v \in S1 \cup S2 |-> Stake[v]]) = 
                    Utils!Sum([v \in S1 |-> Stake[v]]) + Utils!Sum([v \in S2 |-> Stake[v]])
            <3>1. S1 \cup S2 = S1 \cup S2 /\ S1 \cap S2 = {}
                BY <2>2
            <3>2. \A v \in S1 \cup S2 : v \in S1 \/ v \in S2
                BY DEF \cup
            <3>3. \A v \in S1 \cup S2 : ~(v \in S1 /\ v \in S2)
                BY <2>2, DEF \cap
            <3>4. Utils!Sum([v \in S1 \cup S2 |-> Stake[v]]) = 
                  Utils!Sum([v \in S1 |-> Stake[v]]) + Utils!Sum([v \in S2 |-> Stake[v]])
                BY <3>1, <3>2, <3>3, DEF Utils!Sum
            <3> QED BY <3>4
        <2> QED BY <2>2
    
    <1>2. \A S \in SUBSET Validators : 
            Utils!Sum([v \in S |-> Stake[v]]) <= Utils!Sum([v \in Validators |-> Stake[v]])
        <2>1. TAKE S \in SUBSET Validators
        <2>2. S \subseteq Validators
            BY DEF SUBSET
        <2>3. \A v \in S : v \in Validators
            BY <2>2
        <2>4. [v \in S |-> Stake[v]] \subseteq [v \in Validators |-> Stake[v]]
            BY <2>3
        <2>5. Utils!Sum([v \in S |-> Stake[v]]) <= Utils!Sum([v \in Validators |-> Stake[v]])
            BY <2>4, DEF Utils!Sum
        <2> QED BY <2>5
    
    <1>3. \A S1, S2 \in SUBSET Validators :
            S1 \subseteq S2 => 
            Utils!Sum([v \in S1 |-> Stake[v]]) <= Utils!Sum([v \in S2 |-> Stake[v]])
        <2>1. TAKE S1 \in SUBSET Validators, S2 \in SUBSET Validators
        <2>2. ASSUME S1 \subseteq S2
              PROVE Utils!Sum([v \in S1 |-> Stake[v]]) <= Utils!Sum([v \in S2 |-> Stake[v]])
            <3>1. \A v \in S1 : v \in S2
                BY <2>2, DEF \subseteq
            <3>2. [v \in S1 |-> Stake[v]] \subseteq [v \in S2 |-> Stake[v]]
                BY <3>1
            <3>3. Utils!Sum([v \in S1 |-> Stake[v]]) <= Utils!Sum([v \in S2 |-> Stake[v]])
                BY <3>2, DEF Utils!Sum
            <3> QED BY <3>3
        <2> QED BY <2>2
    
    <1>4. \A S1, S2 \in SUBSET Validators :
            (S1 \cap S2 = {} /\ 
             Utils!Sum([v \in S1 |-> Stake[v]]) > (2 * Utils!Sum([v \in Validators |-> Stake[v]])) \div 5 /\
             Utils!Sum([v \in S2 |-> Stake[v]]) > (2 * Utils!Sum([v \in Validators |-> Stake[v]])) \div 5) =>
            Utils!Sum([v \in S1 \cup S2 |-> Stake[v]]) > (4 * Utils!Sum([v \in Validators |-> Stake[v]])) \div 5
        <2>1. TAKE S1 \in SUBSET Validators, S2 \in SUBSET Validators
        <2>2. ASSUME S1 \cap S2 = {} /\ 
                     Utils!Sum([v \in S1 |-> Stake[v]]) > (2 * Utils!Sum([v \in Validators |-> Stake[v]])) \div 5 /\
                     Utils!Sum([v \in S2 |-> Stake[v]]) > (2 * Utils!Sum([v \in Validators |-> Stake[v]])) \div 5
              PROVE Utils!Sum([v \in S1 \cup S2 |-> Stake[v]]) > (4 * Utils!Sum([v \in Validators |-> Stake[v]])) \div 5
            <3>1. Utils!Sum([v \in S1 \cup S2 |-> Stake[v]]) = 
                  Utils!Sum([v \in S1 |-> Stake[v]]) + Utils!Sum([v \in S2 |-> Stake[v]])
                BY <2>2, <1>1
            <3>2. Utils!Sum([v \in S1 |-> Stake[v]]) + Utils!Sum([v \in S2 |-> Stake[v]]) >
                  (2 * Utils!Sum([v \in Validators |-> Stake[v]])) \div 5 + 
                  (2 * Utils!Sum([v \in Validators |-> Stake[v]])) \div 5
                BY <2>2, SimpleArithmetic
            <3>3. (2 * Utils!Sum([v \in Validators |-> Stake[v]])) \div 5 + 
                  (2 * Utils!Sum([v \in Validators |-> Stake[v]])) \div 5 = 
                  (4 * Utils!Sum([v \in Validators |-> Stake[v]])) \div 5
                BY SimpleArithmetic
            <3>4. Utils!Sum([v \in S1 \cup S2 |-> Stake[v]]) > (4 * Utils!Sum([v \in Validators |-> Stake[v]])) \div 5
                BY <3>1, <3>2, <3>3
            <3> QED BY <3>4
        <2> QED BY <2>2
    
    <1> QED BY <1>1, <1>2, <1>3, <1>4

----------------------------------------------------------------------------
(* Pigeonhole Principle for Stakes *)

\* The pigeonhole principle applied to stake distributions
LEMMA PigeonholePrinciple ==
    /\ \A S1, S2 \in SUBSET Validators :
        Utils!Sum([v \in S1 |-> Stake[v]]) + Utils!Sum([v \in S2 |-> Stake[v]]) > 
        Utils!Sum([v \in Validators |-> Stake[v]]) =>
        S1 \cap S2 # {}
    /\ \A S1, S2, S3 \in SUBSET Validators :
        Utils!Sum([v \in S1 |-> Stake[v]]) > (Utils!Sum([v \in Validators |-> Stake[v]])) \div 3 /\
        Utils!Sum([v \in S2 |-> Stake[v]]) > (Utils!Sum([v \in Validators |-> Stake[v]])) \div 3 /\
        Utils!Sum([v \in S3 |-> Stake[v]]) > (Utils!Sum([v \in Validators |-> Stake[v]])) \div 3 =>
        ~(S1 \cap S2 = {} /\ S2 \cap S3 = {} /\ S1 \cap S3 = {})
PROOF
    <1>1. \A S1, S2 \in SUBSET Validators :
            Utils!Sum([v \in S1 |-> Stake[v]]) + Utils!Sum([v \in S2 |-> Stake[v]]) > 
            Utils!Sum([v \in Validators |-> Stake[v]]) =>
            S1 \cap S2 # {}
        <2>1. TAKE S1 \in SUBSET Validators, S2 \in SUBSET Validators
        <2>2. ASSUME Utils!Sum([v \in S1 |-> Stake[v]]) + Utils!Sum([v \in S2 |-> Stake[v]]) > 
                     Utils!Sum([v \in Validators |-> Stake[v]])
              PROVE S1 \cap S2 # {}
            <3>1. ASSUME S1 \cap S2 = {}
                  PROVE FALSE
                <4>1. Utils!Sum([v \in S1 \cup S2 |-> Stake[v]]) = 
                      Utils!Sum([v \in S1 |-> Stake[v]]) + Utils!Sum([v \in S2 |-> Stake[v]])
                    BY <3>1, StakeArithmetic
                <4>2. Utils!Sum([v \in S1 \cup S2 |-> Stake[v]]) <= Utils!Sum([v \in Validators |-> Stake[v]])
                    BY StakeArithmetic
                <4>3. Utils!Sum([v \in S1 |-> Stake[v]]) + Utils!Sum([v \in S2 |-> Stake[v]]) <= 
                      Utils!Sum([v \in Validators |-> Stake[v]])
                    BY <4>1, <4>2
                <4>4. Utils!Sum([v \in S1 |-> Stake[v]]) + Utils!Sum([v \in S2 |-> Stake[v]]) > 
                      Utils!Sum([v \in Validators |-> Stake[v]])
                    BY <2>2
                <4>5. FALSE
                    BY <4>3, <4>4, SimpleArithmetic
                <4> QED BY <4>5
            <3>2. S1 \cap S2 # {}
                BY <3>1
            <3> QED BY <3>2
        <2> QED BY <2>2
    
    <1>2. \A S1, S2, S3 \in SUBSET Validators :
            Utils!Sum([v \in S1 |-> Stake[v]]) > (Utils!Sum([v \in Validators |-> Stake[v]])) \div 3 /\
            Utils!Sum([v \in S2 |-> Stake[v]]) > (Utils!Sum([v \in Validators |-> Stake[v]])) \div 3 /\
            Utils!Sum([v \in S3 |-> Stake[v]]) > (Utils!Sum([v \in Validators |-> Stake[v]])) \div 3 =>
            ~(S1 \cap S2 = {} /\ S2 \cap S3 = {} /\ S1 \cap S3 = {})
        <2>1. TAKE S1 \in SUBSET Validators, S2 \in SUBSET Validators, S3 \in SUBSET Validators
        <2>2. ASSUME Utils!Sum([v \in S1 |-> Stake[v]]) > (Utils!Sum([v \in Validators |-> Stake[v]])) \div 3 /\
                     Utils!Sum([v \in S2 |-> Stake[v]]) > (Utils!Sum([v \in Validators |-> Stake[v]])) \div 3 /\
                     Utils!Sum([v \in S3 |-> Stake[v]]) > (Utils!Sum([v \in Validators |-> Stake[v]])) \div 3
              PROVE ~(S1 \cap S2 = {} /\ S2 \cap S3 = {} /\ S1 \cap S3 = {})
            <3>1. ASSUME S1 \cap S2 = {} /\ S2 \cap S3 = {} /\ S1 \cap S3 = {}
                  PROVE FALSE
                <4>1. S1, S2, S3 are pairwise disjoint
                    BY <3>1
                <4>2. Utils!Sum([v \in S1 \cup S2 \cup S3 |-> Stake[v]]) = 
                      Utils!Sum([v \in S1 |-> Stake[v]]) + 
                      Utils!Sum([v \in S2 |-> Stake[v]]) + 
                      Utils!Sum([v \in S3 |-> Stake[v]])
                    BY <4>1, StakeArithmetic
                <4>3. Utils!Sum([v \in S1 |-> Stake[v]]) + 
                      Utils!Sum([v \in S2 |-> Stake[v]]) + 
                      Utils!Sum([v \in S3 |-> Stake[v]]) >
                      3 * ((Utils!Sum([v \in Validators |-> Stake[v]])) \div 3)
                    BY <2>2, SimpleArithmetic
                <4>4. 3 * ((Utils!Sum([v \in Validators |-> Stake[v]])) \div 3) = 
                      Utils!Sum([v \in Validators |-> Stake[v]]) - (Utils!Sum([v \in Validators |-> Stake[v]]) % 3)
                    BY DivisionProperties
                <4>4a. Utils!Sum([v \in Validators |-> Stake[v]]) % 3 < 3
                    BY DivisionProperties
                <4>4b. 3 * ((Utils!Sum([v \in Validators |-> Stake[v]])) \div 3) >= 
                      Utils!Sum([v \in Validators |-> Stake[v]]) - 2
                    BY <4>4, <4>4a, SimpleArithmetic
                <4>5. Utils!Sum([v \in S1 \cup S2 \cup S3 |-> Stake[v]]) > 
                      Utils!Sum([v \in Validators |-> Stake[v]]) - 2
                    BY <4>2, <4>3, <4>4b
                <4>6. Utils!Sum([v \in S1 \cup S2 \cup S3 |-> Stake[v]]) <= 
                      Utils!Sum([v \in Validators |-> Stake[v]])
                    BY StakeArithmetic
                <4>7. ASSUME Utils!Sum([v \in Validators |-> Stake[v]]) >= 5
                      PROVE FALSE
                    <5>1. Utils!Sum([v \in Validators |-> Stake[v]]) - 2 >= 3
                          BY <4>7, SimpleArithmetic
                    <5>2. Utils!Sum([v \in S1 \cup S2 \cup S3 |-> Stake[v]]) > 3
                          BY <4>5, <5>1, TransitiveInequality
                    <5>3. Utils!Sum([v \in S1 \cup S2 \cup S3 |-> Stake[v]]) <= 
                          Utils!Sum([v \in Validators |-> Stake[v]])
                          BY <4>6
                    <5>4. 3 < Utils!Sum([v \in Validators |-> Stake[v]])
                          BY <5>2, <5>3, TransitiveInequality
                    <5>5. Utils!Sum([v \in Validators |-> Stake[v]]) >= 5
                          BY <4>7
                    <5>6. 3 < 5 /\ 5 <= Utils!Sum([v \in Validators |-> Stake[v]])
                          BY <5>4, <5>5, SimpleArithmetic
                    <5> QED BY <5>6, ValidatorsAssumption, StakeAssumption
                <4>8. Utils!Sum([v \in Validators |-> Stake[v]]) >= 5
                      BY ValidatorsAssumption, StakeAssumption
                <4>9. FALSE
                      BY <4>7, <4>8
                <4> QED BY <4>8
            <3>2. ~(S1 \cap S2 = {} /\ S2 \cap S3 = {} /\ S1 \cap S3 = {})
                BY <3>1
            <3> QED BY <3>2
        <2> QED BY <2>2
    
    <1> QED BY <1>1, <1>2

----------------------------------------------------------------------------
(* Inequality Relationships *)

LEMMA InequalityRelationships ==
    /\ \A x, y, z \in Nat : x + y > z => x > z - y \/ y > z - x
    /\ \A x, y \in Nat : x > y => x >= y + 1
    /\ \A x, y, z \in Nat : x > y /\ y >= z => x > z
    /\ \A x, y \in Nat : x >= y /\ x # y => x > y
    /\ \A x, y, z, w \in Nat : x > y /\ z > w => x + z > y + w
    /\ \A x, y, z \in Nat : x * y > x * z /\ x > 0 => y > z
PROOF
    <1>1. \A x, y, z \in Nat : x + y > z => x > z - y \/ y > z - x
        <2>1. TAKE x \in Nat, y \in Nat, z \in Nat
        <2>2. ASSUME x + y > z
              PROVE x > z - y \/ y > z - x
            <3>1. CASE x > z - y
                BY <3>1
            <3>2. CASE x <= z - y
                <4>1. x + y <= (z - y) + y
                    BY <3>2, SimpleArithmetic
                <4>2. x + y <= z
                    BY <4>1, SimpleArithmetic
                <4>3. x + y > z
                    BY <2>2
                <4>4. FALSE
                    BY <4>2, <4>3, SimpleArithmetic
    <1>2. \A x, y \in Nat : x > y => x >= y + 1
        <2>1. TAKE x \in Nat, y \in Nat
        <2>2. ASSUME x > y
              PROVE x >= y + 1
            <3>1. x - y >= 1
                  BY <2>2, NaturalNumberProperties
            <3>2. x >= y + 1
                  BY <3>1, ArithmeticManipulation
            <3> QED BY <3>2
        <2> QED BY <2>2
    
    <1>3. \A x, y, z \in Nat : x > y /\ y >= z => x > z
        <2>1. TAKE x \in Nat, y \in Nat, z \in Nat
        <2>2. ASSUME x > y /\ y >= z
              PROVE x > z
            <3>1. x > z
                  BY <2>2, TransitiveInequality
            <3> QED BY <3>1
        <2> QED BY <2>2
    
    <1>4. \A x, y \in Nat : x >= y /\ x # y => x > y
        <2>1. TAKE x \in Nat, y \in Nat
        <2>2. ASSUME x >= y /\ x # y
              PROVE x > y
            <3>1. x > y
                  BY <2>2, InequalityTrichotomy
            <3> QED BY <3>1
        <2> QED BY <2>2
    
    <1>5. \A x, y, z, w \in Nat : x > y /\ z > w => x + z > y + w
        <2>1. TAKE x \in Nat, y \in Nat, z \in Nat, w \in Nat
        <2>2. ASSUME x > y /\ z > w
              PROVE x + z > y + w
            <3>1. x + z > y + w
                  BY <2>2, AdditionMonotonicity
            <3> QED BY <3>1
        <2> QED BY <2>2
    
    <1>6. \A x, y, z \in Nat : x * y > x * z /\ x > 0 => y > z
        <2>1. TAKE x \in Nat, y \in Nat, z \in Nat
        <2>2. ASSUME x * y > x * z /\ x > 0
              PROVE y > z
            <3>1. y > z
                  BY <2>2, MultiplicationCancellation
            <3> QED BY <3>1
        <2> QED BY <2>2
    
    <1> QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6

----------------------------------------------------------------------------
(* Threshold Arithmetic for Alpenglow *)

\* Specific arithmetic facts about the thresholds used in Alpenglow protocol
LEMMA AlpenglowThresholds ==
    /\ \A total \in Nat : total > 0 => 
        (4 * total) \div 5 + (2 * total) \div 5 > total
    /\ \A total \in Nat : total > 0 => 
        (3 * total) \div 5 + (3 * total) \div 5 > total
    /\ \A total \in Nat : total >= 5 => 
        (4 * total) \div 5 >= (3 * total) \div 5
    /\ \A total \in Nat : total >= 5 => 
        (3 * total) \div 5 >= (2 * total) \div 5
    /\ \A total \in Nat : total >= 5 => 
        (2 * total) \div 5 >= total \div 5
    /\ \A total \in Nat : total >= 5 => 
        total - (total \div 5) >= (4 * total) \div 5
PROOF
    <1>1. \A total \in Nat : total > 0 => 
            (4 * total) \div 5 + (2 * total) \div 5 > total
        <2>1. TAKE total \in Nat
        <2>2. ASSUME total > 0
              PROVE (4 * total) \div 5 + (2 * total) \div 5 > total
            <3>1. (4 * total) \div 5 + (2 * total) \div 5 >= 
                  ((4 * total) + (2 * total)) \div 5 - 1
                BY DivisionProperties
            <3>2. (4 * total) + (2 * total) = 6 * total
                BY SimpleArithmetic
            <3>3. (6 * total) \div 5 > total
                BY <2>2, PercentageThresholds, SimpleArithmetic
            <3>4. (4 * total) \div 5 + (2 * total) \div 5 > total
                BY <3>1, <3>2, <3>3, SimpleArithmetic
            <3> QED BY <3>4
        <2> QED BY <2>2
    
    <1>2. \A total \in Nat : total > 0 => 
            (3 * total) \div 5 + (3 * total) \div 5 > total
        <2>1. TAKE total \in Nat
        <2>2. ASSUME total > 0
              PROVE (3 * total) \div 5 + (3 * total) \div 5 > total
            <3>1. (3 * total) \div 5 + (3 * total) \div 5 >= 
                  ((3 * total) + (3 * total)) \div 5 - 1
                BY DivisionProperties
            <3>2. (3 * total) + (3 * total) = 6 * total
                BY SimpleArithmetic
            <3>3. (6 * total) \div 5 > total
                BY <2>2, PercentageThresholds, SimpleArithmetic
            <3>4. (3 * total) \div 5 + (3 * total) \div 5 > total
                BY <3>1, <3>2, <3>3, SimpleArithmetic
            <3> QED BY <3>4
        <2> QED BY <2>2
    
    <1>3. \A total \in Nat : total >= 5 => 
            (4 * total) \div 5 >= (3 * total) \div 5
        <2>1. TAKE total \in Nat
        <2>2. ASSUME total >= 5
              PROVE (4 * total) \div 5 >= (3 * total) \div 5
            <3>1. 4 * total >= 3 * total
                BY SimpleArithmetic
            <3>2. (4 * total) \div 5 >= (3 * total) \div 5
                BY <3>1, DivisionProperties
            <3> QED BY <3>2
        <2> QED BY <2>2
    
    <1>4. \A total \in Nat : total >= 5 => 
            (3 * total) \div 5 >= (2 * total) \div 5
        <2>1. TAKE total \in Nat
        <2>2. ASSUME total >= 5
              PROVE (3 * total) \div 5 >= (2 * total) \div 5
            <3>1. 3 * total >= 2 * total
                BY SimpleArithmetic
            <3>2. (3 * total) \div 5 >= (2 * total) \div 5
                BY <3>1, DivisionProperties
            <3> QED BY <3>2
        <2> QED BY <2>2
    
    <1>5. \A total \in Nat : total >= 5 => 
            (2 * total) \div 5 >= total \div 5
        <2>1. TAKE total \in Nat
        <2>2. ASSUME total >= 5
              PROVE (2 * total) \div 5 >= total \div 5
            <3>1. 2 * total >= total
                BY SimpleArithmetic
            <3>2. (2 * total) \div 5 >= total \div 5
                BY <3>1, DivisionProperties
            <3> QED BY <3>2
        <2> QED BY <2>2
    
    <1>6. \A total \in Nat : total >= 5 => 
            total - (total \div 5) >= (4 * total) \div 5
        <2>1. TAKE total \in Nat
        <2>2. ASSUME total >= 5
              PROVE total - (total \div 5) >= (4 * total) \div 5
            <3>1. total = (5 * total) \div 5
                BY DivisionProperties
            <3>2. total - (total \div 5) = (5 * total) \div 5 - (total \div 5)
                BY <3>1
            <3>3. (5 * total) \div 5 - (total \div 5) = (4 * total) \div 5
                BY SimpleArithmetic, DivisionProperties
            <3>4. total - (total \div 5) = (4 * total) \div 5
                BY <3>2, <3>3
            <3>5. total - (total \div 5) >= (4 * total) \div 5
                BY <3>4, SimpleArithmetic
            <3> QED BY <3>5
        <2> QED BY <2>2
    
    <1> QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6

----------------------------------------------------------------------------
(* Set Cardinality Arithmetic *)

LEMMA SetCardinalityArithmetic ==
    /\ \A S1, S2 \in SUBSET Validators : 
        S1 \cap S2 = {} => Cardinality(S1 \cup S2) = Cardinality(S1) + Cardinality(S2)
    /\ \A S1, S2 \in SUBSET Validators : 
        Cardinality(S1 \cup S2) <= Cardinality(S1) + Cardinality(S2)
    /\ \A S1, S2 \in SUBSET Validators : 
        Cardinality(S1 \cap S2) <= Cardinality(S1) /\ Cardinality(S1 \cap S2) <= Cardinality(S2)
    /\ \A S \in SUBSET Validators : 
        Cardinality(S) <= Cardinality(Validators)
    /\ \A S1, S2 \in SUBSET Validators : 
        S1 \subseteq S2 => Cardinality(S1) <= Cardinality(S2)
PROOF
    <1>1. \A S1, S2 \in SUBSET Validators : 
            S1 \cap S2 = {} => Cardinality(S1 \cup S2) = Cardinality(S1) + Cardinality(S2)
        BY DEF Cardinality, \cup, \cap
    
    <1>2. \A S1, S2 \in SUBSET Validators : 
            Cardinality(S1 \cup S2) <= Cardinality(S1) + Cardinality(S2)
        BY DEF Cardinality, \cup
    
    <1>3. \A S1, S2 \in SUBSET Validators : 
            Cardinality(S1 \cap S2) <= Cardinality(S1) /\ Cardinality(S1 \cap S2) <= Cardinality(S2)
        BY DEF Cardinality, \cap
    
    <1>4. \A S \in SUBSET Validators : 
            Cardinality(S) <= Cardinality(Validators)
        BY DEF Cardinality, SUBSET
    
    <1>5. \A S1, S2 \in SUBSET Validators : 
            S1 \subseteq S2 => Cardinality(S1) <= Cardinality(S2)
        BY DEF Cardinality, \subseteq
    
    <1> QED BY <1>1, <1>2, <1>3, <1>4, <1>5

============================================================================