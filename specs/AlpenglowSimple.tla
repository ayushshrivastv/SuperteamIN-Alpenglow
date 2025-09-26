\* Author: Ayush Srivastava
------------------------------- MODULE AlpenglowSimple -------------------------------
(**************************************************************************)
(* Simplified Alpenglow specification for testing TLC                      *)
(**************************************************************************)

EXTENDS Integers, Sequences, FiniteSets, TLC

\* Constants
CONSTANTS 
    Validators,           \* Set of validator identifiers
    ByzantineValidators,  \* Set of Byzantine validators
    OfflineValidators,    \* Set of offline validators
    MaxSlot,              \* Maximum slot number
    MaxView,              \* Maximum view number
    MaxTime               \* Maximum time

\* Variables
VARIABLES
    currentSlot,          \* Current slot number
    clock,                \* Global clock
    messages,             \* Set of messages in transit
    votorView,            \* View number per validator
    votorVotedBlocks,     \* Blocks voted by each validator
    votorFinalizedChain   \* Finalized chain per validator

\* Helper definitions
HonestValidators == Validators \ (ByzantineValidators \union OfflineValidators)

\* Type invariant
TypeInvariant ==
    /\ currentSlot \in Nat
    /\ clock \in Nat
    /\ messages \subseteq [type: STRING, sender: Validators, slot: Nat]
    /\ votorView \in [Validators -> Nat]
    /\ votorVotedBlocks \in [Validators -> SUBSET Nat]
    /\ votorFinalizedChain \in [Validators -> Seq(Nat)]

\* Initial state
Init ==
    /\ currentSlot = 0
    /\ clock = 0
    /\ messages = {}
    /\ votorView = [v \in Validators |-> 1]
    /\ votorVotedBlocks = [v \in Validators |-> {}]
    /\ votorFinalizedChain = [v \in Validators |-> <<>>]

\* Advance time
AdvanceTime ==
    /\ clock' = clock + 1
    /\ UNCHANGED <<currentSlot, messages, votorView, votorVotedBlocks, votorFinalizedChain>>

\* Advance slot
AdvanceSlot ==
    /\ currentSlot < MaxSlot
    /\ currentSlot' = currentSlot + 1
    /\ UNCHANGED <<clock, messages, votorView, votorVotedBlocks, votorFinalizedChain>>

\* Simple vote action
Vote(v) ==
    /\ v \in HonestValidators
    /\ votorView[v] <= MaxView
    /\ LET newBlock == currentSlot * 100 + votorView[v]
       IN votorVotedBlocks' = [votorVotedBlocks EXCEPT ![v] = @ \union {newBlock}]
    /\ UNCHANGED <<currentSlot, clock, messages, votorView, votorFinalizedChain>>

\* Next state relation
Next ==
    \/ AdvanceTime
    \/ AdvanceSlot
    \/ \E v \in Validators : Vote(v)

\* Specification
Spec == Init /\ [][Next]_<<currentSlot, clock, messages, votorView, votorVotedBlocks, votorFinalizedChain>>

\* Safety properties
Safety == currentSlot <= MaxSlot

\* Liveness properties
Progress == <>(currentSlot = MaxSlot)

\* Helper function for minimum
Min(a, b) == IF a < b THEN a ELSE b

\* Invariants
ChainConsistency ==
    \A v1, v2 \in HonestValidators :
        Len(votorFinalizedChain[v1]) > 0 /\ Len(votorFinalizedChain[v2]) > 0 =>
            \E i \in 1..Min(Len(votorFinalizedChain[v1]), Len(votorFinalizedChain[v2])) :
                votorFinalizedChain[v1][i] = votorFinalizedChain[v2][i]

\* Action constraint for model checking
ActionConstraint ==
    /\ currentSlot <= MaxSlot
    /\ clock <= MaxTime
    /\ \A v \in Validators : votorView[v] <= MaxView

============================================================================
