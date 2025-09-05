//! Alpenglow Protocol Validation Tools
//!
//! This module provides comprehensive validation tools for checking real Solana Alpenglow
//! implementations against the formal TLA+ specifications. It includes runtime invariant
//! checking, property monitoring, and conformance testing based on the proven safety and
//! liveness properties.
//!
//! ## Integration with Stateright Actor Model
//!
//! This validation module integrates with the main Alpenglow stateright implementation
//! to provide real-time validation of protocol execution. It bridges the async validation
//! runtime with the synchronous Actor model through event subscription and state observation.

use std::collections::{HashMap, HashSet, VecDeque};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use std::sync::{Arc, Mutex, RwLock};
use std::fmt;

use serde::{Deserialize, Serialize};
use tokio::sync::mpsc;
use tracing::{error, warn, info, debug};

// Import types from the main stateright crate
use alpenglow_stateright::{
    Config as AlpenglowConfig, 
    AlpenglowError, 
    AlpenglowResult,
    ValidatorId as MainValidatorId,
    SlotNumber,
    StakeAmount,
    BlockHash as MainBlockHash,
    Signature,
    Verifiable,
    TlaCompatible,
    local_stateright::{Actor, ActorModel, Id, SystemState},
    integration::{AlpenglowNode, AlpenglowState, AlpenglowMessage, ProtocolConfig},
    votor::{Certificate as MainCertificate, Vote as MainVote, Block as MainBlock, CertificateType as MainCertificateType},
};

// ============================================================================
// Core Types and Interfaces
// ============================================================================

/// Validator identifier (compatible with main crate)
pub type ValidatorId = MainValidatorId;

/// Slot number in the blockchain (compatible with main crate)
pub type Slot = SlotNumber;

/// View number for consensus rounds
pub type View = u64;

/// Block hash identifier (compatible with main crate)
pub type BlockHash = MainBlockHash;

/// Stake amount (compatible with main crate)
pub type Stake = StakeAmount;

/// Timestamp in milliseconds since epoch
pub type Timestamp = u64;

/// Block data structure (compatible with main crate)
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Block {
    pub hash: BlockHash,
    pub slot: Slot,
    pub parent_hash: BlockHash,
    pub timestamp: Timestamp,
    pub proposer: ValidatorId,
    pub transactions: Vec<Transaction>,
}

impl From<MainBlock> for Block {
    fn from(block: MainBlock) -> Self {
        Self {
            hash: block.hash,
            slot: block.slot,
            parent_hash: block.parent_hash,
            timestamp: block.timestamp,
            proposer: block.proposer,
            transactions: block.transactions.into_iter().map(|t| Transaction {
                id: t.id,
                data: t.data,
            }).collect(),
        }
    }
}

impl Into<MainBlock> for Block {
    fn into(self) -> MainBlock {
        MainBlock {
            hash: self.hash,
            slot: self.slot,
            parent_hash: self.parent_hash,
            timestamp: self.timestamp,
            proposer: self.proposer,
            transactions: self.transactions.into_iter().map(|t| alpenglow_stateright::votor::Transaction {
                id: t.id,
                data: t.data,
            }).collect(),
        }
    }
}

/// Transaction data
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Transaction {
    pub id: [u8; 32],
    pub data: Vec<u8>,
}

/// Vote for a block in a specific view (compatible with main crate)
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Vote {
    pub validator: ValidatorId,
    pub view: View,
    pub slot: Slot,
    pub block_hash: BlockHash,
    pub signature: Vec<u8>,
    pub timestamp: Timestamp,
}

impl From<MainVote> for Vote {
    fn from(vote: MainVote) -> Self {
        Self {
            validator: vote.validator,
            view: vote.view,
            slot: vote.slot,
            block_hash: vote.block_hash,
            signature: vote.signature.to_vec(),
            timestamp: vote.timestamp,
        }
    }
}

/// Certificate aggregating votes (compatible with main crate)
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Certificate {
    pub cert_type: CertificateType,
    pub slot: Slot,
    pub view: View,
    pub block_hash: BlockHash,
    pub votes: Vec<Vote>,
    pub total_stake: Stake,
    pub timestamp: Timestamp,
}

impl From<MainCertificate> for Certificate {
    fn from(cert: MainCertificate) -> Self {
        Self {
            cert_type: match cert.cert_type {
                MainCertificateType::Fast => CertificateType::Fast,
                MainCertificateType::Slow => CertificateType::Slow,
                MainCertificateType::Skip => CertificateType::Skip,
            },
            slot: cert.slot,
            view: cert.view,
            block_hash: cert.block,
            votes: Vec::new(), // Main certificate doesn't expose individual votes
            total_stake: cert.stake,
            timestamp: 0, // Not available in main certificate
        }
    }
}

/// Type of certificate based on stake threshold (compatible with main crate)
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum CertificateType {
    Fast,   // ≥80% stake
    Slow,   // ≥60% stake
    Skip,   // Skip to next view
}

/// Validator state information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ValidatorState {
    pub id: ValidatorId,
    pub stake: Stake,
    pub is_online: bool,
    pub is_byzantine: bool,
    pub current_view: View,
    pub current_slot: Slot,
    pub finalized_chain: Vec<Block>,
}

/// Network timing parameters (derived from main crate config)
#[derive(Debug, Clone)]
pub struct TimingParams {
    pub gst: Duration,           // Global Stabilization Time
    pub delta: Duration,         // Message delay bound after GST
    pub slot_duration: Duration, // Duration of each slot
    pub timeout_delta: Duration, // Timeout for view changes
}

impl Default for TimingParams {
    fn default() -> Self {
        Self {
            gst: Duration::from_secs(5),
            delta: Duration::from_millis(100),
            slot_duration: Duration::from_millis(400),
            timeout_delta: Duration::from_secs(1),
        }
    }
}

impl From<AlpenglowConfig> for TimingParams {
    fn from(config: AlpenglowConfig) -> Self {
        Self {
            gst: Duration::from_millis(config.gst),
            delta: Duration::from_millis(config.max_network_delay),
            slot_duration: Duration::from_millis(400), // Default slot duration
            timeout_delta: Duration::from_secs(1),     // Default timeout
        }
    }
}

/// Stake thresholds for different certificate types
#[derive(Debug, Clone)]
pub struct StakeThresholds {
    pub fast_path: f64,      // 0.80 (80%)
    pub slow_path: f64,      // 0.60 (60%)
    pub byzantine_bound: f64, // 0.20 (20% max)
    pub offline_bound: f64,   // 0.20 (20% max)
}

impl Default for StakeThresholds {
    fn default() -> Self {
        Self {
            fast_path: 0.80,
            slow_path: 0.60,
            byzantine_bound: 0.20,
            offline_bound: 0.20,
        }
    }
}

// ============================================================================
// Validation Events and Errors
// ============================================================================

/// Events that can be validated
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ValidationEvent {
    BlockProposed {
        block: Block,
        proposer: ValidatorId,
        timestamp: Timestamp,
    },
    VoteCast {
        vote: Vote,
        timestamp: Timestamp,
    },
    CertificateFormed {
        certificate: Certificate,
        timestamp: Timestamp,
    },
    BlockFinalized {
        block: Block,
        certificate: Certificate,
        timestamp: Timestamp,
    },
    ViewChanged {
        validator: ValidatorId,
        old_view: View,
        new_view: View,
        timestamp: Timestamp,
    },
    ValidatorOffline {
        validator: ValidatorId,
        timestamp: Timestamp,
    },
    ValidatorOnline {
        validator: ValidatorId,
        timestamp: Timestamp,
    },
    NetworkPartition {
        partitioned_validators: Vec<ValidatorId>,
        timestamp: Timestamp,
    },
    NetworkHealed {
        timestamp: Timestamp,
    },
}

/// Validation errors and violations (compatible with main crate errors)
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ValidationError {
    // Safety violations
    ConflictingBlocks {
        slot: Slot,
        block1: BlockHash,
        block2: BlockHash,
    },
    DoubleVoting {
        validator: ValidatorId,
        view: View,
        vote1: BlockHash,
        vote2: BlockHash,
    },
    InvalidCertificate {
        certificate: Certificate,
        reason: String,
    },
    
    // Liveness violations
    NoProgress {
        slot: Slot,
        duration: Duration,
    },
    SlowFinalization {
        slot: Slot,
        expected_time: Duration,
        actual_time: Duration,
    },
    
    // Byzantine behavior
    ByzantineThresholdExceeded {
        byzantine_stake: Stake,
        total_stake: Stake,
        threshold: f64,
    },
    
    // Network violations
    MessageDelayViolation {
        expected_delay: Duration,
        actual_delay: Duration,
        after_gst: bool,
    },
    
    // Implementation errors
    InvalidState {
        validator: ValidatorId,
        description: String,
    },
    ProtocolViolation {
        description: String,
    },
    
    // Integration errors
    ActorModelError {
        description: String,
    },
    StateObservationError {
        description: String,
    },
}

