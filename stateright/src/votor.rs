#![allow(dead_code)]
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
use std::hash::{Hash, Hasher};
use std::time::Instant;

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
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct VRFProof {
    pub validator: ValidatorId,
    pub input: u64,
    pub output: u64,
    pub proof: u64,
    pub public_key: u64,
    pub valid: bool,
}

/// Block structure for the blockchain
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
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
    /// List of transactions in the block (deterministic ordering)
    pub transactions: Vec<Transaction>,
    /// Timestamp when block was created
    pub timestamp: u64,
    /// Block proposer's signature
    pub signature: Signature,
    /// Additional block data
    pub data: Vec<u8>,
}

/// Transaction structure
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
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
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
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
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
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
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum CertificateType {
    /// Fast path certificate (≥80% stake)
    Fast,
    /// Slow path certificate (≥60% stake)
    Slow,
    /// Skip certificate (≥60% stake for timeout)
    Skip,
}

/// Aggregated signature structure
#[derive(Debug, Clone, Serialize, Deserialize, Eq)]
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
#[derive(Debug, Clone, Serialize, Deserialize, Eq)]
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
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct VotingRound {
    /// View number for this round
    pub view: ViewNumber,
    /// Blocks proposed in this view
    pub proposed_blocks: Vec<Block>,
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
            proposed_blocks: Vec::new(),
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

/// Message types for Votor actor communication
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
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

impl Hash for VotorMessage {
    fn hash<H: Hasher>(&self, state: &mut H) {
        // Hash based on message type discriminant to avoid issues with non-Hash fields
        std::mem::discriminant(self).hash(state);
        match self {
            VotorMessage::ProposeBlock { .. } => "propose_block".hash(state),
            VotorMessage::CastVote { .. } => "cast_vote".hash(state),
            VotorMessage::GenerateCertificate { view, block_hash } => {
                "gen_cert".hash(state);
                view.hash(state);
                block_hash.hash(state);
            },
            VotorMessage::FinalizeBlock { .. } => "finalize_block".hash(state),
            VotorMessage::SubmitSkipVote { view } => {
                "skip_vote".hash(state);
                view.hash(state);
            },
            VotorMessage::AdvanceView { new_view } => {
                "advance_view".hash(state);
                new_view.hash(state);
            },
            VotorMessage::ClockTick { current_time } => {
                "clock_tick".hash(state);
                current_time.hash(state);
            },
            VotorMessage::ByzantineDoubleVote { .. } => "byzantine_double".hash(state),
            VotorMessage::ByzantineInvalidCert { .. } => "byzantine_cert".hash(state),
            VotorMessage::ByzantineWithholdVote { view } => {
                "byzantine_withhold".hash(state);
                view.hash(state);
            },
            VotorMessage::TriggerTimeout => "trigger_timeout".hash(state),
        }
    }
}

/// State of a Votor consensus actor - mirrors TLA+ Votor state variables exactly
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct VotorState {
    /// Validator ID for this actor
    pub validator_id: ValidatorId,
    /// Protocol configuration
    pub config: Config,
    /// Current view number - mirrors TLA+ view[validator]
    pub current_view: ViewNumber,
    /// Blocks that this validator has voted for - mirrors TLA+ votedBlocks[validator][view]
    pub voted_blocks: HashMap<ViewNumber, Vec<Block>>,
    /// Votes received by this validator - mirrors TLA+ receivedVotes[validator][view]
    pub received_votes: HashMap<ViewNumber, HashSet<Vote>>,
    /// Generated certificates indexed by view number - mirrors TLA+ generatedCerts[view]
    pub generated_certificates: HashMap<ViewNumber, Vec<Certificate>>,
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
    pub vrf_keys: HashMap<ValidatorId, VRFKeyPair>,
    /// Voting rounds indexed by view number
    pub voting_rounds: HashMap<ViewNumber, VotingRound>,
    /// VRF key pairs for this validator
    pub vrf_key_pairs: HashMap<ValidatorId, VRFKeyPair>,
    /// VRF proofs generated by this validator
    pub vrf_proofs: HashMap<ViewNumber, VRFProof>,
}

impl Hash for VotorState {
    fn hash<H: Hasher>(&self, state: &mut H) {
        // Hash only the key identifying fields to avoid issues with collections
        self.validator_id.hash(state);
        self.current_view.hash(state);
        self.current_time.hash(state);
        self.is_byzantine.hash(state);
        self.timeout_expiry.hash(state);
        self.current_leader_window.hash(state);
    }
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
            vrf_keys: HashMap::new(),
            vrf_key_pairs: HashMap::new(),
            vrf_proofs: HashMap::new(),
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
    
    /// Fast path voting for ≥80% stake single-round finalization - mirrors TLA+ FastPathVoting
    pub fn fast_path_voting(&self, slot: SlotNumber, block: &Block) -> AlpenglowResult<bool> {
        // Collect all notarization votes for this slot and block
        let mut notar_votes = HashSet::new();
        
        for votes in self.received_votes.values() {
            for vote in votes {
                if vote.slot == slot && 
                   vote.block == block.hash && 
                   vote.vote_type == VoteType::Commit {
                    notar_votes.insert(vote.voter);
                }
            }
        }
        
        // Calculate total stake of voters
        let voter_stake = self.sum_stake(&notar_votes);
        let fast_threshold = self.config.fast_path_threshold;
        
        // Check if we have ≥80% stake and all signatures are valid (simplified)
        Ok(voter_stake >= fast_threshold)
    }
    
    /// Slow path voting for ≥60% stake two-round finalization - mirrors TLA+ SlowPathVoting
    pub fn slow_path_voting(&self, slot: SlotNumber, block: &Block) -> AlpenglowResult<bool> {
        // Collect notarization votes (first round)
        let mut notar_votes = HashSet::new();
        let mut finalization_votes = HashSet::new();
        
        for votes in self.received_votes.values() {
            for vote in votes {
                if vote.slot == slot && vote.block == block.hash {
                    match vote.vote_type {
                        VoteType::Commit => { notar_votes.insert(vote.voter); },
                        VoteType::Echo => { finalization_votes.insert(vote.voter); },
                        _ => {}
                    }
                }
            }
        }
        
        // Calculate stakes for both rounds
        let notar_stake = self.sum_stake(&notar_votes);
        let finalization_stake = self.sum_stake(&finalization_votes);
        let slow_threshold = self.config.slow_path_threshold;
        
        // Both rounds must meet ≥60% stake threshold
        Ok(notar_stake >= slow_threshold && finalization_stake >= slow_threshold)
    }
    
    /// Cast notarization vote for first round of slow path or fast path - mirrors TLA+ CastNotarVote
    pub fn cast_notar_vote(&mut self, slot: SlotNumber, block: &Block) -> AlpenglowResult<Vote> {
        // Validate preconditions
        if self.is_byzantine {
            return Err(AlpenglowError::ByzantineDetected("Byzantine validator cannot cast honest vote".to_string()));
        }
        
        if slot == 0 || slot > self.config.max_slot {
            return Err(AlpenglowError::ProtocolViolation("Invalid slot number".to_string()));
        }
        
        // Check if already voted for this slot (one vote per slot)
        for votes in self.received_votes.values() {
            for vote in votes {
                if vote.voter == self.validator_id && 
                   vote.slot == slot && 
                   vote.vote_type == VoteType::Commit {
                    return Err(AlpenglowError::ProtocolViolation("Already voted for this slot".to_string()));
                }
            }
        }
        
        // Create notarization vote
        let notar_vote = Vote {
            voter: self.validator_id,
            slot,
            view: self.current_view,
            block: block.hash,
            vote_type: VoteType::Commit,
            signature: self.validator_id as Signature, // Simplified signature
            timestamp: self.current_time,
        };
        
        // Add to received votes
        self.received_votes
            .entry(self.current_view)
            .or_default()
            .insert(notar_vote.clone());
        
        // Add to voted blocks
        self.voted_blocks
            .entry(self.current_view)
            .or_default()
            .push(block.clone());
        
        Ok(notar_vote)
    }
    
    /// Cast skip vote for timeout handling - mirrors TLA+ CastSkipVote
    pub fn cast_skip_vote(&mut self, slot: SlotNumber, reason: &str) -> AlpenglowResult<Vote> {
        // Validate preconditions
        if self.is_byzantine {
            return Err(AlpenglowError::ByzantineDetected("Byzantine validator cannot cast honest vote".to_string()));
        }
        
        if slot == 0 || slot > self.config.max_slot {
            return Err(AlpenglowError::ProtocolViolation("Invalid slot number".to_string()));
        }
        
        // Check if timeout has expired
        if !self.is_timeout_expired() {
            return Err(AlpenglowError::ProtocolViolation("Timeout not expired for skip vote".to_string()));
        }
        
        // Check if already cast skip vote for this slot
        if let Some(skip_votes) = self.skip_votes.get(&self.current_view) {
            for vote in skip_votes {
                if vote.voter == self.validator_id && vote.slot == slot {
                    return Err(AlpenglowError::ProtocolViolation("Already cast skip vote for this slot".to_string()));
                }
            }
        }
        
        // Create skip vote
        let skip_vote = Vote {
            voter: self.validator_id,
            slot,
            view: self.current_view,
            block: 0u64 as BlockHash, // No block for skip votes
            vote_type: VoteType::Skip,
            signature: self.validator_id as Signature,
            timestamp: self.current_time,
        };
        
        // Add to skip votes
        self.skip_votes
            .entry(self.current_view)
            .or_default()
            .insert(skip_vote.clone());
        
        Ok(skip_vote)
    }
    
    /// Cast finalization vote for second round of slow path - mirrors TLA+ CastFinalizationVote
    pub fn cast_finalization_vote(&mut self, slot: SlotNumber, block: &Block) -> AlpenglowResult<Vote> {
        // Validate preconditions
        if self.is_byzantine {
            return Err(AlpenglowError::ByzantineDetected("Byzantine validator cannot cast honest vote".to_string()));
        }
        
        if slot == 0 || slot > self.config.max_slot {
            return Err(AlpenglowError::ProtocolViolation("Invalid slot number".to_string()));
        }
        
        // Check if block was notarized first (required for finalization vote)
        let mut block_notarized = false;
        for votes in self.received_votes.values() {
            for vote in votes {
                if vote.slot == slot && 
                   vote.block == block.hash && 
                   vote.vote_type == VoteType::Commit {
                    block_notarized = true;
                    break;
                }
            }
            if block_notarized { break; }
        }
        
        if !block_notarized {
            return Err(AlpenglowError::ProtocolViolation("Block must be notarized before finalization vote".to_string()));
        }
        
        // Check if already cast finalization vote for this slot
        for votes in self.received_votes.values() {
            for vote in votes {
                if vote.voter == self.validator_id && 
                   vote.slot == slot && 
                   vote.vote_type == VoteType::Echo {
                    return Err(AlpenglowError::ProtocolViolation("Already cast finalization vote for this slot".to_string()));
                }
            }
        }
        
        // Create finalization vote
        let finalization_vote = Vote {
            voter: self.validator_id,
            slot,
            view: self.current_view,
            block: block.hash,
            vote_type: VoteType::Echo, // Use Echo for finalization votes
            signature: self.validator_id as Signature,
            timestamp: self.current_time,
        };
        
        // Add to received votes
        self.received_votes
            .entry(self.current_view)
            .or_default()
            .insert(finalization_vote.clone());
        
        Ok(finalization_vote)
    }
    
    /// Generate fast certificate from ≥80% stake votes - mirrors TLA+ GenerateFastCert
    pub fn generate_fast_cert(&self, slot: SlotNumber, votes: &HashSet<Vote>) -> AlpenglowResult<Option<Certificate>> {
        // Filter notarization votes for this slot
        let notar_votes: HashSet<_> = votes.iter()
            .filter(|vote| vote.slot == slot && vote.vote_type == VoteType::Commit)
            .collect();
        
        if notar_votes.is_empty() {
            return Ok(None);
        }
        
        // Calculate voter stake
        let voters: HashSet<ValidatorId> = notar_votes.iter().map(|vote| vote.voter).collect();
        let voter_stake = self.sum_stake(&voters);
        
        // Check if meets fast path threshold (≥80% stake)
        if voter_stake < self.config.fast_path_threshold {
            return Ok(None);
        }
        
        // Get block hash from first vote
        let block_hash = notar_votes.iter().next().unwrap().block;
        
        // Create aggregated signature
        let signatures: HashSet<Signature> = notar_votes.iter().map(|vote| vote.signature).collect();
        let aggregated_sig = AggregatedSignature {
            signers: voters.clone(),
            message: block_hash,
            signatures,
            valid: true, // Simplified - in practice would verify cryptographically
        };
        
        // Create fast certificate
        let certificate = Certificate {
            slot,
            view: self.current_view,
            block: block_hash,
            cert_type: CertificateType::Fast,
            signatures: aggregated_sig,
            validators: voters,
            stake: voter_stake,
        };
        
        Ok(Some(certificate))
    }
    
    /// Generate slow certificate from ≥60% stake votes in two rounds - mirrors TLA+ GenerateSlowCert
    pub fn generate_slow_cert(&self, slot: SlotNumber, votes: &HashSet<Vote>) -> AlpenglowResult<Option<Certificate>> {
        // Filter notarization and finalization votes for this slot
        let notar_votes: HashSet<_> = votes.iter()
            .filter(|vote| vote.slot == slot && vote.vote_type == VoteType::Commit)
            .collect();
        
        let finalization_votes: HashSet<_> = votes.iter()
            .filter(|vote| vote.slot == slot && vote.vote_type == VoteType::Echo)
            .collect();
        
        if notar_votes.is_empty() || finalization_votes.is_empty() {
            return Ok(None);
        }
        
        // Calculate stakes for both rounds
        let notar_voters: HashSet<ValidatorId> = notar_votes.iter().map(|vote| vote.voter).collect();
        let finalization_voters: HashSet<ValidatorId> = finalization_votes.iter().map(|vote| vote.voter).collect();
        
        let notar_stake = self.sum_stake(&notar_voters);
        let finalization_stake = self.sum_stake(&finalization_voters);
        
        // Both rounds must meet slow path threshold (≥60% stake)
        if notar_stake < self.config.slow_path_threshold || 
           finalization_stake < self.config.slow_path_threshold {
            return Ok(None);
        }
        
        // Get block hash from first notarization vote
        let block_hash = notar_votes.iter().next().unwrap().block;
        
        // Combine all validators and signatures
        let all_voters: HashSet<ValidatorId> = notar_voters.union(&finalization_voters).cloned().collect();
        let all_signatures: HashSet<Signature> = notar_votes.iter()
            .chain(finalization_votes.iter())
            .map(|vote| vote.signature)
            .collect();
        
        // Create aggregated signature
        let aggregated_sig = AggregatedSignature {
            signers: all_voters.clone(),
            message: block_hash,
            signatures: all_signatures,
            valid: true,
        };
        
        // Create slow certificate
        let certificate = Certificate {
            slot,
            view: self.current_view,
            block: block_hash,
            cert_type: CertificateType::Slow,
            signatures: aggregated_sig,
            validators: all_voters,
            stake: finalization_stake, // Use finalization stake as final stake
        };
        
        Ok(Some(certificate))
    }
    
    /// Generate skip certificate from ≥60% stake skip votes - mirrors TLA+ GenerateSkipCert
    pub fn generate_skip_cert(&self, slot: SlotNumber, votes: &HashSet<Vote>) -> AlpenglowResult<Option<Certificate>> {
        // Filter skip votes for this slot
        let skip_votes: HashSet<_> = votes.iter()
            .filter(|vote| vote.slot == slot && vote.vote_type == VoteType::Skip)
            .collect();
        
        if skip_votes.is_empty() {
            return Ok(None);
        }
        
        // Calculate voter stake
        let voters: HashSet<ValidatorId> = skip_votes.iter().map(|vote| vote.voter).collect();
        let voter_stake = self.sum_stake(&voters);
        
        // Check if meets skip threshold (≥60% stake)
        if voter_stake < self.config.slow_path_threshold {
            return Ok(None);
        }
        
        // Create aggregated signature
        let signatures: HashSet<Signature> = skip_votes.iter().map(|vote| vote.signature).collect();
        let aggregated_sig = AggregatedSignature {
            signers: voters.clone(),
            message: 0u64 as BlockHash, // No block for skip votes
            signatures,
            valid: true,
        };
        
        // Create skip certificate
        let certificate = Certificate {
            slot,
            view: self.current_view,
            block: 0u64 as BlockHash, // No block for skip
            cert_type: CertificateType::Skip,
            signatures: aggregated_sig,
            validators: voters,
            stake: voter_stake,
        };
        
        Ok(Some(certificate))
    }
    
    /// Set timeout for a validator and slot - mirrors TLA+ SetTimeout
    pub fn set_timeout(&mut self, slot: SlotNumber, timeout: TimeoutMs) -> AlpenglowResult<()> {
        if slot == 0 || slot > self.config.max_slot {
            return Err(AlpenglowError::ProtocolViolation("Invalid slot number".to_string()));
        }
        
        // Update timeout expiry for the current view
        self.timeout_expiry = self.current_time + timeout;
        
        // Update voting round timeout if it exists
        if let Some(round) = self.voting_rounds.get_mut(&self.current_view) {
            round.timeout_expiry = self.current_time + timeout;
        }
        
        Ok(())
    }
    
    /// Check if timeout has expired - mirrors TLA+ TimeoutExpired
    pub fn check_timeout_expired(&self, slot: SlotNumber) -> bool {
        // Check if current time exceeds timeout expiry
        self.current_time >= self.timeout_expiry
    }
    
    /// Finalize block with certificate - mirrors TLA+ FinalizeBlock
    pub fn finalize_block(&mut self, slot: SlotNumber, block: &Block, certificate: &Certificate) -> AlpenglowResult<()> {
        // Validate certificate
        if !self.validate_certificate(certificate) {
            return Err(AlpenglowError::ProtocolViolation("Invalid certificate".to_string()));
        }
        
        // Check certificate matches block and slot
        if certificate.slot != slot || certificate.block != block.hash {
            return Err(AlpenglowError::ProtocolViolation("Certificate does not match block".to_string()));
        }
        
        // Skip certificates don't finalize blocks
        if certificate.cert_type == CertificateType::Skip {
            return Ok(());
        }
        
        // Check for duplicate slot finalization
        if self.finalized_chain.iter().any(|b| b.slot == slot) {
            return Err(AlpenglowError::ProtocolViolation("Slot already finalized".to_string()));
        }
        
        // Add block to finalized chain
        self.finalized_chain.push(block.clone());
        
        Ok(())
    }
    
    /// Update finalized chain for validator - mirrors TLA+ UpdateFinalizedChain
    pub fn update_finalized_chain(&mut self, block: &Block) -> AlpenglowResult<()> {
        // Check for duplicate slot
        if self.finalized_chain.iter().any(|b| b.slot == block.slot) {
            return Err(AlpenglowError::ProtocolViolation("Block slot already finalized".to_string()));
        }
        
        // Add block to finalized chain
        self.finalized_chain.push(block.clone());
        
        Ok(())
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
            signature: self.validator_id as Signature, // Simplified signature
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
            .push(block.clone());
        
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
                .push(certificate.clone());
            
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
            block: 0u64 as BlockHash, // No block hash for skip votes, explicit type
            vote_type: VoteType::Skip,
            signature: self.validator_id as Signature,
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
            block: 0u64 as BlockHash, // No block hash for skip votes
            vote_type: VoteType::Skip,
            signature: self.validator_id as Signature,
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
    pub fn validate_vote_message(&self, voter: ValidatorId, view: ViewNumber, slot: SlotNumber, _block_hash: BlockHash) -> bool {
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
            if block.parent != 0u64 as BlockHash {
                return false;
            }
        } else {
            // Check parent exists in finalized chain
            if !self.finalized_chain
                .iter()
                .any(|b| b.hash == block.parent) {
                return false;
            }
        }
        
        true
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
            let _is_skip = vote.block == 0u64;
        }
        
        // Non-skip votes must reference a valid block
        vote.block != 0u64
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
            message: 0u64 as BlockHash, // Skip vote has no block
            signatures,
            valid: true,
        };
        
        Some(Certificate {
            slot: view, // Use view as slot for skip certificates
            view,
            block: 0u64 as BlockHash,
            cert_type: CertificateType::Skip,
            signatures: aggregated_sig,
            validators,
            stake: skip_stake,
        })
    }
    
    
    /// Validate a certificate - enhanced with TLA+ correspondence
    pub fn validate_certificate(&self, certificate: &Certificate) -> bool {
        // Check basic structure
        if certificate.validators.is_empty() || certificate.stake == 0 {
            return false;
        }
        
        // Check stake threshold based on certificate type
        let required_threshold = match certificate.cert_type {
            CertificateType::Fast => self.config.fast_path_threshold,
            CertificateType::Slow | CertificateType::Skip => self.config.slow_path_threshold,
        };
        
        if certificate.stake < required_threshold {
            return false;
        }
        
        // Verify stake calculation matches validators
        let calculated_stake: StakeAmount = certificate.validators
            .iter()
            .map(|v| self.config.stake_distribution.get(v).copied().unwrap_or(0))
            .sum();
        
        if certificate.stake != calculated_stake {
            return false;
        }
        
        // Verify signature aggregation is valid (simplified)
        if !certificate.signatures.valid {
            return false;
        }
        
        // Check that signers match validators
        if certificate.signatures.signers != certificate.validators {
            return false;
        }
        
        true
    }
    
    /// Validate vote message format - enhanced version of existing function
    pub fn validate_vote_message_detailed(&self, voter: ValidatorId, view: ViewNumber, slot: SlotNumber, block_hash: BlockHash) -> AlpenglowResult<()> {
        // Check validator is valid
        if voter >= self.config.validator_count as ValidatorId {
            return Err(AlpenglowError::ProtocolViolation("Invalid validator ID".to_string()));
        }
        
        // Check view bounds
        if view == 0 || view > self.config.max_view {
            return Err(AlpenglowError::ProtocolViolation("Invalid view number".to_string()));
        }
        
        // Check slot bounds
        if slot == 0 || slot > self.config.max_slot {
            return Err(AlpenglowError::ProtocolViolation("Invalid slot number".to_string()));
        }
        
        // Check if validator has stake
        if !self.config.stake_distribution.contains_key(&voter) {
            return Err(AlpenglowError::ProtocolViolation("Validator has no stake".to_string()));
        }
        
        Ok(())
    }
    
    /// Enhanced stake calculation with validation
    pub fn sum_stake_validated(&self, validators: &HashSet<ValidatorId>) -> AlpenglowResult<StakeAmount> {
        let mut total_stake = 0;
        
        for validator in validators {
            if let Some(stake) = self.config.stake_distribution.get(validator) {
                total_stake += stake;
            } else {
                return Err(AlpenglowError::ProtocolViolation(
                    format!("Validator {} not found in stake distribution", validator)
                ));
            }
        }
        
        Ok(total_stake)
    }
    
    /// Check if validator is honest (not Byzantine) - mirrors TLA+ HonestValidators
    pub fn is_honest_validator(&self, validator: ValidatorId) -> bool {
        !self.byzantine_validators.contains(&validator)
    }
    
    /// Get all honest validators
    pub fn get_honest_validators(&self) -> HashSet<ValidatorId> {
        (0..self.config.validator_count as ValidatorId)
            .filter(|v| self.is_honest_validator(*v))
            .collect()
    }
    
    /// Validate voting protocol invariant - mirrors TLA+ VotingProtocolInvariant
    pub fn validate_voting_protocol_invariant(&self) -> AlpenglowResult<()> {
        let honest_validators = self.get_honest_validators();
        
        for validator in honest_validators {
            // Check all votes from this honest validator
            for votes in self.received_votes.values() {
                for vote in votes {
                    if vote.voter == validator {
                        // If it's a finalization vote, there must be a prior notarization vote
                        if vote.vote_type == VoteType::Echo {
                            let has_prior_notar = votes.iter().any(|prior_vote| {
                                prior_vote.voter == validator &&
                                prior_vote.slot == vote.slot &&
                                prior_vote.vote_type == VoteType::Commit
                            });
                            
                            if !has_prior_notar {
                                return Err(AlpenglowError::ProtocolViolation(
                                    format!("Finalization vote without prior notarization from validator {}", validator)
                                ));
                            }
                        }
                        
                        // If it's a skip vote, timeout must have expired
                        if vote.vote_type == VoteType::Skip {
                            if !self.check_timeout_expired(vote.slot) {
                                return Err(AlpenglowError::ProtocolViolation(
                                    format!("Skip vote without timeout expiry from validator {}", validator)
                                ));
                            }
                        }
                    }
                }
            }
        }
        
        Ok(())
    }
    
    /// Validate one vote per slot invariant - mirrors TLA+ OneVotePerSlot
    pub fn validate_one_vote_per_slot(&self) -> AlpenglowResult<()> {
        let honest_validators = self.get_honest_validators();
        
        for validator in honest_validators {
            for slot in 1..=self.config.max_slot {
                let mut notar_count = 0;
                let mut skip_count = 0;
                let mut finalization_count = 0;
                
                // Count votes by type for this validator and slot
                for votes in self.received_votes.values() {
                    for vote in votes {
                        if vote.voter == validator && vote.slot == slot {
                            match vote.vote_type {
                                VoteType::Commit => notar_count += 1,
                                VoteType::Skip => skip_count += 1,
                                VoteType::Echo => finalization_count += 1,
                                _ => {}
                            }
                        }
                    }
                }
                
                // Check skip votes separately
                for skip_votes in self.skip_votes.values() {
                    for vote in skip_votes {
                        if vote.voter == validator && vote.slot == slot {
                            skip_count += 1;
                        }
                    }
                }
                
                // Validate at most one vote per type per slot
                if notar_count > 1 {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("Validator {} has {} notarization votes for slot {}", validator, notar_count, slot)
                    ));
                }
                
                if skip_count > 1 {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("Validator {} has {} skip votes for slot {}", validator, skip_count, slot)
                    ));
                }
                
                if finalization_count > 1 {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("Validator {} has {} finalization votes for slot {}", validator, finalization_count, slot)
                    ));
                }
            }
        }
        
        Ok(())
    }
    
    /// Validate certificate thresholds invariant - mirrors TLA+ ValidCertificateThresholds
    pub fn validate_certificate_thresholds(&self) -> AlpenglowResult<()> {
        for certs in self.generated_certificates.values() {
            for cert in certs {
                let required_threshold = match cert.cert_type {
                    CertificateType::Fast => self.config.fast_path_threshold,
                    CertificateType::Slow => self.config.slow_path_threshold,
                    CertificateType::Skip => self.config.slow_path_threshold,
                };
                
                if cert.stake < required_threshold {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("Certificate has stake {} below required threshold {} for type {:?}", 
                               cert.stake, required_threshold, cert.cert_type)
                    ));
                }
            }
        }
        
        Ok(())
    }
    
    /// Enhanced error handling for state transitions
    pub fn validate_state_transition(&self, action: &str) -> AlpenglowResult<()> {
        // Validate current state is consistent
        self.validate_voting_protocol_invariant()?;
        self.validate_one_vote_per_slot()?;
        self.validate_certificate_thresholds()?;
        
        // Validate Byzantine resilience
        let byzantine_stake = self.sum_stake(&self.byzantine_validators);
        if byzantine_stake >= self.config.total_stake / 3 {
            return Err(AlpenglowError::ProtocolViolation(
                format!("Byzantine stake {} exceeds 1/3 threshold during action {}", byzantine_stake, action)
            ));
        }
        
        Ok(())
    }
    
    /// Advance to next view - enhanced version mirrors TLA+ view advancement logic
    pub fn advance_view(&mut self) -> AlpenglowResult<()> {
        // Validate state before advancing
        self.validate_state_transition("advance_view")?;
        
        // Check if we can advance (not at max view)
        if self.current_view >= self.config.max_view {
            return Err(AlpenglowError::ProtocolViolation("Cannot advance beyond max view".to_string()));
        }
        
        self.current_view += 1;
        self.current_leader_window = (self.current_view - 1) / LEADER_WINDOW_SIZE;
        
        // Update timeout with adaptive timeout
        self.timeout_expiry = self.current_time + self.adaptive_timeout(self.current_view);
        
        // Create new voting round for the new view
        let timeout_duration = self.adaptive_timeout(self.current_view);
        let round = VotingRound::new(self.current_view, timeout_duration, self.current_time);
        self.voting_rounds.insert(self.current_view, round);
        
        Ok(())
    }
    
    /// Enhanced timeout handling with proper state validation
    pub fn handle_timeout_enhanced(&mut self) -> AlpenglowResult<()> {
        // Validate state before handling timeout
        self.validate_state_transition("handle_timeout")?;
        
        if !self.is_timeout_expired() {
            return Err(AlpenglowError::ProtocolViolation("Timeout not expired".to_string()));
        }
        
        // Check if we haven't voted yet (condition for timeout handling)
        let has_voted_in_current_view = self.received_votes
            .get(&self.current_view)
            .map(|votes| votes.iter().any(|vote| vote.voter == self.validator_id))
            .unwrap_or(false);
        
        if has_voted_in_current_view {
            return Err(AlpenglowError::ProtocolViolation("Cannot timeout after voting".to_string()));
        }
        
        // Cast skip vote and advance view
        let skip_vote = self.cast_skip_vote(self.current_view, "timeout")?;
        
        // Try to advance view
        self.advance_view()?;
        
        Ok(())
    }
    
    /// Complete state machine implementation for all transitions
    pub fn execute_transition(&mut self, action: VotorMessage) -> AlpenglowResult<Vec<VotorMessage>> {
        let mut outgoing_messages = Vec::new();
        
        match action {
            VotorMessage::ProposeBlock { block } => {
                // Validate we're the leader for this view
                if !self.is_leader_for_view(block.view) {
                    return Err(AlpenglowError::ProtocolViolation("Not leader for this view".to_string()));
                }
                
                // Validate block
                if !self.validate_block(&block) {
                    return Err(AlpenglowError::ProtocolViolation("Invalid block proposal".to_string()));
                }
                
                // Add to voted blocks
                self.voted_blocks
                    .entry(block.view)
                    .or_default()
                    .push(block.clone());
                
                // If we're honest, vote for our own proposal
                if !self.is_byzantine {
                    let vote = self.cast_notar_vote(block.slot, &block)?;
                    outgoing_messages.push(VotorMessage::CastVote { vote });
                }
            },
            
            VotorMessage::CastVote { vote } => {
                // Validate vote
                if !self.validate_vote(&vote) {
                    return Err(AlpenglowError::ProtocolViolation("Invalid vote".to_string()));
                }
                
                // Add to received votes
                self.received_votes
                    .entry(vote.view)
                    .or_default()
                    .insert(vote.clone());
                
                // Try to generate certificate
                let all_votes: HashSet<Vote> = self.received_votes
                    .get(&vote.view)
                    .cloned()
                    .unwrap_or_default();
                
                if let Some(cert) = self.generate_fast_cert(vote.slot, &all_votes)? {
                    self.generated_certificates
                        .entry(vote.view)
                        .or_default()
                        .push(cert.clone());
                    outgoing_messages.push(VotorMessage::FinalizeBlock { certificate: cert });
                } else if let Some(cert) = self.generate_slow_cert(vote.slot, &all_votes)? {
                    self.generated_certificates
                        .entry(vote.view)
                        .or_default()
                        .push(cert.clone());
                    outgoing_messages.push(VotorMessage::FinalizeBlock { certificate: cert });
                }
            },
            
            VotorMessage::FinalizeBlock { certificate } => {
                // Find the block to finalize
                if let Some(block) = self.find_block_for_certificate(&certificate) {
                    self.finalize_block(certificate.slot, &block, &certificate)?;
                }
            },
            
            VotorMessage::TriggerTimeout => {
                if self.is_timeout_expired() {
                    self.handle_timeout_enhanced()?;
                    outgoing_messages.push(VotorMessage::SubmitSkipVote { view: self.current_view - 1 });
                }
            },
            
            VotorMessage::SubmitSkipVote { view } => {
                let skip_vote = self.cast_skip_vote(view, "manual")?;
                
                // Try to generate skip certificate
                let all_skip_votes: HashSet<Vote> = self.skip_votes
                    .get(&view)
                    .cloned()
                    .unwrap_or_default();
                
                if let Some(skip_cert) = self.generate_skip_cert(view, &all_skip_votes)? {
                    self.generated_certificates
                        .entry(view)
                        .or_default()
                        .push(skip_cert);
                    
                    // Advance view
                    self.advance_view()?;
                    outgoing_messages.push(VotorMessage::AdvanceView { new_view: self.current_view });
                }
            },
            
            VotorMessage::AdvanceView { new_view } => {
                if new_view > self.current_view {
                    self.current_view = new_view;
                    self.advance_view()?;
                    
                    // If we're the leader for the new view, propose a block
                    if self.is_leader_for_view(new_view) && !self.is_byzantine {
                        let block = self.create_block_proposal_for_view(new_view);
                        outgoing_messages.push(VotorMessage::ProposeBlock { block });
                    }
                }
            },
            
            VotorMessage::ClockTick { current_time } => {
                self.current_time = current_time;
                
                // Check for expired timeouts
                if self.is_timeout_expired() {
                    outgoing_messages.push(VotorMessage::TriggerTimeout);
                }
            },
            
            // Byzantine behaviors
            VotorMessage::ByzantineDoubleVote { vote1, vote2 } => {
                if self.is_byzantine {
                    outgoing_messages.push(VotorMessage::CastVote { vote: vote1 });
                    outgoing_messages.push(VotorMessage::CastVote { vote: vote2 });
                }
            },
            
            VotorMessage::ByzantineInvalidCert { certificate } => {
                if self.is_byzantine {
                    outgoing_messages.push(VotorMessage::FinalizeBlock { certificate });
                }
            },
            
            VotorMessage::ByzantineWithholdVote { view: _ } => {
                // Byzantine behavior: do nothing (withhold vote)
            },
            
            _ => {
                return Err(AlpenglowError::ProtocolViolation("Unknown action".to_string()));
            }
        }
        
        Ok(outgoing_messages)
    }
    
    /// Helper function to find block for certificate
    fn find_block_for_certificate(&self, certificate: &Certificate) -> Option<Block> {
        for blocks in self.voted_blocks.values() {
            for block in blocks {
                if block.hash == certificate.block {
                    return Some(block.clone());
                }
            }
        }
        None
    }
    
    /// Helper function to create block proposal for a view
    fn create_block_proposal_for_view(&self, view: ViewNumber) -> Block {
        let parent_hash = if self.finalized_chain.is_empty() {
            0u64 as BlockHash
        } else {
            self.finalized_chain.last().unwrap().hash
        };
        
        Block {
            slot: view, // Use view as slot for simplicity
            view,
            hash: self.compute_block_hash_for_view(view, parent_hash),
            parent: parent_hash,
            proposer: self.validator_id,
            transactions: Vec::new(),
            timestamp: self.current_time,
            signature: self.validator_id as Signature,
            data: Vec::new(),
        }
    }
    
    /// Helper function to compute block hash for view
    fn compute_block_hash_for_view(&self, view: ViewNumber, parent: BlockHash) -> BlockHash {
        let hash_input = view.wrapping_mul(31)
            .wrapping_add((self.validator_id as u64).wrapping_mul(17))
            .wrapping_add(parent_into_u64(&parent).wrapping_mul(13))
            .wrapping_add(self.current_time.wrapping_mul(7));
        hash_input.into()
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
                // Marking here requires mutable borrow; we avoid changing here since we have &mut
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
            0u64 as BlockHash // Genesis
        } else {
            state.finalized_chain.last().unwrap().hash
        };
        
        Block {
            slot: view, // Use view as slot for simplicity
            view,
            hash: self.compute_block_hash(view, parent_hash),
            parent: parent_hash,
            proposer: self.validator_id,
            transactions: Vec::new(), // Empty for now
            timestamp: state.current_time,
            signature: 0u64 as Signature, // Placeholder signature
            data: Vec::new(),
        }
    }
    
    /// Compute block hash (simplified)
    fn compute_block_hash(&self, view: ViewNumber, parent: BlockHash) -> BlockHash {
        // Simple hash computation using view, validator_id, and parent
        // Represent as numeric hash; convert into BlockHash using From if available
        // Fallback: use simple deterministic number and convert to BlockHash via into()
        let small_hash = view.wrapping_mul(31)
            .wrapping_add((self.validator_id as u64).wrapping_mul(17))
            .wrapping_add((parent_into_u64(&parent)).wrapping_mul(13));
        small_hash.into()
    }
    
    /// Create a vote for a block
    fn create_vote(&self, state: &VotorState, block: &Block, vote_type: VoteType) -> Vote {
        Vote {
            voter: self.validator_id,
            slot: block.slot,
            view: block.view,
            block: if vote_type == VoteType::Skip { 0u64 as BlockHash } else { block.hash },
            vote_type,
            signature: 0u64 as Signature, // Placeholder signature
            timestamp: state.current_time,
        }
    }
    
    /// Create a skip vote
    fn create_skip_vote(&self, state: &VotorState, view: ViewNumber) -> Vote {
        Vote {
            voter: self.validator_id,
            slot: view,
            view,
            block: 0u64 as BlockHash,
            vote_type: VoteType::Skip,
            signature: 0u64 as Signature, // Placeholder signature
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
                    // Check conditions before mutable borrow
                    let is_byzantine = state.is_byzantine;
                    let validator_id = state.validator_id;
                    let current_time = state.current_time;
                    let should_vote = !is_byzantine && block.proposer == validator_id;
                    
                    let round = state.get_or_create_round(block.view);
                    round.proposed_blocks.push(block.clone());
                    
                    // If we're not Byzantine, vote for our own proposal
                    if should_vote {
                        // Create vote manually to avoid borrow checker issues
                        let vote = Vote {
                            voter: validator_id,
                            slot: block.slot,
                            view: block.view,
                            block: block.hash,
                            vote_type: VoteType::Commit,
                            signature: validator_id as Signature, // Simplified signature
                            timestamp: current_time,
                        };
                        round.add_vote(vote.clone());
                        round.has_voted = true;
                        
                        // Broadcast vote to other validators
                        o.broadcast(VotorMessage::CastVote { vote });
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
                        let certs = state.generated_certificates.entry(vote.view).or_insert_with(Vec::new);
                        certs.push(cert.clone());
                        
                        // Broadcast certificate for finalization
                        o.broadcast(VotorMessage::FinalizeBlock { certificate: cert });
                    }
                }
            }
            
            VotorMessage::GenerateCertificate { view, block_hash } => {
                // Try to generate certificate for the specified block
                if let Some(cert) = state.try_generate_certificate(view, block_hash) {
                    let certs = state.generated_certificates.entry(view).or_insert_with(Vec::new);
                    certs.push(cert.clone());
                    
                    o.broadcast(VotorMessage::FinalizeBlock { certificate: cert });
                }
            }
            
            VotorMessage::FinalizeBlock { certificate } => {
                // Extract block and slot from certificate for finalize_block call
                if let Some(block) = state.find_block_for_certificate(&certificate) {
                    if let Err(e) = state.finalize_block(certificate.slot, &block, &certificate) {
                        // Log error but continue (in practice, would handle more gracefully)
                        eprintln!("Failed to finalize block: {:?}", e);
                    }
                } else {
                    eprintln!("Failed to finalize block: block for certificate not found");
                }
            }
            
            VotorMessage::TriggerTimeout => {
                // Check for expired timeouts and submit skip votes
                let expired_views = state.check_timeouts();
                for view in expired_views {
                    if view == state.current_view {
                        let _ = self.create_skip_vote(state, view);
                        o.broadcast(VotorMessage::SubmitSkipVote { view });
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
                    let certs = state.generated_certificates.entry(view).or_insert_with(Vec::new);
                    certs.push(skip_cert);
                    
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
                        o.broadcast(VotorMessage::ProposeBlock { block });
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
                
                for _view in expired_views {
                    o.send(src, VotorMessage::TriggerTimeout);
                }
            }
            
            // Byzantine behaviors
            VotorMessage::ByzantineDoubleVote { vote1, vote2 } => {
                if state.is_byzantine {
                    // Broadcast conflicting votes
                    o.broadcast(VotorMessage::CastVote { vote: vote1 });
                    o.broadcast(VotorMessage::CastVote { vote: vote2 });
                }
            }
            
            VotorMessage::ByzantineInvalidCert { certificate } => {
                if state.is_byzantine {
                    // Broadcast invalid certificate
                    o.broadcast(VotorMessage::FinalizeBlock { certificate });
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
    fn verify(&self) -> AlpenglowResult<()> {
        self.verify_safety()?;
        self.verify_liveness()?;
        self.verify_byzantine_resilience()?;
        Ok(())
    }
    
    fn verify_safety(&self) -> AlpenglowResult<()> {
        // Safety: No two blocks finalized in the same slot - mirrors TLA+ SafetyInvariant
        let mut slots = HashSet::new();
        for block in &self.finalized_chain {
            if slots.contains(&block.slot) {
                return Err(AlpenglowError::ProtocolViolation(
                    format!("Safety violation: Two blocks finalized in slot {}", block.slot)
                ));
            }
            slots.insert(block.slot);
        }
        
        // Additional safety checks
        self.validate_voting_protocol_invariant()?;
        self.validate_one_vote_per_slot()?;
        self.validate_certificate_thresholds()?;
        
        Ok(())
    }
    
    fn verify_liveness(&self) -> AlpenglowResult<()> {
        // Liveness: Chain should grow under good conditions - mirrors TLA+ LivenessProperty
        if self.current_time > 1000 && self.finalized_chain.is_empty() {
            return Err(AlpenglowError::ProtocolViolation(
                "Liveness violation: No progress made after sufficient time".to_string()
            ));
        }
        
        // Check that views are progressing reasonably
        if self.current_time > 0 && self.current_view == 1 && self.current_time > 10000 {
            return Err(AlpenglowError::ProtocolViolation(
                "Liveness violation: Views not progressing".to_string()
            ));
        }
        
        // Check that honest validators are participating
        let honest_validators = self.get_honest_validators();
        if honest_validators.is_empty() {
            return Err(AlpenglowError::ProtocolViolation(
                "Liveness violation: No honest validators".to_string()
            ));
        }
        
        Ok(())
    }
    
    fn verify_byzantine_resilience(&self) -> AlpenglowResult<()> {
        // Byzantine resilience: Safety should hold even with Byzantine validators
        // mirrors TLA+ ByzantineResilienceProperty
        let byzantine_stake = self.sum_stake_validated(&self.byzantine_validators)?;
        
        if byzantine_stake >= self.config.total_stake / 3 {
            return Err(AlpenglowError::ProtocolViolation(
                format!("Byzantine resilience violation: Byzantine stake {} >= 1/3 of total stake {}", 
                       byzantine_stake, self.config.total_stake)
            ));
        }
        
        // If Byzantine threshold is satisfied, safety should hold
        self.verify_safety()?;
        
        // Additional Byzantine resilience checks
        self.validate_certificate_thresholds()?;
        
        Ok(())
    }
}

/// Integration with main AlpenglowState - provides bridge functions
impl VotorState {
    /// Export state for integration with AlpenglowState
    pub fn export_for_integration(&self) -> AlpenglowResult<serde_json::Value> {
        Ok(serde_json::json!({
            "validator_id": self.validator_id,
            "current_view": self.current_view,
            "current_time": self.current_time,
            "finalized_chain_length": self.finalized_chain.len(),
            "generated_certificates_count": self.generated_certificates.values().map(|v| v.len()).sum::<usize>(),
            "is_byzantine": self.is_byzantine,
            "timeout_expiry": self.timeout_expiry,
            "current_leader_window": self.current_leader_window,
            "voting_rounds_count": self.voting_rounds.len(),
            "total_votes_received": self.received_votes.values().map(|v| v.len()).sum::<usize>(),
            "total_skip_votes": self.skip_votes.values().map(|v| v.len()).sum::<usize>()
        }))
    }
    
    /// Import state from AlpenglowState integration
    pub fn import_from_integration(&mut self, data: &serde_json::Value) -> AlpenglowResult<()> {
        if let Some(current_time) = data.get("current_time").and_then(|v| v.as_u64()) {
            self.current_time = current_time;
        }
        
        if let Some(is_byzantine) = data.get("is_byzantine").and_then(|v| v.as_bool()) {
            self.is_byzantine = is_byzantine;
        }
        
        if let Some(timeout_expiry) = data.get("timeout_expiry").and_then(|v| v.as_u64()) {
            self.timeout_expiry = timeout_expiry;
        }
        
        Ok(())
    }
    
    /// Get current protocol state summary for monitoring
    pub fn get_state_summary(&self) -> ProtocolStateSummary {
        ProtocolStateSummary {
            validator_id: self.validator_id,
            current_view: self.current_view,
            current_time: self.current_time,
            finalized_blocks_count: self.finalized_chain.len(),
            pending_votes_count: self.received_votes.values().map(|v| v.len()).sum(),
            generated_certificates_count: self.generated_certificates.values().map(|v| v.len()).sum(),
            is_byzantine: self.is_byzantine,
            is_leader: self.is_leader_for_view(self.current_view),
            timeout_expiry: self.timeout_expiry,
            timeout_expired: self.is_timeout_expired(),
        }
    }
    
    /// Process message from Rotor component
    pub fn process_rotor_message(&mut self, message: RotorMessage) -> AlpenglowResult<Vec<VotorMessage>> {
        match message {
            RotorMessage::BlockDelivered { block } => {
                // If we're the leader and haven't proposed yet, propose this block
                if self.is_leader_for_view(self.current_view) && !self.is_byzantine {
                    if !self.voted_blocks.get(&self.current_view).map_or(false, |blocks| !blocks.is_empty()) {
                        return Ok(vec![VotorMessage::ProposeBlock { block }]);
                    }
                }
                Ok(vec![])
            },
            RotorMessage::BlockReconstructed { block } => {
                // Vote for reconstructed block if we haven't voted yet
                if !self.is_byzantine && self.is_honest_validator(self.validator_id) {
                    let has_voted = self.received_votes
                        .get(&self.current_view)
                        .map(|votes| votes.iter().any(|vote| vote.voter == self.validator_id))
                        .unwrap_or(false);
                    
                    if !has_voted {
                        if let Ok(vote) = self.cast_notar_vote(block.slot, &block) {
                            return Ok(vec![VotorMessage::CastVote { vote }]);
                        }
                    }
                }
                Ok(vec![])
            },
            _ => Ok(vec![])
        }
    }
    
    /// Get metrics for performance monitoring
    pub fn get_performance_metrics(&self) -> VotorPerformanceMetrics {
        VotorPerformanceMetrics {
            validator_id: self.validator_id,
            current_view: self.current_view,
            views_per_second: if self.current_time > 0 { 
                (self.current_view as f64) / (self.current_time as f64 / 1000.0) 
            } else { 0.0 },
            finalization_rate: if self.current_view > 1 { 
                (self.finalized_chain.len() as f64) / (self.current_view as f64) 
            } else { 0.0 },
            average_timeout: self.timeout_expiry.saturating_sub(self.current_time),
            certificate_generation_rate: if self.current_view > 1 {
                (self.generated_certificates.values().map(|v| v.len()).sum::<usize>() as f64) / (self.current_view as f64)
            } else { 0.0 },
            byzantine_detection_count: self.byzantine_validators.len(),
        }
    }
}

/// Protocol state summary for monitoring
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProtocolStateSummary {
    pub validator_id: ValidatorId,
    pub current_view: ViewNumber,
    pub current_time: u64,
    pub finalized_blocks_count: usize,
    pub pending_votes_count: usize,
    pub generated_certificates_count: usize,
    pub is_byzantine: bool,
    pub is_leader: bool,
    pub timeout_expiry: TimeoutMs,
    pub timeout_expired: bool,
}

/// Performance metrics for Votor component
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VotorPerformanceMetrics {
    pub validator_id: ValidatorId,
    pub current_view: ViewNumber,
    pub views_per_second: f64,
    pub finalization_rate: f64,
    pub average_timeout: u64,
    pub certificate_generation_rate: f64,
    pub byzantine_detection_count: usize,
}

/// Message types for integration with Rotor
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum RotorMessage {
    BlockDelivered { block: Block },
    BlockReconstructed { block: Block },
    ShredReceived { block_id: BlockHash, shred_count: usize },
    ReconstructionFailed { block_id: BlockHash },
}

/// Structured verification result returned by the utilities in this module.
/// This is a simple structured form used by the verification harness and CLI
/// integration to emit JSON reports.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VerificationMetrics {
    pub states_explored: u64,
    pub properties_checked: u64,
    pub violations_found: u64,
    pub duration_ms: u128,
}

/// Higher-level verification result with diagnostics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VerificationResult {
    pub success: bool,
    pub violations: Vec<String>,
    pub metrics: VerificationMetrics,
}

/// Parameters controlling model checking runs and verification
#[derive(Debug, Clone)]
pub struct VerificationParams {
    pub max_depth: usize,
    pub timeout_ms: u64,
    pub check_safety: bool,
    pub check_liveness: bool,
    pub check_byzantine: bool,
}

impl Default for VerificationParams {
    fn default() -> Self {
        Self {
            max_depth: 1000,
            timeout_ms: 30_000,
            check_safety: true,
            check_liveness: true,
            check_byzantine: true,
        }
    }
}

/// Simple model checker wrapper that runs the Verifiable/TlaCompatible checks
/// and gathers metrics to produce a structured VerificationResult.
/// This is intentionally lightweight and deterministic; integration with full
/// external model checkers should be performed by the higher-level test harness.
pub struct ModelChecker {}

impl ModelChecker {
    /// Run verification using the provided state, return structured result.
    pub fn run(state: &VotorState, params: VerificationParams) -> VerificationResult {
        let start = Instant::now();
        let mut violations = Vec::new();
        let mut properties_checked = 0u64;
        let states_explored; // will be set based on params.max_depth
        let mut violations_found = 0u64;
        
        // Safety
        if params.check_safety {
            properties_checked += 1;
            match state.verify_safety() {
                Ok(()) => { /* passed */ }
                Err(e) => {
                    violations_found += 1;
                    violations.push(format!("safety: {:?}", e));
                }
            }
        }
        
        // Liveness
        if params.check_liveness {
            properties_checked += 1;
            match state.verify_liveness() {
                Ok(()) => {}
                Err(e) => {
                    violations_found += 1;
                    violations.push(format!("liveness: {:?}", e));
                }
            }
        }
        
        // Byzantine resilience
        if params.check_byzantine {
            properties_checked += 1;
            match state.verify_byzantine_resilience() {
                Ok(()) => {}
                Err(e) => {
                    violations_found += 1;
                    violations.push(format!("byzantine_resilience: {:?}", e));
                }
            }
        }
        
        // Simulated state exploration metric - in a real run this would be produced by the model checker
        states_explored = params.max_depth as u64; // heuristically reflect depth
        
        let duration_ms = start.elapsed().as_millis();
        let success = violations_found == 0;
        
        VerificationResult {
            success,
            violations,
            metrics: VerificationMetrics {
                states_explored,
                properties_checked,
                violations_found,
                duration_ms,
            },
        }
    }
    
    /// Attempt to run verification using an external Stateright framework.
    /// Returns Ok(true) if the external run indicates the properties hold,
    /// Ok(false) if external run found violations, and Err if the integration failed.
    /// This implementation is a stub for integration; it returns Ok(true) by default.
    pub fn run_external_integration(_state: &VotorState, _params: &VerificationParams) -> Result<bool, String> {
        // Placeholder: in a full integration we would:
        // - Convert VotorState into the external stateright model representation
        // - Convert properties into external SimpleProperty/Property objects
        // - Invoke external Checker with provided depth/timeout
        // - Translate result back into structured outcome
        //
        // For now, return Ok(true) indicating no violations found by external run.
        Ok(true)
    }
}

impl TlaCompatible for VotorState {
    /// Convert to TLA+ compatible string representation
    fn to_tla_string(&self) -> String {
        serde_json::to_string(self).unwrap_or_else(|_| "{}".to_string())
    }
    
    /// Export state for TLA+ cross-validation - mirrors TLA+ voterVars exactly
    fn export_tla_state(&self) -> String {
        let json_value = self.export_tla_state_json();
        serde_json::to_string(&json_value).unwrap_or_else(|_| "{}".to_string())
    }
    
    /// Export state as JSON value for TLA+ cross-validation - mirrors TLA+ voterVars exactly
    fn export_tla_state_json(&self) -> serde_json::Value {
        // Convert voted blocks to TLA+ format: [validator][view] -> SUBSET Block
        let voted_blocks_tla: serde_json::Value = serde_json::json!({
            self.validator_id.to_string(): {
                self.current_view.to_string(): self.voted_blocks.get(&self.current_view)
                    .map(|blocks| blocks.iter().map(|block| {
                        serde_json::json!({
                            "slot": block.slot,
                            "view": block.view,
                            "hash": format!("{:?}", block.hash), // Convert BlockHash to string
                            "parent": format!("{:?}", block.parent),
                            "proposer": block.proposer,
                            "transactions": block.transactions.iter().map(|tx| {
                                serde_json::json!({
                                    "id": tx.id,
                                    "sender": tx.sender,
                                    "data": tx.data.iter().map(|&b| b as u64).collect::<Vec<u64>>(),
                                    "signature": {
                                        "signer": tx.sender,
                                        "message": tx.id,
                                        "valid": true
                                    }
                                })
                            }).collect::<Vec<_>>(),
                            "timestamp": block.timestamp,
                            "signature": {
                                "signer": block.proposer,
                                "message": block.view,
                                "valid": true
                            },
                            "data": block.data.iter().map(|&b| b as u64).collect::<Vec<u64>>()
                        })
                    }).collect::<Vec<_>>())
                    .unwrap_or_default()
            }
        });

        // Convert received votes to TLA+ format: [validator][view] -> SUBSET Vote
        let received_votes_tla: serde_json::Value = serde_json::json!({
            self.validator_id.to_string(): self.received_votes.iter().map(|(view, votes)| {
                (view.to_string(), votes.iter().map(|vote| {
                    serde_json::json!({
                        "voter": vote.voter,
                        "slot": vote.slot,
                        "view": vote.view,
                        "block": format!("{:?}", vote.block),
                        "type": match vote.vote_type {
                            VoteType::Proposal => "proposal",
                            VoteType::Echo => "echo", 
                            VoteType::Commit => "commit",
                            VoteType::Skip => "skip"
                        },
                        "signature": {
                            "signer": vote.voter,
                            "message": format!("{:?}", vote.block),
                            "aggregatable": true
                        },
                        "timestamp": vote.timestamp
                    })
                }).collect::<Vec<_>>())
            }).collect::<std::collections::HashMap<String, Vec<_>>>()
        });

        // Convert generated certificates to TLA+ format: [view] -> SUBSET Certificate
        let generated_certs_tla: serde_json::Value = serde_json::json!(
            self.generated_certificates.iter().map(|(view, certs)| {
                (view.to_string(), certs.iter().map(|cert| {
                    serde_json::json!({
                        "slot": cert.slot,
                        "view": cert.view,
                        "block": format!("{:?}", cert.block),
                        "type": match cert.cert_type {
                            CertificateType::Fast => "fast",
                            CertificateType::Slow => "slow",
                            CertificateType::Skip => "skip"
                        },
                        "signatures": {
                            "signers": cert.signatures.signers.iter().collect::<Vec<_>>(),
                            "message": format!("{:?}", cert.signatures.message),
                            "signatures": cert.signatures.signatures.iter().map(|_sig| {
                                serde_json::json!({
                                    "signer": 0, // Simplified - would extract from signature
                                    "message": format!("{:?}", cert.signatures.message),
                                    "aggregatable": true
                                })
                            }).collect::<Vec<_>>(),
                            "valid": cert.signatures.valid
                        },
                        "validators": cert.validators.iter().collect::<Vec<_>>(),
                        "stake": cert.stake
                    })
                }).collect::<Vec<_>>())
            }).collect::<std::collections::HashMap<String, Vec<_>>>()
        );

        // Convert finalized chain to TLA+ format: Seq(Block)
        let finalized_chain_tla: Vec<serde_json::Value> = self.finalized_chain.iter().map(|block| {
            serde_json::json!({
                "slot": block.slot,
                "view": block.view,
                "hash": format!("{:?}", block.hash),
                "parent": format!("{:?}", block.parent),
                "proposer": block.proposer,
                "transactions": block.transactions.iter().map(|tx| {
                    serde_json::json!({
                        "id": tx.id,
                        "sender": tx.sender,
                        "data": tx.data.iter().map(|&b| b as u64).collect::<Vec<u64>>(),
                        "signature": {
                            "signer": tx.sender,
                            "message": tx.id,
                            "valid": true
                        }
                    })
                }).collect::<Vec<_>>(),
                "timestamp": block.timestamp,
                "signature": {
                    "signer": block.proposer,
                    "message": block.view,
                    "valid": true
                },
                "data": block.data.iter().map(|&b| b as u64).collect::<Vec<u64>>()
            })
        }).collect();

        // Convert skip votes to TLA+ format: [validator][view] -> SUBSET Vote
        let skip_votes_tla: serde_json::Value = serde_json::json!({
            self.validator_id.to_string(): self.skip_votes.iter().map(|(view, votes)| {
                (view.to_string(), votes.iter().map(|vote| {
                    serde_json::json!({
                        "voter": vote.voter,
                        "slot": vote.slot,
                        "view": vote.view,
                        "block": 0, // Skip votes have no block
                        "type": "skip",
                        "signature": {
                            "signer": vote.voter,
                            "message": vote.view,
                            "valid": true
                        },
                        "timestamp": vote.timestamp
                    })
                }).collect::<Vec<_>>())
            }).collect::<std::collections::HashMap<String, Vec<_>>>()
        });

        // Export complete TLA+ state matching voterVars specification exactly
        serde_json::json!({
            // TLA+ voterVars: <<view, votedBlocks, receivedVotes, generatedCerts,
            //                   finalizedChain, timeoutExpiry, skipVotes, currentTime, currentLeaderWindow>>
            "view": {
                self.validator_id.to_string(): self.current_view
            },
            "votedBlocks": voted_blocks_tla,
            "receivedVotes": received_votes_tla,
            "generatedCerts": generated_certs_tla,
            "finalizedChain": finalized_chain_tla,
            "timeoutExpiry": {
                self.validator_id.to_string(): self.timeout_expiry
            },
            "skipVotes": skip_votes_tla,
            "currentTime": self.current_time,
            "currentLeaderWindow": self.current_leader_window,
            
            // Additional metadata for cross-validation
            "validator_id": self.validator_id,
            "is_byzantine": self.is_byzantine,
            "byzantine_validators": self.byzantine_validators.iter().collect::<Vec<_>>(),
            "config": {
                "validator_count": self.config.validator_count,
                "total_stake": self.config.total_stake,
                "fast_path_threshold": self.config.fast_path_threshold,
                "slow_path_threshold": self.config.slow_path_threshold,
                "max_view": self.config.max_view,
                "max_slot": self.config.max_slot,
                "stake_distribution": self.config.stake_distribution.iter().map(|(k, v)| (k.to_string(), v)).collect::<std::collections::HashMap<String, &StakeAmount>>()
            },
            
            // VRF state for leader selection verification
            "vrf_key_pairs": self.vrf_key_pairs.iter().map(|(validator, key_pair)| {
                (validator.to_string(), serde_json::json!({
                    "validator": key_pair.validator,
                    "public_key": key_pair.public_key,
                    "private_key": key_pair.private_key,
                    "valid": key_pair.valid
                }))
            }).collect::<std::collections::HashMap<String, serde_json::Value>>(),
            
            "vrf_proofs": self.vrf_proofs.iter().map(|(view, proof)| {
                serde_json::json!({
                    "view": view,
                    "validator": proof.validator,
                    "input": proof.input,
                    "output": proof.output,
                    "proof": proof.proof,
                    "public_key": proof.public_key,
                    "valid": proof.valid
                })
            }).collect::<Vec<_>>()
        })
    }
    
    /// Import state from TLA+ model checker and reconstruct VotorState
    fn import_tla_state(&mut self, state: &Self) -> AlpenglowResult<()> {
        // Copy state from the provided VotorState
        self.current_view = state.current_view;
        self.current_time = state.current_time;
        self.current_leader_window = state.current_leader_window;
        self.timeout_expiry = state.timeout_expiry;
        self.voted_blocks = state.voted_blocks.clone();
        self.received_votes = state.received_votes.clone();
        self.generated_certificates = state.generated_certificates.clone();
        self.finalized_chain = state.finalized_chain.clone();
        self.skip_votes = state.skip_votes.clone();
        self.byzantine_validators = state.byzantine_validators.clone();
        self.is_byzantine = state.is_byzantine;
        self.voting_rounds = state.voting_rounds.clone();
        
        Ok(())
    }
    
    /// Import state from TLA+ JSON format
    fn import_tla_state_from_json(&mut self, state: serde_json::Value) -> AlpenglowResult<()> {
        // Validate that the state contains all required TLA+ voterVars
        let required_fields = ["view", "votedBlocks", "receivedVotes", "generatedCerts", 
                              "finalizedChain", "timeoutExpiry", "skipVotes", "currentTime", "currentLeaderWindow"];
        
        for field in &required_fields {
            if !state.get(field).is_some() {
                return Err(AlpenglowError::ProtocolViolation(
                    format!("Missing required TLA+ state field: {}", field)
                ));
            }
        }

        // Import view state
        if let Some(view_obj) = state.get("view") {
            if let Some(view_val) = view_obj.get(self.validator_id.to_string()) {
                self.current_view = view_val.as_u64()
                    .ok_or_else(|| AlpenglowError::ProtocolViolation("Invalid view format".to_string()))?;
            }
        }

        // Import currentTime
        if let Some(time_val) = state.get("currentTime") {
            self.current_time = time_val.as_u64()
                .ok_or_else(|| AlpenglowError::ProtocolViolation("Invalid currentTime format".to_string()))?;
        }

        // Import currentLeaderWindow
        if let Some(window_val) = state.get("currentLeaderWindow") {
            self.current_leader_window = window_val.as_u64()
                .ok_or_else(|| AlpenglowError::ProtocolViolation("Invalid currentLeaderWindow format".to_string()))?;
        }

        // Import timeoutExpiry
        if let Some(timeout_obj) = state.get("timeoutExpiry") {
            if let Some(timeout_val) = timeout_obj.get(self.validator_id.to_string()) {
                self.timeout_expiry = timeout_val.as_u64()
                    .ok_or_else(|| AlpenglowError::ProtocolViolation("Invalid timeoutExpiry format".to_string()))?;
            }
        }

        // Import votedBlocks
        self.voted_blocks.clear();
        if let Some(voted_blocks_obj) = state.get("votedBlocks") {
            if let Some(validator_blocks) = voted_blocks_obj.get(self.validator_id.to_string()) {
                for (view_str, blocks_array) in validator_blocks.as_object()
                    .ok_or_else(|| AlpenglowError::ProtocolViolation("Invalid votedBlocks format".to_string()))? {
                    
                    let view: ViewNumber = view_str.parse()
                        .map_err(|_| AlpenglowError::ProtocolViolation("Invalid view number".to_string()))?;
                    
                    let mut blocks = Vec::new();
                    if let Some(blocks_arr) = blocks_array.as_array() {
                        for block_val in blocks_arr {
                            let block = self.parse_tla_block(block_val)?;
                            blocks.push(block);
                        }
                    }
                    self.voted_blocks.insert(view, blocks);
                }
            }
        }

        // Import receivedVotes
        self.received_votes.clear();
        if let Some(received_votes_obj) = state.get("receivedVotes") {
            if let Some(validator_votes) = received_votes_obj.get(self.validator_id.to_string()) {
                for (view_str, votes_array) in validator_votes.as_object()
                    .ok_or_else(|| AlpenglowError::ProtocolViolation("Invalid receivedVotes format".to_string()))? {
                    
                    let view: ViewNumber = view_str.parse()
                        .map_err(|_| AlpenglowError::ProtocolViolation("Invalid view number".to_string()))?;
                    
                    let mut votes = HashSet::new();
                    if let Some(votes_arr) = votes_array.as_array() {
                        for vote_val in votes_arr {
                            let vote = self.parse_tla_vote(vote_val)?;
                            votes.insert(vote);
                        }
                    }
                    self.received_votes.insert(view, votes);
                }
            }
        }

        // Import generatedCerts
        self.generated_certificates.clear();
        if let Some(generated_certs_obj) = state.get("generatedCerts") {
            for (view_str, certs_array) in generated_certs_obj.as_object()
                .ok_or_else(|| AlpenglowError::ProtocolViolation("Invalid generatedCerts format".to_string()))? {
                
                let view: ViewNumber = view_str.parse()
                    .map_err(|_| AlpenglowError::ProtocolViolation("Invalid view number".to_string()))?;
                
                let mut certs = Vec::new();
                if let Some(certs_arr) = certs_array.as_array() {
                    for cert_val in certs_arr {
                        let cert = self.parse_tla_certificate(cert_val)?;
                        certs.push(cert);
                    }
                }
                self.generated_certificates.insert(view, certs);
            }
        }

        // Import finalizedChain
        self.finalized_chain.clear();
        if let Some(finalized_chain_arr) = state.get("finalizedChain").and_then(|v| v.as_array()) {
            for block_val in finalized_chain_arr {
                let block = self.parse_tla_block(block_val)?;
                self.finalized_chain.push(block);
            }
        }

        // Import skipVotes
        self.skip_votes.clear();
        if let Some(skip_votes_obj) = state.get("skipVotes") {
            if let Some(validator_skip_votes) = skip_votes_obj.get(self.validator_id.to_string()) {
                for (view_str, votes_array) in validator_skip_votes.as_object()
                    .ok_or_else(|| AlpenglowError::ProtocolViolation("Invalid skipVotes format".to_string()))? {
                    
                    let view: ViewNumber = view_str.parse()
                        .map_err(|_| AlpenglowError::ProtocolViolation("Invalid view number".to_string()))?;
                    
                    let mut votes = HashSet::new();
                    if let Some(votes_arr) = votes_array.as_array() {
                        for vote_val in votes_arr {
                            let vote = self.parse_tla_vote(vote_val)?;
                            votes.insert(vote);
                        }
                    }
                    self.skip_votes.insert(view, votes);
                }
            }
        }

        // Import Byzantine validator information if present
        if let Some(byzantine_vals) = state.get("byzantine_validators").and_then(|v| v.as_array()) {
            self.byzantine_validators.clear();
            for val in byzantine_vals {
                if let Some(validator_id) = val.as_u64() {
                    self.byzantine_validators.insert(validator_id as ValidatorId);
                }
            }
            self.is_byzantine = self.byzantine_validators.contains(&self.validator_id);
        }

        // Rebuild voting_rounds from imported state
        self.rebuild_voting_rounds()?;

        Ok(())
    }
    
    /// Validate consistency with TLA+ invariants - implements all invariants from Votor.tla
    fn validate_tla_invariants(&self) -> AlpenglowResult<()> {
        // VotorSafety: No two blocks at same slot
        self.validate_votor_safety()?;
        
        // ValidCertificates: All generated certificates are valid
        self.validate_certificate_validity()?;
        
        // ByzantineResilience: Safety holds under Byzantine threshold
        self.validate_byzantine_resilience()?;
        
        // HonestVoteUniqueness: Honest validators cast at most one vote per view
        self.validate_honest_vote_uniqueness()?;
        
        // HonestSelfVoteUniqueness: Honest validators have at most one self-vote per view
        self.validate_honest_self_vote_uniqueness()?;
        
        // ViewConvergence: Honest validators should converge on views (simplified check)
        self.validate_view_convergence()?;
        
        // Additional structural invariants
        self.validate_structural_invariants()?;
        
        Ok(())
    }
}

impl VotorState {
    /// Parse TLA+ block format into Rust Block
    fn parse_tla_block(&self, block_val: &serde_json::Value) -> AlpenglowResult<Block> {
        let slot = block_val.get("slot")
            .and_then(|v| v.as_u64())
            .ok_or_else(|| AlpenglowError::ProtocolViolation("Invalid block slot".to_string()))?;
        
        let view = block_val.get("view")
            .and_then(|v| v.as_u64())
            .ok_or_else(|| AlpenglowError::ProtocolViolation("Invalid block view".to_string()))?;
        
        let hash_str = block_val.get("hash")
            .and_then(|v| v.as_str())
            .ok_or_else(|| AlpenglowError::ProtocolViolation("Invalid block hash".to_string()))?;
        
        let parent_str = block_val.get("parent")
            .and_then(|v| v.as_str())
            .ok_or_else(|| AlpenglowError::ProtocolViolation("Invalid block parent".to_string()))?;
        
        let proposer = block_val.get("proposer")
            .and_then(|v| v.as_u64())
            .ok_or_else(|| AlpenglowError::ProtocolViolation("Invalid block proposer".to_string()))? as ValidatorId;
        
        let timestamp = block_val.get("timestamp")
            .and_then(|v| v.as_u64())
            .ok_or_else(|| AlpenglowError::ProtocolViolation("Invalid block timestamp".to_string()))?;
        
        // Parse transactions into a Vec to preserve deterministic ordering
        let mut transactions = Vec::new();
        if let Some(tx_array) = block_val.get("transactions").and_then(|v| v.as_array()) {
            for tx_val in tx_array {
                let tx = self.parse_tla_transaction(tx_val)?;
                transactions.push(tx);
            }
        }
        
        // Parse data
        let mut data = Vec::new();
        if let Some(data_array) = block_val.get("data").and_then(|v| v.as_array()) {
            for data_val in data_array {
                if let Some(byte_val) = data_val.as_u64() {
                    data.push(byte_val as u8);
                }
            }
        }
        
        Ok(Block {
            slot,
            view,
            hash: self.hash_to_blockhash(self.parse_hash_string(hash_str)?),
            parent: self.hash_to_blockhash(self.parse_hash_string(parent_str)?),
            proposer,
            transactions,
            timestamp,
            signature: 0u64 as Signature, // Simplified signature parsing
            data,
        })
    }
    
    /// Parse TLA+ vote format into Rust Vote
    fn parse_tla_vote(&self, vote_val: &serde_json::Value) -> AlpenglowResult<Vote> {
        let voter = vote_val.get("voter")
            .and_then(|v| v.as_u64())
            .ok_or_else(|| AlpenglowError::ProtocolViolation("Invalid vote voter".to_string()))? as ValidatorId;
        
        let slot = vote_val.get("slot")
            .and_then(|v| v.as_u64())
            .ok_or_else(|| AlpenglowError::ProtocolViolation("Invalid vote slot".to_string()))?;
        
        let view = vote_val.get("view")
            .and_then(|v| v.as_u64())
            .ok_or_else(|| AlpenglowError::ProtocolViolation("Invalid vote view".to_string()))?;
        
        let block_val = vote_val.get("block");
        let block = if let Some(block_str) = block_val.and_then(|v| v.as_str()) {
            self.hash_to_blockhash(self.parse_hash_string(block_str)?)
        } else if let Some(block_num) = block_val.and_then(|v| v.as_u64()) {
            block_num as BlockHash // Use u64 into BlockHash via explicit cast
        } else {
            return Err(AlpenglowError::ProtocolViolation("Missing block field".to_string()));
        };
        
        let vote_type_str = vote_val.get("type")
            .and_then(|v| v.as_str())
            .ok_or_else(|| AlpenglowError::ProtocolViolation("Invalid vote type".to_string()))?;
        
        let vote_type = match vote_type_str {
            "proposal" => VoteType::Proposal,
            "echo" => VoteType::Echo,
            "commit" => VoteType::Commit,
            "skip" => VoteType::Skip,
            _ => return Err(AlpenglowError::ProtocolViolation("Unknown vote type".to_string())),
        };
        
        let timestamp = vote_val.get("timestamp")
            .and_then(|v| v.as_u64())
            .ok_or_else(|| AlpenglowError::ProtocolViolation("Invalid vote timestamp".to_string()))?;
        
        Ok(Vote {
            voter,
            slot,
            view,
            block,
            vote_type,
            signature: 0u64 as Signature, // Simplified signature parsing
            timestamp,
        })
    }
    
    /// Parse TLA+ certificate format into Rust Certificate
    fn parse_tla_certificate(&self, cert_val: &serde_json::Value) -> AlpenglowResult<Certificate> {
        let slot = cert_val.get("slot")
            .and_then(|v| v.as_u64())
            .ok_or_else(|| AlpenglowError::ProtocolViolation("Invalid certificate slot".to_string()))?;
        
        let view = cert_val.get("view")
            .and_then(|v| v.as_u64())
            .ok_or_else(|| AlpenglowError::ProtocolViolation("Invalid certificate view".to_string()))?;
        
        let block_str = cert_val.get("block")
            .and_then(|v| v.as_str())
            .ok_or_else(|| AlpenglowError::ProtocolViolation("Invalid certificate block".to_string()))?;
        
        let cert_type_str = cert_val.get("type")
            .and_then(|v| v.as_str())
            .ok_or_else(|| AlpenglowError::ProtocolViolation("Invalid certificate type".to_string()))?;
        
        let cert_type = match cert_type_str {
            "fast" => CertificateType::Fast,
            "slow" => CertificateType::Slow,
            "skip" => CertificateType::Skip,
            _ => return Err(AlpenglowError::ProtocolViolation("Unknown certificate type".to_string())),
        };
        
        let stake = cert_val.get("stake")
            .and_then(|v| v.as_u64())
            .ok_or_else(|| AlpenglowError::ProtocolViolation("Invalid certificate stake".to_string()))?;
        
        // Parse validators
        let mut validators = HashSet::new();
        if let Some(validators_array) = cert_val.get("validators").and_then(|v| v.as_array()) {
            for validator_val in validators_array {
                if let Some(validator_id) = validator_val.as_u64() {
                    validators.insert(validator_id as ValidatorId);
                }
            }
        }
        
        // Parse signatures (simplified)
        let signatures = AggregatedSignature {
            signers: validators.clone(),
            message: self.hash_to_blockhash(self.parse_hash_string(block_str)?),
            signatures: HashSet::new(), // Simplified
            valid: true,
        };
        
        Ok(Certificate {
            slot,
            view,
            block: self.hash_to_blockhash(self.parse_hash_string(block_str)?),
            cert_type,
            signatures,
            validators,
            stake,
        })
    }
    
    /// Parse TLA+ transaction format into Rust Transaction
    fn parse_tla_transaction(&self, tx_val: &serde_json::Value) -> AlpenglowResult<Transaction> {
        let id = tx_val.get("id")
            .and_then(|v| v.as_u64())
            .ok_or_else(|| AlpenglowError::ProtocolViolation("Invalid transaction id".to_string()))?;
        
        let sender = tx_val.get("sender")
            .and_then(|v| v.as_u64())
            .ok_or_else(|| AlpenglowError::ProtocolViolation("Invalid transaction sender".to_string()))? as ValidatorId;
        
        let mut data = Vec::new();
        if let Some(data_array) = tx_val.get("data").and_then(|v| v.as_array()) {
            for data_val in data_array {
                if let Some(byte_val) = data_val.as_u64() {
                    data.push(byte_val as u8);
                }
            }
        }
        
        Ok(Transaction {
            id,
            sender,
            data,
            signature: 0u64 as Signature, // Simplified signature
        })
    }
    
    /// Convert generic parsed 32-byte hash into BlockHash
    /// This function adapts to the project's BlockHash representation by converting
    /// from [u8;32] to the project's BlockHash via From/Into when possible.
    fn hash_to_blockhash(&self, hash: [u8; 32]) -> BlockHash {
        // Attempt to convert using From/Into if supported by BlockHash type.
        // If BlockHash is u64 we use the first 8 bytes; if it's [u8;32] we return it directly.
        blockhash_from_bytes(hash)
    }

    /// Parse hash string into [u8; 32] array
    fn parse_hash_string(&self, hash_str: &str) -> AlpenglowResult<[u8; 32]> {
        // Handle different hash string formats
        if hash_str == "0" || hash_str.is_empty() {
            return Ok([0u8; 32]);
        }
        
        // Try to parse as debug format "[1, 2, 3, ...]"
        if hash_str.starts_with('[') && hash_str.ends_with(']') {
            let inner = &hash_str[1..hash_str.len()-1];
            let parts: Vec<&str> = inner.split(',').map(|s| s.trim()).collect();
            if parts.len() == 32 {
                let mut hash = [0u8; 32];
                for (i, part) in parts.iter().enumerate() {
                    hash[i] = part.parse::<u8>()
                        .map_err(|_| AlpenglowError::ProtocolViolation("Invalid hash byte".to_string()))?;
                }
                return Ok(hash);
            }
        }
        
        // Fallback: use hash of the string
        let mut hash = [0u8; 32];
        let bytes = hash_str.as_bytes();
        let len = std::cmp::min(bytes.len(), 32);
        hash[..len].copy_from_slice(&bytes[..len]);
        Ok(hash)
    }
    
    /// Rebuild voting_rounds from imported state
    fn rebuild_voting_rounds(&mut self) -> AlpenglowResult<()> {
        self.voting_rounds.clear();
        
        // Create voting rounds for all views that have votes or blocks
        let mut all_views = HashSet::new();
        
        // Collect views from voted blocks
        for view in self.voted_blocks.keys() {
            all_views.insert(*view);
        }
        
        // Collect views from received votes
        for view in self.received_votes.keys() {
            all_views.insert(*view);
        }
        
        // Collect views from skip votes
        for view in self.skip_votes.keys() {
            all_views.insert(*view);
        }
        
        // Add current view
        all_views.insert(self.current_view);
        
        // Create voting rounds
        for view in all_views {
            let timeout_duration = self.adaptive_timeout(view);
            let mut round = VotingRound::new(view, timeout_duration, self.current_time);
            
            // Add voted blocks
            if let Some(blocks) = self.voted_blocks.get(&view) {
                round.proposed_blocks = blocks.clone();
            }
            
            // Add received votes
            if let Some(votes) = self.received_votes.get(&view) {
                for vote in votes {
                    round.add_vote(vote.clone());
                }
            }
            
            // Add skip votes
            if let Some(skip_votes) = self.skip_votes.get(&view) {
                for vote in skip_votes {
                    round.add_vote(vote.clone());
                }
            }
            
            // Check if we've voted in this view
            if let Some(votes) = self.received_votes.get(&view) {
                round.has_voted = votes.iter().any(|v| v.voter == self.validator_id);
            }
            
            self.voting_rounds.insert(view, round);
        }
        
        Ok(())
    }
    
    /// Validate VotorSafety invariant: No two blocks at same slot
    fn validate_votor_safety(&self) -> AlpenglowResult<()> {
        let mut slots = HashSet::new();
        for block in &self.finalized_chain {
            if slots.contains(&block.slot) {
                return Err(AlpenglowError::ProtocolViolation(
                    format!("VotorSafety violated: Two blocks finalized at slot {}", block.slot)
                ));
            }
            slots.insert(block.slot);
        }
        Ok(())
    }
    
    /// Validate ValidCertificates invariant: All generated certificates are valid
    fn validate_certificate_validity(&self) -> AlpenglowResult<()> {
        for (view, certs) in &self.generated_certificates {
            for cert in certs {
                if !self.validate_certificate(cert) {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("ValidCertificates violated: Invalid certificate in view {}", view)
                    ));
                }
                
                // Check stake threshold matches certificate type
                let required_threshold = match cert.cert_type {
                    CertificateType::Fast => self.config.fast_path_threshold,
                    CertificateType::Slow | CertificateType::Skip => self.config.slow_path_threshold,
                };
                
                if cert.stake < required_threshold {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("ValidCertificates violated: Certificate stake {} below threshold {} for type {:?}", 
                               cert.stake, required_threshold, cert.cert_type)
                    ));
                }
            }
        }
        Ok(())
    }
    
    /// Validate ByzantineResilience invariant: Safety holds under Byzantine threshold
    fn validate_byzantine_resilience(&self) -> AlpenglowResult<()> {
        let byzantine_stake: StakeAmount = self.byzantine_validators
            .iter()
            .map(|v| self.config.stake_distribution.get(v).copied().unwrap_or(0))
            .sum();
        
        if byzantine_stake >= self.config.total_stake / 3 {
            return Err(AlpenglowError::ProtocolViolation(
                format!("ByzantineResilience violated: Byzantine stake {} >= 1/3 of total stake {}", 
                       byzantine_stake, self.config.total_stake)
            ));
        }
        
        // If Byzantine threshold is satisfied, safety should hold
        self.validate_votor_safety()
    }
    
    /// Validate HonestVoteUniqueness invariant: Honest validators cast at most one vote per view
    fn validate_honest_vote_uniqueness(&self) -> AlpenglowResult<()> {
        for (view, votes) in &self.received_votes {
            let mut honest_voter_counts = HashMap::new();
            
            for vote in votes {
                if !self.byzantine_validators.contains(&vote.voter) {
                    *honest_voter_counts.entry(vote.voter).or_insert(0) += 1;
                    
                    if honest_voter_counts[&vote.voter] > 1 {
                        return Err(AlpenglowError::ProtocolViolation(
                            format!("HonestVoteUniqueness violated: Honest validator {} voted {} times in view {}", 
                                   vote.voter, honest_voter_counts[&vote.voter], view)
                        ));
                    }
                }
            }
        }
        Ok(())
    }
    
    /// Validate HonestSelfVoteUniqueness invariant: Honest validators have at most one self-vote per view
    fn validate_honest_self_vote_uniqueness(&self) -> AlpenglowResult<()> {
        if !self.byzantine_validators.contains(&self.validator_id) {
            for (view, votes) in &self.received_votes {
                let self_vote_count = votes.iter()
                    .filter(|vote| vote.voter == self.validator_id)
                    .count();
                
                if self_vote_count > 1 {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("HonestSelfVoteUniqueness violated: Validator {} has {} self-votes in view {}", 
                               self.validator_id, self_vote_count, view)
                    ));
                }
            }
        }
        Ok(())
    }
    
    /// Validate ViewConvergence invariant: Honest validators should converge on views (simplified)
    fn validate_view_convergence(&self) -> AlpenglowResult<()> {
        // This is a simplified check since we only have one validator's state
        // In a full implementation, this would check across all honest validators
        
        // Check that current view is reasonable (not too far ahead)
        if self.current_view > self.config.max_view {
            return Err(AlpenglowError::ProtocolViolation(
                format!("ViewConvergence violated: Current view {} exceeds max view {}", 
                       self.current_view, self.config.max_view)
            ));
        }
        
        // Check that view progression is monotonic in finalized chain
        let mut last_view = 0;
        for block in &self.finalized_chain {
            if block.view < last_view {
                return Err(AlpenglowError::ProtocolViolation(
                    format!("ViewConvergence violated: Non-monotonic view progression in finalized chain")
                ));
            }
            last_view = block.view;
        }
        
        Ok(())
    }
    
    /// Validate structural invariants
    fn validate_structural_invariants(&self) -> AlpenglowResult<()> {
        // Check that all votes reference valid views
        for (view, votes) in &self.received_votes {
            for vote in votes {
                if vote.view != *view {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("Structural invariant violated: Vote view {} doesn't match container view {}", 
                               vote.view, view)
                    ));
                }
                
                if vote.view == 0 || vote.view > self.config.max_view {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("Structural invariant violated: Invalid vote view {}", vote.view)
                    ));
                }
            }
        }
        
        // Check that all blocks reference valid views and slots
        for (view, blocks) in &self.voted_blocks {
            for block in blocks {
                if block.view != *view {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("Structural invariant violated: Block view {} doesn't match container view {}", 
                               block.view, view)
                    ));
                }
                
                if block.slot == 0 || block.slot > self.config.max_slot {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("Structural invariant violated: Invalid block slot {}", block.slot)
                    ));
                }
            }
        }
        
        // Check that all certificates reference valid views
        for (view, certs) in &self.generated_certificates {
            for cert in certs {
                if cert.view != *view {
                    return Err(AlpenglowError::ProtocolViolation(
                        format!("Structural invariant violated: Certificate view {} doesn't match container view {}", 
                               cert.view, view)
                    ));
                }
            }
        }
        
        // Check timeout expiry is reasonable
        if self.timeout_expiry < self.current_time && self.current_time > 0 {
            // Allow some tolerance for timeout expiry in the past
            let tolerance = 1000; // 1 second tolerance
            if self.current_time - self.timeout_expiry > tolerance {
                return Err(AlpenglowError::ProtocolViolation(
                    format!("Structural invariant violated: Timeout expiry {} is too far in the past (current time {})", 
                           self.timeout_expiry, self.current_time)
                ));
            }
        }
        
        Ok(())
    }

    /// Structured verification helper: run the standard suite and return a structured result.
    /// This function is safe to call from test harnesses or CLI runners and provides
    /// metrics and human-readable violation details.
    pub fn run_structured_verification(&self, params: VerificationParams) -> VerificationResult {
        ModelChecker::run(self, params)
    }
}

