//! # Network Layer Implementation
//!
//! This module implements the network layer for the Alpenglow protocol using Stateright's
//! actor model. It provides concrete implementation of the partial synchrony model,
//! GST (Global Stabilization Time) assumptions, and Delta-bounded message delivery
//! as specified in the TLA+ Network.tla specification.
//!
//! ## Key Features
//!
//! - **Partial Synchrony**: Models network behavior before and after GST
//! - **Message Delivery**: Implements Delta-bounded delivery guarantees after GST
//! - **Network Partitions**: Handles network partitions and healing
//! - **Byzantine Behavior**: Models adversarial message control and injection
//! - **Cross-validation**: Compatible with TLA+ Network.tla specification

use crate::{
    AlpenglowError, AlpenglowResult, Config, TlaCompatible, ValidatorId, Verifiable,
    NetworkMessage, MessageType, MessageRecipient,
};
use crate::stateright::{Actor, ActorModel, Id};
use std::collections::{HashMap, HashSet};
use std::hash::{Hash, Hasher};
use std::fmt::Debug;




use serde::{Deserialize, Serialize};

/// Message signature structure matching TLA+ Signature
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct MessageSignature {
    /// Signer validator ID
    pub signer: ValidatorId,
    /// Message being signed (simplified to u64)
    pub message: u64,
    /// Signature validity (for modeling purposes)
    pub valid: bool,
}

/// Network partition structure matching TLA+ NetworkPartition
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct NetworkPartition {
    /// Partition identifier
    pub id: u32,
    /// First partition of validators
    pub partition1: Vec<ValidatorId>,
    /// Second partition of validators
    pub partition2: Vec<ValidatorId>,
    /// When partition started
    pub start_time: u64,
    /// Whether partition has been healed
    pub healed: bool,
}

/// Network state exactly matching TLA+ Network variables
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct NetworkState {
    /// Current logical clock time - mirrors TLA+ clock
    pub clock: u64,
    /// Set of undelivered messages - mirrors TLA+ messageQueue
    pub message_queue: HashSet<NetworkMessage>,
    /// Buffer of delivered messages per validator - mirrors TLA+ messageBuffer
    pub message_buffer: HashMap<ValidatorId, HashSet<NetworkMessage>>,
    /// Current network partitions - mirrors TLA+ networkPartitions
    pub network_partitions: HashSet<NetworkPartition>,
    /// Count of dropped messages - mirrors TLA+ droppedMessages
    pub dropped_messages: u64,
    /// Delivery times for messages - mirrors TLA+ deliveryTime
    pub delivery_time: HashMap<u64, u64>,
    /// Set of Byzantine validators
    pub byzantine_validators: HashSet<ValidatorId>,
    /// Network configuration constants
    pub config: NetworkConfig,
    /// Message ID counter for generating unique IDs
    pub next_message_id: u64,
}

impl Hash for NetworkState {
    fn hash<H: Hasher>(&self, state: &mut H) {
        // Hash only the key identifying fields to avoid issues with collections
        self.clock.hash(state);
        self.dropped_messages.hash(state);
        self.next_message_id.hash(state);
    }
}

/// Network configuration matching TLA+ constants
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct NetworkConfig {
    /// Set of all validators
    pub validators: HashSet<ValidatorId>,
    /// Set of Byzantine validators
    pub byzantine_validators: HashSet<ValidatorId>,
    /// Global Stabilization Time
    pub gst: u64,
    /// Maximum message delay after GST
    pub delta: u64,
    /// Maximum message size
    pub max_message_size: u64,
    /// Network capacity
    pub network_capacity: u64,
    /// Maximum buffer size per validator
    pub max_buffer_size: usize,
    /// Partition timeout
    pub partition_timeout: u64,
}

impl From<Config> for NetworkConfig {
    fn from(config: Config) -> Self {
        let validators: HashSet<ValidatorId> = (0..config.validator_count as ValidatorId).collect();
        Self {
            validators,
            byzantine_validators: HashSet::new(), // Will be set separately
            gst: config.gst,
            delta: config.max_network_delay,
            max_message_size: 1024, // Default value
            network_capacity: 1000000, // Default value
            max_buffer_size: 1000, // Default value
            partition_timeout: 100, // Default value
        }
    }
}

/// Network actor implementing partial synchrony model
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct NetworkActor {
    /// Validator ID for this network actor
    pub validator_id: ValidatorId,
    /// Network configuration
    pub config: Config,
}

/// Messages that can be sent to the network actor
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum NetworkActorMessage {
    /// Send a message to another validator
    SendMessage {
        recipient: ValidatorId,
        content: u64,
    },
    /// Broadcast a message to all validators
    BroadcastMessage {
        content: u64,
    },
    /// Deliver a pending message
    DeliverMessage,
    /// Advance the logical clock
    AdvanceClock,
    /// Create a network partition
    CreatePartition {
        partition1: Vec<ValidatorId>,
        partition2: Vec<ValidatorId>,
    },
    /// Heal a network partition
    HealPartition,
    /// Drop a message (Byzantine behavior)
    DropMessage,
    /// Duplicate a message (Byzantine behavior)
    DuplicateMessage { message_id: u64 },
    /// Inject a Byzantine message
    InjectByzantineMessage {
        recipient: MessageRecipient,
        payload: u64,
    },
    /// Adversarial delay of a message
    AdversarialDelay {
        message_id: u64,
        new_delay: u64,
    },
}

impl NetworkActor {
    /// Create a new network actor for a validator
    pub fn new(validator_id: ValidatorId, config: Config) -> Self {
        Self {
            validator_id,
            config,
        }
    }

    /// Send a message - mirrors TLA+ SendMessage action
    pub fn send_message(
        &self,
        state: &mut NetworkState,
        recipient: ValidatorId,
        content: u64,
    ) -> AlpenglowResult<()> {
        let message_id = self.generate_network_message_id(state.clock, self.validator_id);
        let message = NetworkMessage {
            id: message_id,
            sender: self.validator_id,
            recipient: MessageRecipient::Validator(recipient),
            msg_type: MessageType::Block, // Default type
            payload: vec![content as u8],
            timestamp: state.clock,
            signature: content,
        };

        let delay = self.compute_message_delay(state.clock, self.validator_id);
        state.message_queue.insert(message);
        state.delivery_time.insert(message_id, state.clock + delay);
        state.next_message_id += 1;

        Ok(())
    }

    /// Broadcast message to all validators - mirrors TLA+ BroadcastMessage action
    pub fn broadcast_message(
        &self,
        state: &mut NetworkState,
        content: u64,
    ) -> AlpenglowResult<()> {
        for validator in &state.config.validators {
            if *validator != self.validator_id {
                let message_id = self.generate_network_message_id(state.clock, self.validator_id) + *validator as u64;
                let message = NetworkMessage {
                    id: message_id,
                    sender: self.validator_id,
                    recipient: MessageRecipient::Validator(*validator),
                    msg_type: MessageType::Block,
                    payload: vec![content as u8],
                    timestamp: state.clock,
                    signature: content,
                };

                let delay = self.compute_message_delay(state.clock, self.validator_id);
                state.message_queue.insert(message);
                state.delivery_time.insert(message_id, state.clock + delay);
            }
        }
        state.next_message_id += state.config.validators.len() as u64;

        Ok(())
    }

