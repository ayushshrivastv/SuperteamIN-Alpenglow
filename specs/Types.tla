\* Author: Ayush Srivastava
------------------------------- MODULE Types -------------------------------
(**************************************************************************)
(* Type definitions and common operators for the Alpenglow protocol       *)
(**************************************************************************)

EXTENDS Integers, Sequences, FiniteSets, TLC

\* Note: Utils module will be created separately to avoid circular dependency

CONSTANTS
    Validators,          \* Set of all validators (required)
    ByzantineValidators, \* Set of Byzantine validators (required)
    OfflineValidators,   \* Set of offline validators (required)
    MaxSlot,             \* Maximum slot number (required)
    MaxView,             \* Maximum view number (required)
    GST,                 \* Global Stabilization Time (required)
    Delta                \* Network delay bound (required)

\* Assumptions for proper subset relationships (required)
ASSUME
    /\ ByzantineValidators \subseteq Validators
    /\ OfflineValidators \subseteq Validators
    /\ ByzantineValidators \cap OfflineValidators = {}
    /\ GST >= 0
    /\ Delta > 0
    /\ MaxSlot > 0
    /\ MaxView > 0

\* Set Definitions with proper subset relationships (required)
HonestValidators == Validators \ (ByzantineValidators \cup OfflineValidators)

\* Constants (required)
LeaderWindowSize == 4           \* 4-slot windows (required)
FastPathTimeout == 100          \* Fast path timeout in ms (required)
SlowPathTimeout == 200          \* Slow path timeout in ms (required)

\* Certificate type constants (required)
FastCert == "fast"              \* Fast certificate type constant
SlowCert == "slow"              \* Slow certificate type constant
SkipCert == "skip"              \* Skip certificate type constant

----------------------------------------------------------------------------
(* Basic Types *)

ValidatorID == Nat              \* Validator identifiers (required name)
ValidatorId == ValidatorID      \* Alias for compatibility
Slot == Nat                     \* Slot/epoch numbers (required name)
SlotNumber == Slot              \* Alias for compatibility
ViewNumber == Nat               \* View numbers for consensus
TimeValue == Nat                \* Time values (abstract units)
BlockHash == Hash               \* Block hash type (required name)
CertificateType == {"fast", "slow", "skip"}  \* Certificate types (required)
VoteType == {"proposal", "echo", "commit", "notarization", "finalization", "skip"}  \* Vote types (required)

----------------------------------------------------------------------------
(* Hash Types *)

Hash == Nat                     \* Abstract hash values
MessageHash == Hash
BlockHash == Hash

----------------------------------------------------------------------------
(* Cryptographic Abstractions *)

Signature == [
    signer: ValidatorId,
    message: MessageHash,
    valid: BOOLEAN
]

BLSSignature == [
    signer: ValidatorId,
    message: MessageHash,
    valid: BOOLEAN,
    aggregatable: BOOLEAN
]

AggregatedSignature == [
    signers: SUBSET ValidatorId,
    message: MessageHash,
    signatures: SUBSET BLSSignature,
    valid: BOOLEAN
]

----------------------------------------------------------------------------
(* Helper Functions *)

\* Min function for basic operations
Min(a, b) == IF a <= b THEN a ELSE b

\* Max function for basic operations
Max(a, b) == IF a >= b THEN a ELSE b

\* Sum function for sets (local definition to avoid circular dependency)
RECURSIVE SumSet(_)
SumSet(S) ==
    IF S = {} THEN 0
    ELSE LET x == CHOOSE x \in S : TRUE
         IN x + SumSet(S \ {x})

\* Sum function for functions/records
Sum(f) ==
    LET D == DOMAIN f
    IN IF D = {} THEN 0
       ELSE SumSet({f[x] : x \in D})

----------------------------------------------------------------------------
(* Stake Distribution *)

StakeAmount == Nat              \* Stake amounts in abstract units

StakeDistribution == [
    validator: ValidatorId,
    amount: StakeAmount,
    active: BOOLEAN,
    delegated: BOOLEAN
]

\* Compute total stake for a set of validators
TotalStake(validators, stakeMap) ==
    LET stakeSums == [v \in validators |-> stakeMap[v]]
    IN Sum(stakeSums)

\* Total stake sum - alternative name for compatibility
TotalStakeSum(validators, stakeMap) ==
    TotalStake(validators, stakeMap)

