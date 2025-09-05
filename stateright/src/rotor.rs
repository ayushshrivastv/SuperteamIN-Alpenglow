//! # Rotor Block Propagation Component
//!
//! This module implements the Rotor block propagation component using Stateright's actor model.
//! It provides erasure-coded data dissemination with stake-weighted relay sampling for efficient
//! bandwidth utilization, mirroring the TLA+ specification in `specs/Rotor.tla`.
//!
//! ## Key Features
//!
//! - **Erasure Coding**: Reed-Solomon encoding for fault-tolerant block propagation
//! - **Stake-Weighted Relay**: Proportional relay assignments based on validator stake
//! - **Repair Mechanisms**: Automatic repair of missing shreds with bandwidth management
//! - **Bandwidth Efficiency**: Optimal utilization within per-validator limits
//! - **Cross-Validation**: Verifiable against TLA+ model properties

use crate::{
    AlpenglowError, AlpenglowResult, BlockHash, Config, Signature, StakeAmount, ValidatorId,
    TlaCompatible, Verifiable,
};
use reed_solomon_erasure::galois_8::ReedSolomon;
use serde::{Deserialize, Serialize};
use crate::stateright::{Actor, Id};
use std::collections::{HashMap, HashSet, VecDeque};
use std::time::{Duration, Instant};

/// Shred identifier for non-equivocation tracking - mirrors TLA+ ShredId
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct ShredId {
    /// Slot number
    pub slot: u64,
    /// Shred index within the slot
    pub index: u32,
}

impl ShredId {
    /// Create a new shred ID
    pub fn new(slot: u64, index: u32) -> Self {
        Self { slot, index }
    }
}

/// Erasure-coded block shred containing a piece of the original block - mirrors TLA+ shred structure
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Hash)]
pub struct Shred {
    /// Block identifier this shred belongs to
    pub block_id: BlockHash,
    
    /// Slot number for non-equivocation tracking
    pub slot: u64,
    
    /// Shred index (1..N where N is total shreds)
    pub index: u32,
    
    /// Encoded data payload
    pub data: Vec<u8>,
    
    /// Whether this is a parity shred (true) or data shred (false)
    pub is_parity: bool,
    
    /// Cryptographic signature for integrity
    pub signature: Signature,
    
    /// Size in bytes for bandwidth calculations
    pub size: usize,
}

impl Shred {
    /// Create a new data shred
    pub fn new_data(block_id: BlockHash, slot: u64, index: u32, data: Vec<u8>) -> Self {
        let size = data.len() + 32 + 8 + 4 + 64; // data + block_id + slot + index + signature
        Self {
            block_id,
            slot,
            index,
            data,
            is_parity: false,
            signature: 0, // Placeholder signature
            size,
        }
    }
    
    /// Create a new parity shred
    pub fn new_parity(block_id: BlockHash, slot: u64, index: u32, data: Vec<u8>) -> Self {
        let size = data.len() + 32 + 8 + 4 + 64; // data + block_id + slot + index + signature
        Self {
            block_id,
            slot,
            index,
            data,
            is_parity: true,
            signature: 0, // Placeholder signature
            size,
        }
    }
    
    /// Get shred ID for non-equivocation tracking
    pub fn shred_id(&self) -> ShredId {
        ShredId::new(self.slot, self.index)
    }
    
    /// Validate shred integrity
    pub fn validate(&self) -> bool {
        // Simplified validation - in practice would verify signature
        !self.data.is_empty() && self.index > 0
    }
}

/// Block with erasure coding metadata
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Hash)]
pub struct ErasureBlock {
    /// Block hash identifier
    pub hash: BlockHash,
    
    /// Slot number
    pub slot: u64,
    
    /// View number for consensus
    pub view: u64,
    
    /// Block proposer
    pub proposer: ValidatorId,
    
    /// Parent block hash
    pub parent: BlockHash,
    
    /// Block data payload
    pub data: Vec<u8>,
    
    /// Block timestamp
    pub timestamp: u64,
    
    /// Transaction set
    pub transactions: HashSet<Vec<u8>>,
    
    /// Total number of shreds (K + parity)
    pub total_shreds: u32,
    
    /// Number of data shreds (K)
    pub data_shreds: u32,
}

impl ErasureBlock {
    /// Create a new block
    pub fn new(
        hash: BlockHash,
        slot: u64,
        proposer: ValidatorId,
        data: Vec<u8>,
        data_shreds: u32,
        total_shreds: u32,
    ) -> Self {
        Self {
            hash,
            slot,
            view: 0,
            proposer,
            parent: [0u8; 32], // Genesis parent
            data,
            timestamp: 0, // Will be set by clock
            transactions: HashSet::new(),
            total_shreds,
            data_shreds,
        }
    }
    
    /// Validate block structure
    pub fn validate(&self) -> bool {
        self.total_shreds > self.data_shreds && self.data_shreds > 0
    }
}

/// Repair request for missing shreds
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Hash)]
pub struct RepairRequest {
    /// Validator requesting repair
    pub requester: ValidatorId,
    
    /// Block being repaired
    pub block_id: BlockHash,
    
    /// Set of missing shred indices
    pub missing_pieces: HashSet<u32>,
    
    /// Request timestamp for timeout handling
    pub timestamp: u64,
    
    /// Number of retry attempts
    pub retry_count: u32,
}

/// Relay path for stake-weighted propagation
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Hash)]
pub struct RelayPath {
    /// Source validator
    pub source: ValidatorId,
    
    /// Target validators for relay
    pub targets: Vec<ValidatorId>,
    
    /// Relay weight based on stake
    pub weight: u64,
    
    /// Expected bandwidth usage
    pub bandwidth_cost: u64,
}

/// Reconstruction state for a block
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Hash)]
pub struct ReconstructionState {
    /// Block being reconstructed
    pub block_id: BlockHash,
    
    /// Collected shred indices
    pub collected_pieces: HashSet<u32>,
    
    /// Whether reconstruction is complete
    pub complete: bool,
    
    /// Reconstruction start time
    pub start_time: u64,
    
    /// Number of repair requests sent
    pub repair_requests_sent: u32,
}

/// Rotor actor state - mirrors TLA+ Rotor variables exactly
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Hash)]
pub struct RotorState {
    /// Validator ID
    pub validator_id: ValidatorId,
    
    /// Protocol configuration
    pub config: Config,
    
    /// Stored shreds by block ID and validator - mirrors TLA+ blockShreds
    pub block_shreds: HashMap<BlockHash, HashMap<ValidatorId, HashSet<Shred>>>,
    