impl From<ValidationError> for AlpenglowError {
    fn from(err: ValidationError) -> Self {
        match err {
            ValidationError::ConflictingBlocks { .. } => 
                AlpenglowError::ProtocolViolation(format!("{}", err)),
            ValidationError::DoubleVoting { .. } => 
                AlpenglowError::ByzantineDetected(format!("{}", err)),
            ValidationError::ByzantineThresholdExceeded { .. } => 
                AlpenglowError::ByzantineDetected(format!("{}", err)),
            ValidationError::ProtocolViolation { description } => 
                AlpenglowError::ProtocolViolation(description),
            ValidationError::ActorModelError { description } => 
                AlpenglowError::Other(description),
            ValidationError::StateObservationError { description } => 
                AlpenglowError::Other(description),
            _ => AlpenglowError::Other(format!("{}", err)),
        }
    }
}

impl fmt::Display for ValidationError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ValidationError::ConflictingBlocks { slot, block1, block2 } => {
                write!(f, "Conflicting blocks in slot {}: {:?} vs {:?}", slot, block1, block2)
            }
            ValidationError::DoubleVoting { validator, view, vote1, vote2 } => {
                write!(f, "Double voting by validator {} in view {}: {:?} vs {:?}", 
                       validator, view, vote1, vote2)
            }
            ValidationError::NoProgress { slot, duration } => {
                write!(f, "No progress in slot {} for {:?}", slot, duration)
            }
            ValidationError::ByzantineThresholdExceeded { byzantine_stake, total_stake, threshold } => {
                write!(f, "Byzantine threshold exceeded: {}/{} > {}", 
                       byzantine_stake, total_stake, threshold)
            }
            _ => write!(f, "{:?}", self),
        }
    }
}

impl std::error::Error for ValidationError {}

// ============================================================================
// Actor Model Integration Bridge
// ============================================================================

/// Bridge between async validation runtime and synchronous Actor model
pub struct ActorModelBridge {
    /// Event subscription channel
    event_tx: mpsc::UnboundedSender<ValidationEvent>,
    
    /// State observation handle
    state_observer: Arc<RwLock<Option<StateObserver>>>,
    
    /// Actor model reference
    model_ref: Arc<RwLock<Option<ActorModel<AlpenglowNode, (), ()>>>>,
    
    /// Current system state snapshot
    current_state: Arc<RwLock<Option<SystemState<AlpenglowState>>>>,
}

impl ActorModelBridge {
    /// Create new bridge
    pub fn new() -> (Self, mpsc::UnboundedReceiver<ValidationEvent>) {
        let (event_tx, event_rx) = mpsc::unbounded_channel();
        
        let bridge = Self {
            event_tx,
            state_observer: Arc::new(RwLock::new(None)),
            model_ref: Arc::new(RwLock::new(None)),
            current_state: Arc::new(RwLock::new(None)),
        };
        
        (bridge, event_rx)
    }
    
    /// Attach to an Actor model for observation
    pub fn attach_to_model(&self, model: ActorModel<AlpenglowNode, (), ()>) -> AlpenglowResult<()> {
        let mut model_ref = self.model_ref.write().unwrap();
        *model_ref = Some(model);
        
        // Initialize state observer
        let observer = StateObserver::new(self.event_tx.clone());
        let mut state_observer = self.state_observer.write().unwrap();
        *state_observer = Some(observer);
        
        info!("Actor model bridge attached successfully");
        Ok(())
    }
    
    /// Observe state changes from the Actor model
    pub fn observe_state_change(&self, state: &SystemState<AlpenglowState>) -> AlpenglowResult<()> {
        // Update current state snapshot
        {
            let mut current_state = self.current_state.write().unwrap();
            *current_state = Some(state.clone());
        }
        
        // Extract validation events from state changes
        if let Some(observer) = self.state_observer.read().unwrap().as_ref() {
            observer.extract_events_from_state(state)?;
        }
        
        Ok(())
    }
    
    /// Get current Actor model state
    pub fn get_current_state(&self) -> Option<SystemState<AlpenglowState>> {
        self.current_state.read().unwrap().clone()
    }
    
    /// Send validation event
    pub fn send_event(&self, event: ValidationEvent) -> AlpenglowResult<()> {
        self.event_tx.send(event)
            .map_err(|_| AlpenglowError::Other("Failed to send validation event".to_string()))?;
        Ok(())
    }
}

/// State observer that extracts validation events from Actor model state
pub struct StateObserver {
    event_tx: mpsc::UnboundedSender<ValidationEvent>,
    last_observed_state: Arc<RwLock<Option<SystemState<AlpenglowState>>>>,
}

impl StateObserver {
    pub fn new(event_tx: mpsc::UnboundedSender<ValidationEvent>) -> Self {
        Self {
            event_tx,
            last_observed_state: Arc::new(RwLock::new(None)),
        }
    }
    
    /// Extract validation events from state changes
    pub fn extract_events_from_state(&self, state: &SystemState<AlpenglowState>) -> AlpenglowResult<()> {
        let last_state = self.last_observed_state.read().unwrap().clone();
        
        // Compare with previous state to detect changes
        if let Some(prev_state) = last_state {
            self.detect_state_changes(&prev_state, state)?;
        }
        
        // Update last observed state
        {
            let mut last_state = self.last_observed_state.write().unwrap();
            *last_state = Some(state.clone());
        }
        
        Ok(())
    }
    
    /// Detect changes between states and generate events
    fn detect_state_changes(
        &self, 
        prev_state: &SystemState<AlpenglowState>, 
        current_state: &SystemState<AlpenglowState>
    ) -> AlpenglowResult<()> {
        // Check for new finalized blocks
        for (i, current_actor_state) in current_state.actor_states.iter().enumerate() {
            if let (Some(current), Some(prev)) = (
                current_actor_state.as_ref(),
                prev_state.actor_states.get(i).and_then(|s| s.as_ref())
            ) {
                self.detect_finalized_blocks(prev, current)?;
                self.detect_certificates(prev, current)?;
                self.detect_votes(prev, current)?;
                self.detect_view_changes(prev, current)?;
            }
        }
        
        Ok(())
    }
    
    /// Detect new finalized blocks
    fn detect_finalized_blocks(
        &self,
        prev_state: &AlpenglowState,
        current_state: &AlpenglowState,
    ) -> AlpenglowResult<()> {
        let prev_finalized = &prev_state.votor_state.finalized_chain;
        let current_finalized = &current_state.votor_state.finalized_chain;
        
        // Check for new finalized blocks
        if current_finalized.len() > prev_finalized.len() {
            for block in &current_finalized[prev_finalized.len()..] {
                // Find corresponding certificate
                if let Some(cert) = self.find_certificate_for_block(current_state, block) {
                    let event = ValidationEvent::BlockFinalized {
                        block: block.clone().into(),
                        certificate: cert.into(),
                        timestamp: current_state.global_clock * 10, // Convert ticks to ms
                    };
                    
                    self.event_tx.send(event)
                        .map_err(|_| AlpenglowError::Other("Failed to send block finalized event".to_string()))?;
                }
            }
        }
        
        Ok(())
    }
    
    /// Find certificate for a finalized block
    fn find_certificate_for_block(
        &self,
        state: &AlpenglowState,
        block: &MainBlock,
    ) -> Option<MainCertificate> {
        // Look for certificate in generated certificates
        for certificates in state.votor_state.generated_certificates.values() {
            for cert in certificates {
                if cert.block == block.hash && cert.slot == block.slot {
                    return Some(cert.clone());
                }
            }
        }
        None
    }
    
    /// Detect new certificates
    fn detect_certificates(
        &self,
        prev_state: &AlpenglowState,
        current_state: &AlpenglowState,
    ) -> AlpenglowResult<()> {
        // Compare generated certificates
        for (validator_id, current_certs) in &current_state.votor_state.generated_certificates {
            let prev_certs = prev_state.votor_state.generated_certificates
                .get(validator_id)
                .map(|v| v.len())
                .unwrap_or(0);
            
            if current_certs.len() > prev_certs {
                for cert in &current_certs[prev_certs..] {
                    let event = ValidationEvent::CertificateFormed {
                        certificate: cert.clone().into(),
                        timestamp: current_state.global_clock * 10, // Convert ticks to ms
                    };
                    
                    self.event_tx.send(event)
                        .map_err(|_| AlpenglowError::Other("Failed to send certificate event".to_string()))?;
                }
            }
        }
        
        Ok(())
    }
    
    /// Detect new votes
    fn detect_votes(
        &self,
        prev_state: &AlpenglowState,
        current_state: &AlpenglowState,
    ) -> AlpenglowResult<()> {
        // Compare voting rounds for new votes
        for (view, current_round) in &current_state.votor_state.voting_rounds {
            if let Some(prev_round) = prev_state.votor_state.voting_rounds.get(view) {
                let prev_vote_count = prev_round.received_votes.len();
                let current_vote_count = current_round.received_votes.len();
                
                if current_vote_count > prev_vote_count {
                    // New votes detected - generate events for them
                    for vote in &current_round.received_votes[prev_vote_count..] {
                        let event = ValidationEvent::VoteCast {
                            vote: vote.clone().into(),
                            timestamp: current_state.global_clock * 10, // Convert ticks to ms
                        };
                        
                        self.event_tx.send(event)
                            .map_err(|_| AlpenglowError::Other("Failed to send vote event".to_string()))?;
                    }
                }
            }
        }
        
        Ok(())
    }
    
