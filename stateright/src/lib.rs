//! # Alpenglow Protocol - Stateright Implementation
//!
//! This library provides a Rust implementation of the Solana Alpenglow consensus protocol
//! using the Stateright framework for formal verification and cross-validation with TLA+ specifications.
//!
//! The implementation mirrors the TLA+ specification structure found in the `specs/` directory,
//! providing executable models that can be verified against the formal specifications.
//!
//! ## Architecture
//!
//! The Alpenglow protocol consists of several key components:
//!
//! - **Votor**: Consensus mechanism with dual-path voting (fast path ≥80% stake, slow path ≥60% stake)
//! - **Rotor**: Block propagation using erasure coding and stake-weighted relay sampling
//! - **Network**: Partial synchrony model with GST assumptions and Delta-bounded message delivery
//! - **Integration**: End-to-end protocol combining all components
//!
//! ## Usage
//!
//! ```rust
//! use alpenglow_stateright::{AlpenglowModel, Config};
//!
//! // Create a network configuration
//! let config = Config::new()
//!     .with_validators(4)
//!     .with_byzantine_threshold(1);
//!
//! // Initialize the protocol model
//! let model = AlpenglowModel::new(config);
//!
//! // Run verification
//! model.verify_safety_properties();
//! ```

use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet, BTreeMap, BTreeSet};
use std::fmt::Debug;
use std::hash::Hash;

// Local stateright implementation
pub mod stateright;

// Expose the local stateright module under a distinct name to avoid conflicts with
// any external crate also named `stateright`. Consumers of this crate should use
// `crate::local_stateright` to access the framework primitives provided here.
pub use crate::stateright as local_stateright;

// Core protocol modules
pub mod votor;
pub mod rotor;
pub mod network;
pub mod integration;

// Re-export main components
pub use votor::{VotorActor, VotorState, VotorMessage, VotingRound, Certificate};
pub use rotor::{RotorActor, RotorState, RotorMessage, ErasureBlock, RelayPath};
pub use network::{NetworkActor, NetworkState, NetworkMessage, PartialSynchronyModel};
pub use integration::{AlpenglowNode, AlpenglowState, AlpenglowMessage, ProtocolConfig};

/// Validator identifier type - mirrors TLA+ ValidatorId
pub type ValidatorId = u32;

/// Slot number type for consensus rounds - mirrors TLA+ SlotNumber
pub type SlotNumber = u64;

/// View number type for consensus views - mirrors TLA+ ViewNumber
pub type ViewNumber = u64;

/// Stake amount type - mirrors TLA+ StakeAmount
pub type StakeAmount = u64;

/// Block hash type - mirrors TLA+ BlockHash
pub type BlockHash = u64; // Simplified to u64 for TLA+ compatibility

/// Cryptographic signature type - mirrors TLA+ Signature
pub type Signature = u64; // Simplified to u64 for TLA+ compatibility

/// Time value type - mirrors TLA+ TimeValue
pub type TimeValue = u64;

/// Message hash type - mirrors TLA+ MessageHash
pub type MessageHash = u64;

/// Core types that exactly mirror the TLA+ type definitions

/// Transaction type - mirrors TLA+ Transaction
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct Transaction {
    pub id: u64,
    pub sender: ValidatorId,
    pub data: Vec<u64>,
    pub signature: Signature,
}

/// Block type - mirrors TLA+ Block
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct Block {
    pub slot: SlotNumber,
    pub view: ViewNumber,
    pub hash: BlockHash,
    pub parent: BlockHash,
    pub proposer: ValidatorId,
    pub transactions: HashSet<Transaction>,
    pub timestamp: TimeValue,
    pub signature: Signature,
    pub data: Vec<u64>,
}

/// Vote type - mirrors TLA+ Vote
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct Vote {
    pub voter: ValidatorId,
    pub slot: SlotNumber,
    pub view: ViewNumber,
    pub block: BlockHash,
    pub vote_type: VoteType,
    pub signature: Signature,
    pub timestamp: TimeValue,
}

/// Vote type enumeration - mirrors TLA+ VoteType
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum VoteType {
    Proposal,
    Echo,
    Commit,
    Skip,
}

/// Certificate type - mirrors TLA+ Certificate
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct Certificate {
    pub slot: SlotNumber,
    pub view: ViewNumber,
    pub block: BlockHash,
    pub cert_type: CertificateType,
    pub validators: HashSet<ValidatorId>,
    pub stake: StakeAmount,
    pub signatures: AggregatedSignature,
}

/// Certificate type enumeration - mirrors TLA+ CertificateType
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum CertificateType {
    Fast,
    Slow,
    Skip,
}

/// Aggregated signature type - mirrors TLA+ AggregatedSignature
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct AggregatedSignature {
    pub signers: HashSet<ValidatorId>,
    pub message: MessageHash,
    pub signatures: HashSet<Signature>,
    pub valid: bool,
}

/// Validator type - mirrors TLA+ ValidatorState
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct Validator {
    pub id: ValidatorId,
    pub stake: StakeAmount,
    pub status: ValidatorStatus,
    pub online: bool,
    pub last_seen: TimeValue,
}

/// Validator status enumeration - mirrors TLA+ ValidatorStatus
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum ValidatorStatus {
    Honest,
    Byzantine,
    Offline,
}

/// Erasure coded piece - mirrors TLA+ ErasureCodedPiece
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct ErasureCodedPiece {
    pub block_id: BlockHash,
    pub index: u32,
    pub total_pieces: u32,
    pub data: Vec<u64>,
    pub is_parity: bool,
    pub signature: Signature,
}

/// Network message type - mirrors TLA+ NetworkMessage
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct NetworkMessage {
    pub msg_type: MessageType,
    pub sender: ValidatorId,
    pub recipient: MessageRecipient,
    pub payload: u64, // Simplified payload
    pub timestamp: TimeValue,
    pub signature: Signature,
}

/// Message type enumeration - mirrors TLA+ MessageType
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum MessageType {
    Block,
    Vote,
    Certificate,
    Shred,
    Repair,
}

/// Message recipient type
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum MessageRecipient {
    Validator(ValidatorId),
    Broadcast,
}

/// Action enumeration for Votor consensus - mirrors TLA+ Votor actions
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum VotorAction {
    ProposeBlock { validator: ValidatorId, view: ViewNumber },
    CastVote { validator: ValidatorId, block: Block, view: ViewNumber },
    CollectVotes { validator: ValidatorId, view: ViewNumber },
    FinalizeBlock { validator: ValidatorId, certificate: Certificate },
    SubmitSkipVote { validator: ValidatorId, view: ViewNumber },
    CollectSkipVotes { validator: ValidatorId, view: ViewNumber },
    Timeout { validator: ValidatorId },
}

/// Action enumeration for Rotor propagation - mirrors TLA+ Rotor actions
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum RotorAction {
    ShredAndDistribute { leader: ValidatorId, block: Block },
    RelayShreds { validator: ValidatorId, block_id: BlockHash },
    AttemptReconstruction { validator: ValidatorId, block_id: BlockHash },
    RequestRepair { validator: ValidatorId, block_id: BlockHash },
    RespondToRepair { validator: ValidatorId, request: RepairRequest },
}