    /// Stake-weighted relay assignments - mirrors TLA+ relayAssignments
    pub relay_assignments: HashMap<ValidatorId, Vec<u32>>,
    
    /// Block reconstruction progress - mirrors TLA+ reconstructionState
    pub reconstruction_state: HashMap<ValidatorId, Vec<ReconstructionState>>,
    
    /// Successfully delivered blocks per validator - mirrors TLA+ deliveredBlocks
    pub delivered_blocks: HashMap<ValidatorId, HashSet<BlockHash>>,
    
    /// Active repair requests - mirrors TLA+ repairRequests
    pub repair_requests: HashSet<RepairRequest>,
    
    /// Current bandwidth usage per validator - mirrors TLA+ bandwidthUsage
    pub bandwidth_usage: HashMap<ValidatorId, u64>,
    
    /// Received shreds per validator - mirrors TLA+ receivedShreds
    pub received_shreds: HashMap<ValidatorId, HashSet<Shred>>,
    
    /// Shred assignments per validator - mirrors TLA+ shredAssignments
    pub shred_assignments: HashMap<ValidatorId, HashSet<u32>>,
    
    /// Reconstructed blocks per validator - mirrors TLA+ reconstructedBlocks
    pub reconstructed_blocks: HashMap<ValidatorId, HashSet<ErasureBlock>>,
    
    /// Non-equivocation tracking: history of shreds sent by each validator - mirrors TLA+ rotorHistory
    pub rotor_history: HashMap<ValidatorId, HashMap<ShredId, Shred>>,
    
    /// Global clock for timing operations - mirrors TLA+ clock
    pub clock: u64,
    
    /// Reed-Solomon encoder/decoder
    #[serde(skip)]
    pub reed_solomon: Option<ReedSolomon>,
    
    /// Bandwidth limit per validator
    pub bandwidth_limit: u64,
    
    /// Retry timeout for repair requests
    pub retry_timeout: u64,
    
    /// Maximum retry attempts
    pub max_retries: u32,
    
    /// Load balance tolerance factor
    pub load_balance_tolerance: f64,
    
    /// Erasure coding parameters - K (data shreds)
    pub k: u32,
    
    /// Erasure coding parameters - N (total shreds)
    pub n: u32,
}

impl RotorState {
    /// Create new Rotor state
    pub fn new(validator_id: ValidatorId, config: Config) -> Self {
        let validator_count = config.validator_count;
        let bandwidth_limit = 1000000; // 1MB per validator
        
        // Use erasure coding parameters from config
        let k = config.k;
        let n = config.n;
        
        // Initialize Reed-Solomon with K data shreds and (N-K) parity shreds
        let reed_solomon = if k > 0 && n > k {
            ReedSolomon::new(k as usize, (n - k) as usize).ok()
        } else {
            None
        };
        
        Self {
            validator_id,
            config,
            block_shreds: HashMap::new(),
            relay_assignments: HashMap::new(),
            reconstruction_state: HashMap::new(),
            delivered_blocks: HashMap::new(),
            repair_requests: HashSet::new(),
            bandwidth_usage: HashMap::new(),
            received_shreds: HashMap::new(),
            shred_assignments: HashMap::new(),
            reconstructed_blocks: HashMap::new(),
            rotor_history: HashMap::new(),
            clock: 0,
            reed_solomon,
            bandwidth_limit,
            retry_timeout: 1000, // 1 second
            max_retries: 3,
            load_balance_tolerance: 0.1, // 10% tolerance
            k,
            n,
        }
    }
    
    /// Erasure encode a block into shreds - mirrors TLA+ ErasureEncode
    pub fn erasure_encode(&self, block: &ErasureBlock) -> AlpenglowResult<Vec<Shred>> {
        let k = self.k as usize;
        let n = self.n as usize;
        
        if k >= n {
            return Err(AlpenglowError::InvalidConfig(
                "Data shreds must be less than total shreds".to_string(),
            ));
        }
        
        // Validate proper partitioning as in TLA+ specification
        if k == 0 || n == 0 {
            return Err(AlpenglowError::InvalidConfig(
                "Invalid erasure coding parameters".to_string(),
            ));
        }
        
        // Split block data into K pieces
        let chunk_size = (block.data.len() + k - 1) / k; // Round up division
        let mut data_chunks = Vec::new();
        
        for i in 0..k {
            let start = i * chunk_size;
            let end = std::cmp::min(start + chunk_size, block.data.len());
            let mut chunk = block.data[start..end].to_vec();
            
            // Pad chunk to fixed size
            chunk.resize(chunk_size, 0);
            data_chunks.push(chunk);
        }
        
        // Generate parity chunks using Reed-Solomon
        let parity_count = n - k;
        let mut parity_chunks = vec![vec![0u8; chunk_size]; parity_count];
        
        if let Some(ref rs) = self.reed_solomon {
            // Use Reed-Solomon encoding
            let mut all_chunks = data_chunks.clone();
            all_chunks.append(&mut parity_chunks);
            
            if rs.encode(&mut all_chunks).is_ok() {
                parity_chunks = all_chunks[k..].to_vec();
            } else {
                return Err(AlpenglowError::ProtocolViolation(
                    "Reed-Solomon encoding failed".to_string(),
                ));
            }
        } else {
            // Fallback: simple XOR parity (for compatibility)
            for i in 0..parity_count {
                for j in 0..chunk_size {
                    let mut parity_byte = 0u8;
                    for data_chunk in &data_chunks {
                        parity_byte ^= data_chunk[j];
                    }
                    parity_chunks[i][j] = parity_byte;
                }
            }
        }
        
        // Create shreds with proper index partitioning as in TLA+
        let mut shreds = Vec::new();
        
        // Data shreds use indices 1..K (ensuring unique partitioning)
        for (i, chunk) in data_chunks.into_iter().enumerate() {
            let shred = Shred::new_data(block.hash, block.slot, (i + 1) as u32, chunk);
            shreds.push(shred);
        }
        
        // Parity shreds use indices (K+1)..N (ensuring no overlap)
        for (i, chunk) in parity_chunks.into_iter().enumerate() {
            let shred = Shred::new_parity(block.hash, block.slot, (k + i + 1) as u32, chunk);
            shreds.push(shred);
        }
        
        // Verify proper partitioning before returning (as in TLA+)
        let data_indices: HashSet<u32> = shreds.iter()
            .filter(|s| !s.is_parity)
            .map(|s| s.index)
            .collect();
        let parity_indices: HashSet<u32> = shreds.iter()
            .filter(|s| s.is_parity)
            .map(|s| s.index)
            .collect();
        
        if data_indices.iter().any(|&i| i < 1 || i > k as u32) ||
           parity_indices.iter().any(|&i| i <= k as u32 || i > n as u32) ||
           data_indices.len() + parity_indices.len() != n {
            return Err(AlpenglowError::ProtocolViolation(
                "Invalid shred index partitioning".to_string(),
            ));
        }
        
        Ok(shreds)
    }
    
