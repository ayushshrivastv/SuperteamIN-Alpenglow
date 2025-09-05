//! # Votor Consensus Component
//!
//! This module implements the Votor consensus mechanism from the Alpenglow protocol
//! using Stateright's actor model. It mirrors the dual-path consensus logic from
//! the TLA+ specification in `specs/Votor.tla`.
//!
//! ## Key Features
//!
//! - **Dual-path consensus**: Fast path (≥80% stake) and slow path (≥60% stake)
//! - **Skip mechanism**: Timeout-based view advancement
//! - **Byzantine resilience**: Handles up to 1/3 Byzantine validators
//! - **VRF-based leader selection**: Deterministic but unpredictable leader rotation
//! - **Leader windows**: 4-slot windows with adaptive timeouts
//! - **Certificate generation**: Aggregated signatures for finalization
//!
//! ## State Machine
//!
//! The Votor actor maintains state for:
//! - Current view and voting rounds with leader windows
//! - Received votes and generated certificates
//! - Adaptive timeout handling and skip votes
//! - Finalized blockchain with VRF-based leader selection

use crate::{
    AlpenglowError, AlpenglowResult, BlockHash, Config, Signature, SlotNumber, 
    StakeAmount, TlaCompatible, ValidatorId, Verifiable
};
use serde::{Deserialize, Serialize};
use crate::stateright::{Actor, Id};
use std::collections::{HashMap, HashSet};
use std::time::{Duration, Instant};

/// View number type for consensus rounds
pub type ViewNumber = u64;

/// Timeout duration in milliseconds
pub type TimeoutMs = u64;

/// Leader window size (4 slots as per TLA+ specification)
pub const LEADER_WINDOW_SIZE: u64 = 4;

/// Base timeout duration in milliseconds
pub const BASE_TIMEOUT: u64 = 100;

/// VRF key pair for leader selection
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Hash)]
pub struct VRFKeyPair {
    pub validator: ValidatorId,
    pub public_key: u64,
    pub private_key: u64,
    pub valid: bool,
}

/// VRF proof structure
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Hash)]
pub struct VRFProof {
    pub validator: ValidatorId,
    pub input: u64,
    pub output: u64,
    pub proof: u64,
    pub public_key: u64,
    pub valid: bool,
}

/// Block proposal structure
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Hash)]
pub struct Block {
    /// Slot number for this block
    pub slot: SlotNumber,
    /// View number when proposed
    pub view: ViewNumber,
    /// Block hash identifier
    pub hash: BlockHash,
    /// Parent block hash
    pub parent: BlockHash,
    /// Validator that proposed this block
    pub proposer: ValidatorId,
    /// Set of transactions in the block
    pub transactions: HashSet<Transaction>,
    /// Timestamp when block was created
    pub timestamp: u64,
    /// Block proposer's signature
    pub signature: Signature,
    /// Additional block data
    pub data: Vec<u8>,
}

/// Transaction structure
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Hash)]
pub struct Transaction {
    /// Unique transaction identifier
    pub id: u64,
    /// Transaction sender
    pub sender: ValidatorId,
    /// Transaction data payload
    pub data: Vec<u8>,
    /// Transaction signature
    pub signature: Signature,
}

/// Vote types in the consensus protocol
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Hash)]
pub enum VoteType {
    /// Proposal vote (leader proposes block)
    Proposal,
    /// Echo vote (validator echoes proposal)
    Echo,
    /// Commit vote (validator commits to block)
    Commit,
    /// Skip vote (validator wants to skip current view)
    Skip,
}

/// Vote message structure
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Hash)]
pub struct Vote {
    /// Validator casting the vote
    pub voter: ValidatorId,
    /// Slot being voted on
    pub slot: SlotNumber,
    /// View number for this vote
    pub view: ViewNumber,
    /// Block hash being voted for (0 for skip votes)
    pub block: BlockHash,
    /// Type of vote
    pub vote_type: VoteType,
    /// Vote signature
    pub signature: Signature,
    /// Timestamp when vote was cast
    pub timestamp: u64,
}

/// Certificate types for finalization
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Hash)]
pub enum CertificateType {
    /// Fast path certificate (≥80% stake)
    Fast,
    /// Slow path certificate (≥60% stake)
    Slow,
    /// Skip certificate (≥60% stake for timeout)
    Skip,
}

/// Aggregated signature structure
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Hash)]
pub struct AggregatedSignature {
    /// Set of validators who signed
    pub signers: HashSet<ValidatorId>,
    /// Message that was signed
    pub message: BlockHash,
    /// Individual signatures
    pub signatures: HashSet<Signature>,
    /// Whether the aggregated signature is valid
    pub valid: bool,
}

/// Certificate for block finalization
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Hash)]
pub struct Certificate {
    /// Slot number for the certificate
    pub slot: SlotNumber,
    /// View number when certificate was generated
    pub view: ViewNumber,
    /// Block hash being certified
    pub block: BlockHash,
    /// Type of certificate
    pub cert_type: CertificateType,
    /// Aggregated signatures from validators
    pub signatures: AggregatedSignature,
    /// Set of validators that contributed to certificate
    pub validators: HashSet<ValidatorId>,
    /// Total stake represented by the certificate
    pub stake: StakeAmount,
}

/// Voting round state for a specific view
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Hash)]
pub struct VotingRound {
    /// View number for this round
    pub view: ViewNumber,
    /// Blocks proposed in this view
    pub proposed_blocks: HashSet<Block>,
    /// Votes received for this view
    pub received_votes: HashSet<Vote>,
    /// Skip votes received for this view
    pub skip_votes: HashSet<Vote>,
    /// Whether this validator has voted in this view
    pub has_voted: bool,
    /// Timeout expiry time for this view
    pub timeout_expiry: u64,
    /// Whether timeout has been triggered
    pub timeout_triggered: bool,
}

impl VotingRound {
    /// Create a new voting round
    pub fn new(view: ViewNumber, timeout_duration: TimeoutMs, current_time: u64) -> Self {
        Self {
            view,
            proposed_blocks: HashSet::new(),
            received_votes: HashSet::new(),
            skip_votes: HashSet::new(),
            has_voted: false,
            timeout_expiry: current_time + timeout_duration,
            timeout_triggered: false,
        }
    }
    
    /// Check if timeout has expired
    pub fn is_timeout_expired(&self, current_time: u64) -> bool {
        current_time >= self.timeout_expiry
    }
    
    /// Add a vote to this round
    pub fn add_vote(&mut self, vote: Vote) {
        if vote.vote_type == VoteType::Skip {
            self.skip_votes.insert(vote);
        } else {
            self.received_votes.insert(vote);
        }
    }
    