    /// Deliver a message - mirrors TLA+ DeliverMessage action
    pub fn deliver_message(&self, state: &mut NetworkState) -> AlpenglowResult<bool> {
        // Find a message that can be delivered
        let deliverable_message = state.message_queue.iter()
            .find(|msg| self.can_deliver_message(msg, state))
            .cloned();

        if let Some(message) = deliverable_message {
            // Remove from queue
            state.message_queue.remove(&message);
            state.delivery_time.remove(&message.id);

            // Add to message buffer
            if let MessageRecipient::Validator(recipient) = message.recipient {
                state.message_buffer
                    .entry(recipient)
                    .or_default()
                    .insert(message);
            }

            Ok(true)
        } else {
            Ok(false)
        }
    }

    /// Drop a message - mirrors TLA+ DropMessage action
    pub fn drop_message(&self, state: &mut NetworkState) -> AlpenglowResult<bool> {
        // Can only drop before GST
        if state.clock >= state.config.gst {
            return Ok(false);
        }

        // Find a message that can be dropped (Byzantine or invalid)
        let droppable_message = state.message_queue.iter()
            .find(|msg| {
                state.config.byzantine_validators.contains(&msg.sender) ||
                if msg.signature != 0 {
                    true
                } else {
                    false
                }
            })
            .cloned();

        if let Some(message) = droppable_message {
            state.message_queue.remove(&message);
            state.delivery_time.remove(&message.id);
            state.dropped_messages += 1;
            Ok(true)
        } else {
            Ok(false)
        }
    }

    /// Create a network partition - mirrors TLA+ PartitionNetwork action
    pub fn create_partition(
        &self,
        state: &mut NetworkState,
        partition1: Vec<ValidatorId>,
        partition2: Vec<ValidatorId>,
    ) -> AlpenglowResult<()> {
        // Can only create partitions before GST
        if state.clock >= state.config.gst {
            return Err(AlpenglowError::NetworkError(
                "Cannot create partition after GST".to_string()
            ));
        }

        // Validate partition
        if partition1.is_empty() || partition2.is_empty() {
            return Err(AlpenglowError::NetworkError(
                "Partition groups cannot be empty".to_string()
            ));
        }

        // Convert to HashSet for disjoint check
        let set1: HashSet<_> = partition1.iter().cloned().collect();
        let set2: HashSet<_> = partition2.iter().cloned().collect();
        
        if !set1.is_disjoint(&set2) {
            return Err(AlpenglowError::NetworkError(
                "Partition groups must be disjoint".to_string()
            ));
        }

        let all_validators: HashSet<_> = set1.union(&set2).cloned().collect();
        if all_validators != state.config.validators {
            return Err(AlpenglowError::NetworkError(
                "Partition must cover all validators".to_string()
            ));
        }

        // Ensure partition doesn't isolate all honest validators
        let honest_validators: HashSet<_> = state.config.validators
            .difference(&state.config.byzantine_validators)
            .cloned()
            .collect();

        let set1: HashSet<_> = partition1.iter().cloned().collect();
        let set2: HashSet<_> = partition2.iter().cloned().collect();
        let honest_in_p1 = set1.intersection(&honest_validators).count();
        let honest_in_p2 = set2.intersection(&honest_validators).count();

        if honest_in_p1 == 0 || honest_in_p2 == 0 {
            return Err(AlpenglowError::NetworkError(
                "Partition would isolate all honest validators".to_string()
            ));
        }

        let partition = NetworkPartition {
            id: state.clock as u32, // Use timestamp as unique ID
            partition1: partition1.into_iter().collect(),
            partition2: partition2.into_iter().collect(),
            start_time: state.clock,
            healed: false,
        };

        state.network_partitions.insert(partition);
        Ok(())
    }

    /// Heal a network partition - mirrors TLA+ HealPartition action
    pub fn heal_partition(&self, state: &mut NetworkState) -> AlpenglowResult<bool> {
        // Find an unhealed partition
        let partition_to_heal = state.network_partitions.iter()
            .find(|p| !p.healed && (
                state.clock >= state.config.gst ||
                state.clock >= p.start_time + state.config.partition_timeout
            ))
            .cloned();

        if let Some(partition) = partition_to_heal {
            state.network_partitions.remove(&partition);
            let healed_partition = NetworkPartition {
                healed: true,
                ..partition
            };
            state.network_partitions.insert(healed_partition);
            Ok(true)
        } else {
            Ok(false)
        }
    }

    /// Check if two validators can communicate (not partitioned)
    fn can_communicate(
        &self,
        sender: ValidatorId,
        recipient: ValidatorId,
        partitions: &HashSet<NetworkPartition>,
    ) -> bool {
        !partitions.iter().any(|p| {
            !p.healed
                && ((p.partition1.contains(&sender) && p.partition2.contains(&recipient))
                    || (p.partition2.contains(&sender) && p.partition1.contains(&recipient)))
        })
    }

    /// Compute message delay based on network conditions and GST
    fn compute_message_delay(&self, current_time: u64, _sender: ValidatorId) -> u64 {
        if current_time < self.config.gst {
            // Before GST: unbounded delay (modeled as large but finite)
            self.config.max_network_delay * 10
        } else {
            // After GST: bounded by Delta
            self.config.max_network_delay
        }
    }

    /// Generate unique message ID - mirrors TLA+ GenerateNetworkMessageId
    fn generate_network_message_id(&self, time: u64, validator: ValidatorId) -> u64 {
        time * 10000 + validator as u64
    }

    /// Check if message can be delivered based on timing and network conditions
    fn can_deliver_message(&self, msg: &NetworkMessage, state: &NetworkState) -> bool {
        // Check if delivery time has been reached
        if let Some(&delivery_time) = state.delivery_time.get(&msg.id) {
            if state.clock < delivery_time {
                return false;
            }
        }

        // Check network partitions
        if let MessageRecipient::Validator(recipient) = msg.recipient {
            if !self.can_communicate(msg.sender, recipient, &state.network_partitions) {
                return false;
            }
        }

        // Check message size constraints
        if state.config.max_message_size > 0 && state.config.network_capacity > 0 {
            // Simplified bandwidth check
            if state.config.max_message_size > state.config.network_capacity {
                return false;
            }
        }

        // GST-based delivery guarantee
        if state.clock >= state.config.gst
            && msg.timestamp >= state.config.gst
            && !state.config.byzantine_validators.contains(&msg.sender)
        {
            // After GST, honest messages must be delivered within Delta
            if let Some(&delivery_time) = state.delivery_time.get(&msg.id) {
                return delivery_time <= msg.timestamp + state.config.delta;
            }
        }

        true
    }

    /// Inject Byzantine message
    pub fn inject_byzantine_message(
        &self,
        state: &mut NetworkState,
        recipient: MessageRecipient,
        payload: u64,
    ) -> AlpenglowResult<()> {
        if !state.config.byzantine_validators.contains(&self.validator_id) {
            return Err(AlpenglowError::ByzantineDetected(
                "Only Byzantine validators can inject messages".to_string()
            ));
        }

        let message_id = self.generate_network_message_id(state.clock, self.validator_id);
        let fake_message = NetworkMessage {
            id: message_id,
            sender: self.validator_id,
            recipient,
            msg_type: MessageType::Block,
            payload: vec![payload as u8],
            timestamp: state.clock,
            signature: payload,
        };

        state.message_queue.insert(fake_message);
        state.delivery_time.insert(message_id, state.clock);
        state.next_message_id += 1;

        Ok(())
    }

