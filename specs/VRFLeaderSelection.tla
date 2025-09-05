------------------------------ MODULE VRFLeaderSelection ------------------------------
(**************************************************************************)
(* VRF-based Leader Selection specification for Alpenglow protocol        *)
(* This module implements detailed leader selection using Verifiable      *)
(* Random Functions with 4-slot windows, stake-weighted sampling,         *)
(* and integration with Votor consensus mechanism.                        *)
(**************************************************************************)

EXTENDS Integers, Sequences, FiniteSets, TLC, Types, Utils, Crypto

\* Import VRF base functionality
INSTANCE VRF WITH VRFKeyPairs <- VRFKeyPairs,
                  MaxVRFOutput <- MaxVRFOutput,
                  VRFSeed <- VRFSeed

\* Import Votor for consensus integration
INSTANCE Votor WITH Validators <- Validators,
                    ByzantineValidators <- ByzantineValidators,
                    OfflineValidators <- OfflineValidators,
                    MaxView <- MaxView,
                    MaxSlot <- MaxSlot,
                    GST <- GST,
                    Delta <- Delta

CONSTANTS
    WindowSize,          \* Size of leader windows (4 slots)
    RelayCommitteeSize,  \* Size of relay committee
    MaxWindows,          \* Maximum number of windows to track
    LeaderRotationSeed,  \* Seed for leader rotation within windows
    StakeThreshold       \* Minimum stake threshold for leadership

VARIABLES
    leaderWindows,       \* Leader assignments per window [window -> validator]
    relayCommittees,     \* Relay committees per window [window -> set of validators]
    windowRotations,     \* Rotation schedules within windows [window -> sequence]
    currentWindow,       \* Current active window
    leaderProofs,        \* VRF proofs for leader selection [window -> proof]
    relayProofs,         \* VRF proofs for relay selection [window -> validator -> proof]
    windowTransitions,   \* Window transition history
    leaderChallenges,    \* Challenges to leader selection [window -> set of challenges]
    rotationState        \* Current rotation state within window

leaderSelectionVars == <<leaderWindows, relayCommittees, windowRotations, currentWindow,
                         leaderProofs, relayProofs, windowTransitions, leaderChallenges,
                         rotationState>>

----------------------------------------------------------------------------
(* Window and Slot Management *)

\* Calculate window index from slot
SlotToWindow(slot) == ((slot - 1) \div WindowSize) + 1

\* Calculate slot position within window (0-based)
SlotInWindow(slot) == (slot - 1) % WindowSize

\* Get window start slot
WindowStartSlot(window) == ((window - 1) * WindowSize) + 1

\* Get window end slot
WindowEndSlot(window) == window * WindowSize

\* Check if slot is first in window
IsWindowStart(slot) == SlotInWindow(slot) = 0

\* Check if slot is last in window
IsWindowEnd(slot) == SlotInWindow(slot) = (WindowSize - 1)

\* Get current window from current slot
GetCurrentWindow(slot) == SlotToWindow(slot)

----------------------------------------------------------------------------
(* Stake-Weighted VRF Leader Selection *)

\* Compute stake-weighted VRF value for leader selection
StakeWeightedVRF(validator, window, validators, stakeMap) ==
    IF validator \notin validators \/ stakeMap[validator] < StakeThreshold
    THEN MaxVRFOutput  \* Exclude validators below threshold
    ELSE LET vrfInput == window * 10000 + LeaderRotationSeed
             vrfProof == VRF!VRFGenerateProof(validator, vrfInput)
             stake == stakeMap[validator]
             totalStake == Utils!TotalStake(validators, stakeMap)
             \* Normalize VRF output by stake weight (lower is better)
             weightedValue == IF stake = 0 THEN MaxVRFOutput
                             ELSE (vrfProof.output * totalStake) \div stake
         IN weightedValue