    /// Get votes for a specific block
    pub fn get_votes_for_block(&self, block_hash: BlockHash) -> HashSet<Vote> {
        self.received_votes
            .iter()
            .filter(|vote| vote.block == block_hash)
            .cloned()
            .collect()
    }
    
    /// Calculate total stake for votes on a block
    pub fn calculate_stake_for_block(&self, block_hash: BlockHash, config: &Config) -> StakeAmount {
        let voters: HashSet<ValidatorId> = self.received_votes
            .iter()
            .filter(|vote| vote.block == block_hash)
            .map(|vote| vote.voter)
            .collect();
        
        voters
            .iter()
            .map(|validator| config.stake_distribution.get(validator).copied().unwrap_or(0))
            .sum()
    }
    
    /// Calculate total stake for skip votes
    pub fn calculate_skip_stake(&self, config: &Config) -> StakeAmount {
        let skip_voters: HashSet<ValidatorId> = self.skip_votes
            .iter()
            .map(|vote| vote.voter)
            .collect();
        
        skip_voters
            .iter()
            .map(|validator| config.stake_distribution.get(validator).copied().unwrap_or(0))
            .sum()
    }
}

/// Messages that can be sent to/from Votor actors
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Hash)]
pub enum VotorMessage {
    /// Propose a new block
    ProposeBlock {
        block: Block,
    },
    /// Cast a vote for a block
    CastVote {
        vote: Vote,
    },
    /// Request to generate certificate from collected votes
    GenerateCertificate {
        view: ViewNumber,
        block_hash: BlockHash,
    },
    /// Finalize a block with certificate
    FinalizeBlock {
        certificate: Certificate,
    },
    /// Trigger timeout for current view
    TriggerTimeout,
    /// Submit skip vote due to timeout
    SubmitSkipVote {
        view: ViewNumber,
    },
    /// Advance to next view
    AdvanceView {
        new_view: ViewNumber,
    },
    /// Clock tick for timing
    ClockTick {
        current_time: u64,
    },
    /// Byzantine behavior: double vote
    ByzantineDoubleVote {
        vote1: Vote,
        vote2: Vote,
    },
    /// Byzantine behavior: invalid certificate
    ByzantineInvalidCert {
        certificate: Certificate,
    },
    /// Byzantine behavior: withhold vote
    ByzantineWithholdVote {
        view: ViewNumber,
    },
}

/// State of a Votor consensus actor - mirrors TLA+ Votor state variables exactly
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Hash)]
pub struct VotorState {
    /// Validator ID for this actor
    pub validator_id: ValidatorId,
    /// Protocol configuration
    pub config: Config,
    /// Current view number - mirrors TLA+ view[validator]
    pub current_view: ViewNumber,
    /// Blocks that this validator has voted for - mirrors TLA+ votedBlocks[validator][view]
    pub voted_blocks: HashMap<ViewNumber, HashSet<Block>>,
    /// Votes received by this validator - mirrors TLA+ receivedVotes[validator][view]
    pub received_votes: HashMap<ViewNumber, HashSet<Vote>>,
    /// Generated certificates indexed by view number - mirrors TLA+ generatedCerts[view]
    pub generated_certificates: HashMap<ViewNumber, HashSet<Certificate>>,
    /// Finalized blockchain - mirrors TLA+ finalizedChain
    pub finalized_chain: Vec<Block>,
    /// Skip votes for timeout handling - mirrors TLA+ skipVotes[validator][view]
    pub skip_votes: HashMap<ViewNumber, HashSet<Vote>>,
    /// Timeout expiry times - mirrors TLA+ timeoutExpiry[validator]
    pub timeout_expiry: TimeoutMs,
    /// Current logical time - mirrors TLA+ currentTime
    pub current_time: u64,
    /// Current leader window index - mirrors TLA+ currentLeaderWindow
    pub current_leader_window: u64,
    /// Whether this validator is Byzantine
    pub is_byzantine: bool,
    /// Set of Byzantine validators (for simulation)
    pub byzantine_validators: HashSet<ValidatorId>,
    /// VRF key pairs for leader selection
    pub vrf_key_pairs: HashMap<ValidatorId, VRFKeyPair>,
    /// VRF proofs generated by validators
    pub vrf_proofs: HashSet<VRFProof>,
    /// Voting rounds indexed by view number (for compatibility)
    pub voting_rounds: HashMap<ViewNumber, VotingRound>,
}

impl VotorState {
    /// Create a new Votor state - mirrors TLA+ Init
    pub fn new(validator_id: ValidatorId, config: Config) -> Self {
        let mut state = Self {
            validator_id,
            config: config.clone(),
            current_view: 1,
            voted_blocks: HashMap::new(),
            received_votes: HashMap::new(),
            generated_certificates: HashMap::new(),
            finalized_chain: Vec::new(),
            skip_votes: HashMap::new(),
            timeout_expiry: BASE_TIMEOUT,
            current_time: 0,
            current_leader_window: 0,
            is_byzantine: false,
            byzantine_validators: HashSet::new(),
            vrf_key_pairs: HashMap::new(),
            vrf_proofs: HashSet::new(),
            voting_rounds: HashMap::new(),
        };
        
        // Initialize VRF key pairs for all validators
        for validator in 0..config.validator_count {
            let validator_id = validator as ValidatorId;
            let key_pair = state.generate_vrf_key_pair(validator_id, 12345); // Fixed seed for determinism
            state.vrf_key_pairs.insert(validator_id, key_pair);
        }
        
        // Initialize first voting round
        let timeout_duration = state.adaptive_timeout(1);
        let round = VotingRound::new(1, timeout_duration, 0);
        state.voting_rounds.insert(1, round);
        
        // Initialize timeout expiry with adaptive timeout
        state.timeout_expiry = state.current_time + state.adaptive_timeout(1);
        
        state
    }
    
    /// Set Byzantine behavior for this validator
    pub fn set_byzantine(&mut self, byzantine_validators: HashSet<ValidatorId>) {
        self.is_byzantine = byzantine_validators.contains(&self.validator_id);
        self.byzantine_validators = byzantine_validators;
    }
    
    /// Generate VRF key pair for a validator - mirrors TLA+ VRFGenerateKeyPair
    pub fn generate_vrf_key_pair(&self, validator: ValidatorId, seed: u64) -> VRFKeyPair {
        let private_key = (validator as u64 * seed * 7919) % 999999;
        let public_key = (private_key * 2) % 999999;
        
        VRFKeyPair {
            validator,
            public_key,
            private_key,
            valid: true,
        }
    }
    
