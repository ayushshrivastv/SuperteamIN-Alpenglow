------------------------------ MODULE Votor ------------------------------
(**************************************************************************)
(* Votor consensus component for the Alpenglow protocol, implementing      *)
(* fast voting-based consensus with 100ms finalization targets.           *)
(**************************************************************************)

EXTENDS Integers, Sequences, FiniteSets, TLC, VRF

CONSTANTS
    Validators,          \* Set of all validators
    ByzantineValidators, \* Set of Byzantine validators
    Stake,               \* Stake distribution
    MaxView,             \* Maximum view number
    MaxSlot,             \* Maximum slot number
    TimeoutDelta,        \* Base timeout duration
    InitialLeader,       \* Initial leader for simplicity
    LeaderWindowSize     \* Size of leader windows (e.g., 4)

INSTANCE Types
INSTANCE Utils

\* Use Utils!Sum for stake calculation to ensure consistency
SumStake(f) == Utils!Sum(f)

----------------------------------------------------------------------------
(* Voting State per Validator *)

VARIABLES
    view,             \* Current view number for each validator
    votedBlocks,      \* Blocks that validators have voted for
    receivedVotes,    \* Votes received by validators
    generatedCerts,   \* Certificates generated after vote aggregation
    finalizedChain,   \* Finalized blockchain
    timeoutExpiry,    \* Timeout expiration times for validators
    skipVotes,        \* Skip votes for timeout handling
    currentTime,      \* Global clock for timestamps (renamed from clock)
    currentLeaderWindow\* Current leader window index (0-based)

votorVars == <<view, votedBlocks, receivedVotes, generatedCerts,
               finalizedChain, timeoutExpiry, skipVotes, currentTime, currentLeaderWindow>>

----------------------------------------------------------------------------
(* Type Invariant *)

TypeInvariant ==
    /\ view \in [Validators -> 1..MaxView]
    /\ votedBlocks \in [Validators -> [1..MaxView -> SUBSET [slot: Nat, view: Nat, hash: Nat, parent: Nat, proposer: Nat, transactions: SUBSET [id: Nat, sender: Nat, data: Seq(Nat), signature: [signer: Nat, message: Nat, valid: BOOLEAN]], timestamp: Nat, signature: [signer: Nat, message: Nat, valid: BOOLEAN], data: Seq(Nat)]]]
    /\ receivedVotes \in [Validators -> [1..MaxView -> SUBSET [voter: Nat, slot: Nat, view: Nat, block: Nat, type: {"proposal", "echo", "commit", "skip"}, signature: [signer: Nat, message: Nat, aggregatable: BOOLEAN], timestamp: Nat]]]
    /\ generatedCerts \in [1..MaxView -> SUBSET [slot: Nat, view: Nat, block: Nat, type: {"fast", "slow", "skip"}, signatures: [signers: SUBSET Nat, message: Nat, signatures: SUBSET [signer: Nat, message: Nat, aggregatable: BOOLEAN], valid: BOOLEAN], validators: SUBSET Nat, stake: Nat]]
    /\ finalizedChain \in Seq([slot: Nat, view: Nat, hash: Nat, parent: Nat, proposer: Nat, transactions: SUBSET [id: Nat, sender: Nat, data: Seq(Nat), signature: [signer: Nat, message: Nat, valid: BOOLEAN]], timestamp: Nat, signature: [signer: Nat, message: Nat, valid: BOOLEAN], data: Seq(Nat)])
    /\ timeoutExpiry \in [Validators -> Nat]
    /\ skipVotes \in [Validators -> [1..MaxView -> SUBSET [voter: Nat, view: Nat, type: {"skip"}, signature: [signer: Nat, message: Nat, aggregatable: BOOLEAN], timestamp: Nat]]]
    /\ currentTime \in Nat
    /\ currentLeaderWindow \in Nat

----------------------------------------------------------------------------
(* Timing Constants and Functions *)

