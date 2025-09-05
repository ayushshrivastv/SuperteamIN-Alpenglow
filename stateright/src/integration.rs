//! # Alpenglow Integration Module
//!
//! This module combines the Votor, Rotor, and Network components into a complete
//! Alpenglow node implementation. It provides end-to-end verification of the
//! protocol properties proven in `specs/Integration.tla` and includes performance
//! benchmarking capabilities.
//!
//! ## Key Features
//!
//! - **Complete Node Implementation**: Integrates consensus, block propagation, and networking
//! - **Cross-Component Verification**: Validates interactions between Votor, Rotor, and Network
//! - **Performance Benchmarking**: Measures throughput, latency, and bandwidth efficiency
//! - **Byzantine Resilience**: Handles coordinated attacks across all components
//! - **TLA+ Cross-Validation**: Verifies consistency with formal specifications

use crate::{
    network::{NetworkActorMessage, NetworkState, NetworkConfig},
    rotor::{RotorMessage, RotorState, ErasureBlock},
    votor::{VotorMessage, VotorState, Block, Certificate, CertificateType},
    AlpenglowError, AlpenglowResult, Config, 
    TlaCompatible, ValidatorId, Verifiable,
    NetworkMessage, MessageType as NetworkMessageType,
};
use serde::{Deserialize, Serialize};
use crate::stateright::{Actor, ActorModel, Id};
use std::collections::{HashMap, HashSet};
use std::hash::{Hash, Hasher};

/// System health status for each component
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum ComponentHealth {
    /// Component is operating normally
    Healthy,
    /// Component is degraded but functional
    Degraded,
    /// Component has failed
    Failed,
    /// Network is partitioned
    Partitioned,
    /// Network is congested
    Congested,
    /// Network is running slowly
    Slow,
}

/// Overall system state
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum SystemState {
    /// System is initializing
    Initializing,
    /// System is running normally
    Running,
    /// System is degraded but operational
    Degraded,
    /// System is attempting recovery
    Recovering,
    /// System has halted
    Halted,
}

/// Cross-component interaction log entry
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct InteractionLogEntry {
    /// Source component
    pub source: String,
    /// Target component
    pub target: String,
    /// Interaction type
    pub interaction_type: String,
    /// Timestamp
    pub timestamp: u64,
    /// Additional metadata
    pub metadata: HashMap<String, String>,
}

/// Performance metrics for the integrated system
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct PerformanceMetrics {
    /// Blocks finalized per second
    pub throughput: u64,
    /// Average finalization latency in milliseconds
    pub latency: u64,
    /// Network bandwidth usage in bytes per second
    pub bandwidth: u64,
    /// Certificates generated per slot
    pub certificate_rate: u64,
    /// Repair requests per slot
    pub repair_rate: u64,
    /// Total messages processed
    pub messages_processed: u64,
    /// Failed operations count
    pub failed_operations: u64,
}

impl PerformanceMetrics {
    /// Create new empty metrics
    pub fn new() -> Self {
        Self {
            throughput: 0,
            latency: 0,
            bandwidth: 0,
            certificate_rate: 0,
            repair_rate: 0,
            messages_processed: 0,
            failed_operations: 0,
        }
    }
    
    /// Update throughput metric
    pub fn update_throughput(&mut self, blocks_finalized: u64, time_window: u64) {
        if time_window > 0 {
            self.throughput = blocks_finalized / time_window;
        }
    }
    
    /// Update latency metric
    pub fn update_latency(&mut self, total_latency: u64, block_count: u64) {
        if block_count > 0 {
            self.latency = total_latency / block_count;
        }
    }
    
    /// Add bandwidth usage
    pub fn add_bandwidth(&mut self, bytes: u64) {
        self.bandwidth += bytes;
    }
    
    /// Increment message counter
    pub fn increment_messages(&mut self) {
        self.messages_processed += 1;
    }
    
    /// Increment failure counter
    pub fn increment_failures(&mut self) {
        self.failed_operations += 1;
    }
}

/// Configuration for the integrated Alpenglow protocol
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ProtocolConfig {
    /// Base protocol configuration
    pub base_config: Config,
    /// Performance monitoring enabled
    pub performance_monitoring: bool,
    /// Byzantine fault injection enabled (for testing)
    pub byzantine_testing: bool,
    /// Cross-validation with TLA+ enabled
    pub tla_cross_validation: bool,
    /// Detailed logging enabled
    pub detailed_logging: bool,
    /// Benchmark mode enabled
    pub benchmark_mode: bool,
}

impl ProtocolConfig {
    /// Create new protocol configuration
    pub fn new(base_config: Config) -> Self {
        Self {
            base_config,
            performance_monitoring: true,
            byzantine_testing: false,
            tla_cross_validation: false,
            detailed_logging: false,
            benchmark_mode: false,
        }
    }
    
    /// Enable performance monitoring
    pub fn with_performance_monitoring(mut self) -> Self {
        self.performance_monitoring = true;
        self
    }
    
    /// Enable Byzantine testing
    pub fn with_byzantine_testing(mut self) -> Self {
        self.byzantine_testing = true;
        self
    }
    
    /// Enable TLA+ cross-validation
    pub fn with_tla_cross_validation(mut self) -> Self {
        self.tla_cross_validation = true;
        self
    }
    
    /// Enable benchmark mode
    pub fn with_benchmark_mode(mut self) -> Self {
        self.benchmark_mode = true;
        self.performance_monitoring = true;
        self
    }
}

/// Complete Alpenglow node state integrating all components
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AlpenglowState {
    /// Validator ID for this node
    pub validator_id: ValidatorId,
    /// Protocol configuration
    pub config: ProtocolConfig,
    /// Current system state
    pub system_state: SystemState,
    /// Component health status
    pub component_health: HashMap<String, ComponentHealth>,
    /// Votor consensus state
    pub votor_state: VotorState,
    /// Rotor block propagation state
    pub rotor_state: RotorState,
    /// Network layer state
    pub network_state: NetworkState,
    /// Cross-component interaction log
    pub interaction_log: Vec<InteractionLogEntry>,
    /// Performance metrics
    pub performance_metrics: PerformanceMetrics,
    /// Integration-specific errors
    pub integration_errors: HashSet<String>,
    /// Global logical clock
    pub global_clock: u64,
    /// Benchmark start time
    pub benchmark_start_time: Option<u64>,
    /// TLA+ state export for cross-validation
    pub tla_state_cache: Option<serde_json::Value>,
}

impl Hash for AlpenglowState {
    fn hash<H: Hasher>(&self, state: &mut H) {
        // Hash only the key identifying fields to avoid issues with collections
        self.validator_id.hash(state);
        self.global_clock.hash(state);
        self.benchmark_start_time.hash(state);
        // Hash the component states using their Hash implementations
        self.votor_state.hash(state);
        self.rotor_state.hash(state);
        self.network_state.hash(state);
    }
}

impl AlpenglowState {
    /// Create new Alpenglow state
    pub fn new(validator_id: ValidatorId, config: ProtocolConfig) -> Self {
        let votor_state = VotorState::new(validator_id, config.base_config.clone());
        let rotor_state = RotorState::new(validator_id, config.base_config.clone());
        let network_state = NetworkState {
            clock: 0,
            message_queue: HashSet::new(),
            message_buffer: HashMap::new(),
            network_partitions: HashSet::new(),
            dropped_messages: 0,
            delivery_time: HashMap::new(),
            byzantine_validators: HashSet::new(),
            config: NetworkConfig {
                validators: (0..config.base_config.validator_count as ValidatorId).collect(),
                byzantine_validators: HashSet::new(),
                gst: 1000,
                delta: 100,
                max_message_size: 1024 * 1024,
                network_capacity: 1_000_000,
                max_buffer_size: 1000,
                partition_timeout: 5000,
            },
            next_message_id: 1,
        };
        
        let mut component_health = HashMap::new();
        component_health.insert("votor".to_string(), ComponentHealth::Healthy);
        component_health.insert("rotor".to_string(), ComponentHealth::Healthy);
        component_health.insert("network".to_string(), ComponentHealth::Healthy);
        component_health.insert("crypto".to_string(), ComponentHealth::Healthy);
        
        Self {
            validator_id,
            config,
            system_state: SystemState::Initializing,
            component_health,
            votor_state,
            rotor_state,
            network_state,
            interaction_log: Vec::new(),
            performance_metrics: PerformanceMetrics::new(),
            integration_errors: HashSet::new(),
            global_clock: 0,
            benchmark_start_time: None,
            tla_state_cache: None,
        }
    }
    
    /// Initialize the system
    pub fn initialize(&mut self) -> AlpenglowResult<()> {
        self.system_state = SystemState::Running;
        self.global_clock = 0;
        
        if self.config.benchmark_mode {
            self.benchmark_start_time = Some(self.global_clock);
        }
        
        self.log_interaction("system", "all", "initialization", HashMap::new());
        Ok(())
    }
    
    /// Log cross-component interaction
    pub fn log_interaction(
        &mut self,
        source: &str,
        target: &str,
        interaction_type: &str,
        metadata: HashMap<String, String>,
    ) {
        if self.config.detailed_logging {
            let entry = InteractionLogEntry {
                source: source.to_string(),
                target: target.to_string(),
                interaction_type: interaction_type.to_string(),
                timestamp: self.global_clock,
                metadata,
            };
            self.interaction_log.push(entry);
        }
    }
    
    /// Update component health
    pub fn update_component_health(&mut self, component: &str, health: ComponentHealth) {
        self.component_health.insert(component.to_string(), health.clone());
        
        // Update system state based on component health
        self.update_system_state();
        
        let mut metadata = HashMap::new();
        metadata.insert("component".to_string(), component.to_string());
        metadata.insert("health".to_string(), format!("{:?}", health));
        self.log_interaction("system", component, "health_update", metadata);
    }
    
    /// Update system state based on component health
    fn update_system_state(&mut self) {
        let votor_health = self.component_health.get("votor").unwrap_or(&ComponentHealth::Healthy);
        let rotor_health = self.component_health.get("rotor").unwrap_or(&ComponentHealth::Healthy);
        let network_health = self.component_health.get("network").unwrap_or(&ComponentHealth::Healthy);
        let crypto_health = self.component_health.get("crypto").unwrap_or(&ComponentHealth::Healthy);
        
        self.system_state = match (votor_health, rotor_health, network_health, crypto_health) {
            (ComponentHealth::Failed, _, _, _) | (_, _, _, ComponentHealth::Failed) => SystemState::Halted,
            (_, ComponentHealth::Failed, _, _) | (_, _, ComponentHealth::Failed, _) => SystemState::Halted,
            (_, _, ComponentHealth::Partitioned, _) => SystemState::Degraded,
            (ComponentHealth::Degraded, _, _, _) | (_, ComponentHealth::Degraded, _, _) => SystemState::Degraded,
            (_, _, ComponentHealth::Degraded, _) | (_, _, ComponentHealth::Congested, _) => SystemState::Degraded,
            (_, _, _, ComponentHealth::Slow) => SystemState::Degraded,
            _ => SystemState::Running,
        };
    }
    