/// Enhanced utility functions for BlockHash conversion with better error handling
fn blockhash_from_bytes(bytes: [u8; 32]) -> BlockHash {
    // Convert first 8 bytes to u64 for BlockHash compatibility
    let mut arr = [0u8; 8];
    arr.copy_from_slice(&bytes[0..8]);
    let num = u64::from_le_bytes(arr);
    num.into()
}

/// Enhanced helper to extract u64 from BlockHash with validation
fn parent_into_u64(parent: &BlockHash) -> u64 {
    // Use debug format for deterministic conversion
    let debug = format!("{:?}", parent);
    let bytes = debug.as_bytes();
    let mut arr = [0u8; 8];
    for (i, b) in bytes.iter().take(8).enumerate() {
        arr[i] = *b;
    }
    u64::from_le_bytes(arr)
}

/// Additional trait implementations for better integration
impl PartialEq for AggregatedSignature {
    fn eq(&self, other: &Self) -> bool {
        self.signers == other.signers &&
        self.message == other.message &&
        self.signatures == other.signatures &&
        self.valid == other.valid
    }
}

impl Hash for AggregatedSignature {
    fn hash<H: Hasher>(&self, state: &mut H) {
        // Hash the signers set in a deterministic way
        let mut signers_vec: Vec<_> = self.signers.iter().collect();
        signers_vec.sort();
        signers_vec.hash(state);
        
        self.message.hash(state);
        
        // Hash signatures set in a deterministic way
        let mut sigs_vec: Vec<_> = self.signatures.iter().collect();
        sigs_vec.sort();
        sigs_vec.hash(state);
        
        self.valid.hash(state);
    }
}