/// Action enumeration for Network operations - mirrors TLA+ Network actions
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum NetworkAction {
    DeliverMessage { message: NetworkMessage },
    DropMessage { message: NetworkMessage },
    PartitionNetwork { partition: HashSet<ValidatorId> },
    HealPartition,
}

/// Byzantine action enumeration - mirrors TLA+ Byzantine behaviors
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum ByzantineAction {
    DoubleVote { validator: ValidatorId, view: ViewNumber },
    InvalidBlock { validator: ValidatorId },
    WithholdShreds { validator: ValidatorId },
    Equivocate { validator: ValidatorId },
}

/// Main action enumeration combining all protocol actions
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum AlpenglowAction {
    AdvanceClock,
    AdvanceSlot,
    AdvanceView { validator: ValidatorId },
    Votor(VotorAction),
    Rotor(RotorAction),
    Network(NetworkAction),
    Byzantine(ByzantineAction),
}

/// Repair request type - mirrors TLA+ RepairRequest
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct RepairRequest {
    pub requester: ValidatorId,
    pub block_id: BlockHash,
    pub missing_indices: HashSet<u32>,
    pub timestamp: TimeValue,
}

/// Global configuration for the Alpenglow protocol
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Config {
    /// Number of validators in the network
    pub validator_count: usize,
    
    /// Stake distribution among validators
    pub stake_distribution: HashMap<ValidatorId, StakeAmount>,
    
    /// Total stake in the network
    pub total_stake: StakeAmount,
    
    /// Fast path threshold (typically 80% of total stake)
    pub fast_path_threshold: StakeAmount,
    
    /// Slow path threshold (typically 60% of total stake)
    pub slow_path_threshold: StakeAmount,
    
    /// Maximum number of Byzantine validators tolerated
    pub byzantine_threshold: usize,
    
    /// Network delay bounds for partial synchrony
    pub max_network_delay: u64,
    
    /// Global Stabilization Time (GST) for network synchrony
    pub gst: u64,
    
    /// Bandwidth limit per validator (bytes per round)
    pub bandwidth_limit: usize,
    
    /// Erasure coding parameters (rate of data to total shreds)
    pub erasure_coding_rate: f64,
    
    /// Maximum block size in bytes
    pub max_block_size: usize,
    
    /// Erasure coding K parameter (data shreds)
    pub k: u32,
    
    /// Erasure coding N parameter (total shreds)
    pub n: u32,
    
    /// Maximum view number
    pub max_view: ViewNumber,
    
    /// Maximum slot number
    pub max_slot: SlotNumber,
    
    /// Timeout delta for consensus
    pub timeout_delta: TimeValue,
}

/// Main Alpenglow model struct - mirrors TLA+ Alpenglow state variables
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AlpenglowModel {
    /// Configuration
    pub config: Config,
    
    /// Current state
    pub state: AlpenglowState,
}

/// Alpenglow state - mirrors TLA+ Alpenglow state variables exactly
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AlpenglowState {
    // Time and scheduling - mirrors TLA+ time variables
    pub clock: TimeValue,
    pub current_slot: SlotNumber,
    pub current_rotor: ValidatorId,
    
    // Votor consensus state - mirrors TLA+ Votor variables
    pub votor_view: HashMap<ValidatorId, ViewNumber>,
    pub votor_voted_blocks: HashMap<ValidatorId, HashMap<ViewNumber, HashSet<Block>>>,
    pub votor_generated_certs: HashMap<ViewNumber, HashSet<Certificate>>,
    pub votor_finalized_chain: Vec<Block>,
    pub votor_skip_votes: HashMap<ValidatorId, HashMap<ViewNumber, HashSet<Vote>>>,
    pub votor_timeout_expiry: HashMap<ValidatorId, TimeValue>,
    pub votor_received_votes: HashMap<ValidatorId, HashMap<ViewNumber, HashSet<Vote>>>,
    
    // Rotor propagation state - mirrors TLA+ Rotor variables
    pub rotor_block_shreds: HashMap<BlockHash, HashMap<ValidatorId, HashSet<ErasureCodedPiece>>>,
    pub rotor_relay_assignments: HashMap<ValidatorId, Vec<u32>>,
    pub rotor_reconstruction_state: HashMap<ValidatorId, Vec<ReconstructionState>>,
    pub rotor_delivered_blocks: HashMap<ValidatorId, HashSet<BlockHash>>,
    pub rotor_repair_requests: HashSet<RepairRequest>,
    pub rotor_bandwidth_usage: HashMap<ValidatorId, u64>,
    pub rotor_shred_assignments: HashMap<ValidatorId, HashSet<u32>>,
    pub rotor_received_shreds: HashMap<ValidatorId, HashSet<ErasureCodedPiece>>,
    pub rotor_reconstructed_blocks: HashMap<ValidatorId, HashSet<Block>>,
    
    // Network state - mirrors TLA+ Network variables
    pub network_message_queue: HashSet<NetworkMessage>,
    pub network_message_buffer: HashMap<ValidatorId, HashSet<NetworkMessage>>,
    pub network_partitions: HashSet<HashSet<ValidatorId>>,
    pub network_dropped_messages: u64,
    pub network_delivery_time: HashMap<NetworkMessage, TimeValue>,
    
    // Additional state variables - mirrors TLA+ additional variables
    pub finalized_blocks: HashMap<SlotNumber, HashSet<Block>>,
    pub finalized_by_slot: HashMap<SlotNumber, HashSet<Block>>,
    pub delivered_blocks: HashSet<Block>,
    pub messages: HashSet<NetworkMessage>,
    pub failure_states: HashMap<ValidatorId, ValidatorStatus>,
    pub nonce_counter: u64,
    pub latency_metrics: HashMap<SlotNumber, TimeValue>,
    pub bandwidth_metrics: HashMap<ValidatorId, u64>,
}

/// Reconstruction state - mirrors TLA+ reconstruction tracking
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct ReconstructionState {
    pub block_id: BlockHash,
    pub collected_pieces: HashSet<u32>,
    pub complete: bool,
}

impl AlpenglowModel {
    /// Create a new Alpenglow model with the given configuration
    pub fn new(config: Config) -> Self {
        let state = AlpenglowState::init(&config);
        Self { config, state }
    }
    
    /// Get the current state
    pub fn state(&self) -> &AlpenglowState {
        &self.state
    }
    
    /// Get the configuration
    pub fn config(&self) -> &Config {
        &self.config
    }
    
    /// Check if an action is enabled in the current state
    pub fn action_enabled(&self, action: &AlpenglowAction) -> bool {
        match action {
            AlpenglowAction::AdvanceClock => true,
            AlpenglowAction::AdvanceSlot => {
                // Can advance slot if current slot has finalized blocks
                self.state.finalized_blocks.get(&self.state.current_slot)
                    .map_or(false, |blocks| !blocks.is_empty()) &&
                self.state.current_slot < self.config.max_slot
            },
            AlpenglowAction::AdvanceView { validator } => {
                // Can advance view if timeout expired
                let current_view = self.state.votor_view.get(validator).copied().unwrap_or(1);
                let timeout_expiry = self.state.votor_timeout_expiry.get(validator).copied().unwrap_or(0);
                current_view < self.config.max_view && self.state.clock >= timeout_expiry
            },
            AlpenglowAction::Votor(votor_action) => self.votor_action_enabled(votor_action),
            AlpenglowAction::Rotor(rotor_action) => self.rotor_action_enabled(rotor_action),
            AlpenglowAction::Network(network_action) => self.network_action_enabled(network_action),
            AlpenglowAction::Byzantine(byzantine_action) => self.byzantine_action_enabled(byzantine_action),
        }
    }
    