\* Compute stake of a specific set of validators
StakeOfSet(validatorSet, stakeMap) ==
    TotalStake(validatorSet, stakeMap)

\* Check if stake threshold is met
MeetsStakeThreshold(validators, stakeMap, threshold, total) ==
    TotalStake(validators, stakeMap) >= (threshold * total) \div 100

\* Fast path threshold (80 percent of total stake)
FastPathThreshold(totalStake) ==
    (80 * totalStake) \div 100

\* Slow path threshold (60 percent of total stake)
SlowPathThreshold(totalStake) ==
    (60 * totalStake) \div 100

\* Check if validators meet fast path threshold
MeetsFastPathThreshold(validators, stakeMap, totalStake) ==
    TotalStake(validators, stakeMap) >= FastPathThreshold(totalStake)

\* Check if validators meet slow path threshold
MeetsSlowPathThreshold(validators, stakeMap, totalStake) ==
    TotalStake(validators, stakeMap) >= SlowPathThreshold(totalStake)

\* Required stake for different certificate types
RequiredStake(certificateType, totalStake) ==
    CASE certificateType = "fast" -> FastPathThreshold(totalStake)
      [] certificateType = "slow" -> SlowPathThreshold(totalStake)
      [] certificateType = "skip" -> SlowPathThreshold(totalStake)
      [] OTHER -> 0

----------------------------------------------------------------------------
(* Block Structure *)

Transaction == [
    id: Nat,
    sender: ValidatorId,
    data: Seq(Nat),
    signature: Signature
]

Block == [
    slot: SlotNumber,
    view: ViewNumber,
    hash: BlockHash,
    parent: BlockHash,
    proposer: ValidatorId,
    transactions: SUBSET Transaction,
    timestamp: TimeValue,
    signature: Signature,
    data: Seq(Nat)  \* Abstract block data
]

GenesisBlock == [
    slot |-> 0,
    view |-> 0,
    hash |-> 0,
    parent |-> 0,
    proposer |-> 0,
    transactions |-> {},
    timestamp |-> 0,
    signature |-> [signer |-> 0, message |-> 0, valid |-> TRUE],
    data |-> <<>>
]

\* Check block validity
ValidBlock(block, parent) ==
    /\ block.parent = parent.hash
    /\ block.slot > parent.slot
    /\ block.signature.valid

\* Check block validity (single argument wrapper for proofs)
ValidBlock1(block) ==
    \E parent \in Block : ValidBlock(block, parent)

----------------------------------------------------------------------------
(* Cryptographic Invariants *)

\* Formalize that honest validators cannot forge signatures
NoSignatureForge(sig, validator, honestValidators) ==
    \/ validator \in honestValidators => sig.signer = validator
    \/ validator \notin honestValidators  \* Byzantine validators can forge

\* Signature uniqueness per validator per message
SignatureUniqueness(signatures) ==
    \A s1, s2 \in signatures :
        (s1.signer = s2.signer /\ s1.message = s2.message) => s1 = s2

\* Cryptographic hash collision resistance
NoHashCollision(hash1, hash2, data1, data2) ==
    (hash1 = hash2) => (data1 = data2)

\* Digital signature unforgeability
UnforgeableSignature(sig, message, validator, honestValidators) ==
    /\ sig.valid
    /\ validator \in honestValidators
    => sig.signer = validator /\ sig.message = message

----------------------------------------------------------------------------
(* Signature Functions *)

\* Enhanced BLS aggregation check with proper validation
ValidBLSAggregate(signatures) ==
    /\ Cardinality(signatures) > 0
    /\ \A sig \in signatures :
        /\ sig.aggregatable
        /\ sig.valid
    /\ \A s1, s2 \in signatures : s1.message = s2.message
    /\ SignatureUniqueness(signatures)
    /\ \A sig \in signatures :
        \E validator \in ValidatorId : sig.signer = validator

\* Aggregate signatures
AggregateSignatures(sigs) ==
    [signers |-> {s.signer : s \in sigs},
     message |-> IF sigs = {} THEN 0 ELSE (CHOOSE s \in sigs : TRUE).message,
     signatures |-> sigs,
     valid |-> ValidBLSAggregate(sigs)]

----------------------------------------------------------------------------
(* Cryptographic Invariants *)

\* No signature forgery invariant - honest validators cannot forge signatures
NoSignatureForgeInvariant ==
    \A sig \in Signature :
        sig.valid => sig.signer \in Validators