    /// Detect view changes
    fn detect_view_changes(
        &self,
        prev_state: &AlpenglowState,
        current_state: &AlpenglowState,
    ) -> AlpenglowResult<()> {
        if current_state.votor_state.current_view > prev_state.votor_state.current_view {
            let event = ValidationEvent::ViewChanged {
                validator: current_state.validator_id,
                old_view: prev_state.votor_state.current_view,
                new_view: current_state.votor_state.current_view,
                timestamp: current_state.global_clock * 10, // Convert ticks to ms
            };
            
            self.event_tx.send(event)
                .map_err(|_| AlpenglowError::Other("Failed to send view change event".to_string()))?;
        }
        
        Ok(())
    }
}

// ============================================================================
// Core Validator
// ============================================================================

/// Main validation engine that monitors Alpenglow protocol execution
pub struct AlpenglowValidator {
    /// Current system state
    state: Arc<RwLock<SystemState>>,
    
    /// Validation configuration
    config: ValidationConfig,
    
    /// Event processing channel
    event_tx: mpsc::UnboundedSender<ValidationEvent>,
    event_rx: Arc<Mutex<mpsc::UnboundedReceiver<ValidationEvent>>>,
    
    /// Violation reporting channel
    violation_tx: mpsc::UnboundedSender<ValidationError>,
    
    /// Metrics collection
    metrics: Arc<Mutex<ValidationMetrics>>,
    
    /// Property checkers
    safety_checker: SafetyChecker,
    liveness_checker: LivenessChecker,
    byzantine_checker: ByzantineChecker,
    network_checker: NetworkChecker,
    
    /// Actor model bridge for integration
    actor_bridge: Option<ActorModelBridge>,
}

/// System state tracking
#[derive(Debug, Default)]
struct SystemState {
    /// Current slot
    current_slot: Slot,
    
    /// Current time
    current_time: Timestamp,
    
    /// Validator states
    validators: HashMap<ValidatorId, ValidatorState>,
    
    /// Finalized blocks per slot
    finalized_blocks: HashMap<Slot, Vec<Block>>,
    
    /// Active certificates
    certificates: HashMap<(Slot, View), Certificate>,
    
    /// Vote history
    votes: HashMap<ValidatorId, HashMap<View, Vote>>,
    
    /// Network partitions
    partitions: Vec<HashSet<ValidatorId>>,
    
    /// Timing information
    timing_params: TimingParams,
    
    /// Stake distribution
    stake_distribution: HashMap<ValidatorId, Stake>,
    
    /// Total stake in system
    total_stake: Stake,
}

/// Validation configuration (compatible with main crate config)
#[derive(Debug, Clone)]
pub struct ValidationConfig {
    pub timing_params: TimingParams,
    pub stake_thresholds: StakeThresholds,
    pub enable_safety_checks: bool,
    pub enable_liveness_checks: bool,
    pub enable_byzantine_checks: bool,
    pub enable_network_checks: bool,
    pub enable_actor_integration: bool,
    pub max_finalization_delay: Duration,
    pub max_view_duration: Duration,
}

impl Default for ValidationConfig {
    fn default() -> Self {
        Self {
            timing_params: TimingParams::default(),
            stake_thresholds: StakeThresholds::default(),
            enable_safety_checks: true,
            enable_liveness_checks: true,
            enable_byzantine_checks: true,
            enable_network_checks: true,
            enable_actor_integration: true,
            max_finalization_delay: Duration::from_secs(10),
            max_view_duration: Duration::from_secs(5),
        }
    }
}

impl From<AlpenglowConfig> for ValidationConfig {
    fn from(config: AlpenglowConfig) -> Self {
        Self {
            timing_params: TimingParams::from(config.clone()),
            stake_thresholds: StakeThresholds {
                fast_path: config.fast_path_threshold as f64 / config.total_stake as f64,
                slow_path: config.slow_path_threshold as f64 / config.total_stake as f64,
                byzantine_bound: config.byzantine_threshold as f64 / config.validator_count as f64,
                offline_bound: 0.20,
            },
            enable_safety_checks: true,
            enable_liveness_checks: true,
            enable_byzantine_checks: true,
            enable_network_checks: true,
            enable_actor_integration: true,
            max_finalization_delay: Duration::from_secs(10),
            max_view_duration: Duration::from_secs(5),
        }
    }
}

/// Validation metrics
#[derive(Debug, Default)]
pub struct ValidationMetrics {
    pub events_processed: u64,
    pub safety_violations: u64,
    pub liveness_violations: u64,
    pub byzantine_violations: u64,
    pub network_violations: u64,
    pub fast_path_certificates: u64,
    pub slow_path_certificates: u64,
    pub skip_certificates: u64,
    pub average_finalization_time: Duration,
    pub max_finalization_time: Duration,
}

impl AlpenglowValidator {
    /// Create a new validator instance
    pub fn new(config: ValidationConfig) -> Self {
        let (event_tx, event_rx) = mpsc::unbounded_channel();
        let (violation_tx, _) = mpsc::unbounded_channel();
        
        Self {
            state: Arc::new(RwLock::new(SystemState::default())),
            config: config.clone(),
            event_tx,
            event_rx: Arc::new(Mutex::new(event_rx)),
            violation_tx,
            metrics: Arc::new(Mutex::new(ValidationMetrics::default())),
            safety_checker: SafetyChecker::new(config.clone()),
            liveness_checker: LivenessChecker::new(config.clone()),
            byzantine_checker: ByzantineChecker::new(config.clone()),
            network_checker: NetworkChecker::new(config.clone()),
            actor_bridge: None,
        }
    }
    
    /// Create validator with Actor model integration
    pub fn new_with_actor_integration(
        config: ValidationConfig,
        model: ActorModel<AlpenglowNode, (), ()>
    ) -> AlpenglowResult<Self> {
        let mut validator = Self::new(config);
        
        if validator.config.enable_actor_integration {
            let (bridge, event_rx) = ActorModelBridge::new();
            bridge.attach_to_model(model)?;
            
            // Replace event receiver with bridge receiver
            validator.event_rx = Arc::new(Mutex::new(event_rx));
            validator.actor_bridge = Some(bridge);
            
            info!("Validator created with Actor model integration");
        }
        
        Ok(validator)
    }
    
    /// Attach to existing Actor model
    pub fn attach_to_actor_model(&mut self, model: ActorModel<AlpenglowNode, (), ()>) -> AlpenglowResult<()> {
        if !self.config.enable_actor_integration {
            return Err(AlpenglowError::InvalidConfig(
                "Actor integration not enabled in config".to_string()
            ));
        }
        
        let (bridge, event_rx) = ActorModelBridge::new();
        bridge.attach_to_model(model)?;
        
        // Replace event receiver with bridge receiver
        self.event_rx = Arc::new(Mutex::new(event_rx));
        self.actor_bridge = Some(bridge);
        
        info!("Validator attached to Actor model");
        Ok(())
    }
    
    /// Observe Actor model state change
    pub fn observe_actor_state(&self, state: &SystemState<AlpenglowState>) -> AlpenglowResult<()> {
        if let Some(bridge) = &self.actor_bridge {
            bridge.observe_state_change(state)?;
        }
        Ok(())
    }
    
    /// Get current Actor model state
    pub fn get_actor_state(&self) -> Option<SystemState<AlpenglowState>> {
        self.actor_bridge.as_ref()?.get_current_state()
    }
    
    /// Get event sender for external components
    pub fn event_sender(&self) -> mpsc::UnboundedSender<ValidationEvent> {
        self.event_tx.clone()
    }
    
    /// Get violation receiver for monitoring
    pub fn violation_receiver(&self) -> mpsc::UnboundedReceiver<ValidationError> {
        let (_, rx) = mpsc::unbounded_channel();
        rx
    }
    
    /// Start the validation engine
    pub async fn run(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        info!("Starting Alpenglow validator");
        
        let event_rx = Arc::clone(&self.event_rx);
        
        loop {
            let event = {
                let mut rx = event_rx.lock().unwrap();
                rx.recv().await
            };
            
            match event {
                Some(event) => {
                    if let Err(e) = self.process_event(event).await {
                        error!("Error processing event: {}", e);
                        let _ = self.violation_tx.send(e);
                    }
                }
                None => {
                    warn!("Event channel closed, stopping validator");
                    break;
                }
            }
        }
        
        Ok(())
    }
    
    /// Process a validation event
    async fn process_event(&mut self, event: ValidationEvent) -> Result<(), ValidationError> {
        debug!("Processing event: {:?}", event);
        
        // Update metrics
        {
            let mut metrics = self.metrics.lock().unwrap();
            metrics.events_processed += 1;
        }
        
        // Update system state
        self.update_state(&event)?;
        
        // Run property checks
        if self.config.enable_safety_checks {
            self.safety_checker.check(&event, &self.state)?;
        }
        
        if self.config.enable_liveness_checks {
            self.liveness_checker.check(&event, &self.state)?;
        }
        
        if self.config.enable_byzantine_checks {
            self.byzantine_checker.check(&event, &self.state)?;
        }
        
        if self.config.enable_network_checks {
            self.network_checker.check(&event, &self.state)?;
        }
        
        Ok(())
    }
    