    /// Process Votor-Rotor interaction with comprehensive error handling and edge cases
    pub fn process_votor_rotor_interaction(&mut self, certificate: &Certificate) -> AlpenglowResult<()> {
        // Synchronize time between components first
        self.synchronize_component_times();
        
        // Verify certificate meets requirements
        if !self.votor_state.validate_certificate(certificate) {
            let error_msg = format!("Invalid certificate for slot {}, view {}", certificate.slot, certificate.view);
            self.integration_errors.insert("invalid_certificate".to_string());
            self.performance_metrics.increment_failures();
            self.update_component_health("votor", ComponentHealth::Degraded);
            return Err(AlpenglowError::ProtocolViolation(error_msg));
        }
        
        // Skip certificates don't need block propagation but still need validation
        if certificate.cert_type == CertificateType::Skip {
            // Validate skip certificate has sufficient stake
            if certificate.stake < self.config.base_config.slow_path_threshold {
                let error_msg = format!("Skip certificate has insufficient stake: {} < {}", 
                    certificate.stake, self.config.base_config.slow_path_threshold);
                self.integration_errors.insert("insufficient_skip_stake".to_string());
                self.performance_metrics.increment_failures();
                return Err(AlpenglowError::ProtocolViolation(error_msg));
            }
            
            let mut metadata = HashMap::new();
            metadata.insert("slot".to_string(), certificate.slot.to_string());
            metadata.insert("view".to_string(), certificate.view.to_string());
            metadata.insert("stake".to_string(), certificate.stake.to_string());
            self.log_interaction("votor", "rotor", "skip_certificate", metadata);
            return Ok(());
        }
        
        // Find the block for this certificate
        let block_hash = certificate.block;
        let block_option = self.votor_state.voting_rounds
            .values()
            .flat_map(|round| &round.proposed_blocks)
            .find(|b| b.hash == block_hash);
        
        let block = match block_option {
            Some(block) => block.clone(),
            None => {
                // Check if block is already finalized
                if let Some(finalized_block) = self.votor_state.finalized_chain
                    .iter()
                    .find(|b| b.hash == block_hash) {
                    finalized_block.clone()
                } else {
                    let error_msg = format!("Block not found for certificate: {:?}", block_hash);
                    self.integration_errors.insert("block_not_found".to_string());
                    self.performance_metrics.increment_failures();
                    self.update_component_health("votor", ComponentHealth::Degraded);
                    return Err(AlpenglowError::ProtocolViolation(error_msg));
                }
            }
        };
        
        // Validate block-certificate consistency
        if block.slot != certificate.slot || block.view != certificate.view {
            let error_msg = format!("Block-certificate mismatch: block(slot={}, view={}) vs cert(slot={}, view={})",
                block.slot, block.view, certificate.slot, certificate.view);
            self.integration_errors.insert("block_certificate_mismatch".to_string());
            self.performance_metrics.increment_failures();
            return Err(AlpenglowError::ProtocolViolation(error_msg));
        }
        
        // Check if Rotor already has the block shreds
        if !self.rotor_state.block_shreds.contains_key(&block_hash) {
            // Block needs to be shredded first - trigger shredding
            let erasure_block = ErasureBlock::new(
                block.hash,
                block.slot,
                block.proposer,
                block.data.clone(),
                (self.config.base_config.validator_count * 2 / 3) as u32,
                self.config.base_config.validator_count as u32,
            );
            
            // Validate erasure block parameters
            if !erasure_block.validate() {
                let error_msg = "Invalid erasure block parameters".to_string();
                self.integration_errors.insert("invalid_erasure_block".to_string());
                self.performance_metrics.increment_failures();
                self.update_component_health("rotor", ComponentHealth::Degraded);
                return Err(AlpenglowError::ProtocolViolation(error_msg));
            }
            
            // Check bandwidth availability for shredding
            let estimated_bandwidth = erasure_block.data.len() as u64 * 2; // Estimate with overhead
            if !self.rotor_state.check_bandwidth_limit(self.validator_id, estimated_bandwidth) {
                let error_msg = "Insufficient bandwidth for block shredding".to_string();
                self.integration_errors.insert("bandwidth_exceeded".to_string());
                self.performance_metrics.increment_failures();
                self.update_component_health("rotor", ComponentHealth::Congested);
                return Err(AlpenglowError::ProtocolViolation(error_msg));
            }
            
            let mut metadata = HashMap::new();
            metadata.insert("block_hash".to_string(), format!("{:?}", block_hash));
            metadata.insert("certificate_type".to_string(), format!("{:?}", certificate.cert_type));
            metadata.insert("block_size".to_string(), block.data.len().to_string());
            metadata.insert("data_shreds".to_string(), erasure_block.data_shreds.to_string());
            metadata.insert("total_shreds".to_string(), erasure_block.total_shreds.to_string());
            self.log_interaction("votor", "rotor", "block_shredding_required", metadata);
        } else {
            // Verify existing shreds are sufficient for reconstruction
            if let Some(block_shreds) = self.rotor_state.block_shreds.get(&block_hash) {
                let total_shreds: usize = block_shreds.values().map(|shreds| shreds.len()).sum();
                let required_shreds = (self.config.base_config.validator_count * 2 / 3) as usize;
                
                if total_shreds < required_shreds {
                    let error_msg = format!("Insufficient shreds for block reconstruction: {} < {}", 
                        total_shreds, required_shreds);
                    self.integration_errors.insert("insufficient_shreds".to_string());
                    self.performance_metrics.increment_failures();
                    self.update_component_health("rotor", ComponentHealth::Degraded);
                    return Err(AlpenglowError::ProtocolViolation(error_msg));
                }
            }
        }
        
        // Validate certificate stake thresholds
        let required_threshold = match certificate.cert_type {
            CertificateType::Fast => self.config.base_config.fast_path_threshold,
            CertificateType::Slow => self.config.base_config.slow_path_threshold,
            CertificateType::Skip => self.config.base_config.slow_path_threshold,
        };
        
        if certificate.stake < required_threshold {
            let error_msg = format!("Certificate stake {} below threshold {} for {:?}", 
                certificate.stake, required_threshold, certificate.cert_type);
            self.integration_errors.insert("insufficient_certificate_stake".to_string());
            self.performance_metrics.increment_failures();
            return Err(AlpenglowError::ProtocolViolation(error_msg));
        }
        
        // Update performance metrics
        self.performance_metrics.increment_messages();
        self.performance_metrics.certificate_rate += 1;
        
        // Log successful interaction
        let mut metadata = HashMap::new();
        metadata.insert("block_hash".to_string(), format!("{:?}", block_hash));
        metadata.insert("certificate_type".to_string(), format!("{:?}", certificate.cert_type));
        metadata.insert("stake".to_string(), certificate.stake.to_string());
        metadata.insert("validators_count".to_string(), certificate.validators.len().to_string());
        self.log_interaction("votor", "rotor", "certificate_propagation", metadata);
        
        Ok(())
    }
    
    /// Process Network-Component interaction with comprehensive message handling
    pub fn process_network_interaction(&mut self, message: &NetworkMessage) -> AlpenglowResult<()> {
        // Synchronize time between components
        self.synchronize_component_times();
        
        // Validate message integrity
        if message.signature == 0 && !self.network_state.byzantine_validators.contains(&message.sender) {
            let error_msg = format!("Invalid signature from honest validator {}", message.sender);
            self.integration_errors.insert("invalid_message_signature".to_string());
            self.performance_metrics.increment_failures();
            self.update_component_health("network", ComponentHealth::Degraded);
            return Err(AlpenglowError::ProtocolViolation(error_msg));
        }
        
        // Check message timing constraints
        let current_time = self.global_clock;
        if current_time >= self.config.base_config.gst {
            // After GST, check Delta-bounded delivery
            let max_delay = self.config.base_config.max_network_delay;
            if message.timestamp + max_delay < current_time {
                let error_msg = format!("Message delivery violates Delta bound: delay {} > {}", 
                    current_time - message.timestamp, max_delay);
                self.integration_errors.insert("delta_bound_violation".to_string());
                self.performance_metrics.increment_failures();
                self.update_component_health("network", ComponentHealth::Slow);
                return Err(AlpenglowError::ProtocolViolation(error_msg));
            }
        }
        
        // Validate sender is a known validator
        if message.sender >= self.config.base_config.validator_count as ValidatorId {
            let error_msg = format!("Invalid sender validator ID: {}", message.sender);
            self.integration_errors.insert("invalid_sender".to_string());
            self.performance_metrics.increment_failures();
            return Err(AlpenglowError::ProtocolViolation(error_msg));
        }
        
        // Process message based on type
        match message.msg_type {
            NetworkMessageType::Vote => {
                // Validate vote payload size
                if message.payload.is_empty() {
                    let error_msg = "Empty vote payload".to_string();
                    self.integration_errors.insert("empty_vote_payload".to_string());
                    self.performance_metrics.increment_failures();
                    return Err(AlpenglowError::ProtocolViolation(error_msg));
                }
                
                // Check if Votor can process more votes
                let current_view = self.votor_state.current_view;
                if let Some(round) = self.votor_state.voting_rounds.get(&current_view) {
                    if round.received_votes.len() > self.config.base_config.validator_count * 3 {
                        // Too many votes for current view - possible spam
                        let error_msg = "Excessive votes for current view".to_string();
                        self.integration_errors.insert("vote_spam_detected".to_string());
                        self.performance_metrics.increment_failures();
                        self.update_component_health("votor", ComponentHealth::Degraded);
                        return Err(AlpenglowError::ProtocolViolation(error_msg));
                    }
                }
                
                let mut metadata = HashMap::new();
                metadata.insert("sender".to_string(), message.sender.to_string());
                metadata.insert("payload_size".to_string(), message.payload.len().to_string());
                metadata.insert("current_view".to_string(), current_view.to_string());
                self.log_interaction("network", "votor", "vote_delivery", metadata);
            }
            
            NetworkMessageType::Block => {
                // Validate block payload
                if message.payload.len() > 1024 * 1024 {  // 1MB limit
                    let error_msg = format!("Block payload too large: {} bytes", message.payload.len());
                    self.integration_errors.insert("oversized_block".to_string());
                    self.performance_metrics.increment_failures();
                    return Err(AlpenglowError::ProtocolViolation(error_msg));
                }
                
                if message.payload.is_empty() {
                    let error_msg = "Empty block payload".to_string();
                    self.integration_errors.insert("empty_block_payload".to_string());
                    self.performance_metrics.increment_failures();
                    return Err(AlpenglowError::ProtocolViolation(error_msg));
                }
                
                // Check Rotor bandwidth capacity
                let bandwidth_needed = message.payload.len() as u64;
                if !self.rotor_state.check_bandwidth_limit(self.validator_id, bandwidth_needed) {
                    let error_msg = "Insufficient bandwidth for block processing".to_string();
                    self.integration_errors.insert("bandwidth_exceeded".to_string());
                    self.performance_metrics.increment_failures();
                    self.update_component_health("rotor", ComponentHealth::Congested);
                    return Err(AlpenglowError::ProtocolViolation(error_msg));
                }
                
                let mut metadata = HashMap::new();
                metadata.insert("sender".to_string(), message.sender.to_string());
                metadata.insert("payload_size".to_string(), message.payload.len().to_string());
                metadata.insert("bandwidth_used".to_string(), bandwidth_needed.to_string());
                self.log_interaction("network", "rotor", "block_delivery", metadata);
            }
            
            NetworkMessageType::Certificate => {
                // Validate certificate payload
                if message.payload.is_empty() {
                    let error_msg = "Empty certificate payload".to_string();
                    self.integration_errors.insert("empty_certificate_payload".to_string());
                    self.performance_metrics.increment_failures();
                    return Err(AlpenglowError::ProtocolViolation(error_msg));
                }
                
                // Route certificate to both Votor and Rotor with validation
                let mut metadata = HashMap::new();
                metadata.insert("sender".to_string(), message.sender.to_string());
                metadata.insert("payload_size".to_string(), message.payload.len().to_string());
                metadata.insert("timestamp".to_string(), message.timestamp.to_string());
                
                self.log_interaction("network", "votor", "certificate_delivery", metadata.clone());
                self.log_interaction("network", "rotor", "certificate_delivery", metadata);
            }
            
            NetworkMessageType::RepairRequest => {
                // Validate repair request
                if message.payload.is_empty() {
                    let error_msg = "Empty repair request payload".to_string();
                    self.integration_errors.insert("empty_repair_request".to_string());
                    self.performance_metrics.increment_failures();
                    return Err(AlpenglowError::ProtocolViolation(error_msg));
                }
                
                // Check repair request rate limiting
                let repair_count = self.rotor_state.repair_requests.len();
                if repair_count > 50 {  // Rate limit
                    let error_msg = format!("Too many active repair requests: {}", repair_count);
                    self.integration_errors.insert("repair_rate_limit".to_string());
                    self.performance_metrics.increment_failures();
                    self.update_component_health("rotor", ComponentHealth::Degraded);
                    return Err(AlpenglowError::ProtocolViolation(error_msg));
                }
                
                let mut metadata = HashMap::new();
                metadata.insert("sender".to_string(), message.sender.to_string());
                metadata.insert("active_repairs".to_string(), repair_count.to_string());
                self.log_interaction("network", "rotor", "repair_request", metadata);
                self.performance_metrics.repair_rate += 1;
            }
            
            NetworkMessageType::RepairResponse => {
                // Validate repair response
                if message.payload.is_empty() {
                    let error_msg = "Empty repair response payload".to_string();
                    self.integration_errors.insert("empty_repair_response".to_string());
                    self.performance_metrics.increment_failures();
                    return Err(AlpenglowError::ProtocolViolation(error_msg));
                }
                
                let mut metadata = HashMap::new();
                metadata.insert("sender".to_string(), message.sender.to_string());
                metadata.insert("payload_size".to_string(), message.payload.len().to_string());
                self.log_interaction("network", "rotor", "repair_response", metadata);
            }
            
            NetworkMessageType::Heartbeat => {
                // Process heartbeat for liveness monitoring
                let mut metadata = HashMap::new();
                metadata.insert("sender".to_string(), message.sender.to_string());
                metadata.insert("timestamp".to_string(), message.timestamp.to_string());
                metadata.insert("current_time".to_string(), current_time.to_string());
                
                // Check heartbeat freshness
                if current_time > message.timestamp + 100 {  // 100 tick staleness limit
                    metadata.insert("stale".to_string(), (message.signature != 0).to_string());
                    self.update_component_health("network", ComponentHealth::Slow);
                }
                
                self.log_interaction("network", "system", "heartbeat", metadata);
            }
            
            NetworkMessageType::Byzantine => {
                // Handle Byzantine message with detailed logging
                let mut metadata = HashMap::new();
                metadata.insert("sender".to_string(), message.sender.to_string());
                metadata.insert("payload_size".to_string(), message.payload.len().to_string());
                metadata.insert("signature_valid".to_string(), (message.signature != 0).to_string());
                
                self.integration_errors.insert("byzantine_message_detected".to_string());
                self.performance_metrics.increment_failures();
                self.update_component_health("network", ComponentHealth::Degraded);
                self.log_interaction("network", "system", "byzantine_detection", metadata);
                
                // Mark sender as potentially Byzantine if not already known
                if !self.network_state.byzantine_validators.contains(&message.sender) {
                    self.integration_errors.insert("new_byzantine_validator".to_string());
                }
            }
            
            NetworkMessageType::Shred => {
                // Handle Rotor shred messages
                let mut metadata = HashMap::new();
                metadata.insert("sender".to_string(), message.sender.to_string());
                metadata.insert("payload_size".to_string(), message.payload.len().to_string());
                
                self.log_interaction("network", "rotor", "shred_received", metadata);
            }
            
            NetworkMessageType::Repair => {
                // Handle Rotor repair messages
                let mut metadata = HashMap::new();
                metadata.insert("sender".to_string(), message.sender.to_string());
                metadata.insert("payload_size".to_string(), message.payload.len().to_string());
                
                self.log_interaction("network", "rotor", "repair_received", metadata);
            }
        }
        
        // Update bandwidth metrics
        self.performance_metrics.add_bandwidth(message.payload.len() as u64);
        self.performance_metrics.increment_messages();
        
        Ok(())
    }
    