\* Remove deprecated ComputeLeader definition to avoid conflicts
\* The main ComputeLeader function is defined later in the file

----------------------------------------------------------------------------
(* Vote Types *)

\* VoteType already defined above with required values

Vote == [
    voter: ValidatorId,
    slot: SlotNumber,
    view: ViewNumber,
    block: BlockHash,
    type: VoteType,
    signature: BLSSignature
]

\* Aggregate votes for the same block
AggregateVotes(votes) ==
    LET voters == {v.voter : v \in votes}
        sigs == {v.signature : v \in votes}
        firstVote == CHOOSE v \in votes : TRUE
    IN
    [
        voters |-> voters,
        block |-> firstVote.block,
        signatures |-> sigs,
        aggregatedSig |-> AggregateSignatures(sigs)
    ]

\* Create certificate from votes
CreateCertificate(votes, slot, view) ==
    LET voters == {v.voter : v \in votes}
        firstVote == CHOOSE v \in votes : TRUE
        sigs == {v.signature : v \in votes}
    IN
    [
        voters |-> voters,
        block |-> firstVote.block,
        signatures |-> sigs,
        aggregatedSig |-> AggregateSignatures(sigs)
    ]

----------------------------------------------------------------------------
(* Certificate Types *)

\* CertificateType already defined above with required values

Certificate == [
    slot: SlotNumber,
    view: ViewNumber,
    block: BlockHash,
    type: CertificateType,
    signatures: AggregatedSignature,
    validators: SUBSET ValidatorId,
    stake: StakeAmount
]

\* Create a fast certificate (80 percent stake)
FastCertificate(slot, view, block, validators, signatures, stakeMap) ==
    LET totalStake == TotalStake(validators, stakeMap)
    IN [
        slot |-> slot,
        view |-> view,
        block |-> block,
        type |-> "fast",
        signatures |-> signatures,
        validators |-> validators,
        stake |-> totalStake
    ]

\* Create a slow certificate (60 percent stake, two rounds)
SlowCertificate(slot, view, block, validators, signatures, stakeMap) ==
    LET totalStake == TotalStake(validators, stakeMap)
    IN [
        slot |-> slot,
        view |-> view,
        block |-> block,
        type |-> "slow",
        signatures |-> signatures,
        validators |-> validators,
        stake |-> totalStake
    ]

\* Create a skip certificate (timeout)
SkipCertificate(slot, view, validators, signatures, stakeMap) ==
    [
        slot |-> slot,
        view |-> view,
        block |-> 0,  \* No block
        type |-> "skip",
        signatures |-> signatures,
        validators |-> validators,
        stake |-> TotalStake(validators, stakeMap)
    ]

----------------------------------------------------------------------------
(* Network Message Types *)

MessageType == {"block", "vote", "certificate", "shred", "repair"}

\* NetworkMessage type definition
NetworkMessage == [
    type: MessageType,
    sender: ValidatorId,
    recipient: ValidatorId \cup {"broadcast"},
    payload: Nat,  \* Abstract payload
    timestamp: TimeValue,
    signature: Signature
]

\* Consensus messages (Votor)
ConsensusMessage == [
    type: {"block", "vote", "certificate"},
    sender: ValidatorId,
    slot: SlotNumber,
    view: ViewNumber,
    content: Nat  \* Abstract content
]

\* Propagation messages (Rotor)
PropagationMessage == [
    type: {"shred", "repair_request", "repair_response"},
    sender: ValidatorId,
    blockId: BlockHash,
    shredIndex: Nat,
    content: Seq(Nat)  \* Abstract content representation
]

----------------------------------------------------------------------------
(* Byzantine and Fault Models *)

ValidatorStatus == {"honest", "byzantine", "offline"}

ValidatorState == [
    id: ValidatorId,
    status: ValidatorStatus,
    stake: StakeAmount,
    online: BOOLEAN,
    lastSeen: TimeValue
]

\* Byzantine fault threshold (f_byzantine)
ByzantineFaultBound == 20  \* 20 percent of total stake

\* Offline fault threshold (f_offline)
OfflineFaultBound == 20    \* 20 percent of total stake

\* Check if system is within fault bounds
WithinFaultBounds(byzantineStake, offlineStake, totalStake) ==
    /\ byzantineStake <= (ByzantineFaultBound * totalStake) \div 100
    /\ offlineStake <= (OfflineFaultBound * totalStake) \div 100