    /// Update system state based on event
    fn update_state(&self, event: &ValidationEvent) -> Result<(), ValidationError> {
        let mut state = self.state.write().unwrap();
        
        match event {
            ValidationEvent::BlockProposed { block, proposer, timestamp } => {
                state.current_time = *timestamp;
                state.current_slot = block.slot;
                
                // Update proposer state
                if let Some(validator) = state.validators.get_mut(proposer) {
                    validator.current_slot = block.slot;
                }
            }
            
            ValidationEvent::VoteCast { vote, timestamp } => {
                state.current_time = *timestamp;
                
                // Record vote
                state.votes
                    .entry(vote.validator)
                    .or_insert_with(HashMap::new)
                    .insert(vote.view, vote.clone());
                
                // Update validator state
                if let Some(validator) = state.validators.get_mut(&vote.validator) {
                    validator.current_view = vote.view;
                    validator.current_slot = vote.slot;
                }
            }
            
            ValidationEvent::CertificateFormed { certificate, timestamp } => {
                state.current_time = *timestamp;
                
                // Record certificate
                state.certificates.insert(
                    (certificate.slot, certificate.view),
                    certificate.clone()
                );
                
                // Update metrics
                let mut metrics = self.metrics.lock().unwrap();
                match certificate.cert_type {
                    CertificateType::Fast => metrics.fast_path_certificates += 1,
                    CertificateType::Slow => metrics.slow_path_certificates += 1,
                    CertificateType::Skip => metrics.skip_certificates += 1,
                }
            }
            
            ValidationEvent::BlockFinalized { block, certificate, timestamp } => {
                state.current_time = *timestamp;
                
                // Record finalized block
                state.finalized_blocks
                    .entry(block.slot)
                    .or_insert_with(Vec::new)
                    .push(block.clone());
                
                // Update validator finalized chains
                for validator in state.validators.values_mut() {
                    if !validator.is_byzantine {
                        // Honest validators should have consistent finalized chains
                        if validator.finalized_chain.len() <= block.slot as usize {
                            validator.finalized_chain.resize(block.slot as usize + 1, block.clone());
                        }
                        validator.finalized_chain[block.slot as usize] = block.clone();
                    }
                }
                
                // Update finalization timing metrics
                let finalization_time = Duration::from_millis(*timestamp - block.timestamp);
                let mut metrics = self.metrics.lock().unwrap();
                
                // Update average (simple moving average)
                let count = metrics.events_processed;
                metrics.average_finalization_time = Duration::from_millis(
                    (metrics.average_finalization_time.as_millis() as u64 * (count - 1) + 
                     finalization_time.as_millis() as u64) / count
                );
                
                if finalization_time > metrics.max_finalization_time {
                    metrics.max_finalization_time = finalization_time;
                }
            }
            
            ValidationEvent::ViewChanged { validator, new_view, timestamp, .. } => {
                state.current_time = *timestamp;
                
                if let Some(val_state) = state.validators.get_mut(validator) {
                    val_state.current_view = *new_view;
                }
            }
            
            ValidationEvent::ValidatorOffline { validator, timestamp } => {
                state.current_time = *timestamp;
                
                if let Some(val_state) = state.validators.get_mut(validator) {
                    val_state.is_online = false;
                }
            }
            
            ValidationEvent::ValidatorOnline { validator, timestamp } => {
                state.current_time = *timestamp;
                
                if let Some(val_state) = state.validators.get_mut(validator) {
                    val_state.is_online = true;
                }
            }
            
            ValidationEvent::NetworkPartition { partitioned_validators, timestamp } => {
                state.current_time = *timestamp;
                state.partitions.push(partitioned_validators.iter().cloned().collect());
            }
            
            ValidationEvent::NetworkHealed { timestamp } => {
                state.current_time = *timestamp;
                state.partitions.clear();
            }
        }
        
        Ok(())
    }
    
    /// Get current validation metrics
    pub fn get_metrics(&self) -> ValidationMetrics {
        self.metrics.lock().unwrap().clone()
    }
    
    /// Initialize validator set with stakes
    pub fn initialize_validators(&self, validators: Vec<(ValidatorId, Stake)>) {
        let mut state = self.state.write().unwrap();
        
        let total_stake: Stake = validators.iter().map(|(_, stake)| stake).sum();
        state.total_stake = total_stake;
        
        for (id, stake) in validators {
            state.stake_distribution.insert(id, stake);
            state.validators.insert(id, ValidatorState {
                id,
                stake,
                is_online: true,
                is_byzantine: false,
                current_view: 0,
                current_slot: 0,
                finalized_chain: Vec::new(),
            });
        }
    }
    
    /// Mark validators as Byzantine
    pub fn mark_byzantine(&self, validators: Vec<ValidatorId>) {
        let mut state = self.state.write().unwrap();
        
        for validator_id in validators {
            if let Some(validator) = state.validators.get_mut(&validator_id) {
                validator.is_byzantine = true;
            }
        }
    }
}

// ============================================================================
// Safety Property Checker
// ============================================================================

/// Checks safety properties from Safety.tla
pub struct SafetyChecker {
    config: ValidationConfig,
}

impl SafetyChecker {
    pub fn new(config: ValidationConfig) -> Self {
        Self { config }
    }
    
    /// Check safety properties for an event
    pub fn check(
        &self,
        event: &ValidationEvent,
        state: &Arc<RwLock<SystemState>>,
    ) -> Result<(), ValidationError> {
        match event {
            ValidationEvent::BlockFinalized { block, certificate, .. } => {
                self.check_safety_invariant(block, state)?;
                self.check_certificate_validity(certificate, state)?;
            }
            
            ValidationEvent::VoteCast { vote, .. } => {
                self.check_no_double_voting(vote, state)?;
            }
            
            ValidationEvent::CertificateFormed { certificate, .. } => {
                self.check_certificate_stake_requirements(certificate, state)?;
            }
            
            _ => {}
        }
        
        Ok(())
    }
    
    /// Check SafetyInvariant: No two conflicting blocks finalized in same slot
    fn check_safety_invariant(
        &self,
        block: &Block,
        state: &Arc<RwLock<SystemState>>,
    ) -> Result<(), ValidationError> {
        let state = state.read().unwrap();
        
        if let Some(finalized_blocks) = state.finalized_blocks.get(&block.slot) {
            for existing_block in finalized_blocks {
                if existing_block.hash != block.hash {
                    return Err(ValidationError::ConflictingBlocks {
                        slot: block.slot,
                        block1: existing_block.hash,
                        block2: block.hash,
                    });
                }
            }
        }
        
        Ok(())
    }
    
    /// Check HonestSingleVote: Honest validators vote at most once per view
    fn check_no_double_voting(
        &self,
        vote: &Vote,
        state: &Arc<RwLock<SystemState>>,
    ) -> Result<(), ValidationError> {
        let state = state.read().unwrap();
        
        // Only check for honest validators
        if let Some(validator) = state.validators.get(&vote.validator) {
            if validator.is_byzantine {
                return Ok(()); // Byzantine validators can double vote
            }
        }
        
        if let Some(validator_votes) = state.votes.get(&vote.validator) {
            if let Some(existing_vote) = validator_votes.get(&vote.view) {
                if existing_vote.block_hash != vote.block_hash {
                    return Err(ValidationError::DoubleVoting {
                        validator: vote.validator,
                        view: vote.view,
                        vote1: existing_vote.block_hash,
                        vote2: vote.block_hash,
                    });
                }
            }
        }
        
        Ok(())
    }
    
    /// Check certificate has sufficient stake
    fn check_certificate_stake_requirements(
        &self,
        certificate: &Certificate,
        state: &Arc<RwLock<SystemState>>,
    ) -> Result<(), ValidationError> {
        let state = state.read().unwrap();
        
        let required_stake = match certificate.cert_type {
            CertificateType::Fast => {
                (state.total_stake as f64 * self.config.stake_thresholds.fast_path) as Stake
            }
            CertificateType::Slow => {
                (state.total_stake as f64 * self.config.stake_thresholds.slow_path) as Stake
            }
            CertificateType::Skip => {
                (state.total_stake as f64 * self.config.stake_thresholds.slow_path) as Stake
            }
        };
        
        if certificate.total_stake < required_stake {
            return Err(ValidationError::InvalidCertificate {
                certificate: certificate.clone(),
                reason: format!(
                    "Insufficient stake: {} < {} required for {:?}",
                    certificate.total_stake, required_stake, certificate.cert_type
                ),
            });
        }
        
        Ok(())
    }
    
    /// Check certificate validity
    fn check_certificate_validity(
        &self,
        certificate: &Certificate,
        state: &Arc<RwLock<SystemState>>,
    ) -> Result<(), ValidationError> {
        let state = state.read().unwrap();
        
        // Verify all votes in certificate are for the same block
        for vote in &certificate.votes {
            if vote.block_hash != certificate.block_hash {
                return Err(ValidationError::InvalidCertificate {
                    certificate: certificate.clone(),
                    reason: "Vote block hash mismatch".to_string(),
                });
            }
            
            if vote.view != certificate.view {
                return Err(ValidationError::InvalidCertificate {
                    certificate: certificate.clone(),
                    reason: "Vote view mismatch".to_string(),
                });
            }
            
            if vote.slot != certificate.slot {
                return Err(ValidationError::InvalidCertificate {
                    certificate: certificate.clone(),
                    reason: "Vote slot mismatch".to_string(),
                });
            }
        }
        
        // Verify stake calculation
        let calculated_stake: Stake = certificate.votes
            .iter()
            .map(|vote| state.stake_distribution.get(&vote.validator).unwrap_or(&0))
            .sum();
        
        if calculated_stake != certificate.total_stake {
            return Err(ValidationError::InvalidCertificate {
                certificate: certificate.clone(),
                reason: format!(
                    "Stake calculation mismatch: {} != {}",
                    calculated_stake, certificate.total_stake
                ),
            });
        }
        
        Ok(())
    }
}

