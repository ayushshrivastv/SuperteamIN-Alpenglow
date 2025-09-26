---------------------------- MODULE SafetyCore ----------------------------
(***************************************************************************)
(* Standalone Safety Verification for Alpenglow Consensus                 *)
(* Self-contained module proving the three required safety theorems        *)
(* without complex dependencies - First Principles Approach               *)
(***************************************************************************)

EXTENDS Integers, FiniteSets, Sequences, TLC

CONSTANTS
    Validators,          \* Set of validator identifiers
    ByzantineValidators, \* Set of Byzantine validators (≤20%)
    MaxSlot,             \* Maximum slot number
    MaxBlocks,           \* Maximum blocks per slot
    Stake                \* Stake per validator (simplified)

ASSUME
    /\ ByzantineValidators \subseteq Validators
    /\ Cardinality(ByzantineValidators) <= Cardinality(Validators) \div 5  \* At most 20%
    /\ MaxSlot > 0
    /\ MaxBlocks > 0
    /\ Stake > 0

VARIABLES
    finalizedBlocks,     \* Slot -> Set of finalized blocks
    certificates,        \* Set of certificates issued
    votingHistory,       \* Validator -> sequence of votes
    byzantineActions     \* Set of Byzantine behaviors

safetyVars == <<finalizedBlocks, certificates, votingHistory, byzantineActions>>

----------------------------------------------------------------------------
(* Type Definitions *)

Block == [id: Nat, slot: Nat, hash: Nat, proposer: Validators]
Certificate == [blockId: Nat, validator: Validators, slot: Nat, signature: BOOLEAN]
Vote == [validator: Validators, blockId: Nat, slot: Nat, type: STRING]

----------------------------------------------------------------------------
(* Helper Functions *)

\* Total stake in the system
TotalStake == Cardinality(Validators) * Stake

\* Byzantine stake constraint (≤20%)
ByzantineStakeRatio == 
    (Cardinality(ByzantineValidators) * Stake * 100) \div TotalStake

\* Explicit Byzantine percentage for verification display
ByzantinePercentage == ByzantineStakeRatio

\* Honest validators
HonestValidators == Validators \ ByzantineValidators

\* Check if block has supermajority certificates (>2/3)
HasSupermajority(blockId, slot) ==
    LET blockCerts == {cert \in certificates : cert.blockId = blockId /\ cert.slot = slot}
        signers == {cert.validator : cert \in blockCerts}
        threshold == (2 * Cardinality(Validators)) \div 3 + 1
    IN Cardinality(signers) >= threshold

\* Check if block is finalized
IsFinalized(blockId, slot) ==
    /\ HasSupermajority(blockId, slot)
    /\ \E block \in finalizedBlocks[slot] : block.id = blockId

----------------------------------------------------------------------------
(* Initialization *)

Init ==
    /\ finalizedBlocks = [slot \in 1..MaxSlot |-> {}]
    /\ certificates = {}
    /\ votingHistory = [v \in Validators |-> <<>>]
    /\ byzantineActions = {}

----------------------------------------------------------------------------
(* Actions *)

\* Honest validator issues certificate (no double-signing)
IssueCertificate(validator, blockId, slot) ==
    /\ validator \in HonestValidators
    /\ slot \in 1..MaxSlot
    /\ blockId \in 1..MaxBlocks
    /\ ~\E cert \in certificates : 
         cert.validator = validator /\ cert.slot = slot  \* No double-signing
    /\ LET newCert == [blockId |-> blockId, validator |-> validator, 
                       slot |-> slot, signature |-> TRUE]
       IN certificates' = certificates \cup {newCert}
    /\ UNCHANGED <<finalizedBlocks, votingHistory, byzantineActions>>

\* Byzantine validator double-signs (violates protocol)
ByzantineDoubleSign(validator, blockId1, blockId2, slot) ==
    /\ validator \in ByzantineValidators
    /\ blockId1 # blockId2
    /\ slot \in 1..MaxSlot
    /\ LET cert1 == [blockId |-> blockId1, validator |-> validator, 
                     slot |-> slot, signature |-> TRUE]
           cert2 == [blockId |-> blockId2, validator |-> validator, 
                     slot |-> slot, signature |-> TRUE]
           byzantineAction == [validator |-> validator, action |-> "double_sign", 
                              slot |-> slot, blocks |-> {blockId1, blockId2}]
       IN /\ certificates' = certificates \cup {cert1, cert2}
          /\ byzantineActions' = byzantineActions \cup {byzantineAction}
    /\ UNCHANGED <<finalizedBlocks, votingHistory>>