    /// VRF evaluation function - mirrors TLA+ VRFEvaluate
    pub fn vrf_evaluate(&self, private_key: u64, input: u64) -> u64 {
        let max_vrf_output = 999999;
        let hash1 = (private_key * input * 991) % max_vrf_output;
        let hash2 = (hash1 * 997 + input * 983) % max_vrf_output;
        (hash1 + hash2) % max_vrf_output
    }
    
    /// Generate VRF proof - mirrors TLA+ VRFProve
    pub fn vrf_prove(&self, validator: ValidatorId, input: u64) -> Option<VRFProof> {
        if let Some(key_pair) = self.vrf_key_pairs.get(&validator) {
            let output = self.vrf_evaluate(key_pair.private_key, input);
            let proof = (key_pair.private_key * input * output * 7919) % 999999;
            
            Some(VRFProof {
                validator,
                input,
                output,
                proof,
                public_key: key_pair.public_key,
                valid: true,
            })
        } else {
            None
        }
    }
    
    /// Verify VRF proof - mirrors TLA+ VRFVerify
    pub fn vrf_verify(&self, public_key: u64, input: u64, proof: u64, output: u64) -> bool {
        let expected_proof_hash = (public_key * input * output * 7919) % 999999;
        let deterministic_output = self.vrf_evaluate(public_key / 2, input); // Derive private key
        
        proof == expected_proof_hash && output == deterministic_output
    }
    
    /// Adaptive timeout using leader window based exponential backoff - mirrors TLA+ AdaptiveTimeout
    pub fn adaptive_timeout(&self, view: ViewNumber) -> TimeoutMs {
        BASE_TIMEOUT * (2_u64.pow((view / LEADER_WINDOW_SIZE) as u32))
    }
    
    /// Calculate timeout duration for a view (backward compatibility)
    pub fn calculate_timeout_duration(&self, view: ViewNumber) -> TimeoutMs {
        self.adaptive_timeout(view)
    }
    
    /// Cast vote for a block - mirrors TLA+ CastVote action
    pub fn cast_vote(&mut self, block: &Block, view: ViewNumber) -> AlpenglowResult<Vote> {
        if !self.validate_vote_message(self.validator_id, view, block.slot, block.hash) {
            return Err(AlpenglowError::ProtocolViolation("Invalid vote message".to_string()));
        }
        
        if view != self.current_view {
            return Err(AlpenglowError::ProtocolViolation("Vote view mismatch".to_string()));
        }
        
        let vote = Vote {
            voter: self.validator_id,
            slot: block.slot,
            view,
            block: block.hash,
            vote_type: VoteType::Commit,
            signature: self.validator_id as u64, // Simplified signature
            timestamp: self.current_time,
        };
        
        // Add to received votes
        self.received_votes
            .entry(view)
            .or_default()
            .insert(vote.clone());
            
        // Add to voted blocks
        self.voted_blocks
            .entry(view)
            .or_default()
            .insert(block.clone());
        
        Ok(vote)
    }
    
    /// Collect votes and generate certificate - mirrors TLA+ CollectVotes action
    pub fn collect_votes(&mut self, view: ViewNumber) -> AlpenglowResult<Option<Certificate>> {
        if view != self.current_view {
            return Err(AlpenglowError::ProtocolViolation("Collect votes view mismatch".to_string()));
        }
        
        let votes_for_view = self.received_votes.get(&view).cloned().unwrap_or_default();
        let voted_stake = self.sum_stake(&votes_for_view.iter().map(|v| v.voter).collect());
        let total_stake = self.config.total_stake;
        let fast_threshold = (total_stake * 4) / 5; // 80% for fast path
        let slow_threshold = (total_stake * 3) / 5; // 60% for slow path
        
        if voted_stake >= slow_threshold && !votes_for_view.is_empty() {
            let first_vote = votes_for_view.iter().next().unwrap();
            let block_hash = first_vote.block;
            
            let cert_type = if voted_stake >= fast_threshold {
                CertificateType::Fast
            } else {
                CertificateType::Slow
            };
            
            let validators: HashSet<ValidatorId> = votes_for_view.iter().map(|v| v.voter).collect();
            let signatures: HashSet<Signature> = votes_for_view.iter().map(|v| v.signature).collect();
            
            let aggregated_sig = AggregatedSignature {
                signers: validators.clone(),
                message: block_hash,
                signatures,
                valid: true,
            };
            
            let certificate = Certificate {
                slot: first_vote.slot,
                view,
                block: block_hash,
                cert_type,
                signatures: aggregated_sig,
                validators,
                stake: voted_stake,
            };
            
            // Add to generated certificates
            self.generated_certificates
                .entry(view)
                .or_default()
                .insert(certificate.clone());
            
            Ok(Some(certificate))
        } else {
            Ok(None)
        }
    }
    
    /// Generate certificate for a specific block - mirrors TLA+ certificate generation logic
    pub fn generate_certificate(&mut self, view: ViewNumber, block_hash: BlockHash) -> AlpenglowResult<Option<Certificate>> {
        let votes_for_view = self.received_votes.get(&view).cloned().unwrap_or_default();
        let votes_for_block: HashSet<Vote> = votes_for_view
            .iter()
            .filter(|vote| vote.block == block_hash)
            .cloned()
            .collect();
        
        if votes_for_block.is_empty() {
            return Ok(None);
        }
        
        let voted_stake = self.sum_stake(&votes_for_block.iter().map(|v| v.voter).collect());
        let cert_type = if voted_stake >= self.config.fast_path_threshold {
            CertificateType::Fast
        } else if voted_stake >= self.config.slow_path_threshold {
            CertificateType::Slow
        } else {
            return Ok(None); // Insufficient stake
        };
        
        let validators: HashSet<ValidatorId> = votes_for_block.iter().map(|v| v.voter).collect();
        let signatures: HashSet<Signature> = votes_for_block.iter().map(|v| v.signature).collect();
        
        let aggregated_sig = AggregatedSignature {
            signers: validators.clone(),
            message: block_hash,
            signatures,
            valid: true,
        };
        
        let certificate = Certificate {
            slot: votes_for_block.iter().next().unwrap().slot,
            view,
            block: block_hash,
            cert_type,
            signatures: aggregated_sig,
            validators,
            stake: voted_stake,
        };
        
        Ok(Some(certificate))
    }
    
    /// Handle timeout - mirrors TLA+ Timeout action
    pub fn handle_timeout(&mut self) -> AlpenglowResult<()> {
        if self.current_time < self.timeout_expiry {
            return Err(AlpenglowError::ProtocolViolation("Timeout not expired".to_string()));
        }
        
        let current_view = self.current_view;
        let new_view = current_view + 1;
        let new_leader_window = (new_view - 1) / LEADER_WINDOW_SIZE;
        
        // Submit skip vote
        let skip_vote = Vote {
            voter: self.validator_id,
            slot: current_view,
            view: current_view,
            block: [0u8; 32], // No block for skip
            vote_type: VoteType::Skip,
            signature: self.validator_id as u64,
            timestamp: self.current_time,
        };
        
        self.skip_votes
            .entry(current_view)
            .or_default()
            .insert(skip_vote);
        
        // Advance view
        self.current_view = new_view;
        self.timeout_expiry = self.current_time + self.adaptive_timeout(new_view);
        self.current_leader_window = new_leader_window;
        
        Ok(())
    }
    
