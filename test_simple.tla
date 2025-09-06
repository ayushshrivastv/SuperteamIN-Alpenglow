---- MODULE test_simple ----
EXTENDS Naturals

VARIABLE x

Init == x = 0
Next == x' = x + 1
Spec == Init /\ [][Next]_x

TypeOK == x \in Nat
====