\* Finalize block when it has supermajority
FinalizeBlock(blockId, slot) ==
    /\ slot \in 1..MaxSlot
    /\ blockId \in 1..MaxBlocks
    /\ HasSupermajority(blockId, slot)
    /\ ~\E block \in finalizedBlocks[slot] : block.id = blockId  \* Not already finalized
    /\ LET newBlock == [id |-> blockId, slot |-> slot, hash |-> blockId, 
                        proposer |-> CHOOSE v \in Validators : TRUE]
       IN finalizedBlocks' = [finalizedBlocks EXCEPT ![slot] = @ \cup {newBlock}]
    /\ UNCHANGED <<certificates, votingHistory, byzantineActions>>

\* Next state relation
Next ==
    \/ \E validator \in Validators, blockId \in 1..MaxBlocks, slot \in 1..MaxSlot :
           IssueCertificate(validator, blockId, slot)
    \/ \E validator \in ByzantineValidators, blockId1, blockId2 \in 1..MaxBlocks, slot \in 1..MaxSlot :
           ByzantineDoubleSign(validator, blockId1, blockId2, slot)
    \/ \E blockId \in 1..MaxBlocks, slot \in 1..MaxSlot :
           FinalizeBlock(blockId, slot)

Spec == Init /\ [][Next]_safetyVars

----------------------------------------------------------------------------
(* SAFETY PROPERTIES - The Three Required Theorems *)

\* PROPERTY 1: No Conflicting Blocks Finalized in Same Slot
NoConflictingFinalization ==
    \A slot \in 1..MaxSlot :
        \A block1, block2 \in finalizedBlocks[slot] :
            block1.id = block2.id  \* Same block ID means same block

\* PROPERTY 2: Chain Consistency Under 20% Byzantine Stake
ChainConsistencyByzantine ==
    /\ ByzantineStakeRatio <= 20  \* At most 20% Byzantine stake
    /\ \A slot \in 1..MaxSlot :
         \A block \in finalizedBlocks[slot] :
           LET blockCerts == {cert \in certificates : cert.blockId = block.id /\ cert.slot = slot}
               honestCerts == {cert \in blockCerts : cert.validator \in HonestValidators}
               honestCount == Cardinality({cert.validator : cert \in honestCerts})
               threshold == (2 * Cardinality(HonestValidators)) \div 3 + 1
           IN honestCount >= threshold  \* Honest supermajority required

\* PROPERTY 3: Certificate Uniqueness and Non-Equivocation
CertificateUniquenessNonEquivocation ==
    \A cert1, cert2 \in certificates :
        /\ cert1.validator = cert2.validator
        /\ cert1.validator \in HonestValidators  \* Only for honest validators
        /\ cert1.slot = cert2.slot
        => cert1.blockId = cert2.blockId  \* Same validator, same slot => same block

----------------------------------------------------------------------------
(* Supporting Invariants *)

\* Type correctness
TypeInvariant ==
    /\ finalizedBlocks \in [1..MaxSlot -> SUBSET Block]
    /\ certificates \in SUBSET Certificate
    /\ votingHistory \in [Validators -> Seq(Vote)]
    /\ byzantineActions \in SUBSET [validator: Validators, action: STRING, 
                                   slot: Nat, blocks: SUBSET Nat]

\* Byzantine constraint maintained
ByzantineConstraint ==
    ByzantineStakeRatio <= 20

\* Honest validators don't double-sign
HonestBehavior ==
    \A validator \in HonestValidators :
        \A slot \in 1..MaxSlot :
            Cardinality({cert \in certificates : 
                        cert.validator = validator /\ cert.slot = slot}) <= 1

\* Finalized blocks have supermajority
FinalizationRequirement ==
    \A slot \in 1..MaxSlot :
        \A block \in finalizedBlocks[slot] :
            HasSupermajority(block.id, slot)

\* Chain consistency achieved under Byzantine conditions
ChainConsistencyAchieved ==
    /\ ByzantineStakeRatio <= 20  \* Testing up to maximum Byzantine threshold
    /\ \A slot \in 1..MaxSlot :
         Cardinality(finalizedBlocks[slot]) <= 1  \* At most one block per slot

\* Byzantine tolerance verification - shows we handle up to 20%
ByzantineFaultTolerance ==
    ByzantineStakeRatio <= 20 => ChainConsistencyByzantine

----------------------------------------------------------------------------
(* Action Constraints for Finite Verification *)

ActionConstraint ==
    /\ \A slot \in 1..MaxSlot : Cardinality(finalizedBlocks[slot]) <= MaxBlocks
    /\ Cardinality(certificates) <= MaxSlot * MaxBlocks * Cardinality(Validators)
    /\ Cardinality(byzantineActions) <= Cardinality(ByzantineValidators) * MaxSlot

=============================================================================