    /// Execute an action and return the new state
    pub fn execute_action(&self, action: AlpenglowAction) -> AlpenglowResult<AlpenglowState> {
        if !self.action_enabled(&action) {
            return Err(AlpenglowError::ProtocolViolation(
                format!("Action not enabled: {:?}", action)
            ));
        }
        
        let mut new_state = self.state.clone();
        
        match action {
            AlpenglowAction::AdvanceClock => {
                new_state.clock += 1;
            },
            AlpenglowAction::AdvanceSlot => {
                new_state.current_slot += 1;
            },
            AlpenglowAction::AdvanceView { validator } => {
                let current_view = new_state.votor_view.get(&validator).copied().unwrap_or(1);
                new_state.votor_view.insert(validator, current_view + 1);
                
                // Update timeout expiry with exponential backoff
                let new_timeout = new_state.clock + self.config.timeout_delta * (2_u64.pow((current_view + 1) as u32));
                new_state.votor_timeout_expiry.insert(validator, new_timeout);
            },
            AlpenglowAction::Votor(votor_action) => {
                self.execute_votor_action(&mut new_state, votor_action)?;
            },
            AlpenglowAction::Rotor(rotor_action) => {
                self.execute_rotor_action(&mut new_state, rotor_action)?;
            },
            AlpenglowAction::Network(network_action) => {
                self.execute_network_action(&mut new_state, network_action)?;
            },
            AlpenglowAction::Byzantine(byzantine_action) => {
                self.execute_byzantine_action(&mut new_state, byzantine_action)?;
            },
        }
        
        Ok(new_state)
    }
    
    /// Check if a Votor action is enabled
    fn votor_action_enabled(&self, action: &VotorAction) -> bool {
        match action {
            VotorAction::ProposeBlock { validator, view } => {
                let current_view = self.state.votor_view.get(validator).copied().unwrap_or(1);
                *view == current_view && self.is_leader_for_view(*validator, *view)
            },
            VotorAction::CastVote { validator, view, .. } => {
                let current_view = self.state.votor_view.get(validator).copied().unwrap_or(1);
                *view == current_view
            },
            VotorAction::CollectVotes { validator, view } => {
                let current_view = self.state.votor_view.get(validator).copied().unwrap_or(1);
                *view == current_view
            },
            VotorAction::FinalizeBlock { validator, certificate } => {
                let current_view = self.state.votor_view.get(validator).copied().unwrap_or(1);
                self.state.votor_generated_certs.get(&current_view)
                    .map_or(false, |certs| certs.contains(certificate))
            },
            VotorAction::SubmitSkipVote { validator, view } => {
                let current_view = self.state.votor_view.get(validator).copied().unwrap_or(1);
                let timeout_expiry = self.state.votor_timeout_expiry.get(validator).copied().unwrap_or(0);
                *view == current_view && self.state.clock >= timeout_expiry
            },
            VotorAction::CollectSkipVotes { validator, view } => {
                let current_view = self.state.votor_view.get(validator).copied().unwrap_or(1);
                *view == current_view
            },
            VotorAction::Timeout { validator } => {
                let timeout_expiry = self.state.votor_timeout_expiry.get(validator).copied().unwrap_or(0);
                self.state.clock >= timeout_expiry
            },
        }
    }
    
    /// Check if a Rotor action is enabled
    fn rotor_action_enabled(&self, action: &RotorAction) -> bool {
        match action {
            RotorAction::ShredAndDistribute { leader, block } => {
                *leader == block.proposer && !self.state.rotor_block_shreds.contains_key(&block.hash)
            },
            RotorAction::RelayShreds { validator, block_id } => {
                self.state.rotor_block_shreds.get(block_id)
                    .and_then(|shreds| shreds.get(validator))
                    .map_or(false, |validator_shreds| !validator_shreds.is_empty())
            },
            RotorAction::AttemptReconstruction { validator, block_id } => {
                self.can_reconstruct(*validator, *block_id) &&
                !self.state.rotor_delivered_blocks.get(validator)
                    .map_or(false, |delivered| delivered.contains(block_id))
            },
            RotorAction::RequestRepair { validator, block_id } => {
                !self.can_reconstruct(*validator, *block_id) &&
                !self.state.rotor_delivered_blocks.get(validator)
                    .map_or(false, |delivered| delivered.contains(block_id))
            },
            RotorAction::RespondToRepair { validator, request } => {
                self.state.rotor_repair_requests.contains(request) &&
                self.state.rotor_block_shreds.get(&request.block_id)
                    .and_then(|shreds| shreds.get(validator))
                    .map_or(false, |validator_shreds| !validator_shreds.is_empty())
            },
        }
    }
    
    /// Check if a Network action is enabled
    fn network_action_enabled(&self, action: &NetworkAction) -> bool {
        match action {
            NetworkAction::DeliverMessage { message } => {
                self.state.network_message_queue.contains(message)
            },
            NetworkAction::DropMessage { message } => {
                self.state.network_message_queue.contains(message)
            },
            NetworkAction::PartitionNetwork { .. } => true,
            NetworkAction::HealPartition => !self.state.network_partitions.is_empty(),
        }
    }
    
    /// Check if a Byzantine action is enabled
    fn byzantine_action_enabled(&self, action: &ByzantineAction) -> bool {
        match action {
            ByzantineAction::DoubleVote { validator, .. } => {
                matches!(self.state.failure_states.get(validator), Some(ValidatorStatus::Byzantine))
            },
            ByzantineAction::InvalidBlock { validator } => {
                matches!(self.state.failure_states.get(validator), Some(ValidatorStatus::Byzantine))
            },
            ByzantineAction::WithholdShreds { validator } => {
                matches!(self.state.failure_states.get(validator), Some(ValidatorStatus::Byzantine))
            },
            ByzantineAction::Equivocate { validator } => {
                matches!(self.state.failure_states.get(validator), Some(ValidatorStatus::Byzantine))
            },
        }
    }
    