\* Select leader for window using stake-weighted VRF
SelectWindowLeader(window, validators, stakeMap) ==
    IF validators = {} THEN 0
    ELSE LET eligibleValidators == {v \in validators : 
                                     /\ VRF!VRFHasValidKeys(v)
                                     /\ stakeMap[v] >= StakeThreshold
                                     /\ v \notin ByzantineValidators}
             weightedValues == [v \in eligibleValidators |-> 
                               StakeWeightedVRF(v, window, validators, stakeMap)]
             minWeight == IF eligibleValidators = {} THEN MaxVRFOutput
                         ELSE Min({weightedValues[v] : v \in eligibleValidators})
             winners == {v \in eligibleValidators : weightedValues[v] = minWeight}
         IN IF winners = {} THEN 0
            ELSE CHOOSE v \in winners : TRUE  \* Deterministic choice

\* Verify leader selection for window
VerifyWindowLeader(window, leader, validators, stakeMap) ==
    /\ leader \in validators
    /\ VRF!VRFHasValidKeys(leader)
    /\ stakeMap[leader] >= StakeThreshold
    /\ leader \notin ByzantineValidators
    /\ LET expectedLeader == SelectWindowLeader(window, validators, stakeMap)
       IN expectedLeader = leader

\* Generate VRF proof for leader selection
GenerateLeaderProof(validator, window) ==
    IF VRF!VRFHasValidKeys(validator)
    THEN LET vrfInput == window * 10000 + LeaderRotationSeed
             proof == VRF!VRFGenerateProof(validator, vrfInput)
         IN [window |-> window,
             validator |-> validator,
             input |-> vrfInput,
             output |-> proof.output,
             proof |-> proof.proof,
             publicKey |-> proof.publicKey,
             timestamp |-> clock,
             valid |-> proof.valid]
    ELSE [window |-> window,
          validator |-> validator,
          input |-> 0,
          output |-> 0,
          proof |-> 0,
          publicKey |-> 0,
          timestamp |-> clock,
          valid |-> FALSE]

\* Verify leader proof
VerifyLeaderProof(leaderProof, validators, stakeMap) ==
    /\ leaderProof.valid
    /\ leaderProof.validator \in validators
    /\ VRF!VRFHasValidKeys(leaderProof.validator)
    /\ VRF!VRFVerifyValidatorProof(leaderProof.validator, leaderProof)
    /\ stakeMap[leaderProof.validator] >= StakeThreshold

----------------------------------------------------------------------------
(* Relay Committee Selection *)

\* Select relay committee using VRF-based sampling
SelectRelayCommittee(window, validators, stakeMap, committeeSize) ==
    IF validators = {} \/ committeeSize = 0 THEN {}
    ELSE LET eligibleValidators == {v \in validators : 
                                     /\ VRF!VRFHasValidKeys(v)
                                     /\ stakeMap[v] >= StakeThreshold
                                     /\ v \notin ByzantineValidators}
             totalStake == Utils!TotalStake(eligibleValidators, stakeMap)
             \* Select committee members iteratively
             SelectMember(index, excluded) ==
                 IF eligibleValidators \ excluded = {} THEN 0
                 ELSE LET candidates == eligibleValidators \ excluded
                          vrfInput == window * 10000 + index * 100 + LeaderRotationSeed
                          vrfValues == [v \in candidates |-> 
                                       LET proof == VRF!VRFGenerateProof(v, vrfInput)
                                           stake == stakeMap[v]
                                       IN IF stake = 0 THEN MaxVRFOutput
                                          ELSE (proof.output * totalStake) \div stake]
                          minValue == Min({vrfValues[v] : v \in candidates})
                          winners == {v \in candidates : vrfValues[v] = minValue}
                      IN CHOOSE v \in winners : TRUE
             \* Recursively build committee
             BuildCommittee(size, excluded, committee) ==
                 IF size = 0 \/ Cardinality(eligibleValidators \ excluded) = 0
                 THEN committee
                 ELSE LET member == SelectMember(Cardinality(committee) + 1, excluded)
                      IN IF member = 0 THEN committee
                         ELSE BuildCommittee(size - 1, excluded \cup {member}, committee \cup {member})
         IN BuildCommittee(committeeSize, {}, {})