    /// Reconstruct block from available shreds - mirrors TLA+ ReconstructBlock
    pub fn reconstruct_block(&self, shreds: &HashSet<Shred>) -> AlpenglowResult<ErasureBlock> {
        if shreds.is_empty() {
            return Err(AlpenglowError::ProtocolViolation(
                "No shreds available for reconstruction".to_string(),
            ));
        }
        
        let block_id = shreds.iter().next().unwrap().block_id;
        let slot = shreds.iter().next().unwrap().slot;
        let k = self.k as usize;
        
        if shreds.len() < k {
            return Err(AlpenglowError::ProtocolViolation(
                "Insufficient shreds for reconstruction".to_string(),
            ));
        }
        
        // Separate data and parity shreds as in TLA+
        let data_shreds: Vec<_> = shreds.iter().filter(|s| !s.is_parity).collect();
        let parity_shreds: Vec<_> = shreds.iter().filter(|s| s.is_parity).collect();
        let data_indices: HashSet<u32> = data_shreds.iter().map(|s| s.index).collect();
        let parity_indices: HashSet<u32> = parity_shreds.iter().map(|s| s.index).collect();
        
        // Reconstruct data following TLA+ logic
        let mut reconstructed_data = Vec::new();
        
        if data_indices.len() >= k {
            // Can reconstruct from data shreds only (RecoverFromData in TLA+)
            let mut sorted_data: Vec<_> = data_shreds.into_iter().collect();
            sorted_data.sort_by_key(|s| s.index);
            
            for shred in sorted_data.iter().take(k) {
                reconstructed_data.extend_from_slice(&shred.data);
            }
        } else if data_indices.len() + parity_indices.len() >= k {
            // Need to use parity shreds for reconstruction (RecoverWithParity in TLA+)
            if let Some(ref rs) = self.reed_solomon {
                // Use Reed-Solomon reconstruction
                let mut all_shreds: Vec<_> = shreds.iter().collect();
                all_shreds.sort_by_key(|s| s.index);
                
                // Prepare chunks for Reed-Solomon reconstruction
                let mut chunks: Vec<Option<Vec<u8>>> = vec![None; self.n as usize];
                for shred in all_shreds.iter() {
                    if (shred.index as usize) <= self.n as usize {
                        chunks[(shred.index - 1) as usize] = Some(shred.data.clone());
                    }
                }
                
                if rs.reconstruct(&mut chunks).is_ok() {
                    for chunk in chunks.into_iter().take(k) {
                        if let Some(data) = chunk {
                            reconstructed_data.extend_from_slice(&data);
                        }
                    }
                } else {
                    return Err(AlpenglowError::ProtocolViolation(
                        "Reed-Solomon reconstruction failed".to_string(),
                    ));
                }
            } else {
                // Fallback reconstruction using XOR for simple parity
                if data_indices.len() == k - 1 && parity_indices.len() >= 1 {
                    // Can recover one missing data shred using XOR
                    let mut sorted_data: Vec<_> = data_shreds.into_iter().collect();
                    sorted_data.sort_by_key(|s| s.index);
                    
                    for shred in sorted_data.iter() {
                        reconstructed_data.extend_from_slice(&shred.data);
                    }
                    
                    // Find missing data shred and recover using parity
                    let missing_index = (1..=k as u32).find(|i| !data_indices.contains(i));
                    if let Some(_missing) = missing_index {
                        if let Some(parity_shred) = parity_shreds.first() {
                            // Simple XOR recovery (simplified)
                            let mut recovered_chunk = parity_shred.data.clone();
                            for data_shred in &sorted_data {
                                for (i, &byte) in data_shred.data.iter().enumerate() {
                                    if i < recovered_chunk.len() {
                                        recovered_chunk[i] ^= byte;
                                    }
                                }
                            }
                            reconstructed_data.extend_from_slice(&recovered_chunk);
                        }
                    }
                } else {
                    return Err(AlpenglowError::ProtocolViolation(
                        "Cannot reconstruct without Reed-Solomon".to_string(),
                    ));
                }
            }
        } else {
            return Err(AlpenglowError::ProtocolViolation(
                "Insufficient shreds for reconstruction".to_string(),
            ));
        }
        
        // Remove padding and create block
        let block = ErasureBlock {
            hash: block_id,
            slot,
            view: 0, // Will be set from metadata
            proposer: 0, // Will be determined from context
            parent: [0u8; 32],
            data: reconstructed_data,
            timestamp: self.clock,
            transactions: HashSet::new(),
            total_shreds: self.n,
            data_shreds: self.k,
        };
        
        Ok(block)
    }
    
    /// Assign shreds to validators based on stake weights - mirrors TLA+ AssignPiecesToRelays
    pub fn assign_pieces_to_relays(&self, validators: &[ValidatorId], num_pieces: u32) -> HashMap<ValidatorId, HashSet<u32>> {
        let mut assignments = HashMap::new();
        
        // Calculate total stake - mirrors TLA+ SumStake
        let total_stake: StakeAmount = validators
            .iter()
            .map(|v| self.config.stake_distribution.get(v).unwrap_or(&0))
            .sum();
        
        if total_stake == 0 {
            // Equal distribution if no stake info
            let pieces_per_validator = (num_pieces + validators.len() as u32 - 1) / validators.len() as u32;
            for (i, &validator) in validators.iter().enumerate() {
                let start = i as u32 * pieces_per_validator;
                let end = std::cmp::min(start + pieces_per_validator, num_pieces);
                let pieces: HashSet<u32> = (start + 1..=end).collect();
                assignments.insert(validator, pieces);
            }
        } else {
            // Stake-weighted distribution as in TLA+ specification
            let mut assigned_pieces = 0;
            for &validator in validators {
                let stake = self.config.stake_distribution.get(&validator).unwrap_or(&0);
                // piecesPerValidator(v) = (Stake[v] * numPieces) \div totalStake + 1
                let pieces_for_validator = ((*stake as u64 * num_pieces as u64) / total_stake as u64) + 1;
                let pieces_for_validator = std::cmp::min(pieces_for_validator as u32, num_pieces - assigned_pieces);
                
                // RandomSubset(piecesPerValidator(v), 1..numPieces) in TLA+
                let pieces: HashSet<u32> = (assigned_pieces + 1..=assigned_pieces + pieces_for_validator).collect();
                assignments.insert(validator, pieces);
                assigned_pieces += pieces_for_validator;
                
                if assigned_pieces >= num_pieces {
                    break;
                }
            }
        }
        
        assignments
    }
    