    /// Execute a Votor action
    fn execute_votor_action(&self, state: &mut AlpenglowState, action: VotorAction) -> AlpenglowResult<()> {
        match action {
            VotorAction::ProposeBlock { validator, view } => {
                let new_block = Block {
                    slot: view,
                    view,
                    hash: view, // Simplified hash
                    parent: state.votor_finalized_chain.last().map_or(0, |b| b.hash),
                    proposer: validator,
                    transactions: HashSet::new(),
                    timestamp: state.clock,
                    signature: validator as u64, // Simplified signature
                    data: vec![],
                };
                
                state.votor_voted_blocks
                    .entry(validator)
                    .or_default()
                    .entry(view)
                    .or_default()
                    .insert(new_block);
            },
            VotorAction::CastVote { validator, block, view } => {
                let vote = Vote {
                    voter: validator,
                    slot: block.slot,
                    view,
                    block: block.hash,
                    vote_type: VoteType::Commit,
                    signature: validator as u64, // Simplified signature
                    timestamp: state.clock,
                };
                
                state.votor_received_votes
                    .entry(validator)
                    .or_default()
                    .entry(view)
                    .or_default()
                    .insert(vote);
                    
                state.votor_voted_blocks
                    .entry(validator)
                    .or_default()
                    .entry(view)
                    .or_default()
                    .insert(block);
            },
            VotorAction::CollectVotes { validator, view } => {
                if let Some(votes) = state.votor_received_votes.get(&validator).and_then(|v| v.get(&view)) {
                    let voted_stake: StakeAmount = votes.iter()
                        .map(|vote| self.config.stake_distribution.get(&vote.voter).copied().unwrap_or(0))
                        .sum();
                    
                    if voted_stake >= self.config.slow_path_threshold && !votes.is_empty() {
                        let first_vote = votes.iter().next().unwrap();
                        let cert_type = if voted_stake >= self.config.fast_path_threshold {
                            CertificateType::Fast
                        } else {
                            CertificateType::Slow
                        };
                        
                        let certificate = Certificate {
                            slot: first_vote.slot,
                            view,
                            block: first_vote.block,
                            cert_type,
                            validators: votes.iter().map(|v| v.voter).collect(),
                            stake: voted_stake,
                            signatures: AggregatedSignature {
                                signers: votes.iter().map(|v| v.voter).collect(),
                                message: first_vote.block,
                                signatures: votes.iter().map(|v| v.signature).collect(),
                                valid: true,
                            },
                        };
                        
                        state.votor_generated_certs
                            .entry(view)
                            .or_default()
                            .insert(certificate);
                    }
                }
            },
            VotorAction::FinalizeBlock { validator: _, certificate } => {
                // Find the block to finalize
                if let Some(block) = state.votor_voted_blocks.values()
                    .flat_map(|view_blocks| view_blocks.values())
                    .flat_map(|blocks| blocks.iter())
                    .find(|b| b.hash == certificate.block) {
                    
                    state.votor_finalized_chain.push(block.clone());
                    state.finalized_blocks
                        .entry(certificate.slot)
                        .or_default()
                        .insert(block.clone());
                    state.finalized_by_slot
                        .entry(certificate.slot)
                        .or_default()
                        .insert(block.clone());
                }
            },
            VotorAction::SubmitSkipVote { validator, view } => {
                let skip_vote = Vote {
                    voter: validator,
                    slot: view,
                    view,
                    block: 0, // No block for skip
                    vote_type: VoteType::Skip,
                    signature: validator as u64,
                    timestamp: state.clock,
                };
                
                state.votor_skip_votes
                    .entry(validator)
                    .or_default()
                    .entry(view)
                    .or_default()
                    .insert(skip_vote);
                    
                // Advance view
                state.votor_view.insert(validator, view + 1);
                let new_timeout = state.clock + self.config.timeout_delta * (2_u64.pow((view + 1) as u32));
                state.votor_timeout_expiry.insert(validator, new_timeout);
            },
            VotorAction::CollectSkipVotes { validator, view } => {
                if let Some(skip_votes) = state.votor_skip_votes.get(&validator).and_then(|v| v.get(&view)) {
                    let skip_stake: StakeAmount = skip_votes.iter()
                        .map(|vote| self.config.stake_distribution.get(&vote.voter).copied().unwrap_or(0))
                        .sum();
                    
                    if skip_stake >= (2 * self.config.total_stake) / 3 {
                        state.votor_view.insert(validator, view + 1);
                        let new_timeout = state.clock + self.config.timeout_delta * (2_u64.pow((view + 1) as u32));
                        state.votor_timeout_expiry.insert(validator, new_timeout);
                    }
                }
            },
            VotorAction::Timeout { validator } => {
                let current_view = state.votor_view.get(&validator).copied().unwrap_or(1);
                state.votor_view.insert(validator, current_view + 1);
                let new_timeout = state.clock + self.config.timeout_delta * (2_u64.pow((current_view + 1) as u32));
                state.votor_timeout_expiry.insert(validator, new_timeout);
            },
        }
        Ok(())
    }
    
    /// Execute a Rotor action
    fn execute_rotor_action(&self, state: &mut AlpenglowState, action: RotorAction) -> AlpenglowResult<()> {
        match action {
            RotorAction::ShredAndDistribute { leader: _, block } => {
                let shreds = self.erasure_encode(&block);
                let assignments = self.assign_pieces_to_relays(&shreds);
                
                let mut block_shreds = HashMap::new();
                for validator in 0..self.config.validator_count {
                    let validator_id = validator as ValidatorId;
                    let assigned_indices = assignments.get(&validator_id).cloned().unwrap_or_default();
                    let validator_shreds: HashSet<_> = shreds.iter()
                        .filter(|s| assigned_indices.contains(&s.index))
                        .cloned()
                        .collect();
                    block_shreds.insert(validator_id, validator_shreds);
                }
                
                state.rotor_block_shreds.insert(block.hash, block_shreds);
                state.rotor_relay_assignments = assignments;
            },
            RotorAction::RelayShreds { validator, block_id } => {
                if let Some(block_shreds) = state.rotor_block_shreds.get_mut(&block_id) {
                    if let Some(my_shreds) = block_shreds.get(&validator).cloned() {
                        // Relay to other validators
                        for other_validator in 0..self.config.validator_count {
                            let other_id = other_validator as ValidatorId;
                            if other_id != validator {
                                block_shreds.entry(other_id).or_default().extend(my_shreds.iter().cloned());
                            }
                        }
                    }
                }
            },
            RotorAction::AttemptReconstruction { validator, block_id } => {
                if let Some(pieces) = state.rotor_block_shreds.get(&block_id).and_then(|bs| bs.get(&validator)) {
                    if pieces.len() >= self.config.k as usize {
                        let reconstructed_block = self.reconstruct_block(pieces);
                        state.rotor_delivered_blocks
                            .entry(validator)
                            .or_default()
                            .insert(block_id);
                        state.rotor_reconstructed_blocks
                            .entry(validator)
                            .or_default()
                            .insert(reconstructed_block.clone());
                        state.delivered_blocks.insert(reconstructed_block);
                    }
                }
            },
            RotorAction::RequestRepair { validator, block_id } => {
                if let Some(pieces) = state.rotor_block_shreds.get(&block_id).and_then(|bs| bs.get(&validator)) {
                    let current_indices: HashSet<_> = pieces.iter().map(|p| p.index).collect();
                    let needed_indices: HashSet<_> = (1..=self.config.k).filter(|i| !current_indices.contains(i)).collect();
                    
                    if !needed_indices.is_empty() {
                        let repair_request = RepairRequest {
                            requester: validator,
                            block_id,
                            missing_indices: needed_indices,
                            timestamp: state.clock,
                        };
                        state.rotor_repair_requests.insert(repair_request);
                    }
                }
            },
            RotorAction::RespondToRepair { validator, request } => {
                if let Some(my_pieces) = state.rotor_block_shreds.get(&request.block_id).and_then(|bs| bs.get(&validator)) {
                    let requested_pieces: HashSet<_> = my_pieces.iter()
                        .filter(|p| request.missing_indices.contains(&p.index))
                        .cloned()
                        .collect();
                    
                    if !requested_pieces.is_empty() {
                        state.rotor_block_shreds
                            .entry(request.block_id)
                            .or_default()
                            .entry(request.requester)
                            .or_default()
                            .extend(requested_pieces);
                        state.rotor_repair_requests.remove(&request);
                    }
                }
            },
        }
        Ok(())
    }
    