    /// Submit skip vote - mirrors TLA+ SubmitSkipVote action
    pub fn submit_skip_vote(&mut self, view: ViewNumber) -> AlpenglowResult<Vote> {
        if self.current_time < self.timeout_expiry {
            return Err(AlpenglowError::ProtocolViolation("Timeout not expired for skip vote".to_string()));
        }
        
        if view != self.current_view {
            return Err(AlpenglowError::ProtocolViolation("Skip vote view mismatch".to_string()));
        }
        
        let new_view = view + 1;
        let new_leader_window = (new_view - 1) / LEADER_WINDOW_SIZE;
        
        let skip_vote = Vote {
            voter: self.validator_id,
            slot: view,
            view,
            block: [0u8; 32], // No block for skip
            vote_type: VoteType::Skip,
            signature: self.validator_id as u64,
            timestamp: self.current_time,
        };
        
        // Add skip vote
        self.skip_votes
            .entry(view)
            .or_default()
            .insert(skip_vote.clone());
        
        // Advance view
        self.current_view = new_view;
        self.timeout_expiry = self.current_time + self.adaptive_timeout(new_view);
        self.current_leader_window = new_leader_window;
        
        Ok(skip_vote)
    }
    
    /// Collect skip votes and advance view - mirrors TLA+ CollectSkipVotes action
    pub fn collect_skip_votes(&mut self, view: ViewNumber) -> AlpenglowResult<bool> {
        if view != self.current_view {
            return Err(AlpenglowError::ProtocolViolation("Collect skip votes view mismatch".to_string()));
        }
        
        let skip_votes_for_view = self.skip_votes.get(&view).cloned().unwrap_or_default();
        let skip_voters: HashSet<ValidatorId> = skip_votes_for_view.iter().map(|v| v.voter).collect();
        let skip_stake = self.sum_stake(&skip_voters);
        let total_stake = self.config.total_stake;
        
        if skip_stake >= (2 * total_stake) / 3 { // 2/3+ stake voted to skip
            let new_view = view + 1;
            let new_leader_window = (new_view - 1) / LEADER_WINDOW_SIZE;
            
            self.current_view = new_view;
            self.timeout_expiry = self.current_time + self.adaptive_timeout(new_view);
            self.current_leader_window = new_leader_window;
            
            Ok(true) // View advanced
        } else {
            Ok(false) // Not enough skip votes
        }
    }
    
    /// Validate vote message format - mirrors TLA+ ValidateVoteMessage
    pub fn validate_vote_message(&self, voter: ValidatorId, view: ViewNumber, slot: SlotNumber, block_hash: BlockHash) -> bool {
        voter < self.config.validator_count as ValidatorId &&
        view >= 1 && view <= self.config.max_view &&
        slot >= 1 && slot <= self.config.max_slot
    }
    
    /// Sum stake for a set of validators - mirrors TLA+ SumStake
    pub fn sum_stake(&self, validators: &HashSet<ValidatorId>) -> StakeAmount {
        validators
            .iter()
            .map(|v| self.config.stake_distribution.get(v).copied().unwrap_or(0))
            .sum()
    }
    
    /// Get or create voting round for a view
    pub fn get_or_create_round(&mut self, view: ViewNumber) -> &mut VotingRound {
        if !self.voting_rounds.contains_key(&view) {
            let timeout_duration = self.adaptive_timeout(view);
            let round = VotingRound::new(view, timeout_duration, self.current_time);
            self.voting_rounds.insert(view, round);
        }
        self.voting_rounds.get_mut(&view).unwrap()
    }
    
    /// VRF-based leader selection for a view within a leader window - mirrors TLA+ VRFComputeLeaderForView
    pub fn vrf_compute_leader_for_view(&self, slot: SlotNumber, view: ViewNumber) -> ValidatorId {
        let window_start = (slot / LEADER_WINDOW_SIZE) * LEADER_WINDOW_SIZE;
        let view_in_window = view % LEADER_WINDOW_SIZE;
        let vrf_input = window_start * 1000 + view_in_window;
        
        self.vrf_compute_leader(vrf_input)
    }
    
    /// VRF-based leader computation - mirrors TLA+ VRFComputeLeader
    pub fn vrf_compute_leader(&self, input: u64) -> ValidatorId {
        if self.config.validator_count == 0 {
            return 0;
        }
        
        let mut best_validator = 0;
        let mut best_weighted_value = u64::MAX;
        
        for validator in 0..self.config.validator_count {
            let validator_id = validator as ValidatorId;
            if let Some(vrf_proof) = self.vrf_prove(validator_id, input) {
                let stake = self.config.stake_distribution.get(&validator_id).copied().unwrap_or(0);
                let weighted_value = if stake == 0 {
                    u64::MAX
                } else {
                    (vrf_proof.output * self.config.total_stake) / stake
                };
                
                if weighted_value < best_weighted_value {
                    best_weighted_value = weighted_value;
                    best_validator = validator_id;
                }
            }
        }
        
        best_validator
    }
    
    /// Deterministic leader selection using VRF and leader windows - mirrors TLA+ ComputeLeaderForView
    pub fn compute_leader_for_view(&self, view: ViewNumber) -> ValidatorId {
        let slot = self.get_slot_from_time(self.current_time);
        self.vrf_compute_leader_for_view(slot, view)
    }
    
    /// Get slot from time - mirrors TLA+ GetSlotFromTime
    pub fn get_slot_from_time(&self, time: u64) -> SlotNumber {
        time / 400 + 1 // SlotDuration = 400ms
    }
    
    /// Check if this validator is the leader for a given view - mirrors TLA+ IsLeaderForView
    pub fn is_leader_for_view(&self, view: ViewNumber) -> bool {
        let slot = self.get_slot_from_time(self.current_time);
        self.vrf_is_leader_for_view(self.validator_id, slot, view)
    }
    
    /// VRF-based leader check for view - mirrors TLA+ VRFIsLeaderForView
    pub fn vrf_is_leader_for_view(&self, validator: ValidatorId, slot: SlotNumber, view: ViewNumber) -> bool {
        let window_index = slot / LEADER_WINDOW_SIZE;
        let window_leader = self.vrf_compute_window_leader(window_index);
        let view_leader = self.vrf_rotate_leader_in_window(window_leader, view);
        view_leader == validator
    }
    