    /// Duplicate a message (Byzantine behavior)
    pub fn duplicate_message(&self, state: &mut NetworkState, message_id: u64) -> AlpenglowResult<()> {
        if let Some(original_msg) = state.message_queue.iter().find(|msg| msg.id == message_id).cloned() {
            if !state.config.byzantine_validators.contains(&original_msg.sender) {
                return Err(AlpenglowError::ByzantineDetected(
                    "Can only duplicate Byzantine messages".to_string()
                ));
            }

            let duplicate = NetworkMessage {
                id: state.next_message_id,
                ..original_msg
            };

            state.message_queue.insert(duplicate.clone());
            if let Some(&delivery_time) = state.delivery_time.get(&message_id) {
                state.delivery_time.insert(duplicate.id, delivery_time);
            }
            state.next_message_id += 1;

            Ok(())
        } else {
            Err(AlpenglowError::NetworkError(
                "Message not found for duplication".to_string()
            ))
        }
    }

    /// Apply adversarial delay to a message
    pub fn adversarial_delay(
        &self,
        state: &mut NetworkState,
        message_id: u64,
        new_delay: u64,
    ) -> AlpenglowResult<()> {
        // Can only apply adversarial delay before GST
        if state.clock >= state.config.gst {
            return Err(AlpenglowError::NetworkError(
                "Cannot apply adversarial delay after GST".to_string()
            ));
        }

        if let Some(msg) = state.message_queue.iter().find(|msg| msg.id == message_id) {
            if state.config.byzantine_validators.contains(&msg.sender) {
                state.delivery_time.insert(message_id, state.clock + new_delay);
                Ok(())
            } else {
                Err(AlpenglowError::ByzantineDetected(
                    "Can only delay Byzantine messages".to_string()
                ))
            }
        } else {
            Err(AlpenglowError::NetworkError(
                "Message not found for delay".to_string()
            ))
        }
    }
}

impl Actor for NetworkActor {
    type Msg = NetworkActorMessage;
    type State = NetworkState;

    fn on_start(&self, _id: Id, _o: &mut crate::stateright::util::Out<Self>) -> Self::State {
        let validators: HashSet<ValidatorId> = (0..self.config.validator_count as ValidatorId).collect();
        let mut message_buffer = HashMap::new();
        for validator in &validators {
            message_buffer.insert(*validator, HashSet::new());
        }

        let network_config = NetworkConfig::from(self.config.clone());

        NetworkState {
            clock: 0,
            message_queue: HashSet::new(),
            message_buffer,
            network_partitions: HashSet::new(),
            dropped_messages: 0,
            delivery_time: HashMap::new(),
            byzantine_validators: HashSet::new(), // Will be set based on configuration
            config: network_config,
            next_message_id: 1,
        }
    }

    fn on_msg(
        &self,
        _id: Id,
        state: &mut Self::State,
        _src: Id,
        msg: Self::Msg,
        _o: &mut crate::stateright::util::Out<Self>,
    ) {
        match msg {
            NetworkActorMessage::SendMessage { recipient, content } => {
                let _ = self.send_message(state, recipient, content);
            }

            NetworkActorMessage::BroadcastMessage { content } => {
                let _ = self.broadcast_message(state, content);
            }

            NetworkActorMessage::DeliverMessage => {
                let _ = self.deliver_message(state);
            }

            NetworkActorMessage::AdvanceClock => {
                state.clock += 1;
            }

            NetworkActorMessage::CreatePartition {
                partition1,
                partition2,
            } => {
                let _ = self.create_partition(state, partition1, partition2);
            }

            NetworkActorMessage::HealPartition => {
                let _ = self.heal_partition(state);
            }

            NetworkActorMessage::DropMessage => {
                let _ = self.drop_message(state);
            }

            NetworkActorMessage::DuplicateMessage { message_id } => {
                let _ = self.duplicate_message(state, message_id);
            }

            NetworkActorMessage::InjectByzantineMessage { recipient, payload } => {
                let _ = self.inject_byzantine_message(state, recipient, payload);
            }

            NetworkActorMessage::AdversarialDelay {
                message_id,
                new_delay,
            } => {
                let _ = self.adversarial_delay(state, message_id, new_delay);
            }
        }
    }
}

/// Partial synchrony model for the network
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct PartialSynchronyModel {
    /// Network configuration
    pub config: Config,
    /// Current global time
    pub global_time: u64,
    /// Set of Byzantine validators
    pub byzantine_validators: HashSet<ValidatorId>,
}

impl PartialSynchronyModel {
    /// Create a new partial synchrony model
    pub fn new(config: Config) -> Self {
        Self {
            config,
            global_time: 0,
            byzantine_validators: HashSet::new(),
        }
    }

    /// Set Byzantine validators
    pub fn with_byzantine_validators(mut self, byzantine: HashSet<ValidatorId>) -> Self {
        self.byzantine_validators = byzantine;
        self
    }

    /// Check if we're in the synchronous period (after GST)
    pub fn is_synchronous(&self) -> bool {
        self.global_time >= self.config.gst
    }

    /// Get maximum message delay for current period
    pub fn max_message_delay(&self) -> u64 {
        if self.is_synchronous() {
            self.config.max_network_delay
        } else {
            // Before GST, delays can be unbounded (modeled as very large)
            self.config.max_network_delay * 10
        }
    }

    /// Advance global time
    pub fn advance_time(&mut self) {
        self.global_time += 1;
    }

    /// Check if message delivery is guaranteed
    pub fn is_delivery_guaranteed(&self, sender: ValidatorId, timestamp: u64) -> bool {
        self.is_synchronous()
            && timestamp >= self.config.gst
            && !self.byzantine_validators.contains(&sender)
    }
}

impl Verifiable for NetworkState {
    fn verify(&self) -> AlpenglowResult<()> {
        // Delegate to the existing verification methods for safety, liveness, and Byzantine resilience
        self.verify_safety()?;
        self.verify_liveness()?;
        self.verify_byzantine_resilience()?;
        Ok(())
    }

    fn verify_safety(&self) -> AlpenglowResult<()> {
        // NoForgery: No message forgery for honest validators
        for msg in &self.message_queue {
            if !self.config.byzantine_validators.contains(&msg.sender) && msg.signature == 0 {
                return Err(AlpenglowError::ProtocolViolation(
                    "Message forgery detected for honest validator".to_string(),
                ));
            }
        }

        // BoundedDeliveryProperty: Bounded delivery after GST
        if self.clock >= self.config.gst {
            for msg in &self.message_queue {
                if msg.timestamp >= self.config.gst
                    && !self.config.byzantine_validators.contains(&msg.sender)
                {
                    if let Some(&delivery_time) = self.delivery_time.get(&msg.id) {
                        if delivery_time > msg.timestamp + self.config.delta {
                            return Err(AlpenglowError::ProtocolViolation(
                                "Message delivery exceeds Delta bound after GST".to_string(),
                            ));
                        }
                    }
                }
            }
        }

        // PartitionDetection: Partitions are eventually healed
        for partition in &self.network_partitions {
            if !partition.healed && self.clock >= partition.start_time + self.config.partition_timeout {
                return Err(AlpenglowError::ProtocolViolation(
                    "Partition not healed within timeout".to_string(),
                ));
            }
        }

        Ok(())
    }

    fn verify_liveness(&self) -> AlpenglowResult<()> {
        // EventualDeliveryProperty: All honest messages eventually delivered after GST
        if self.clock >= self.config.gst + self.config.delta {
            for msg in &self.message_queue {
                if msg.timestamp < self.clock - self.config.delta
                    && !self.config.byzantine_validators.contains(&msg.sender)
                {
                    return Err(AlpenglowError::ProtocolViolation(
                        "Honest message not delivered within expected time".to_string(),
                    ));
                }
            }
        }

        // NetworkHealing: Network partitions are healed after GST
        if self.clock >= self.config.gst + self.config.delta {
            for partition in &self.network_partitions {
                if !partition.healed {
                    return Err(AlpenglowError::ProtocolViolation(
                        "Network partition not healed after GST + Delta".to_string(),
                    ));
                }
            }
        }

        Ok(())
    }