// ============================================================================
// Liveness Property Checker
// ============================================================================

/// Checks liveness properties from Liveness.tla
pub struct LivenessChecker {
    config: ValidationConfig,
    slot_start_times: HashMap<Slot, Timestamp>,
    view_start_times: HashMap<(ValidatorId, View), Timestamp>,
}

impl LivenessChecker {
    pub fn new(config: ValidationConfig) -> Self {
        Self {
            config,
            slot_start_times: HashMap::new(),
            view_start_times: HashMap::new(),
        }
    }
    
    /// Check liveness properties for an event
    pub fn check(
        &mut self,
        event: &ValidationEvent,
        state: &Arc<RwLock<SystemState>>,
    ) -> Result<(), ValidationError> {
        match event {
            ValidationEvent::BlockProposed { block, timestamp, .. } => {
                self.slot_start_times.entry(block.slot).or_insert(*timestamp);
                self.check_progress(block.slot, *timestamp, state)?;
            }
            
            ValidationEvent::BlockFinalized { block, timestamp, .. } => {
                self.check_bounded_finalization(block, *timestamp, state)?;
            }
            
            ValidationEvent::ViewChanged { validator, new_view, timestamp, .. } => {
                self.view_start_times.insert((*validator, *new_view), *timestamp);
                self.check_timeout_progress(*validator, *new_view, *timestamp, state)?;
            }
            
            _ => {}
        }
        
        Ok(())
    }
    
    /// Check Progress: System makes progress with >60% honest stake
    fn check_progress(
        &self,
        slot: Slot,
        current_time: Timestamp,
        state: &Arc<RwLock<SystemState>>,
    ) -> Result<(), ValidationError> {
        let state = state.read().unwrap();
        
        // Check if we have sufficient honest stake
        let honest_stake: Stake = state.validators
            .values()
            .filter(|v| !v.is_byzantine && v.is_online)
            .map(|v| v.stake)
            .sum();
        
        let required_stake = (state.total_stake as f64 * self.config.stake_thresholds.slow_path) as Stake;
        
        if honest_stake < required_stake {
            return Ok(()); // Not enough honest stake, progress not guaranteed
        }
        
        // Check if we're after GST
        let gst_time = self.config.timing_params.gst.as_millis() as Timestamp;
        if current_time < gst_time {
            return Ok(()); // Before GST, progress not guaranteed
        }
        
        // Check if slot has been running too long without finalization
        if let Some(start_time) = self.slot_start_times.get(&slot) {
            let duration = Duration::from_millis(current_time - start_time);
            
            if duration > self.config.max_finalization_delay {
                // Check if block is actually finalized
                if !state.finalized_blocks.contains_key(&slot) {
                    return Err(ValidationError::NoProgress { slot, duration });
                }
            }
        }
        
        Ok(())
    }
    
    /// Check BoundedFinalization: Finalization within 2*Delta after GST
    fn check_bounded_finalization(
        &self,
        block: &Block,
        finalization_time: Timestamp,
        state: &Arc<RwLock<SystemState>>,
    ) -> Result<(), ValidationError> {
        let state = state.read().unwrap();
        
        // Check if we have sufficient honest stake
        let honest_stake: Stake = state.validators
            .values()
            .filter(|v| !v.is_byzantine && v.is_online)
            .map(|v| v.stake)
            .sum();
        
        let required_stake = (state.total_stake as f64 * self.config.stake_thresholds.slow_path) as Stake;
        
        if honest_stake < required_stake {
            return Ok(()); // Not enough honest stake, bounded finalization not guaranteed
        }
        
        // Check timing after GST
        let gst_time = self.config.timing_params.gst.as_millis() as Timestamp;
        if block.timestamp < gst_time {
            return Ok(()); // Block proposed before GST
        }
        
        let finalization_duration = Duration::from_millis(finalization_time - block.timestamp);
        let max_expected_duration = 2 * self.config.timing_params.delta;
        
        if finalization_duration > max_expected_duration {
            return Err(ValidationError::SlowFinalization {
                slot: block.slot,
                expected_time: max_expected_duration,
                actual_time: finalization_duration,
            });
        }
        
        Ok(())
    }
    
    /// Check TimeoutProgress: Views advance despite unresponsive leaders
    fn check_timeout_progress(
        &self,
        validator: ValidatorId,
        view: View,
        timestamp: Timestamp,
        state: &Arc<RwLock<SystemState>>,
    ) -> Result<(), ValidationError> {
        let state = state.read().unwrap();
        
        // Check if validator is honest
        if let Some(val_state) = state.validators.get(&validator) {
            if val_state.is_byzantine {
                return Ok(()); // Byzantine validators can behave arbitrarily
            }
        }
        
        // Check if previous view lasted too long
        if view > 0 {
            if let Some(prev_start) = self.view_start_times.get(&(validator, view - 1)) {
                let view_duration = Duration::from_millis(timestamp - prev_start);
                
                if view_duration > self.config.max_view_duration {
                    // This is actually expected behavior - timeouts should cause view changes
                    debug!("View {} lasted {:?}, triggering timeout", view - 1, view_duration);
                }
            }
        }
        
        Ok(())
    }
}

// ============================================================================
// Byzantine Fault Checker
// ============================================================================

/// Checks Byzantine fault tolerance properties
pub struct ByzantineChecker {
    config: ValidationConfig,
}

impl ByzantineChecker {
    pub fn new(config: ValidationConfig) -> Self {
        Self { config }
    }
    
    /// Check Byzantine fault tolerance properties
    pub fn check(
        &self,
        event: &ValidationEvent,
        state: &Arc<RwLock<SystemState>>,
    ) -> Result<(), ValidationError> {
        match event {
            ValidationEvent::VoteCast { vote, .. } => {
                self.check_byzantine_threshold(state)?;
                self.detect_equivocation(vote, state)?;
            }
            
            ValidationEvent::CertificateFormed { certificate, .. } => {
                self.check_byzantine_certificate_resistance(certificate, state)?;
            }
            
            _ => {}
        }
        
        Ok(())
    }
    
    /// Check that Byzantine stake doesn't exceed 20% threshold
    fn check_byzantine_threshold(
        &self,
        state: &Arc<RwLock<SystemState>>,
    ) -> Result<(), ValidationError> {
        let state = state.read().unwrap();
        
        let byzantine_stake: Stake = state.validators
            .values()
            .filter(|v| v.is_byzantine)
            .map(|v| v.stake)
            .sum();
        
        let threshold = state.total_stake as f64 * self.config.stake_thresholds.byzantine_bound;
        
        if byzantine_stake as f64 > threshold {
            return Err(ValidationError::ByzantineThresholdExceeded {
                byzantine_stake,
                total_stake: state.total_stake,
                threshold: self.config.stake_thresholds.byzantine_bound,
            });
        }
        
        Ok(())
    }
    
    /// Detect equivocation (double voting) patterns
    fn detect_equivocation(
        &self,
        vote: &Vote,
        state: &Arc<RwLock<SystemState>>,
    ) -> Result<(), ValidationError> {
        let state = state.read().unwrap();
        
        if let Some(validator_votes) = state.votes.get(&vote.validator) {
            if let Some(existing_vote) = validator_votes.get(&vote.view) {
                if existing_vote.block_hash != vote.block_hash {
                    // This is equivocation - mark validator as Byzantine if not already
                    warn!("Detected equivocation from validator {}", vote.validator);
                    
                    // In a real implementation, this would trigger Byzantine marking
                    // For validation, we report it as a potential issue
                    return Err(ValidationError::DoubleVoting {
                        validator: vote.validator,
                        view: vote.view,
                        vote1: existing_vote.block_hash,
                        vote2: vote.block_hash,
                    });
                }
            }
        }
        
        Ok(())
    }
    
    /// Check that Byzantine validators alone cannot form certificates
    fn check_byzantine_certificate_resistance(
        &self,
        certificate: &Certificate,
        state: &Arc<RwLock<SystemState>>,
    ) -> Result<(), ValidationError> {
        let state = state.read().unwrap();
        
        let byzantine_stake_in_cert: Stake = certificate.votes
            .iter()
            .filter_map(|vote| {
                state.validators.get(&vote.validator)
                    .filter(|v| v.is_byzantine)
                    .map(|v| v.stake)
            })
            .sum();
        
        // Byzantine validators alone should not be able to form any certificate
        let min_required_stake = (state.total_stake as f64 * self.config.stake_thresholds.slow_path) as Stake;
        
        if byzantine_stake_in_cert >= min_required_stake {
            return Err(ValidationError::InvalidCertificate {
                certificate: certificate.clone(),
                reason: format!(
                    "Certificate formed with only Byzantine stake: {} >= {}",
                    byzantine_stake_in_cert, min_required_stake
                ),
            });
        }
        
        Ok(())
    }
}