    /// Compute leader for 4-slot window - mirrors TLA+ VRFComputeWindowLeader
    pub fn vrf_compute_window_leader(&self, window_index: u64) -> ValidatorId {
        self.vrf_compute_leader(window_index)
    }
    
    /// Rotate leader within window based on view - mirrors TLA+ VRFRotateLeaderInWindow
    pub fn vrf_rotate_leader_in_window(&self, window_leader: ValidatorId, view: ViewNumber) -> ValidatorId {
        if self.config.validator_count == 0 {
            return 0;
        }
        
        // Create deterministic validator list
        let mut validators: Vec<ValidatorId> = (0..self.config.validator_count as ValidatorId).collect();
        validators.sort(); // Ensure deterministic ordering
        
        if let Some(leader_index) = validators.iter().position(|&v| v == window_leader) {
            let rotation_offset = (view % LEADER_WINDOW_SIZE) as usize;
            let new_index = (leader_index + rotation_offset) % validators.len();
            validators[new_index]
        } else {
            0 // Fallback
        }
    }
    
    /// Validate a block proposal
    pub fn validate_block(&self, block: &Block) -> bool {
        // Check basic block structure
        if block.slot == 0 || block.view == 0 {
            return false;
        }
        
        // Check if proposer is valid leader for the view
        if self.compute_leader_for_view(block.view) != block.proposer {
            return false;
        }
        
        // Check parent chain consistency
        if self.finalized_chain.is_empty() {
            // Genesis block case
            block.parent == [0u8; 32]
        } else {
            // Check parent exists in finalized chain
            self.finalized_chain
                .iter()
                .any(|b| b.hash == block.parent)
        }
    }
    
    /// Validate a vote message
    pub fn validate_vote(&self, vote: &Vote) -> bool {
        // Basic validation
        if vote.view == 0 || vote.slot == 0 {
            return false;
        }
        
        // Check if voter is a valid validator
        if !self.config.stake_distribution.contains_key(&vote.voter) {
            return false;
        }
        
        // Skip votes can have zero block hash
        if vote.vote_type == VoteType::Skip {
            return vote.block == [0u8; 32];
        }
        
        // Non-skip votes must reference a valid block
        vote.block != [0u8; 32]
    }
    
    /// Generate certificate from collected votes
    pub fn try_generate_certificate(&mut self, view: ViewNumber, block_hash: BlockHash) -> Option<Certificate> {
        let round = self.voting_rounds.get(&view)?;
        let votes = round.get_votes_for_block(block_hash);
        
        if votes.is_empty() {
            return None;
        }
        
        let stake = round.calculate_stake_for_block(block_hash, &self.config);
        let validators: HashSet<ValidatorId> = votes.iter().map(|v| v.voter).collect();
        let signatures: HashSet<Signature> = votes.iter().map(|v| v.signature).collect();
        
        // Determine certificate type based on stake threshold
        let cert_type = if stake >= self.config.fast_path_threshold {
            CertificateType::Fast
        } else if stake >= self.config.slow_path_threshold {
            CertificateType::Slow
        } else {
            return None; // Insufficient stake
        };
        
        let aggregated_sig = AggregatedSignature {
            signers: validators.clone(),
            message: block_hash,
            signatures,
            valid: true, // In practice, would verify cryptographic validity
        };
        
        Some(Certificate {
            slot: votes.iter().next()?.slot,
            view,
            block: block_hash,
            cert_type,
            signatures: aggregated_sig,
            validators,
            stake,
        })
    }
    
    /// Try to generate skip certificate
    pub fn try_generate_skip_certificate(&mut self, view: ViewNumber) -> Option<Certificate> {
        let round = self.voting_rounds.get(&view)?;
        let skip_stake = round.calculate_skip_stake(&self.config);
        
        if skip_stake < self.config.slow_path_threshold {
            return None;
        }
        
        let validators: HashSet<ValidatorId> = round.skip_votes.iter().map(|v| v.voter).collect();
        let signatures: HashSet<Signature> = round.skip_votes.iter().map(|v| v.signature).collect();
        
        let aggregated_sig = AggregatedSignature {
            signers: validators.clone(),
            message: [0u8; 32], // Skip votes have no block
            signatures,
            valid: true,
        };
        
        Some(Certificate {
            slot: view, // Use view as slot for skip certificates
            view,
            block: [0u8; 32],
            cert_type: CertificateType::Skip,
            signatures: aggregated_sig,
            validators,
            stake: skip_stake,
        })
    }
    
    /// Finalize a block with certificate
    pub fn finalize_block(&mut self, certificate: &Certificate) -> AlpenglowResult<()> {
        // Validate certificate
        if !self.validate_certificate(certificate) {
            return Err(AlpenglowError::ProtocolViolation(
                "Invalid certificate".to_string()
            ));
        }
        
        // Skip certificates don't finalize blocks
        if certificate.cert_type == CertificateType::Skip {
            return Ok(());
        }
        
        // Check for duplicate slot finalization
        if self.finalized_chain.iter().any(|b| b.slot == certificate.slot) {
            return Err(AlpenglowError::ProtocolViolation(
                "Slot already finalized".to_string()
            ));
        }
        
        // Find the block to finalize
        let block = self.voting_rounds
            .values()
            .flat_map(|round| &round.proposed_blocks)
            .find(|b| b.hash == certificate.block)
            .ok_or_else(|| AlpenglowError::ProtocolViolation(
                "Block not found for certificate".to_string()
            ))?;
        
        // Add to finalized chain
        self.finalized_chain.push(block.clone());
        
        Ok(())
    }
    
    /// Validate a certificate
    pub fn validate_certificate(&self, certificate: &Certificate) -> bool {
        // Check basic structure
        if certificate.validators.is_empty() || certificate.stake == 0 {
            return false;
        }
        
        // Check stake threshold
        let required_threshold = match certificate.cert_type {
            CertificateType::Fast => self.config.fast_path_threshold,
            CertificateType::Slow | CertificateType::Skip => self.config.slow_path_threshold,
        };
        
        if certificate.stake < required_threshold {
            return false;
        }
        
        // Verify stake calculation
        let calculated_stake: StakeAmount = certificate.validators
            .iter()
            .map(|v| self.config.stake_distribution.get(v).copied().unwrap_or(0))
            .sum();
        
        certificate.stake == calculated_stake
    }
    