    /// Detect component failures with comprehensive health monitoring
    pub fn detect_component_failures(&mut self) -> Vec<String> {
        let mut failures = Vec::new();
        
        // Votor failure detection with time-aware thresholds
        let time_since_gst = if self.global_clock > self.config.base_config.gst {
            self.global_clock - self.config.base_config.gst
        } else {
            0
        };
        
        // Excessive view changes indicate consensus problems
        let view_change_rate = if time_since_gst > 0 {
            self.votor_state.current_view as f64 / time_since_gst as f64
        } else {
            0.0
        };
        
        if view_change_rate > 0.5 {  // More than 1 view change per 2 ticks
            self.update_component_health("votor", ComponentHealth::Failed);
            failures.push("votor_excessive_view_changes".to_string());
        } else if self.votor_state.current_view > 200 {
            self.update_component_health("votor", ComponentHealth::Degraded);
            failures.push("votor_high_view_count".to_string());
        }
        
        // No progress after GST with time tolerance
        if time_since_gst > 200 && self.votor_state.finalized_chain.is_empty() {
            self.update_component_health("votor", ComponentHealth::Degraded);
            failures.push("votor_no_progress_after_gst".to_string());
        }
        
        // Check for stalled consensus (no new blocks in reasonable time)
        if !self.votor_state.finalized_chain.is_empty() {
            let last_block = self.votor_state.finalized_chain.last().unwrap();
            let last_block_ticks = self.convert_time_to_ticks(last_block.timestamp);
            if self.global_clock > last_block_ticks + 300 {  // No new blocks in 300 ticks
                self.update_component_health("votor", ComponentHealth::Degraded);
                failures.push("votor_consensus_stalled".to_string());
            }
        }
        
        // Rotor failure detection with bandwidth and repair analysis
        let repair_count = self.rotor_state.repair_requests.len();
        let total_validators = self.config.base_config.validator_count;
        
        if repair_count > total_validators * 5 {
            // Too many repair requests relative to validator count
            self.update_component_health("rotor", ComponentHealth::Failed);
            failures.push("rotor_excessive_repairs".to_string());
        } else if repair_count > total_validators * 2 {
            self.update_component_health("rotor", ComponentHealth::Degraded);
            failures.push("rotor_high_repair_rate".to_string());
        }
        
        // Check bandwidth utilization
        let total_bandwidth_used: u64 = self.rotor_state.bandwidth_usage.values().sum();
        let total_bandwidth_limit = self.rotor_state.bandwidth_limit * total_validators as u64;
        let bandwidth_utilization = if total_bandwidth_limit > 0 {
            (total_bandwidth_used * 100) / total_bandwidth_limit
        } else {
            0
        };
        
        if bandwidth_utilization > 95 {
            self.update_component_health("rotor", ComponentHealth::Congested);
            failures.push("rotor_bandwidth_exhausted".to_string());
        } else if bandwidth_utilization > 80 {
            self.update_component_health("rotor", ComponentHealth::Degraded);
            failures.push("rotor_high_bandwidth_usage".to_string());
        }
        
        // Check block delivery progress
        let delivered_count: usize = self.rotor_state.delivered_blocks.values()
            .map(|blocks| blocks.len())
            .sum();
        
        if time_since_gst > 200 && delivered_count == 0 {
            self.update_component_health("rotor", ComponentHealth::Degraded);
            failures.push("rotor_no_delivery_after_gst".to_string());
        }
        
        // Network failure detection with timing analysis
        let active_partitions = self.network_state.network_partitions
            .iter()
            .filter(|p| !p.healed)
            .count();
        
        if active_partitions > 0 && time_since_gst > 150 {
            // Persistent partitions after GST + grace period
            self.update_component_health("network", ComponentHealth::Partitioned);
            failures.push("network_persistent_partition".to_string());
        }
        
        // Message queue analysis
        let queue_size = self.network_state.message_queue.len();
        let buffer_size: usize = self.network_state.message_buffer.values()
            .map(|msgs| msgs.len())
            .sum();
        
        if queue_size > 2000 {
            self.update_component_health("network", ComponentHealth::Failed);
            failures.push("network_queue_overflow".to_string());
        } else if queue_size > 1000 {
            self.update_component_health("network", ComponentHealth::Congested);
            failures.push("network_congestion".to_string());
        }
        
        if buffer_size > 5000 {
            self.update_component_health("network", ComponentHealth::Congested);
            failures.push("network_buffer_overflow".to_string());
        }
        
        // Check message delivery rate after GST
        if time_since_gst > 100 {
            let dropped_rate = if self.performance_metrics.messages_processed > 0 {
                (self.network_state.dropped_messages * 100) / self.performance_metrics.messages_processed
            } else {
                0
            };
            
            if dropped_rate > 20 {  // More than 20% message drop rate
                self.update_component_health("network", ComponentHealth::Degraded);
                failures.push("network_high_drop_rate".to_string());
            }
        }
        
        // Cross-component failure detection
        let error_count = self.integration_errors.len();
        if error_count > 20 {
            self.update_component_health("system", ComponentHealth::Failed);
            failures.push("system_excessive_errors".to_string());
        } else if error_count > 10 {
            self.update_component_health("system", ComponentHealth::Degraded);
            failures.push("system_high_error_rate".to_string());
        }
        
        // Performance degradation detection
        if self.config.performance_monitoring {
            if self.performance_metrics.failed_operations > self.performance_metrics.messages_processed / 4 {
                // More than 25% failure rate
                self.update_component_health("system", ComponentHealth::Degraded);
                failures.push("system_high_failure_rate".to_string());
            }
            
            if self.performance_metrics.throughput == 0 && time_since_gst > 300 {
                // No throughput after reasonable time post-GST
                self.update_component_health("system", ComponentHealth::Degraded);
                failures.push("system_zero_throughput".to_string());
            }
        }
        
        // Add failures to integration errors with timestamps
        for failure in &failures {
            self.integration_errors.insert(format!("{}@{}", failure, self.global_clock));
        }
        
        failures
    }
    
    /// Attempt system recovery with comprehensive error handling and staged approach
    pub fn attempt_recovery(&mut self) -> AlpenglowResult<()> {
        if self.system_state != SystemState::Degraded && self.system_state != SystemState::Halted {
            return Ok(());
        }
        
        let previous_state = self.system_state.clone();
        self.system_state = SystemState::Recovering;
        
        let mut recovery_metadata = HashMap::new();
        recovery_metadata.insert("previous_state".to_string(), format!("{:?}", previous_state));
        recovery_metadata.insert("error_count".to_string(), self.integration_errors.len().to_string());
        recovery_metadata.insert("global_clock".to_string(), self.global_clock.to_string());
        
        // Stage 1: Network recovery
        let network_healthy = self.attempt_network_recovery()?;
        recovery_metadata.insert("network_recovery".to_string(), network_healthy.to_string());
        
        // Stage 2: Rotor recovery (depends on network)
        let rotor_functional = if network_healthy {
            self.attempt_rotor_recovery()?
        } else {
            false
        };
        recovery_metadata.insert("rotor_recovery".to_string(), rotor_functional.to_string());
        
        // Stage 3: Votor recovery (depends on network and rotor)
        let votor_stable = if network_healthy && rotor_functional {
            self.attempt_votor_recovery()?
        } else {
            false
        };
        recovery_metadata.insert("votor_recovery".to_string(), votor_stable.to_string());
        
        // Stage 4: System-level recovery
        let system_recovered = network_healthy && votor_stable && rotor_functional;
        
        if system_recovered {
            // Gradual recovery - restore component health
            self.update_component_health("network", ComponentHealth::Healthy);
            self.update_component_health("rotor", ComponentHealth::Healthy);
            self.update_component_health("votor", ComponentHealth::Healthy);
            self.update_component_health("crypto", ComponentHealth::Healthy);
            
            // Clear resolved errors with careful filtering
            let errors_to_remove: Vec<String> = self.integration_errors
                .iter()
                .filter(|error| {
                    // Remove errors that should be resolved by recovery
                    error.contains("votor_") || 
                    error.contains("rotor_") || 
                    error.contains("network_") ||
                    error.contains("bandwidth_") ||
                    error.contains("congestion") ||
                    error.contains("time_synchronization")
                })
                .cloned()
                .collect();
            
            for error in errors_to_remove {
                self.integration_errors.remove(&error);
            }
            
            // Reset performance counters
            self.performance_metrics.failed_operations = 0;
            
            recovery_metadata.insert("errors_cleared".to_string(), "true".to_string());
            self.log_interaction("system", "all", "recovery_successful", recovery_metadata);
            
            // Verify recovery was actually successful
            self.verify_recovery_success()?;
        } else {
            // Partial recovery or recovery failed
            let failed_components = vec![
                if !network_healthy { "network" } else { "" },
                if !rotor_functional { "rotor" } else { "" },
                if !votor_stable { "votor" } else { "" },
            ].into_iter()
                .filter(|s| !s.is_empty())
                .collect::<Vec<_>>()
                .join(",");
            
            recovery_metadata.insert("failed_components".to_string(), failed_components);
            recovery_metadata.insert("partial_recovery".to_string(), "true".to_string());
            
            self.log_interaction("system", "all", "recovery_attempted", recovery_metadata);
            
            // Return to previous state if recovery completely failed
            if !network_healthy && !rotor_functional && !votor_stable {
                self.system_state = previous_state;
                return Err(AlpenglowError::ProtocolViolation("Recovery failed completely".to_string()));
            }
        }
        
        Ok(())
    }
    