    /// Execute a Network action
    fn execute_network_action(&self, state: &mut AlpenglowState, action: NetworkAction) -> AlpenglowResult<()> {
        match action {
            NetworkAction::DeliverMessage { message } => {
                state.network_message_queue.remove(&message);
                match message.recipient {
                    MessageRecipient::Validator(validator_id) => {
                        state.network_message_buffer
                            .entry(validator_id)
                            .or_default()
                            .insert(message);
                    },
                    MessageRecipient::Broadcast => {
                        for validator in 0..self.config.validator_count {
                            let validator_id = validator as ValidatorId;
                            state.network_message_buffer
                                .entry(validator_id)
                                .or_default()
                                .insert(message.clone());
                        }
                    },
                }
            },
            NetworkAction::DropMessage { message } => {
                state.network_message_queue.remove(&message);
                state.network_dropped_messages += 1;
            },
            NetworkAction::PartitionNetwork { partition } => {
                state.network_partitions.insert(partition);
            },
            NetworkAction::HealPartition => {
                state.network_partitions.clear();
            },
        }
        Ok(())
    }
    
    /// Execute a Byzantine action
    fn execute_byzantine_action(&self, state: &mut AlpenglowState, action: ByzantineAction) -> AlpenglowResult<()> {
        match action {
            ByzantineAction::DoubleVote { validator, view } => {
                // Create two conflicting votes
                let vote1 = Vote {
                    voter: validator,
                    slot: view,
                    view,
                    block: 1,
                    vote_type: VoteType::Commit,
                    signature: validator as u64,
                    timestamp: state.clock,
                };
                let vote2 = Vote {
                    voter: validator,
                    slot: view,
                    view,
                    block: 2,
                    vote_type: VoteType::Commit,
                    signature: validator as u64,
                    timestamp: state.clock,
                };
                
                // Deliver to all validators
                for other_validator in 0..self.config.validator_count {
                    let other_id = other_validator as ValidatorId;
                    state.votor_received_votes
                        .entry(other_id)
                        .or_default()
                        .entry(view)
                        .or_default()
                        .extend([vote1.clone(), vote2.clone()]);
                }
            },
            ByzantineAction::InvalidBlock { validator } => {
                let invalid_block = Block {
                    slot: state.current_slot,
                    view: state.votor_view.get(&validator).copied().unwrap_or(1),
                    hash: 999999, // Invalid hash
                    parent: 0,
                    proposer: validator,
                    transactions: HashSet::new(),
                    timestamp: state.clock,
                    signature: validator as u64,
                    data: vec![],
                };
                
                let current_view = state.votor_view.get(&validator).copied().unwrap_or(1);
                state.votor_voted_blocks
                    .entry(validator)
                    .or_default()
                    .entry(current_view)
                    .or_default()
                    .insert(invalid_block);
            },
            ByzantineAction::WithholdShreds { validator: _ } => {
                // Do nothing - withhold shreds by not relaying
            },
            ByzantineAction::Equivocate { validator } => {
                // Send conflicting messages
                let msg1 = NetworkMessage {
                    msg_type: MessageType::Vote,
                    sender: validator,
                    recipient: MessageRecipient::Broadcast,
                    payload: 1,
                    timestamp: state.clock,
                    signature: validator as u64,
                };
                let msg2 = NetworkMessage {
                    msg_type: MessageType::Vote,
                    sender: validator,
                    recipient: MessageRecipient::Broadcast,
                    payload: 2,
                    timestamp: state.clock,
                    signature: validator as u64,
                };
                
                state.network_message_queue.extend([msg1, msg2]);
            },
        }
        Ok(())
    }
    
    /// Check if validator is leader for view (stake-weighted selection)
    fn is_leader_for_view(&self, validator: ValidatorId, view: ViewNumber) -> bool {
        self.compute_leader_for_view(view) == validator
    }
    
    /// Compute leader for view using stake-weighted selection
    fn compute_leader_for_view(&self, view: ViewNumber) -> ValidatorId {
        let total_stake = self.config.total_stake;
        if total_stake == 0 {
            return 0;
        }
        
        let target = (view * total_stake) % total_stake;
        let mut cumulative_stake = 0;
        
        for validator in 0..self.config.validator_count {
            let validator_id = validator as ValidatorId;
            let stake = self.config.stake_distribution.get(&validator_id).copied().unwrap_or(0);
            cumulative_stake += stake;
            if cumulative_stake > target {
                return validator_id;
            }
        }
        
        0 // Fallback
    }
    
    /// Check if validator can reconstruct block
    fn can_reconstruct(&self, validator: ValidatorId, block_id: BlockHash) -> bool {
        self.state.rotor_block_shreds.get(&block_id)
            .and_then(|shreds| shreds.get(&validator))
            .map_or(false, |pieces| pieces.len() >= self.config.k as usize)
    }
    
    /// Erasure encode a block
    fn erasure_encode(&self, block: &Block) -> Vec<ErasureCodedPiece> {
        let mut shreds = Vec::new();
        
        // Data shreds (indices 1..K)
        for i in 1..=self.config.k {
            shreds.push(ErasureCodedPiece {
                block_id: block.hash,
                index: i,
                total_pieces: self.config.n,
                data: vec![block.hash, i as u64], // Simplified data
                is_parity: false,
                signature: block.signature,
            });
        }
        
        // Parity shreds (indices K+1..N)
        for i in (self.config.k + 1)..=self.config.n {
            shreds.push(ErasureCodedPiece {
                block_id: block.hash,
                index: i,
                total_pieces: self.config.n,
                data: vec![block.hash, i as u64], // Simplified parity
                is_parity: true,
                signature: block.signature,
            });
        }
        
        shreds
    }
    
    /// Assign pieces to relay validators
    fn assign_pieces_to_relays(&self, shreds: &[ErasureCodedPiece]) -> HashMap<ValidatorId, Vec<u32>> {
        let mut assignments = HashMap::new();
        
        for validator in 0..self.config.validator_count {
            let validator_id = validator as ValidatorId;
            let stake = self.config.stake_distribution.get(&validator_id).copied().unwrap_or(0);
            let pieces_count = if self.config.total_stake == 0 {
                1
            } else {
                ((stake * self.config.n as u64) / self.config.total_stake + 1) as usize
            };
            
            let assigned_indices: Vec<u32> = shreds.iter()
                .take(pieces_count)
                .map(|s| s.index)
                .collect();
            assignments.insert(validator_id, assigned_indices);
        }
        
        assignments
    }
    
    /// Reconstruct block from pieces
    fn reconstruct_block(&self, pieces: &HashSet<ErasureCodedPiece>) -> Block {
        let first_piece = pieces.iter().next().unwrap();
        Block {
            slot: 0, // Will be set from metadata
            view: 0, // Will be set from metadata
            hash: first_piece.block_id,
            parent: 0,
            proposer: 0,
            transactions: HashSet::new(),
            timestamp: 0,
            signature: first_piece.signature,
            data: vec![],
        }
    }
}