    /// Check if validator can reconstruct a block - mirrors TLA+ CanReconstruct
    pub fn can_reconstruct(&self, validator: ValidatorId, block_id: &BlockHash) -> bool {
        if let Some(validator_shreds) = self.block_shreds.get(block_id).and_then(|bs| bs.get(&validator)) {
            validator_shreds.len() >= self.k as usize
        } else {
            false
        }
    }
    
    /// Check if validator has already sent a shred with this ID - mirrors TLA+ HasSentShred
    pub fn has_sent_shred(&self, validator: ValidatorId, shred_id: &ShredId) -> bool {
        self.rotor_history
            .get(&validator)
            .map_or(false, |history| history.contains_key(shred_id))
    }
    
    /// Get the shred previously sent by validator for this ID - mirrors TLA+ GetSentShred
    pub fn get_sent_shred(&self, validator: ValidatorId, shred_id: &ShredId) -> Option<&Shred> {
        self.rotor_history
            .get(&validator)
            .and_then(|history| history.get(shred_id))
    }
    
    /// Record that validator sent a shred with given ID - mirrors TLA+ RecordShredSent
    pub fn record_shred_sent(&mut self, validator: ValidatorId, shred_id: ShredId, shred: Shred) {
        self.rotor_history
            .entry(validator)
            .or_insert_with(HashMap::new)
            .insert(shred_id, shred);
    }
    
    /// Check non-equivocation for a set of shreds - mirrors TLA+ RotorNonEquivocation
    pub fn check_non_equivocation(&self, validator: ValidatorId, shreds: &HashSet<Shred>) -> bool {
        for shred in shreds {
            let shred_id = shred.shred_id();
            if let Some(existing_shred) = self.get_sent_shred(validator, &shred_id) {
                if existing_shred != shred {
                    return false; // Equivocation detected
                }
            }
        }
        true
    }
    
    /// Compute bandwidth usage for shreds
    pub fn compute_bandwidth(&self, shreds: &HashSet<Shred>) -> u64 {
        shreds.iter().map(|s| s.size as u64).sum()
    }
    
    /// Compute repair bandwidth
    pub fn compute_repair_bandwidth(&self, requests: &HashSet<RepairRequest>) -> u64 {
        requests.len() as u64 * 50 // 50 bytes per repair request
    }
    
    /// Select relay targets based on stake weights - mirrors TLA+ SelectRelayTargets
    pub fn select_relay_targets(&self, validator: ValidatorId, _shred: &Shred) -> Vec<ValidatorId> {
        // Stake-weighted sampling for relay targets as in TLA+
        let total_stake = self.config.total_stake;
        let relay_count = std::cmp::min(self.config.validator_count / 3, 10);
        let mut targets = Vec::new();
        
        // Select validators with highest stake (excluding self) - PS-P sampling scheme
        let mut validators_by_stake: Vec<_> = self.config.stake_distribution
            .iter()
            .filter(|(&v, _)| v != validator)
            .filter(|(_, &stake)| stake > 0) // Only relay to staked validators
            .collect();
        validators_by_stake.sort_by_key(|(_, &stake)| std::cmp::Reverse(stake));
        
        // Implement PS-P (Probability Sampling with Proportional to size) sampling
        for (&target, &stake) in validators_by_stake.iter().take(relay_count) {
            // Include validator if stake weight is above threshold
            let relay_weight = (stake * 1000) / total_stake; // Scale for threshold comparison
            if relay_weight > 100 { // Threshold for relay inclusion
                targets.push(target);
            }
        }
        
        // Ensure minimum relay count for connectivity
        if targets.len() < relay_count && validators_by_stake.len() >= relay_count {
            for (&target, _) in validators_by_stake.iter().take(relay_count) {
                if !targets.contains(&target) {
                    targets.push(target);
                    if targets.len() >= relay_count {
                        break;
                    }
                }
            }
        }
        
        targets
    }
    
    /// Validate block integrity
    pub fn validate_block_integrity(&self, block: &ErasureBlock) -> bool {
        block.validate() && !block.data.is_empty()
    }
    
    /// Check bandwidth limits
    pub fn check_bandwidth_limit(&self, validator: ValidatorId, additional_usage: u64) -> bool {
        let current_usage = self.bandwidth_usage.get(&validator).unwrap_or(&0);
        current_usage + additional_usage <= self.bandwidth_limit
    }
    
    /// Update bandwidth usage
    pub fn update_bandwidth_usage(&mut self, validator: ValidatorId, usage: u64) {
        *self.bandwidth_usage.entry(validator).or_insert(0) += usage;
    }
    
    /// Advance clock
    pub fn advance_clock(&mut self) {
        self.clock += 1;
    }
    
    /// Get honest validators (non-Byzantine)
    pub fn honest_validators(&self) -> Vec<ValidatorId> {
        (0..self.config.validator_count as ValidatorId)
            .filter(|&v| {
                // In practice, would check Byzantine validator set
                // For now, assume all validators are honest
                true
            })
            .collect()
    }
}

/// Messages for Rotor actor communication
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Hash)]
pub enum RotorMessage {
    /// Shred and distribute a new block
    ShredAndDistribute {
        leader: ValidatorId,
        block: ErasureBlock,
    },
    
    /// Relay shreds to other validators
    RelayShreds {
        validator: ValidatorId,
        block_id: BlockHash,
        shreds: Vec<Shred>,
    },
    
    /// Attempt block reconstruction
    AttemptReconstruction {
        validator: ValidatorId,
        block_id: BlockHash,
    },
    
    /// Request repair for missing pieces
    RequestRepair {
        validator: ValidatorId,
        block_id: BlockHash,
        missing_pieces: HashSet<u32>,
    },
    
    /// Respond to repair request
    RespondToRepair {
        validator: ValidatorId,
        request: RepairRequest,
        shreds: Vec<Shred>,
    },
    
    /// Clock tick for timing operations
    ClockTick,
}

/// Rotor actor implementing block propagation
#[derive(Debug, Clone)]
pub struct RotorActor {
    /// Actor configuration
    pub config: Config,
}

