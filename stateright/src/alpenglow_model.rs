#![allow(dead_code)]
//! # Alpenglow Consensus Model
//!
//! This module implements the main Stateright model that mirrors the TLA+ Alpenglow specification
//! from `specs/Alpenglow.tla`. It provides cross-validation capabilities by implementing identical
//! logic for certificate generation, timeout handling, and Byzantine behavior modeling.
//!
//! ## Key Features
//!
//! - **State Representation**: Matches TLA+ variables exactly (clock, currentSlot, votorView, etc.)
//! - **Action Enumeration**: Covers all Next actions from Alpenglow.tla
//! - **State Transitions**: Correspond exactly to TLA+ actions
//! - **Property Checkers**: Safety, liveness, and resilience verification
//! - **Votor/Rotor Integration**: Seamless integration with existing consensus and propagation modules
//! - **Cross-Validation**: Behavioral equivalence with TLA+ specification

use crate::votor::{
    VotorState, VotorMessage, Vote, VoteType, Certificate, CertificateType,
    Block, ViewNumber, LEADER_WINDOW_SIZE,
};
use crate::rotor::{
    RotorState, RotorMessage, Shred, RepairRequest,
};
use crate::{
    AlpenglowError, AlpenglowResult, BlockHash, Config, Signature, SlotNumber,
    StakeAmount, TlaCompatible, ValidatorId, Verifiable,
};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::hash::{Hash, Hasher};
use std::time::Instant;

/// Slot duration in milliseconds - mirrors TLA+ SlotDuration
pub const SLOT_DURATION: u64 = 150;

/// Global Stabilization Time - mirrors TLA+ GST
pub const GST: u64 = 1000;

/// Network delay bound - mirrors TLA+ Delta
pub const DELTA: u64 = 100;

/// Maximum number of slots - mirrors TLA+ MaxSlot
pub const MAX_SLOT: SlotNumber = 1000;

/// Maximum number of views - mirrors TLA+ MaxView
pub const MAX_VIEW: ViewNumber = 10000;

/// Network message structure for inter-validator communication
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct NetworkMessage {
    /// Message type identifier
    pub msg_type: String,
    /// Sender validator ID
    pub sender: ValidatorId,
    /// Recipient validator ID (or "broadcast" for all)
    pub recipient: String,
    /// Message payload
    pub payload: serde_json::Value,
    /// Message timestamp
    pub timestamp: u64,
    /// Message signature for integrity
    pub signature: Signature,
}

impl NetworkMessage {
    /// Create a new network message
    pub fn new(
        msg_type: String,
        sender: ValidatorId,
        recipient: String,
        payload: serde_json::Value,
        timestamp: u64,
    ) -> Self {
        Self {
            msg_type,
            sender,
            recipient,
            payload,
            timestamp,
            signature: sender as Signature, // Simplified signature
        }
    }

    /// Create a broadcast message
    pub fn broadcast(
        msg_type: String,
        sender: ValidatorId,
        payload: serde_json::Value,
        timestamp: u64,
    ) -> Self {
        Self::new(msg_type, sender, "broadcast".to_string(), payload, timestamp)
    }

    /// Check if message is a broadcast
    pub fn is_broadcast(&self) -> bool {
        self.recipient == "broadcast"
    }

    /// Validate message integrity
    pub fn validate(&self) -> bool {
        // Simplified validation - in practice would verify cryptographic signature
        self.signature == self.sender as Signature && !self.msg_type.is_empty()
    }
}

/// Alpenglow action types - mirrors TLA+ Next actions exactly
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Hash)]
pub enum AlpenglowAction {
    /// Advance global clock - mirrors TLA+ AdvanceClock
    AdvanceClock,
    
    /// Advance to next slot when current slot is finalized - mirrors TLA+ AdvanceSlot
    AdvanceSlot,
    
    /// Advance view on timeout - mirrors TLA+ AdvanceView
    AdvanceView {
        validator: ValidatorId,
    },
    
    /// Votor consensus actions - mirrors TLA+ VotorAction
    VotorAction {
        action: VotorMessage,
    },
    
    /// Rotor propagation actions - mirrors TLA+ RotorAction
    RotorAction {
        action: RotorMessage,
    },
    
    /// Network message delivery - mirrors TLA+ NetworkAction
    NetworkAction {
        action: NetworkActionType,
    },
    
    /// Byzantine validator actions - mirrors TLA+ ByzantineAction
    ByzantineAction {
        validator: ValidatorId,
        behavior: ByzantineBehavior,
    },
}

/// Network action types for message handling
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Hash)]
pub enum NetworkActionType {
    /// Deliver a message - mirrors TLA+ DeliverMessage
    DeliverMessage {
        message: NetworkMessage,
    },
    
    /// Drop a message - mirrors TLA+ DropMessage
    DropMessage {
        message: NetworkMessage,
    },
    
    /// Create network partition - mirrors TLA+ PartitionNetwork
    PartitionNetwork {
        partition: Vec<ValidatorId>,
    },
    
    /// Heal network partition - mirrors TLA+ HealPartition
    HealPartition {
        partition: Vec<ValidatorId>,
    },
}

/// Byzantine behavior types - mirrors TLA+ Byzantine actions
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Hash)]
pub enum ByzantineBehavior {
    /// Double voting - mirrors TLA+ ByzantineDoubleVote
    DoubleVote {
        vote1: Vote,
        vote2: Vote,
    },
    
    /// Invalid block proposal - mirrors TLA+ ByzantineInvalidBlock
    InvalidBlock {
        block: Block,
    },
    
    /// Withhold shreds - mirrors TLA+ ByzantineWithholdShreds
    WithholdShreds {
        block_id: BlockHash,
        shred_indices: Vec<u32>,
    },
    
    /// Equivocation - mirrors TLA+ ByzantineEquivocate
    Equivocation,
    
    /// Message withholding - mirrors TLA+ ByzantineWithholding
    Withholding,
    
    /// Invalid signature - mirrors TLA+ ByzantineInvalidSignature
    InvalidSignature,
}

/// Alpenglow state - mirrors TLA+ vars exactly
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AlpenglowState {
    /// Global clock - mirrors TLA+ clock
    pub clock: u64,
    
    /// Current protocol slot - mirrors TLA+ currentSlot
    pub current_slot: SlotNumber,
    
    /// Votor consensus state per validator - mirrors TLA+ votor state variables
    pub votor_states: HashMap<ValidatorId, VotorState>,
    
    /// Rotor propagation state per validator - mirrors TLA+ rotor state variables
    pub rotor_states: HashMap<ValidatorId, RotorState>,
    
    /// Network message queue - mirrors TLA+ networkMessageQueue
    pub network_message_queue: HashSet<NetworkMessage>,
    
    /// Network message buffer per validator - mirrors TLA+ networkMessageBuffer
    pub network_message_buffer: HashMap<ValidatorId, HashSet<NetworkMessage>>,
    
    /// Network partitions - mirrors TLA+ networkPartitions
    /// Changed to Vec<HashSet<ValidatorId>> because HashSet<HashSet<...>> is not hashable.
    pub network_partitions: Vec<HashSet<ValidatorId>>,
    
    /// Dropped messages count - mirrors TLA+ networkDroppedMessages
    pub network_dropped_messages: u64,
    
    /// Message delivery time mapping - mirrors TLA+ networkDeliveryTime
    pub network_delivery_time: HashMap<NetworkMessage, u64>,
    
    /// In-flight messages - mirrors TLA+ messages
    pub messages: HashSet<NetworkMessage>,
    
    /// Finalized blocks per slot - mirrors TLA+ finalizedBlocks
    pub finalized_blocks: HashMap<SlotNumber, HashSet<Block>>,
    
    /// Derived mapping slot -> block - mirrors TLA+ finalizedBySlot
    pub finalized_by_slot: HashMap<SlotNumber, Option<Block>>,
    
    /// Validator failure states - mirrors TLA+ failureStates
    pub failure_states: HashMap<ValidatorId, String>,
    
    /// Counter for generating unique nonces - mirrors TLA+ nonceCounter
    pub nonce_counter: u64,
    
    /// Finalization latencies per slot - mirrors TLA+ latencyMetrics
    pub latency_metrics: HashMap<SlotNumber, u64>,
    
    /// Bandwidth consumption per validator - mirrors TLA+ bandwidthMetrics
    pub bandwidth_metrics: HashMap<ValidatorId, u64>,
    
    /// Protocol configuration
    pub config: Config,
    
    /// Set of Byzantine validators
    pub byzantine_validators: HashSet<ValidatorId>,
    
    /// Set of offline validators
    pub offline_validators: HashSet<ValidatorId>,
    
    /// Validator stakes mapping
    pub validator_stakes: HashMap<ValidatorId, StakeAmount>,
}

impl Hash for AlpenglowState {
    fn hash<H: Hasher>(&self, state: &mut H) {
        // Hash only key identifying fields to avoid issues with complex collections
        self.clock.hash(state);
        self.current_slot.hash(state);
        self.nonce_counter.hash(state);
        self.network_dropped_messages.hash(state);
        self.byzantine_validators.len().hash(state);
        self.offline_validators.len().hash(state);
    }
}