impl AlpenglowState {
    /// Initialize state - mirrors TLA+ Init
    pub fn init(config: &Config) -> Self {
        let mut votor_view = HashMap::new();
        let mut votor_voted_blocks = HashMap::new();
        let mut votor_skip_votes = HashMap::new();
        let mut votor_timeout_expiry = HashMap::new();
        let mut votor_received_votes = HashMap::new();
        let mut rotor_relay_assignments = HashMap::new();
        let mut rotor_reconstruction_state = HashMap::new();
        let mut rotor_delivered_blocks = HashMap::new();
        let mut rotor_bandwidth_usage = HashMap::new();
        let mut rotor_shred_assignments = HashMap::new();
        let mut rotor_received_shreds = HashMap::new();
        let mut rotor_reconstructed_blocks = HashMap::new();
        let mut network_message_buffer = HashMap::new();
        let mut failure_states = HashMap::new();
        let mut latency_metrics = HashMap::new();
        let mut bandwidth_metrics = HashMap::new();
        let mut finalized_blocks = HashMap::new();
        let mut finalized_by_slot = HashMap::new();
        
        // Initialize per-validator state
        for validator in 0..config.validator_count {
            let validator_id = validator as ValidatorId;
            votor_view.insert(validator_id, 1);
            votor_voted_blocks.insert(validator_id, HashMap::new());
            votor_skip_votes.insert(validator_id, HashMap::new());
            votor_timeout_expiry.insert(validator_id, config.timeout_delta);
            votor_received_votes.insert(validator_id, HashMap::new());
            rotor_relay_assignments.insert(validator_id, Vec::new());
            rotor_reconstruction_state.insert(validator_id, Vec::new());
            rotor_delivered_blocks.insert(validator_id, HashSet::new());
            rotor_bandwidth_usage.insert(validator_id, 0);
            rotor_shred_assignments.insert(validator_id, HashSet::new());
            rotor_received_shreds.insert(validator_id, HashSet::new());
            rotor_reconstructed_blocks.insert(validator_id, HashSet::new());
            network_message_buffer.insert(validator_id, HashSet::new());
            failure_states.insert(validator_id, ValidatorStatus::Honest);
            bandwidth_metrics.insert(validator_id, 0);
        }
        
        // Initialize per-slot state
        for slot in 1..=config.max_slot {
            latency_metrics.insert(slot, 0);
            finalized_blocks.insert(slot, HashSet::new());
            finalized_by_slot.insert(slot, HashSet::new());
        }
        
        Self {
            clock: 0,
            current_slot: 1,
            current_rotor: 0, // Initial leader
            votor_view,
            votor_voted_blocks,
            votor_generated_certs: HashMap::new(),
            votor_finalized_chain: Vec::new(),
            votor_skip_votes,
            votor_timeout_expiry,
            votor_received_votes,
            rotor_block_shreds: HashMap::new(),
            rotor_relay_assignments,
            rotor_reconstruction_state,
            rotor_delivered_blocks,
            rotor_repair_requests: HashSet::new(),
            rotor_bandwidth_usage,
            rotor_shred_assignments,
            rotor_received_shreds,
            rotor_reconstructed_blocks,
            network_message_queue: HashSet::new(),
            network_message_buffer,
            network_partitions: HashSet::new(),
            network_dropped_messages: 0,
            network_delivery_time: HashMap::new(),
            finalized_blocks,
            finalized_by_slot,
            delivered_blocks: HashSet::new(),
            messages: HashSet::new(),
            failure_states,
            nonce_counter: 0,
            latency_metrics,
            bandwidth_metrics,
        }
    }
    
    /// Get the latest finalized view
    pub fn latest_finalized_view(&self) -> ViewNumber {
        self.votor_finalized_chain.last().map_or(0, |block| block.view)
    }
}

impl Config {
    /// Create a new configuration with default values
    pub fn new() -> Self {
        Self {
            validator_count: 4,
            stake_distribution: HashMap::new(),
            total_stake: 0,
            fast_path_threshold: 0,
            slow_path_threshold: 0,
            byzantine_threshold: 0,
            max_network_delay: 100,
            gst: 1000,
            bandwidth_limit: 10_000_000,
            erasure_coding_rate: 0.5,
            max_block_size: 1_000_000,
            k: 2,
            n: 4,
            max_view: 10,
            max_slot: 10,
            timeout_delta: 100,
        }
    }
    
    /// Set the number of validators
    pub fn with_validators(mut self, count: usize) -> Self {
        self.validator_count = count;
        self.byzantine_threshold = if count > 0 { (count - 1) / 3 } else { 0 }; // Standard Byzantine threshold
        
        // Initialize equal stake distribution
        let stake_per_validator = 1000;
        self.total_stake = (count as u64) * stake_per_validator;
        
        self.stake_distribution.clear();
        for i in 0..count {
            self.stake_distribution.insert(i as ValidatorId, stake_per_validator);
        }
        
        self.fast_path_threshold = (self.total_stake * 80) / 100;
        self.slow_path_threshold = (self.total_stake * 60) / 100;
        
        self
    }
    
    /// Set the Byzantine threshold
    pub fn with_byzantine_threshold(mut self, threshold: usize) -> Self {
        self.byzantine_threshold = threshold;
        self
    }
    
    /// Set custom stake distribution
    pub fn with_stake_distribution(mut self, stakes: HashMap<ValidatorId, StakeAmount>) -> Self {
        self.total_stake = stakes.values().sum();
        self.fast_path_threshold = (self.total_stake * 80) / 100;
        self.slow_path_threshold = (self.total_stake * 60) / 100;
        self.stake_distribution = stakes;
        self
    }
    
    /// Set network timing parameters
    pub fn with_network_timing(mut self, max_delay: u64, gst: u64) -> Self {
        self.max_network_delay = max_delay;
        self.gst = gst;
        self
    }
    
    /// Set erasure coding parameters
    pub fn with_erasure_coding(mut self, k: u32, n: u32) -> Self {
        self.k = k;
        self.n = n;
        self
    }
    
    /// Validate the configuration
    pub fn validate(&self) -> Result<(), String> {
        if self.validator_count == 0 {
            return Err("Validator count must be positive".to_string());
        }
        
        if self.byzantine_threshold >= self.validator_count {
            return Err("Byzantine threshold must be less than validator count".to_string());
        }
        
        if self.stake_distribution.len() != self.validator_count {
            return Err("Stake distribution must match validator count".to_string());
        }
        
        if self.fast_path_threshold <= self.slow_path_threshold {
            return Err("Fast path threshold must be greater than slow path threshold".to_string());
        }
        
        if self.slow_path_threshold <= (self.total_stake * 50) / 100 {
            return Err("Slow path threshold must be greater than 50% of total stake".to_string());
        }
        
        if self.n <= self.k {
            return Err("N must be greater than K for erasure coding".to_string());
        }
        
        if self.k < (2 * self.validator_count as u32) / 3 {
            return Err("K must be at least 2/3 of validator count".to_string());
        }
        
        Ok(())
    }
}

impl Default for Config {
    fn default() -> Self {
        Self::new().with_validators(4)
    }
}