    /// Advance to next view - mirrors TLA+ view advancement logic
    pub fn advance_view(&mut self) {
        self.current_view += 1;
        self.current_leader_window = (self.current_view - 1) / LEADER_WINDOW_SIZE;
        
        // Update timeout with adaptive timeout
        self.timeout_expiry = self.current_time + self.adaptive_timeout(self.current_view);
        
        // Create new voting round for the new view
        let timeout_duration = self.adaptive_timeout(self.current_view);
        let round = VotingRound::new(self.current_view, timeout_duration, self.current_time);
        self.voting_rounds.insert(self.current_view, round);
    }
    
    /// Check if timeout has expired for current view
    pub fn is_timeout_expired(&self) -> bool {
        self.current_time >= self.timeout_expiry
    }
    
    /// Check if any timeouts have expired
    pub fn check_timeouts(&mut self) -> Vec<ViewNumber> {
        let mut expired_views = Vec::new();
        
        // Check current view timeout
        if self.is_timeout_expired() {
            expired_views.push(self.current_view);
        }
        
        // Check voting round timeouts
        for (&view, round) in &mut self.voting_rounds {
            if !round.timeout_triggered && round.is_timeout_expired(self.current_time) {
                round.timeout_triggered = true;
                expired_views.push(view);
            }
        }
        
        expired_views
    }
}

/// Votor consensus actor implementation
#[derive(Debug, Clone)]
pub struct VotorActor {
    /// Validator ID for this actor
    pub validator_id: ValidatorId,
    /// Protocol configuration
    pub config: Config,
}

impl VotorActor {
    /// Create a new Votor actor
    pub fn new(validator_id: ValidatorId, config: Config) -> Self {
        Self {
            validator_id,
            config,
        }
    }
    
    /// Create a block proposal
    fn create_block_proposal(&self, state: &VotorState, view: ViewNumber) -> Block {
        let parent_hash = if state.finalized_chain.is_empty() {
            [0u8; 32] // Genesis
        } else {
            state.finalized_chain.last().unwrap().hash
        };
        
        Block {
            slot: view, // Use view as slot for simplicity
            view,
            hash: self.compute_block_hash(view, parent_hash),
            parent: parent_hash,
            proposer: self.validator_id,
            transactions: HashSet::new(), // Empty for now
            timestamp: state.current_time,
            signature: [0u8; 64], // Placeholder signature
            data: Vec::new(),
        }
    }
    
    /// Compute block hash (simplified)
    fn compute_block_hash(&self, view: ViewNumber, parent: BlockHash) -> BlockHash {
        let mut hash = [0u8; 32];
        hash[0..8].copy_from_slice(&view.to_le_bytes());
        hash[8..16].copy_from_slice(&self.validator_id.to_le_bytes());
        hash[16..24].copy_from_slice(&parent[0..8]);
        hash
    }
    
    /// Create a vote for a block
    fn create_vote(&self, state: &VotorState, block: &Block, vote_type: VoteType) -> Vote {
        Vote {
            voter: self.validator_id,
            slot: block.slot,
            view: block.view,
            block: if vote_type == VoteType::Skip { [0u8; 32] } else { block.hash },
            vote_type,
            signature: [0u8; 64], // Placeholder signature
            timestamp: state.current_time,
        }
    }
    
    /// Create a skip vote
    fn create_skip_vote(&self, state: &VotorState, view: ViewNumber) -> Vote {
        Vote {
            voter: self.validator_id,
            slot: view,
            view,
            block: [0u8; 32],
            vote_type: VoteType::Skip,
            signature: [0u8; 64], // Placeholder signature
            timestamp: state.current_time,
        }
    }
}

impl Actor for VotorActor {
    type Msg = VotorMessage;
    type State = VotorState;
    
    fn on_start(&self, _id: Id, _o: &mut crate::stateright::util::Out<Self>) -> Self::State {
        VotorState::new(self.validator_id, self.config.clone())
    }
    
    fn on_msg(
        &self,
        _id: Id,
        state: &mut Self::State,
        src: Id,
        msg: Self::Msg,
        o: &mut crate::stateright::util::Out<Self>,
    ) {
        match msg {
            VotorMessage::ProposeBlock { block } => {
                // Validate and add block proposal
                if state.validate_block(&block) {
                    let round = state.get_or_create_round(block.view);
                    round.proposed_blocks.insert(block.clone());
                    
                    // If we're not Byzantine, vote for our own proposal
                    if !state.is_byzantine && block.proposer == state.validator_id {
                        let vote = self.create_vote(state, &block, VoteType::Commit);
                        round.add_vote(vote.clone());
                        round.has_voted = true;
                        
                        // Broadcast vote to other validators
                        o.broadcast(&VotorMessage::CastVote { vote });
                    }
                }
            }
            
            VotorMessage::CastVote { vote } => {
                // Validate and process vote
                if state.validate_vote(&vote) {
                    let round = state.get_or_create_round(vote.view);
                    round.add_vote(vote.clone());
                    
                    // Try to generate certificate if we have enough votes
                    if let Some(cert) = state.try_generate_certificate(vote.view, vote.block) {
                        let certs = state.generated_certificates.entry(vote.view).or_insert_with(HashSet::new);
                        certs.insert(cert.clone());
                        
                        // Broadcast certificate for finalization
                        o.broadcast(&VotorMessage::FinalizeBlock { certificate: cert });
                    }
                }
            }
            
            VotorMessage::GenerateCertificate { view, block_hash } => {
                // Try to generate certificate for the specified block
                if let Some(cert) = state.try_generate_certificate(view, block_hash) {
                    let certs = state.generated_certificates.entry(view).or_insert_with(HashSet::new);
                    certs.insert(cert.clone());
                    
                    o.broadcast(&VotorMessage::FinalizeBlock { certificate: cert });
                }
            }
            
            VotorMessage::FinalizeBlock { certificate } => {
                // Attempt to finalize the block
                if let Err(e) = state.finalize_block(&certificate) {
                    // Log error but continue (in practice, would handle more gracefully)
                    eprintln!("Failed to finalize block: {:?}", e);
                }
            }
            
            VotorMessage::TriggerTimeout => {
                // Check for expired timeouts and submit skip votes
                let expired_views = state.check_timeouts();
                for view in expired_views {
                    if view == state.current_view {
                        let skip_vote = self.create_skip_vote(state, view);
                        o.broadcast(&VotorMessage::SubmitSkipVote { view });
                    }
                }
            }
            
            VotorMessage::SubmitSkipVote { view } => {
                // Submit skip vote and try to generate skip certificate
                let skip_vote = self.create_skip_vote(state, view);
                let round = state.get_or_create_round(view);
                round.add_vote(skip_vote);
                
                // Try to generate skip certificate
                if let Some(skip_cert) = state.try_generate_skip_certificate(view) {
                    let certs = state.generated_certificates.entry(view).or_insert_with(HashSet::new);
                    certs.insert(skip_cert);
                    
                    // Advance to next view
                    o.send(src, VotorMessage::AdvanceView { new_view: view + 1 });
                }
            }
            
            VotorMessage::AdvanceView { new_view } => {
                // Advance to the new view - mirrors TLA+ view advancement
                if new_view > state.current_view {
                    state.current_view = new_view;
                    state.current_leader_window = (new_view - 1) / LEADER_WINDOW_SIZE;
                    state.timeout_expiry = state.current_time + state.adaptive_timeout(new_view);
                    
                    let timeout_duration = state.adaptive_timeout(new_view);
                    let round = VotingRound::new(new_view, timeout_duration, state.current_time);
                    state.voting_rounds.insert(new_view, round);
                    
                    // If we're the leader for this view, propose a block
                    if state.is_leader_for_view(new_view) && !state.is_byzantine {
                        let block = self.create_block_proposal(state, new_view);
                        o.broadcast(&VotorMessage::ProposeBlock { block });
                    }
                }
            }
            
            VotorMessage::ClockTick { current_time } => {
                // Update current time and check for timeouts - mirrors TLA+ AdvanceClock
                state.current_time = current_time;
                
                // Update current leader window based on time
                let slot = state.get_slot_from_time(current_time);
                state.current_leader_window = slot / LEADER_WINDOW_SIZE;
                
                let expired_views = state.check_timeouts();
                
                for view in expired_views {
                    o.send(src, VotorMessage::TriggerTimeout);
                }
            }
            
            // Byzantine behaviors
            VotorMessage::ByzantineDoubleVote { vote1, vote2 } => {
                if state.is_byzantine {
                    // Broadcast conflicting votes
                    o.broadcast(&VotorMessage::CastVote { vote: vote1 });
                    o.broadcast(&VotorMessage::CastVote { vote: vote2 });
                }
            }
            
            VotorMessage::ByzantineInvalidCert { certificate } => {
                if state.is_byzantine {
                    // Broadcast invalid certificate
                    o.broadcast(&VotorMessage::FinalizeBlock { certificate });
                }
            }
            
            VotorMessage::ByzantineWithholdVote { view: _ } => {
                if state.is_byzantine {
                    // Simply do nothing (withhold vote)
                }
            }
        }
    }
}