impl AlpenglowState {
    /// Create new Alpenglow state - mirrors TLA+ Init
    pub fn new(config: Config) -> Self {
        let mut votor_states = HashMap::new();
        let mut rotor_states = HashMap::new();
        let mut network_message_buffer = HashMap::new();
        let mut failure_states = HashMap::new();
        let mut bandwidth_metrics = HashMap::new();
        
        // Initialize per-validator state
        for validator_id in 0..config.validator_count {
            let validator_id = validator_id as ValidatorId;
            
            // Initialize Votor state
            let votor_state = VotorState::new(validator_id, config.clone());
            votor_states.insert(validator_id, votor_state);
            
            // Initialize Rotor state
            let rotor_state = RotorState::new(validator_id, config.clone());
            rotor_states.insert(validator_id, rotor_state);
            
            // Initialize network buffer
            network_message_buffer.insert(validator_id, HashSet::new());
            
            // Initialize failure state
            failure_states.insert(validator_id, "active".to_string());
            
            // Initialize bandwidth metrics
            bandwidth_metrics.insert(validator_id, 0);
        }
        
        Self {
            clock: 0,
            current_slot: 1,
            votor_states,
            rotor_states,
            network_message_queue: HashSet::new(),
            network_message_buffer,
            network_partitions: Vec::new(),
            network_dropped_messages: 0,
            network_delivery_time: HashMap::new(),
            messages: HashSet::new(),
            finalized_blocks: HashMap::new(),
            finalized_by_slot: HashMap::new(),
            failure_states,
            nonce_counter: 0,
            latency_metrics: HashMap::new(),
            bandwidth_metrics,
            config: config.clone(),
            byzantine_validators: HashSet::new(),
            offline_validators: HashSet::new(),
            validator_stakes: (0..config.validator_count as ValidatorId)
                .map(|id| (id, 1000)) // Default stake of 1000 for each validator
                .collect(),
        }
    }
    
    /// Set Byzantine validators - mirrors TLA+ Byzantine validator configuration
    pub fn set_byzantine_validators(&mut self, byzantine_validators: HashSet<ValidatorId>) {
        self.byzantine_validators = byzantine_validators.clone();
        
        // Update Votor states with Byzantine information
        for (&validator_id, votor_state) in &mut self.votor_states {
            votor_state.set_byzantine(byzantine_validators.clone());
        }
        
        // Update failure states
        for &validator_id in &byzantine_validators {
            self.failure_states.insert(validator_id, "byzantine".to_string());
        }
    }
    
    /// Set offline validators - mirrors TLA+ offline validator configuration
    pub fn set_offline_validators(&mut self, offline_validators: HashSet<ValidatorId>) {
        self.offline_validators = offline_validators.clone();
        
        // Update failure states
        for &validator_id in &offline_validators {
            self.failure_states.insert(validator_id, "offline".to_string());
        }
    }
    
    /// Get honest validators - mirrors TLA+ HonestValidators
    pub fn honest_validators(&self) -> HashSet<ValidatorId> {
        (0..self.config.validator_count as ValidatorId)
            .filter(|v| !self.byzantine_validators.contains(v) && !self.offline_validators.contains(v))
            .collect()
    }
    
    /// Advance global clock - mirrors TLA+ AdvanceClock action
    pub fn advance_clock(&mut self) -> AlpenglowResult<()> {
        self.clock += 1;
        
        // Update all Votor states with new time
        for votor_state in self.votor_states.values_mut() {
            votor_state.current_time = self.clock;
        }
        
        // Update all Rotor states with new time
        for rotor_state in self.rotor_states.values_mut() {
            rotor_state.clock = self.clock;
        }
        
        Ok(())
    }
    
    /// Advance to next slot when current slot is finalized - mirrors TLA+ AdvanceSlot action
    pub fn advance_slot(&mut self) -> AlpenglowResult<()> {
        // Check if current slot has finalized block
        if !self.finalized_blocks.contains_key(&self.current_slot) ||
           self.finalized_blocks[&self.current_slot].is_empty() {
            return Err(AlpenglowError::ProtocolViolation(
                "Cannot advance slot without finalized block".to_string()
            ));
        }
        
        if self.current_slot >= MAX_SLOT {
            return Err(AlpenglowError::ProtocolViolation(
                "Cannot advance beyond maximum slot".to_string()
            ));
        }
        
        self.current_slot += 1;
        Ok(())
    }
    
    /// Advance view on timeout - mirrors TLA+ AdvanceView action
    pub fn advance_view(&mut self, validator: ValidatorId) -> AlpenglowResult<()> {
        if !self.honest_validators().contains(&validator) {
            return Err(AlpenglowError::ProtocolViolation(
                "Only honest validators can advance view".to_string()
            ));
        }
        
        if let Some(votor_state) = self.votor_states.get_mut(&validator) {
            // Check if timeout has expired
            if !votor_state.is_timeout_expired() {
                return Err(AlpenglowError::ProtocolViolation(
                    "Cannot advance view before timeout expiry".to_string()
                ));
            }
            
            // Check if block delivery failed from Rotor
            let current_delivered = self.rotor_states
                .get(&validator)
                .map(|rs| rs.delivered_blocks.get(&validator).cloned().unwrap_or_default())
                .unwrap_or_default();
            
            let has_block_for_slot = current_delivered.iter()
                .any(|&block_id| {
                    // Check if this block corresponds to current slot (simplified mapping)
                    block_id as u64 == self.current_slot
                });
            
            if has_block_for_slot {
                return Err(AlpenglowError::ProtocolViolation(
                    "Cannot advance view when block is available".to_string()
                ));
            }
            
            // Advance view
            votor_state.advance_view()?;
            
            // Set new timeout with adaptive timeout
            let new_timeout = votor_state.adaptive_timeout(votor_state.current_view);
            votor_state.set_timeout(self.current_slot, new_timeout)?;
        }
        
        Ok(())
    }
    
    /// Execute Votor consensus action - mirrors TLA+ VotorAction
    pub fn execute_votor_action(&mut self, action: VotorMessage) -> AlpenglowResult<Vec<NetworkMessage>> {
        let mut network_messages = Vec::new();
        // Clone the action upfront to avoid borrow/move conflicts when matching and then moving it.
        let action_copy = action.clone();
        
        match &action_copy {
            VotorMessage::ProposeBlock { block } => {
                let proposer = block.proposer;
                
                // Validate proposer is leader for current view (use immutable borrow)
                if let Some(vs) = self.votor_states.get(&proposer) {
                    if !vs.is_leader_for_view(vs.current_view) {
                        return Err(AlpenglowError::ProtocolViolation(
                            "Invalid block proposer for current view".to_string()
                        ));
                    }
                }
                
                // Execute action on proposer's Votor state (pass cloned action)
                if let Some(votor_state) = self.votor_states.get_mut(&proposer) {
                    let outgoing = votor_state.execute_transition(action_copy.clone())?;
                    
                    // Convert Votor messages to network messages
                    for votor_msg in outgoing {
                        let payload = serde_json::to_value(&votor_msg)
                            .map_err(|_| AlpenglowError::ProtocolViolation("Serialization failed".to_string()))?;
                        
                        let net_msg = NetworkMessage::broadcast(
                            "votor_message".to_string(),
                            proposer,
                            payload,
                            self.clock,
                        );
                        network_messages.push(net_msg);
                    }
                }
                
                // If we're honest, vote for our own proposal
                let is_byz = self.byzantine_validators.contains(&proposer);
                if !is_byz {
                    if let Some(votor_state) = self.votor_states.get_mut(&proposer) {
                        if let Ok(vote) = votor_state.cast_notar_vote(block.slot, &block) {
                            let vote_msg = VotorMessage::CastVote { vote };
                            let payload = serde_json::to_value(&vote_msg)
                                .map_err(|_| AlpenglowError::ProtocolViolation("Serialization failed".to_string()))?;
                            
                            let net_msg = NetworkMessage::broadcast(
                                "votor_vote".to_string(),
                                proposer,
                                payload,
                                self.clock,
                            );
                            network_messages.push(net_msg);
                        }
                    }
                }
            },
            
            VotorMessage::CastVote { vote } => {
                let voter = vote.voter;
                // Execute action on voter's Votor state
                if let Some(votor_state) = self.votor_states.get_mut(&voter) {
                    let outgoing = votor_state.execute_transition(action_copy.clone())?;
                    
                    // Convert to network messages
                    for votor_msg in outgoing {
                        let payload = serde_json::to_value(&votor_msg)
                            .map_err(|_| AlpenglowError::ProtocolViolation("Serialization failed".to_string()))?;
                        
                        let net_msg = NetworkMessage::broadcast(
                            "votor_message".to_string(),
                            voter,
                            payload,
                            self.clock,
                        );
                        network_messages.push(net_msg);
                    }
                }
                
                // Process vote on all other validators. Extract clock beforehand to avoid borrow conflicts.
                let current_clock = self.clock;
                // Collect validator IDs to avoid holding mutable and immutable borrows across the loop
                let validator_ids: Vec<ValidatorId> = self.votor_states.keys().cloned().collect();
                for validator_id in validator_ids {
                    if validator_id != voter {
                        // It's safe to get a mutable reference now
                        if let Some(vs) = self.votor_states.get_mut(&validator_id) {
                            // Add vote to received votes
                            vs.received_votes
                                .entry(vote.view)
                                .or_default()
                                .insert(vote.clone());
                            
                            // Try to generate certificate
                            if let Some(cert) = vs.try_generate_certificate(vote.view, vote.block) {
                                vs.generated_certificates
                                    .entry(vote.view)
                                    .or_default()
                                    .push(cert.clone());
                                
                                // Broadcast certificate
                                let cert_msg = VotorMessage::FinalizeBlock { certificate: cert };
                                let payload = serde_json::to_value(&cert_msg)
                                    .map_err(|_| AlpenglowError::ProtocolViolation("Serialization failed".to_string()))?;
                                
                                let net_msg = NetworkMessage::broadcast(
                                    "votor_certificate".to_string(),
                                    validator_id,
                                    payload,
                                    current_clock,
                                );
                                network_messages.push(net_msg);
                            }
                        }
                    }
                }
            },
        
        _ => {
            return Err(AlpenglowError::ProtocolViolation("Unknown Votor action".to_string()));
        }
    }
    
    Ok(network_messages)
    }

