\* Author: Ayush Srivastava
-------------------------- MODULE test_votor_safety --------------------------
(***************************************************************************)
(* Unit test for Votor safety properties                                  *)
(***************************************************************************)

EXTENDS Votor, TLC

----------------------------------------------------------------------------
(* Test Configuration *)

TestValidators == {v1, v2, v3, v4, v5}
TestByzantine == {v5}
TestStake == [v1 |-> 30, v2 |-> 25, v3 |-> 20, v4 |-> 15, v5 |-> 10]

----------------------------------------------------------------------------
(* Safety Tests *)

\* Test: No double voting
TestNoDoubleVoting ==
    LET validator == v1
        view == 1
    IN
    /\ ProcessVote(validator, view, "block1")
    /\ ~ProcessVote(validator, view, "block2")  \* Should fail

\* Test: Conflicting certificates impossible
TestNoConflictingCertificates ==
    LET slot == 1
        cert1 == [block |-> "block1", slot |-> slot, votes |-> {v1, v2, v3}]
        cert2 == [block |-> "block2", slot |-> slot, votes |-> {v1, v2, v3}]
    IN
    ~(cert1 \in certificates /\ cert2 \in certificates)

\* Test: Byzantine cannot exceed threshold
TestByzantineThreshold ==
    LET byzantineStake == SumStake(TestByzantine)
        totalStake == SumStake(TestValidators)
    IN
    byzantineStake < totalStake \div 3

\* Test: Fast path requires 80% stake
TestFastPathStakeRequirement ==
    LET votes == {v1, v2, v3}  \* 75% stake
        totalStake == 100
        voteStake == 75
    IN
    voteStake < FastPathStake => ~CanFormFastCertificate(votes)

\* Test: Slow path requires 60% stake  
TestSlowPathStakeRequirement ==
    LET votes == {v1, v2}  \* 55% stake
        totalStake == 100
        voteStake == 55
    IN
    voteStake < SlowPathStake => ~CanFormSlowCertificate(votes)

----------------------------------------------------------------------------
(* Test Execution *)

TestSuite ==
    /\ TestNoDoubleVoting
    /\ TestNoConflictingCertificates
    /\ TestByzantineThreshold
    /\ TestFastPathStakeRequirement
    /\ TestSlowPathStakeRequirement

\* Property to check
PROPERTY AllTestsPass == TestSuite

============================================================================