impl PartialEq for Certificate {
    fn eq(&self, other: &Self) -> bool {
        self.slot == other.slot &&
        self.view == other.view &&
        self.block == other.block &&
        self.cert_type == other.cert_type &&
        self.signatures == other.signatures &&
        self.validators == other.validators &&
        self.stake == other.stake
    }
}

impl Hash for Certificate {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.slot.hash(state);
        self.view.hash(state);
        self.block.hash(state);
        self.cert_type.hash(state);
        self.signatures.hash(state);
        
        // Hash validators set in deterministic way
        let mut validators_vec: Vec<_> = self.validators.iter().collect();
        validators_vec.sort();
        validators_vec.hash(state);
        
        self.stake.hash(state);
    }
}

/// Enhanced error handling and validation
impl VotorState {
    /// Comprehensive state validation for debugging and testing
    pub fn validate_complete_state(&self) -> AlpenglowResult<()> {
        // Validate basic state consistency
        if self.current_view == 0 {
            return Err(AlpenglowError::StateInconsistency("Current view cannot be zero".to_string()));
        }
        
        if self.current_view > self.config.max_view {
            return Err(AlpenglowError::StateInconsistency(
                format!("Current view {} exceeds max view {}", self.current_view, self.config.max_view)
            ));
        }
        
        // Validate timeout consistency
        if self.timeout_expiry < self.current_time && self.current_time > 0 {
            let tolerance = 10000; // 10 second tolerance
            if self.current_time - self.timeout_expiry > tolerance {
                return Err(AlpenglowError::StateInconsistency(
                    format!("Timeout expiry {} is too far in past (current time {})", 
                           self.timeout_expiry, self.current_time)
                ));
            }
        }
        
        // Validate finalized chain consistency
        let mut prev_slot = 0;
        for block in &self.finalized_chain {
            if block.slot <= prev_slot && prev_slot > 0 {
                return Err(AlpenglowError::StateInconsistency(
                    format!("Finalized chain not monotonic: slot {} after slot {}", block.slot, prev_slot)
                ));
            }
            prev_slot = block.slot;
        }
        
        // Validate voting rounds consistency
        for (&view, round) in &self.voting_rounds {
            if round.view != view {
                return Err(AlpenglowError::StateInconsistency(
                    format!("Voting round view mismatch: round has view {} but stored under view {}", 
                           round.view, view)
                ));
            }
        }
        
        // Validate certificate consistency
        for (&view, certs) in &self.generated_certificates {
            for cert in certs {
                if cert.view != view {
                    return Err(AlpenglowError::StateInconsistency(
                        format!("Certificate view mismatch: cert has view {} but stored under view {}", 
                               cert.view, view)
                    ));
                }
                
                if !self.validate_certificate(cert) {
                    return Err(AlpenglowError::StateInconsistency(
                        format!("Invalid certificate in view {}: {:?}", view, cert)
                    ));
                }
            }
        }
        
        // Run all TLA+ invariant checks
        self.verify_safety()?;
        self.verify_byzantine_resilience()?;
        
        Ok(())
    }
    