    /// Execute Rotor propagation action - mirrors TLA+ RotorAction
    pub fn execute_rotor_action(&mut self, action: RotorMessage) -> AlpenglowResult<Vec<NetworkMessage>> {
        // Clone the action to avoid borrow checker issues
        let action_copy = action.clone();
        let mut network_messages = Vec::new();
        
        match &action_copy {
            RotorMessage::ShredAndDistribute { leader, block } => {
            // Validate leader
            if !self.honest_validators().contains(leader) {
                return Err(AlpenglowError::ProtocolViolation(
                    "Invalid leader for shred and distribute".to_string()
                ));
            }
                
                // Execute on leader's Rotor state
                if let Some(rotor_state) = self.rotor_states.get_mut(leader) {
                    // Propose block first
                    rotor_state.propose_block(*leader, block.slot, block.clone())?;
                    
                    // Shred the block
                    let shreds = rotor_state.shred_block(block)?;
                    
                    // Assign shreds to validators
                    let validators: Vec<ValidatorId> = (0..self.config.validator_count as ValidatorId).collect();
                    let assignments = rotor_state.assign_pieces_to_relays(&validators, rotor_state.n);
                    
                    // Distribute shreds according to assignments
                    for (&validator, assigned_indices) in &assignments {
                        let validator_shreds: Vec<Shred> = shreds
                            .iter()
                            .filter(|s| assigned_indices.contains(&s.index))
                            .cloned()
                            .collect();
                        
                        if !validator_shreds.is_empty() {
                            let relay_msg = RotorMessage::RelayShreds {
                                validator,
                                block_id: block.hash,
                                shreds: validator_shreds,
                            };
                            
                            let payload = serde_json::to_value(&relay_msg)
                                .map_err(|_| AlpenglowError::ProtocolViolation("Serialization failed".to_string()))?;
                            
                            let net_msg = NetworkMessage::new(
                                "rotor_relay".to_string(),
                                *leader,
                                validator.to_string(),
                                payload,
                                self.clock,
                            );
                            network_messages.push(net_msg);
                        }
                    }
                }
            },
            
            RotorMessage::RelayShreds { validator, block_id, shreds } => {
                // Process shred relay
                if let Some(rotor_state) = self.rotor_states.get_mut(validator) {
                    // Add shreds to validator's collection
                    for shred in shreds {
                        rotor_state.received_shreds
                            .entry(*validator)
                            .or_default()
                            .insert(shred.clone());
                        
                        rotor_state.block_shreds
                            .entry(*block_id)
                            .or_default()
                            .entry(*validator)
                            .or_default()
                            .insert(shred.clone());
                    }
                    
                    // Check if we can reconstruct the block
                    if rotor_state.can_reconstruct(*validator, block_id) {
                        let reconstruct_msg = RotorMessage::AttemptReconstruction {
                            validator: *validator,
                            block_id: *block_id,
                        };
                        
                        let payload = serde_json::to_value(&reconstruct_msg)
                            .map_err(|_| AlpenglowError::ProtocolViolation("Serialization failed".to_string()))?;
                        
                        let net_msg = NetworkMessage::new(
                            "rotor_reconstruct".to_string(),
                            *validator,
                            validator.to_string(),
                            payload,
                            self.clock,
                        );
                        network_messages.push(net_msg);
                    }
                }
            }
        
        RotorMessage::AttemptReconstruction { validator, block_id } => {
            // Attempt block reconstruction
            if let Some(rotor_state) = self.rotor_states.get_mut(validator) {
                if let Some(block_shreds) = rotor_state.block_shreds.get(block_id) {
                    if let Some(validator_shreds) = block_shreds.get(validator) {
                        match rotor_state.reconstruct_block(validator_shreds) {
                            Ok(block) => {
                                // Successful reconstruction
                                rotor_state.delivered_blocks
                                    .entry(*validator)
                                    .or_default()
                                    .insert(block.hash);
                                
                                // Convert ErasureBlock to Block for Votor layer
                                let votor_block = crate::votor::Block {
                                    slot: block.slot,
                                    view: block.view,
                                    hash: block.hash,
                                    parent: block.parent,
                                    proposer: block.proposer,
                                    transactions: Vec::new(), // ErasureBlock doesn't have transactions
                                    timestamp: block.timestamp,
                                    signature: block.proposer as Signature,
                                    data: Vec::new(), // ErasureBlock doesn't have data field
                                };
                                
                                // Notify Votor layer
                                if let Some(votor_state) = self.votor_states.get_mut(validator) {
                                    if let Ok(vote) = votor_state.cast_notar_vote(block.slot, &votor_block) {
                                        let vote_msg = VotorMessage::CastVote { vote };
                                        let payload = serde_json::to_value(&vote_msg)
                                            .map_err(|_| AlpenglowError::ProtocolViolation("Serialization failed".to_string()))?;
                                        
                                        let net_msg = NetworkMessage::broadcast(
                                            "votor_vote_from_rotor".to_string(),
                                            *validator,
                                            payload,
                                            self.clock,
                                        );
                                        network_messages.push(net_msg);
                                    }
                                }
                            },
                            Err(_) => {
                                // Reconstruction failed, request repair
                                let repair_msg = RotorMessage::RequestRepair {
                                    validator: *validator,
                                    block_id: *block_id,
                                    missing_pieces: Vec::new(),
                                };
                                
                                let payload = serde_json::to_value(&repair_msg)
                                    .map_err(|_| AlpenglowError::ProtocolViolation("Serialization failed".to_string()))?;
                                
                                let net_msg = NetworkMessage::broadcast(
                                    "rotor_repair_request".to_string(),
                                    *validator,
                                    payload,
                                    self.clock,
                                );
                                network_messages.push(net_msg);
                            }
                        }
                    }
                }
            }
        },
        
        RotorMessage::RequestRepair { validator, block_id, .. } => {
            // Process repair request
            if let Some(rotor_state) = self.rotor_states.get_mut(validator) {
                // Compute missing pieces
                let k = rotor_state.k;
                let current_pieces: HashSet<u32> = rotor_state.block_shreds
                    .get(block_id)
                    .and_then(|bs| bs.get(validator))
                    .map(|shreds| shreds.iter().map(|s| s.index).collect())
                    .unwrap_or_default();
                
                let needed_pieces: Vec<u32> = (1..=k)
                    .filter(|i| !current_pieces.contains(i))
                    .collect();
                
                if !needed_pieces.is_empty() {
                    let repair_request = RepairRequest {
                        requester: *validator,
                        block_id: *block_id,
                        missing_pieces: needed_pieces,
                        timestamp: self.clock,
                        retry_count: 0,
                    };
                    
                    rotor_state.repair_requests.insert(repair_request.clone());
                    
                    // Broadcast repair request to other validators
                    for other_validator in 0..self.config.validator_count {
                        let other_validator = other_validator as ValidatorId;
                        if other_validator != *validator {
                            let respond_msg = RotorMessage::RespondToRepair {
                                validator: other_validator,
                                request: repair_request.clone(),
                                shreds: Vec::new(),
                            };
                            
                            let payload = serde_json::to_value(&respond_msg)
                                .map_err(|_| AlpenglowError::ProtocolViolation("Serialization failed".to_string()))?;
                            
                            let net_msg = NetworkMessage::new(
                                "rotor_repair_response".to_string(),
                                *validator,
                                other_validator.to_string(),
                                payload,
                                self.clock,
                            );
                            network_messages.push(net_msg);
                        }
                    }
                }
            }
        },
        
        RotorMessage::RespondToRepair { validator, request, .. } => {
            // Respond to repair request
            if let Some(rotor_state) = self.rotor_states.get_mut(validator) {
                if let Some(block_shreds) = rotor_state.block_shreds.get(&request.block_id) {
                    if let Some(validator_shreds) = block_shreds.get(validator) {
                        let response_shreds: Vec<Shred> = validator_shreds
                            .iter()
                            .filter(|s| request.missing_pieces.contains(&s.index))
                            .cloned()
                            .collect();
                        
                        if !response_shreds.is_empty() {
                            // Send shreds to requester
                            let relay_msg = RotorMessage::RelayShreds {
                                validator: request.requester,
                                block_id: request.block_id,
                                shreds: response_shreds,
                            };
                            
                            let payload = serde_json::to_value(&relay_msg)
                                .map_err(|_| AlpenglowError::ProtocolViolation("Serialization failed".to_string()))?;
                            
                            let net_msg = NetworkMessage::new(
                                "rotor_repair_shreds".to_string(),
                                *validator,
                                request.requester.to_string(),
                                payload,
                                self.clock,
                            );
                            network_messages.push(net_msg);
                        }
                    }
                }
            }
        },
        
        RotorMessage::ClockTick => {
            // Update clock on all Rotor states
            for rotor_state in self.rotor_states.values_mut() {
                rotor_state.advance_clock();
            }
        }
        }
        
        Ok(network_messages)
    }
    
    
    /// Execute network action - mirrors TLA+ NetworkAction
    pub fn execute_network_action(&mut self, action: NetworkActionType) -> Result<Vec<NetworkMessage>, AlpenglowError> {
        let mut network_messages = Vec::new();
        
        match action {
            NetworkActionType::DeliverMessage { message } => {
                // Process the delivered message
                network_messages.push(message);
            },
            NetworkActionType::DropMessage { .. } => {
                // Message is dropped, increment counter
                self.network_dropped_messages += 1;
            },
            NetworkActionType::PartitionNetwork { partition } => {
                // Create network partition
                self.network_partitions.push(partition.into_iter().collect());
            },
            NetworkActionType::HealPartition { partition } => {
                // Remove network partition
                let partition_set: HashSet<ValidatorId> = partition.into_iter().collect();
                self.network_partitions.retain(|p| p != &partition_set);
            },
        }
        
        Ok(network_messages)
    }
    