    fn verify_byzantine_resilience(&self) -> AlpenglowResult<()> {
        // Byzantine resilience: Protocol continues despite Byzantine behavior
        let byzantine_count = self.config.byzantine_validators.len();
        let total_validators = self.config.validators.len();

        if byzantine_count >= total_validators / 3 {
            return Err(AlpenglowError::ProtocolViolation(
                "Too many Byzantine validators for safety".to_string(),
            ));
        }

        Ok(())
    }
}

impl TlaCompatible for NetworkState {
    fn to_tla_string(&self) -> String {
        // Serialize the network state to a JSON string representation
        match serde_json::to_string(self) {
            Ok(json_str) => json_str,
            Err(_) => "{}".to_string(),
        }
    }

    /// Export complete network state for TLA+ cross-validation
    /// Matches all TLA+ Network variables exactly
    fn export_tla_state(&self) -> String {
        // Convert message queue to TLA+ format (set of messages)
        let message_queue: Vec<serde_json::Value> = self.message_queue.iter()
            .map(|msg| serde_json::json!({
                "id": msg.id,
                "sender": msg.sender,
                "recipient": match msg.recipient {
                    MessageRecipient::Validator(v) => serde_json::Value::Number(serde_json::Number::from(v)),
                    MessageRecipient::Broadcast => serde_json::Value::String("broadcast".to_string()),
                },
                "type": match msg.msg_type {
                    MessageType::Block => "block",
                    MessageType::Vote => "vote", 
                    MessageType::Certificate => "certificate",
                    MessageType::Shred => "shred",
                    MessageType::Repair => "repair",
                    MessageType::RepairRequest => "repair_request",
                    MessageType::RepairResponse => "repair_response",
                    MessageType::Heartbeat => "heartbeat",
                    MessageType::Byzantine => "byzantine",
                },
                "payload": msg.payload,
                "timestamp": msg.timestamp,
                "signature": msg.signature
            }))
            .collect();

        // Convert message buffer to TLA+ format (function from validator to set of messages)
        let message_buffer: serde_json::Map<String, serde_json::Value> = self.message_buffer.iter()
            .map(|(validator, messages)| {
                let msgs: Vec<serde_json::Value> = messages.iter()
                    .map(|msg| serde_json::json!({
                        "id": msg.id,
                        "sender": msg.sender,
                        "recipient": match msg.recipient {
                            MessageRecipient::Validator(v) => serde_json::Value::Number(serde_json::Number::from(v)),
                            MessageRecipient::Broadcast => serde_json::Value::String("broadcast".to_string()),
                        },
                        "type": match msg.msg_type {
                            MessageType::Block => "block",
                            MessageType::Vote => "vote",
                            MessageType::Certificate => "certificate", 
                            MessageType::Shred => "shred",
                            MessageType::Repair => "repair",
                            MessageType::RepairRequest => "repair_request",
                            MessageType::RepairResponse => "repair_response",
                            MessageType::Heartbeat => "heartbeat",
                            MessageType::Byzantine => "byzantine",
                        },
                        "payload": msg.payload,
                        "timestamp": msg.timestamp,
                        "signature": msg.signature
                    }))
                    .collect();
                (validator.to_string(), serde_json::Value::Array(msgs))
            })
            .collect();

        // Convert network partitions to TLA+ format
        let network_partitions: Vec<serde_json::Value> = self.network_partitions.iter()
            .map(|partition| serde_json::json!({
                "partition1": partition.partition1.iter().collect::<Vec<_>>(),
                "partition2": partition.partition2.iter().collect::<Vec<_>>(),
                "startTime": partition.start_time,
                "healed": partition.healed
            }))
            .collect();

        // Convert delivery time map to TLA+ format (function from message ID to time)
        let delivery_time: serde_json::Map<String, serde_json::Value> = self.delivery_time.iter()
            .map(|(msg_id, time)| (msg_id.to_string(), serde_json::Value::Number(serde_json::Number::from(*time))))
            .collect();

        // Export all TLA+ Network variables exactly as specified
        let json_value = serde_json::json!({
            // Core TLA+ Network variables - mirrors Network.tla exactly
            "messageQueue": message_queue,
            "messageBuffer": message_buffer,
            "networkPartitions": network_partitions,
            "droppedMessages": self.dropped_messages,
            "deliveryTime": delivery_time,
            "clock": self.clock,
            
            // Additional state for complete cross-validation
            "byzantineValidators": self.config.byzantine_validators.iter().collect::<Vec<_>>(),
            "validators": self.config.validators.iter().collect::<Vec<_>>(),
            
            // Network configuration constants - mirrors TLA+ constants
            "GST": self.config.gst,
            "Delta": self.config.delta,
            "MaxMessageSize": self.config.max_message_size,
            "NetworkCapacity": self.config.network_capacity,
            "MaxBufferSize": self.config.max_buffer_size,
            "PartitionTimeout": self.config.partition_timeout,
            
            // Partial synchrony model state
            "partialSynchronyActive": self.clock >= self.config.gst,
            "networkSynchronized": self.network_partitions.iter().all(|p| p.healed),
            
            // Message delivery guarantees state
            "gstDeliveryGuarantees": self.clock >= self.config.gst,
            "boundedDeliveryActive": self.clock >= self.config.gst,
            
            // Performance and health metrics
            "congestionLevel": self.message_queue.len(),
            "averageDeliveryTime": if self.delivery_time.is_empty() { 0 } else {
                self.delivery_time.values().sum::<u64>() / self.delivery_time.len() as u64
            },
            "partitionCount": self.network_partitions.len(),
            "activePartitionCount": self.network_partitions.iter().filter(|p| !p.healed).count(),
            
            // Cross-validation metadata
            "exportTimestamp": self.clock,
            "stateVersion": "1.0",
            "networkVars": ["messageQueue", "messageBuffer", "networkPartitions", "droppedMessages", "deliveryTime", "clock"]
        });

        // Convert JSON to string
        serde_json::to_string(&json_value).unwrap_or_else(|_| "{}".to_string())
    }

    /// Import complete network state from TLA+ model checker
    /// Reconstructs NetworkState from TLA+ exported JSON with comprehensive error handling
    fn import_tla_state(&mut self, state: &NetworkState) -> AlpenglowResult<()> {
        // Copy state from the provided NetworkState reference
        self.clock = state.clock;
        self.message_queue = state.message_queue.clone();
        self.message_buffer = state.message_buffer.clone();
        self.network_partitions = state.network_partitions.clone();
        self.dropped_messages = state.dropped_messages;
        self.delivery_time = state.delivery_time.clone();
        self.byzantine_validators = state.byzantine_validators.clone();
        self.config = state.config.clone();
        self.next_message_id = state.next_message_id;

        // Validate imported state consistency
        self.validate_imported_state()?;

        Ok(())
    }