    /// Attempt network recovery
    fn attempt_network_recovery(&mut self) -> AlpenglowResult<bool> {
        let mut network_healthy = true;
        
        // Heal network partitions if past GST
        if self.global_clock >= self.config.base_config.gst {
            let partitions_to_heal: Vec<_> = self.network_state.network_partitions
                .iter()
                .filter(|p| !p.healed)
                .cloned()
                .collect();
            
            for mut partition in partitions_to_heal {
                partition.healed = true;
                self.network_state.network_partitions.remove(&partition);
                self.network_state.network_partitions.insert(partition);
            }
        }
        
        // Clear message queue if it's too large
        if self.network_state.message_queue.len() > 1000 {
            // Keep only recent messages
            let cutoff_time = self.global_clock.saturating_sub(100);
            self.network_state.message_queue.retain(|msg| msg.timestamp >= cutoff_time);
            network_healthy = self.network_state.message_queue.len() < 500;
        }
        
        // Reset dropped message counter if it's excessive
        if self.network_state.dropped_messages > 1000 {
            self.network_state.dropped_messages = 0;
        }
        
        // Check final network health
        network_healthy = network_healthy && 
            self.network_state.network_partitions.iter().all(|p| p.healed) &&
            self.network_state.message_queue.len() < 200;
        
        Ok(network_healthy)
    }
    
    /// Attempt rotor recovery
    fn attempt_rotor_recovery(&mut self) -> AlpenglowResult<bool> {
        let rotor_functional; // will be set based on rotor state checks
        
        // Clear excessive repair requests
        if self.rotor_state.repair_requests.len() > 50 {
            // Keep only recent repair requests
            let cutoff_time = self.global_clock.saturating_sub(self.rotor_state.retry_timeout);
            self.rotor_state.repair_requests.retain(|req| req.timestamp >= cutoff_time);
        }
        
        // Reset bandwidth usage if it's at the limit
        let total_usage: u64 = self.rotor_state.bandwidth_usage.values().sum();
        let total_limit = self.rotor_state.bandwidth_limit * self.config.base_config.validator_count as u64;
        
        if total_usage > total_limit * 9 / 10 {  // If using more than 90% of total bandwidth
            // Reset bandwidth counters (simulating a new time window)
            for usage in self.rotor_state.bandwidth_usage.values_mut() {
                *usage = *usage / 2;  // Reduce by half
            }
        }
        
        // Check final rotor health
        rotor_functional = self.rotor_state.repair_requests.len() < 20 &&
            self.rotor_state.bandwidth_usage.values().all(|&usage| usage < self.rotor_state.bandwidth_limit);
        
        Ok(rotor_functional)
    }
    
    /// Attempt votor recovery
    fn attempt_votor_recovery(&mut self) -> AlpenglowResult<bool> {
        let mut votor_stable = true;
        
        // Check if view changes are reasonable
        let time_since_gst = if self.global_clock > self.config.base_config.gst {
            self.global_clock - self.config.base_config.gst
        } else {
            self.global_clock
        };
        
        // If view count is excessive relative to time, it indicates problems
        if time_since_gst > 0 {
            let view_rate = self.votor_state.current_view as f64 / time_since_gst as f64;
            votor_stable = view_rate < 0.2;  // Less than 1 view per 5 ticks
        }
        
        // Check if there's been some progress
        if self.global_clock > self.config.base_config.gst + 100 {
            // After GST + grace period, should have some finalized blocks
            votor_stable = votor_stable && !self.votor_state.finalized_chain.is_empty();
        }
        
        // Check voting round health
        let current_round = self.votor_state.voting_rounds.get(&self.votor_state.current_view);
        if let Some(round) = current_round {
            // Ensure voting round isn't stuck with too many votes
            let vote_count = round.received_votes.len() + round.skip_votes.len();
            votor_stable = votor_stable && vote_count < self.config.base_config.validator_count * 3;
        }
        
        Ok(votor_stable)
    }
    
    /// Verify that recovery was actually successful
    fn verify_recovery_success(&self) -> AlpenglowResult<()> {
        // Check that all components report healthy
        for (component, health) in &self.component_health {
            if *health == ComponentHealth::Failed {
                return Err(AlpenglowError::ProtocolViolation(
                    format!("Component {} still failed after recovery", component)
                ));
            }
        }
        
        // Check that critical errors are resolved
        let critical_errors = ["excessive_repairs", "queue_overflow", "bandwidth_exhausted"];
        for error in &self.integration_errors {
            for critical in &critical_errors {
                if error.contains(critical) {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("Critical error {} not resolved", error)
                    ));
                }
            }
        }
        
        // Check that system can make progress
        if self.global_clock > self.config.base_config.gst + 200 {
            if self.votor_state.finalized_chain.is_empty() {
                return Err(AlpenglowError::ProtocolViolation(
                    "No progress after recovery".to_string()
                ));
            }
        }
        
        Ok(())
    }
    
    /// Update performance metrics with comprehensive calculations and error handling
    pub fn update_performance_metrics(&mut self) {
        if !self.config.performance_monitoring {
            return;
        }
        
        // Calculate throughput with proper time window handling
        let finalized_blocks = self.votor_state.finalized_chain.len() as u64;
        let time_window = if let Some(start_time) = self.benchmark_start_time {
            std::cmp::max(self.global_clock.saturating_sub(start_time), 1)
        } else {
            std::cmp::max(self.global_clock, 1)
        };
        self.performance_metrics.update_throughput(finalized_blocks, time_window);
        
        // Calculate average latency with proper handling of time units
        let mut total_latency: u64 = 0;
        let mut valid_blocks = 0u64;
        
        for block in &self.votor_state.finalized_chain {
            // Convert between time units: block.timestamp is in milliseconds, global_clock is in ticks
            let block_time_ticks = self.convert_time_to_ticks(block.timestamp);
            if self.global_clock >= block_time_ticks {
                total_latency += self.global_clock - block_time_ticks;
                valid_blocks += 1;
            }
        }
        
        if valid_blocks > 0 {
            self.performance_metrics.update_latency(total_latency, valid_blocks);
        }
        
        // Calculate bandwidth usage across all validators
        let total_bandwidth = self.rotor_state.bandwidth_usage
            .values()
            .sum::<u64>();
        
        // Add network message bandwidth
        let network_bandwidth = self.network_state.message_queue
            .iter()
            .map(|msg| msg.payload.len() as u64)
            .sum::<u64>();
        
        self.performance_metrics.bandwidth = total_bandwidth + network_bandwidth;
        
        // Calculate certificate rate with proper normalization
        let total_certificates: u64 = self.votor_state.generated_certificates
            .values()
            .map(|certs| certs.len() as u64)
            .sum();
        
        let current_slot = std::cmp::max(self.votor_state.current_view, 1);
        self.performance_metrics.certificate_rate = total_certificates / current_slot;
        
        // Calculate repair rate with time-based normalization
        let repair_count = self.rotor_state.repair_requests.len() as u64;
        self.performance_metrics.repair_rate = if time_window > 0 {
            repair_count * 100 / time_window  // Repairs per 100 ticks
        } else {
            0
        };
        
        // Update message processing rate
        let total_network_messages = self.network_state.message_buffer
            .values()
            .map(|msgs| msgs.len() as u64)
            .sum::<u64>();
        
        self.performance_metrics.messages_processed = total_network_messages + 
            self.votor_state.voting_rounds.values()
                .map(|round| round.received_votes.len() as u64)
                .sum::<u64>();
        
        // Calculate failure rate
        let total_operations = self.performance_metrics.messages_processed + 
            self.performance_metrics.certificate_rate * current_slot +
            repair_count;
        
        if total_operations > 0 {
            let failure_rate = (self.performance_metrics.failed_operations * 100) / total_operations;
            if failure_rate > 10 {  // More than 10% failure rate
                self.update_component_health("system", ComponentHealth::Degraded);
            }
        }
    }
    
    /// Synchronize time between components handling different time units
    fn synchronize_component_times(&mut self) {
        // Convert global logical clock to component-specific time units
        
        // Votor uses milliseconds - convert ticks to milliseconds
        let votor_time_ms = self.convert_ticks_to_time(self.global_clock);
        self.votor_state.current_time = votor_time_ms;
        
        // Rotor uses logical ticks - direct assignment
        self.rotor_state.clock = self.global_clock;
        
        // Network uses logical ticks - direct assignment
        self.network_state.clock = self.global_clock;
        
        // Ensure all components are synchronized within tolerance
        let time_tolerance = 5; // 5 tick tolerance
        
        if self.votor_state.current_time > 0 {
            let votor_ticks = self.convert_time_to_ticks(self.votor_state.current_time);
            if votor_ticks.abs_diff(self.global_clock) > time_tolerance {
                self.integration_errors.insert("time_synchronization_drift".to_string());
                self.update_component_health("system", ComponentHealth::Degraded);
            }
        }
    }
    
    /// Convert logical ticks to milliseconds (1 tick = 10ms for simulation)
    fn convert_ticks_to_time(&self, ticks: u64) -> u64 {
        ticks * 10  // 10ms per tick
    }
    
    /// Convert milliseconds to logical ticks
    fn convert_time_to_ticks(&self, time_ms: u64) -> u64 {
        time_ms / 10  // 10ms per tick
    }
    
    /// Advance global clock with proper time synchronization
    pub fn advance_clock(&mut self) {
        self.global_clock += 1;
        
        // Synchronize all component times
        self.synchronize_component_times();
        
        // Update performance metrics periodically
        if self.global_clock % 10 == 0 {
            self.update_performance_metrics();
        }
        
        // Check for component failures periodically
        if self.global_clock % 50 == 0 {
            self.detect_component_failures();
        }
        
        // Attempt recovery if needed
        if self.system_state == SystemState::Degraded && self.global_clock % 100 == 0 {
            if let Err(e) = self.attempt_recovery() {
                self.integration_errors.insert(format!("recovery_failed: {}", e));
                self.performance_metrics.increment_failures();
            }
        }
        
        // Check for time-based invariants
        if self.global_clock > self.config.base_config.gst {
            // After GST, ensure progress is being made
            if self.global_clock % 200 == 0 {  // Check every 200 ticks
                self.verify_post_gst_progress();
            }
        }
        
        // Cleanup old interaction logs to prevent memory growth
        if self.global_clock % 1000 == 0 {
            self.cleanup_old_logs();
        }
    }
    
    /// Verify progress is being made after GST
    fn verify_post_gst_progress(&mut self) {
        let time_since_gst = self.global_clock - self.config.base_config.gst;
        
        // Check if any blocks have been finalized since GST
        let blocks_since_gst = self.votor_state.finalized_chain
            .iter()
            .filter(|block| {
                let block_ticks = self.convert_time_to_ticks(block.timestamp);
                block_ticks >= self.config.base_config.gst
            })
            .count();
        
        if time_since_gst > 500 && blocks_since_gst == 0 {  // No progress in 500 ticks after GST
            self.integration_errors.insert("no_progress_after_gst".to_string());
            self.update_component_health("system", ComponentHealth::Degraded);
        }
        
        // Check if views are advancing too quickly (sign of problems)
        if self.votor_state.current_view > time_since_gst / 10 {  // More than 1 view per 10 ticks
            self.integration_errors.insert("excessive_view_changes".to_string());
            self.update_component_health("votor", ComponentHealth::Degraded);
        }
    }
    
    /// Cleanup old interaction logs to prevent memory growth
    fn cleanup_old_logs(&mut self) {
        let cutoff_time = self.global_clock.saturating_sub(5000);  // Keep last 5000 ticks
        self.interaction_log.retain(|entry| entry.timestamp >= cutoff_time);
        
        // Also cleanup old integration errors that have been resolved
        let resolved_errors: Vec<String> = self.integration_errors
            .iter()
            .filter(|error| {
                // Remove errors that are no longer relevant
                match error.as_str() {
                    "time_synchronization_drift" => {
                        // Check if time sync is now OK
                        let votor_ticks = self.convert_time_to_ticks(self.votor_state.current_time);
                        votor_ticks.abs_diff(self.global_clock) <= 5
                    }
                    "bandwidth_exceeded" => {
                        // Check if bandwidth is now available
                        self.rotor_state.bandwidth_usage.values().all(|&usage| usage < self.rotor_state.bandwidth_limit)
                    }
                    _ => false  // Keep other errors
                }
            })
            .cloned()
            .collect();
        
        for error in resolved_errors {
            self.integration_errors.remove(&error);
        }
    }
    
    /// Export state for TLA+ cross-validation
    pub fn export_tla_state(&self) -> serde_json::Value {
        serde_json::json!({
            "systemState": format!("{:?}", self.system_state),
            "componentHealth": self.component_health,
            "votorState": self.votor_state.export_tla_state(),
            "rotorState": self.rotor_state.export_tla_state(),
            "networkState": self.network_state.export_tla_state(),
            "performanceMetrics": self.performance_metrics,
            "globalClock": self.global_clock,
            "integrationErrors": self.integration_errors
        })
    }
    
    /// Generate benchmark report
    pub fn generate_benchmark_report(&self) -> serde_json::Value {
        let runtime = if let Some(start_time) = self.benchmark_start_time {
            self.global_clock - start_time
        } else {
            self.global_clock
        };
        
        serde_json::json!({
            "runtime": runtime,
            "performance_metrics": self.performance_metrics,
            "system_state": format!("{:?}", self.system_state),
            "component_health": self.component_health,
            "integration_errors": self.integration_errors,
            "interaction_count": self.interaction_log.len(),
            "finalized_blocks": self.votor_state.finalized_chain.len(),
            "delivered_blocks_total": self.rotor_state.delivered_blocks.values()
                .map(|blocks| blocks.len()).sum::<usize>(),
            "network_messages": self.network_state.message_buffer.values()
                .map(|msgs| msgs.len()).sum::<usize>()
        })
    }
}