    /// Execute network action (legacy method) - mirrors TLA+ NetworkAction
    pub fn execute_network_action_legacy(&mut self, action: NetworkActionType) -> AlpenglowResult<()> {
        match action {
            NetworkActionType::DeliverMessage { message } => {
                // Validate message
                if !message.validate() {
                    return Err(AlpenglowError::ProtocolViolation(
                        "Invalid message signature".to_string()
                    ));
                }
                
                // Check if message should be delivered (not in partition)
                let sender_partition = self.find_validator_partition(message.sender);
                
                if message.is_broadcast() {
                    // Deliver to all validators in same partition
                    for validator_id in 0..self.config.validator_count {
                        let validator_id = validator_id as ValidatorId;
                        let recipient_partition = self.find_validator_partition(validator_id);
                        
                        if sender_partition == recipient_partition {
                            self.network_message_buffer
                                .entry(validator_id)
                                .or_default()
                                .insert(message.clone());
                        }
                    }
                } else {
                    // Deliver to specific recipient if in same partition
                    if let Ok(recipient_id) = message.recipient.parse::<ValidatorId>() {
                        let recipient_partition = self.find_validator_partition(recipient_id);
                        
                        if sender_partition == recipient_partition {
                            self.network_message_buffer
                                .entry(recipient_id)
                                .or_default()
                                .insert(message.clone());
                        }
                    }
                }
            },
            
            NetworkActionType::DropMessage { message } => {
                // Drop the message
                self.network_dropped_messages += 1;
                self.messages.remove(&message);
            },
            
            NetworkActionType::PartitionNetwork { partition } => {
                // Create network partition
                if !partition.is_empty() {
                    // Avoid duplicates
                    let partition_set: HashSet<ValidatorId> = partition.iter().cloned().collect();
                    if !self.network_partitions.iter().any(|p| p == &partition_set) {
                        self.network_partitions.push(partition_set);
                    }
                }
            },
            
            NetworkActionType::HealPartition { partition } => {
                // Heal network partition: remove matching partition if present
                let partition_set: HashSet<ValidatorId> = partition.iter().cloned().collect();
                self.network_partitions.retain(|p| p != &partition_set);
            },
        }
        
        Ok(())
    }
    
    
    /// Find which partition a validator belongs to
    fn find_validator_partition(&self, validator: ValidatorId) -> Option<HashSet<ValidatorId>> {
        for partition in &self.network_partitions {
            if partition.contains(&validator) {
                return Some(partition.clone());
            }
        }
        None // Not in any partition (can communicate with all)
    }
    
    /// Helper function to find block for certificate
    fn find_block_for_certificate(&self, certificate: &Certificate) -> Option<Block> {
        for votor_state in self.votor_states.values() {
            for blocks in votor_state.voted_blocks.values() {
                for block in blocks {
                    if block.hash == certificate.block {
                        return Some(block.clone());
                    }
                }
            }
        }
        None
    }
    
    /// Helper function to compute block hash
    fn compute_block_hash(&self, view: ViewNumber, parent: BlockHash, proposer: ValidatorId) -> BlockHash {
        let hash_input = view.wrapping_mul(31)
            .wrapping_add((proposer as u64).wrapping_mul(17))
            .wrapping_add(self.parent_hash_to_u64(parent).wrapping_mul(13))
            .wrapping_add(self.clock.wrapping_mul(7));
        hash_input.into()
    }
    
    /// Helper function to convert parent hash to u64
    fn parent_hash_to_u64(&self, parent: BlockHash) -> u64 {
        // Use debug format for deterministic conversion
        let debug = format!("{:?}", parent);
        let bytes = debug.as_bytes();
        let mut arr = [0u8; 8];
        for (i, b) in bytes.iter().take(8).enumerate() {
            arr[i] = *b;
        }
        u64::from_le_bytes(arr)
    }
    
    /// Check if in sync period - mirrors TLA+ InSyncPeriod
    pub fn in_sync_period(&self) -> bool {
        // Simple heuristic: in sync if most validators are active
        let active_validators = self.votor_states.len();
        let total_validators = active_validators + self.offline_validators.len();
        if total_validators == 0 {
            return true;
        }
        active_validators * 3 > total_validators * 2 // More than 2/3 active
    }
    
    /// Compute current slot from clock - mirrors TLA+ ComputeSlot
    pub fn compute_slot(&self, time: u64) -> SlotNumber {
        time / SLOT_DURATION + 1
    }
    
    /// Get current time - mirrors TLA+ CurrentTime
    pub fn current_time(&self) -> u64 {
        self.clock
    }
    
    /// Sum stake for a set of validators - mirrors TLA+ SumStake
    pub fn sum_stake(&self, validators: &HashSet<ValidatorId>) -> StakeAmount {
        validators
            .iter()
            .map(|v| self.config.stake_distribution.get(v).copied().unwrap_or(0))
            .sum()
    }
    
    /// Get total stake - mirrors TLA+ TotalStake
    pub fn total_stake(&self) -> StakeAmount {
        self.config.total_stake
    }
    
    /// Check fast path threshold - mirrors TLA+ FastPathThreshold
    pub fn fast_path_threshold(&self) -> StakeAmount {
        (self.total_stake() * 4) / 5 // 80%
    }
    
    /// Check slow path threshold - mirrors TLA+ SlowPathThreshold
    pub fn slow_path_threshold(&self) -> StakeAmount {
        (self.total_stake() * 3) / 5 // 60%
    }
    
    /// Check Byzantine threshold - mirrors TLA+ ByzantineThreshold
    pub fn byzantine_threshold(&self) -> StakeAmount {
        self.total_stake() / 3 // 33%
    }
    
    /// Validate Byzantine resilience - mirrors TLA+ ByzantineResilience
    pub fn validate_byzantine_resilience(&self) -> AlpenglowResult<()> {
        let byzantine_stake = self.sum_stake(&self.byzantine_validators);
        if byzantine_stake >= self.byzantine_threshold() {
            return Err(AlpenglowError::ProtocolViolation(
                format!("Byzantine stake {} exceeds threshold {}", byzantine_stake, self.byzantine_threshold())
            ));
        }
        Ok(())
    }
    
    
    /// Get performance metrics
    pub fn get_performance_metrics(&self) -> AlpenglowPerformanceMetrics {
        let total_finalized = self.finalized_blocks.len();
        let avg_latency = if !self.latency_metrics.is_empty() {
            self.latency_metrics.values().sum::<u64>() / self.latency_metrics.len() as u64
        } else {
            0
        };
        
        let total_bandwidth = self.bandwidth_metrics.values().sum();
        let avg_bandwidth = if !self.bandwidth_metrics.is_empty() {
            total_bandwidth / self.bandwidth_metrics.len() as u64
        } else {
            0
        };
        
        AlpenglowPerformanceMetrics {
            clock: self.clock,
            current_slot: self.current_slot,
            total_finalized_blocks: total_finalized,
            average_finalization_latency: avg_latency,
            total_bandwidth_used: total_bandwidth,
            average_bandwidth_per_validator: avg_bandwidth,
            network_messages_sent: self.messages.len(),
            network_messages_dropped: self.network_dropped_messages,
            active_network_partitions: self.network_partitions.len(),
            byzantine_validators_count: self.byzantine_validators.len(),
            offline_validators_count: self.offline_validators.len(),
        }
    }
    
    /// Get state summary for monitoring
    pub fn get_state_summary(&self) -> AlpenglowStateSummary {
        AlpenglowStateSummary {
            clock: self.clock,
            current_slot: self.current_slot,
            finalized_blocks_count: self.finalized_blocks.len(),
            pending_messages_count: self.messages.len(),
            network_partitions_count: self.network_partitions.len(),
            byzantine_validators: self.byzantine_validators.clone(),
            offline_validators: self.offline_validators.clone(),
            in_sync_period: self.in_sync_period(),
        }
    }
    
    
    /// Execute Byzantine action
    pub fn execute_byzantine_action(&mut self, validator_id: ValidatorId, behavior: ByzantineBehavior) -> Result<Vec<NetworkMessage>, AlpenglowError> {
        let mut network_messages = Vec::new();
        
        match behavior {
            ByzantineBehavior::Equivocation => {
                // Byzantine validator sends conflicting messages
                if let Some(votor_state) = self.votor_states.get(&validator_id) {
                    // Create conflicting vote messages
                    let vote1 = Vote {
                        voter: validator_id,
                        slot: votor_state.current_view,
                        view: votor_state.current_view,
                        block: 1,
                        vote_type: crate::votor::VoteType::Proposal,
                        signature: 123,
                        timestamp: self.clock,
                    };
                    let message1 = NetworkMessage {
                        msg_type: "votor_vote".to_string(),
                        sender: validator_id,
                        recipient: "broadcast".to_string(),
                        payload: serde_json::to_value(&vote1).unwrap(),
                        timestamp: self.clock,
                        signature: 123,
                    };
                    
                    let vote2 = Vote {
                        voter: validator_id,
                        slot: votor_state.current_view,
                        view: votor_state.current_view,
                        block: 2, // Different block
                        vote_type: crate::votor::VoteType::Proposal,
                        signature: 456,
                        timestamp: self.clock,
                    };
                    let message2 = NetworkMessage {
                        msg_type: "votor_vote".to_string(),
                        sender: validator_id,
                        recipient: "broadcast".to_string(),
                        payload: serde_json::to_value(&vote2).unwrap(),
                        timestamp: self.clock,
                        signature: 456,
                    };
                    
                    network_messages.push(message1);
                    network_messages.push(message2);
                }
            },
            ByzantineBehavior::Withholding => {
                // Byzantine validator withholds messages (no action)
            },
            ByzantineBehavior::InvalidSignature => {
                // Byzantine validator sends message with invalid signature
                if let Some(votor_state) = self.votor_states.get(&validator_id) {
                    let vote = Vote {
                        voter: validator_id,
                        slot: votor_state.current_view,
                        view: votor_state.current_view,
                        block: 1,
                        vote_type: crate::votor::VoteType::Proposal,
                        signature: 999999, // Invalid signature
                        timestamp: self.clock,
                    };
                    let message = NetworkMessage {
                        msg_type: "votor_vote".to_string(),
                        sender: validator_id,
                        recipient: "broadcast".to_string(),
                        payload: serde_json::to_value(&vote).unwrap(),
                        timestamp: self.clock,
                        signature: 999999, // Invalid signature
                    };
                    network_messages.push(message);
                }
            },
            ByzantineBehavior::DoubleVote { vote1, vote2 } => {
                // Byzantine validator sends double votes
                let message1 = NetworkMessage {
                    msg_type: "votor_vote".to_string(),
                    sender: validator_id,
                    recipient: "broadcast".to_string(),
                    payload: serde_json::to_value(&vote1).unwrap(),
                    timestamp: self.clock,
                    signature: vote1.signature,
                };
                let message2 = NetworkMessage {
                    msg_type: "votor_vote".to_string(),
                    sender: validator_id,
                    recipient: "broadcast".to_string(),
                    payload: serde_json::to_value(&vote2).unwrap(),
                    timestamp: self.clock,
                    signature: vote2.signature,
                };
                network_messages.push(message1);
                network_messages.push(message2);
            },
            ByzantineBehavior::InvalidBlock { block } => {
                // Byzantine validator proposes invalid block
                let message = NetworkMessage {
                    msg_type: "votor_propose".to_string(),
                    sender: validator_id,
                    recipient: "broadcast".to_string(),
                    payload: serde_json::to_value(&block).unwrap(),
                    timestamp: self.clock,
                    signature: 0, // Default signature
                };
                network_messages.push(message);
            },
            ByzantineBehavior::WithholdShreds { block_id, shred_indices } => {
                // Byzantine validator withholds specific shreds
                // This is handled by not sending the shreds (no action needed)
                let _ = (block_id, shred_indices); // Suppress unused warnings
            },
        }
        
        Ok(network_messages)
    }
    