/// Implement Model trait for AlpenglowModel to enable Stateright verification
impl Model for AlpenglowModel {
    type State = AlpenglowState;
    type Action = AlpenglowAction;
    
    fn init_states(&self) -> Vec<Self::State> {
        vec![AlpenglowState::init(&self.config)]
    }
    
    fn actions(&self, state: &Self::State, actions: &mut Vec<Self::Action>) {
        // Add all enabled actions
        
        // Clock and slot advancement
        actions.push(AlpenglowAction::AdvanceClock);
        
        if state.finalized_blocks.get(&state.current_slot).map_or(false, |blocks| !blocks.is_empty()) &&
           state.current_slot < self.config.max_slot {
            actions.push(AlpenglowAction::AdvanceSlot);
        }
        
        // Per-validator actions
        for validator in 0..self.config.validator_count {
            let validator_id = validator as ValidatorId;
            let current_view = state.votor_view.get(&validator_id).copied().unwrap_or(1);
            let timeout_expiry = state.votor_timeout_expiry.get(&validator_id).copied().unwrap_or(0);
            
            // View advancement
            if current_view < self.config.max_view && state.clock >= timeout_expiry {
                actions.push(AlpenglowAction::AdvanceView { validator: validator_id });
            }
            
            // Votor actions
            if current_view == state.votor_view.get(&validator_id).copied().unwrap_or(1) &&
               self.is_leader_for_view(validator_id, current_view) {
                actions.push(AlpenglowAction::Votor(VotorAction::ProposeBlock {
                    validator: validator_id,
                    view: current_view,
                }));
            }
            
            // Add other Votor actions
            actions.push(AlpenglowAction::Votor(VotorAction::CollectVotes {
                validator: validator_id,
                view: current_view,
            }));
            
            if state.clock >= timeout_expiry {
                actions.push(AlpenglowAction::Votor(VotorAction::SubmitSkipVote {
                    validator: validator_id,
                    view: current_view,
                }));
            }
            
            // Rotor actions
            for block_id in state.rotor_block_shreds.keys() {
                if self.can_reconstruct(validator_id, *block_id) &&
                   !state.rotor_delivered_blocks.get(&validator_id)
                       .map_or(false, |delivered| delivered.contains(block_id)) {
                    actions.push(AlpenglowAction::Rotor(RotorAction::AttemptReconstruction {
                        validator: validator_id,
                        block_id: *block_id,
                    }));
                }
                
                if !self.can_reconstruct(validator_id, *block_id) &&
                   !state.rotor_delivered_blocks.get(&validator_id)
                       .map_or(false, |delivered| delivered.contains(block_id)) {
                    actions.push(AlpenglowAction::Rotor(RotorAction::RequestRepair {
                        validator: validator_id,
                        block_id: *block_id,
                    }));
                }
            }
            
            // Byzantine actions for Byzantine validators
            if matches!(state.failure_states.get(&validator_id), Some(ValidatorStatus::Byzantine)) {
                actions.push(AlpenglowAction::Byzantine(ByzantineAction::DoubleVote {
                    validator: validator_id,
                    view: current_view,
                }));
                
                actions.push(AlpenglowAction::Byzantine(ByzantineAction::InvalidBlock {
                    validator: validator_id,
                }));
            }
        }
        
        // Network actions
        for message in &state.network_message_queue {
            actions.push(AlpenglowAction::Network(NetworkAction::DeliverMessage {
                message: message.clone(),
            }));
            
            actions.push(AlpenglowAction::Network(NetworkAction::DropMessage {
                message: message.clone(),
            }));
        }
        
        if !state.network_partitions.is_empty() {
            actions.push(AlpenglowAction::Network(NetworkAction::HealPartition));
        }
    }
    
    fn next_state(&self, state: &Self::State, action: Self::Action) -> Option<Self::State> {
        // Create a temporary model with the current state
        let temp_model = AlpenglowModel {
            config: self.config.clone(),
            state: state.clone(),
        };
        
        temp_model.execute_action(action).ok()
    }
}

/// Common error types for the Alpenglow protocol
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum AlpenglowError {
    /// Invalid configuration
    InvalidConfig(String),
    /// Protocol violation detected
    ProtocolViolation(String),
    /// Network error
    NetworkError(String),
    /// Byzantine behavior detected
    ByzantineDetected(String),
    /// Timeout occurred
    Timeout(String),
    /// General error
    Other(String),
}

impl From<String> for AlpenglowError {
    fn from(s: String) -> Self {
        AlpenglowError::Other(s)
    }
}

/// Result type for Alpenglow operations
pub type AlpenglowResult<T> = Result<T, AlpenglowError>;

/// Trait for protocol components that can be verified
pub trait Verifiable {
    /// Verify safety properties
    fn verify_safety(&self) -> AlpenglowResult<()>;
    
    /// Verify liveness properties
    fn verify_liveness(&self) -> AlpenglowResult<()>;
    
    /// Verify Byzantine resilience
    fn verify_byzantine_resilience(&self) -> AlpenglowResult<()>;
}

/// Trait for cross-validation with TLA+ specifications
pub trait TlaCompatible {
    /// Export state for TLA+ cross-validation
    fn export_tla_state(&self) -> serde_json::Value;
    
    /// Import state from TLA+ model checker
    fn import_tla_state(&mut self, state: serde_json::Value) -> AlpenglowResult<()>;
    
    /// Validate consistency with TLA+ invariants
    fn validate_tla_invariants(&self) -> AlpenglowResult<()>;
}

/// Main entry point for creating an Alpenglow protocol model
pub fn create_model(config: Config) -> AlpenglowResult<AlpenglowModel> {
    config.validate()?;
    Ok(AlpenglowModel::new(config))
}

/// Property checkers for formal verification
pub mod properties {
    use super::*;

    
    /// Safety property: No two conflicting blocks are finalized in the same slot
    pub fn safety_no_conflicting_finalization(state: &AlpenglowState) -> bool {
        // Check that at most one block is finalized per slot
        state.finalized_blocks.values().all(|blocks| blocks.len() <= 1)
    }
    
    /// Liveness property: Progress is eventually made
    pub fn liveness_eventual_progress(state: &AlpenglowState) -> bool {
        // Check that progress has been made (at least one block finalized)
        !state.votor_finalized_chain.is_empty()
    }
    
    /// Byzantine resilience: Protocol remains safe under Byzantine faults
    pub fn byzantine_resilience(state: &AlpenglowState, config: &Config) -> bool {
        let byzantine_count = state.failure_states.values()
            .filter(|status| matches!(status, ValidatorStatus::Byzantine))
            .count();
        
        // Safety should hold as long as Byzantine validators are less than 1/3
        byzantine_count < config.validator_count / 3
    }
    
    /// Certificate validity: All generated certificates are valid
    pub fn certificate_validity(state: &AlpenglowState, config: &Config) -> bool {
        state.votor_generated_certs.values()
            .flat_map(|certs| certs.iter())
            .all(|cert| {
                match cert.cert_type {
                    CertificateType::Fast => cert.stake >= config.fast_path_threshold,
                    CertificateType::Slow => cert.stake >= config.slow_path_threshold,
                    CertificateType::Skip => cert.stake >= config.slow_path_threshold,
                }
            })
    }
    