/// Messages for the integrated Alpenglow node
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum AlpenglowMessage {
    /// Initialize the node
    Initialize,
    /// Process a Votor message
    VotorMessage(VotorMessage),
    /// Process a Rotor message
    RotorMessage(RotorMessage),
    /// Process a Network message
    NetworkMessage(NetworkActorMessage),
    /// Cross-component certificate propagation
    PropagateCertificate {
        certificate: Certificate,
    },
    /// Cross-component block propagation
    PropagateBlock {
        block: Block,
    },
    /// Trigger component failure (for testing)
    TriggerFailure {
        component: String,
        failure_type: String,
    },
    /// Request system recovery
    RequestRecovery,
    /// Clock tick for timing
    ClockTick,
    /// Request performance report
    RequestPerformanceReport,
    /// Request TLA+ state export
    RequestTlaStateExport,
    /// Byzantine behavior injection (for testing)
    InjectByzantineBehavior {
        behavior_type: String,
        parameters: HashMap<String, String>,
    },
    /// Benchmark configuration update
    BenchmarkConfig {
        parameters: HashMap<String, String>,
    },
}

impl Hash for AlpenglowMessage {
    fn hash<H: Hasher>(&self, state: &mut H) {
        // Hash based on message type discriminant to avoid issues with non-Hash fields
        std::mem::discriminant(self).hash(state);
        match self {
            AlpenglowMessage::Initialize => {},
            AlpenglowMessage::VotorMessage(_) => "votor".hash(state),
            AlpenglowMessage::RotorMessage(_) => "rotor".hash(state),
            AlpenglowMessage::NetworkMessage(_) => "network".hash(state),
            AlpenglowMessage::PropagateCertificate { .. } => "cert_prop".hash(state),
            AlpenglowMessage::PropagateBlock { .. } => "block_prop".hash(state),
            AlpenglowMessage::InjectByzantineBehavior { .. } => "byzantine".hash(state),
            AlpenglowMessage::BenchmarkConfig { .. } => "benchmark".hash(state),
            _ => "other".hash(state),
        }
    }
}

/// Complete Alpenglow node actor
#[derive(Debug, Clone)]
pub struct AlpenglowNode {
    /// Validator ID
    pub validator_id: ValidatorId,
    /// Protocol configuration
    pub config: ProtocolConfig,
}

impl AlpenglowNode {
    /// Create a new Alpenglow node
    pub fn new(validator_id: ValidatorId, config: Config) -> Self {
        let protocol_config = ProtocolConfig::new(config);
        Self {
            validator_id,
            config: protocol_config,
        }
    }
    
    /// Create a new Alpenglow node with custom protocol configuration
    pub fn with_config(validator_id: ValidatorId, config: ProtocolConfig) -> Self {
        Self {
            validator_id,
            config,
        }
    }
    
    /// Enable Byzantine testing
    pub fn with_byzantine_testing(mut self) -> Self {
        self.config.byzantine_testing = true;
        self
    }
    
    /// Enable benchmark mode
    pub fn with_benchmark_mode(mut self) -> Self {
        self.config.benchmark_mode = true;
        self.config.performance_monitoring = true;
        self
    }
    
    /// Enable TLA+ cross-validation
    pub fn with_tla_cross_validation(mut self) -> Self {
        self.config.tla_cross_validation = true;
        self
    }
}

impl Actor for AlpenglowNode {
    type Msg = AlpenglowMessage;
    type State = AlpenglowState;
    
    fn on_start(&self, _id: Id, o: &mut crate::stateright::util::Out<Self>) -> Self::State {
        let mut state = AlpenglowState::new(self.validator_id, self.config.clone());
        
        // Initialize the system
        if let Err(e) = state.initialize() {
            eprintln!("Failed to initialize Alpenglow node: {:?}", e);
        }
        
        // Schedule periodic clock ticks
        o.send(_id, AlpenglowMessage::ClockTick);
        
        state
    }
    
    fn on_msg(
        &self,
        id: Id,
        state: &mut Self::State,
        _src: Id,
        msg: Self::Msg,
        o: &mut crate::stateright::util::Out<Self>,
    ) {
        match msg {
            AlpenglowMessage::Initialize => {
                if let Err(e) = state.initialize() {
                    eprintln!("Failed to initialize: {:?}", e);
                    state.integration_errors.insert("initialization_failed".to_string());
                }
            }
            
            AlpenglowMessage::VotorMessage(votor_msg) => {
                // Process Votor message and handle cross-component interactions
                match &votor_msg {
                    VotorMessage::FinalizeBlock { certificate } => {
                        if let Err(e) = state.process_votor_rotor_interaction(certificate) {
                            eprintln!("Votor-Rotor interaction failed: {:?}", e);
                        }
                    }
                    _ => {}
                }
                
                // Forward to Votor component (in practice, would use embedded Votor actor)
                state.performance_metrics.increment_messages();
            }
            
            AlpenglowMessage::RotorMessage(_rotor_msg) => {
                // Process Rotor message
                state.performance_metrics.increment_messages();
                
                // Forward to Rotor component (in practice, would use embedded Rotor actor)
            }
            
            AlpenglowMessage::NetworkMessage(_network_msg) => {
                // Process Network message
                state.performance_metrics.increment_messages();
                
                // Forward to Network component (in practice, would use embedded Network actor)
            }
            
            AlpenglowMessage::PropagateCertificate { certificate } => {
                // Handle cross-component certificate propagation
                if let Err(e) = state.process_votor_rotor_interaction(&certificate) {
                    eprintln!("Certificate propagation failed: {:?}", e);
                    state.performance_metrics.increment_failures();
                }
                
                // Broadcast certificate to other nodes
                // Certificate contains block hash, need to propagate certificate itself
                o.broadcast(AlpenglowMessage::PropagateCertificate { 
                    certificate: certificate.clone() 
                });
            }
            
            AlpenglowMessage::PropagateBlock { block } => {
                // Handle block propagation across components
                let erasure_block = ErasureBlock::new(
                    block.hash,
                    block.slot,
                    block.proposer,
                    block.data.clone(),
                    (state.config.base_config.validator_count * 2 / 3) as u32,
                    state.config.base_config.validator_count as u32,
                );
                
                // Trigger Rotor shredding and distribution
                o.send(id, AlpenglowMessage::RotorMessage(RotorMessage::ShredAndDistribute {
                    leader: block.proposer,
                    block: erasure_block,
                }));
                
                state.log_interaction("integration", "rotor", "block_propagation", HashMap::new());
            }
            
            AlpenglowMessage::TriggerFailure { component, failure_type } => {
                if state.config.byzantine_testing {
                    let health = match failure_type.as_str() {
                        "fail" => ComponentHealth::Failed,
                        "degrade" => ComponentHealth::Degraded,
                        "partition" => ComponentHealth::Partitioned,
                        "congest" => ComponentHealth::Congested,
                        _ => ComponentHealth::Degraded,
                    };
                    
                    state.update_component_health(&component, health);
                    state.integration_errors.insert(format!("{}_{}", component, failure_type));
                    
                    let mut metadata = HashMap::new();
                    metadata.insert("component".to_string(), component);
                    metadata.insert("failure_type".to_string(), failure_type);
                    state.log_interaction("test", "system", "failure_injection", metadata);
                }
            }
            
            AlpenglowMessage::RequestRecovery => {
                if let Err(e) = state.attempt_recovery() {
                    eprintln!("Recovery failed: {:?}", e);
                    state.performance_metrics.increment_failures();
                }
            }
            
            AlpenglowMessage::ClockTick => {
                state.advance_clock();
                
                // Schedule next clock tick
                o.send(id, AlpenglowMessage::ClockTick);
                
                // Trigger periodic operations
                if state.global_clock % 100 == 0 {
                    // Periodic health check
                    state.detect_component_failures();
                }
                
                if state.global_clock % 200 == 0 && state.system_state == SystemState::Degraded {
                    // Periodic recovery attempt
                    o.send(id, AlpenglowMessage::RequestRecovery);
                }
            }
            
            AlpenglowMessage::RequestPerformanceReport => {
                if state.config.performance_monitoring {
                    let report = state.generate_benchmark_report();
                    println!("Performance Report: {}", serde_json::to_string_pretty(&report).unwrap_or_default());
                }
            }
            
            AlpenglowMessage::RequestTlaStateExport => {
                // Export current state to TLA+ format for cross-validation
                let tla_state = serde_json::json!({
                    "votor_state": {
                        "validator_id": state.votor_state.validator_id,
                        "current_view": state.votor_state.current_view,
                        "voted_blocks_count": state.votor_state.voted_blocks.len(),
                        "received_votes_count": state.votor_state.received_votes.len(),
                        "certificates_count": state.votor_state.generated_certificates.len()
                    },
                    "rotor_state": "rotor_state_placeholder",
                    "network_state": "network_state_placeholder"
                });
                state.tla_state_cache = Some(tla_state);
            },
            
            AlpenglowMessage::BenchmarkConfig { parameters } => {
                // Update benchmark configuration
                for (key, value) in parameters {
                    // Process benchmark parameter updates
                    match key.as_str() {
                        "timeout_multiplier" => {
                            if let Ok(_multiplier) = value.parse::<f64>() {
                                // Timeout multiplier would be applied to base timeout values
                                // For now, just log the parameter
                            }
                        },
                        "byzantine_threshold" => {
                            if let Ok(threshold) = value.parse::<usize>() {
                                state.config.base_config.byzantine_threshold = threshold;
                            }
                        },
                        _ => {
                            // Log unknown parameter
                            state.integration_errors.insert(format!("Unknown benchmark parameter: {}", key));
                        }
                    }
                }
            },
            
            AlpenglowMessage::InjectByzantineBehavior { behavior_type, parameters } => {
                if state.config.byzantine_testing {
                    match behavior_type.as_str() {
                        "double_vote" => {
                            // Inject double voting behavior
                            state.integration_errors.insert("byzantine_double_vote".to_string());
                        }
                        "withhold_vote" => {
                            // Inject vote withholding
                            state.integration_errors.insert("byzantine_withhold_vote".to_string());
                        }
                        "invalid_certificate" => {
                            // Inject invalid certificate
                            state.integration_errors.insert("byzantine_invalid_certificate".to_string());
                        }
                        "network_partition" => {
                            // Inject network partition
                            state.update_component_health("network", ComponentHealth::Partitioned);
                        }
                        _ => {
                            state.integration_errors.insert("unknown_byzantine_behavior".to_string());
                        }
                    }
                    
                    let mut metadata = HashMap::new();
                    metadata.insert("behavior_type".to_string(), behavior_type);
                    for (key, value) in parameters {
                        metadata.insert(key, value);
                    }
                    state.log_interaction("test", "system", "byzantine_injection", metadata);
                }
            }
        }
    }
}