    /// Import complete network state from TLA+ JSON format
    /// This is a helper method for importing from JSON when needed
    fn import_tla_state_from_json(&mut self, state: serde_json::Value) -> AlpenglowResult<()> {
        // Import clock with validation
        if let Some(clock_val) = state.get("clock") {
            match clock_val.as_u64() {
                Some(clock) => self.clock = clock,
                None => return Err(AlpenglowError::NetworkError(
                    "Invalid clock value in TLA+ state - must be non-negative integer".to_string()
                )),
            }
        } else {
            return Err(AlpenglowError::NetworkError(
                "Missing required 'clock' field in TLA+ state".to_string()
            ));
        }

        // Import dropped messages count with validation
        if let Some(dropped_val) = state.get("droppedMessages") {
            match dropped_val.as_u64() {
                Some(dropped) => self.dropped_messages = dropped,
                None => return Err(AlpenglowError::NetworkError(
                    "Invalid droppedMessages value in TLA+ state - must be non-negative integer".to_string()
                )),
            }
        }

        // Import message queue with comprehensive validation
        if let Some(queue_val) = state.get("messageQueue") {
            if let Some(queue_array) = queue_val.as_array() {
                let mut new_queue = HashSet::new();
                for msg_val in queue_array {
                    let message = self.parse_tla_message(msg_val)?;
                    new_queue.insert(message);
                }
                self.message_queue = new_queue;
            } else {
                return Err(AlpenglowError::NetworkError(
                    "Invalid messageQueue format in TLA+ state - must be array".to_string()
                ));
            }
        }

        // Import message buffer with validation
        if let Some(buffer_val) = state.get("messageBuffer") {
            if let Some(buffer_obj) = buffer_val.as_object() {
                let mut new_buffer = HashMap::new();
                for (validator_str, messages_val) in buffer_obj {
                    let validator: ValidatorId = validator_str.parse()
                        .map_err(|_| AlpenglowError::NetworkError(
                            format!("Invalid validator ID in messageBuffer: {}", validator_str)
                        ))?;
                    
                    if let Some(messages_array) = messages_val.as_array() {
                        let mut validator_messages = HashSet::new();
                        for msg_val in messages_array {
                            let message = self.parse_tla_message(msg_val)?;
                            validator_messages.insert(message);
                        }
                        new_buffer.insert(validator, validator_messages);
                    } else {
                        return Err(AlpenglowError::NetworkError(
                            format!("Invalid message array for validator {} in messageBuffer", validator)
                        ));
                    }
                }
                self.message_buffer = new_buffer;
            } else {
                return Err(AlpenglowError::NetworkError(
                    "Invalid messageBuffer format in TLA+ state - must be object".to_string()
                ));
            }
        }

        // Import network partitions with validation
        if let Some(partitions_val) = state.get("networkPartitions") {
            if let Some(partitions_array) = partitions_val.as_array() {
                let mut new_partitions = HashSet::new();
                for partition_val in partitions_array {
                    let partition = self.parse_tla_partition(partition_val)?;
                    new_partitions.insert(partition);
                }
                self.network_partitions = new_partitions;
            } else {
                return Err(AlpenglowError::NetworkError(
                    "Invalid networkPartitions format in TLA+ state - must be array".to_string()
                ));
            }
        }

        // Import delivery time map with validation
        if let Some(delivery_val) = state.get("deliveryTime") {
            if let Some(delivery_obj) = delivery_val.as_object() {
                let mut new_delivery_time = HashMap::new();
                for (msg_id_str, time_val) in delivery_obj {
                    let msg_id: u64 = msg_id_str.parse()
                        .map_err(|_| AlpenglowError::NetworkError(
                            format!("Invalid message ID in deliveryTime: {}", msg_id_str)
                        ))?;
                    
                    let time = time_val.as_u64()
                        .ok_or_else(|| AlpenglowError::NetworkError(
                            format!("Invalid delivery time for message {}: must be non-negative integer", msg_id)
                        ))?;
                    
                    new_delivery_time.insert(msg_id, time);
                }
                self.delivery_time = new_delivery_time;
            } else {
                return Err(AlpenglowError::NetworkError(
                    "Invalid deliveryTime format in TLA+ state - must be object".to_string()
                ));
            }
        }

        // Import Byzantine validators if present
        if let Some(byzantine_val) = state.get("byzantineValidators") {
            if let Some(byzantine_array) = byzantine_val.as_array() {
                let mut byzantine_set = HashSet::new();
                for validator_val in byzantine_array {
                    let validator = validator_val.as_u64()
                        .ok_or_else(|| AlpenglowError::NetworkError(
                            "Invalid Byzantine validator ID - must be non-negative integer".to_string()
                        ))? as ValidatorId;
                    byzantine_set.insert(validator);
                }
                self.config.byzantine_validators = byzantine_set;
            }
        }

        // Validate imported state consistency
        self.validate_imported_state()?;

        Ok(())
    }

    /// Validate all TLA+ Network invariants with comprehensive checks
    fn validate_tla_invariants(&self) -> AlpenglowResult<()> {
        // Core safety, liveness, and Byzantine resilience checks
        self.verify_safety().map_err(|e| AlpenglowError::ProtocolViolation(
            format!("Safety property violation: {}", e)
        ))?;
        
        self.verify_liveness().map_err(|e| AlpenglowError::ProtocolViolation(
            format!("Liveness property violation: {}", e)
        ))?;
        
        self.verify_byzantine_resilience().map_err(|e| AlpenglowError::ProtocolViolation(
            format!("Byzantine resilience violation: {}", e)
        ))?;

        // NetworkTypeOK invariant - comprehensive type checking
        self.validate_network_type_ok()?;

        // Partial synchrony invariants
        self.validate_partial_synchrony_invariants()?;

        // Message delivery invariants
        self.validate_message_delivery_invariants()?;

        // Network partition invariants
        self.validate_partition_invariants()?;

        // Byzantine behavior invariants
        self.validate_byzantine_invariants()?;

        // Performance and resource invariants
        self.validate_performance_invariants()?;

        Ok(())
    }
}

impl NetworkState {
    /// Parse TLA+ message format into NetworkMessage
    fn parse_tla_message(&self, msg_val: &serde_json::Value) -> AlpenglowResult<NetworkMessage> {
        let _id = msg_val.get("id")
            .and_then(|v| v.as_u64())
            .ok_or_else(|| AlpenglowError::NetworkError("Missing or invalid message ID".to_string()))?;

        let sender = msg_val.get("sender")
            .and_then(|v| v.as_u64())
            .ok_or_else(|| AlpenglowError::NetworkError("Missing or invalid sender".to_string()))? as ValidatorId;

        let recipient = match msg_val.get("recipient") {
            Some(serde_json::Value::Number(n)) => {
                let validator_id = n.as_u64()
                    .ok_or_else(|| AlpenglowError::NetworkError("Invalid recipient validator ID".to_string()))? as ValidatorId;
                MessageRecipient::Validator(validator_id)
            },
            Some(serde_json::Value::String(s)) if s == "broadcast" => MessageRecipient::Broadcast,
            _ => return Err(AlpenglowError::NetworkError("Invalid recipient format".to_string())),
        };

        let msg_type = match msg_val.get("type").and_then(|v| v.as_str()) {
            Some("block") => MessageType::Block,
            Some("vote") => MessageType::Vote,
            Some("certificate") => MessageType::Certificate,
            Some("shred") => MessageType::Shred,
            Some("repair") => MessageType::Repair,
            _ => return Err(AlpenglowError::NetworkError("Invalid or missing message type".to_string())),
        };

        let payload = msg_val.get("payload")
            .and_then(|v| v.as_u64())
            .ok_or_else(|| AlpenglowError::NetworkError("Missing or invalid payload".to_string()))?;

        let timestamp = msg_val.get("timestamp")
            .and_then(|v| v.as_u64())
            .ok_or_else(|| AlpenglowError::NetworkError("Missing or invalid timestamp".to_string()))?;

        let signature = if let Some(sig_val) = msg_val.get("signature") {
            sig_val.as_u64()
                .ok_or_else(|| AlpenglowError::NetworkError("Invalid signature format".to_string()))?
        } else {
            return Err(AlpenglowError::NetworkError("Missing message signature".to_string()));
        };

        Ok(NetworkMessage {
            id: self.next_message_id,
            sender,
            recipient,
            msg_type,
            payload: vec![payload as u8],
            timestamp,
            signature: signature,
        })
    }