\* Slot timing parameters
TimeoutBase == 100   \* base timeout in milliseconds

\* Adaptive timeout using leader window based exponential backoff
AdaptiveTimeout(vw) ==
    \* Exponential backoff by window: TimeoutBase * 2^(view div LeaderWindowSize)
    TimeoutBase * (2 ^ (vw \div LeaderWindowSize))

\* Calculate timeout duration for a given view (backward-compatible wrapper)
GetTimeoutDuration(vw) ==
    AdaptiveTimeout(vw)

\* Get current slot based on time
GetSlotFromTime(time) ==
    time \div 400 + 1  \* SlotDuration = 400ms

\* Get slot start time
GetSlotStartTime(slot) ==
    (slot - 1) * 400  \* SlotDuration = 400ms

\* Check if within slot window
WithinSlotWindow(time, slot) ==
    /\ time >= GetSlotStartTime(slot)
    /\ time < GetSlotStartTime(slot + 1)

\* Range of a sequence
Range(seq) == {seq[i] : i \in DOMAIN seq}

\* Last element of a sequence
Last(seq) == seq[Len(seq)]

----------------------------------------------------------------------------
(* Type Definitions are used from Types module directly *)

\* Deterministic stake-weighted leader selection helper.
\* Prefer VRF-based selection using the VRF module and leader windows.
ComputeLeaderForView(vw) ==
    LET slot == GetSlotFromTime(currentTime)
    IN VRFComputeLeaderForView(slot, vw, Validators, Stake, LeaderWindowSize)

----------------------------------------------------------------------------
(* Cryptographic functions - use from Types module directly *)

----------------------------------------------------------------------------
(* Helper Functions *)

\* Check if validator is leader for view using VRF+window-based selection
IsLeaderForView(validator, vw) ==
    LET slot == GetSlotFromTime(currentTime)
    IN VRFIsLeaderForView(validator, slot, vw, Validators, Stake, LeaderWindowSize)

\* Validate block structure and parent chain
CheckValidBlock(block, chain) ==
    /\ block.proposer \in Validators
    /\ block.slot \in 1..MaxSlot
    /\ \/ Len(chain) = 0 /\ block.parent = "genesis"
       \/ Len(chain) > 0 /\ block.parent = Last(chain).hash

\* Validate certificate has sufficient stake (strengthened to use actual Stake)
ValidCertificate(cert) ==
    /\ cert.block \in Nat
    /\ cert.slot \in 1..MaxSlot
    /\ cert.view \in 1..MaxView
    /\ cert.type \in {"fast", "slow", "skip"}
    /\ cert.validators \subseteq Validators
    /\ cert.signatures \in [signers: SUBSET Nat, message: Nat, signatures: SUBSET [signer: Nat, message: Nat, aggregatable: BOOLEAN], valid: BOOLEAN]
    /\ cert.stake = SumStake([v \in cert.validators |-> Stake[v]])  \* stake matches validators included
    /\ LET totalStake == SumStake([v \in Validators |-> Stake[v]])
           fastThreshold == (4 * totalStake) \div 5
           slowThreshold == (3 * totalStake) \div 5
       IN IF cert.type = "fast" THEN cert.stake >= fastThreshold
          ELSE IF cert.type = "slow" THEN cert.stake >= slowThreshold
          ELSE cert.stake >= slowThreshold  \* skip requires at least slow threshold
    \* If signatures claim to be valid, ensure signers correspond to validators
    /\ (cert.signatures.valid = TRUE) => cert.signatures.signers = cert.validators
    \* All signers (if present) must be validators
    /\ cert.signatures.signers \subseteq Validators

\* Validate vote message format
ValidateVoteMessage(v, vw, slot, blockHash) ==
    /\ v \in Validators
    /\ vw \in 1..MaxView
    /\ slot \in 1..MaxSlot
    /\ blockHash \in Nat  \* Block hash