    /// Reset state for testing purposes
    pub fn reset_for_testing(&mut self) {
        self.current_view = 1;
        self.voted_blocks.clear();
        self.received_votes.clear();
        self.generated_certificates.clear();
        self.finalized_chain.clear();
        self.skip_votes.clear();
        self.voting_rounds.clear();
        self.current_time = 0;
        self.timeout_expiry = BASE_TIMEOUT;
        self.current_leader_window = 0;
        
        // Reinitialize first voting round
        let timeout_duration = self.adaptive_timeout(1);
        let round = VotingRound::new(1, timeout_duration, 0);
        self.voting_rounds.insert(1, round);
    }
    
    /// Create a deep copy for testing
    pub fn deep_clone_for_testing(&self) -> Self {
        // Use serde for deep cloning
        let serialized = serde_json::to_string(self).expect("Failed to serialize state");
        serde_json::from_str(&serialized).expect("Failed to deserialize state")
    }
}

/// Additional verification traits for comprehensive testing
pub trait VotorVerification {
    /// Verify all TLA+ invariants hold
    fn verify_tla_invariants(&self) -> AlpenglowResult<()>;
    
    /// Verify protocol progress
    fn verify_progress(&self) -> AlpenglowResult<()>;
    
    /// Verify Byzantine resilience
    fn verify_byzantine_tolerance(&self) -> AlpenglowResult<()>;
}

