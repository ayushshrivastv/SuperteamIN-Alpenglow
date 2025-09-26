\* Author: Ayush Srivastava
---- MODULE StakeTest ----
\* Simple stake definition for testing

EXTENDS Integers

CONSTANTS v1, v2, v3

\* Define Stake as a function
Stake == [v \in {v1, v2, v3} |-> 10]

====