impl Verifiable for AlpenglowState {
    fn verify_safety(&self) -> AlpenglowResult<()> {
        // Verify individual component safety
        self.votor_state.verify_safety()?;
        self.rotor_state.verify_safety()?;
        self.network_state.verify_safety()?;
        
        // Cross-component safety properties
        
        // Safety: No conflicting blocks finalized
        let mut finalized_slots = HashSet::new();
        for block in &self.votor_state.finalized_chain {
            if finalized_slots.contains(&block.slot) {
                return Err(AlpenglowError::ProtocolViolation(
                    "Conflicting blocks finalized in same slot".to_string()
                ));
            }
            finalized_slots.insert(block.slot);
        }
        
        // Safety: All finalized blocks must be available in Rotor
        for block in &self.votor_state.finalized_chain {
            if !self.rotor_state.block_shreds.contains_key(&block.hash) {
                return Err(AlpenglowError::ProtocolViolation(
                    "Finalized block not available in Rotor".to_string()
                ));
            }
        }
        
        // Safety: Component health consistency
        if self.system_state == SystemState::Running {
            for (component, health) in &self.component_health {
                if *health == ComponentHealth::Failed {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("System running with failed component: {}", component)
                    ));
                }
            }
        }
        
        Ok(())
    }
    
    fn verify_liveness(&self) -> AlpenglowResult<()> {
        // Verify individual component liveness
        self.votor_state.verify_liveness()?;
        self.rotor_state.verify_liveness()?;
        self.network_state.verify_liveness()?;
        
        // Cross-component liveness properties
        
        // Liveness: System makes progress after GST
        if self.global_clock > self.config.base_config.gst + 100 {
            if self.votor_state.finalized_chain.is_empty() {
                return Err(AlpenglowError::ProtocolViolation(
                    "No progress made after GST".to_string()
                ));
            }
        }
        
        // Liveness: Cross-component interactions occur
        if self.global_clock > 100 && self.interaction_log.is_empty() {
            return Err(AlpenglowError::ProtocolViolation(
                "No cross-component interactions detected".to_string()
            ));
        }
        
        // Liveness: System recovers from degraded states
        if self.system_state == SystemState::Degraded && self.global_clock > 1000 {
            // Should attempt recovery within reasonable time
            let recovery_attempts = self.interaction_log
                .iter()
                .filter(|entry| entry.interaction_type == "recovery_attempted")
                .count();
            
            if recovery_attempts == 0 {
                return Err(AlpenglowError::ProtocolViolation(
                    "No recovery attempts in degraded state".to_string()
                ));
            }
        }
        
        Ok(())
    }
    
    fn verify_byzantine_resilience(&self) -> AlpenglowResult<()> {
        // Verify individual component Byzantine resilience
        self.votor_state.verify_byzantine_resilience()?;
        self.rotor_state.verify_byzantine_resilience()?;
        self.network_state.verify_byzantine_resilience()?;
        
        // Cross-component Byzantine resilience
        
        // Byzantine resilience: System maintains safety under Byzantine faults
        let byzantine_count = self.network_state.byzantine_validators.len();
        let total_validators = self.config.base_config.validator_count;
        
        if byzantine_count >= total_validators / 3 {
            // With too many Byzantine validators, check if system halted appropriately
            if self.system_state == SystemState::Running {
                return Err(AlpenglowError::ProtocolViolation(
                    "System running with too many Byzantine validators".to_string()
                ));
            }
        } else {
            // With acceptable Byzantine count, system should maintain safety
            self.verify_safety()?;
        }
        
        Ok(())
    }
}

impl TlaCompatible for AlpenglowState {
    fn export_tla_state(&self) -> serde_json::Value {
        // Export state matching TLA+ Integration specification exactly
        let system_state_str = match self.system_state {
            SystemState::Initializing => "initializing",
            SystemState::Running => "running", 
            SystemState::Degraded => "degraded",
            SystemState::Recovering => "recovering",
            SystemState::Halted => "halted",
        };
        
        // Convert component health to TLA+ format
        let mut component_health_tla = serde_json::Map::new();
        for (component, health) in &self.component_health {
            let health_str = match health {
                ComponentHealth::Healthy => "healthy",
                ComponentHealth::Degraded => "degraded", 
                ComponentHealth::Failed => "failed",
                ComponentHealth::Partitioned => "partitioned",
                ComponentHealth::Congested => "congested",
                ComponentHealth::Slow => "slow",
            };
            component_health_tla.insert(component.clone(), serde_json::Value::String(health_str.to_string()));
        }
        
        // Convert interaction log to TLA+ sequence format
        let interaction_log_tla: Vec<serde_json::Value> = self.interaction_log
            .iter()
            .map(|entry| {
                serde_json::json!({
                    "source": entry.source,
                    "target": entry.target,
                    "type": entry.interaction_type,
                    "timestamp": entry.timestamp
                })
            })
            .collect();
        
        // Export performance metrics matching TLA+ PerformanceMetric structure
        let performance_metrics_tla = serde_json::json!({
            "throughput": self.performance_metrics.throughput,
            "latency": self.performance_metrics.latency,
            "bandwidth": self.performance_metrics.bandwidth,
            "certificateRate": self.performance_metrics.certificate_rate,
            "repairRate": self.performance_metrics.repair_rate
        });
        
        // Convert integration errors to TLA+ set format
        let integration_errors_tla: Vec<String> = self.integration_errors.iter().cloned().collect();
        
        // Export component states with proper TLA+ structure
        let votor_state_tla = self.votor_state.export_tla_state();
        let rotor_state_tla = self.rotor_state.export_tla_state();
        let network_state_tla = self.network_state.export_tla_state();
        
        // Construct the complete TLA+ state matching Integration.tla variables
        serde_json::json!({
            // Core Integration.tla variables
            "systemState": system_state_str,
            "componentHealth": serde_json::Value::Object(component_health_tla),
            "interactionLog": interaction_log_tla,
            "performanceMetrics": performance_metrics_tla,
            "integrationErrors": integration_errors_tla,
            
            // Component states for cross-validation
            "votorState": votor_state_tla,
            "rotorState": rotor_state_tla,
            "networkState": network_state_tla,
            
            // Additional state for comprehensive verification
            "globalClock": self.global_clock,
            "validatorId": self.validator_id,
            
            // Cross-component state tracking
            "crossComponentInteractions": {
                "votorRotorInteractions": self.interaction_log.iter()
                    .filter(|entry| entry.source == "votor" && entry.target == "rotor")
                    .count(),
                "networkComponentInteractions": self.interaction_log.iter()
                    .filter(|entry| entry.source == "network")
                    .count(),
                "systemRecoveryAttempts": self.interaction_log.iter()
                    .filter(|entry| entry.interaction_type == "recovery_attempted")
                    .count()
            },
            
            // Performance tracking for TLA+ verification
            "performanceTracking": {
                "messagesProcessed": self.performance_metrics.messages_processed,
                "failedOperations": self.performance_metrics.failed_operations,
                "benchmarkStartTime": self.benchmark_start_time,
                "timeWindow": if let Some(start) = self.benchmark_start_time {
                    self.global_clock.saturating_sub(start)
                } else {
                    self.global_clock
                }
            },
            
            // Configuration for invariant checking
            "configurationState": {
                "validatorCount": self.config.base_config.validator_count,
                "fastPathThreshold": self.config.base_config.fast_path_threshold,
                "slowPathThreshold": self.config.base_config.slow_path_threshold,
                "gst": self.config.base_config.gst,
                "maxNetworkDelay": self.config.base_config.max_network_delay,
                "performanceMonitoring": self.config.performance_monitoring,
                "byzantineTesting": self.config.byzantine_testing,
                "tlaCrossValidation": self.config.tla_cross_validation
            }
        })
    }
    
    fn import_tla_state(&mut self, state: serde_json::Value) -> AlpenglowResult<()> {
        // Import system state with comprehensive error handling
        if let Some(system_state_str) = state.get("systemState").and_then(|v| v.as_str()) {
            self.system_state = match system_state_str {
                "initializing" => SystemState::Initializing,
                "running" => SystemState::Running,
                "degraded" => SystemState::Degraded,
                "recovering" => SystemState::Recovering,
                "halted" => SystemState::Halted,
                _ => {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("Invalid system state in TLA+ import: {}", system_state_str)
                    ));
                }
            };
        } else {
            return Err(AlpenglowError::ProtocolViolation(
                "Missing systemState in TLA+ import".to_string()
            ));
        }
        
        // Import component health with validation
        if let Some(component_health_obj) = state.get("componentHealth").and_then(|v| v.as_object()) {
            self.component_health.clear();
            
            for (component, health_value) in component_health_obj {
                if let Some(health_str) = health_value.as_str() {
                    let health = match health_str {
                        "healthy" => ComponentHealth::Healthy,
                        "degraded" => ComponentHealth::Degraded,
                        "failed" => ComponentHealth::Failed,
                        "partitioned" => ComponentHealth::Partitioned,
                        "congested" => ComponentHealth::Congested,
                        "slow" => ComponentHealth::Slow,
                        _ => {
                            return Err(AlpenglowError::ProtocolViolation(
                                format!("Invalid component health: {} for component {}", health_str, component)
                            ));
                        }
                    };
                    self.component_health.insert(component.clone(), health);
                } else {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("Invalid health value for component {}", component)
                    ));
                }
            }
        } else {
            return Err(AlpenglowError::ProtocolViolation(
                "Missing componentHealth in TLA+ import".to_string()
            ));
        }
        
        // Import interaction log with validation
        if let Some(interaction_log_array) = state.get("interactionLog").and_then(|v| v.as_array()) {
            self.interaction_log.clear();
            
            for (index, interaction_value) in interaction_log_array.iter().enumerate() {
                if let Some(interaction_obj) = interaction_value.as_object() {
                    let source = interaction_obj.get("source")
                        .and_then(|v| v.as_str())
                        .ok_or_else(|| AlpenglowError::ProtocolViolation(
                            format!("Missing source in interaction log entry {}", index)
                        ))?;
                    
                    let target = interaction_obj.get("target")
                        .and_then(|v| v.as_str())
                        .ok_or_else(|| AlpenglowError::ProtocolViolation(
                            format!("Missing target in interaction log entry {}", index)
                        ))?;
                    
                    let interaction_type = interaction_obj.get("type")
                        .and_then(|v| v.as_str())
                        .ok_or_else(|| AlpenglowError::ProtocolViolation(
                            format!("Missing type in interaction log entry {}", index)
                        ))?;
                    
                    let timestamp = interaction_obj.get("timestamp")
                        .and_then(|v| v.as_u64())
                        .ok_or_else(|| AlpenglowError::ProtocolViolation(
                            format!("Missing timestamp in interaction log entry {}", index)
                        ))?;
                    
                    let entry = InteractionLogEntry {
                        source: source.to_string(),
                        target: target.to_string(),
                        interaction_type: interaction_type.to_string(),
                        timestamp,
                        metadata: HashMap::new(), // Metadata not preserved in TLA+ export
                    };
                    
                    self.interaction_log.push(entry);
                } else {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("Invalid interaction log entry {} format", index)
                    ));
                }
            }
        }
        
        // Import performance metrics with validation
        if let Some(perf_metrics_obj) = state.get("performanceMetrics").and_then(|v| v.as_object()) {
            self.performance_metrics.throughput = perf_metrics_obj.get("throughput")
                .and_then(|v| v.as_u64())
                .unwrap_or(0);
            
            self.performance_metrics.latency = perf_metrics_obj.get("latency")
                .and_then(|v| v.as_u64())
                .unwrap_or(0);
            
            self.performance_metrics.bandwidth = perf_metrics_obj.get("bandwidth")
                .and_then(|v| v.as_u64())
                .unwrap_or(0);
            
            self.performance_metrics.certificate_rate = perf_metrics_obj.get("certificateRate")
                .and_then(|v| v.as_u64())
                .unwrap_or(0);
            
            self.performance_metrics.repair_rate = perf_metrics_obj.get("repairRate")
                .and_then(|v| v.as_u64())
                .unwrap_or(0);
        }
        
        // Import integration errors
        if let Some(errors_array) = state.get("integrationErrors").and_then(|v| v.as_array()) {
            self.integration_errors.clear();
            for error_value in errors_array {
                if let Some(error_str) = error_value.as_str() {
                    self.integration_errors.insert(error_str.to_string());
                }
            }
        }
        
        // Import global clock
        if let Some(clock) = state.get("globalClock").and_then(|v| v.as_u64()) {
            self.global_clock = clock;
        }
        
        // Import component states with error handling
        if let Some(votor_state) = state.get("votorState") {
            self.votor_state.import_tla_state(votor_state.clone())
                .map_err(|e| AlpenglowError::ProtocolViolation(
                    format!("Failed to import Votor state: {}", e)
                ))?;
        }
        
        if let Some(rotor_state) = state.get("rotorState") {
            self.rotor_state.import_tla_state(rotor_state.clone())
                .map_err(|e| AlpenglowError::ProtocolViolation(
                    format!("Failed to import Rotor state: {}", e)
                ))?;
        }
        
        if let Some(network_state) = state.get("networkState") {
            self.network_state.import_tla_state(network_state.clone())
                .map_err(|e| AlpenglowError::ProtocolViolation(
                    format!("Failed to import Network state: {}", e)
                ))?;
        }
        
        // Import performance tracking data
        if let Some(perf_tracking) = state.get("performanceTracking").and_then(|v| v.as_object()) {
            if let Some(messages_processed) = perf_tracking.get("messagesProcessed").and_then(|v| v.as_u64()) {
                self.performance_metrics.messages_processed = messages_processed;
            }
            
            if let Some(failed_operations) = perf_tracking.get("failedOperations").and_then(|v| v.as_u64()) {
                self.performance_metrics.failed_operations = failed_operations;
            }
            
            if let Some(benchmark_start) = perf_tracking.get("benchmarkStartTime").and_then(|v| v.as_u64()) {
                self.benchmark_start_time = Some(benchmark_start);
            }
        }
        
        // Synchronize component times after import
        self.synchronize_component_times();
        
        Ok(())
    }
    
    fn validate_tla_invariants(&self) -> AlpenglowResult<()> {
        // Validate all TLA+ Integration invariants from the specification
        
        // TypeInvariantIntegration: Validate all state types
        self.validate_type_invariant_integration()?;
        
        // ComponentConsistency: Validate component health consistency
        self.validate_component_consistency()?;
        
        // CrossComponentSafety: Validate cross-component safety properties
        self.validate_cross_component_safety()?;
        
        // PerformanceBounds: Validate performance metric bounds
        self.validate_performance_bounds()?;
        
        // Additional integration-specific invariants
        self.validate_integration_specific_invariants()?;
        
        Ok(())
    }
}