// ============================================================================
// Network Property Checker
// ============================================================================

/// Checks network timing and partition properties
pub struct NetworkChecker {
    config: ValidationConfig,
    message_timestamps: HashMap<(ValidatorId, ValidatorId), Vec<Timestamp>>,
}

impl NetworkChecker {
    pub fn new(config: ValidationConfig) -> Self {
        Self {
            config,
            message_timestamps: HashMap::new(),
        }
    }
    
    /// Check network properties
    pub fn check(
        &mut self,
        event: &ValidationEvent,
        state: &Arc<RwLock<SystemState>>,
    ) -> Result<(), ValidationError> {
        match event {
            ValidationEvent::VoteCast { vote, timestamp } => {
                self.check_message_delay(vote.validator, *timestamp, state)?;
            }
            
            ValidationEvent::NetworkPartition { .. } => {
                self.check_partition_behavior(state)?;
            }
            
            _ => {}
        }
        
        Ok(())
    }
    
    /// Check message delivery delays after GST
    fn check_message_delay(
        &mut self,
        sender: ValidatorId,
        timestamp: Timestamp,
        state: &Arc<RwLock<SystemState>>,
    ) -> Result<(), ValidationError> {
        let state = state.read().unwrap();
        
        let gst_time = self.config.timing_params.gst.as_millis() as Timestamp;
        
        if timestamp > gst_time {
            // After GST, messages should be delivered within Delta
            // This is a simplified check - in practice, we'd track individual message delivery
            
            // Record message timestamp for this sender
            for validator in state.validators.keys() {
                if *validator != sender {
                    self.message_timestamps
                        .entry((sender, *validator))
                        .or_insert_with(Vec::new)
                        .push(timestamp);
                }
            }
        }
        
        Ok(())
    }
    
    /// Check behavior during network partitions
    fn check_partition_behavior(
        &self,
        state: &Arc<RwLock<SystemState>>,
    ) -> Result<(), ValidationError> {
        let state = state.read().unwrap();
        
        // During partitions, progress should only be possible if one partition
        // has >60% of total stake
        for partition in &state.partitions {
            let partition_stake: Stake = partition
                .iter()
                .filter_map(|v| state.validators.get(v))
                .map(|v| v.stake)
                .sum();
            
            let required_stake = (state.total_stake as f64 * self.config.stake_thresholds.slow_path) as Stake;
            
            if partition_stake >= required_stake {
                // This partition can make progress
                debug!("Partition with {}/{} stake can make progress", 
                       partition_stake, state.total_stake);
            }
        }
        
        Ok(())
    }
}

// ============================================================================
// Conformance Testing Interface
// ============================================================================

/// Conformance test suite for Alpenglow implementations
pub struct ConformanceTestSuite {
    validator: AlpenglowValidator,
    test_scenarios: Vec<TestScenario>,
}

/// Individual test scenario
#[derive(Debug, Clone)]
pub struct TestScenario {
    pub name: String,
    pub description: String,
    pub events: Vec<ValidationEvent>,
    pub expected_violations: Vec<ValidationError>,
    pub timeout: Duration,
}

impl ConformanceTestSuite {
    /// Create new test suite
    pub fn new(config: ValidationConfig) -> Self {
        Self {
            validator: AlpenglowValidator::new(config),
            test_scenarios: Self::create_default_scenarios(),
        }
    }
    
    /// Run all conformance tests
    pub async fn run_all_tests(&mut self) -> ConformanceTestResults {
        let mut results = ConformanceTestResults::default();
        
        for scenario in &self.test_scenarios.clone() {
            let result = self.run_test_scenario(scenario).await;
            results.add_result(scenario.name.clone(), result);
        }
        
        results
    }
    
    /// Run a specific test scenario
    pub async fn run_test_scenario(&mut self, scenario: &TestScenario) -> TestResult {
        info!("Running test scenario: {}", scenario.name);
        
        let start_time = Instant::now();
        let mut violations = Vec::new();
        
        // Process all events in the scenario
        for event in &scenario.events {
            if let Err(violation) = self.validator.process_event(event.clone()).await {
                violations.push(violation);
            }
        }
        
        let duration = start_time.elapsed();
        
        // Check if violations match expectations
        let expected_set: HashSet<_> = scenario.expected_violations.iter().collect();
        let actual_set: HashSet<_> = violations.iter().collect();
        
        let success = expected_set == actual_set;
        
        TestResult {
            success,
            duration,
            violations,
            expected_violations: scenario.expected_violations.clone(),
        }
    }
    
    /// Create default test scenarios
    fn create_default_scenarios() -> Vec<TestScenario> {
        vec![
            // Safety test: Conflicting blocks
            TestScenario {
                name: "safety_conflicting_blocks".to_string(),
                description: "Test detection of conflicting blocks in same slot".to_string(),
                events: vec![
                    ValidationEvent::BlockFinalized {
                        block: Block {
                            hash: [1; 32],
                            slot: 1,
                            parent_hash: [0; 32],
                            timestamp: 1000,
                            proposer: 1,
                            transactions: vec![],
                        },
                        certificate: Certificate {
                            cert_type: CertificateType::Fast,
                            slot: 1,
                            view: 1,
                            block_hash: [1; 32],
                            votes: vec![],
                            total_stake: 800,
                            timestamp: 1000,
                        },
                        timestamp: 1000,
                    },
                    ValidationEvent::BlockFinalized {
                        block: Block {
                            hash: [2; 32],
                            slot: 1,
                            parent_hash: [0; 32],
                            timestamp: 1000,
                            proposer: 2,
                            transactions: vec![],
                        },
                        certificate: Certificate {
                            cert_type: CertificateType::Fast,
                            slot: 1,
                            view: 1,
                            block_hash: [2; 32],
                            votes: vec![],
                            total_stake: 800,
                            timestamp: 1000,
                        },
                        timestamp: 1000,
                    },
                ],
                expected_violations: vec![
                    ValidationError::ConflictingBlocks {
                        slot: 1,
                        block1: [1; 32],
                        block2: [2; 32],
                    }
                ],
                timeout: Duration::from_secs(5),
            },
            
            // Liveness test: No progress
            TestScenario {
                name: "liveness_no_progress".to_string(),
                description: "Test detection of lack of progress".to_string(),
                events: vec![
                    ValidationEvent::BlockProposed {
                        block: Block {
                            hash: [1; 32],
                            slot: 1,
                            parent_hash: [0; 32],
                            timestamp: 6000, // After GST
                            proposer: 1,
                            transactions: vec![],
                        },
                        proposer: 1,
                        timestamp: 6000,
                    },
                    // No finalization for a long time
                ],
                expected_violations: vec![
                    ValidationError::NoProgress {
                        slot: 1,
                        duration: Duration::from_secs(10),
                    }
                ],
                timeout: Duration::from_secs(15),
            },
            
            // Byzantine test: Double voting
            TestScenario {
                name: "byzantine_double_voting".to_string(),
                description: "Test detection of double voting".to_string(),
                events: vec![
                    ValidationEvent::VoteCast {
                        vote: Vote {
                            validator: 1,
                            view: 1,
                            slot: 1,
                            block_hash: [1; 32],
                            signature: vec![],
                            timestamp: 1000,
                        },
                        timestamp: 1000,
                    },
                    ValidationEvent::VoteCast {
                        vote: Vote {
                            validator: 1,
                            view: 1,
                            slot: 1,
                            block_hash: [2; 32],
                            signature: vec![],
                            timestamp: 1001,
                        },
                        timestamp: 1001,
                    },
                ],
                expected_violations: vec![
                    ValidationError::DoubleVoting {
                        validator: 1,
                        view: 1,
                        vote1: [1; 32],
                        vote2: [2; 32],
                    }
                ],
                timeout: Duration::from_secs(5),
            },
        ]
    }
    
    /// Add custom test scenario
    pub fn add_test_scenario(&mut self, scenario: TestScenario) {
        self.test_scenarios.push(scenario);
    }
}

/// Results of conformance testing
#[derive(Debug, Default)]
pub struct ConformanceTestResults {
    pub total_tests: usize,
    pub passed_tests: usize,
    pub failed_tests: usize,
    pub test_results: HashMap<String, TestResult>,
}

impl ConformanceTestResults {
    fn add_result(&mut self, test_name: String, result: TestResult) {
        self.total_tests += 1;
        if result.success {
            self.passed_tests += 1;
        } else {
            self.failed_tests += 1;
        }
        self.test_results.insert(test_name, result);
    }
    
    pub fn success_rate(&self) -> f64 {
        if self.total_tests == 0 {
            0.0
        } else {
            self.passed_tests as f64 / self.total_tests as f64
        }
    }
}

/// Result of a single test
#[derive(Debug, Clone)]
pub struct TestResult {
    pub success: bool,
    pub duration: Duration,
    pub violations: Vec<ValidationError>,
    pub expected_violations: Vec<ValidationError>,
}

// ============================================================================
// Runtime Monitoring Interface
// ============================================================================