\* Generate relay proofs for committee selection
GenerateRelayProofs(window, validators, stakeMap, committeeSize) ==
    LET committee == SelectRelayCommittee(window, validators, stakeMap, committeeSize)
    IN [v \in committee |-> 
        LET vrfInput == window * 10000 + 1 * 100 + LeaderRotationSeed  \* Use index 1 for simplicity
            proof == VRF!VRFGenerateProof(v, vrfInput)
        IN [window |-> window,
            validator |-> v,
            input |-> vrfInput,
            output |-> proof.output,
            proof |-> proof.proof,
            publicKey |-> proof.publicKey,
            role |-> "relay",
            timestamp |-> clock,
            valid |-> proof.valid]]

\* Verify relay committee selection
VerifyRelayCommittee(window, committee, validators, stakeMap, committeeSize) ==
    /\ Cardinality(committee) <= committeeSize
    /\ committee \subseteq validators
    /\ \A v \in committee : 
        /\ VRF!VRFHasValidKeys(v)
        /\ stakeMap[v] >= StakeThreshold
        /\ v \notin ByzantineValidators
    /\ LET expectedCommittee == SelectRelayCommittee(window, validators, stakeMap, committeeSize)
       IN committee = expectedCommittee

----------------------------------------------------------------------------
(* Leader Rotation Within Windows *)

\* Generate rotation sequence for window
GenerateWindowRotation(window, leader, validators, stakeMap) ==
    IF leader = 0 \/ leader \notin validators THEN <<>>
    ELSE LET eligibleValidators == {v \in validators : 
                                     /\ VRF!VRFHasValidKeys(v)
                                     /\ stakeMap[v] >= StakeThreshold
                                     /\ v \notin ByzantineValidators}
             validatorList == CHOOSE seq \in Seq(eligibleValidators) :
                               /\ Len(seq) = Cardinality(eligibleValidators)
                               /\ \A v \in eligibleValidators : \E i \in DOMAIN seq : seq[i] = v
                               /\ \A i, j \in DOMAIN seq : i # j => seq[i] # seq[j]
             leaderIndex == CHOOSE i \in DOMAIN validatorList : validatorList[i] = leader
             \* Create rotation starting from leader
             rotationSeq == [slot \in 1..WindowSize |->
                            LET rotationIndex == ((leaderIndex - 1 + slot - 1) % Cardinality(eligibleValidators)) + 1
                            IN validatorList[rotationIndex]]
         IN rotationSeq

\* Get leader for specific slot within window
GetSlotLeader(slot, window, rotation) ==
    IF window \notin DOMAIN leaderWindows \/ leaderWindows[window] = 0
    THEN 0
    ELSE LET slotInWindow == SlotInWindow(slot) + 1  \* 1-based indexing
         IN IF slotInWindow \in DOMAIN rotation
            THEN rotation[slotInWindow]
            ELSE leaderWindows[window]  \* Fallback to window leader

\* Verify slot leader assignment
VerifySlotLeader(slot, leader, validators, stakeMap) ==
    LET window == SlotToWindow(slot)
        expectedRotation == IF window \in DOMAIN windowRotations
                           THEN windowRotations[window]
                           ELSE <<>>
        expectedLeader == GetSlotLeader(slot, window, expectedRotation)
    IN expectedLeader = leader

\* Update rotation state for view changes
UpdateRotationState(window, view, leader) ==
    LET baseRotation == IF window \in DOMAIN windowRotations
                       THEN windowRotations[window]
                       ELSE <<>>
        viewOffset == (view - 1) % WindowSize
        adjustedRotation == IF baseRotation = <<>> THEN <<>>
                           ELSE [slot \in DOMAIN baseRotation |->
                                LET newIndex == ((slot - 1 + viewOffset) % Len(baseRotation)) + 1
                                IN baseRotation[newIndex]]
    IN adjustedRotation

----------------------------------------------------------------------------
(* Window Transition Management *)