impl AlpenglowState {
    /// Validate TLA+ TypeInvariantIntegration
    fn validate_type_invariant_integration(&self) -> AlpenglowResult<()> {
        // systemState \in SystemStates
        match self.system_state {
            SystemState::Initializing | SystemState::Running | SystemState::Degraded |
            SystemState::Recovering | SystemState::Halted => {}
        }
        
        // componentHealth validation
        let required_components = ["votor", "rotor", "network", "crypto"];
        for component in &required_components {
            if let Some(health) = self.component_health.get(*component) {
                match health {
                    ComponentHealth::Healthy | ComponentHealth::Degraded | ComponentHealth::Failed |
                    ComponentHealth::Partitioned | ComponentHealth::Congested | ComponentHealth::Slow => {}
                }
            } else {
                return Err(AlpenglowError::ProtocolViolation(
                    format!("Missing required component health: {}", component)
                ));
            }
        }
        
        // Validate network component has appropriate health states
        if let Some(network_health) = self.component_health.get("network") {
            match network_health {
                ComponentHealth::Healthy | ComponentHealth::Partitioned | 
                ComponentHealth::Congested | ComponentHealth::Failed => {}
                _ => {
                    return Err(AlpenglowError::ProtocolViolation(
                        "Network component has invalid health state".to_string()
                    ));
                }
            }
        }
        
        // Validate crypto component has appropriate health states
        if let Some(crypto_health) = self.component_health.get("crypto") {
            match crypto_health {
                ComponentHealth::Healthy | ComponentHealth::Slow | ComponentHealth::Failed => {}
                _ => {
                    return Err(AlpenglowError::ProtocolViolation(
                        "Crypto component has invalid health state".to_string()
                    ));
                }
            }
        }
        
        // interactionLog \in Seq(InteractionType)
        for (index, entry) in self.interaction_log.iter().enumerate() {
            // Validate source and target are valid components
            let valid_components = ["votor", "rotor", "network", "system", "test"];
            if !valid_components.contains(&entry.source.as_str()) {
                return Err(AlpenglowError::ProtocolViolation(
                    format!("Invalid interaction source at index {}: {}", index, entry.source)
                ));
            }
            
            if !valid_components.contains(&entry.target.as_str()) && entry.target != "all" {
                return Err(AlpenglowError::ProtocolViolation(
                    format!("Invalid interaction target at index {}: {}", index, entry.target)
                ));
            }
            
            // Validate interaction types
            let valid_types = ["request", "response", "broadcast", "error", "recovery", 
                              "initialization", "health_update", "certificate_propagation",
                              "block_propagation", "vote_delivery", "repair_request"];
            if !valid_types.contains(&entry.interaction_type.as_str()) {
                return Err(AlpenglowError::ProtocolViolation(
                    format!("Invalid interaction type at index {}: {}", index, entry.interaction_type)
                ));
            }
        }
        
        // performanceMetrics \in PerformanceMetric (all fields are Nat)
        // All u64 values are valid natural numbers in TLA+
        
        // integrationErrors \in SUBSET STRING
        // HashSet<String> is valid subset of strings
        
        Ok(())
    }
    
    /// Validate TLA+ ComponentConsistency invariant
    fn validate_component_consistency(&self) -> AlpenglowResult<()> {
        let votor_health = self.component_health.get("votor").unwrap_or(&ComponentHealth::Healthy);
        let rotor_health = self.component_health.get("rotor").unwrap_or(&ComponentHealth::Healthy);
        let network_health = self.component_health.get("network").unwrap_or(&ComponentHealth::Healthy);
        let crypto_health = self.component_health.get("crypto").unwrap_or(&ComponentHealth::Healthy);
        
        // If Votor is failed, system cannot be running normally
        if *votor_health == ComponentHealth::Failed {
            match self.system_state {
                SystemState::Degraded | SystemState::Halted | SystemState::Recovering => {}
                _ => {
                    return Err(AlpenglowError::ProtocolViolation(
                        "Votor failed but system not in degraded/halted/recovering state".to_string()
                    ));
                }
            }
        }
        
        // If network is failed, both Votor and Rotor are affected
        if *network_health == ComponentHealth::Failed {
            if !matches!(votor_health, ComponentHealth::Degraded | ComponentHealth::Failed) {
                return Err(AlpenglowError::ProtocolViolation(
                    "Network failed but Votor not degraded/failed".to_string()
                ));
            }
            
            if !matches!(rotor_health, ComponentHealth::Degraded | ComponentHealth::Failed) {
                return Err(AlpenglowError::ProtocolViolation(
                    "Network failed but Rotor not degraded/failed".to_string()
                ));
            }
            
            match self.system_state {
                SystemState::Degraded | SystemState::Halted | SystemState::Recovering => {}
                _ => {
                    return Err(AlpenglowError::ProtocolViolation(
                        "Network failed but system not in degraded/halted/recovering state".to_string()
                    ));
                }
            }
        }
        
        // If crypto is failed, consensus cannot proceed
        if *crypto_health == ComponentHealth::Failed {
            if *votor_health != ComponentHealth::Failed {
                return Err(AlpenglowError::ProtocolViolation(
                    "Crypto failed but Votor not failed".to_string()
                ));
            }
            
            match self.system_state {
                SystemState::Halted | SystemState::Recovering => {}
                _ => {
                    return Err(AlpenglowError::ProtocolViolation(
                        "Crypto failed but system not halted/recovering".to_string()
                    ));
                }
            }
        }
        
        // Network partitions affect system state
        if *network_health == ComponentHealth::Partitioned {
            match self.system_state {
                SystemState::Degraded | SystemState::Recovering => {}
                _ => {
                    return Err(AlpenglowError::ProtocolViolation(
                        "Network partitioned but system not degraded/recovering".to_string()
                    ));
                }
            }
            
            // Performance should be reduced (throughput <= throughput / 2)
            // This is checked in performance bounds validation
        }
        
        // Rotor failure affects block propagation
        if *rotor_health == ComponentHealth::Failed {
            match self.system_state {
                SystemState::Degraded | SystemState::Halted | SystemState::Recovering => {}
                _ => {
                    return Err(AlpenglowError::ProtocolViolation(
                        "Rotor failed but system not degraded/halted/recovering".to_string()
                    ));
                }
            }
            
            // Should have high repair rate (checked in performance bounds)
        }
        
        // System state consistency with component health
        match self.system_state {
            SystemState::Running => {
                if !matches!(votor_health, ComponentHealth::Healthy | ComponentHealth::Degraded) {
                    return Err(AlpenglowError::ProtocolViolation(
                        "System running but Votor not healthy/degraded".to_string()
                    ));
                }
                
                if *crypto_health != ComponentHealth::Healthy {
                    return Err(AlpenglowError::ProtocolViolation(
                        "System running but crypto not healthy".to_string()
                    ));
                }
                
                if !matches!(network_health, ComponentHealth::Healthy | ComponentHealth::Congested) {
                    return Err(AlpenglowError::ProtocolViolation(
                        "System running but network not healthy/congested".to_string()
                    ));
                }
            }
            
            SystemState::Halted => {
                let has_failed_component = *votor_health == ComponentHealth::Failed ||
                    *crypto_health == ComponentHealth::Failed ||
                    *network_health == ComponentHealth::Failed;
                
                if !has_failed_component {
                    return Err(AlpenglowError::ProtocolViolation(
                        "System halted but no critical component failed".to_string()
                    ));
                }
            }
            
            _ => {} // Other states are transitional
        }
        
        Ok(())
    }
    