    /// Parse TLA+ partition format into NetworkPartition
    fn parse_tla_partition(&self, partition_val: &serde_json::Value) -> AlpenglowResult<NetworkPartition> {
        let partition1_array = partition_val.get("partition1")
            .and_then(|v| v.as_array())
            .ok_or_else(|| AlpenglowError::NetworkError("Missing or invalid partition1".to_string()))?;

        let partition1: Vec<ValidatorId> = partition1_array.iter()
            .map(|v| v.as_u64().ok_or_else(|| AlpenglowError::NetworkError("Invalid validator in partition1".to_string())))
            .collect::<Result<Vec<_>, _>>()?
            .into_iter()
            .map(|v| v as ValidatorId)
            .collect();

        let partition2_array = partition_val.get("partition2")
            .and_then(|v| v.as_array())
            .ok_or_else(|| AlpenglowError::NetworkError("Missing or invalid partition2".to_string()))?;

        let partition2: Vec<ValidatorId> = partition2_array.iter()
            .map(|v| v.as_u64().ok_or_else(|| AlpenglowError::NetworkError("Invalid validator in partition2".to_string())))
            .collect::<Result<Vec<_>, _>>()?
            .into_iter()
            .map(|v| v as ValidatorId)
            .collect();

        let start_time = partition_val.get("startTime")
            .and_then(|v| v.as_u64())
            .ok_or_else(|| AlpenglowError::NetworkError("Missing or invalid startTime".to_string()))?;

        let healed = partition_val.get("healed")
            .and_then(|v| v.as_bool())
            .ok_or_else(|| AlpenglowError::NetworkError("Missing or invalid healed status".to_string()))?;

        Ok(NetworkPartition {
            id: start_time as u32, // Use start_time as ID for imported partitions
            partition1,
            partition2,
            start_time,
            healed,
        })
    }

    /// Validate imported state consistency
    fn validate_imported_state(&self) -> AlpenglowResult<()> {
        // Validate message queue consistency
        for msg in &self.message_queue {
            if !self.config.validators.contains(&msg.sender) {
                return Err(AlpenglowError::NetworkError(
                    format!("Message queue contains invalid sender: {}", msg.sender)
                ));
            }
            
            if let MessageRecipient::Validator(recipient) = msg.recipient {
                if !self.config.validators.contains(&recipient) {
                    return Err(AlpenglowError::NetworkError(
                        format!("Message queue contains invalid recipient: {}", recipient)
                    ));
                }
            }
        }

        // Validate message buffer consistency
        for (validator, messages) in &self.message_buffer {
            if !self.config.validators.contains(validator) {
                return Err(AlpenglowError::NetworkError(
                    format!("Message buffer contains invalid validator: {}", validator)
                ));
            }
            
            for msg in messages {
                if let MessageRecipient::Validator(recipient) = msg.recipient {
                    if recipient != *validator {
                        return Err(AlpenglowError::NetworkError(
                            format!("Message in wrong validator buffer: message for {} in buffer {}", recipient, validator)
                        ));
                    }
                }
            }
        }

        // Validate delivery time consistency
        for (msg_id, delivery_time) in &self.delivery_time {
            if *delivery_time < self.clock {
                // Find corresponding message
                if !self.message_queue.iter().any(|msg| msg.id == *msg_id) {
                    return Err(AlpenglowError::NetworkError(
                        format!("Delivery time exists for non-existent message: {}", msg_id)
                    ));
                }
            }
        }

        // Validate partition consistency
        for partition in &self.network_partitions {
            if partition.partition1.is_empty() || partition.partition2.is_empty() {
                return Err(AlpenglowError::NetworkError(
                    "Network partition contains empty groups".to_string()
                ));
            }
            
            let set1: HashSet<_> = partition.partition1.iter().cloned().collect();
            let set2: HashSet<_> = partition.partition2.iter().cloned().collect();
            if !set1.is_disjoint(&set2) {
                return Err(AlpenglowError::NetworkError(
                    "Network partition groups are not disjoint".to_string()
                ));
            }
        }

        Ok(())
    }

    /// Validate NetworkTypeOK invariant comprehensively
    fn validate_network_type_ok(&self) -> AlpenglowResult<()> {
        // Validate message queue structure
        for msg in &self.message_queue {
            if !self.config.validators.contains(&msg.sender) {
                return Err(AlpenglowError::ProtocolViolation(
                    format!("Invalid sender {} in message queue", msg.sender)
                ));
            }
            
            if let MessageRecipient::Validator(recipient) = msg.recipient {
                if !self.config.validators.contains(&recipient) {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("Invalid recipient {} in message queue", recipient)
                    ));
                }
            }