\* Initialize new window
InitializeWindow(window, validators, stakeMap) ==
    /\ window \notin DOMAIN leaderWindows
    /\ LET leader == SelectWindowLeader(window, validators, stakeMap)
           committee == SelectRelayCommittee(window, validators, stakeMap, RelayCommitteeSize)
           rotation == GenerateWindowRotation(window, leader, validators, stakeMap)
           leaderProof == GenerateLeaderProof(leader, window)
           relayProofs == GenerateRelayProofs(window, validators, stakeMap, RelayCommitteeSize)
       IN /\ leaderWindows' = leaderWindows @@ (window :> leader)
          /\ relayCommittees' = relayCommittees @@ (window :> committee)
          /\ windowRotations' = windowRotations @@ (window :> rotation)
          /\ leaderProofs' = leaderProofs @@ (window :> leaderProof)
          /\ relayProofs' = relayProofs @@ (window :> relayProofs)
          /\ windowTransitions' = windowTransitions \cup {[window |-> window,
                                                          leader |-> leader,
                                                          committee |-> committee,
                                                          timestamp |-> clock]}
    /\ UNCHANGED <<currentWindow, leaderChallenges, rotationState>>

\* Transition to next window
TransitionWindow(newWindow, validators, stakeMap) ==
    /\ newWindow = currentWindow + 1
    /\ newWindow <= MaxWindows
    /\ InitializeWindow(newWindow, validators, stakeMap)
    /\ currentWindow' = newWindow
    /\ UNCHANGED <<leaderChallenges, rotationState>>

\* Handle window overlap for smooth transitions
HandleWindowOverlap(slot, validators, stakeMap) ==
    LET window == SlotToWindow(slot)
        nextWindow == window + 1
    IN /\ IsWindowEnd(slot)  \* Last slot of window
       /\ nextWindow <= MaxWindows
       /\ nextWindow \notin DOMAIN leaderWindows
       /\ InitializeWindow(nextWindow, validators, stakeMap)
       /\ UNCHANGED <<currentWindow, leaderChallenges, rotationState>>

----------------------------------------------------------------------------
(* Challenge and Verification Mechanisms *)

\* Challenge leader selection
ChallengeLeaderSelection(challenger, window, reason, evidence) ==
    /\ challenger \in Validators
    /\ challenger \notin ByzantineValidators
    /\ window \in DOMAIN leaderWindows
    /\ window \notin DOMAIN leaderChallenges \/ 
       ~\E c \in leaderChallenges[window] : c.challenger = challenger
    /\ LET challenge == [challenger |-> challenger,
                        window |-> window,
                        reason |-> reason,
                        evidence |-> evidence,
                        timestamp |-> clock]
       IN leaderChallenges' = IF window \in DOMAIN leaderChallenges
                             THEN [leaderChallenges EXCEPT ![window] = leaderChallenges[window] \cup {challenge}]
                             ELSE leaderChallenges @@ (window :> {challenge})
    /\ UNCHANGED <<leaderWindows, relayCommittees, windowRotations, currentWindow,
                   leaderProofs, relayProofs, windowTransitions, rotationState>>

\* Resolve challenge by verification
ResolveChallengeByVerification(window, validators, stakeMap) ==
    /\ window \in DOMAIN leaderChallenges
    /\ window \in DOMAIN leaderWindows
    /\ window \in DOMAIN leaderProofs
    /\ LET leader == leaderWindows[window]
           proof == leaderProofs[window]
           isValid == VerifyLeaderProof(proof, validators, stakeMap)
           expectedLeader == SelectWindowLeader(window, validators, stakeMap)
       IN /\ isValid
          /\ leader = expectedLeader
          /\ leaderChallenges' = [leaderChallenges EXCEPT ![window] = {}]
    /\ UNCHANGED <<leaderWindows, relayCommittees, windowRotations, currentWindow,
                   leaderProofs, relayProofs, windowTransitions, rotationState>>