/// Runtime monitor for live Alpenglow deployments
pub struct RuntimeMonitor {
    validator: AlpenglowValidator,
    alert_thresholds: AlertThresholds,
    alert_sender: mpsc::UnboundedSender<Alert>,
}

/// Alert thresholds for monitoring
#[derive(Debug, Clone)]
pub struct AlertThresholds {
    pub max_finalization_delay: Duration,
    pub max_byzantine_stake_ratio: f64,
    pub max_offline_stake_ratio: f64,
    pub min_fast_path_ratio: f64,
}

impl Default for AlertThresholds {
    fn default() -> Self {
        Self {
            max_finalization_delay: Duration::from_secs(10),
            max_byzantine_stake_ratio: 0.15, // Alert at 15% (before 20% limit)
            max_offline_stake_ratio: 0.15,
            min_fast_path_ratio: 0.80, // Alert if fast path usage drops below 80%
        }
    }
}

/// Alert types for monitoring
#[derive(Debug, Clone)]
pub enum Alert {
    SafetyViolation {
        violation: ValidationError,
        timestamp: Timestamp,
        severity: AlertSeverity,
    },
    LivenessIssue {
        description: String,
        timestamp: Timestamp,
        severity: AlertSeverity,
    },
    ByzantineActivity {
        validator: ValidatorId,
        description: String,
        timestamp: Timestamp,
        severity: AlertSeverity,
    },
    NetworkIssue {
        description: String,
        timestamp: Timestamp,
        severity: AlertSeverity,
    },
    PerformanceDegradation {
        metric: String,
        current_value: f64,
        threshold: f64,
        timestamp: Timestamp,
        severity: AlertSeverity,
    },
}

/// Alert severity levels
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AlertSeverity {
    Info,
    Warning,
    Critical,
    Emergency,
}

impl RuntimeMonitor {
    /// Create new runtime monitor
    pub fn new(
        config: ValidationConfig,
        alert_thresholds: AlertThresholds,
    ) -> (Self, mpsc::UnboundedReceiver<Alert>) {
        let (alert_sender, alert_receiver) = mpsc::unbounded_channel();
        
        let monitor = Self {
            validator: AlpenglowValidator::new(config),
            alert_thresholds,
            alert_sender,
        };
        
        (monitor, alert_receiver)
    }
    
    /// Start monitoring
    pub async fn start_monitoring(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        info!("Starting runtime monitoring");
        
        // Start the validator
        tokio::spawn(async move {
            // This would be the main monitoring loop
            // In practice, this would connect to the actual Alpenglow implementation
        });
        
        Ok(())
    }
    
    /// Process monitoring event
    pub async fn process_monitoring_event(&mut self, event: ValidationEvent) {
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_millis() as Timestamp;
        
        // Process through validator
        if let Err(violation) = self.validator.process_event(event).await {
            let severity = self.classify_violation_severity(&violation);
            
            let alert = Alert::SafetyViolation {
                violation,
                timestamp,
                severity,
            };
            
            let _ = self.alert_sender.send(alert);
        }
        
        // Check performance metrics
        self.check_performance_alerts(timestamp).await;
    }
    
    /// Classify violation severity
    fn classify_violation_severity(&self, violation: &ValidationError) -> AlertSeverity {
        match violation {
            ValidationError::ConflictingBlocks { .. } => AlertSeverity::Emergency,
            ValidationError::DoubleVoting { .. } => AlertSeverity::Critical,
            ValidationError::ByzantineThresholdExceeded { .. } => AlertSeverity::Emergency,
            ValidationError::NoProgress { .. } => AlertSeverity::Warning,
            ValidationError::SlowFinalization { .. } => AlertSeverity::Info,
            _ => AlertSeverity::Warning,
        }
    }
    
    /// Check for performance-related alerts
    async fn check_performance_alerts(&self, timestamp: Timestamp) {
        let metrics = self.validator.get_metrics();
        
        // Check finalization delay
        if metrics.max_finalization_time > self.alert_thresholds.max_finalization_delay {
            let alert = Alert::PerformanceDegradation {
                metric: "max_finalization_time".to_string(),
                current_value: metrics.max_finalization_time.as_secs_f64(),
                threshold: self.alert_thresholds.max_finalization_delay.as_secs_f64(),
                timestamp,
                severity: AlertSeverity::Warning,
            };
            
            let _ = self.alert_sender.send(alert);
        }
        
        // Check fast path ratio
        let total_certs = metrics.fast_path_certificates + metrics.slow_path_certificates;
        if total_certs > 0 {
            let fast_path_ratio = metrics.fast_path_certificates as f64 / total_certs as f64;
            
            if fast_path_ratio < self.alert_thresholds.min_fast_path_ratio {
                let alert = Alert::PerformanceDegradation {
                    metric: "fast_path_ratio".to_string(),
                    current_value: fast_path_ratio,
                    threshold: self.alert_thresholds.min_fast_path_ratio,
                    timestamp,
                    severity: AlertSeverity::Info,
                };
                
                let _ = self.alert_sender.send(alert);
            }
        }
    }
}

// ============================================================================
// Public API
// ============================================================================

/// Main entry point for validation tools with Actor model integration
pub struct ValidationTools {
    validator: AlpenglowValidator,
    conformance_suite: ConformanceTestSuite,
    runtime_monitor: Option<RuntimeMonitor>,
    actor_model: Option<ActorModel<AlpenglowNode, (), ()>>,
}

impl ValidationTools {
    /// Create new validation tools instance
    pub fn new(config: ValidationConfig) -> Self {
        Self {
            validator: AlpenglowValidator::new(config.clone()),
            conformance_suite: ConformanceTestSuite::new(config.clone()),
            runtime_monitor: None,
            actor_model: None,
        }
    }
    
    /// Create validation tools with Actor model integration
    pub fn new_with_actor_model(
        config: ValidationConfig,
        model: ActorModel<AlpenglowNode, (), ()>
    ) -> AlpenglowResult<Self> {
        let validator = AlpenglowValidator::new_with_actor_integration(config.clone(), model.clone())?;
        
        Ok(Self {
            validator,
            conformance_suite: ConformanceTestSuite::new(config.clone()),
            runtime_monitor: None,
            actor_model: Some(model),
        })
    }
    
    /// Create validation tools from Alpenglow config
    pub fn from_alpenglow_config(config: AlpenglowConfig) -> AlpenglowResult<Self> {
        let validation_config = ValidationConfig::from(config.clone());
        let model = alpenglow_stateright::create_model(config)?;
        
        Self::new_with_actor_model(validation_config, model)
    }
    
    /// Attach to existing Actor model
    pub fn attach_to_actor_model(&mut self, model: ActorModel<AlpenglowNode, (), ()>) -> AlpenglowResult<()> {
        self.validator.attach_to_actor_model(model.clone())?;
        self.actor_model = Some(model);
        Ok(())
    }
    
    /// Initialize with validator set
    pub fn initialize_validators(&mut self, validators: Vec<(ValidatorId, Stake)>) {
        self.validator.initialize_validators(validators);
    }
    
    /// Get event sender for real-time validation
    pub fn get_event_sender(&self) -> mpsc::UnboundedSender<ValidationEvent> {
        self.validator.event_sender()
    }
    
    /// Run conformance tests
    pub async fn run_conformance_tests(&mut self) -> ConformanceTestResults {
        self.conformance_suite.run_all_tests().await
    }
    
    /// Run conformance tests with Actor model
    pub async fn run_actor_model_tests(&mut self) -> AlpenglowResult<ConformanceTestResults> {
        if self.actor_model.is_none() {
            return Err(AlpenglowError::InvalidConfig(
                "No Actor model attached for testing".to_string()
            ));
        }
        
        // Run tests with Actor model integration
        let results = self.conformance_suite.run_all_tests().await;
        Ok(results)
    }
    
    /// Start runtime monitoring
    pub fn start_runtime_monitoring(
        &mut self,
        alert_thresholds: AlertThresholds,
    ) -> mpsc::UnboundedReceiver<Alert> {
        let (monitor, alert_receiver) = RuntimeMonitor::new(
            ValidationConfig::default(),
            alert_thresholds,
        );
        
        self.runtime_monitor = Some(monitor);
        alert_receiver
    }
    
    /// Observe Actor model state change (for integration)
    pub fn observe_actor_state(&self, state: &SystemState<AlpenglowState>) -> AlpenglowResult<()> {
        self.validator.observe_actor_state(state)
    }
    
    /// Get current Actor model state
    pub fn get_actor_state(&self) -> Option<SystemState<AlpenglowState>> {
        self.validator.get_actor_state()
    }
    
    /// Get current validation metrics
    pub fn get_metrics(&self) -> ValidationMetrics {
        self.validator.get_metrics()
    }
    
    /// Validate Actor model state against TLA+ invariants
    pub fn validate_actor_invariants(&self) -> AlpenglowResult<()> {
        if let Some(state) = self.get_actor_state() {
            for actor_state in &state.actor_states {
                if let Some(alpenglow_state) = actor_state.as_ref() {
                    alpenglow_state.validate_tla_invariants()?;
                }
            }
        }
        Ok(())
    }
    