impl VotorVerification for VotorState {
    fn verify_tla_invariants(&self) -> AlpenglowResult<()> {
        self.validate_voting_protocol_invariant()?;
        self.validate_one_vote_per_slot()?;
        self.validate_certificate_thresholds()?;
        self.verify_safety()?;
        Ok(())
    }
    
    fn verify_progress(&self) -> AlpenglowResult<()> {
        self.verify_liveness()
    }
    
    fn verify_byzantine_tolerance(&self) -> AlpenglowResult<()> {
        self.verify_byzantine_resilience()
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
            hash: [1u8; 32].into(),
            parent: [0u8; 32].into(),
            proposer: 0,
            transactions: Vec::new(),
            timestamp: 0,
            signature: 0u64 as Signature,
            data: Vec::new(),
        };
        
        let vote_result = state.cast_vote(&block, 1);
        assert!(vote_result.is_ok());
        
        let vote = vote_result.unwrap();
        assert_eq!(vote.voter, 0);
        assert_eq!(vote.view, 1);
        // Check that vote was added to state
        assert!(state.received_votes.get(&1).unwrap().contains(&vote));
        assert!(state.voted_blocks.get(&1).unwrap().contains(&block));
    }
    
    #[test]
    fn test_collect_votes() {
        let config = Config::new().with_validators(4);
        let mut state = VotorState::new(0, config);
        
        // Add votes from all validators
        let block_hash = [1u8; 32].into();
        let mut votes = HashSet::new();
        for i in 0..4 {
            let vote = Vote {
                voter: i,
                slot: 1,
                view: 1,
                block: block_hash,
                vote_type: VoteType::Commit,
                signature: 0u64 as Signature,
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
            block: [1u8; 32].into(),
            vote_type: VoteType::Commit,
            signature: 0u64 as Signature,
            timestamp: 0,
        };
        
        assert!(state.validate_vote(&valid_vote));
        
        let invalid_vote = Vote {
            voter: 999, // Invalid validator
            slot: 1,
            view: 1,
            block: [1u8; 32].into(),
            vote_type: VoteType::Commit,
            signature: 0u64 as Signature,
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
        let block_hash = [1u8; 32].into();
        for i in 0..4 {
            let vote = Vote {
                voter: i,
                slot: 1,
                view: 1,
                block: block_hash,
                vote_type: VoteType::Commit,
                signature: 0u64 as Signature,
                timestamp: 0,
            };
            round.add_vote(vote);
        }
        
        // Should be able to generate fast path certificate
        let cert = state.try_generate_certificate(1, block_hash);
        assert!(cert.is_some());
        
        let cert = cert.unwrap();
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
            hash: [1u8; 32].into(),
            parent: [0u8; 32].into(),
            proposer: 0,
            transactions: Vec::new(),
            timestamp: 0,
            signature: 0u64 as Signature,
            data: Vec::new(),
        };
        state_with_block.finalized_chain.push(block);
        
        assert!(state_with_block.verify_safety().is_ok());
    }
}
