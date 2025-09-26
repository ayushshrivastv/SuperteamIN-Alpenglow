\* Author: Ayush Srivastava
------------------------------- MODULE TypesCore -------------------------------
(**************************************************************************)
(* Core type definitions for the Alpenglow protocol                       *)
(* Split from Types.tla to work around parser issues                      *)
(**************************************************************************)

EXTENDS Integers, Sequences, FiniteSets, TLC

----------------------------------------------------------------------------
(* BASIC TYPES *)
----------------------------------------------------------------------------

\* Validator identifier
ValidatorId == Nat

\* Slot number in the blockchain
SlotNumber == Nat

\* View number within a slot
ViewNumber == Nat

\* Block hash (simplified as natural number)
BlockHash == Nat

\* Transaction identifier
TransactionId == Nat

\* Stake amount
StakeAmount == Nat

\* Time value
TimeValue == Nat

\* Message identifier
MessageId == Nat

\* Certificate types
CertificateType == {"fast", "slow", "skip"}

\* Message types
MessageType == {"block", "vote", "certificate", "timeout", "sync"}

\* Vote types
VoteType == {"prevote", "precommit", "commit"}

----------------------------------------------------------------------------
(* RECORD TYPES *)
----------------------------------------------------------------------------

\* Transaction record
Transaction == [
    id: TransactionId,
    sender: ValidatorId,
    data: Nat,
    timestamp: TimeValue
]

\* Block record
Block == [
    slot: SlotNumber,
    view: ViewNumber,
    hash: BlockHash,
    parent: BlockHash,
    transactions: Seq(Transaction),
    proposer: ValidatorId,
    timestamp: TimeValue
]

\* Vote record
Vote == [
    validator: ValidatorId,
    slot: SlotNumber,
    view: ViewNumber,
    block: BlockHash,
    type: VoteType,
    signature: Nat,
    timestamp: TimeValue
]

\* Signature record
Signature == [
    signer: ValidatorId,
    message: Nat,
    valid: BOOLEAN,
    aggregatable: BOOLEAN
]

\* Aggregated signature
AggregatedSignature == [
    signers: SUBSET ValidatorId,
    message: Nat,
    valid: BOOLEAN,
    count: Nat
]

\* Certificate record
Certificate == [
    slot: SlotNumber,
    view: ViewNumber,
    block: BlockHash,
    type: CertificateType,
    signatures: AggregatedSignature,
    validators: SUBSET ValidatorId,
    stake: StakeAmount
]

\* Message record
Message == [
    id: MessageId,
    type: MessageType,
    sender: ValidatorId,
    receiver: ValidatorId,
    content: Nat,
    timestamp: TimeValue
]

\* Network state
NetworkState == [
    messages: SUBSET Message,
    delivered: SUBSET MessageId,
    lost: SUBSET MessageId,
    delayed: SUBSET MessageId
]

\* Validator state
ValidatorState == [
    id: ValidatorId,
    view: ViewNumber,
    votedBlocks: SUBSET Block,
    finalizedChain: Seq(Block),
    certificates: SUBSET Certificate,
    messages: SUBSET Message
]

----------------------------------------------------------------------------
(* HELPER FUNCTIONS *)
----------------------------------------------------------------------------

\* Create an empty block
EmptyBlock == [
    slot |-> 0,
    view |-> 0,
    hash |-> 0,
    parent |-> 0,
    transactions |-> <<>>,
    proposer |-> 0,
    timestamp |-> 0
]

\* Create a genesis block
GenesisBlock == [
    slot |-> 0,
    view |-> 0,
    hash |-> 1,
    parent |-> 0,
    transactions |-> <<>>,
    proposer |-> 0,
    timestamp |-> 0
]

\* Check if a block is valid
IsValidBlock(block) ==
    /\ block.slot \in SlotNumber
    /\ block.view \in ViewNumber
    /\ block.hash \in BlockHash
    /\ block.parent \in BlockHash
    /\ block.proposer \in ValidatorId
    /\ block.timestamp \in TimeValue

\* Check if a vote is valid
IsValidVote(vote) ==
    /\ vote.validator \in ValidatorId
    /\ vote.slot \in SlotNumber
    /\ vote.view \in ViewNumber
    /\ vote.block \in BlockHash
    /\ vote.type \in VoteType
    /\ vote.timestamp \in TimeValue

\* Check if a certificate is valid
IsValidCertificate(cert) ==
    /\ cert.slot \in SlotNumber
    /\ cert.view \in ViewNumber
    /\ cert.block \in BlockHash
    /\ cert.type \in CertificateType
    /\ cert.stake \in StakeAmount

============================================================================