\* Reselect leader if challenge is valid
ReselectLeaderAfterChallenge(window, validators, stakeMap) ==
    /\ window \in DOMAIN leaderChallenges
    /\ window \in DOMAIN leaderWindows
    /\ LET currentLeader == leaderWindows[window]
           expectedLeader == SelectWindowLeader(window, validators, stakeMap)
       IN /\ currentLeader # expectedLeader  \* Challenge is valid
          /\ leaderWindows' = [leaderWindows EXCEPT ![window] = expectedLeader]
          /\ LET newRotation == GenerateWindowRotation(window, expectedLeader, validators, stakeMap)
                 newProof == GenerateLeaderProof(expectedLeader, window)
             IN /\ windowRotations' = [windowRotations EXCEPT ![window] = newRotation]
                /\ leaderProofs' = [leaderProofs EXCEPT ![window] = newProof]
          /\ leaderChallenges' = [leaderChallenges EXCEPT ![window] = {}]
    /\ UNCHANGED <<relayCommittees, currentWindow, relayProofs, windowTransitions, rotationState>>

----------------------------------------------------------------------------
(* Integration with Votor Consensus *)

\* Check if validator can propose block in current view
CanProposeBlock(validator, slot, view, validators, stakeMap) ==
    LET window == SlotToWindow(slot)
        rotation == IF window \in DOMAIN windowRotations
                   THEN windowRotations[window]
                   ELSE <<>>
        viewRotation == UpdateRotationState(window, view, leaderWindows[window])
        slotLeader == GetSlotLeader(slot, window, viewRotation)
    IN /\ validator = slotLeader
       /\ validator \in validators
       /\ validator \notin ByzantineValidators
       /\ VRF!VRFHasValidKeys(validator)

\* Verify block proposer using VRF leader selection
VerifyBlockProposer(block, validators, stakeMap) ==
    CanProposeBlock(block.proposer, block.slot, block.view, validators, stakeMap)

\* Get relay committee for block validation
GetBlockRelayCommittee(slot, validators, stakeMap) ==
    LET window == SlotToWindow(slot)
    IN IF window \in DOMAIN relayCommittees
       THEN relayCommittees[window]
       ELSE SelectRelayCommittee(window, validators, stakeMap, RelayCommitteeSize)

\* Check if validator is in relay committee
IsRelayValidator(validator, slot, validators, stakeMap) ==
    LET committee == GetBlockRelayCommittee(slot, validators, stakeMap)
    IN validator \in committee

\* Generate committee vote using VRF-selected relays
GenerateCommitteeVote(slot, block, validators, stakeMap) ==
    LET committee == GetBlockRelayCommittee(slot, validators, stakeMap)
        votes == {[voter |-> v,
                  slot |-> slot,
                  block_hash |-> block.hash,
                  validator_id |-> v,
                  signature |-> Types!SignMessage(v, block.hash),
                  timestamp |-> clock] : v \in committee}
    IN votes

\* Verify committee vote threshold
VerifyCommitteeVoteThreshold(votes, slot, validators, stakeMap, threshold) ==
    LET committee == GetBlockRelayCommittee(slot, validators, stakeMap)
        validVotes == {vote \in votes : vote.voter \in committee}
        voteStake == Utils!TotalStake({vote.voter : vote \in validVotes}, stakeMap)
        totalStake == Utils!TotalStake(validators, stakeMap)
    IN voteStake * 100 >= threshold * totalStake

----------------------------------------------------------------------------
(* Initialization *)

Init ==
    /\ leaderWindows = [window \in {} |-> 0]
    /\ relayCommittees = [window \in {} |-> {}]
    /\ windowRotations = [window \in {} |-> <<>>]
    /\ currentWindow = 1
    /\ leaderProofs = [window \in {} |-> []]
    /\ relayProofs = [window \in {} |-> [validator \in {} |-> []]]
    /\ windowTransitions = {}
    /\ leaderChallenges = [window \in {} |-> {}]
    /\ rotationState = [window \in {} |-> [view \in {} |-> <<>>]]

----------------------------------------------------------------------------
(* Next State Actions *)