    /// Bandwidth safety: All validators respect bandwidth limits
    pub fn bandwidth_safety(state: &AlpenglowState, config: &Config) -> bool {
        state.rotor_bandwidth_usage.values()
            .all(|usage| *usage <= config.bandwidth_limit as u64)
    }
    
    /// Chain consistency: All honest validators agree on finalized chain
    pub fn chain_consistency(state: &AlpenglowState) -> bool {
        // For simplicity, check that there's a single finalized chain
        // In a full implementation, this would check agreement across validators
        state.finalized_blocks.values()
            .all(|blocks| blocks.len() <= 1)
    }
    
    /// Erasure coding validity: All shreds have valid indices
    pub fn erasure_coding_validity(state: &AlpenglowState, config: &Config) -> bool {
        state.rotor_block_shreds.values()
            .flat_map(|validator_shreds| validator_shreds.values())
            .flat_map(|shreds| shreds.iter())
            .all(|shred| {
                shred.index >= 1 && shred.index <= config.n &&
                shred.total_pieces == config.n &&
                (!shred.is_parity && shred.index <= config.k) ||
                (shred.is_parity && shred.index > config.k)
            })
    }
}

/// Utilities for cross-validation and testing
pub mod utils {
    use super::*;
    
    /// Generate test configurations for various scenarios
    pub fn test_configs() -> Vec<Config> {
        vec![
            Config::new().with_validators(3),
            Config::new().with_validators(4),
            Config::new().with_validators(7),
            Config::new().with_validators(10),
        ]
    }
    
    /// Create a configuration with Byzantine validators
    pub fn byzantine_config(total_validators: usize, byzantine_count: usize) -> Config {
        Config::new()
            .with_validators(total_validators)
            .with_byzantine_threshold(byzantine_count)
    }
    
    /// Create a configuration with unequal stake distribution
    pub fn unequal_stake_config() -> Config {
        let mut stakes = HashMap::new();
        stakes.insert(0, 4000); // 40% stake
        stakes.insert(1, 3000); // 30% stake
        stakes.insert(2, 2000); // 20% stake
        stakes.insert(3, 1000); // 10% stake
        
        Config::new()
            .with_validators(4)
            .with_stake_distribution(stakes)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_config_creation() {
        let config = Config::new().with_validators(4);
        assert_eq!(config.validator_count, 4);
        assert_eq!(config.byzantine_threshold, 1);
        assert!(config.validate().is_ok());
    }
    
    #[test]
    fn test_config_validation() {
        let invalid_config = Config {
            validator_count: 0,
            ..Default::default()
        };
        assert!(invalid_config.validate().is_err());
    }
    
    #[test]
    fn test_stake_thresholds() {
        let config = Config::new().with_validators(4);
        assert!(config.fast_path_threshold > config.slow_path_threshold);
        assert!(config.slow_path_threshold > config.total_stake / 2);
    }
    
    #[test]
    fn test_model_creation() {
        let config = Config::new().with_validators(3);
        let model = create_model(config);
        assert!(model.is_ok());
    }
    
    #[test]
    fn test_alpenglow_state_init() {
        let config = Config::new().with_validators(3);
        let state = AlpenglowState::init(&config);
        
        assert_eq!(state.clock, 0);
        assert_eq!(state.current_slot, 1);
        assert_eq!(state.votor_view.len(), 3);
        assert!(state.votor_finalized_chain.is_empty());
    }
    
    #[test]
    fn test_leader_selection() {
        let config = Config::new().with_validators(4);
        let model = AlpenglowModel::new(config);
        
        // Test deterministic leader selection
        let leader1 = model.compute_leader_for_view(1);
        let leader2 = model.compute_leader_for_view(1);
        assert_eq!(leader1, leader2);
        
        // Different views may have different leaders
        let leader_view2 = model.compute_leader_for_view(2);
        // Leaders can be the same or different, but selection should be deterministic
        assert_eq!(model.compute_leader_for_view(2), leader_view2);
    }
    
    #[test]
    fn test_erasure_encoding() {
        let config = Config::new().with_validators(4).with_erasure_coding(2, 4);
        let model = AlpenglowModel::new(config);
        
        let block = Block {
            slot: 1,
            view: 1,
            hash: 123,
            parent: 0,
            proposer: 0,
            transactions: HashSet::new(),
            timestamp: 0,
            signature: 456,
            data: vec![],
        };
        
        let shreds = model.erasure_encode(&block);
        assert_eq!(shreds.len(), 4);
        
        // Check data shreds
        let data_shreds: Vec<_> = shreds.iter().filter(|s| !s.is_parity).collect();
        assert_eq!(data_shreds.len(), 2);
        assert!(data_shreds.iter().all(|s| s.index <= 2));
        
        // Check parity shreds
        let parity_shreds: Vec<_> = shreds.iter().filter(|s| s.is_parity).collect();
        assert_eq!(parity_shreds.len(), 2);
        assert!(parity_shreds.iter().all(|s| s.index > 2));
    }
    
    #[test]
    fn test_action_execution() {
        let config = Config::new().with_validators(3);
        let model = AlpenglowModel::new(config);
        
        // Test clock advancement
        let new_state = model.execute_action(AlpenglowAction::AdvanceClock).unwrap();
        assert_eq!(new_state.clock, 1);
        
        // Test view advancement
        let validator = 0;
        let new_state = model.execute_action(AlpenglowAction::AdvanceView { validator }).unwrap();
        assert_eq!(new_state.votor_view.get(&validator).copied().unwrap_or(1), 2);
    }
    
    #[test]
    fn test_safety_properties() {
        let config = Config::new().with_validators(3);
        let state = AlpenglowState::init(&config);
        
        assert!(properties::safety_no_conflicting_finalization(&state));
        assert!(properties::chain_consistency(&state));
        assert!(properties::bandwidth_safety(&state, &config));
        assert!(properties::erasure_coding_validity(&state, &config));
    }
    
    #[test]
    fn test_byzantine_resilience() {
        let config = Config::new().with_validators(4).with_byzantine_threshold(1);
        let mut state = AlpenglowState::init(&config);
        
        // Mark one validator as Byzantine
        state.failure_states.insert(0, ValidatorStatus::Byzantine);
        
        assert!(properties::byzantine_resilience(&state, &config));
        
        // Mark too many validators as Byzantine
        state.failure_states.insert(1, ValidatorStatus::Byzantine);
        assert!(!properties::byzantine_resilience(&state, &config));
    }
    
    #[test]
    fn test_model_trait_implementation() {
        let config = Config::new().with_validators(3);
        let model = AlpenglowModel::new(config);
        
        // Test init_states
        let init_states = model.init_states();
        assert_eq!(init_states.len(), 1);
        assert_eq!(init_states[0].clock, 0);
        
        // Test actions
        let mut actions = Vec::new();
        model.actions(&init_states[0], &mut actions);
        assert!(!actions.is_empty());
        assert!(actions.contains(&AlpenglowAction::AdvanceClock));
        
        // Test next_state
        let next_state = model.next_state(&init_states[0], AlpenglowAction::AdvanceClock);
        assert!(next_state.is_some());
        assert_eq!(next_state.unwrap().clock, 1);
    }
}