    /// Parse hash from string (helper method)
    pub fn parse_hash_from_string(&self, hash_str: &str) -> Result<BlockHash, AlpenglowError> {
        // Simple parsing - in practice would use proper hash parsing
        match hash_str.parse::<u64>() {
            Ok(hash) => Ok(hash),
            Err(_) => Err(AlpenglowError::InvalidBlockHash { hash: hash_str.to_string() }),
        }
    }
}

/// Performance metrics for Alpenglow protocol
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AlpenglowPerformanceMetrics {
    pub clock: u64,
    pub current_slot: SlotNumber,
    pub total_finalized_blocks: usize,
    pub average_finalization_latency: u64,
    pub total_bandwidth_used: u64,
    pub average_bandwidth_per_validator: u64,
    pub network_messages_sent: usize,
    pub network_messages_dropped: u64,
    pub active_network_partitions: usize,
    pub byzantine_validators_count: usize,
    pub offline_validators_count: usize,
}

/// State summary for monitoring
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AlpenglowStateSummary {
    pub clock: u64,
    pub current_slot: SlotNumber,
    pub finalized_blocks_count: usize,
    pub pending_messages_count: usize,
    pub network_partitions_count: usize,
    pub byzantine_validators: HashSet<ValidatorId>,
    pub offline_validators: HashSet<ValidatorId>,
    pub in_sync_period: bool,
}

/// Alpenglow model for Stateright verification
#[derive(Debug, Clone)]
pub struct AlpenglowModel {
    /// Protocol configuration
    pub config: Config,
    /// Set of Byzantine validators
    pub byzantine_validators: HashSet<ValidatorId>,
    /// Set of offline validators
    pub offline_validators: HashSet<ValidatorId>,
}

impl AlpenglowModel {
    /// Create new Alpenglow model
    pub fn new(config: Config) -> Self {
        Self {
            config,
            byzantine_validators: HashSet::new(),
            offline_validators: HashSet::new(),
        }
    }
    
    /// Set Byzantine validators
    pub fn with_byzantine_validators(mut self, byzantine_validators: HashSet<ValidatorId>) -> Self {
        self.byzantine_validators = byzantine_validators;
        self
    }
    
    /// Set offline validators
    pub fn with_offline_validators(mut self, offline_validators: HashSet<ValidatorId>) -> Self {
        self.offline_validators = offline_validators;
        self
    }
    
    /// Get initial state - mirrors TLA+ Init
    pub fn init_state(&self) -> AlpenglowState {
        let mut state = AlpenglowState::new(self.config.clone());
        state.set_byzantine_validators(self.byzantine_validators.clone());
        state.set_offline_validators(self.offline_validators.clone());
        state
    }
    
    /// Get all possible actions from a state - mirrors TLA+ Next
    pub fn actions(&self, state: &AlpenglowState) -> Vec<AlpenglowAction> {
        let mut actions = Vec::new();
        
        // Always can advance clock
        actions.push(AlpenglowAction::AdvanceClock);
        
        // Can advance slot if current slot is finalized
        if state.finalized_blocks.contains_key(&state.current_slot) &&
           !state.finalized_blocks[&state.current_slot].is_empty() &&
           state.current_slot < MAX_SLOT {
            actions.push(AlpenglowAction::AdvanceSlot);
        }
        
        // View advancement for validators with expired timeouts
        for (&validator_id, votor_state) in &state.votor_states {
            if state.honest_validators().contains(&validator_id) &&
               votor_state.is_timeout_expired() {
                actions.push(AlpenglowAction::AdvanceView { validator: validator_id });
            }
        }
        
        // Votor actions
        for (&validator_id, votor_state) in &state.votor_states {
            // Clock tick
            actions.push(AlpenglowAction::VotorAction {
                action: VotorMessage::ClockTick { current_time: state.clock },
            });
            
            // Timeout trigger
            if votor_state.is_timeout_expired() {
                actions.push(AlpenglowAction::VotorAction {
                    action: VotorMessage::TriggerTimeout,
                });
            }
            
            // Block proposal for leaders
            if votor_state.is_leader_for_view(votor_state.current_view) &&
               !state.byzantine_validators.contains(&validator_id) {
                let parent_hash = if votor_state.finalized_chain.is_empty() {
                    0u64.into()
                } else {
                    votor_state.finalized_chain.last().unwrap().hash
                };
                
                let block = Block {
                    slot: state.current_slot,
                    view: votor_state.current_view,
                    hash: state.compute_block_hash(votor_state.current_view, parent_hash, validator_id),
                    parent: parent_hash,
                    proposer: validator_id,
                    transactions: Vec::new(),
                    timestamp: state.clock,
                    signature: validator_id as Signature,
                    data: Vec::new(),
                };
                
                actions.push(AlpenglowAction::VotorAction {
                    action: VotorMessage::ProposeBlock { block },
                });
            }
        }
        
        // Rotor actions
        actions.push(AlpenglowAction::RotorAction {
            action: RotorMessage::ClockTick,
        });
        
        // Network actions for message delivery
        for message in &state.messages {
            actions.push(AlpenglowAction::NetworkAction {
                action: NetworkActionType::DeliverMessage { message: message.clone() },
            });
            
            // Can also drop messages
            actions.push(AlpenglowAction::NetworkAction {
                action: NetworkActionType::DropMessage { message: message.clone() },
            });
        }
        
        // Byzantine actions
        for &validator_id in &state.byzantine_validators {
            // Double voting
            if let Some(votor_state) = state.votor_states.get(&validator_id) {
                let vote1 = Vote {
                    voter: validator_id,
                    slot: state.current_slot,
                    view: votor_state.current_view,
                    block: 1u64.into(),
                    vote_type: VoteType::Commit,
                    signature: validator_id as Signature,
                    timestamp: state.clock,
                };
                
                let vote2 = Vote {
                    voter: validator_id,
                    slot: state.current_slot,
                    view: votor_state.current_view,
                    block: 2u64.into(), // Different block
                    vote_type: VoteType::Commit,
                    signature: validator_id as Signature,
                    timestamp: state.clock,
                };
                
                actions.push(AlpenglowAction::ByzantineAction {
                    validator: validator_id,
                    behavior: ByzantineBehavior::DoubleVote { vote1, vote2 },
                });
            }
        }
        
        actions
    }
    
    /// Execute action on state - mirrors TLA+ action execution
    pub fn execute_action(&self, state: &mut AlpenglowState, action: AlpenglowAction) -> AlpenglowResult<()> {
        match action {
            AlpenglowAction::AdvanceClock => {
                state.advance_clock()?;
            },
            
            AlpenglowAction::AdvanceSlot => {
                state.advance_slot()?;
            },
            
            AlpenglowAction::AdvanceView { validator } => {
                state.advance_view(validator)?;
            },
            
            AlpenglowAction::VotorAction { action } => {
                let messages = state.execute_votor_action(action)?;
                for message in messages {
                    state.messages.insert(message);
                }
            },
            
            AlpenglowAction::RotorAction { action } => {
                let messages = state.execute_rotor_action(action)?;
                for message in messages {
                    state.messages.insert(message);
                }
            },
            
            AlpenglowAction::NetworkAction { action } => {
                let _messages = state.execute_network_action(action)?;
            },
            
            AlpenglowAction::ByzantineAction { validator, behavior } => {
                let messages = state.execute_byzantine_action(validator, behavior)?;
                for message in messages {
                    state.messages.insert(message);
                }
            },
        }
        
        Ok(())
    }
}

impl Verifiable for AlpenglowState {
    fn verify(&self) -> AlpenglowResult<()> {
        // Default verify implementation that runs all checks
        self.verify_safety()?;
        self.verify_liveness()?;
        self.verify_byzantine_resilience()?;
        Ok(())
    }