impl RotorActor {
    /// Create new Rotor actor
    pub fn new(config: Config) -> Self {
        Self { config }
    }
}

impl Actor for RotorActor {
    type Msg = RotorMessage;
    type State = RotorState;
    
    fn on_start(&self, id: Id, o: &mut crate::stateright::util::Out<Self>) -> Self::State {
        let validator_id = id.into();
        let mut state = RotorState::new(validator_id, self.config.clone());
        
        // Initialize bandwidth usage for all validators
        for i in 0..self.config.validator_count {
            state.bandwidth_usage.insert(i as ValidatorId, 0);
            state.delivered_blocks.insert(i as ValidatorId, HashSet::new());
            state.received_shreds.insert(i as ValidatorId, HashSet::new());
            state.shred_assignments.insert(i as ValidatorId, HashSet::new());
            state.reconstructed_blocks.insert(i as ValidatorId, HashSet::new());
            state.reconstruction_state.insert(i as ValidatorId, Vec::new());
        }
        
        // Schedule periodic clock ticks
        o.send(id, RotorMessage::ClockTick);
        
        state
    }
    
    fn on_msg(&self, id: Id, state: &mut Self::State, _src: Id, msg: Self::Msg, o: &mut crate::stateright::util::Out<Self>) {
        let validator_id = id as ValidatorId;
        
        match msg {
            RotorMessage::ShredAndDistribute { leader, block } => {
                if leader == validator_id && leader == block.proposer {
                    // Only the leader can shred and distribute - mirrors TLA+ ShredAndDistribute
                    if !state.block_shreds.contains_key(&block.hash) {
                        match state.erasure_encode(&block) {
                            Ok(shreds) => {
                                let validators: Vec<ValidatorId> = (0..state.config.validator_count as ValidatorId).collect();
                                let assignments = state.assign_pieces_to_relays(&validators, state.n);
                                
                                // Check non-equivocation: ensure leader hasn't sent different shreds for same slot/index
                                let leader_shreds: HashSet<Shred> = shreds
                                    .iter()
                                    .filter(|s| assignments.get(&leader).unwrap_or(&HashSet::new()).contains(&s.index))
                                    .cloned()
                                    .collect();
                                
                                if !state.check_non_equivocation(leader, &leader_shreds) {
                                    // Non-equivocation violation detected, reject this action
                                    return;
                                }
                                
                                // Store shreds according to assignments
                                let mut block_shred_map = HashMap::new();
                                for validator in &validators {
                                    let assigned_indices = assignments.get(validator).unwrap_or(&HashSet::new());
                                    let validator_shreds: HashSet<Shred> = shreds
                                        .iter()
                                        .filter(|s| assigned_indices.contains(&s.index))
                                        .cloned()
                                        .collect();
                                    block_shred_map.insert(*validator, validator_shreds);
                                }
                                
                                state.block_shreds.insert(block.hash, block_shred_map);
                                state.relay_assignments = assignments.into_iter()
                                    .map(|(v, indices)| (v, indices.into_iter().collect()))
                                    .collect();
                                
                                // Update shred assignments for leader
                                if let Some(leader_assignment) = state.relay_assignments.get(&leader) {
                                    state.shred_assignments.insert(leader, leader_assignment.iter().cloned().collect());
                                }
                                
                                // Record shreds sent by leader for non-equivocation tracking
                                for shred in &leader_shreds {
                                    let shred_id = shred.shred_id();
                                    state.record_shred_sent(leader, shred_id, shred.clone());
                                }
                                
                                state.advance_clock();
                                
                                // Trigger relay for assigned shreds
                                o.send(id, RotorMessage::RelayShreds {
                                    validator: validator_id,
                                    block_id: block.hash,
                                    shreds: Vec::new(), // Will be populated in relay logic
                                });
                            }
                            Err(_) => {
                                // Encoding failed, skip this block
                            }
                        }
                    }
                }
            }
            
            RotorMessage::RelayShreds { validator, block_id, .. } => {
                if validator == validator_id {
                    if let Some(block_shreds) = state.block_shreds.get(&block_id) {
                        if let Some(my_shreds) = block_shreds.get(&validator_id) {
                            if !my_shreds.is_empty() {
                                let bandwidth_needed = state.compute_bandwidth(my_shreds);
                                
                                // Check non-equivocation for relay - mirrors TLA+ RelayShreds
                                if !state.check_non_equivocation(validator_id, my_shreds) {
                                    // Non-equivocation violation detected, reject this action
                                    return;
                                }
                                
                                if state.check_bandwidth_limit(validator_id, bandwidth_needed) {
                                    // Select relay targets using PS-P sampling
                                    let targets = state.select_relay_targets(validator_id, &my_shreds.iter().next().unwrap());
                                    
                                    // Send shreds to targets
                                    for target in targets {
                                        if target != validator_id {
                                            let target_id = Id::from(target);
                                            let shreds_vec: Vec<Shred> = my_shreds.iter().cloned().collect();
                                            o.send(target_id, RotorMessage::RelayShreds {
                                                validator: target,
                                                block_id,
                                                shreds: shreds_vec,
                                            });
                                        }
                                    }
                                    
                                    // Record shreds sent for non-equivocation tracking
                                    for shred in my_shreds {
                                        let shred_id = shred.shred_id();
                                        state.record_shred_sent(validator_id, shred_id, shred.clone());
                                    }
                                    
                                    state.update_bandwidth_usage(validator_id, bandwidth_needed);
                                    state.advance_clock();
                                }
                            }
                        }
                    }
                }
            }
            
            RotorMessage::AttemptReconstruction { validator, block_id } => {
                if validator == validator_id {
                    if !state.delivered_blocks.get(&validator_id).unwrap_or(&HashSet::new()).contains(&block_id) {
                        if state.can_reconstruct(validator_id, &block_id) {
                            if let Some(block_shreds) = state.block_shreds.get(&block_id) {
                                if let Some(my_shreds) = block_shreds.get(&validator_id) {
                                    match state.reconstruct_block(my_shreds) {
                                        Ok(block) => {
                                            // Successful reconstruction
                                            let reconstruction_state = ReconstructionState {
                                                block_id,
                                                collected_pieces: my_shreds.iter().map(|s| s.index).collect(),
                                                complete: true,
                                                start_time: state.clock,
                                                repair_requests_sent: 0,
                                            };
                                            
                                            state.reconstruction_state
                                                .entry(validator_id)
                                                .or_insert_with(Vec::new)
                                                .push(reconstruction_state);
                                            
                                            state.delivered_blocks
                                                .entry(validator_id)
                                                .or_insert_with(HashSet::new)
                                                .insert(block_id);
                                            
                                            state.reconstructed_blocks
                                                .entry(validator_id)
                                                .or_insert_with(HashSet::new)
                                                .insert(block);
                                            
                                            state.advance_clock();
                                        }
                                        Err(_) => {
                                            // Reconstruction failed, might need repair
                                            o.send(id, RotorMessage::RequestRepair {
                                                validator: validator_id,
                                                block_id,
                                                missing_pieces: HashSet::new(), // Will be computed
                                            });
                                        }
                                    }
                                }
                            }
                        } else {
                            // Cannot reconstruct, request repair
                            o.send(id, RotorMessage::RequestRepair {
                                validator: validator_id,
                                block_id,
                                missing_pieces: HashSet::new(), // Will be computed
                            });
                        }
                    }
                }
            }
            
            RotorMessage::RequestRepair { validator, block_id, .. } => {
                if validator == validator_id {
                    if !state.can_reconstruct(validator_id, &block_id) {
                        if !state.delivered_blocks.get(&validator_id).unwrap_or(&HashSet::new()).contains(&block_id) {
                            // Compute missing pieces
                            let k = state.get_data_shred_count(&block_id);
                            let current_pieces: HashSet<u32> = state.block_shreds
                                .get(&block_id)
                                .and_then(|bs| bs.get(&validator_id))
                                .map(|shreds| shreds.iter().map(|s| s.index).collect())
                                .unwrap_or_default();
                            
                            let needed_pieces: HashSet<u32> = (1..=k as u32)
                                .filter(|i| !current_pieces.contains(i))
                                .collect();
                            
                            if !needed_pieces.is_empty() {
                                let repair_bandwidth = state.compute_repair_bandwidth(&HashSet::new()) + 50; // Base cost
                                
                                if state.check_bandwidth_limit(validator_id, repair_bandwidth) {
                                    let repair_request = RepairRequest {
                                        requester: validator_id,
                                        block_id,
                                        missing_pieces: needed_pieces,
                                        timestamp: state.clock,
                                        retry_count: 0,
                                    };
                                    
                                    state.repair_requests.insert(repair_request.clone());
                                    state.update_bandwidth_usage(validator_id, repair_bandwidth);
                                    state.advance_clock();
                                    
                                    // Broadcast repair request to other validators
                                    for i in 0..state.config.validator_count {
                                        let target_id = Id::from(i as ValidatorId);
                                        if target_id != id {
                                            o.send(target_id, RotorMessage::RespondToRepair {
                                                validator: i as ValidatorId,
                                                request: repair_request.clone(),
                                                shreds: Vec::new(),
                                            });
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            RotorMessage::RespondToRepair { validator, request, .. } => {
                if validator == validator_id && state.repair_requests.contains(&request) {
                    if let Some(block_shreds) = state.block_shreds.get(&request.block_id) {
                        if let Some(my_shreds) = block_shreds.get(&validator_id) {
                            let requested_shreds: Vec<Shred> = my_shreds
                                .iter()
                                .filter(|s| request.missing_pieces.contains(&s.index))
                                .cloned()
                                .collect();
                            
                            if !requested_shreds.is_empty() {
                                let response_bandwidth = requested_shreds.iter().map(|s| s.size as u64).sum();
                                
                                if state.check_bandwidth_limit(validator_id, response_bandwidth) {
                                    // Send shreds to requester
                                    if let Some(requester_shreds) = state.block_shreds
                                        .get_mut(&request.block_id)
                                        .and_then(|bs| bs.get_mut(&request.requester))
                                    {
                                        for shred in &requested_shreds {
                                            requester_shreds.insert(shred.clone());
                                        }
                                    }
                                    
                                    state.repair_requests.remove(&request);
                                    state.update_bandwidth_usage(validator_id, response_bandwidth);
                                    state.advance_clock();
                                    
                                    // Notify requester to attempt reconstruction
                                    let requester_id = Id::from(request.requester);
                                    o.send(requester_id, RotorMessage::AttemptReconstruction {
                                        validator: request.requester,
                                        block_id: request.block_id,
                                    });
                                }
                            }
                        }
                    }
                }
            }
            
            RotorMessage::ClockTick => {
                state.advance_clock();
                
                // Schedule next clock tick
                o.send(id, RotorMessage::ClockTick);
                
                // Trigger periodic operations
                // Check for blocks that need reconstruction
                for block_id in state.block_shreds.keys().cloned().collect::<Vec<_>>() {
                    if !state.delivered_blocks.get(&validator_id).unwrap_or(&HashSet::new()).contains(&block_id) {
                        o.send(id, RotorMessage::AttemptReconstruction {
                            validator: validator_id,
                            block_id,
                        });
                    }
                }
            }
        }
    }
}

impl Verifiable for RotorState {
    fn verify_safety(&self) -> AlpenglowResult<()> {
        // Rotor non-equivocation: no validator sends two different shreds with the same ID
        // Mirrors TLA+ RotorNonEquivocation invariant
        for (&validator, history) in &self.rotor_history {
            for (shred_id, sent_shred) in history {
                // Check all shreds in block_shreds for this validator
                for block_shreds in self.block_shreds.values() {
                    if let Some(validator_shreds) = block_shreds.get(&validator) {
                        for other_shred in validator_shreds {
                            let other_shred_id = other_shred.shred_id();
                            if other_shred_id == *shred_id && other_shred != sent_shred {
                                return Err(AlpenglowError::ProtocolViolation(
                                    format!("Non-equivocation violation: validator {} sent different shreds with same ID {:?}", validator, shred_id),
                                ));
                            }
                        }
                    }
                }
            }
        }
        
        // Bandwidth safety: All validators respect bandwidth limits
        for (&validator, &usage) in &self.bandwidth_usage {
            if usage > self.bandwidth_limit {
                return Err(AlpenglowError::ProtocolViolation(
                    format!("Validator {} exceeded bandwidth limit", validator),
                ));
            }
        }
        
        // Reconstruction correctness: All reconstructed blocks are valid
        for blocks in self.reconstructed_blocks.values() {
            for block in blocks {
                if !self.validate_block_integrity(block) {
                    return Err(AlpenglowError::ProtocolViolation(
                        "Invalid reconstructed block".to_string(),
                    ));
                }
            }
        }
        
        // Distinct indices: No duplicate shred indices per block - mirrors TLA+ DistinctIndices
        for block_shreds in self.block_shreds.values() {
            for validator_shreds in block_shreds.values() {
                let indices: HashSet<u32> = validator_shreds.iter().map(|s| s.index).collect();
                if indices.len() != validator_shreds.len() {
                    return Err(AlpenglowError::ProtocolViolation(
                        "Duplicate shred indices detected".to_string(),
                    ));
                }
            }
        }
        
        // Valid erasure code: ensures proper K/N partitioning - mirrors TLA+ ValidErasureCode
        for block_shreds in self.block_shreds.values() {
            for validator_shreds in block_shreds.values() {
                let data_shreds: Vec<_> = validator_shreds.iter().filter(|s| !s.is_parity).collect();
                let parity_shreds: Vec<_> = validator_shreds.iter().filter(|s| s.is_parity).collect();
                let data_indices: HashSet<u32> = data_shreds.iter().map(|s| s.index).collect();
                let parity_indices: HashSet<u32> = parity_shreds.iter().map(|s| s.index).collect();
                
                // Check proper partitioning
                if data_indices.iter().any(|&i| i < 1 || i > self.k) ||
                   parity_indices.iter().any(|&i| i <= self.k || i > self.n) ||
                   !data_indices.is_disjoint(&parity_indices) {
                    return Err(AlpenglowError::ProtocolViolation(
                        "Invalid erasure code partitioning".to_string(),
                    ));
                }
            }
        }
        
        Ok(())
    }
    
    fn verify_liveness(&self) -> AlpenglowResult<()> {
        // Block delivery guarantee: All honest validators eventually receive blocks
        let honest_validators = self.honest_validators();
        for block_id in self.block_shreds.keys() {
            let mut delivered_count = 0;
            for &validator in &honest_validators {
                if self.delivered_blocks.get(&validator).unwrap_or(&HashSet::new()).contains(block_id) {
                    delivered_count += 1;
                }
            }
            
            // In practice, would check eventual delivery with timeout
            // For now, just verify that some progress is made
            if delivered_count == 0 && self.clock > 100 {
                return Err(AlpenglowError::ProtocolViolation(
                    "No block delivery progress".to_string(),
                ));
            }
        }
        
        // Repair completion: All repair requests are eventually processed
        for request in &self.repair_requests {
            if self.clock - request.timestamp > self.retry_timeout * (self.max_retries as u64) {
                return Err(AlpenglowError::ProtocolViolation(
                    "Repair request timeout".to_string(),
                ));
            }
        }
        
        Ok(())
    }
    
    fn verify_byzantine_resilience(&self) -> AlpenglowResult<()> {
        // Progress with failures: Protocol makes progress even with some failed validators
        let total_validators = self.config.validator_count;
        let failed_validators = self.bandwidth_usage
            .iter()
            .filter(|(_, &usage)| usage == 0)
            .count();
        
        if failed_validators >= total_validators / 3 {
            // Too many failures, but check if remaining validators can still make progress
            let active_validators = total_validators - failed_validators;
            if active_validators < (total_validators * 2) / 3 {
                return Err(AlpenglowError::ProtocolViolation(
                    "Too many validator failures for Byzantine resilience".to_string(),
                ));
            }
        }
        
        Ok(())
    }
}

impl TlaCompatible for RotorState {
    fn export_tla_state(&self) -> serde_json::Value {
        // Export state in format compatible with TLA+ cross-validation
        let rotor_history_json: HashMap<String, HashMap<String, serde_json::Value>> = self.rotor_history
            .iter()
            .map(|(&validator, history)| {
                let history_json: HashMap<String, serde_json::Value> = history
                    .iter()
                    .map(|(shred_id, shred)| {
                        let key = format!("slot_{}_index_{}", shred_id.slot, shred_id.index);
                        let value = serde_json::json!({
                            "block_id": format!("{:?}", shred.block_id),
                            "slot": shred.slot,
                            "index": shred.index,
                            "is_parity": shred.is_parity,
                            "size": shred.size
                        });
                        (key, value)
                    })
                    .collect();
                (validator.to_string(), history_json)
            })
            .collect();
        
        serde_json::json!({
            "validator_id": self.validator_id,
            "clock": self.clock,
            "delivered_blocks": self.delivered_blocks,
            "bandwidth_usage": self.bandwidth_usage,
            "repair_requests_count": self.repair_requests.len(),
            "reconstructed_blocks_count": self.reconstructed_blocks.values().map(|s| s.len()).sum::<usize>(),
            "rotor_history": rotor_history_json,
            "k": self.k,
            "n": self.n,
            "block_shreds_count": self.block_shreds.len(),
            "relay_assignments": self.relay_assignments,
        })
    }
    
    fn import_tla_state(&mut self, state: serde_json::Value) -> AlpenglowResult<()> {
        if let Some(clock) = state.get("clock").and_then(|v| v.as_u64()) {
            self.clock = clock;
        }
        
        if let Some(k) = state.get("k").and_then(|v| v.as_u64()) {
            self.k = k as u32;
        }
        
        if let Some(n) = state.get("n").and_then(|v| v.as_u64()) {
            self.n = n as u32;
        }
        
        // Import rotor_history for cross-validation
        if let Some(history_json) = state.get("rotor_history").and_then(|v| v.as_object()) {
            self.rotor_history.clear();
            for (validator_str, validator_history) in history_json {
                if let Ok(validator_id) = validator_str.parse::<ValidatorId>() {
                    let mut history = HashMap::new();
                    if let Some(validator_history_obj) = validator_history.as_object() {
                        for (shred_id_str, shred_json) in validator_history_obj {
                            // Parse shred_id from "slot_X_index_Y" format
                            if let Some(captures) = shred_id_str.strip_prefix("slot_") {
                                if let Some(index_pos) = captures.find("_index_") {
                                    let slot_str = &captures[..index_pos];
                                    let index_str = &captures[index_pos + 7..];
                                    if let (Ok(slot), Ok(index)) = (slot_str.parse::<u64>(), index_str.parse::<u32>()) {
                                        let shred_id = ShredId::new(slot, index);
                                        // Create placeholder shred for cross-validation
                                        let shred = Shred::new_data([0u8; 32], slot, index, vec![]);
                                        history.insert(shred_id, shred);
                                    }
                                }
                            }
                        }
                    }
                    self.rotor_history.insert(validator_id, history);
                }
            }
        }
        
        Ok(())
    }
    
    fn validate_tla_invariants(&self) -> AlpenglowResult<()> {
        // Validate key invariants that should match TLA+ specification
        self.verify_safety()?;
        self.verify_liveness()?;
        self.verify_byzantine_resilience()?;
        
        // Additional TLA+ specific invariants
        
        // TypeInvariant checks
        for (&validator, history) in &self.rotor_history {
            if validator >= self.config.validator_count as ValidatorId {
                return Err(AlpenglowError::ProtocolViolation(
                    "Invalid validator ID in rotor history".to_string(),
                ));
            }
            
            for (shred_id, shred) in history {
                if shred_id.slot != shred.slot || shred_id.index != shred.index {
                    return Err(AlpenglowError::ProtocolViolation(
                        "Inconsistent shred ID and shred data".to_string(),
                    ));
                }
            }
        }
        
        // Clock must be non-negative
        if self.clock < 0 {
            return Err(AlpenglowError::ProtocolViolation(
                "Invalid clock value".to_string(),
            ));
        }
        
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_erasure_encoding() {
        let config = Config::new().with_validators(4).with_erasure_coding(2, 3);
        let state = RotorState::new(0, config);
        
        let block = ErasureBlock::new(
            [1u8; 32],
            1,
            0,
            vec![1, 2, 3, 4, 5, 6, 7, 8],
            2,
            3,
        );
        
        let shreds = state.erasure_encode(&block).unwrap();
        assert_eq!(shreds.len(), 3);
        
        // Check data shreds (indices 1..K)
        let data_shreds: Vec<_> = shreds.iter().filter(|s| !s.is_parity).collect();
        assert_eq!(data_shreds.len(), 2);
        assert!(data_shreds.iter().all(|s| s.index >= 1 && s.index <= 2));
        
        // Check parity shreds (indices K+1..N)
        let parity_shreds: Vec<_> = shreds.iter().filter(|s| s.is_parity).collect();
        assert_eq!(parity_shreds.len(), 1);
        assert!(parity_shreds.iter().all(|s| s.index > 2 && s.index <= 3));
        
        // Verify proper partitioning
        let data_indices: HashSet<u32> = data_shreds.iter().map(|s| s.index).collect();
        let parity_indices: HashSet<u32> = parity_shreds.iter().map(|s| s.index).collect();
        assert!(data_indices.is_disjoint(&parity_indices));
    }
    
    #[test]
    fn test_block_reconstruction() {
        let config = Config::new().with_validators(4).with_erasure_coding(2, 3);
        let state = RotorState::new(0, config);
        
        let block = ErasureBlock::new(
            [1u8; 32],
            1,
            0,
            vec![1, 2, 3, 4, 5, 6, 7, 8],
            2,
            3,
        );
        
        let shreds = state.erasure_encode(&block).unwrap();
        let shred_set: HashSet<Shred> = shreds.into_iter().collect();
        
        let reconstructed = state.reconstruct_block(&shred_set).unwrap();
        assert_eq!(reconstructed.hash, block.hash);
        assert_eq!(reconstructed.slot, block.slot);
    }
    
    #[test]
    fn test_stake_weighted_assignment() {
        let config = Config::new().with_validators(3);
        let state = RotorState::new(0, config);
        
        let validators = vec![0, 1, 2];
        let assignments = state.assign_pieces_to_relays(&validators, 6);
        
        assert_eq!(assignments.len(), 3);
        for assignment in assignments.values() {
            assert!(!assignment.is_empty());
        }
    }
    
    #[test]
    fn test_bandwidth_limits() {
        let config = Config::new().with_validators(3);
        let mut state = RotorState::new(0, config);
        
        assert!(state.check_bandwidth_limit(0, 500000));
        state.update_bandwidth_usage(0, 500000);
        assert!(state.check_bandwidth_limit(0, 500000));
        assert!(!state.check_bandwidth_limit(0, 500001));
    }
    
    #[test]
    fn test_non_equivocation_tracking() {
        let config = Config::new().with_validators(3).with_erasure_coding(2, 3);
        let mut state = RotorState::new(0, config);
        
        let shred_id = ShredId::new(1, 1);
        let shred1 = Shred::new_data([1u8; 32], 1, 1, vec![1, 2, 3]);
        let shred2 = Shred::new_data([2u8; 32], 1, 1, vec![4, 5, 6]); // Different data, same ID
        
        // Record first shred
        state.record_shred_sent(0, shred_id.clone(), shred1.clone());
        assert!(state.has_sent_shred(0, &shred_id));
        assert_eq!(state.get_sent_shred(0, &shred_id), Some(&shred1));
        
        // Check non-equivocation with same shred (should pass)
        let same_shreds = [shred1.clone()].iter().cloned().collect();
        assert!(state.check_non_equivocation(0, &same_shreds));
        
        // Check non-equivocation with different shred (should fail)
        let different_shreds = [shred2].iter().cloned().collect();
        assert!(!state.check_non_equivocation(0, &different_shreds));
    }
    
    #[test]
    fn test_safety_verification() {
        let config = Config::new().with_validators(3).with_erasure_coding(2, 3);
        let state = RotorState::new(0, config);
        
        assert!(state.verify_safety().is_ok());
    }
    
    #[test]
    fn test_tla_compatibility() {
        let config = Config::new().with_validators(3).with_erasure_coding(2, 3);
        let mut state = RotorState::new(0, config);
        
        // Add some test data
        let shred_id = ShredId::new(1, 1);
        let shred = Shred::new_data([1u8; 32], 1, 1, vec![1, 2, 3]);
        state.record_shred_sent(0, shred_id, shred);
        
        let exported = state.export_tla_state();
        assert!(exported.get("validator_id").is_some());
        assert!(exported.get("clock").is_some());
        assert!(exported.get("rotor_history").is_some());
        assert!(exported.get("k").is_some());
        assert!(exported.get("n").is_some());
        
        // Test import
        let mut new_state = RotorState::new(1, Config::new().with_validators(3).with_erasure_coding(2, 3));
        assert!(new_state.import_tla_state(exported).is_ok());
        
        assert!(state.validate_tla_invariants().is_ok());
    }
    
    #[test]
    fn test_ps_p_sampling() {
        let config = Config::new().with_validators(5).with_erasure_coding(3, 5);
        let state = RotorState::new(0, config);
        
        let shred = Shred::new_data([1u8; 32], 1, 1, vec![1, 2, 3]);
        let targets = state.select_relay_targets(0, &shred);
        
        // Should select some targets based on stake weights
        assert!(!targets.is_empty());
        assert!(!targets.contains(&0)); // Should not include self
        
        // All targets should be valid validator IDs
        for target in targets {
            assert!(target < state.config.validator_count as ValidatorId);
        }
    }
}