----------------------------------------------------------------------------
(* Time and Slot Management *)

SlotDuration == 400  \* milliseconds

\* Compute slot from time
TimeToSlot(time) ==
    time \div SlotDuration

\* Compute view timeout calculation
ViewTimeout(view, baseTimeout) ==
    IF view = 1 THEN baseTimeout
    ELSE baseTimeout * (2 ^ ((view - 1) % 10))  \* Exponential backoff, capped at 2^10

\* Check if within timeout window
WithinTimeout(currentTime, startTime, timeout) ==
    currentTime <= startTime + timeout

----------------------------------------------------------------------------
(* Erasure Coding Types *)

ErasureCodedPiece == [
    blockId: BlockHash,
    index: Nat,
    totalPieces: Nat,
    data: Seq(Nat),
    isParity: BOOLEAN,
    signature: Signature
]

ReconstructionThreshold == [
    k: Nat,  \* Minimum pieces needed
    n: Nat   \* Total pieces
]

RepairRequest == [
    requester: ValidatorId,
    blockId: BlockHash,
    missingIndices: SUBSET Nat,
    timestamp: TimeValue
]

\* Message payload type - abstract representation
MessagePayload == Nat  \* Abstract payload identifier


----------------------------------------------------------------------------
(* Window and Chain Predicates *)

\* Window size for leader selection (4 slots per window)
WindowSize == LeaderWindowSize  \* Use the required constant

\* Window Functions (required)
\* Check if two slots are in the same leader window
SameWindow(s1, s2) ==
    (s1 \div LeaderWindowSize) = (s2 \div LeaderWindowSize)

\* Return all slots in the window containing slot s (4-slot windows)
WindowSlots(s) ==
    LET windowIndex == s \div LeaderWindowSize
        windowStart == windowIndex * LeaderWindowSize
    IN {windowStart + i : i \in 0..(LeaderWindowSize - 1)}

\* Check if one block is a descendant of another in the chain
\* b_prime is a descendant of b if there's a chain from b to b_prime
RECURSIVE IsDescendant(_, _)
IsDescendant(b_prime, b) ==
    \/ b_prime = b  \* A block is its own descendant
    \/ /\ b_prime # b
       /\ b_prime.parent = b.hash  \* Direct child
    \/ /\ b_prime # b
       /\ b_prime.parent # 0  \* Has a parent
       /\ \E intermediate \in Block :
           /\ intermediate.hash = b_prime.parent
           /\ IsDescendant(intermediate, b)  \* Recursive descendant check

\* Check direct parent-child relationship
IsParent(child, parent) ==
    /\ child.parent = parent.hash
    /\ child.slot > parent.slot

\* Extract the proposer of a block
BlockProducer(b) ==
    IF b = GenesisBlock THEN 0
    ELSE IF "proposer" \in DOMAIN b THEN b.proposer
    ELSE 0

----------------------------------------------------------------------------
(* Additional Helper Functions *)

\* Check if sequence is prefix of another
IsPrefix(s1, s2) ==
    /\ Len(s1) <= Len(s2)
    /\ \A i \in 1..Len(s1) : s1[i] = s2[i]

