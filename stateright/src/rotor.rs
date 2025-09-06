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
use std::collections::{HashMap, HashSet};
use std::hash::{Hash, Hasher};
use serde::{Deserialize, Serialize};
use crate::stateright::{Actor, Id};

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
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
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
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
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
    pub transactions: Vec<Vec<u8>>,
    
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
            view: 2u64,
            proposer,
            parent: 0, // Genesis parent
            data,
            timestamp: 0, // Will be set by clock
            transactions: Vec::new(),
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
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct RepairRequest {
    /// Validator requesting repair
    pub requester: ValidatorId,
    
    /// Block being repaired
    pub block_id: BlockHash,
    
    /// Set of missing shred indices
    pub missing_pieces: Vec<u32>,
    
    /// Request timestamp for timeout handling
    pub timestamp: u64,
    
    /// Number of retry attempts
    pub retry_count: u32,
}

/// Relay path for stake-weighted propagation
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RepairState {
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
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
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
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
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

impl Hash for RotorState {
    fn hash<H: Hasher>(&self, state: &mut H) {
        // Hash only the key identifying fields to avoid issues with collections
        self.validator_id.hash(state);
        self.clock.hash(state);
        self.bandwidth_limit.hash(state);
        self.retry_timeout.hash(state);
        self.max_retries.hash(state);
        self.k.hash(state);
        self.n.hash(state);
    }
}

impl RotorState {
    /// Create new Rotor state
    pub fn new(validator_id: ValidatorId, config: Config) -> Self {
        let _validator_count = config.validator_count;
        let bandwidth_limit = config.bandwidth_limit;
        
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
            config: config.clone(),
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
        let data_chunks_count = data_chunks.len();
        for (i, chunk) in data_chunks.into_iter().enumerate() {
            let shred = Shred::new_data(block.hash, block.slot, (i + 1) as u32, chunk);
            shreds.push(shred);
        }
        
        // Parity shreds use indices (K+1)..N (ensuring no overlap)
        for (i, chunk) in parity_chunks.into_iter().enumerate() {
            let shred = Shred::new_parity(block.hash, block.slot, (i + data_chunks_count + 1) as u32, chunk);
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
            view: 2u64, // Will be set from metadata
            proposer: 0, // Will be determined from context
            parent: 0,
            data: reconstructed_data,
            timestamp: self.clock,
            transactions: Vec::new(),
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
            .map(|_v| self.config.stake_distribution.get(_v).unwrap_or(&0))
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
            .filter(|&_v| {
                // In practice, would check Byzantine validator set
                // For now, assume all validators are honest
                true
            })
            .collect()
    }
    
    /// Helper method to parse shred from JSON for TLA+ import
    fn parse_shred_from_json(&self, shred_json: &serde_json::Value) -> AlpenglowResult<Option<Shred>> {
        let block_id_str = shred_json.get("blockId")
            .and_then(|v| v.as_str())
            .ok_or_else(|| AlpenglowError::ProtocolViolation("Missing blockId in shred JSON".to_string()))?;
        
        let slot = shred_json.get("slot")
            .and_then(|v| v.as_u64())
            .unwrap_or(0);
        
        let index = shred_json.get("index")
            .and_then(|v| v.as_u64())
            .map(|n| n as u32)
            .ok_or_else(|| AlpenglowError::ProtocolViolation("Missing index in shred JSON".to_string()))?;
        
        let data = shred_json.get("data")
            .and_then(|v| v.as_array())
            .map(|arr| arr.iter().filter_map(|v| v.as_u64().map(|n| n as u8)).collect::<Vec<u8>>())
            .unwrap_or_default();
        
        let is_parity = shred_json.get("isParity")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        
        let signature = shred_json.get("signature")
            .and_then(|v| v.as_u64())
            .unwrap_or(0);
        
        let size = shred_json.get("size")
            .and_then(|v| v.as_u64())
            .map(|n| n as usize)
            .unwrap_or(data.len() + 64); // Default size calculation
        
        let block_id = self.parse_block_id_from_string(block_id_str)?;
        
        let shred = Shred {
            block_id,
            slot,
            index,
            data,
            is_parity,
            signature,
            size,
        };
        
        Ok(Some(shred))
    }
    
    /// Helper method to parse block ID from string representation
    fn parse_block_id_from_string(&self, block_id_str: &str) -> AlpenglowResult<BlockHash> {
        // For simplicity, create a deterministic block ID from the string hash
        let mut hasher = std::collections::hash_map::DefaultHasher::new();
        use std::hash::{Hash, Hasher};
        block_id_str.hash(&mut hasher);
        let hash = hasher.finish();
        Ok(hash)
    }
    
    /// Helper method to parse shred ID from string representation
    fn parse_shred_id_from_string(&self, shred_id_str: &str) -> Option<ShredId> {
        if let Some(captures) = shred_id_str.strip_prefix("slot_") {
            if let Some(index_pos) = captures.find("_index_") {
                let slot_str = &captures[..index_pos];
                let index_str = &captures[index_pos + 7..];
                if let (Ok(slot), Ok(index)) = (slot_str.parse::<u64>(), index_str.parse::<u32>()) {
                    return Some(ShredId::new(slot, index));
                }
            }
        }
        None
    }
    
    /// Helper method to parse reconstruction state from JSON
    fn parse_reconstruction_state_from_json(&self, state_json: &serde_json::Value) -> AlpenglowResult<Option<ReconstructionState>> {
        let block_id_str = state_json.get("blockId")
            .and_then(|v| v.as_str())
            .ok_or_else(|| AlpenglowError::ProtocolViolation("Missing blockId in reconstruction state JSON".to_string()))?;
        
        let collected_pieces = state_json.get("collectedPieces")
            .and_then(|v| v.as_array())
            .map(|arr| arr.iter().filter_map(|v| v.as_u64().map(|n| n as u32)).collect::<HashSet<u32>>())
            .unwrap_or_default();
        
        let complete = state_json.get("complete")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        
        let start_time = state_json.get("startTime")
            .and_then(|v| v.as_u64())
            .unwrap_or(0);
        
        let repair_requests_sent = state_json.get("repairRequestsSent")
            .and_then(|v| v.as_u64())
            .map(|n| n as u32)
            .unwrap_or(0);
        
        let block_id = self.parse_block_id_from_string(block_id_str)?;
        
        let reconstruction_state = ReconstructionState {
            block_id,
            collected_pieces,
            complete,
            start_time,
            repair_requests_sent,
        };
        
        Ok(Some(reconstruction_state))
    }
    
    /// Helper method to parse repair request from JSON
    fn parse_repair_request_from_json(&self, request_json: &serde_json::Value) -> AlpenglowResult<Option<RepairRequest>> {
        let requester = request_json.get("requester")
            .and_then(|v| v.as_u64())
            .map(|n| n as ValidatorId)
            .ok_or_else(|| AlpenglowError::ProtocolViolation("Missing requester in repair request JSON".to_string()))?;
        
        let block_id_str = request_json.get("blockId")
            .and_then(|v| v.as_str())
            .ok_or_else(|| AlpenglowError::ProtocolViolation("Missing blockId in repair request JSON".to_string()))?;
        
        let missing_pieces = request_json.get("missingPieces")
            .and_then(|v| v.as_array())
            .map(|arr| arr.iter().filter_map(|v| v.as_u64().map(|n| n as u32)).collect::<HashSet<u32>>())
            .unwrap_or_default();
        
        let timestamp = request_json.get("timestamp")
            .and_then(|v| v.as_u64())
            .unwrap_or(0);
        
        let retry_count = request_json.get("retryCount")
            .and_then(|v| v.as_u64())
            .map(|n| n as u32)
            .unwrap_or(0);
        
        let block_id = self.parse_block_id_from_string(block_id_str)?;
        
        let repair_request = RepairRequest {
            requester,
            block_id,
            missing_pieces: missing_pieces.into_iter().collect(),
            timestamp,
            retry_count,
        };
        
        Ok(Some(repair_request))
    }
    
    /// Helper method to parse erasure block from JSON
    fn parse_erasure_block_from_json(&self, block_json: &serde_json::Value) -> AlpenglowResult<Option<ErasureBlock>> {
        let hash_str = block_json.get("hash")
            .and_then(|v| v.as_str())
            .ok_or_else(|| AlpenglowError::ProtocolViolation("Missing hash in erasure block JSON".to_string()))?;
        
        let slot = block_json.get("slot")
            .and_then(|v| v.as_u64())
            .unwrap_or(0);
        
        let view = block_json.get("view")
            .and_then(|v| v.as_u64())
            .unwrap_or(0);
        
        let proposer = block_json.get("proposer")
            .and_then(|v| v.as_u64())
            .map(|n| n as ValidatorId)
            .unwrap_or(0);
        
        let parent_str = block_json.get("parent")
            .and_then(|v| v.as_str())
            .unwrap_or("[0; 32]");
        
        let data = block_json.get("data")
            .and_then(|v| v.as_array())
            .map(|arr| arr.iter().filter_map(|v| v.as_u64().map(|n| n as u8)).collect::<Vec<u8>>())
            .unwrap_or_default();
        
        let timestamp = block_json.get("timestamp")
            .and_then(|v| v.as_u64())
            .unwrap_or(0);
        
        let total_shreds = block_json.get("totalShreds")
            .and_then(|v| v.as_u64())
            .map(|n| n as u32)
            .unwrap_or(self.n);
        
        let data_shreds = block_json.get("dataShreds")
            .and_then(|v| v.as_u64())
            .map(|n| n as u32)
            .unwrap_or(self.k);
        
        let hash = self.parse_block_id_from_string(hash_str)?;
        let parent = self.parse_block_id_from_string(parent_str)?;
        
        let erasure_block = ErasureBlock {
            hash,
            slot,
            view,
            proposer,
            parent,
            data,
            timestamp,
            transactions: Vec::new(), // Transactions not included in basic JSON
            total_shreds,
            data_shreds,
        };
        
        Ok(Some(erasure_block))
    }
    
    /// Validate imported state consistency
    fn validate_imported_state(&self) -> AlpenglowResult<()> {
        // Check that all validators in various maps are valid
        let max_validator = self.config.validator_count as ValidatorId;
        
        for &validator in self.bandwidth_usage.keys() {
            if validator >= max_validator {
                return Err(AlpenglowError::ProtocolViolation(
                    format!("Invalid validator {} in bandwidth_usage", validator)
                ));
            }
        }
        
        for &validator in self.delivered_blocks.keys() {
            if validator >= max_validator {
                return Err(AlpenglowError::ProtocolViolation(
                    format!("Invalid validator {} in delivered_blocks", validator)
                ));
            }
        }
        
        // Check that erasure coding parameters are consistent
        if self.k >= self.n || self.k == 0 || self.n == 0 {
            return Err(AlpenglowError::InvalidConfig(
                format!("Invalid erasure coding parameters: k={}, n={}", self.k, self.n)
            ));
        }
        
        // Check that all shreds have valid indices
        for validator_shreds in self.block_shreds.values() {
            for shreds in validator_shreds.values() {
                for shred in shreds {
                    if shred.index < 1 || shred.index > self.n {
                        return Err(AlpenglowError::ProtocolViolation(
                            format!("Invalid shred index {} not in range 1..{}", shred.index, self.n)
                        ));
                    }
                }
            }
        }
        
        Ok(())
    }
    
    /// Get data shred count for a block (helper for repair logic)
    fn get_data_shred_count(&self, _block_id: &BlockHash) -> u32 {
        self.k // All blocks use the same K parameter
    }
    
    /// Propose a new block - mirrors TLA+ ProposeBlock action
    pub fn propose_block(&mut self, leader: ValidatorId, slot: u64, block: ErasureBlock) -> AlpenglowResult<()> {
        // Validate leader and block
        if leader != block.proposer {
            return Err(AlpenglowError::ProtocolViolation(
                "Block proposer does not match leader".to_string(),
            ));
        }
        
        if slot != block.slot {
            return Err(AlpenglowError::ProtocolViolation(
                "Block slot does not match proposed slot".to_string(),
            ));
        }
        
        // Check if block already exists
        if self.block_shreds.contains_key(&block.hash) {
            return Err(AlpenglowError::ProtocolViolation(
                "Block already exists".to_string(),
            ));
        }
        
        // Validate block integrity
        if !self.validate_block_integrity(&block) {
            return Err(AlpenglowError::ProtocolViolation(
                "Invalid block integrity".to_string(),
            ));
        }
        
        // Store block for shredding
        self.block_shreds.insert(block.hash, HashMap::new());
        self.advance_clock();
        
        Ok(())
    }
    
    /// Shred a block into erasure-coded pieces - mirrors TLA+ ShredBlock action
    pub fn shred_block(&mut self, block: &ErasureBlock) -> AlpenglowResult<Vec<Shred>> {
        // Check if block exists
        if !self.block_shreds.contains_key(&block.hash) {
            return Err(AlpenglowError::ProtocolViolation(
                "Block not found for shredding".to_string(),
            ));
        }
        
        // Encode block into shreds
        let shreds = self.erasure_encode(block)?;
        
        // Create shred map for storage
        let mut shred_map = HashMap::new();
        for i in 1..=self.n {
            if let Some(shred) = shreds.iter().find(|s| s.index == i) {
                shred_map.insert(i, shred.clone());
            }
        }
        
        // Store shreds in block_shreds structure
        if let Some(block_entry) = self.block_shreds.get_mut(&block.hash) {
            block_entry.insert(self.validator_id, shreds.iter().cloned().collect());
        }
        
        self.advance_clock();
        Ok(shreds)
    }
    
    /// Broadcast shreds to selected recipients - mirrors TLA+ BroadcastShred action
    pub fn broadcast_shred(&mut self, relay: ValidatorId, shred: &Shred, recipients: &[ValidatorId]) -> AlpenglowResult<()> {
        // Validate relay
        if relay != self.validator_id {
            return Err(AlpenglowError::ProtocolViolation(
                "Invalid relay validator".to_string(),
            ));
        }
        
        // Check if shred exists in our collection
        let has_shred = self.block_shreds
            .get(&shred.block_id)
            .and_then(|bs| bs.get(&relay))
            .map_or(false, |shreds| shreds.contains(shred));
        
        if !has_shred {
            return Err(AlpenglowError::ProtocolViolation(
                "Shred not found for broadcasting".to_string(),
            ));
        }
        
        // Check bandwidth limits
        let bandwidth_needed = shred.size as u64 * recipients.len() as u64;
        if !self.check_bandwidth_limit(relay, bandwidth_needed) {
            return Err(AlpenglowError::ProtocolViolation(
                "Bandwidth limit exceeded".to_string(),
            ));
        }
        
        // Broadcast to recipients
        for &recipient in recipients {
            if recipient != relay {
                // Add shred to recipient's received shreds
                self.received_shreds
                    .entry(recipient)
                    .or_insert_with(HashSet::new)
                    .insert(shred.clone());
                
                // Also add to block_shreds for the recipient
                self.block_shreds
                    .entry(shred.block_id)
                    .or_insert_with(HashMap::new)
                    .entry(recipient)
                    .or_insert_with(HashSet::new)
                    .insert(shred.clone());
            }
        }
        
        // Update bandwidth usage
        self.update_bandwidth_usage(relay, bandwidth_needed);
        self.advance_clock();
        
        Ok(())
    }
    
    /// Create a shred from block data - mirrors TLA+ CreateShred
    pub fn create_shred(&self, block: &ErasureBlock, index: u32, merkle_path: Vec<u8>) -> AlpenglowResult<Shred> {
        if index < 1 || index > self.n {
            return Err(AlpenglowError::ProtocolViolation(
                format!("Invalid shred index {} not in range 1..{}", index, self.n),
            ));
        }
        
        // Determine if this is a parity shred
        let is_parity = index > self.k;
        
        // Create shred data (simplified - in practice would contain actual block data chunk)
        let data = if is_parity {
            // Parity data computation
            vec![0u8; 1024] // Placeholder parity data
        } else {
            // Data chunk from block
            let chunk_size = (block.data.len() + self.k as usize - 1) / self.k as usize;
            let start = ((index - 1) as usize) * chunk_size;
            let end = std::cmp::min(start + chunk_size, block.data.len());
            block.data[start..end].to_vec()
        };
        
        let shred = Shred {
            block_id: block.hash,
            slot: block.slot,
            index,
            data,
            is_parity,
            signature: block.proposer as u64, // Simplified signature
            size: 1024 + merkle_path.len(), // Base size + merkle proof
        };
        
        Ok(shred)
    }
    
    /// Validate shred integrity - mirrors TLA+ ValidateShred
    pub fn validate_shred(&self, shred: &Shred, merkle_root: &[u8]) -> bool {
        // Basic validation
        if shred.index < 1 || shred.index > self.n {
            return false;
        }
        
        // Check parity flag consistency
        if shred.is_parity && shred.index <= self.k {
            return false;
        }
        if !shred.is_parity && shred.index > self.k {
            return false;
        }
        
        // Validate data is not empty
        if shred.data.is_empty() {
            return false;
        }
        
        // Simplified merkle validation (in practice would verify actual merkle proof)
        if merkle_root.is_empty() {
            return false;
        }
        
        // Signature validation (simplified)
        if shred.signature == 0 {
            return false;
        }
        
        true
    }
    
    /// Validate reconstructed block - mirrors TLA+ ValidateReconstructedBlock
    pub fn validate_reconstructed_block(&self, block: &ErasureBlock, expected_hash: BlockHash) -> bool {
        block.hash == expected_hash && self.validate_block_integrity(block)
    }
    
    /// Request missing shreds for incomplete block - mirrors TLA+ RequestMissingShreds
    pub fn request_missing_shreds(&mut self, validator: ValidatorId, slot: u64, missing_indices: &[u32]) -> AlpenglowResult<()> {
        if validator != self.validator_id {
            return Err(AlpenglowError::ProtocolViolation(
                "Invalid validator for repair request".to_string(),
            ));
        }
        
        if missing_indices.is_empty() {
            return Ok(()); // Nothing to request
        }
        
        // Validate missing indices
        for &index in missing_indices {
            if index < 1 || index > self.n {
                return Err(AlpenglowError::ProtocolViolation(
                    format!("Invalid missing index {} not in range 1..{}", index, self.n),
                ));
            }
        }
        
        // Find block ID for this slot (simplified - assumes one block per slot)
        let block_id = slot; // Simplified mapping
        
        // Check bandwidth for repair request
        let repair_bandwidth = self.compute_repair_bandwidth(&HashSet::new()) + (missing_indices.len() as u64 * 50);
        if !self.check_bandwidth_limit(validator, repair_bandwidth) {
            return Err(AlpenglowError::ProtocolViolation(
                "Bandwidth limit exceeded for repair request".to_string(),
            ));
        }
        
        // Create repair request
        let repair_request = RepairRequest {
            requester: validator,
            block_id,
            missing_pieces: missing_indices.to_vec(),
            timestamp: self.clock,
            retry_count: 0,
        };
        
        self.repair_requests.insert(repair_request);
        self.update_bandwidth_usage(validator, repair_bandwidth);
        self.advance_clock();
        
        Ok(())
    }
    
    /// Respond to repair request by sending missing shreds - mirrors TLA+ RespondToRepairRequest
    pub fn respond_to_repair_request(&mut self, validator: ValidatorId, request: &RepairRequest) -> AlpenglowResult<Vec<Shred>> {
        if validator != self.validator_id {
            return Err(AlpenglowError::ProtocolViolation(
                "Invalid validator for repair response".to_string(),
            ));
        }
        
        if !self.repair_requests.contains(request) {
            return Err(AlpenglowError::ProtocolViolation(
                "Repair request not found".to_string(),
            ));
        }
        
        // Find available shreds for the requested block
        let available_shreds = self.block_shreds
            .get(&request.block_id)
            .and_then(|bs| bs.get(&validator))
            .cloned()
            .unwrap_or_default();
        
        // Filter shreds that match the missing pieces
        let response_shreds: Vec<Shred> = available_shreds
            .into_iter()
            .filter(|s| request.missing_pieces.contains(&s.index))
            .collect();
        
        if response_shreds.is_empty() {
            return Ok(Vec::new()); // No shreds to send
        }
        
        // Check bandwidth for response
        let response_bandwidth = response_shreds.iter().map(|s| s.size as u64).sum();
        if !self.check_bandwidth_limit(validator, response_bandwidth) {
            return Err(AlpenglowError::ProtocolViolation(
                "Bandwidth limit exceeded for repair response".to_string(),
            ));
        }
        
        // Send shreds to requester (add to their received shreds)
        for shred in &response_shreds {
            self.received_shreds
                .entry(request.requester)
                .or_insert_with(HashSet::new)
                .insert(shred.clone());
            
            // Also add to block_shreds for the requester
            self.block_shreds
                .entry(request.block_id)
                .or_insert_with(HashMap::new)
                .entry(request.requester)
                .or_insert_with(HashSet::new)
                .insert(shred.clone());
        }
        
        // Remove the repair request
        self.repair_requests.remove(request);
        self.update_bandwidth_usage(validator, response_bandwidth);
        self.advance_clock();
        
        Ok(response_shreds)
    }
    
    /// Check if block delivery was successful to honest majority - mirrors TLA+ RotorSuccessful
    pub fn rotor_successful(&self, slot: u64) -> bool {
        let block_id = slot; // Simplified mapping
        let honest_validators = self.honest_validators();
        let successful_validators: Vec<_> = honest_validators
            .iter()
            .filter(|&&v| {
                self.delivered_blocks
                    .get(&v)
                    .map_or(false, |delivered| delivered.contains(&block_id))
            })
            .collect();
        
        let honest_stake: StakeAmount = honest_validators
            .iter()
            .map(|&v| self.config.stake_distribution.get(&v).unwrap_or(&0))
            .sum();
        
        let successful_stake: StakeAmount = successful_validators
            .iter()
            .map(|&&v| self.config.stake_distribution.get(&v).unwrap_or(&0))
            .sum();
        
        successful_stake > honest_stake / 2
    }
    
    /// Stake-weighted sampling for relay selection - mirrors TLA+ StakeWeightedSampling
    pub fn stake_weighted_sampling(&self, validators: &[ValidatorId], count: usize) -> Vec<ValidatorId> {
        if validators.is_empty() || count == 0 {
            return Vec::new();
        }
        
        let total_stake = self.config.total_stake;
        if total_stake == 0 {
            // Equal probability sampling if no stake info
            let mut result = validators.to_vec();
            result.truncate(count);
            return result;
        }
        
        // Create cumulative stake distribution for sampling
        let mut cumulative_stakes = Vec::new();
        let mut cumulative = 0u64;
        
        for &validator in validators {
            let stake = self.config.stake_distribution.get(&validator).unwrap_or(&0);
            cumulative += stake;
            cumulative_stakes.push((validator, cumulative));
        }
        
        // Sample validators proportional to stake
        let mut selected = Vec::new();
        let mut used_validators = HashSet::new();
        
        for i in 0..count {
            if used_validators.len() >= validators.len() {
                break; // All validators already selected
            }
            
            // Deterministic sampling based on position and total stake
            let target = ((i as u64 + 1) * total_stake) / (count as u64 + 1);
            
            // Find validator with cumulative stake >= target
            for &(validator, cum_stake) in &cumulative_stakes {
                if cum_stake >= target && !used_validators.contains(&validator) {
                    selected.push(validator);
                    used_validators.insert(validator);
                    break;
                }
            }
        }
        
        // Fill remaining slots if needed
        while selected.len() < count && selected.len() < validators.len() {
            for &validator in validators {
                if !used_validators.contains(&validator) {
                    selected.push(validator);
                    used_validators.insert(validator);
                    if selected.len() >= count {
                        break;
                    }
                }
            }
            break; // Avoid infinite loop
        }
        
        selected
    }
    
    /// Select relays for specific slot and shred index - mirrors TLA+ SelectRelays
    pub fn select_relays(&self, slot: u64, shred_index: u32) -> Vec<ValidatorId> {
        let seed = slot * 1000 + shred_index as u64;
        let relay_count = std::cmp::min(self.config.validator_count / 3, 10);
        
        // Use deterministic selection based on seed
        let all_validators: Vec<ValidatorId> = (0..self.config.validator_count as ValidatorId).collect();
        
        // Create deterministic but stake-weighted selection
        let mut selected_validators = Vec::new();
        let total_stake = self.config.total_stake;
        
        if total_stake == 0 {
            // Round-robin selection if no stake info
            for i in 0..relay_count {
                let index = ((seed + i as u64) % self.config.validator_count as u64) as usize;
                if index < all_validators.len() {
                    selected_validators.push(all_validators[index]);
                }
            }
        } else {
            // Stake-weighted deterministic selection
            for i in 0..relay_count {
                let target = ((seed + i as u64) % total_stake) as u64;
                let mut cumulative = 0u64;
                
                for &validator in &all_validators {
                    let stake = self.config.stake_distribution.get(&validator).unwrap_or(&0);
                    cumulative += stake;
                    if cumulative > target && !selected_validators.contains(&validator) {
                        selected_validators.push(validator);
                        break;
                    }
                }
            }
        }
        
        selected_validators
    }
    
    /// Reed-Solomon encode using the reed-solomon-erasure crate - mirrors TLA+ ReedSolomonEncode
    pub fn reed_solomon_encode(&self, block: &ErasureBlock, k: u32, n: u32) -> AlpenglowResult<Vec<Shred>> {
        if k >= n || k == 0 || n == 0 {
            return Err(AlpenglowError::InvalidConfig(
                "Invalid Reed-Solomon parameters".to_string(),
            ));
        }
        
        let k_usize = k as usize;
        let n_usize = n as usize;
        
        // Create Reed-Solomon encoder
        let rs = ReedSolomon::new(k_usize, n_usize - k_usize)
            .map_err(|_| AlpenglowError::ProtocolViolation("Failed to create Reed-Solomon encoder".to_string()))?;
        
        // Split block data into k chunks
        let chunk_size = (block.data.len() + k_usize - 1) / k_usize;
        let mut data_chunks = Vec::new();
        
        for i in 0..k_usize {
            let start = i * chunk_size;
            let end = std::cmp::min(start + chunk_size, block.data.len());
            let mut chunk = block.data[start..end].to_vec();
            chunk.resize(chunk_size, 0); // Pad with zeros
            data_chunks.push(chunk);
        }
        
        // Create parity chunks
        let mut parity_chunks = vec![vec![0u8; chunk_size]; n_usize - k_usize];
        
        // Encode using Reed-Solomon
        let mut all_chunks = data_chunks.clone();
        all_chunks.append(&mut parity_chunks);
        
        rs.encode(&mut all_chunks)
            .map_err(|_| AlpenglowError::ProtocolViolation("Reed-Solomon encoding failed".to_string()))?;
        
        // Create shreds from chunks
        let mut shreds = Vec::new();
        
        // Data shreds (indices 1..k)
        for (i, chunk) in all_chunks[0..k_usize].iter().enumerate() {
            let shred = Shred::new_data(block.hash, block.slot, (i + 1) as u32, chunk.clone());
            shreds.push(shred);
        }
        
        // Parity shreds (indices k+1..n)
        for (i, chunk) in all_chunks[k_usize..].iter().enumerate() {
            let shred = Shred::new_parity(block.hash, block.slot, k + i as u32 + 1, chunk.clone());
            shreds.push(shred);
        }
        
        Ok(shreds)
    }
    
    /// Reed-Solomon decode using the reed-solomon-erasure crate - mirrors TLA+ ReedSolomonDecode
    pub fn reed_solomon_decode(&self, shreds: &[Shred]) -> AlpenglowResult<ErasureBlock> {
        if shreds.is_empty() {
            return Err(AlpenglowError::ProtocolViolation(
                "No shreds provided for decoding".to_string(),
            ));
        }
        
        let k_usize = self.k as usize;
        let n_usize = self.n as usize;
        
        if shreds.len() < k_usize {
            return Err(AlpenglowError::ProtocolViolation(
                "Insufficient shreds for reconstruction".to_string(),
            ));
        }
        
        // Create Reed-Solomon decoder
        let rs = ReedSolomon::new(k_usize, n_usize - k_usize)
            .map_err(|_| AlpenglowError::ProtocolViolation("Failed to create Reed-Solomon decoder".to_string()))?;
        
        // Prepare chunks for reconstruction
        let mut chunks: Vec<Option<Vec<u8>>> = vec![None; n_usize];
        
        for shred in shreds {
            if shred.index >= 1 && shred.index <= self.n {
                chunks[(shred.index - 1) as usize] = Some(shred.data.clone());
            }
        }
        
        // Reconstruct using Reed-Solomon
        rs.reconstruct(&mut chunks)
            .map_err(|_| AlpenglowError::ProtocolViolation("Reed-Solomon reconstruction failed".to_string()))?;
        
        // Combine data chunks to reconstruct block
        let mut reconstructed_data = Vec::new();
        for chunk_opt in chunks.into_iter().take(k_usize) {
            if let Some(chunk) = chunk_opt {
                reconstructed_data.extend_from_slice(&chunk);
            }
        }
        
        // Create reconstructed block
        let block_id = shreds[0].block_id;
        let slot = shreds[0].slot;
        
        let block = ErasureBlock {
            hash: block_id,
            slot,
            view: 2u64,
            proposer: 0, // Will be determined from context
            parent: 0,
            data: reconstructed_data,
            timestamp: self.clock,
            transactions: Vec::new(),
            total_shreds: self.n,
            data_shreds: self.k,
        };
        
        Ok(block)
    }
    
    /// Collect metrics for bandwidth usage, delivery times, and reconstruction success rates
    pub fn collect_metrics(&self) -> RotorMetrics {
        let total_bandwidth_used: u64 = self.bandwidth_usage.values().sum();
        let total_blocks = self.block_shreds.len();
        let total_delivered: usize = self.delivered_blocks.values().map(|s| s.len()).sum();
        let total_reconstructed: usize = self.reconstructed_blocks.values().map(|s| s.len()).sum();
        let active_repair_requests = self.repair_requests.len();
        
        // Calculate average delivery time (simplified)
        let avg_delivery_time = if total_delivered > 0 {
            self.clock / total_delivered as u64
        } else {
            0
        };
        
        // Calculate reconstruction success rate
        let reconstruction_success_rate = if total_blocks > 0 {
            (total_reconstructed as f64) / (total_blocks as f64)
        } else {
            0.0
        };
        
        // Calculate bandwidth utilization
        let total_bandwidth_capacity = self.bandwidth_limit * self.config.validator_count as u64;
        let bandwidth_utilization = if total_bandwidth_capacity > 0 {
            (total_bandwidth_used as f64) / (total_bandwidth_capacity as f64)
        } else {
            0.0
        };
        
        RotorMetrics {
            total_bandwidth_used,
            bandwidth_utilization,
            total_blocks,
            total_delivered,
            total_reconstructed,
            reconstruction_success_rate,
            active_repair_requests,
            avg_delivery_time,
            clock: self.clock,
        }
    }
}

/// Metrics for Rotor performance tracking
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RotorMetrics {
    /// Total bandwidth used across all validators
    pub total_bandwidth_used: u64,
    /// Bandwidth utilization as percentage (0.0 to 1.0)
    pub bandwidth_utilization: f64,
    /// Total number of blocks being propagated
    pub total_blocks: usize,
    /// Total number of blocks delivered
    pub total_delivered: usize,
    /// Total number of blocks reconstructed
    pub total_reconstructed: usize,
    /// Reconstruction success rate (0.0 to 1.0)
    pub reconstruction_success_rate: f64,
    /// Number of active repair requests
    pub active_repair_requests: usize,
    /// Average delivery time
    pub avg_delivery_time: u64,
    /// Current clock time
    pub clock: u64,
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
        missing_pieces: Vec<u32>,
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
        let validator_id = id as u32;
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
                                let empty_set = HashSet::new();
                                for validator in &validators {
                                    let assigned_indices = assignments.get(validator).unwrap_or(&empty_set);
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
                    // Clone the shreds to avoid borrow checker issues
                    let my_shreds_clone = state.block_shreds.get(&block_id)
                        .and_then(|block_shreds| block_shreds.get(&validator_id))
                        .cloned();
                    
                    if let Some(my_shreds) = my_shreds_clone {
                        if !my_shreds.is_empty() {
                            let bandwidth_needed = state.compute_bandwidth(&my_shreds);
                            
                            // Check non-equivocation for relay - mirrors TLA+ RelayShreds
                            if !state.check_non_equivocation(validator_id, &my_shreds) {
                                // Non-equivocation violation detected, reject this action
                                return;
                            }
                            
                            if state.check_bandwidth_limit(validator_id, bandwidth_needed) {
                                // Select relay targets using PS-P sampling
                                let targets = state.select_relay_targets(validator_id, &my_shreds.iter().next().unwrap());
                                
                                // Send shreds to targets
                                for target in targets {
                                    if target != validator_id {
                                        let target_id = Id::from(target as usize);
                                        let shreds_vec: Vec<Shred> = my_shreds.iter().cloned().collect();
                                        o.send(target_id, RotorMessage::RelayShreds {
                                            validator: target,
                                            block_id,
                                            shreds: shreds_vec,
                                        });
                                    }
                                }
                                
                                // Record shreds sent for non-equivocation tracking
                                for shred in &my_shreds {
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
                                                missing_pieces: Vec::new(), // Will be computed
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
                                missing_pieces: Vec::new(), // Will be computed
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
                                        missing_pieces: needed_pieces.into_iter().collect(),
                                        timestamp: state.clock,
                                        retry_count: 0,
                                    };
                                    
                                    state.repair_requests.insert(repair_request.clone());
                                    state.update_bandwidth_usage(validator_id, repair_bandwidth);
                                    state.advance_clock();
                                    
                                    // Broadcast repair request to other validators
                                    for i in 0..state.config.validator_count {
                                        let target_id = Id::from(i);
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
                                    let requester_id = Id::from(request.requester as usize);
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
    fn verify(&self) -> AlpenglowResult<()> {
        // Default comprehensive verification calls the three specific checks
        self.verify_safety()?;
        self.verify_liveness()?;
        self.verify_byzantine_resilience()?;
        Ok(())
    }

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
    fn to_tla_string(&self) -> String {
        // Serialize the RotorState to a JSON string for TLA+ compatibility export.
        serde_json::to_string(self).unwrap_or_else(|_| "{}".to_string())
    }

    fn validate_tla_invariants(&self) -> AlpenglowResult<()> {
        // Validate all invariants that should match TLA+ Rotor specification exactly
        
        // 1. RotorNonEquivocation: no validator sends two different shreds with the same ID
        for (&validator, history) in &self.rotor_history {
            for (shred_id, sent_shred) in history {
                // Check all shreds in block_shreds for this validator
                for block_shreds in self.block_shreds.values() {
                    if let Some(validator_shreds) = block_shreds.get(&validator) {
                        for other_shred in validator_shreds {
                            let other_shred_id = other_shred.shred_id();
                            if other_shred_id.slot == shred_id.slot && 
                               other_shred_id.index == shred_id.index &&
                               other_shred != sent_shred {
                                return Err(AlpenglowError::ProtocolViolation(
                                    format!("RotorNonEquivocation violation: validator {} sent different shreds with same ID slot:{} index:{}", 
                                           validator, shred_id.slot, shred_id.index),
                                ));
                            }
                        }
                    }
                }
            }
        }
        
        // 2. DistinctIndices: ensures no duplicate shred indices per block per validator
        for (block_id, validator_shreds) in &self.block_shreds {
            for (&validator, shreds) in validator_shreds {
                let indices: HashSet<u32> = shreds.iter().map(|s| s.index).collect();
                if indices.len() != shreds.len() {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("DistinctIndices violation: validator {} has duplicate shred indices for block {:?}", 
                               validator, block_id),
                    ));
                }
            }
        }
        
        // 3. ValidErasureCode: ensures proper K/N partitioning
        for (block_id, validator_shreds) in &self.block_shreds {
            for (&validator, shreds) in validator_shreds {
                let data_shreds: Vec<_> = shreds.iter().filter(|s| !s.is_parity).collect();
                let parity_shreds: Vec<_> = shreds.iter().filter(|s| s.is_parity).collect();
                let data_indices: HashSet<u32> = data_shreds.iter().map(|s| s.index).collect();
                let parity_indices: HashSet<u32> = parity_shreds.iter().map(|s| s.index).collect();
                
                // Check proper partitioning: data indices in 1..K, parity indices in (K+1)..N
                for &index in &data_indices {
                    if index < 1 || index > self.k {
                        return Err(AlpenglowError::ProtocolViolation(
                            format!("ValidErasureCode violation: data shred index {} not in range 1..{} for block {:?} validator {}", 
                                   index, self.k, block_id, validator),
                        ));
                    }
                }
                
                for &index in &parity_indices {
                    if index <= self.k || index > self.n {
                        return Err(AlpenglowError::ProtocolViolation(
                            format!("ValidErasureCode violation: parity shred index {} not in range {}..{} for block {:?} validator {}", 
                                   index, self.k + 1, self.n, block_id, validator),
                        ));
                    }
                }
                
                // Check no overlap between data and parity indices
                if !data_indices.is_disjoint(&parity_indices) {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("ValidErasureCode violation: data and parity indices overlap for block {:?} validator {}", 
                               block_id, validator),
                    ));
                }
            }
        }
        
        // 4. TypeInvariant: validate all type constraints from TLA+ specification
        
        // Check all shreds have valid properties
        for (_block_id, validator_shreds) in &self.block_shreds {
            for (&validator, shreds) in validator_shreds {
                for shred in shreds {
                    // s.blockId # <<>> (non-empty block ID)
                    if shred.block_id == 0u64 {
                        return Err(AlpenglowError::ProtocolViolation(
                            format!("TypeInvariant violation: empty block ID for shred index {} validator {}", 
                                   shred.index, validator),
                        ));
                    }
                    
                    // s.index \in 1..N
                    if shred.index < 1 || shred.index > self.n {
                        return Err(AlpenglowError::ProtocolViolation(
                            format!("TypeInvariant violation: shred index {} not in range 1..{} for validator {}", 
                                   shred.index, self.n, validator),
                        ));
                    }
                    
                    // s.slot \in Nat (non-negative)
                    // Slot is u64, so always non-negative in Rust
                }
            }
        }
        
        // Check validator constraints
        for &validator in self.bandwidth_usage.keys() {
            if validator >= self.config.validator_count as ValidatorId {
                return Err(AlpenglowError::ProtocolViolation(
                    format!("TypeInvariant violation: invalid validator ID {} >= {}", 
                           validator, self.config.validator_count),
                ));
            }
        }
        
        // bandwidthUsage[v] \in Nat (non-negative)
        for (&validator, &usage) in &self.bandwidth_usage {
            // u64 is always non-negative, but check for reasonable bounds
            if usage > self.bandwidth_limit * 10 {
                return Err(AlpenglowError::ProtocolViolation(
                    format!("TypeInvariant violation: excessive bandwidth usage {} for validator {}", 
                           usage, validator),
                ));
            }
        }
        
        // deliveredBlocks[v] \subseteq Nat (block IDs are natural numbers)
        // BlockHash is [u8; 32], so this is satisfied by construction
        
        // rotorHistory[v] \in [ShredId -> UNION {blockShreds[b][v] : b \in DOMAIN blockShreds}]
        for (&validator, history) in &self.rotor_history {
            for (shred_id, shred) in history {
                // Verify shred ID consistency
                if shred_id.slot != shred.slot || shred_id.index != shred.index {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("TypeInvariant violation: inconsistent shred ID and shred data for validator {}", 
                               validator),
                    ));
                }
                
                // Verify shred exists in some block for this validator
                let mut found = false;
                for block_shreds in self.block_shreds.values() {
                    if let Some(validator_shreds) = block_shreds.get(&validator) {
                        if validator_shreds.contains(shred) {
                            found = true;
                            break;
                        }
                    }
                }
                if !found {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("TypeInvariant violation: shred in history not found in blockShreds for validator {}", 
                               validator),
                    ));
                }
            }
        }
        
        // clock \in Nat (non-negative)
        // u64 is always non-negative
        
        // 5. BandwidthSafety: All validators respect bandwidth limits
        for (&validator, &usage) in &self.bandwidth_usage {
            if usage > self.bandwidth_limit {
                return Err(AlpenglowError::ProtocolViolation(
                    format!("BandwidthSafety violation: validator {} usage {} exceeds limit {}", 
                           validator, usage, self.bandwidth_limit),
                ));
            }
        }
        
        // 6. LoadBalanced: bandwidth usage is reasonably balanced
        if self.bandwidth_usage.len() > 1 {
            let usages: Vec<u64> = self.bandwidth_usage.values().cloned().collect();
            let min_usage = *usages.iter().min().unwrap_or(&0);
            let max_usage = *usages.iter().max().unwrap_or(&0);
            let tolerance = (self.load_balance_tolerance * self.bandwidth_limit as f64) as u64;
            
            if max_usage > min_usage + tolerance {
                return Err(AlpenglowError::ProtocolViolation(
                    format!("LoadBalanced violation: bandwidth usage imbalance {} > tolerance {}", 
                           max_usage - min_usage, tolerance),
                ));
            }
        }
        
        // 7. ReconstructionCorrectness: All reconstructed blocks are valid
        for (&validator, blocks) in &self.reconstructed_blocks {
            for block in blocks {
                if !self.validate_block_integrity(block) {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("ReconstructionCorrectness violation: invalid reconstructed block for validator {}", 
                               validator),
                    ));
                }
                
                // Verify block is properly delivered
                if !self.delivered_blocks.get(&validator).unwrap_or(&HashSet::new()).contains(&block.hash) {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("ReconstructionCorrectness violation: reconstructed block not marked as delivered for validator {}", 
                               validator),
                    ));
                }
            }
        }
        
        // 8. Validate erasure coding parameters consistency
        if self.k >= self.n || self.k == 0 || self.n == 0 {
            return Err(AlpenglowError::ProtocolViolation(
                format!("Invalid erasure coding parameters: K={}, N={}", self.k, self.n),
            ));
        }
        
        // 9. Validate repair request consistency
        for request in &self.repair_requests {
            // Requester must be valid validator
            if request.requester >= self.config.validator_count as ValidatorId {
                return Err(AlpenglowError::ProtocolViolation(
                    format!("Invalid repair request: requester {} >= validator count {}", 
                           request.requester, self.config.validator_count),
                ));
            }
            
            // Missing pieces must be in valid range
            for &piece_index in &request.missing_pieces {
                if piece_index < 1 || piece_index > self.n {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("Invalid repair request: missing piece index {} not in range 1..{}", 
                               piece_index, self.n),
                    ));
                }
            }
            
            // Timestamp must not be in the future
            if request.timestamp > self.clock {
                return Err(AlpenglowError::ProtocolViolation(
                    format!("Invalid repair request: timestamp {} > current clock {}", 
                           request.timestamp, self.clock),
                ));
            }
        }
        
        // 10. Validate reconstruction state consistency
        for (&validator, states) in &self.reconstruction_state {
            for state in states {
                // Collected pieces must be in valid range
                for &piece_index in &state.collected_pieces {
                    if piece_index < 1 || piece_index > self.n {
                        return Err(AlpenglowError::ProtocolViolation(
                            format!("Invalid reconstruction state: collected piece index {} not in range 1..{} for validator {}", 
                                   piece_index, self.n, validator),
                        ));
                    }
                }
                
                // If complete, must have enough pieces
                if state.complete && state.collected_pieces.len() < self.k as usize {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("Invalid reconstruction state: marked complete but only {} < {} pieces for validator {}", 
                               state.collected_pieces.len(), self.k, validator),
                    ));
                }
                
                // Start time must not be in the future
                if state.start_time > self.clock {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("Invalid reconstruction state: start time {} > current clock {} for validator {}", 
                               state.start_time, self.clock, validator),
                    ));
                }
            }
        }
        
        Ok(())
    }

    fn export_tla_state(&self) -> String {
        // Export as JSON string which is the canonical representation for TlaCompatible
        serde_json::to_string(&serde_json::json!({
            // Core state variables matching TLA+ rotorVars
            "blockShreds": self.block_shreds.iter().map(|(&block_id, validator_shreds)| {
                let validator_shreds_json: HashMap<String, Vec<serde_json::Value>> = validator_shreds
                    .iter()
                    .map(|(&validator, shreds)| {
                        let shreds_json: Vec<serde_json::Value> = shreds
                            .iter()
                            .map(|shred| {
                                serde_json::json!({
                                    "blockId": format!("{:?}", shred.block_id),
                                    "slot": shred.slot,
                                    "index": shred.index,
                                    "data": shred.data,
                                    "isParity": shred.is_parity,
                                    "signature": shred.signature,
                                    "size": shred.size
                                })
                            })
                            .collect();
                        (validator.to_string(), shreds_json)
                    })
                    .collect();
                (format!("{:?}", block_id), validator_shreds_json)
            }).collect::<HashMap<_, _>>(),
            "relayAssignments": self.relay_assignments.iter().map(|(&validator, assignments)| (validator.to_string(), assignments.clone())).collect::<HashMap<_, _>>(),
            "reconstructionState": self.reconstruction_state.iter().map(|(&validator, states)| {
                let states_json: Vec<serde_json::Value> = states
                    .iter()
                    .map(|state| {
                        serde_json::json!({
                            "blockId": format!("{:?}", state.block_id),
                            "collectedPieces": state.collected_pieces.iter().collect::<Vec<_>>(),
                            "complete": state.complete,
                            "startTime": state.start_time,
                            "repairRequestsSent": state.repair_requests_sent
                        })
                    })
                    .collect();
                (validator.to_string(), states_json)
            }).collect::<HashMap<_, _>>(),
            "deliveredBlocks": self.delivered_blocks.iter().map(|(&validator, blocks)| {
                let blocks_json: Vec<String> = blocks.iter().map(|block_id| format!("{:?}", block_id)).collect();
                (validator.to_string(), blocks_json)
            }).collect::<HashMap<_, _>>(),
            "repairRequests": self.repair_requests.iter().map(|request| {
                serde_json::json!({
                    "requester": request.requester,
                    "blockId": format!("{:?}", request.block_id),
                    "missingPieces": request.missing_pieces.iter().collect::<Vec<_>>(),
                    "timestamp": request.timestamp,
                    "retryCount": request.retry_count
                })
            }).collect::<Vec<_>>(),
            "bandwidthUsage": self.bandwidth_usage.iter().map(|(&validator, &usage)| (validator.to_string(), usage)).collect::<HashMap<_, _>>(),
            "receivedShreds": self.received_shreds.iter().map(|(&validator, shreds)| {
                let shreds_json: Vec<serde_json::Value> = shreds.iter().map(|shred| {
                    serde_json::json!({
                        "blockId": format!("{:?}", shred.block_id),
                        "slot": shred.slot,
                        "index": shred.index,
                        "data": shred.data,
                        "isParity": shred.is_parity,
                        "signature": shred.signature,
                        "size": shred.size
                    })
                }).collect();
                (validator.to_string(), shreds_json)
            }).collect::<HashMap<_, _>>(),
            "shredAssignments": self.shred_assignments.iter().map(|(&validator, assignments)| {
                let assignments_vec: Vec<u32> = assignments.iter().cloned().collect();
                (validator.to_string(), assignments_vec)
            }).collect::<HashMap<_, _>>(),
            "reconstructedBlocks": self.reconstructed_blocks.iter().map(|(&validator, blocks)| {
                let blocks_json: Vec<serde_json::Value> = blocks.iter().map(|block| {
                    serde_json::json!({
                        "hash": format!("{:?}", block.hash),
                        "slot": block.slot,
                        "view": block.view,
                        "proposer": block.proposer,
                        "parent": format!("{:?}", block.parent),
                        "data": block.data,
                        "timestamp": block.timestamp,
                        "totalShreds": block.total_shreds,
                        "dataShreds": block.data_shreds
                    })
                }).collect();
                (validator.to_string(), blocks_json)
            }).collect::<HashMap<_, _>>(),
            "rotorHistory": self.rotor_history.iter().map(|(&validator, history)| {
                let history_json: HashMap<String, serde_json::Value> = history.iter().map(|(shred_id, shred)| {
                    let key = format!("slot_{}_index_{}", shred_id.slot, shred_id.index);
                    let value = serde_json::json!({
                        "blockId": format!("{:?}", shred.block_id),
                        "slot": shred.slot,
                        "index": shred.index,
                        "data": shred.data,
                        "isParity": shred.is_parity,
                        "signature": shred.signature,
                        "size": shred.size
                    });
                    (key, value)
                }).collect();
                (validator.to_string(), history_json)
            }).collect::<HashMap<_, _>>(),
            "clock": self.clock,
            "validator_id": self.validator_id,
            "k": self.k,
            "n": self.n,
            "bandwidth_limit": self.bandwidth_limit,
            "retry_timeout": self.retry_timeout,
            "max_retries": self.max_retries,
            "load_balance_tolerance": self.load_balance_tolerance,
            "total_blocks": self.block_shreds.len(),
            "total_repair_requests": self.repair_requests.len(),
            "total_delivered_blocks": self.delivered_blocks.values().map(|s| s.len()).sum::<usize>(),
            "total_reconstructed_blocks": self.reconstructed_blocks.values().map(|s| s.len()).sum::<usize>(),
            "total_bandwidth_used": self.bandwidth_usage.values().sum::<u64>(),
            "validator_count": self.config.validator_count,
            "stake_distribution": self.config.stake_distribution,
            "total_stake": self.config.total_stake
        })).unwrap_or_else(|_| "{}".to_string())
    }

    fn import_tla_state(&mut self, state: &Self) -> AlpenglowResult<()> {
        // Import state from another RotorState (canonical trait signature uses &Self)
        // We selectively copy the serializable and relevant fields.
        self.validator_id = state.validator_id;
        self.config = state.config.clone();
        self.block_shreds = state.block_shreds.clone();
        self.relay_assignments = state.relay_assignments.clone();
        self.reconstruction_state = state.reconstruction_state.clone();
        self.delivered_blocks = state.delivered_blocks.clone();
        self.repair_requests = state.repair_requests.clone();
        self.bandwidth_usage = state.bandwidth_usage.clone();
        self.received_shreds = state.received_shreds.clone();
        self.shred_assignments = state.shred_assignments.clone();
        self.reconstructed_blocks = state.reconstructed_blocks.clone();
        self.rotor_history = state.rotor_history.clone();
        self.clock = state.clock;
        self.bandwidth_limit = state.bandwidth_limit;
        self.retry_timeout = state.retry_timeout;
        self.max_retries = state.max_retries;
        self.load_balance_tolerance = state.load_balance_tolerance;
        self.k = state.k;
        self.n = state.n;
        
        // Recompute reed_solomon based on k/n if possible
        self.reed_solomon = if self.k > 0 && self.n > self.k {
            ReedSolomon::new(self.k as usize, (self.n - self.k) as usize).ok()
        } else {
            None
        };
        
        // Validate imported state consistency
        self.validate_imported_state()?;
        
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
            1u64,
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
            1u64,
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
        let shred1 = Shred::new_data(1u64, 1, 1, vec![1, 2, 3]);
        let shred2 = Shred::new_data(2u64, 1, 1, vec![4, 5, 6]); // Different data, same ID
        
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
        let shred3 = Shred::new_data(1u64, 1, 1, vec![7, 8, 9]);
        state.record_shred_sent(0, shred_id, shred3);
        
        let exported_str = state.export_tla_state();
        let exported: serde_json::Value = serde_json::from_str(&exported_str).unwrap_or(serde_json::Value::Null);
        assert!(exported.get("validator_id").is_some());
        assert!(exported.get("clock").is_some());
        assert!(exported.get("rotorHistory").is_some());
        assert!(exported.get("k").is_some());
        assert!(exported.get("n").is_some());
        
        // Test import using the &Self signature
        let mut new_state = RotorState::new(1, Config::new().with_validators(3).with_erasure_coding(2, 3));
        assert!(new_state.import_tla_state(&state).is_ok());
        
        assert!(state.validate_tla_invariants().is_ok());
    }
    
    #[test]
    fn test_ps_p_sampling() {
        let config = Config::new().with_validators(5).with_erasure_coding(3, 5);
        let state = RotorState::new(0, config);
        
        let shred = Shred::new_data(1u64, 1, 1, vec![1, 2, 3]);
        let targets = state.select_relay_targets(0, &shred);
        
        // Should select some targets based on stake weights
        assert!(!targets.is_empty());
        assert!(!targets.contains(&0)); // Should not include self
        
        // All targets should be valid validator IDs
        for target in targets {
            assert!(target < state.config.validator_count as ValidatorId);
        }
    }
    
    #[test]
    fn test_propose_block() {
        let config = Config::new().with_validators(3).with_erasure_coding(2, 3);
        let mut state = RotorState::new(0, config);
        
        let block = ErasureBlock::new(1u64, 1, 0, vec![1, 2, 3, 4], 2, 3);
        
        let result = state.propose_block(0, 1, block);
        assert!(result.is_ok());
        assert!(state.block_shreds.contains_key(&1u64));
    }
    
    #[test]
    fn test_shred_block() {
        let config = Config::new().with_validators(3).with_erasure_coding(2, 3);
        let mut state = RotorState::new(0, config);
        
        let block = ErasureBlock::new(1u64, 1, 0, vec![1, 2, 3, 4], 2, 3);
        
        // First propose the block
        state.propose_block(0, 1, block.clone()).unwrap();
        
        // Then shred it
        let result = state.shred_block(&block);
        assert!(result.is_ok());
        
        let shreds = result.unwrap();
        assert_eq!(shreds.len(), 3); // 2 data + 1 parity
    }
    
    #[test]
    fn test_broadcast_shred() {
        let config = Config::new().with_validators(3).with_erasure_coding(2, 3);
        let mut state = RotorState::new(0, config);
        
        let block = ErasureBlock::new(1u64, 1, 0, vec![1, 2, 3, 4], 2, 3);
        state.propose_block(0, 1, block.clone()).unwrap();
        let shreds = state.shred_block(&block).unwrap();
        
        let shred = &shreds[0];
        let recipients = vec![1, 2];
        
        let result = state.broadcast_shred(0, shred, &recipients);
        assert!(result.is_ok());
        
        // Check that recipients received the shred
        assert!(state.received_shreds.get(&1).unwrap().contains(shred));
        assert!(state.received_shreds.get(&2).unwrap().contains(shred));
    }
    
    #[test]
    fn test_repair_mechanism() {
        let config = Config::new().with_validators(3).with_erasure_coding(2, 3);
        let mut state = RotorState::new(0, config);
        
        // Request missing shreds
        let missing_indices = vec![1, 2];
        let result = state.request_missing_shreds(0, 1, &missing_indices);
        assert!(result.is_ok());
        assert_eq!(state.repair_requests.len(), 1);
        
        // Create a repair request to respond to
        let repair_request = state.repair_requests.iter().next().unwrap().clone();
        
        // Add some shreds to respond with
        let shred1 = Shred::new_data(1u64, 1, 1, vec![1, 2, 3]);
        let shred2 = Shred::new_data(1u64, 1, 2, vec![4, 5, 6]);
        
        state.block_shreds.insert(1u64, HashMap::new());
        state.block_shreds.get_mut(&1u64).unwrap().insert(0, [shred1.clone(), shred2.clone()].iter().cloned().collect());
        
        // Respond to repair request
        let result = state.respond_to_repair_request(0, &repair_request);
        assert!(result.is_ok());
        
        let response_shreds = result.unwrap();
        assert_eq!(response_shreds.len(), 2);
    }
    
    #[test]
    fn test_rotor_successful() {
        let config = Config::new().with_validators(3).with_erasure_coding(2, 3);
        let mut state = RotorState::new(0, config);
        
        // Initially no blocks delivered
        assert!(!state.rotor_successful(1));
        
        // Mark block as delivered to majority of validators
        state.delivered_blocks.insert(0, [1u64].iter().cloned().collect());
        state.delivered_blocks.insert(1, [1u64].iter().cloned().collect());
        
        // Now should be successful
        assert!(state.rotor_successful(1));
    }
    
    #[test]
    fn test_stake_weighted_sampling() {
        let config = Config::new().with_validators(4).with_erasure_coding(2, 4);
        let state = RotorState::new(0, config);
        
        let validators = vec![0, 1, 2, 3];
        let selected = state.stake_weighted_sampling(&validators, 2);
        
        assert_eq!(selected.len(), 2);
        assert!(selected.iter().all(|&v| validators.contains(&v)));
    }
    
    #[test]
    fn test_select_relays() {
        let config = Config::new().with_validators(4).with_erasure_coding(2, 4);
        let state = RotorState::new(0, config);
        
        let relays = state.select_relays(1, 1);
        assert!(!relays.is_empty());
        assert!(relays.len() <= 4);
        
        // Should be deterministic
        let relays2 = state.select_relays(1, 1);
        assert_eq!(relays, relays2);
    }
    
    #[test]
    fn test_reed_solomon_encode_decode() {
        let config = Config::new().with_validators(3).with_erasure_coding(2, 3);
        let state = RotorState::new(0, config);
        
        let block = ErasureBlock::new(1u64, 1, 0, vec![1, 2, 3, 4, 5, 6, 7, 8], 2, 3);
        
        // Encode
        let result = state.reed_solomon_encode(&block, 2, 3);
        assert!(result.is_ok());
        
        let shreds = result.unwrap();
        assert_eq!(shreds.len(), 3);
        
        // Decode
        let result = state.reed_solomon_decode(&shreds);
        assert!(result.is_ok());
        
        let reconstructed = result.unwrap();
        assert_eq!(reconstructed.hash, block.hash);
    }
    
    #[test]
    fn test_metrics_collection() {
        let config = Config::new().with_validators(3).with_erasure_coding(2, 3);
        let mut state = RotorState::new(0, config);
        
        // Add some test data
        state.bandwidth_usage.insert(0, 1000);
        state.bandwidth_usage.insert(1, 2000);
        state.delivered_blocks.insert(0, [1u64, 2u64].iter().cloned().collect());
        
        let metrics = state.collect_metrics();
        assert_eq!(metrics.total_bandwidth_used, 3000);
        assert_eq!(metrics.total_delivered, 2);
        assert!(metrics.bandwidth_utilization >= 0.0);
    }
    
    #[test]
    fn test_create_and_validate_shred() {
        let config = Config::new().with_validators(3).with_erasure_coding(2, 3);
        let state = RotorState::new(0, config);
        
        let block = ErasureBlock::new(1u64, 1, 0, vec![1, 2, 3, 4], 2, 3);
        let merkle_path = vec![0u8; 32];
        
        let result = state.create_shred(&block, 1, merkle_path);
        assert!(result.is_ok());
        
        let shred = result.unwrap();
        assert_eq!(shred.block_id, block.hash);
        assert_eq!(shred.slot, block.slot);
        assert_eq!(shred.index, 1);
        assert!(!shred.is_parity); // Index 1 should be data shred
        
        // Validate the shred
        let merkle_root = vec![1u8; 32];
        assert!(state.validate_shred(&shred, &merkle_root));
    }
}