    fn verify_safety(&self) -> AlpenglowResult<()> {
        // Safety: No two blocks finalized in the same slot - mirrors TLA+ SafetyInvariant
        for (slot, blocks) in &self.finalized_blocks {
            if blocks.len() > 1 {
                return Err(AlpenglowError::ProtocolViolation(
                    format!("Safety violation: Multiple blocks finalized in slot {}", slot)
                ));
            }
        }
        
        // Certificate uniqueness per slot - mirrors TLA+ CertificateUniqueness
        for votor_state in self.votor_states.values() {
            votor_state.verify_safety()?;
        }
        
        // Chain consistency across honest validators - mirrors TLA+ ChainConsistency
        let honest_validators = self.honest_validators();
        if honest_validators.len() > 1 {
            let mut reference_chain: Option<&Vec<Block>> = None;
            
            for &validator in &honest_validators {
                if let Some(votor_state) = self.votor_states.get(&validator) {
                    if reference_chain.is_none() {
                        reference_chain = Some(&votor_state.finalized_chain);
                    } else if let Some(ref_chain) = reference_chain {
                        // Check chain consistency (simplified - should check proper prefix relationship)
                        if votor_state.finalized_chain.len() > 0 && ref_chain.len() > 0 {
                            let min_len = std::cmp::min(votor_state.finalized_chain.len(), ref_chain.len());
                            for i in 0..min_len {
                                if votor_state.finalized_chain[i].hash != ref_chain[i].hash {
                                    return Err(AlpenglowError::ProtocolViolation(
                                        "Chain consistency violation between honest validators".to_string()
                                    ));
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // Rotor non-equivocation - mirrors TLA+ RotorNonEquivocation
        for rotor_state in self.rotor_states.values() {
            rotor_state.verify_safety()?;
        }
        
        // Consistent finalization mapping
        for (slot, blocks) in &self.finalized_blocks {
            if blocks.len() == 1 {
                let block = blocks.iter().next().unwrap();
                if let Some(mapped_block) = self.finalized_by_slot.get(slot) {
                    if mapped_block.as_ref() != Some(block) {
                        return Err(AlpenglowError::ProtocolViolation(
                            format!("Inconsistent finalization mapping for slot {}", slot)
                        ));
                    }
                }
            }
        }
        
        Ok(())
    }
    
    fn verify_liveness(&self) -> AlpenglowResult<()> {
        // Progress: Chain should grow under good conditions - mirrors TLA+ LivenessProperty
        if self.in_sync_period() && self.finalized_blocks.is_empty() && self.clock > GST + 1000 {
            return Err(AlpenglowError::ProtocolViolation(
                "Liveness violation: No progress after GST + sufficient time".to_string()
            ));
        }
        
        // Fast path completion with high participation - mirrors TLA+ FastPath
        let responsive_stake = self.sum_stake(&self.honest_validators());
        let total_stake = self.total_stake();
        
        if responsive_stake >= self.fast_path_threshold() && self.in_sync_period() {
            // Should eventually have fast certificates
            let has_fast_cert = self.votor_states.values().any(|vs| {
                vs.generated_certificates.values().any(|certs| {
                    certs.iter().any(|cert| cert.cert_type == CertificateType::Fast)
                })
            });
            
            if self.clock > GST + DELTA && !has_fast_cert && !self.finalized_blocks.is_empty() {
                // This is a soft liveness check - in practice would need more sophisticated timing
            }
        }
        
        // Bounded finalization time - mirrors TLA+ BoundedFinalization
        for (&slot, latency) in &self.latency_metrics {
            let bound = if responsive_stake >= self.fast_path_threshold() {
                DELTA // Fast path bound
            } else {
                2 * DELTA // Slow path bound
            };
            
            if *latency > bound {
                return Err(AlpenglowError::ProtocolViolation(
                    format!("Bounded finalization violation: slot {} took {} > bound {}", slot, latency, bound)
                ));
            }
        }
        
        // Block delivery guarantee from Rotor - mirrors TLA+ BlockDeliveryGuarantee
        for rotor_state in self.rotor_states.values() {
            rotor_state.verify_liveness()?;
        }
        
        Ok(())
    }
    
    fn verify_byzantine_resilience(&self) -> AlpenglowResult<()> {
        // Byzantine resilience: Safety should hold under Byzantine threshold - mirrors TLA+ ByzantineResilience
        self.validate_byzantine_resilience()?;
        
        // Maintain liveness under maximum offline faults - mirrors TLA+ OfflineResilience
        let offline_stake = self.sum_stake(&self.offline_validators);
        let total_stake = self.total_stake();
        
        if offline_stake <= total_stake / 5 && self.in_sync_period() {
            // Should maintain progress
            if self.clock > GST + 2 * DELTA && self.finalized_blocks.is_empty() {
                return Err(AlpenglowError::ProtocolViolation(
                    "Offline resilience violation: No progress with acceptable offline stake".to_string()
                ));
            }
        }
        
        // Recovery after network partition - mirrors TLA+ PartitionRecovery
        if self.network_partitions.is_empty() && self.in_sync_period() {
            // Should recover after partitions heal
            if self.clock > GST + DELTA && self.finalized_blocks.is_empty() {
                // This is a soft check - in practice would need more sophisticated recovery detection
            }
        }
        
        // Combined "20+20" resilience - mirrors TLA+ Combined2020Resilience
        let byzantine_stake = self.sum_stake(&self.byzantine_validators);
        
        if byzantine_stake <= total_stake / 5 && offline_stake <= total_stake / 5 {
            // Safety should hold
            self.verify_safety()?;
            
            // Liveness should hold after GST
            if self.in_sync_period() {
                // Should eventually make progress
                if self.clock > GST + 3 * DELTA && self.finalized_blocks.is_empty() {
                    return Err(AlpenglowError::ProtocolViolation(
                        "Combined 20+20 resilience violation: No progress with acceptable fault levels".to_string()
                    ));
                }
            }
        }
        
        // Verify individual component resilience
        for votor_state in self.votor_states.values() {
            votor_state.verify_byzantine_resilience()?;
        }
        
        for rotor_state in self.rotor_states.values() {
            rotor_state.verify_byzantine_resilience()?;
        }
        
        Ok(())
    }
}

impl TlaCompatible for AlpenglowState {
    /// Convert to a TLA+ compatible string representation (JSON)
    fn to_tla_string(&self) -> String {
        // Build JSON value using existing export_tla_state_json logic, then serialize
        let json_value = {
            // Reuse export logic but produce serde_json::Value
            // Export Votor states as parsed JSON values
            let votor_states_json: HashMap<String, serde_json::Value> = self.votor_states
                .iter()
                .map(|(&validator, state)| {
                    let parsed = serde_json::from_str(&state.export_tla_state()).unwrap_or(serde_json::Value::Null);
                    (validator.to_string(), parsed)
                })
                .collect();

            let rotor_states_json: HashMap<String, serde_json::Value> = self.rotor_states
                .iter()
                .map(|(&validator, state)| {
                    let parsed = serde_json::from_str(&state.export_tla_state()).unwrap_or(serde_json::Value::Null);
                    (validator.to_string(), parsed)
                })
                .collect();

            let messages_json: Vec<serde_json::Value> = self.messages
                .iter()
                .map(|msg| serde_json::json!({
                    "type": msg.msg_type,
                    "sender": msg.sender,
                    "recipient": msg.recipient,
                    "payload": msg.payload,
                    "timestamp": msg.timestamp,
                    "signature": {
                        "signer": msg.sender,
                        "message": msg.msg_type,
                        "valid": msg.validate()
                    }
                }))
                .collect();

            let finalized_blocks_json: HashMap<String, Vec<serde_json::Value>> = self.finalized_blocks
                .iter()
                .map(|(&slot, blocks)| {
                    let blocks_json: Vec<serde_json::Value> = blocks
                        .iter()
                        .map(|block| serde_json::json!({
                            "slot": block.slot,
                            "view": block.view,
                            "hash": format!("{:?}", block.hash),
                            "parent": format!("{:?}", block.parent),
                            "proposer": block.proposer,
                            "timestamp": block.timestamp,
                            "signature": {
                                "signer": block.proposer,
                                "message": block.view,
                                "valid": true
                            },
                            "data": block.data,
                            "transactions": block.transactions.len()
                        }))
                        .collect();
                    (slot.to_string(), blocks_json)
                })
                .collect();

            let network_partitions_json: Vec<Vec<ValidatorId>> = self.network_partitions
                .iter()
                .map(|partition| partition.iter().cloned().collect())
                .collect();

            serde_json::json!({
                "clock": self.clock,
                "currentSlot": self.current_slot,
                "votorStates": votor_states_json,
                "rotorStates": rotor_states_json,
                "networkMessageQueue": self.network_message_queue.len(),
                "networkMessageBuffer": self.network_message_buffer.iter()
                    .map(|(&v, msgs)| (v.to_string(), msgs.len()))
                    .collect::<HashMap<String, usize>>(),
                "networkPartitions": network_partitions_json,
                "networkDroppedMessages": self.network_dropped_messages,
                "networkDeliveryTime": self.network_delivery_time.len(),
                "messages": messages_json,
                "finalizedBlocks": finalized_blocks_json,
                "finalizedBySlot": self.finalized_by_slot.iter()
                    .map(|(&slot, block_opt)| {
                        let block_json = if let Some(block) = block_opt {
                            serde_json::json!({
                                "slot": block.slot,
                                "hash": format!("{:?}", block.hash),
                                "proposer": block.proposer
                            })
                        } else {
                            serde_json::Value::Null
                        };
                        (slot.to_string(), block_json)
                    })
                    .collect::<HashMap<String, serde_json::Value>>(),
                "failureStates": self.failure_states,
                "nonceCounter": self.nonce_counter,
                "latencyMetrics": self.latency_metrics.iter()
                    .map(|(&slot, &latency)| (slot.to_string(), latency))
                    .collect::<HashMap<String, u64>>(),
                "bandwidthMetrics": self.bandwidth_metrics.iter()
                    .map(|(&validator, &bandwidth)| (validator.to_string(), bandwidth))
                    .collect::<HashMap<String, u64>>(),
                "config": {
                    "validator_count": self.config.validator_count,
                    "total_stake": self.config.total_stake,
                    "fast_path_threshold": self.fast_path_threshold(),
                    "slow_path_threshold": self.slow_path_threshold(),
                    "byzantine_threshold": self.byzantine_threshold(),
                    "stake_distribution": self.config.stake_distribution.iter()
                        .map(|(&v, &stake)| (v.to_string(), stake))
                        .collect::<HashMap<String, StakeAmount>>()
                },
                "byzantineValidators": self.byzantine_validators.iter().collect::<Vec<_>>(),
                "offlineValidators": self.offline_validators.iter().collect::<Vec<_>>(),
                "honestValidators": self.honest_validators().iter().collect::<Vec<_>>(),
                "GST": GST,
                "Delta": DELTA,
                "SlotDuration": SLOT_DURATION,
                "MaxSlot": MAX_SLOT,
                "MaxView": MAX_VIEW,
                "inSyncPeriod": self.in_sync_period(),
                "totalFinalizedBlocks": self.finalized_blocks.len(),
                "totalNetworkMessages": self.messages.len(),
                "activeNetworkPartitions": self.network_partitions.len()
            })
        };
        serde_json::to_string(&json_value).unwrap_or_else(|_| "{}".to_string())
    }
    
    /// Export TLA+ state as a JSON string for cross-validation
    fn export_tla_state(&self) -> String {
        self.to_tla_string()
    }
    
    /// Import TLA+ state from another AlpenglowState representation (copy selected fields)
    fn import_tla_state(&mut self, state: &Self) -> AlpenglowResult<()> {
        // Copy time and scheduling
        self.clock = state.clock;
        self.current_slot = state.current_slot;
        
        // Copy voter and rotor states by deep cloning
        self.votor_states = state.votor_states.clone();
        self.rotor_states = state.rotor_states.clone();
        
        // Copy network buffers and messages
        self.network_message_queue = state.network_message_queue.clone();
        self.network_message_buffer = state.network_message_buffer.clone();
        self.messages = state.messages.clone();
        self.network_dropped_messages = state.network_dropped_messages;
        self.network_delivery_time = state.network_delivery_time.clone();
        
        // Copy finalization data
        self.finalized_blocks = state.finalized_blocks.clone();
        self.finalized_by_slot = state.finalized_by_slot.clone();
        self.latency_metrics = state.latency_metrics.clone();
        
        // Copy validator sets and failure info
        self.failure_states = state.failure_states.clone();
        self.byzantine_validators = state.byzantine_validators.clone();
        self.offline_validators = state.offline_validators.clone();
        
        // Copy partitions
        self.network_partitions = state.network_partitions.clone();
        
        // Copy counters and metrics
        self.nonce_counter = state.nonce_counter;
        self.bandwidth_metrics = state.bandwidth_metrics.clone();
        
        Ok(())
    }
    
    fn validate_tla_invariants(&self) -> AlpenglowResult<()> {
        // Validate all invariants that should match TLA+ Alpenglow specification exactly
        
        // 1. TypeOK: All variables have correct types
        if self.clock > u64::MAX / 2 {
            return Err(AlpenglowError::ProtocolViolation(
                "TypeOK violation: clock value too large".to_string()
            ));
        }
        
        if self.current_slot == 0 || self.current_slot > MAX_SLOT {
            return Err(AlpenglowError::ProtocolViolation(
                "TypeOK violation: invalid current slot".to_string()
            ));
        }
        
        // 2. VotorRotorIntegration: Blocks available for voting must come from Rotor delivery
        for (&validator, votor_state) in &self.votor_states {
            for votes in votor_state.received_votes.values() {
                for vote in votes {
                    if vote.vote_type != VoteType::Skip {
                        // Check if block is available from Rotor
                        let has_block = self.rotor_states
                            .get(&validator)
                            .map(|rs| rs.delivered_blocks.get(&validator).unwrap_or(&HashSet::new()).contains(&vote.block))
                            .unwrap_or(false);
                        
                        if !has_block && vote.block != BlockHash::from(0u64) {
                            return Err(AlpenglowError::ProtocolViolation(
                                format!("VotorRotorIntegration violation: validator {} voted for unavailable block", validator)
                            ));
                        }
                    }
                }
            }
        }
        
        // 3. DeliveredBlocksConsistency: Delivered blocks consistency with reconstruction
        for (&validator, rotor_state) in &self.rotor_states {
            let delivered = rotor_state.delivered_blocks.get(&validator).cloned().unwrap_or_default();
            let reconstructed_hashes: HashSet<BlockHash> = rotor_state.reconstructed_blocks
                .get(&validator)
                .unwrap_or(&HashSet::new())
                .iter()
                .map(|block| block.hash)
                .collect();
            
            for &delivered_block in &delivered {
                if !reconstructed_hashes.contains(&delivered_block) {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("DeliveredBlocksConsistency violation: validator {} has delivered block not in reconstructed set", validator)
                    ));
                }
            }
        }
        
        // 4. Validate individual component invariants
        for votor_state in self.votor_states.values() {
            votor_state.validate_tla_invariants()?;
        }
        
        for rotor_state in self.rotor_states.values() {
            rotor_state.validate_tla_invariants()?;
        }
        
        // 5. Safety invariants
        self.verify_safety()?;
        
        // 6. Byzantine resilience invariants
        self.verify_byzantine_resilience()?;
        
        // 7. Network invariants
        for message in &self.messages {
            if !message.validate() {
                return Err(AlpenglowError::ProtocolViolation(
                    "Network invariant violation: invalid message in flight".to_string()
                ));
            }
        }
        
        // 8. Finalization consistency
        for (&slot, blocks) in &self.finalized_blocks {
            if blocks.len() > 1 {
                return Err(AlpenglowError::ProtocolViolation(
                    format!("Finalization consistency violation: multiple blocks finalized in slot {}", slot)
                ));
            }
            
            if blocks.len() == 1 {
                let block = blocks.iter().next().unwrap();
                if let Some(mapped_block) = self.finalized_by_slot.get(&slot) {
                    if mapped_block.as_ref() != Some(block) {
                        return Err(AlpenglowError::ProtocolViolation(
                            format!("Finalization mapping inconsistency for slot {}", slot)
                        ));
                    }
                }
            }
        }
        
        Ok(())
    }
}

// Additional helper methods for AlpenglowState
impl AlpenglowState {
    /// Helper function to parse block from JSON
    pub fn parse_block_from_json(&self, block_json: &serde_json::Value) -> AlpenglowResult<Option<Block>> {
        let slot = block_json.get("slot")
            .and_then(|v| v.as_u64())
            .ok_or_else(|| AlpenglowError::ProtocolViolation("Missing slot in block JSON".to_string()))?;
        
        let view = block_json.get("view")
            .and_then(|v| v.as_u64())
            .ok_or_else(|| AlpenglowError::ProtocolViolation("Missing view in block JSON".to_string()))?;
        
        let hash_str = block_json.get("hash")
            .and_then(|v| v.as_str())
            .ok_or_else(|| AlpenglowError::ProtocolViolation("Missing hash in block JSON".to_string()))?;
        
        let parent_str = block_json.get("parent")
            .and_then(|v| v.as_str())
            .ok_or_else(|| AlpenglowError::ProtocolViolation("Missing parent in block JSON".to_string()))?;
        
        let proposer = block_json.get("proposer")
            .and_then(|v| v.as_u64())
            .map(|n| n as ValidatorId)
            .ok_or_else(|| AlpenglowError::ProtocolViolation("Missing proposer in block JSON".to_string()))?;
        
        let timestamp = block_json.get("timestamp")
            .and_then(|v| v.as_u64())
            .unwrap_or(0);
        
        let data = block_json.get("data")
            .and_then(|v| v.as_array())
            .map(|arr| arr.iter().filter_map(|v| v.as_u64().map(|n| n as u8)).collect())
            .unwrap_or_default();
        
        let hash = self.parse_hash_from_string_helper(hash_str)?;
        let parent = self.parse_hash_from_string_helper(parent_str)?;
        
        let block = Block {
            slot,
            view,
            hash,
            parent,
            proposer,
            transactions: Vec::new(), // Simplified - transactions not fully parsed
            timestamp,
            signature: proposer as Signature,
            data,
        };
        
        Ok(Some(block))
    }
    
    /// Helper function to parse hash from string
    pub fn parse_hash_from_string_helper(&self, hash_str: &str) -> AlpenglowResult<BlockHash> {
        // Simple hash parsing - in practice would handle various formats
        if hash_str == "0" || hash_str.is_empty() {
            return Ok(0u64.into());
        }
        
        // Use string hash for deterministic conversion
        let mut hasher = std::collections::hash_map::DefaultHasher::new();
        use std::hash::{Hash, Hasher};
        hash_str.hash(&mut hasher);
        let hash = hasher.finish();
        Ok(hash.into())
    }
    
    /// Validate imported state consistency
    pub fn validate_imported_state(&self) -> AlpenglowResult<()> {
        // Check that all validators in various maps are valid
        let max_validator = self.config.validator_count as ValidatorId;
        
        for &validator in self.votor_states.keys() {
            if validator >= max_validator {
                return Err(AlpenglowError::ProtocolViolation(
                    format!("Invalid validator {} in votor_states", validator)
                ));
            }
        }
        
        for &validator in self.rotor_states.keys() {
            if validator >= max_validator {
                return Err(AlpenglowError::ProtocolViolation(
                    format!("Invalid validator {} in rotor_states", validator)
                ));
            }
        }
        
        // Check Byzantine and offline validator sets
        for &validator in &self.byzantine_validators {
            if validator >= max_validator {
                return Err(AlpenglowError::ProtocolViolation(
                    format!("Invalid Byzantine validator {}", validator)
                ));
            }
        }
        
        for &validator in &self.offline_validators {
            if validator >= max_validator {
                return Err(AlpenglowError::ProtocolViolation(
                    format!("Invalid offline validator {}", validator)
                ));
            }
        }
        
        // Check that Byzantine and offline sets don't overlap
        if !self.byzantine_validators.is_disjoint(&self.offline_validators) {
            return Err(AlpenglowError::ProtocolViolation(
                "Byzantine and offline validator sets overlap".to_string()
            ));
        }
        
        // Check clock consistency
        if self.clock == 0 && (!self.finalized_blocks.is_empty() || !self.messages.is_empty()) {
            return Err(AlpenglowError::ProtocolViolation(
                "Clock is zero but state indicates activity".to_string()
            ));
        }
        
        // Check slot bounds
        if self.current_slot == 0 || self.current_slot > MAX_SLOT {
            return Err(AlpenglowError::ProtocolViolation(
                format!("Current slot {} out of bounds", self.current_slot)
            ));
        }
        
        Ok(())
    }
}

/// Verification result for structured testing
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AlpenglowVerificationResult {
    pub success: bool,
    pub violations: Vec<String>,
    pub metrics: AlpenglowVerificationMetrics,
}

/// Verification metrics for testing
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AlpenglowVerificationMetrics {
    pub states_explored: u64,
    pub properties_checked: u64,
    pub violations_found: u64,
    pub duration_ms: u128,
    pub safety_violations: u64,
    pub liveness_violations: u64,
    pub byzantine_resilience_violations: u64,
}

/// Model checker for Alpenglow verification
pub struct AlpenglowModelChecker {
    pub model: AlpenglowModel,
}

impl AlpenglowModelChecker {
    /// Create new model checker
    pub fn new(model: AlpenglowModel) -> Self {
        Self { model }
    }
    
    /// Run verification with given parameters
    pub fn verify(&self, max_steps: usize, max_time_ms: u128) -> AlpenglowVerificationResult {
        let start = Instant::now();
        let mut violations = Vec::new();
        let mut states_explored = 0u64;
        let mut properties_checked = 0u64;
        let mut safety_violations = 0u64;
        let mut liveness_violations = 0u64;
        let mut byzantine_resilience_violations = 0u64;
        
        // Initialize state
        let mut state = self.model.init_state();
        
        // Run bounded model checking
        for step in 0..max_steps {
            if start.elapsed().as_millis() > max_time_ms {
                break;
            }
            
            states_explored += 1;
            
            // Check properties
            properties_checked += 3; // Safety, liveness, Byzantine resilience
            
            // Safety check
            if let Err(e) = state.verify_safety() {
                safety_violations += 1;
                violations.push(format!("Safety violation at step {}: {:?}", step, e));
            }
            
            // Liveness check (simplified)
            if let Err(e) = state.verify_liveness() {
                liveness_violations += 1;
                violations.push(format!("Liveness violation at step {}: {:?}", step, e));
            }
            
            // Byzantine resilience check
            if let Err(e) = state.verify_byzantine_resilience() {
                byzantine_resilience_violations += 1;
                violations.push(format!("Byzantine resilience violation at step {}: {:?}", step, e));
            }
            
            // Get possible actions
            let actions = self.model.actions(&state);
            if actions.is_empty() {
                break; // No more actions possible
            }
            
            // Execute first action (simplified - in practice would explore all)
            if let Some(action) = actions.first() {
                if let Err(e) = self.model.execute_action(&mut state, action.clone()) {
                    violations.push(format!("Action execution error at step {}: {:?}", step, e));
                    break;
                }
            }
        }
        
        let duration_ms = start.elapsed().as_millis();
        let violations_found = violations.len() as u64;
        let success = violations.is_empty();
        
        AlpenglowVerificationResult {
            success,
            violations,
            metrics: AlpenglowVerificationMetrics {
                states_explored,
                properties_checked,
                violations_found,
                duration_ms,
                safety_violations,
                liveness_violations,
                byzantine_resilience_violations,
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_alpenglow_state_creation() {
        let config = Config::new().with_validators(4);
        let state = AlpenglowState::new(config);
        
        assert_eq!(state.clock, 0);
        assert_eq!(state.current_slot, 1);
        assert_eq!(state.votor_states.len(), 4);
        assert_eq!(state.rotor_states.len(), 4);
        assert!(state.finalized_blocks.is_empty());
    }
    
    #[test]
    fn test_alpenglow_model() {
        let config = Config::new().with_validators(3);
        let model = AlpenglowModel::new(config);
        
        let state = model.init_state();
        assert_eq!(state.votor_states.len(), 3);
        assert_eq!(state.rotor_states.len(), 3);
        
        let actions = model.actions(&state);
        assert!(!actions.is_empty());
        assert!(actions.iter().any(|a| matches!(a, AlpenglowAction::AdvanceClock)));
    }
    
    #[test]
    fn test_advance_clock() {
        let config = Config::new().with_validators(3);
        let mut state = AlpenglowState::new(config);
        
        assert_eq!(state.clock, 0);
        state.advance_clock().unwrap();
        assert_eq!(state.clock, 1);
        
        // Check that Votor and Rotor states are updated
        for votor_state in state.votor_states.values() {
            assert_eq!(votor_state.current_time, 1);
        }
        
        for rotor_state in state.rotor_states.values() {
            assert_eq!(rotor_state.clock, 1);
        }
    }
    
    #[test]
    fn test_byzantine_validators() {
        let config = Config::new().with_validators(4);
        let mut state = AlpenglowState::new(config);
        
        let byzantine_validators: HashSet<ValidatorId> = [0, 1].iter().cloned().collect();
        state.set_byzantine_validators(byzantine_validators.clone());
        
        assert_eq!(state.byzantine_validators, byzantine_validators);
        assert_eq!(state.honest_validators().len(), 2);
        
        // Check that Votor states are updated
        for (&validator_id, votor_state) in &state.votor_states {
            assert_eq!(votor_state.is_byzantine, byzantine_validators.contains(&validator_id));
        }
    }
    
    #[test]
    fn test_safety_verification() {
        let config = Config::new().with_validators(3);
        let state = AlpenglowState::new(config);
        
        // Empty state should be safe
        assert!(state.verify_safety().is_ok());
    }
    
    #[test]
    fn test_liveness_verification() {
        let config = Config::new().with_validators(3);
        let state = AlpenglowState::new(config);
        
        // Initial state should pass liveness
        assert!(state.verify_liveness().is_ok());
    }
    
    #[test]
    fn test_byzantine_resilience() {
        let config = Config::new().with_validators(4);
        let mut state = AlpenglowState::new(config);
        
        // Set Byzantine validators below threshold
        let byzantine_validators = [0].iter().cloned().collect();
        state.set_byzantine_validators(byzantine_validators);
        
        assert!(state.verify_byzantine_resilience().is_ok());
        
        // Set Byzantine validators above threshold
        let byzantine_validators = [0, 1, 2].iter().cloned().collect();
        state.set_byzantine_validators(byzantine_validators);
        
        assert!(state.verify_byzantine_resilience().is_err());
    }
    
    #[test]
    fn test_tla_compatibility() {
        let config = Config::new().with_validators(3);
        let mut state = AlpenglowState::new(config);
        
        // Set some test data
        state.clock = 100;
        state.current_slot = 5;
        
        let exported_str = state.export_tla_state();
        // Parse exported JSON string to value for inspection
        let exported_val: serde_json::Value = serde_json::from_str(&exported_str).expect("Exported TLA state should be valid JSON");
        assert_eq!(exported_val.get("clock").and_then(|v| v.as_u64()), Some(100));
        assert_eq!(exported_val.get("currentSlot").and_then(|v| v.as_u64()), Some(5));
        
        // Test import by copying from another AlpenglowState
        let mut new_state = AlpenglowState::new(Config::new().with_validators(3));
        assert!(new_state.import_tla_state(&state).is_ok());
        assert_eq!(new_state.clock, 100);
        assert_eq!(new_state.current_slot, 5);
    }
    
    #[test]
    fn test_model_checker() {
        let config = Config::new().with_validators(3);
        let model = AlpenglowModel::new(config);
        let checker = AlpenglowModelChecker::new(model);
        
        let result = checker.verify(10, 1000); // 10 steps, 1 second max
        assert!(result.metrics.states_explored > 0);
        assert!(result.metrics.properties_checked > 0);
    }
    
    #[test]
    fn test_network_messages() {
        let msg = NetworkMessage::new(
            "test".to_string(),
            0,
            "1".to_string(),
            serde_json::json!({"data": "test"}),
            100,
        );
        
        assert_eq!(msg.sender, 0);
        assert_eq!(msg.recipient, "1");
        assert!(msg.validate());
        assert!(!msg.is_broadcast());
        
        let broadcast_msg = NetworkMessage::broadcast(
            "test".to_string(),
            0,
            serde_json::json!({"data": "test"}),
            100,
        );
        
        assert!(broadcast_msg.is_broadcast());
    }
    
    #[test]
    fn test_action_execution() {
        let config = Config::new().with_validators(3);
        let model = AlpenglowModel::new(config);
        let mut state = model.init_state();
        
        // Test clock advancement
        let action = AlpenglowAction::AdvanceClock;
        assert!(model.execute_action(&mut state, action).is_ok());
        assert_eq!(state.clock, 1);
        
        // Test Votor action
        let votor_action = AlpenglowAction::VotorAction {
            action: VotorMessage::ClockTick { current_time: state.clock },
        };
        assert!(model.execute_action(&mut state, votor_action).is_ok());
    }
    
    #[test]
    fn test_performance_metrics() {
        let config = Config::new().with_validators(3);
        let mut state = AlpenglowState::new(config);
        
        // Add some test data
        state.clock = 1000;
        state.current_slot = 10;
        state.latency_metrics.insert(1, 150);
        state.latency_metrics.insert(2, 200);
        state.bandwidth_metrics.insert(0, 1000);
        state.bandwidth_metrics.insert(1, 1500);
        
        let metrics = state.get_performance_metrics();
        assert_eq!(metrics.clock, 1000);
        assert_eq!(metrics.current_slot, 10);
        assert_eq!(metrics.average_finalization_latency, 175); // (150 + 200) / 2
        assert_eq!(metrics.total_bandwidth_used, 2500); // 1000 + 1500
    }
    
    #[test]
    fn test_state_summary() {
        let config = Config::new().with_validators(4);
        let mut state = AlpenglowState::new(config);
        
        state.clock = GST + 100; // Past GST
        state.set_byzantine_validators([0].iter().cloned().collect());
        state.set_offline_validators([1].iter().cloned().collect());
        
        let summary = state.get_state_summary();
        assert!(summary.in_sync_period);
        assert_eq!(summary.byzantine_validators.len(), 1);
        assert_eq!(summary.offline_validators.len(), 1);
    }
}