            // Validate message signature structure
            if !self.config.byzantine_validators.contains(&msg.sender) {
                return Err(AlpenglowError::ProtocolViolation(
                    format!("Message signature from Byzantine validator {}", msg.sender)
                ));
            }
        }

        // Validate message buffer structure
        for (validator, messages) in &self.message_buffer {
            if !self.config.validators.contains(validator) {
                return Err(AlpenglowError::ProtocolViolation(
                    format!("Invalid validator {} in message buffer", validator)
                ));
            }
            
            for msg in messages {
                if let MessageRecipient::Validator(recipient) = msg.recipient {
                    if recipient != *validator {
                        return Err(AlpenglowError::ProtocolViolation(
                            format!("Message for {} found in buffer for {}", recipient, validator)
                        ));
                    }
                }
            }
        }

        // Validate network partitions structure
        for partition in &self.network_partitions {
            for validator in &partition.partition1 {
                if !self.config.validators.contains(validator) {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("Invalid validator {} in partition1", validator)
                    ));
                }
            }
            for validator in &partition.partition2 {
                if !self.config.validators.contains(validator) {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("Invalid validator {} in partition2", validator)
                    ));
                }
            }
        }

        Ok(())
    }

    /// Validate partial synchrony invariants
    fn validate_partial_synchrony_invariants(&self) -> AlpenglowResult<()> {
        // PartialSynchrony invariant from TLA+
        if self.clock >= self.config.gst {
            for msg in &self.message_queue {
                if !self.config.byzantine_validators.contains(&msg.sender) 
                    && msg.timestamp >= self.config.gst {
                    if let Some(&delivery_time) = self.delivery_time.get(&msg.id) {
                        if delivery_time > msg.timestamp + self.config.delta {
                            return Err(AlpenglowError::ProtocolViolation(
                                format!("Message {} violates Delta bound after GST: delivery_time={}, timestamp={}, delta={}", 
                                    msg.id, delivery_time, msg.timestamp, self.config.delta)
                            ));
                        }
                    }
                }
            }
        }

        // GSTDeliveryGuarantees invariant
        if self.clock >= self.config.gst {
            for msg in &self.message_queue {
                if !self.config.byzantine_validators.contains(&msg.sender)
                    && msg.timestamp >= self.config.gst {
                    if !self.delivery_time.contains_key(&msg.id) {
                        return Err(AlpenglowError::ProtocolViolation(
                            format!("Honest message {} after GST missing delivery time", msg.id)
                        ));
                    }
                }
            }
        }

        Ok(())
    }

    /// Validate message delivery invariants
    fn validate_message_delivery_invariants(&self) -> AlpenglowResult<()> {
        // BoundedDeliveryProperty
        if self.clock >= self.config.gst {
            for msg in &self.message_queue {
                if msg.timestamp >= self.config.gst
                    && !self.config.byzantine_validators.contains(&msg.sender) {
                    if let Some(&delivery_time) = self.delivery_time.get(&msg.id) {
                        if delivery_time > msg.timestamp + self.config.delta {
                            return Err(AlpenglowError::ProtocolViolation(
                                format!("Message delivery exceeds Delta bound: msg={}, delivery={}, timestamp={}, delta={}", 
                                    msg.id, delivery_time, msg.timestamp, self.config.delta)
                            ));
                        }
                    }
                }
            }
        }

        // EventualDeliveryProperty
        if self.clock >= self.config.gst + self.config.delta {
            for msg in &self.message_queue {
                if msg.timestamp < self.clock - self.config.delta
                    && !self.config.byzantine_validators.contains(&msg.sender) {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("Honest message {} not delivered within expected time", msg.id)
                    ));
                }
            }
        }

        // MessageOrdering property
        for msg1 in &self.message_queue {
            for msg2 in &self.message_queue {
                if msg1.sender == msg2.sender
                    && msg1.recipient == msg2.recipient
                    && msg1.timestamp < msg2.timestamp
                    && !self.config.byzantine_validators.contains(&msg1.sender)
                    && self.clock >= self.config.gst {
                    if let (Some(&delivery1), Some(&delivery2)) = 
                        (self.delivery_time.get(&msg1.id), self.delivery_time.get(&msg2.id)) {
                        if delivery1 > delivery2 {
                            return Err(AlpenglowError::ProtocolViolation(
                                format!("Message ordering violation: earlier message {} delivered after later message {}", 
                                    msg1.id, msg2.id)
                            ));
                        }
                    }
                }
            }
        }

        Ok(())
    }

    /// Validate network partition invariants
    fn validate_partition_invariants(&self) -> AlpenglowResult<()> {
        // PartitionDetection invariant
        for partition in &self.network_partitions {
            if !partition.healed && self.clock >= partition.start_time + self.config.partition_timeout {
                return Err(AlpenglowError::ProtocolViolation(
                    format!("Partition not healed within timeout: start={}, current={}, timeout={}", 
                        partition.start_time, self.clock, self.config.partition_timeout)
                ));
            }
        }

        // NetworkHealing invariant
        if self.clock >= self.config.gst + self.config.delta {
            for partition in &self.network_partitions {
                if !partition.healed {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("Network partition not healed after GST + Delta: start={}, current={}, gst={}, delta={}", 
                            partition.start_time, self.clock, self.config.gst, self.config.delta)
                    ));
                }
            }
        }

        // Validate partition structure
        for partition in &self.network_partitions {
            if partition.partition1.is_empty() || partition.partition2.is_empty() {
                return Err(AlpenglowError::ProtocolViolation(
                    "Network partition contains empty groups".to_string()
                ));
            }
            
            let set1: HashSet<_> = partition.partition1.iter().cloned().collect();
            let set2: HashSet<_> = partition.partition2.iter().cloned().collect();
            if !set1.is_disjoint(&set2) {
                return Err(AlpenglowError::ProtocolViolation(
                    "Network partition groups are not disjoint".to_string()
                ));
            }

            let all_in_partition: HashSet<_> = set1.union(&set2).cloned().collect();
            if all_in_partition != self.config.validators {
                return Err(AlpenglowError::ProtocolViolation(
                    "Network partition does not cover all validators".to_string()
                ));
            }
        }

        Ok(())
    }

    /// Validate Byzantine behavior invariants
    fn validate_byzantine_invariants(&self) -> AlpenglowResult<()> {
        // NoForgery invariant
        for msg in &self.message_queue {
            if !self.config.byzantine_validators.contains(&msg.sender) && msg.signature == 0 {
                return Err(AlpenglowError::ProtocolViolation(
                    format!("Message forgery detected for honest validator {}", msg.sender)
                ));
            }
        }

        // ChannelIntegrity invariant
        for msg in &self.message_queue {
            if msg.signature != 0 && !self.config.byzantine_validators.contains(&msg.sender) {
                // In a real implementation, this would verify cryptographic integrity
                // For modeling purposes, we check signature consistency
                // Simplified signature validation for u64 type
                if msg.signature != msg.sender as u64 {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("Message signature {} does not match sender {}", 
                            msg.signature, msg.sender)
                    ));
                }
            }
        }

        // Byzantine threshold check
        let byzantine_count = self.config.byzantine_validators.len();
        let total_validators = self.config.validators.len();
        if byzantine_count >= total_validators / 3 {
            return Err(AlpenglowError::ProtocolViolation(
                format!("Too many Byzantine validators: {} out of {} (threshold: {})", 
                    byzantine_count, total_validators, total_validators / 3)
            ));
        }

        Ok(())
    }

    /// Validate performance and resource invariants
    fn validate_performance_invariants(&self) -> AlpenglowResult<()> {
        // BandwidthUtilization invariant
        let current_usage = self.message_queue.len() as u64 * self.config.max_message_size;
        if current_usage > self.config.network_capacity {
            return Err(AlpenglowError::ProtocolViolation(
                format!("Bandwidth utilization exceeds capacity: {} > {}", 
                    current_usage, self.config.network_capacity)
            ));
        }

        // BufferBounds invariant
        for (validator, messages) in &self.message_buffer {
            if messages.len() > self.config.max_buffer_size {
                return Err(AlpenglowError::ProtocolViolation(
                    format!("Message buffer for validator {} exceeds maximum size: {} > {}", 
                        validator, messages.len(), self.config.max_buffer_size)
                ));
            }
        }

        // CongestionControl invariant
        let congestion_level = self.message_queue.len();
        if congestion_level > 1000 {
            // Check if congestion is being reduced
            // This is a simplified check - in practice would track congestion over time
            return Err(AlpenglowError::ProtocolViolation(
                format!("High congestion level not being controlled: {}", congestion_level)
            ));
        }

        Ok(())
    }
}

/// Create a network model for verification
pub fn create_network_model(
    config: Config,
    _byzantine_validators: HashSet<ValidatorId>,
) -> ActorModel<NetworkActor, (), ()> {
    let mut model = ActorModel::new();

    for validator_id in 0..config.validator_count {
        let actor = NetworkActor::new(validator_id as ValidatorId, config.clone());
        model = model.actor(actor);
    }

    model
}

/// Initialize network state - mirrors TLA+ NetworkInit
pub fn network_init(config: NetworkConfig) -> NetworkState {
    let mut message_buffer = HashMap::new();
    for validator in &config.validators {
        message_buffer.insert(*validator, HashSet::new());
    }

    NetworkState {
        clock: 0,
        message_queue: HashSet::new(),
        message_buffer,
        network_partitions: HashSet::new(),
        dropped_messages: 0,
        delivery_time: HashMap::new(),
        byzantine_validators: config.byzantine_validators.clone(),
        config,
        next_message_id: 1,
    }
}

/// Network specification - mirrors TLA+ NetworkSpec
pub struct NetworkSpec {
    pub config: NetworkConfig,
}

impl NetworkSpec {
    pub fn new(config: NetworkConfig) -> Self {
        Self { config }
    }