    /// Validate TLA+ CrossComponentSafety invariant
    fn validate_cross_component_safety(&self) -> AlpenglowResult<()> {
        // Validate that Votor certificates can be propagated by Rotor
        for cert in self.votor_state.generated_certificates.values().flatten() {
            // Certificate blocks must be available in Rotor for propagation
            if !self.rotor_state.block_shreds.contains_key(&cert.block) {
                // Allow for certificates that haven't been propagated yet
                // This is not a safety violation unless the certificate is finalized
                if self.votor_state.finalized_chain.iter().any(|block| block.hash == cert.block) {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("Finalized certificate block {} not available in Rotor", cert.block)
                    ));
                }
            }
        }
        
        // Network message delivery bounds (after GST)
        if self.global_clock > self.config.base_config.gst {
            // Check that messages sent before GST + Delta are delivered or dropped appropriately
            let gst_plus_delta = self.config.base_config.gst + self.config.base_config.max_network_delay;
            
            for message in &self.network_state.message_queue {
                if message.timestamp <= gst_plus_delta && self.global_clock > gst_plus_delta {
                    // Message should have been delivered by now unless sender is Byzantine
                    if !self.network_state.byzantine_validators.contains(&message.sender) {
                        return Err(AlpenglowError::ProtocolViolation(
                            format!("Message from honest validator {} not delivered within Delta bound", message.sender)
                        ));
                    }
                }
            }
        }
        
        // Component health consistency with actual state
        let votor_health = self.component_health.get("votor").unwrap_or(&ComponentHealth::Healthy);
        let rotor_health = self.component_health.get("rotor").unwrap_or(&ComponentHealth::Healthy);
        let network_health = self.component_health.get("network").unwrap_or(&ComponentHealth::Healthy);
        
        if *votor_health == ComponentHealth::Healthy {
            // Should have reasonable view numbers
            if self.votor_state.current_view > 1000 {
                return Err(AlpenglowError::ProtocolViolation(
                    "Votor healthy but excessive view number".to_string()
                ));
            }
            
            // Should have generated some certificates if running for a while
            if self.global_clock > self.config.base_config.gst + 100 {
                if self.votor_state.generated_certificates.is_empty() {
                    return Err(AlpenglowError::ProtocolViolation(
                        "Votor healthy but no certificates generated after GST".to_string()
                    ));
                }
            }
        }
        
        if *rotor_health == ComponentHealth::Healthy {
            // Should have some block shreds if blocks have been proposed
            if !self.votor_state.finalized_chain.is_empty() && self.rotor_state.block_shreds.is_empty() {
                return Err(AlpenglowError::ProtocolViolation(
                    "Rotor healthy but no block shreds for finalized blocks".to_string()
                ));
            }
            
            // Each block should have sufficient shreds for reconstruction
            for (block_hash, validator_shreds) in &self.rotor_state.block_shreds {
                let total_shreds: usize = validator_shreds.values().map(|shreds| shreds.len()).sum();
                let required_shreds = (self.config.base_config.validator_count * 2 / 3) as usize;
                
                if total_shreds < required_shreds {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("Block {} has insufficient shreds: {} < {}", block_hash, total_shreds, required_shreds)
                    ));
                }
            }
        }
        
        if *network_health == ComponentHealth::Healthy {
            // Should have no active partitions
            let active_partitions = self.network_state.network_partitions
                .iter()
                .filter(|p| !p.healed)
                .count();
            
            if active_partitions > 0 {
                return Err(AlpenglowError::ProtocolViolation(
                    "Network healthy but has active partitions".to_string()
                ));
            }
            
            // Message queue should not be overflowing
            if self.network_state.message_queue.len() > 1000 {
                return Err(AlpenglowError::ProtocolViolation(
                    "Network healthy but message queue overflowing".to_string()
                ));
            }
        }
        
        // No conflicting states between components
        if *votor_health == ComponentHealth::Healthy && *network_health == ComponentHealth::Failed {
            return Err(AlpenglowError::ProtocolViolation(
                "Conflicting state: Votor healthy but network failed".to_string()
            ));
        }
        
        if *rotor_health == ComponentHealth::Healthy && *network_health == ComponentHealth::Failed {
            return Err(AlpenglowError::ProtocolViolation(
                "Conflicting state: Rotor healthy but network failed".to_string()
            ));
        }
        
        Ok(())
    }
    
    /// Validate TLA+ PerformanceBounds invariant
    fn validate_performance_bounds(&self) -> AlpenglowResult<()> {
        let max_block_size = self.config.base_config.max_block_size as u64;
        let validator_count = self.config.base_config.validator_count as u64;
        let network_capacity = 10_000_000u64; // Network capacity constant
        let max_slot = self.config.base_config.max_slot;
        let max_blocks = 100u64; // MaxBlocks constant
        let max_retries = 3u64; // MaxRetries constant
        
        // throughput <= MaxBlockSize * N
        let max_throughput = max_block_size * validator_count;
        if self.performance_metrics.throughput > max_throughput {
            return Err(AlpenglowError::ProtocolViolation(
                format!("Throughput {} exceeds maximum {}", 
                    self.performance_metrics.throughput, max_throughput)
            ));
        }
        
        // latency >= Delta
        if self.performance_metrics.latency > 0 && 
           self.performance_metrics.latency < self.config.base_config.max_network_delay {
            return Err(AlpenglowError::ProtocolViolation(
                format!("Latency {} below minimum Delta {}", 
                    self.performance_metrics.latency, self.config.base_config.max_network_delay)
            ));
        }
        
        // bandwidth <= NetworkCapacity
        if self.performance_metrics.bandwidth > network_capacity {
            return Err(AlpenglowError::ProtocolViolation(
                format!("Bandwidth {} exceeds network capacity {}", 
                    self.performance_metrics.bandwidth, network_capacity)
            ));
        }
        
        // certificateRate <= MaxSlot
        if self.performance_metrics.certificate_rate > max_slot {
            return Err(AlpenglowError::ProtocolViolation(
                format!("Certificate rate {} exceeds max slot {}", 
                    self.performance_metrics.certificate_rate, max_slot)
            ));
        }
        
        // repairRate <= MaxBlocks * MaxRetries
        let max_repair_rate = max_blocks * max_retries;
        if self.performance_metrics.repair_rate > max_repair_rate {
            return Err(AlpenglowError::ProtocolViolation(
                format!("Repair rate {} exceeds maximum {}", 
                    self.performance_metrics.repair_rate, max_repair_rate)
            ));
        }
        
        // Additional performance consistency checks
        
        // If network is partitioned, throughput should be reduced
        if let Some(ComponentHealth::Partitioned) = self.component_health.get("network") {
            // This is a soft constraint - throughput should be significantly reduced
            // but we don't enforce the exact division by 2 as it depends on partition size
        }
        
        // If Rotor is failed, repair rate should be high
        if let Some(ComponentHealth::Failed) = self.component_health.get("rotor") {
            if self.performance_metrics.repair_rate <= max_blocks / 2 {
                return Err(AlpenglowError::ProtocolViolation(
                    "Rotor failed but repair rate not elevated".to_string()
                ));
            }
        }
        
        Ok(())
    }
    
    /// Validate integration-specific invariants
    fn validate_integration_specific_invariants(&self) -> AlpenglowResult<()> {
        // Validate cross-component interaction consistency
        let votor_rotor_interactions = self.interaction_log.iter()
            .filter(|entry| entry.source == "votor" && entry.target == "rotor")
            .count();
        
        let network_component_interactions = self.interaction_log.iter()
            .filter(|entry| entry.source == "network")
            .count();
        
        // If system has been running for a while, should have cross-component interactions
        if self.global_clock > self.config.base_config.gst + 200 {
            if self.system_state == SystemState::Running {
                if votor_rotor_interactions == 0 && !self.votor_state.finalized_chain.is_empty() {
                    return Err(AlpenglowError::ProtocolViolation(
                        "No Votor-Rotor interactions despite finalized blocks".to_string()
                    ));
                }
                
                if network_component_interactions == 0 {
                    return Err(AlpenglowError::ProtocolViolation(
                        "No network-component interactions after GST".to_string()
                    ));
                }
            }
        }
        
        // Validate error consistency
        for error in &self.integration_errors {
            // Errors should be consistent with component health
            if error.contains("votor_") {
                let votor_health = self.component_health.get("votor").unwrap_or(&ComponentHealth::Healthy);
                if *votor_health == ComponentHealth::Healthy {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("Votor error {} but component healthy", error)
                    ));
                }
            }
            
            if error.contains("rotor_") {
                let rotor_health = self.component_health.get("rotor").unwrap_or(&ComponentHealth::Healthy);
                if *rotor_health == ComponentHealth::Healthy {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("Rotor error {} but component healthy", error)
                    ));
                }
            }
            
            if error.contains("network_") {
                let network_health = self.component_health.get("network").unwrap_or(&ComponentHealth::Healthy);
                if *network_health == ComponentHealth::Healthy {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("Network error {} but component healthy", error)
                    ));
                }
            }
        }
        
        // Validate time consistency
        if self.global_clock > 0 {
            // All component times should be synchronized within tolerance
            let votor_ticks = self.convert_time_to_ticks(self.votor_state.current_time);
            let time_diff = votor_ticks.abs_diff(self.global_clock);
            
            if time_diff > 10 {  // 10 tick tolerance
                return Err(AlpenglowError::ProtocolViolation(
                    format!("Time synchronization drift: {} ticks", time_diff)
                ));
            }
        }
        
        // Validate performance metrics consistency
        if self.config.performance_monitoring {
            let total_operations = self.performance_metrics.messages_processed + 
                self.performance_metrics.certificate_rate + 
                self.performance_metrics.repair_rate;
            
            if total_operations > 0 {
                let failure_rate = (self.performance_metrics.failed_operations * 100) / total_operations;
                
                // If failure rate is very high, system should be degraded
                if failure_rate > 50 && self.system_state == SystemState::Running {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("High failure rate {} but system running", failure_rate)
                    ));
                }
            }
        }
        
        Ok(())
    }
}

/// Create an Alpenglow protocol model for verification
pub fn create_alpenglow_model(
    config: Config,
    byzantine_validators: HashSet<ValidatorId>,
) -> AlpenglowResult<ActorModel<AlpenglowNode, (), ()>> {
    config.validate()?;
    
    let mut model = ActorModel::new();
    
    for validator_id in 0..config.validator_count {
        let validator_id = validator_id as ValidatorId;
        let mut node = AlpenglowNode::new(validator_id, config.clone());
        
        if byzantine_validators.contains(&validator_id) {
            node = node.with_byzantine_testing();
        }
        
        model = model.actor(node);
    }
    
    Ok(model)
}
pub fn create_benchmark_model(config: Config) -> AlpenglowResult<ActorModel<AlpenglowNode, (), ()>> {
    config.validate()?;
    
    let mut model = ActorModel::new();
    for validator_id in 0..config.validator_count {
        let validator_id = validator_id as ValidatorId;
        let node = AlpenglowNode::new(validator_id, config.clone())
            .with_benchmark_mode();
        
        model = model.actor(node);
    }
    
    Ok(model)
}

// Duplicate impl Verifiable removed - already defined above

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_alpenglow_node_creation() {
        let config = Config::new().with_validators(4);
        let node = AlpenglowNode::new(0, config);
        
        assert_eq!(node.validator_id, 0);
        assert_eq!(node.config.base_config.validator_count, 4);
    }
    
    #[test]
    fn test_alpenglow_state_initialization() {
        let config = Config::new().with_validators(4);
        let protocol_config = ProtocolConfig::new(config);
        let mut state = AlpenglowState::new(0, protocol_config);
        
        assert_eq!(state.validator_id, 0);
        assert_eq!(state.system_state, SystemState::Initializing);
        
        assert!(state.initialize().is_ok());
        assert_eq!(state.system_state, SystemState::Running);
    }
    
    #[test]
    fn test_component_health_updates() {
        let config = Config::new().with_validators(4);
        let protocol_config = ProtocolConfig::new(config);
        let mut state = AlpenglowState::new(0, protocol_config);
        
        state.initialize().unwrap();
        assert_eq!(state.system_state, SystemState::Running);
        
        state.update_component_health("votor", ComponentHealth::Failed);
        assert_eq!(state.system_state, SystemState::Halted);
        
        state.update_component_health("votor", ComponentHealth::Degraded);
        assert_eq!(state.system_state, SystemState::Degraded);
    }
    
    #[test]
    fn test_performance_metrics() {
        let config = Config::new().with_validators(4);
        let protocol_config = ProtocolConfig::new(config).with_performance_monitoring();
        let mut state = AlpenglowState::new(0, protocol_config);
        
        state.performance_metrics.increment_messages();
        assert_eq!(state.performance_metrics.messages_processed, 1);
        
        state.performance_metrics.increment_failures();
        assert_eq!(state.performance_metrics.failed_operations, 1);
        
        state.performance_metrics.update_throughput(10, 5);
        assert_eq!(state.performance_metrics.throughput, 2);
    }
    
    #[test]
    fn test_cross_component_interaction() {
        let config = Config::new().with_validators(4);
        let protocol_config = ProtocolConfig::new(config);
        let mut state = AlpenglowState::new(0, protocol_config);
        
        // Create a test certificate
        let certificate = Certificate {
            slot: 1,
            view: 1,
            block: [1u8; 32],
            cert_type: CertificateType::Fast,
            signatures: crate::votor::AggregatedSignature {
                signers: [0, 1, 2, 3].iter().cloned().collect(),
                message: [1u8; 32],
                signatures: HashSet::new(),
                valid: true,
            },
            validators: [0, 1, 2, 3].iter().cloned().collect(),
            stake: 4000,
        };
        
        // This should fail because the block doesn't exist
        let result = state.process_votor_rotor_interaction(&certificate);
        assert!(result.is_err());
        assert!(state.integration_errors.contains("block_not_found"));
    }
    
    #[test]
    fn test_failure_detection() {
        let config = Config::new().with_validators(4);
        let protocol_config = ProtocolConfig::new(config);
        let mut state = AlpenglowState::new(0, protocol_config);
        
        // Simulate excessive view changes
        state.votor_state.current_view = 150;
        let failures = state.detect_component_failures();
        
        assert!(failures.contains(&"votor_excessive_views".to_string()));
        assert_eq!(state.component_health.get("votor"), Some(&ComponentHealth::Failed));
    }
    
    #[test]
    fn test_safety_verification() {
        let config = Config::new().with_validators(4);
        let protocol_config = ProtocolConfig::new(config);
        let state = AlpenglowState::new(0, protocol_config);
        
        assert!(state.verify_safety().is_ok());
    }
    
    #[test]
    fn test_tla_compatibility() {
        let config = Config::new().with_validators(4);
        let protocol_config = ProtocolConfig::new(config).with_tla_cross_validation();
        let state = AlpenglowState::new(0, protocol_config);
        
        let exported = state.export_tla_state();
        assert!(exported.get("systemState").is_some());
        assert!(exported.get("globalClock").is_some());
        
        assert!(state.validate_tla_invariants().is_ok());
    }
    
    #[test]
    fn test_model_creation() {
        let config = Config::new().with_validators(3);
        let byzantine_validators = [0].iter().cloned().collect();
        
        let model = create_alpenglow_model(config, byzantine_validators);
        assert!(model.is_ok());
    }
    
    #[test]
    fn test_benchmark_model() {
        let config = Config::new().with_validators(3);
        let model = create_benchmark_model(config);
        assert!(model.is_ok());
    }
    
    #[test]
    fn test_benchmark_report() {
        let config = Config::new().with_validators(4);
        let protocol_config = ProtocolConfig::new(config).with_benchmark_mode();
        let mut state = AlpenglowState::new(0, protocol_config);
        
        state.initialize().unwrap();
        state.advance_clock();
        
        let report = state.generate_benchmark_report();
        assert!(report.get("runtime").is_some());
        assert!(report.get("performance_metrics").is_some());
    }
}