impl Verifiable for VotorState {
    fn verify_safety(&self) -> AlpenglowResult<()> {
        // Safety: No two blocks finalized in the same slot
        let mut slots = HashSet::new();
        for block in &self.finalized_chain {
            if slots.contains(&block.slot) {
                return Err(AlpenglowError::ProtocolViolation(
                    "Two blocks finalized in same slot".to_string()
                ));
            }
            slots.insert(block.slot);
        }
        Ok(())
    }
    
    fn verify_liveness(&self) -> AlpenglowResult<()> {
        // Liveness: Chain should grow under good conditions
        // This is a simplified check - in practice would be more sophisticated
        if self.current_time > 1000 && self.finalized_chain.is_empty() {
            return Err(AlpenglowError::ProtocolViolation(
                "No progress made".to_string()
            ));
        }
        Ok(())
    }
    
    fn verify_byzantine_resilience(&self) -> AlpenglowResult<()> {
        // Byzantine resilience: Safety should hold even with Byzantine validators
        let byzantine_stake: StakeAmount = self.byzantine_validators
            .iter()
            .map(|v| self.config.stake_distribution.get(v).copied().unwrap_or(0))
            .sum();
        
        if byzantine_stake >= self.config.total_stake / 3 {
            return Err(AlpenglowError::ProtocolViolation(
                "Too many Byzantine validators".to_string()
            ));
        }
        
        self.verify_safety()
    }
}

impl TlaCompatible for VotorState {
    fn export_tla_state(&self) -> serde_json::Value {
        serde_json::json!({
            "validator_id": self.validator_id,
            "current_view": self.current_view,
            "finalized_chain_length": self.finalized_chain.len(),
            "voting_rounds": self.voting_rounds.len(),
            "generated_certificates": self.generated_certificates.values().map(|certs| certs.len()).sum::<usize>(),
            "current_time": self.current_time,
            "is_byzantine": self.is_byzantine
        })
    }
    
    fn import_tla_state(&mut self, _state: serde_json::Value) -> AlpenglowResult<()> {
        // Implementation would parse TLA+ state and update internal state
        // This is a placeholder for cross-validation functionality
        Ok(())
    }
    