Next ==
    \/ \E window \in 1..MaxWindows, validators \in SUBSET Validators, stakeMap \in [Validators -> Nat] :
        InitializeWindow(window, validators, stakeMap)
    \/ \E newWindow \in 1..MaxWindows, validators \in SUBSET Validators, stakeMap \in [Validators -> Nat] :
        TransitionWindow(newWindow, validators, stakeMap)
    \/ \E slot \in 1..MaxSlot, validators \in SUBSET Validators, stakeMap \in [Validators -> Nat] :
        HandleWindowOverlap(slot, validators, stakeMap)
    \/ \E challenger \in Validators, window \in 1..MaxWindows, reason \in STRING, evidence \in STRING :
        ChallengeLeaderSelection(challenger, window, reason, evidence)
    \/ \E window \in 1..MaxWindows, validators \in SUBSET Validators, stakeMap \in [Validators -> Nat] :
        ResolveChallengeByVerification(window, validators, stakeMap)
    \/ \E window \in 1..MaxWindows, validators \in SUBSET Validators, stakeMap \in [Validators -> Nat] :
        ReselectLeaderAfterChallenge(window, validators, stakeMap)

----------------------------------------------------------------------------
(* Type Invariants *)

TypeInvariant ==
    /\ leaderWindows \in [1..MaxWindows -> Validators \cup {0}]
    /\ relayCommittees \in [1..MaxWindows -> SUBSET Validators]
    /\ windowRotations \in [1..MaxWindows -> Seq(Validators)]
    /\ currentWindow \in 1..MaxWindows
    /\ leaderProofs \in [1..MaxWindows -> UNION {VRF!VRFProof, []}]
    /\ relayProofs \in [1..MaxWindows -> [Validators -> UNION {VRF!VRFProof, []}]]
    /\ windowTransitions \subseteq [window: 1..MaxWindows, leader: Validators, 
                                   committee: SUBSET Validators, timestamp: Nat]
    /\ leaderChallenges \in [1..MaxWindows -> SUBSET [challenger: Validators, window: 1..MaxWindows,
                                                     reason: STRING, evidence: STRING, timestamp: Nat]]
    /\ rotationState \in [1..MaxWindows -> [1..MaxView -> Seq(Validators)]]

----------------------------------------------------------------------------
(* Safety Properties *)

\* Leader selection is deterministic
LeaderSelectionDeterministic ==
    \A window \in DOMAIN leaderWindows :
        \A validators \in SUBSET Validators, stakeMap \in [Validators -> Nat] :
            leaderWindows[window] = SelectWindowLeader(window, validators, stakeMap)

\* Only eligible validators can be leaders
LeaderEligibility ==
    \A window \in DOMAIN leaderWindows :
        LET leader == leaderWindows[window]
        IN leader # 0 =>
            /\ leader \in Validators
            /\ leader \notin ByzantineValidators
            /\ VRF!VRFHasValidKeys(leader)

\* Relay committees contain only eligible validators
RelayCommitteeEligibility ==
    \A window \in DOMAIN relayCommittees :
        \A validator \in relayCommittees[window] :
            /\ validator \in Validators
            /\ validator \notin ByzantineValidators
            /\ VRF!VRFHasValidKeys(validator)

\* Window rotations are consistent with leaders
RotationConsistency ==
    \A window \in DOMAIN windowRotations :
        window \in DOMAIN leaderWindows =>
            LET rotation == windowRotations[window]
                leader == leaderWindows[window]
            IN rotation # <<>> => rotation[1] = leader

\* VRF proofs are valid
VRFProofValidity ==
    /\ \A window \in DOMAIN leaderProofs :
        leaderProofs[window] # [] => leaderProofs[window].valid
    /\ \A window \in DOMAIN relayProofs :
        \A validator \in DOMAIN relayProofs[window] :
            relayProofs[window][validator] # [] => relayProofs[window][validator].valid