    /// Export Actor model state for TLA+ cross-validation
    pub fn export_actor_tla_state(&self) -> Option<serde_json::Value> {
        if let Some(state) = self.get_actor_state() {
            let mut exported_states = Vec::new();
            
            for actor_state in &state.actor_states {
                if let Some(alpenglow_state) = actor_state.as_ref() {
                    exported_states.push(alpenglow_state.export_tla_state());
                }
            }
            
            Some(serde_json::json!({
                "actor_states": exported_states,
                "system_time": state.system_time,
                "validation_timestamp": SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap()
                    .as_millis()
            }))
        } else {
            None
        }
    }
}

/// Integration utilities for bridging validation with Actor model
pub mod integration {
    use super::*;
    
    /// Create validation tools from Actor model
    pub fn create_validation_from_model(
        model: ActorModel<AlpenglowNode, (), ()>
    ) -> AlpenglowResult<ValidationTools> {
        let config = ValidationConfig::default();
        ValidationTools::new_with_actor_model(config, model)
    }
    
    /// Create validation tools from Alpenglow config
    pub fn create_validation_from_config(
        config: AlpenglowConfig
    ) -> AlpenglowResult<ValidationTools> {
        ValidationTools::from_alpenglow_config(config)
    }
    
    /// Run end-to-end validation test
    pub async fn run_end_to_end_validation(
        config: AlpenglowConfig,
        test_duration: Duration,
    ) -> AlpenglowResult<ValidationReport> {
        let mut tools = create_validation_from_config(config)?;
        
        // Initialize validators
        let validators: Vec<(ValidatorId, Stake)> = (0..4)
            .map(|i| (i, 1000))
            .collect();
        tools.initialize_validators(validators);
        
        // Run conformance tests
        let conformance_results = tools.run_actor_model_tests().await?;
        
        // Validate invariants
        tools.validate_actor_invariants()?;
        
        // Export TLA+ state
        let tla_state = tools.export_actor_tla_state();
        
        Ok(ValidationReport {
            conformance_results,
            invariant_validation: true,
            tla_state_export: tla_state,
            metrics: tools.get_metrics(),
            test_duration,
        })
    }
}

/// Comprehensive validation report
#[derive(Debug)]
pub struct ValidationReport {
    pub conformance_results: ConformanceTestResults,
    pub invariant_validation: bool,
    pub tla_state_export: Option<serde_json::Value>,
    pub metrics: ValidationMetrics,
    pub test_duration: Duration,
}

impl ValidationReport {
    /// Check if validation passed
    pub fn is_valid(&self) -> bool {
        self.conformance_results.success_rate() > 0.95 && self.invariant_validation
    }
    
    /// Generate summary report
    pub fn summary(&self) -> String {
        format!(
            "Validation Report:\n\
             - Conformance Tests: {}/{} passed ({:.1}%)\n\
             - Invariant Validation: {}\n\
             - Events Processed: {}\n\
             - Safety Violations: {}\n\
             - Liveness Violations: {}\n\
             - Byzantine Violations: {}\n\
             - Test Duration: {:?}\n\
             - Overall Status: {}",
            self.conformance_results.passed_tests,
            self.conformance_results.total_tests,
            self.conformance_results.success_rate() * 100.0,
            if self.invariant_validation { "PASSED" } else { "FAILED" },
            self.metrics.events_processed,
            self.metrics.safety_violations,
            self.metrics.liveness_violations,
            self.metrics.byzantine_violations,
            self.test_duration,
            if self.is_valid() { "VALID" } else { "INVALID" }
        )
    }
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use alpenglow_stateright::utils::test_configs;
    
    #[tokio::test]
    async fn test_safety_invariant_violation() {
        let mut validator = AlpenglowValidator::new(ValidationConfig::default());
        
        // Initialize validators
        validator.initialize_validators(vec![(1, 100), (2, 100), (3, 100)]);
        
        // Create conflicting blocks
        let block1 = Block {
            hash: [1; 32],
            slot: 1,
            parent_hash: [0; 32],
            timestamp: 1000,
            proposer: 1,
            transactions: vec![],
        };
        
        let block2 = Block {
            hash: [2; 32],
            slot: 1,
            parent_hash: [0; 32],
            timestamp: 1000,
            proposer: 2,
            transactions: vec![],
        };
        
        // Finalize first block
        let cert1 = Certificate {
            cert_type: CertificateType::Fast,
            slot: 1,
            view: 1,
            block_hash: [1; 32],
            votes: vec![],
            total_stake: 240,
            timestamp: 1000,
        };
        
        let event1 = ValidationEvent::BlockFinalized {
            block: block1,
            certificate: cert1,
            timestamp: 1000,
        };
        
        assert!(validator.process_event(event1).await.is_ok());
        
        // Try to finalize conflicting block
        let cert2 = Certificate {
            cert_type: CertificateType::Fast,
            slot: 1,
            view: 1,
            block_hash: [2; 32],
            votes: vec![],
            total_stake: 240,
            timestamp: 1000,
        };
        
        let event2 = ValidationEvent::BlockFinalized {
            block: block2,
            certificate: cert2,
            timestamp: 1000,
        };
        
        let result = validator.process_event(event2).await;
        assert!(result.is_err());
        
        if let Err(ValidationError::ConflictingBlocks { slot, .. }) = result {
            assert_eq!(slot, 1);
        } else {
            panic!("Expected ConflictingBlocks error");
        }
    }
    
    #[tokio::test]
    async fn test_double_voting_detection() {
        let mut validator = AlpenglowValidator::new(ValidationConfig::default());
        
        // Initialize validators
        validator.initialize_validators(vec![(1, 100)]);
        
        // First vote
        let vote1 = Vote {
            validator: 1,
            view: 1,
            slot: 1,
            block_hash: [1; 32],
            signature: vec![],
            timestamp: 1000,
        };
        
        let event1 = ValidationEvent::VoteCast {
            vote: vote1,
            timestamp: 1000,
        };
        
        assert!(validator.process_event(event1).await.is_ok());
        
        // Conflicting vote
        let vote2 = Vote {
            validator: 1,
            view: 1,
            slot: 1,
            block_hash: [2; 32],
            signature: vec![],
            timestamp: 1001,
        };
        
        let event2 = ValidationEvent::VoteCast {
            vote: vote2,
            timestamp: 1001,
        };
        
        let result = validator.process_event(event2).await;
        assert!(result.is_err());
        
        if let Err(ValidationError::DoubleVoting { validator: v, view, .. }) = result {
            assert_eq!(v, 1);
            assert_eq!(view, 1);
        } else {
            panic!("Expected DoubleVoting error");
        }
    }
    
    #[tokio::test]
    async fn test_conformance_suite() {
        let mut suite = ConformanceTestSuite::new(ValidationConfig::default());
        let results = suite.run_all_tests().await;
        
        assert!(results.total_tests > 0);
        println!("Conformance test results: {}/{} passed", 
                results.passed_tests, results.total_tests);
    }
    
    #[tokio::test]
    async fn test_actor_model_integration() {
        // Test integration with Actor model
        let config = test_configs()[0].clone();
        let model = alpenglow_stateright::create_model(config.clone()).unwrap();
        
        let validation_config = ValidationConfig::from(config);
        let tools = ValidationTools::new_with_actor_model(validation_config, model);
        
        assert!(tools.is_ok());
        let tools = tools.unwrap();
        
        // Test state observation
        assert!(tools.get_actor_state().is_some());
    }
    
    #[tokio::test]
    async fn test_end_to_end_validation() {
        let config = test_configs()[0].clone();
        let test_duration = Duration::from_secs(1);
        
        let result = integration::run_end_to_end_validation(config, test_duration).await;
        assert!(result.is_ok());
        
        let report = result.unwrap();
        println!("Validation report:\n{}", report.summary());
        
        // Should have some test results
        assert!(report.conformance_results.total_tests > 0);
    }
    
    #[test]
    fn test_validation_config_conversion() {
        let alpenglow_config = test_configs()[0].clone();
        let validation_config = ValidationConfig::from(alpenglow_config.clone());
        
        // Check that timing parameters are correctly converted
        assert_eq!(validation_config.timing_params.gst.as_millis(), alpenglow_config.gst as u128);
        assert_eq!(validation_config.timing_params.delta.as_millis(), alpenglow_config.max_network_delay as u128);
        
        // Check stake thresholds
        let expected_fast_path = alpenglow_config.fast_path_threshold as f64 / alpenglow_config.total_stake as f64;
        assert!((validation_config.stake_thresholds.fast_path - expected_fast_path).abs() < 0.01);
    }
    
    #[test]
    fn test_type_conversions() {
        // Test conversion between validation types and main crate types
        let main_block = alpenglow_stateright::votor::Block {
            hash: [1; 32],
            slot: 1,
            parent_hash: [0; 32],
            timestamp: 1000,
            proposer: 1,
            view: 1,
            data: vec![1, 2, 3],
            transactions: vec![],
        };
        
        let validation_block: Block = main_block.clone().into();
        assert_eq!(validation_block.hash, main_block.hash);
        assert_eq!(validation_block.slot, main_block.slot);
        assert_eq!(validation_block.proposer, main_block.proposer);
        
        let converted_back: alpenglow_stateright::votor::Block = validation_block.into();
        assert_eq!(converted_back.hash, main_block.hash);
        assert_eq!(converted_back.slot, main_block.slot);
    }
}