    fn validate_tla_invariants(&self) -> AlpenglowResult<()> {
        // Validate key invariants from TLA+ specification
        self.verify_safety()?;
        
        // Additional TLA+ specific invariants
        for round in self.voting_rounds.values() {
            // Honest validators vote at most once per view
            let mut voter_counts = HashMap::new();
            for vote in &round.received_votes {
                if !self.byzantine_validators.contains(&vote.voter) {
                    *voter_counts.entry(vote.voter).or_insert(0) += 1;
                    if voter_counts[&vote.voter] > 1 {
                        return Err(AlpenglowError::ProtocolViolation(
                            "Honest validator voted multiple times".to_string()
                        ));
                    }
                }
            }
        }
        
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Config;
    
    #[test]
    fn test_votor_state_creation() {
        let config = Config::new().with_validators(4);
        let state = VotorState::new(0, config);
        
        assert_eq!(state.validator_id, 0);
        assert_eq!(state.current_view, 1);
        assert!(state.finalized_chain.is_empty());
        assert_eq!(state.voting_rounds.len(), 1);
    }
    
    #[test]
    fn test_leader_selection() {
        let config = Config::new().with_validators(4);
        let state = VotorState::new(0, config);
        
        // Leader selection should be deterministic
        let leader1 = state.compute_leader_for_view(1);
        let leader2 = state.compute_leader_for_view(1);
        assert_eq!(leader1, leader2);
        
        // Different views may have different leaders
        let leader_view2 = state.compute_leader_for_view(2);
        // May or may not be different, but should be deterministic
        assert_eq!(leader_view2, state.compute_leader_for_view(2));
    }
    
    #[test]
    fn test_adaptive_timeout() {
        let config = Config::new().with_validators(4);
        let state = VotorState::new(0, config);
        
        // Timeout should increase exponentially by leader window
        let timeout1 = state.adaptive_timeout(1);
        let timeout5 = state.adaptive_timeout(5); // Next window (5/4 = 1)
        let timeout9 = state.adaptive_timeout(9); // Next window (9/4 = 2)
        
        assert_eq!(timeout1, 100); // Base timeout
        assert_eq!(timeout5, 200); // 2x base (window 1)
        assert_eq!(timeout9, 400); // 4x base (window 2)
    }
    
    #[test]
    fn test_vrf_leader_selection() {
        let config = Config::new().with_validators(4);
        let state = VotorState::new(0, config);
        
        // VRF leader selection should be deterministic
        let leader1 = state.vrf_compute_leader_for_view(1, 1);
        let leader2 = state.vrf_compute_leader_for_view(1, 1);
        assert_eq!(leader1, leader2);
        
        // Different inputs should potentially give different leaders
        let leader_diff_slot = state.vrf_compute_leader_for_view(2, 1);
        let leader_diff_view = state.vrf_compute_leader_for_view(1, 2);
        
        // Results should be deterministic
        assert_eq!(leader_diff_slot, state.vrf_compute_leader_for_view(2, 1));
        assert_eq!(leader_diff_view, state.vrf_compute_leader_for_view(1, 2));
    }
    
    #[test]
    fn test_leader_window_rotation() {
        let config = Config::new().with_validators(4);
        let state = VotorState::new(0, config);
        
        // Test leader rotation within window
        let window_leader = state.vrf_compute_window_leader(0);
        let view1_leader = state.vrf_rotate_leader_in_window(window_leader, 1);
        let view2_leader = state.vrf_rotate_leader_in_window(window_leader, 2);
        
        // Leaders should be deterministic
        assert_eq!(view1_leader, state.vrf_rotate_leader_in_window(window_leader, 1));
        assert_eq!(view2_leader, state.vrf_rotate_leader_in_window(window_leader, 2));
    }
    
    #[test]
    fn test_cast_vote() {
        let config = Config::new().with_validators(4);
        let mut state = VotorState::new(0, config);
        
        let block = Block {
            slot: 1,
            view: 1,
            hash: [1u8; 32],
            parent: [0u8; 32],
            proposer: 0,
            transactions: HashSet::new(),
            timestamp: 0,
            signature: [0u8; 64],
            data: Vec::new(),
        };
        
        let vote_result = state.cast_vote(&block, 1);
        assert!(vote_result.is_ok());
        
        let vote = vote_result.unwrap();
        assert_eq!(vote.voter, 0);
        assert_eq!(vote.view, 1);
        assert_eq!(vote.block, block.hash);
        
        // Check that vote was added to state
        assert!(state.received_votes.get(&1).unwrap().contains(&vote));
        assert!(state.voted_blocks.get(&1).unwrap().contains(&block));
    }
    
    #[test]
    fn test_collect_votes() {
        let config = Config::new().with_validators(4);
        let mut state = VotorState::new(0, config);
        
        // Add votes from all validators
        let block_hash = [1u8; 32];
        let mut votes = HashSet::new();
        for i in 0..4 {
            let vote = Vote {
                voter: i,
                slot: 1,
                view: 1,
                block: block_hash,
                vote_type: VoteType::Commit,
                signature: [0u8; 64],
                timestamp: 0,
            };
            votes.insert(vote);
        }
        state.received_votes.insert(1, votes);
        
        let cert_result = state.collect_votes(1);
        assert!(cert_result.is_ok());
        
        let cert_opt = cert_result.unwrap();
        assert!(cert_opt.is_some());
        
        let cert = cert_opt.unwrap();
        assert_eq!(cert.cert_type, CertificateType::Fast);
        assert_eq!(cert.validators.len(), 4);
    }
    
    #[test]
    fn test_handle_timeout() {
        let config = Config::new().with_validators(4);
        let mut state = VotorState::new(0, config);
        
        // Set time past timeout
        state.current_time = state.timeout_expiry + 1;
        
        let result = state.handle_timeout();
        assert!(result.is_ok());
        
        // View should have advanced
        assert_eq!(state.current_view, 2);
        
        // Skip vote should have been added
        assert!(!state.skip_votes.get(&1).unwrap().is_empty());
    }
    
    #[test]
    fn test_submit_skip_vote() {
        let config = Config::new().with_validators(4);
        let mut state = VotorState::new(0, config);
        
        // Set time past timeout
        state.current_time = state.timeout_expiry + 1;
        
        let skip_vote_result = state.submit_skip_vote(1);
        assert!(skip_vote_result.is_ok());
        
        let skip_vote = skip_vote_result.unwrap();
        assert_eq!(skip_vote.vote_type, VoteType::Skip);
        assert_eq!(skip_vote.view, 1);
        assert_eq!(skip_vote.block, [0u8; 32]);
        
        // View should have advanced
        assert_eq!(state.current_view, 2);
    }
    
    #[test]
    fn test_vote_validation() {
        let config = Config::new().with_validators(4);
        let state = VotorState::new(0, config);
        
        let valid_vote = Vote {
            voter: 0,
            slot: 1,
            view: 1,
            block: [1u8; 32],
            vote_type: VoteType::Commit,
            signature: [0u8; 64],
            timestamp: 0,
        };
        
        assert!(state.validate_vote(&valid_vote));
        
        let invalid_vote = Vote {
            voter: 999, // Invalid validator
            slot: 1,
            view: 1,
            block: [1u8; 32],
            vote_type: VoteType::Commit,
            signature: [0u8; 64],
            timestamp: 0,
        };
        
        assert!(!state.validate_vote(&invalid_vote));
    }
    
    #[test]
    fn test_certificate_generation() {
        let config = Config::new().with_validators(4);
        let mut state = VotorState::new(0, config);
        
        // Create a voting round
        let round = state.get_or_create_round(1);
        
        // Add votes from all validators (should exceed fast path threshold)
        let block_hash = [1u8; 32];
        for i in 0..4 {
            let vote = Vote {
                voter: i,
                slot: 1,
                view: 1,
                block: block_hash,
                vote_type: VoteType::Commit,
                signature: [0u8; 64],
                timestamp: 0,
            };
            round.add_vote(vote);
        }
        
        // Should be able to generate fast path certificate
        let cert = state.try_generate_certificate(1, block_hash);
        assert!(cert.is_some());
        
        let cert = cert.unwrap();
        assert_eq!(cert.cert_type, CertificateType::Fast);
        assert_eq!(cert.validators.len(), 4);
    }
    
    #[test]
    fn test_safety_verification() {
        let config = Config::new().with_validators(4);
        let state = VotorState::new(0, config);
        
        // Empty chain should be safe
        assert!(state.verify_safety().is_ok());
        
        // Single block should be safe
        let mut state_with_block = state.clone();
        let block = Block {
            slot: 1,
            view: 1,
            hash: [1u8; 32],
            parent: [0u8; 32],
            proposer: 0,
            transactions: HashSet::new(),
            timestamp: 0,
            signature: [0u8; 64],
            data: Vec::new(),
        };
        state_with_block.finalized_chain.push(block);
        
        assert!(state_with_block.verify_safety().is_ok());
    }
}