\* Validate certificate format (structural checks)
ValidateCertificate(cert) ==
    /\ cert.type \in {"fast", "slow", "skip"}
    /\ cert.stake >= 0
    /\ cert.validators \subseteq Validators
    /\ cert.signatures \in [signers: SUBSET Nat, message: Nat, signatures: SUBSET [signer: Nat, message: Nat, aggregatable: BOOLEAN], valid: BOOLEAN]
    /\ cert.signatures.signers \subseteq Validators

\* Calculate timeout with exponential backoff (compat)
CalculateTimeout(vw) ==
    AdaptiveTimeout(vw)

----------------------------------------------------------------------------
(* Initialization *)

Init ==
    /\ currentTime = 0
    /\ view = [v \in Validators |-> 1]
    /\ votedBlocks = [v \in Validators |-> [vw \in 1..MaxView |-> {}]]
    /\ receivedVotes = [v \in Validators |-> [vw \in 1..MaxView |-> {}]]
    /\ generatedCerts = [vw \in 1..MaxView |-> {}]
    /\ finalizedChain = <<>>
    /\ timeoutExpiry = [v \in Validators |-> currentTime + AdaptiveTimeout(1)]
    /\ skipVotes = [v \in Validators |-> [vw \in 1..MaxView |-> {}]]
    /\ currentLeaderWindow = 0

----------------------------------------------------------------------------
(* State Transitions *)

\* Propose new block for current view
ProposeBlock(v, vw) ==
    /\ vw = view[v]
    /\ v = ComputeLeaderForView(view[v])  \* VRF+window-based leader selection
    /\ LET newBlock == [
                        slot |-> vw,
                        view |-> vw,
                        hash |-> vw,  \* Use vw as hash for simplicity
                        parent |-> IF Len(finalizedChain[v]) = 0 THEN 0
                                  ELSE Last(finalizedChain[v]).hash,
                        proposer |-> v,
                        transactions |-> {},
                        timestamp |-> currentTime,
                        signature |-> [signer |-> v, message |-> vw, valid |-> TRUE],
                        data |-> <<>>]
       IN /\ votedBlocks' = [votedBlocks EXCEPT
                             ![v][vw] = votedBlocks[v][vw] \cup {newBlock}]
          /\ UNCHANGED <<view, receivedVotes, generatedCerts, finalizedChain,
                        timeoutExpiry, skipVotes, currentTime, currentLeaderWindow>>

\* Validator casts vote for a block with validation
CastVote(v, block, vw) ==
    /\ ValidateVoteMessage(v, vw, block.slot, block.hash)
    /\ vw = view[v]
    /\ LET vote == [
                    voter |-> v,
                    slot |-> block.slot,
                    view |-> vw,
                    block |-> block.hash,
                    type |-> "commit",
                    timestamp |-> clock,
                    signature |-> [signer |-> v, message |-> block.hash, valid |-> TRUE]]
       IN /\ receivedVotes' = [receivedVotes EXCEPT
                               ![v][vw] = receivedVotes[v][vw] \cup {vote}]
          /\ votedBlocks' = [votedBlocks EXCEPT
                             ![v][vw] = votedBlocks[v][vw] \cup {block}]
    /\ UNCHANGED <<view, generatedCerts, finalizedChain,
                  timeoutExpiry, skipVotes, clock, currentTime, currentLeaderWindow>>

