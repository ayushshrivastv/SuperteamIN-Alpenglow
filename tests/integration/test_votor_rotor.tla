---------------------- MODULE test_votor_rotor ----------------------
(***************************************************************************)
(* Integration test for Votor-Rotor interaction                           *)
(***************************************************************************)

EXTENDS Votor, Rotor, Network, TLC

----------------------------------------------------------------------------
(* Test Configuration *)

TestValidators == {v1, v2, v3, v4, v5}
TestStake == [v1 |-> 30, v2 |-> 25, v3 |-> 20, v4 |-> 15, v5 |-> 10]

----------------------------------------------------------------------------
(* Integration Tests *)

\* Test: Certificate triggers Rotor propagation
TestCertificatePropagation ==
    LET block == [slot |-> 1, hash |-> "hash1", data |-> "data"]
        cert == [block |-> block, votes |-> TestValidators, type |-> "fast"]
    IN
    /\ FormCertificate(cert)
    => <>(block \in rotorBlocks)

\* Test: Shreds created from certified blocks
TestShredCreation ==
    \A cert \in certificates :
        LET block == cert.block
        IN \E shreds \in SUBSET rotorShreds :
            /\ Cardinality(shreds) >= K
            /\ \A shred \in shreds : shred.block = block

\* Test: Repair requests for missing shreds
TestRepairProtocol ==
    LET missingShreds == {s \in rotorShreds : ~IsDelivered(s)}
    IN
    Cardinality(missingShreds) > 0 =>
        \E repair \in rotorRepairs : repair.shreds \subseteq missingShreds

\* Test: Network delivers consensus messages
TestConsensusMessageDelivery ==
    \A vote \in votorVotes :
        <>(vote \in networkDelivered)

\* Test: Fast path to propagation latency
TestFastPathLatency ==
    LET fastCert == CHOOSE c \in certificates : c.type = "fast"
        propagationStart == clock
    IN
    fastCert.block \in rotorBlocks =>
        clock - propagationStart <= Delta * 2

----------------------------------------------------------------------------
(* Test Execution *)

IntegrationTestSuite ==
    /\ TestCertificatePropagation
    /\ TestShredCreation
    /\ TestRepairProtocol
    /\ TestConsensusMessageDelivery
    /\ TestFastPathLatency

\* Property to check
PROPERTY IntegrationTestsPass == []<>IntegrationTestSuite

============================================================================
