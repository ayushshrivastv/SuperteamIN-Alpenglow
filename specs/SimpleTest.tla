---------------------------- MODULE SimpleTest ----------------------------
EXTENDS Integers

VARIABLES x

Init == x = 0

Next == x' = x + 1 /\ x < 5

Spec == Init /\ [][Next]_x

TypeOK == x \in 0..5

=============================================================================