\* Collect votes and generate certificate
CollectVotes(validator, vw) ==
    /\ vw = view[validator]
    /\ LET votesForView == receivedVotes[validator][vw]
           votedStake == SumStake([v \in {vote.voter : vote \in votesForView} |-> Stake[v]])
           totalStake == SumStake([v \in Validators |-> Stake[v]])
           fastThreshold == (totalStake * 4) \div 5  \* 80% for fast path
           slowThreshold == (totalStake * 3) \div 5  \* 60% for slow path
       IN /\ votedStake >= slowThreshold
          /\ Cardinality(votesForView) > 0
          /\ LET blockHash == (CHOOSE vote \in votesForView : TRUE).block
                 block == CHOOSE b \in UNION {votedBlocks[v][vw] : v \in Validators} :
                          b.hash = blockHash
                 certType == IF votedStake >= fastThreshold THEN "fast" ELSE "slow"
                 signatures == {vote.signature : vote \in votesForView}
                 aggregatedSig == [signers |-> {vote.voter : vote \in votesForView},
                                  message |-> blockHash,
                                  signatures |-> signatures,
                                  valid |-> TRUE]
                 cert == [
                         slot |-> block.slot,
                         view |-> vw,
                         block |-> blockHash,
                         type |-> certType,
                         signatures |-> aggregatedSig,
                         validators |-> {vote.voter : vote \in votesForView},
                         stake |-> votedStake]
             IN generatedCerts' = [generatedCerts EXCEPT
                                  ![vw] = generatedCerts[vw] \cup {cert}]
    /\ UNCHANGED <<view, votedBlocks, receivedVotes, finalizedChain,
                  timeoutExpiry, skipVotes, clock, currentTime, currentLeaderWindow>>

\* Finalize block with certificate
FinalizeBlock(validator, cert) ==
    /\ cert \in generatedCerts[view[validator]]
    /\ cert.type \in {"fast", "slow"}  \* Both fast and slow path finalization
    /\ ~(\E b \in Range(finalizedChain) : b.slot = cert.slot)  \* No duplicate slots
    /\ LET blockToFinalize == CHOOSE b \in votedBlocks[validator][view[validator]] :
                                b.hash = cert.block
       IN finalizedChain' = Append(finalizedChain, blockToFinalize)
    /\ UNCHANGED <<view, votedBlocks, receivedVotes, generatedCerts,
                  timeoutExpiry, skipVotes, currentTime, currentLeaderWindow>>

\* Handle view timeout
Timeout(validator) ==
    /\ currentTime >= timeoutExpiry[validator]
    /\ LET vw == view[validator]
           newView == vw + 1
           newLeaderWindow == (newView - 1) \div LeaderWindowSize
       IN /\ skipVotes' = [skipVotes EXCEPT
                           ![validator][vw] = skipVotes[validator][vw] \cup
                           {[voter |-> validator, slot |-> vw, view |-> vw,
                             block |-> 0, type |-> "skip", timestamp |-> currentTime,
                             signature |-> [signer |-> validator, message |-> vw, valid |-> TRUE]]}]
          /\ view' = [view EXCEPT ![validator] = newView]  \* Move to next view
          /\ timeoutExpiry' = [timeoutExpiry EXCEPT
                               ![validator] = currentTime + AdaptiveTimeout(newView)]
          /\ currentLeaderWindow' = newLeaderWindow
    /\ UNCHANGED <<votedBlocks, receivedVotes, generatedCerts, finalizedChain, currentTime>>

\* Submit skip vote on timeout
SubmitSkipVote(v, vw) ==
    /\ currentTime >= timeoutExpiry[v]
    /\ vw = view[v]
    /\ LET newView == view[v] + 1
           newLeaderWindow == (newView - 1) \div LeaderWindowSize
           skipVote == [
                         voter |-> v,
                         slot |-> vw,
                         view |-> vw,
                         block |-> 0,  \* No block for skip
                         type |-> "skip",
                         timestamp |-> currentTime,
                         signature |-> [signer |-> v, message |-> vw, valid |-> TRUE]
                       ]
       IN skipVotes' = [skipVotes EXCEPT
                        ![v][view[v]] = skipVotes[v][view[v]] \cup {skipVote}]
    /\ view' = [view EXCEPT ![v] = newView]  \* Move to next view
    /\ timeoutExpiry' = [timeoutExpiry EXCEPT
                           ![v] = currentTime + AdaptiveTimeout(newView)]
    /\ currentLeaderWindow' = newLeaderWindow
    /\ UNCHANGED <<votedBlocks, receivedVotes, generatedCerts, finalizedChain, currentTime>>