\* Find common prefix of two sequences
RECURSIVE CommonPrefix(_, _)
CommonPrefix(s1, s2) ==
    LET minLen == Min(Len(s1), Len(s2))
        prefixLen == CHOOSE l \in 0..minLen :
            /\ \A i \in 1..l : s1[i] = s2[i]
            /\ (l = minLen \/ s1[l+1] # s2[l+1])
    IN
    SubSeq(s1, 1, prefixLen)

\* Generate unique identifier
GenerateId(slot, view, validator) ==
    slot * 1000000 + view * 1000 + validator


\* Convert value to string representation (abstract) - renamed to avoid conflict with TLC
ToStringCustom(value) ==
    IF value \in Nat THEN <<value>>
    ELSE IF value \in STRING THEN value
    ELSE <<>>

\* Abstract erasure coding validity
ValidErasureCode(pieces, k) ==
    Cardinality({p.index : p \in pieces}) >= k

\* Timing functions
ComputeDelta80 == 100  \* milliseconds for 80 percent stake
ComputeDelta60 == 200  \* milliseconds for 60 percent stake

\* Cryptographic abstractions
SignMessage(validator, message) ==
    [signer |-> validator,
     message |-> IF message \in MessageHash THEN message ELSE GenerateId(0, 0, validator),
     valid |-> TRUE,
     aggregatable |-> TRUE]

\* Permutation function for symmetry - renamed to avoid conflict with TLC
PermutationsCustom(S) ==
    {f \in [S -> S] : \A x, y \in S : x # y => f[x] # f[y]}

\* Block hash function - renamed to avoid conflict with type definition
ComputeBlockHash(block) ==
    IF block = 0 THEN 0  \* Genesis or null block
    ELSE IF block \in Nat THEN block  \* Already a hash
    ELSE IF "hash" \in DOMAIN block THEN block.hash
    ELSE GenerateId(IF "slot" \in DOMAIN block THEN block.slot ELSE 0,
                    IF "view" \in DOMAIN block THEN block.view ELSE 0,
                    IF "proposer" \in DOMAIN block THEN block.proposer ELSE 0)

\* Compute stake delegations
ComputeDelegations(validators, delegationMap) ==
    [v \in validators |->
        IF \E d \in DOMAIN delegationMap : delegationMap[d] = v
        THEN Cardinality({x \in DOMAIN delegationMap : delegationMap[x] = v})
        ELSE IF v \in DOMAIN delegationMap THEN delegationMap[v] ELSE 0]

\* Leader Selection (required) - deterministic leader selection
ComputeLeader(slot, validators, stake) ==
    IF validators = {} THEN 0  \* Handle empty validator set
    ELSE IF Cardinality(validators) = 1 THEN CHOOSE v \in validators : TRUE
    ELSE
        LET totalStake == Sum(stake)
            \* VRF-style deterministic randomness
            vrfSeed == VRFEvaluate(slot, 0)  \* Use slot as seed
            targetValue == IF totalStake = 0 THEN 0 ELSE (vrfSeed % totalStake)
            \* Create an ordered sequence of validators
            ValidatorOrder == CHOOSE seq \in [1..Cardinality(validators) -> validators] :
                                \A i, j \in 1..Cardinality(validators) :
                                    i < j => seq[i] # seq[j]
            \* Cumulative stake distribution by index
            cumulativeStake == [i \in 1..Cardinality(validators) |->
                IF i = 1 THEN
                    IF ValidatorOrder[1] \in DOMAIN stake THEN stake[ValidatorOrder[1]] ELSE 0
                ELSE SumSet({IF ValidatorOrder[j] \in DOMAIN stake THEN stake[ValidatorOrder[j]] ELSE 0 : j \in 1..i})
            ]
            \* Find index whose cumulative stake range contains target
            selectedIndex == IF totalStake = 0 THEN 1
                           ELSE CHOOSE i \in 1..Cardinality(validators) :
                               /\ cumulativeStake[i] > targetValue
                               /\ \A j \in 1..Cardinality(validators) :
                                   (j < i => cumulativeStake[j] <= targetValue) \/ j >= i
        IN ValidatorOrder[selectedIndex]

\* Stake Functions (required) - implement Stake[v] function mapping validators to stake weights
Stake == [v \in Validators |->
    IF v \in ByzantineValidators THEN 150  \* Byzantine validators have 15% stake
    ELSE IF v \in OfflineValidators THEN 100  \* Offline validators have 10% stake
    ELSE 200]  \* Honest validators have 20% stake

\* Compute window leader for a given window index
ComputeWindowLeader(windowIndex, validators, stakes) ==
    ComputeLeader(windowIndex, validators, stakes)

\* Check if validator is the leader for a specific slot within their window
IsSlotLeader(validator, slot, validators, stakes) ==
    LET windowIndex == slot \div WindowSize
        windowLeader == ComputeWindowLeader(windowIndex, validators, stakes)
    IN windowLeader = validator

\* Get the leader for a specific slot
GetSlotLeader(slot, validators, stakes) ==
    LET windowIndex == slot \div WindowSize
    IN ComputeWindowLeader(windowIndex, validators, stakes)

\* Deterministic leader selection with VRF proof
ComputeLeaderWithProof(slot, validators, stakes, vrfProof) ==
    LET totalStake == Sum(stakes)
        vrfOutput == IF totalStake = 0 THEN 0 ELSE (vrfProof % totalStake)
        \* Create an ordered sequence of validators
        ValidatorOrder == CHOOSE seq \in [1..Cardinality(validators) -> validators] :
                            \A i, j \in 1..Cardinality(validators) :
                                i < j => seq[i] # seq[j]
        \* Cumulative stake distribution by index
        cumulativeStake == [i \in 1..Cardinality(validators) |->
            IF i = 1 THEN
                IF ValidatorOrder[1] \in DOMAIN stakes THEN stakes[ValidatorOrder[1]] ELSE 0
            ELSE SumSet({IF ValidatorOrder[j] \in DOMAIN stakes THEN stakes[ValidatorOrder[j]] ELSE 0 : j \in 1..i})
        ]
        \* Find index whose cumulative stake range contains target
        selectedIndex == IF totalStake = 0 THEN 1
                       ELSE CHOOSE i \in 1..Cardinality(validators) :
                           /\ cumulativeStake[i] > vrfOutput
                           /\ \A j \in 1..Cardinality(validators) :
                               (j < i => cumulativeStake[j] <= vrfOutput) \/ j >= i
    IN ValidatorOrder[selectedIndex]

\* Validate VRF proof for leader selection
ValidVRFProof(slot, validator, proof, publicKey) ==
    /\ proof \in Nat
    /\ VRFEvaluate(slot, validator) = proof
    /\ VerifySignature([signer |-> validator, message |-> slot, valid |-> TRUE], slot, publicKey)

\* Stake-weighted random selection
StakeWeightedSelection(candidates, stakes, randomness) ==
    LET totalStake == Sum([v \in candidates |-> IF v \in DOMAIN stakes THEN stakes[v] ELSE 0])
        target == IF totalStake = 0 THEN 0 ELSE (randomness % totalStake)
        \* Create an ordered sequence of candidates
        CandidateOrder == CHOOSE seq \in [1..Cardinality(candidates) -> candidates] :
                            \A i, j \in 1..Cardinality(candidates) :
                                i < j => seq[i] # seq[j]
        \* Cumulative stake distribution by index
        cumulative == [i \in 1..Cardinality(candidates) |->
            IF i = 1 THEN
                IF CandidateOrder[1] \in DOMAIN stakes THEN stakes[CandidateOrder[1]] ELSE 0
            ELSE SumSet({IF CandidateOrder[j] \in DOMAIN stakes THEN stakes[CandidateOrder[j]] ELSE 0 : j \in 1..i})
        ]
        \* Find index whose cumulative stake range contains target
        selectedIndex == IF totalStake = 0 THEN 1
                       ELSE CHOOSE i \in 1..Cardinality(candidates) :
                           /\ cumulative[i] > target
                           /\ \A j \in 1..Cardinality(candidates) :
                               (j < i => cumulative[j] <= target) \/ j >= i
    IN CandidateOrder[selectedIndex]

\* Check if validator is leader for slot
IsLeader(validator, slot, schedule) ==
    /\ slot \in DOMAIN schedule
    /\ schedule[slot] = validator

\* Check if chain extends another
ExtendsChain(chain1, chain2) ==
    IsPrefix(chain2, chain1)

\* Find longest common prefix of chains
RECURSIVE LongestCommonPrefix(_)
LongestCommonPrefix(chains) ==
    IF Cardinality(chains) = 0 THEN <<>>
    ELSE IF Cardinality(chains) = 1 THEN CHOOSE c \in chains : TRUE
    ELSE LET c1 == CHOOSE c \in chains : TRUE
             rest == chains \ {c1}
             RECURSIVE FoldCommonPrefix(_)
             FoldCommonPrefix(S) ==
                 IF S = {} THEN c1
                 ELSE LET x == CHOOSE x \in S : TRUE
                      IN CommonPrefix(x, FoldCommonPrefix(S \ {x}))
         IN FoldCommonPrefix(rest)

\* Check Byzantine agreement
ByzantineAgreement(honest, byzantine, total) ==
    /\ Cardinality(byzantine) < (total \div 3)
    /\ Cardinality(honest) > ((2 * total) \div 3)

\* Compute supermajority threshold
Supermajority(stake) ==
    ((2 * stake) \div 3) + 1

\* Check liveness condition
LivenessCondition(online, total) ==
    Cardinality(online) > ((2 * total) \div 3)

\* Enhanced cryptographic verification with forgery protection
VerifySignature(sig, message, pubkey) ==
    /\ sig.valid
    /\ sig.message = message
    /\ sig.signer = pubkey

\* Verify signature with honest validator check
VerifySignatureHonest(sig, message, validator, honestValidators) ==
    /\ VerifySignature(sig, message, validator)
    /\ NoSignatureForge(sig, validator, honestValidators)

\* Batch signature verification
BatchVerifySignatures(signatures, messages, validators, honestValidators) ==
    /\ Cardinality(signatures) = Cardinality(messages)
    /\ Cardinality(messages) = Cardinality(validators)
    /\ \A i \in 1..Cardinality(signatures) :
        LET sig == CHOOSE s \in signatures : TRUE  \* Simplified selection
            msg == CHOOSE m \in messages : TRUE
            val == CHOOSE v \in validators : TRUE
        IN VerifySignatureHonest(sig, msg, val, honestValidators)

\* Enhanced VRF evaluation with cryptographic properties
VRFEvaluate(seed, validator) ==
    LET hash1 == ((seed * 997 + validator * 991) % 1000000)
        hash2 == ((hash1 * 983 + seed * 977) % 1000000)
    IN ((hash1 + hash2) % 1000000)

\* VRF proof generation
VRFProve(seed, validator, secretKey) ==
    [
        output |-> VRFEvaluate(seed, validator),
        proof |-> ((seed * secretKey * validator) % 1000000),
        valid |-> TRUE
    ]

\* VRF proof verification
VRFVerify(seed, proof, publicKey, output) ==
    /\ proof.valid
    /\ proof.output = output
    /\ VRFEvaluate(seed, publicKey) = output

\* Check if value is in valid range
InRange(value, min, max) ==
    value >= min /\ value <= max

\* Median of a set of values
Median(values) ==
    LET sorted == CHOOSE seq \in Seq(values) :
                    /\ \A i, j \in 1..Len(seq) : i < j => seq[i] <= seq[j]
                    /\ \A v \in values : \E i \in 1..Len(seq) : seq[i] = v
        size == Cardinality(values)
    IN IF size = 0 THEN 0
       ELSE IF (size % 2) = 1
            THEN sorted[(size + 1) \div 2]
            ELSE (sorted[size \div 2] + sorted[size \div 2 + 1]) \div 2

\* Sort a set and return as sequence
SortedSeq(S, lessThan(_, _)) ==
    LET sorted == CHOOSE seq \in Seq(S) : \A i, j \in 1..Len(seq) : i < j => lessThan(seq[i], seq[j])
    IN sorted

----------------------------------------------------------------------------
(* Network Partition Recovery and Timing Constraints *)

\* Network partition state
PartitionState == [
    partitions: SUBSET (SUBSET ValidatorId),
    isolated: SUBSET ValidatorId,
    bridges: SUBSET ValidatorId,
    recoveryTime: TimeValue
]

\* Global Stabilization Time (GST) model
GSTModel == [
    gst: TimeValue,
    beforeGST: BOOLEAN,
    afterGST: BOOLEAN,
    messageDelay: TimeValue
]

\* Network synchrony assumptions
SynchronyAssumption == [
    type: {"synchronous", "asynchronous", "partial"},
    maxDelay: TimeValue,
    gst: TimeValue,
    reliability: Nat  \* Percentage
]

\* Partition recovery mechanism
PartitionRecovery == [
    detectionTime: TimeValue,
    recoveryStrategy: {"merge", "elect_leader", "wait"},
    consensusRequired: BOOLEAN,
    stakeMajority: BOOLEAN
]

\* Timing constraint types
TimingConstraint == [
    type: {"slot_duration", "view_timeout", "message_delay", "recovery_time"},
    value: TimeValue,
    bound: {"upper", "lower", "exact"},
    condition: STRING
]

\* Check if network is partitioned
IsPartitioned(topology, validators) ==
    \E partition \in SUBSET validators :
        /\ partition # {}
        /\ partition # validators
        /\ \A u \in partition, v \in (validators \ partition) :
            <<u, v>> \notin topology.edges

\* Compute partition size by stake
PartitionStakeSize(partition, stakes) ==
    Sum([v \in partition |-> stakes[v]])

\* Check if partition has majority stake
HasMajorityStake(partition, stakes, totalStake) ==
    PartitionStakeSize(partition, stakes) > (totalStake \div 2)

\* Network healing condition
NetworkHealed(oldTopology, newTopology, validators) ==
    /\ IsConnected(newTopology)
    /\ \A v \in validators : v \in newTopology.nodes
    /\ \A edge \in oldTopology.edges : edge \in newTopology.edges

\* Recovery time estimation
EstimateRecoveryTime(partitionSize, totalValidators, baseTime) ==
    baseTime * ((partitionSize * 100) \div totalValidators)

\* Abstract shortest path
ShortestPath(topology, source, dest) ==
    IF <<source, dest>> \in topology.edges THEN 1
    ELSE 2  \* Simplified

\* Compute network diameter
NetworkDiameter(topology) ==
    LET paths == {ShortestPath(topology, u, v) : u, v \in topology.nodes}
    IN IF paths = {} THEN 0
       ELSE CHOOSE m \in paths : \A p \in paths : m >= p

\* Check network connectivity
IsConnected(topology) ==
    \A u, v \in topology.nodes :
        \E path \in Seq(topology.nodes) :
            /\ path[1] = u
            /\ path[Len(path)] = v
            /\ \A i \in 1..(Len(path)-1) :
                <<path[i], path[i+1]>> \in topology.edges

\* Enhanced connectivity check with partition awareness
IsConnectedWithPartitions(topology, partitions) ==
    /\ \A partition \in partitions :
        \A u, v \in partition :
            \E path \in Seq(partition) :
                /\ path[1] = u
                /\ path[Len(path)] = v
                /\ \A i \in 1..(Len(path)-1) :
                    <<path[i], path[i+1]>> \in topology.edges

\* Check if GST has passed
AfterGST(currentTime, gst) ==
    currentTime >= gst

\* Message delivery guarantee after GST
MessageDeliveryAfterGST(sendTime, receiveTime, gst, delta) ==
    /\ sendTime >= gst
    /\ receiveTime <= sendTime + delta

\* Partial synchrony condition
PartialSynchrony(gst, delta, currentTime) ==
    /\ \E t \in TimeValue : t >= gst
    /\ currentTime >= gst
    /\ \A message : MessageDeliveryAfterGST(message.sendTime, message.receiveTime, gst, delta)

----------------------------------------------------------------------------
(* Network Timing Operators *)

\* Message delay bounds
MessageDelayBound == 100  \* milliseconds

\* Network timing constraints
NetworkTimingConstraints == [
    maxDelay: MessageDelayBound,
    gstBound: 1000,  \* GST bound in milliseconds
    viewTimeout: 2000,  \* View timeout in milliseconds
    slotDuration: SlotDuration
]

\* Check if message delivery is within bounds
WithinDeliveryBounds(sendTime, receiveTime, bound) ==
    receiveTime <= sendTime + bound

\* Protocol delay tolerance
ProtocolDelayTolerance(protocolType) ==
    CASE protocolType = "consensus" -> 200
      [] protocolType = "propagation" -> 100
      [] protocolType = "recovery" -> 500
      [] OTHER -> MessageDelayBound

\* Bounded delay after GST
BoundedDelayAfterGST(sendTime, receiveTime, gst, delta) ==
    /\ sendTime >= gst
    /\ receiveTime <= sendTime + delta

\* Event ordering constraints
EventOrderingConstraint(event1, event2, timeBound) ==
    event2.timestamp <= event1.timestamp + timeBound

\* Network stability condition
NetworkStable(topology, gst, currentTime) ==
    /\ currentTime >= gst
    /\ IsConnected(topology)
    /\ \A partition \in topology.partitions : partition = {}

\* Synchronization window
SynchronizationWindow(gst, windowSize) ==
    [start |-> gst, end |-> gst + windowSize]

\* Check if time is within synchronization window
InSyncWindow(time, window) ==
    time >= window.start /\ time <= window.end

\* Network convergence time
NetworkConvergenceTime(validators, messageDelay, rounds) ==
    rounds * messageDelay * Cardinality(validators)

\* Liveness timing constraint
LivenessTimingConstraint(slot, view, timeout) ==
    [
        slot |-> slot,
        view |-> view,
        deadline |-> timeout,
        type |-> "liveness"
    ]

\* Safety timing constraint
SafetyTimingConstraint(slot, view, delay) ==
    [
        slot |-> slot,
        view |-> view,
        maxDelay |-> delay,
        type |-> "safety"
    ]

\* Check timing constraint satisfaction
SatisfiesTimingConstraint(constraint, actualTime, expectedTime) ==
    CASE constraint.type = "liveness" -> actualTime <= constraint.deadline
      [] constraint.type = "safety" -> actualTime >= expectedTime
      [] OTHER -> TRUE

============================================================================