\* No conflicting leaders in same window
NoConflictingLeaders ==
    \A window \in DOMAIN leaderWindows :
        \A transition1, transition2 \in windowTransitions :
            /\ transition1.window = window
            /\ transition2.window = window
            => transition1.leader = transition2.leader

----------------------------------------------------------------------------
(* Liveness Properties *)

\* Eventually all windows have leaders
EventualLeaderSelection ==
    \A window \in 1..MaxWindows :
        <>(window \in DOMAIN leaderWindows /\ leaderWindows[window] # 0)

\* Progress through windows
WindowProgress ==
    <>(\A window \in 1..Min({MaxWindows, 10}) : window \in DOMAIN leaderWindows)

\* Challenges are eventually resolved
ChallengeResolution ==
    \A window \in 1..MaxWindows :
        (window \in DOMAIN leaderChallenges /\ leaderChallenges[window] # {}) =>
            <>(leaderChallenges[window] = {})

----------------------------------------------------------------------------
(* Byzantine Resilience Properties *)

\* Byzantine validators cannot control leader selection
ByzantineResistantLeaderSelection ==
    \A window \in DOMAIN leaderWindows :
        leaderWindows[window] \notin ByzantineValidators

\* Byzantine validators cannot dominate relay committees
ByzantineResistantRelaySelection ==
    \A window \in DOMAIN relayCommittees :
        LET byzantineInCommittee == relayCommittees[window] \cap ByzantineValidators
            totalCommittee == Cardinality(relayCommittees[window])
        IN totalCommittee > 0 => Cardinality(byzantineInCommittee) * 3 < totalCommittee

\* VRF unpredictability prevents manipulation
VRFUnpredictabilityProperty ==
    \A window1, window2 \in 1..MaxWindows :
        /\ window1 # window2
        /\ window1 \in DOMAIN leaderWindows
        /\ window2 \in DOMAIN leaderWindows
        => leaderWindows[window1] # leaderWindows[window2] \/ 
           \E validator \in Validators : 
               StakeWeightedVRF(validator, window1, Validators, Types!Stake) #
               StakeWeightedVRF(validator, window2, Validators, Types!Stake)

----------------------------------------------------------------------------
(* Integration Properties *)

\* Leader selection integrates with Votor consensus
VotorIntegration ==
    \A slot \in 1..MaxSlot, view \in 1..MaxView :
        \A validator \in Validators :
            CanProposeBlock(validator, slot, view, Validators, Types!Stake) =>
                \E window \in DOMAIN leaderWindows :
                    /\ window = SlotToWindow(slot)
                    /\ validator \in {leaderWindows[window]} \cup 
                       (IF window \in DOMAIN relayCommittees 
                        THEN relayCommittees[window] 
                        ELSE {})

\* Relay committees support consensus voting
RelayVotingSupport ==
    \A slot \in 1..MaxSlot :
        \A validators \in SUBSET Validators, stakeMap \in [Validators -> Nat] :
            LET committee == GetBlockRelayCommittee(slot, validators, stakeMap)
                committeeStake == Utils!TotalStake(committee, stakeMap)
                totalStake == Utils!TotalStake(validators, stakeMap)
            IN committee # {} => committeeStake * 5 >= totalStake  \* At least 20% stake

----------------------------------------------------------------------------
(* Specification *)

Spec == Init /\ [][Next]_leaderSelectionVars

\* Complete safety properties
SafetyProperties ==
    /\ TypeInvariant
    /\ LeaderSelectionDeterministic
    /\ LeaderEligibility
    /\ RelayCommitteeEligibility
    /\ RotationConsistency
    /\ VRFProofValidity
    /\ NoConflictingLeaders
    /\ ByzantineResistantLeaderSelection
    /\ ByzantineResistantRelaySelection

\* Complete liveness properties
LivenessProperties ==
    /\ EventualLeaderSelection
    /\ WindowProgress
    /\ ChallengeResolution

\* Integration properties
IntegrationProperties ==
    /\ VotorIntegration
    /\ RelayVotingSupport
    /\ VRFUnpredictabilityProperty

============================================================================