    /// Check if state satisfies network type invariant
    pub fn network_type_ok(&self, state: &NetworkState) -> bool {
        // All messages in queue have valid structure
        for msg in &state.message_queue {
            if !self.config.validators.contains(&msg.sender) {
                return false;
            }
            
            if let MessageRecipient::Validator(recipient) = msg.recipient {
                if !self.config.validators.contains(&recipient) {
                    return false;
                }
            }
        }

        // All message buffers are for valid validators
        for validator in state.message_buffer.keys() {
            if !self.config.validators.contains(validator) {
                return false;
            }
        }

        // All partitions contain valid validators
        for partition in &state.network_partitions {
            for validator in &partition.partition1 {
                if !self.config.validators.contains(validator) {
                    return false;
                }
            }
            for validator in &partition.partition2 {
                if !self.config.validators.contains(validator) {
                    return false;
                }
            }
        }

        true
    }

    /// Check partial synchrony property
    pub fn partial_synchrony(&self, state: &NetworkState) -> bool {
        if state.clock >= self.config.gst {
            // After GST, all honest messages have bounded delivery
            for msg in &state.message_queue {
                if !self.config.byzantine_validators.contains(&msg.sender) 
                    && msg.timestamp >= self.config.gst {
                    if let Some(&delivery_time) = state.delivery_time.get(&msg.id) {
                        if delivery_time > msg.timestamp + self.config.delta {
                            return false;
                        }
                    }
                }
            }
        }
        true
    }

    /// Check GST delivery guarantees
    pub fn gst_delivery_guarantees(&self, state: &NetworkState) -> bool {
        if state.clock >= self.config.gst {
            for msg in &state.message_queue {
                if !self.config.byzantine_validators.contains(&msg.sender)
                    && msg.timestamp >= self.config.gst {
                    if let Some(&delivery_time) = state.delivery_time.get(&msg.id) {
                        if delivery_time > msg.timestamp + self.config.delta {
                            return false;
                        }
                    } else {
                        return false; // Message should have delivery time
                    }
                }
            }
        }
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_network_actor_creation() {
        let config = Config::default();
        let actor = NetworkActor::new(0, config);
        assert_eq!(actor.validator_id, 0);
    }

    #[test]
    fn test_partial_synchrony_model() {
        let config = Config::default().with_network_timing(100, 1000);
        let mut model = PartialSynchronyModel::new(config);

        assert!(!model.is_synchronous());
        assert_eq!(model.max_message_delay(), 1000); // Before GST

        // Advance past GST
        for _ in 0..1001 {
            model.advance_time();
        }

        assert!(model.is_synchronous());
        assert_eq!(model.max_message_delay(), 100); // After GST
    }

    #[test]
    fn test_send_message() {
        let config = Config::default();
        let actor = NetworkActor::new(0, config.clone());
        let network_config = NetworkConfig::from(config);
        let mut state = network_init(network_config);

        let result = actor.send_message(&mut state, 1, 42);
        assert!(result.is_ok());
        assert_eq!(state.message_queue.len(), 1);
        
        let msg = state.message_queue.iter().next().unwrap();
        assert_eq!(msg.sender, 0);
        assert_eq!(msg.recipient, MessageRecipient::Validator(1));
        assert_eq!(msg.payload, 42);
        assert!(msg.signature != 0);
    }

    #[test]
    fn test_network_partition() {
        let partition = NetworkPartition {
            partition1: [0, 1].iter().cloned().collect(),
            partition2: [2, 3].iter().cloned().collect(),
            start_time: 0,
            healed: false,
        };

        let config = Config::default();
        let actor = NetworkActor::new(0, config);
        let partitions = [partition].iter().cloned().collect();

        assert!(!actor.can_communicate(0, 2, &partitions));
        assert!(actor.can_communicate(0, 1, &partitions));
    }

    #[test]
    fn test_gst_delivery_bounds() {
        let config = Config::default().with_network_timing(50, 1000);
        let actor = NetworkActor::new(0, config);

        // Before GST
        let delay_before = actor.compute_message_delay(500, 0);
        assert_eq!(delay_before, 500); // 10 * max_network_delay

        // After GST
        let delay_after = actor.compute_message_delay(1500, 0);
        assert_eq!(delay_after, 50); // max_network_delay
    }

    #[test]
    fn test_broadcast_message() {
        let config = Config::default().with_validators(4);
        let actor = NetworkActor::new(0, config.clone());
        let network_config = NetworkConfig::from(config);
        let mut state = network_init(network_config);

        let result = actor.broadcast_message(&mut state, 123);
        assert!(result.is_ok());
        assert_eq!(state.message_queue.len(), 3); // Broadcast to 3 other validators
    }

    #[test]
    fn test_deliver_message() {
        let config = Config::default();
        let actor = NetworkActor::new(0, config.clone());
        let network_config = NetworkConfig::from(config);
        let mut state = network_init(network_config);

        // Send a message first
        let _ = actor.send_message(&mut state, 1, 42);
        
        // Set delivery time to current time so it can be delivered
        let msg_id = state.message_queue.iter().next().unwrap().id;
        state.delivery_time.insert(msg_id, state.clock);

        let result = actor.deliver_message(&mut state);
        assert!(result.is_ok());
        assert!(result.unwrap()); // Message was delivered
        assert_eq!(state.message_queue.len(), 0);
        assert_eq!(state.message_buffer.get(&1).unwrap().len(), 1);
    }

    #[test]
    fn test_network_spec() {
        let config = Config::default().with_validators(3);
        let network_config = NetworkConfig::from(config);
        let state = network_init(network_config.clone());
        let spec = NetworkSpec::new(network_config);

        assert!(spec.network_type_ok(&state));
        assert!(spec.partial_synchrony(&state));
        assert!(spec.gst_delivery_guarantees(&state));
    }

    #[test]
    fn test_byzantine_message_injection() {
        let config = Config::default();
        let actor = NetworkActor::new(0, config.clone());
        let mut network_config = NetworkConfig::from(config);
        network_config.byzantine_validators.insert(0); // Mark validator 0 as Byzantine
        let mut state = network_init(network_config);

        let initial_queue_size = state.message_queue.len();
        
        let result = actor.inject_byzantine_message(
            &mut state,
            MessageRecipient::Validator(1),
            999
        );
        
        assert!(result.is_ok());
        assert_eq!(state.message_queue.len(), initial_queue_size + 1);
        
        let fake_msg = state.message_queue.iter().next().unwrap();
        assert_eq!(fake_msg.sender, 0);
        assert_eq!(fake_msg.payload, 999);
        assert!(fake_msg.signature == 0);
    }

    #[test]
    fn test_create_and_heal_partition() {
        let config = Config::default().with_validators(4);
        let actor = NetworkActor::new(0, config.clone());
        let network_config = NetworkConfig::from(config);
        let mut state = network_init(network_config);

        let partition1: HashSet<ValidatorId> = [0, 1].iter().cloned().collect();
        let partition2: HashSet<ValidatorId> = [2, 3].iter().cloned().collect();

        // Create partition
        let result = actor.create_partition(&mut state, partition1.clone(), partition2.clone());
        assert!(result.is_ok());
        assert_eq!(state.network_partitions.len(), 1);

        // Advance time past GST
        state.clock = state.config.gst + 1;

        // Heal partition
        let result = actor.heal_partition(&mut state);
        assert!(result.is_ok());
        assert!(result.unwrap()); // Partition was healed
        
        // Check that partition is marked as healed
        let partition = state.network_partitions.iter().next().unwrap();
        assert!(partition.healed);
    }
}