\* Collect skip votes and advance view when threshold reached
CollectSkipVotes(validator, vw) ==
    /\ vw = view[validator]
    /\ LET skipVotesForView == skipVotes[validator][vw]
           skipVoters == {vote.voter : vote \in skipVotesForView}
           skipStake == SumStake([v \in skipVoters |-> Stake[v]])
           totalStake == SumStake([v \in Validators |-> Stake[v]])
           newView == vw + 1
           newLeaderWindow == (newView - 1) \div LeaderWindowSize
       IN /\ skipStake >= (2 * totalStake) \div 3  \* 2/3+ stake voted to skip
          /\ view' = [view EXCEPT ![validator] = newView]
          /\ timeoutExpiry' = [timeoutExpiry EXCEPT
                               ![validator] = currentTime + AdaptiveTimeout(newView)]
          /\ currentLeaderWindow' = newLeaderWindow
    /\ UNCHANGED <<votedBlocks, receivedVotes, generatedCerts, finalizedChain, skipVotes, clock, currentTime>>

----------------------------------------------------------------------------
(* Byzantine Behaviors *)

\* Byzantine validator double votes for different blocks
\* Improved model: Byzantine may broadcast conflicting votes to any subset
\* of validators. We simulate broadcast to all validators for simplicity.
ByzantineDoubleVote(v, vw) ==
    /\ v \in ByzantineValidators
    /\ vw = view[v]
    /\ \E b1, b2 \in Nat :
        /\ b1 # b2
        /\ LET vote1 == [voter |-> v, slot |-> vw, view |-> vw,
                        block |-> b1, type |-> "commit",
                        timestamp |-> currentTime,
                        signature |-> [signer |-> v, message |-> b1, valid |-> FALSE]]
               vote2 == [voter |-> v, slot |-> vw, view |-> vw,
                        block |-> b2, type |-> "commit",
                        timestamp |-> currentTime,
                        signature |-> [signer |-> v, message |-> b2, valid |-> FALSE]]
               DeliverTo == Validators
           IN receivedVotes' = [rec \in Validators |->
                                  IF rec \in DeliverTo
                                    THEN [receivedVotes[rec] EXCEPT ![vw] = receivedVotes[rec][vw] \cup {vote1, vote2}]
                                    ELSE receivedVotes[rec]]
    /\ UNCHANGED <<view, votedBlocks, generatedCerts, finalizedChain,
                  timeoutExpiry, skipVotes, clock, currentTime, currentLeaderWindow>>

\* Byzantine validator creates invalid certificate
ByzantineInvalidCert(v, vw) ==
    /\ v \in ByzantineValidators
    /\ vw = view[v]
    /\ \E block \in [hash: Nat, slot: 1..MaxSlot] :
        /\ LET fakeValidators == ByzantineValidators
               fakeSignatures == {[signer |-> bv, message |-> block.hash, valid |-> FALSE]
                                 : bv \in fakeValidators}
               fakeAggSig == [signers |-> fakeValidators,
                             message |-> block.hash,
                             signatures |-> fakeSignatures,
                             valid |-> FALSE]
               fakeCert == [slot |-> block.slot,
                           view |-> vw,
                           block |-> block.hash,
                           type |-> "fast",
                           signatures |-> fakeAggSig,
                           validators |-> fakeValidators,
                           stake |-> SumStake([bv \in fakeValidators |-> Stake[bv]])]
           IN generatedCerts' = [generatedCerts EXCEPT
                                ![vw] = generatedCerts[vw] \cup {fakeCert}]
    /\ UNCHANGED <<view, votedBlocks, receivedVotes, finalizedChain,
                  timeoutExpiry, skipVotes, clock, currentTime, currentLeaderWindow>>

\* Byzantine validator withholds votes
ByzantineWithholdVote(v, vw) ==
    /\ v \in ByzantineValidators
    /\ vw = view[v]
    /\ UNCHANGED votorVars  \* Simply do nothing

----------------------------------------------------------------------------
(* Clock advancement *)

AdvanceClock ==
    /\ currentTime' = currentTime + 1
    /\ UNCHANGED <<view, votedBlocks, receivedVotes, generatedCerts,
                  finalizedChain, timeoutExpiry, skipVotes, currentLeaderWindow>>

----------------------------------------------------------------------------
(* Next state relation *)

Next ==
    \/ \E v \in Validators, vw \in 1..MaxView :
        ProposeBlock(v, vw)
    \/ \E v \in Validators, vw \in 1..MaxView :
        \E b \in votedBlocks[v][vw] : CastVote(v, b, vw)
    \/ \E v \in Validators, vw \in 1..MaxView :
        CollectVotes(v, vw)
    \/ \E v \in Validators, cert \in UNION {generatedCerts[vw] : vw \in 1..MaxView} :
        FinalizeBlock(v, cert)
    \/ \E v \in Validators :
        Timeout(v)
    \/ \E v \in Validators, vw \in 1..MaxView :
        SubmitSkipVote(v, vw)
    \/ \E v \in Validators, vw \in 1..MaxView :
        CollectSkipVotes(v, vw)
    \/ \E v \in ByzantineValidators, vw \in 1..MaxView :
        \/ ByzantineDoubleVote(v, vw)
        \/ ByzantineInvalidCert(v, vw)
        \/ ByzantineWithholdVote(v, vw)
    \/ AdvanceClock

----------------------------------------------------------------------------
(* Invariants and Properties *)

\* Safety: No two blocks at same slot
VotorSafety ==
    \A i, j \in DOMAIN finalizedChain :
        finalizedChain[i].slot = finalizedChain[j].slot => i = j

\* Liveness: Chain grows under good conditions
VotorLiveness ==
    <>[](Len(finalizedChain) > 0)

\* Certificate validity
ValidCertificates ==
    \A vw \in 1..MaxView :
        \A cert \in generatedCerts[vw] :
            ValidCertificate(cert)

\* Fast path percentage (property check)
FastPathRate ==
    LET fastCerts == {cert \in UNION {generatedCerts[vw] : vw \in 1..MaxView} :
                      cert.type = "fast"}
        allCerts == UNION {generatedCerts[vw] : vw \in 1..MaxView}
    IN Cardinality(allCerts) > 0 =>
       Cardinality(fastCerts) >= Cardinality(allCerts) \div 2

\* Byzantine resilience
ByzantineResilience ==
    LET byzantineStake == SumStake([v \in ByzantineValidators |-> Stake[v]])
        totalStake == SumStake([v \in Validators |-> Stake[v]])
    IN byzantineStake < totalStake \div 3 => VotorSafety

\* Eventually finalize under good conditions
EventualFinalization ==
    <>[](Cardinality(ByzantineValidators) < Cardinality(Validators) \div 3 =>
        Len(finalizedChain) > 0)

\* View synchronization convergence
ViewConvergence ==
    <>[]\A v1, v2 \in Validators \ ByzantineValidators :
        view[v1] = view[v2]

\* Vote uniqueness invariant: honest validators cast at most one vote per view
HonestVoteUniqueness ==
    \A rec \in Validators, vw \in 1..MaxView :
        \A u \in Validators \ ByzantineValidators :
            Cardinality({vote \in receivedVotes[rec][vw] : vote.voter = u}) <= 1

\* For each honest validator, in their own inbox they have at most one vote by themselves per view
HonestSelfVoteUniqueness ==
    \A u \in Validators \ ByzantineValidators, vw \in 1..MaxView :
        Cardinality({vote \in receivedVotes[u][vw] : vote.voter = u}) <= 1

============================================================================
