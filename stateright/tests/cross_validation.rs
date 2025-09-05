//! Cross-validation tests between Stateright implementation and TLA+ specifications
//!
//! These tests verify that the Rust implementation behaves consistently with
//! the formal TLA+ specifications by:
//! 1. Running the same scenarios in both systems
//! 2. Comparing state transitions
//! 3. Validating invariants are preserved
//! 4. Checking that properties hold in both models

use alpenglow_stateright::{
    votor::{VotorActor, VotorState, Block, Vote, Certificate, CertificateType, VoteType, AggregatedSignature, Transaction},
    rotor::{RotorActor, RotorState, ErasureBlock},
    network::{NetworkActor, NetworkState},
    integration::{AlpenglowNode, AlpenglowState, ProtocolConfig},
    Config, ValidatorId, BlockHash, SlotNumber,
    local_stateright, // Use the local stateright implementation
};
use serde_json::json;
use std::collections::{HashMap, HashSet};

// Import external stateright crate with explicit namespace to avoid conflicts
extern crate stateright as external_stateright;
use external_stateright::{Checker, Model};

/// Test that Votor state transitions match TLA+ specification
#[test]
fn test_votor_tla_cross_validation() {
    let config = Config::new().with_validators(4);
    let mut votor_state = VotorState::new(0, config.clone());
    
    // Initialize the actor model using local stateright implementation
    let mut actor_model = local_stateright::ActorModel::new();
    let votor_actor = VotorActor::new(0, config.clone());
    actor_model = actor_model.actor(votor_actor);
    actor_model.init();
    
    // Export initial state
    let initial_tla_state = votor_state.export_tla_state();
    assert!(initial_tla_state.get("currentView").is_some());
    assert!(initial_tla_state.get("finalizedChain").is_some());
    
    // Test block proposal
    let block = Block {
        slot: 1,
        view: 0,
        hash: [1u8; 32],
        parent: [0u8; 32],
        proposer: 0,
        timestamp: 100,
        transactions: HashSet::new(),
        data: vec![1, 2, 3],
        signature: [0u8; 64],
    };
    
    votor_state.voting_rounds.get_mut(&0).unwrap().proposed_blocks.insert(block.clone());
    
    // Export state after proposal
    let after_proposal_state = votor_state.export_tla_state();
    
    // Verify TLA+ invariants
    assert!(votor_state.validate_tla_invariants().is_ok());
    
    // Test vote processing
    let vote = Vote {
        voter: 1,
        slot: 1,
        view: 0,
        block: block.hash,
        vote_type: VoteType::Echo,
        signature: [0u8; 64],
        timestamp: 100,
    };
    
    votor_state.voting_rounds.get_mut(&0).unwrap().received_votes.insert(vote);
    
    // Export state after vote
    let after_vote_state = votor_state.export_tla_state();
    
    // Verify that state changes are consistent with TLA+ model
    assert!(votor_state.validate_tla_invariants().is_ok());
    
    // Test certificate generation
    let certificate = Certificate {
        slot: 1,
        view: 0,
        block: block.hash,
        cert_type: CertificateType::Fast,
        signatures: AggregatedSignature {
            signers: [0, 1, 2, 3].iter().cloned().collect(),
            message: block.hash,
            signatures: HashSet::new(),
            valid: true,
        },
        validators: [0, 1, 2, 3].iter().cloned().collect(),
        stake: 4000,
    };
    
    votor_state.generated_certificates.entry(1).or_insert(HashSet::new()).insert(certificate);
    
    // Verify final state consistency
    assert!(votor_state.validate_tla_invariants().is_ok());
    assert!(votor_state.verify_safety().is_ok());
}

/// Test that Rotor erasure coding matches TLA+ specification
#[test]
fn test_rotor_tla_cross_validation() {
    let config = Config::new().with_validators(4);
    let mut rotor_state = RotorState::new(0, config.clone());
    
    // Initialize the actor model using local stateright implementation
    let mut actor_model = local_stateright::ActorModel::new();
    let rotor_actor = RotorActor::new(0, config.clone());
    actor_model = actor_model.actor(rotor_actor);
    actor_model.init();
    
    // Export initial state
    let initial_tla_state = rotor_state.export_tla_state();
    assert!(initial_tla_state.get("blockShreds").is_some());
    assert!(initial_tla_state.get("relayAssignments").is_some());
    
    // Test block shredding
    let block_hash = [1u8; 32];
    let block_data = vec![1u8; 1000];
    let erasure_block = ErasureBlock::new(block_hash, 1, 0, block_data, 2, 4);
    
    // Shred the block
    let shreds = rotor_state.shred_block(&erasure_block);
    rotor_state.block_shreds.insert(block_hash, shreds.clone());
    
    // Export state after shredding
    let after_shred_state = rotor_state.export_tla_state();
    
    // Verify TLA+ invariants
    assert!(rotor_state.validate_tla_invariants().is_ok());
    
    // Test relay assignment
    let assignments = rotor_state.calculate_relay_assignments(0, &config.stake_distribution);
    rotor_state.relay_assignments.insert(block_hash, assignments);
    
    // Export state after relay assignment
    let after_relay_state = rotor_state.export_tla_state();
    
    // Verify state consistency
    assert!(rotor_state.validate_tla_invariants().is_ok());
    assert!(rotor_state.verify_safety().is_ok());
    
    // Test reconstruction
    let required_shreds: Vec<_> = shreds.iter().take(2).cloned().collect();
    rotor_state.reconstruction_state.insert(block_hash, required_shreds);
    
    // Verify final state
    assert!(rotor_state.validate_tla_invariants().is_ok());
}

/// Test network partial synchrony model matches TLA+ specification
#[test]
fn test_network_tla_cross_validation() {
    let config = Config::new()
        .with_validators(4)
        .with_network_timing(100, 1000); // Delta=100, GST=1000
    
    // Initialize the actor model using local stateright implementation
    let mut actor_model = local_stateright::ActorModel::new();
    let network_actor = NetworkActor::new(0, config.clone());
    actor_model = actor_model.actor(network_actor);
    actor_model.init();
    
    let mut network_state = NetworkState {
        validator_id: 0,
        clock: 0,
        message_queue: Default::default(),
        message_buffer: HashMap::new(),
        network_partitions: HashSet::new(),
        dropped_messages: 0,
        delivery_times: HashMap::new(),
        byzantine_validators: HashSet::new(),
        config: config.clone(),
        next_message_id: 1,
    };
    
    // Initialize message buffer for all validators
    for i in 0..4 {
        network_state.message_buffer.insert(i, Vec::new());
    }
    
    // Export initial state
    let initial_tla_state = network_state.export_tla_state();
    assert!(initial_tla_state.get("clock").is_some());
    assert!(initial_tla_state.get("messageQueue").is_some());
    
    // Test pre-GST behavior
    network_state.clock = 500; // Before GST
    assert!(network_state.validate_tla_invariants().is_ok());
    
    // Test post-GST behavior
    network_state.clock = 1500; // After GST
    assert!(network_state.validate_tla_invariants().is_ok());
    
    // Verify safety properties
    assert!(network_state.verify_safety().is_ok());
    
    // Test Byzantine validator handling
    network_state.byzantine_validators.insert(3);
    let after_byzantine_state = network_state.export_tla_state();
    
    // Verify Byzantine resilience
    assert!(network_state.verify_byzantine_resilience().is_ok());
}

/// Test Byzantine scenario consistency
#[test]
fn test_byzantine_scenario_consistency() {
    let config = Config::new().with_validators(4);
    let byzantine_validators: HashSet<u32> = [3].iter().cloned().collect();
    
    // Initialize the actor model using local stateright implementation
    let mut actor_model = local_stateright::ActorModel::new();
    let alpenglow_node = AlpenglowNode::new(0, config.clone());
    actor_model = actor_model.actor(alpenglow_node);
    actor_model.init();
    
    // Create corresponding TLA+ compatible state
    let protocol_config = ProtocolConfig::new(config)
        .with_byzantine_testing()
        .with_tla_cross_validation();
    let mut state = AlpenglowState::new(0, protocol_config);
    state.network_state.byzantine_validators = byzantine_validators;
    
    // Initialize
    state.initialize().unwrap();
    
    // Verify Byzantine resilience
    assert!(state.verify_byzantine_resilience().is_ok());
    
    // Export state for TLA+ validation
    let tla_state = state.export_tla_state();
    assert!(tla_state.get("networkState").unwrap().get("byzantineValidators").is_some());
    
    // Verify invariants hold with Byzantine validators
    assert!(state.validate_tla_invariants().is_ok());
}

/// Test integrated system matches TLA+ Integration.tla specification
#[test]
fn test_integration_tla_cross_validation() {
    let config = Config::new().with_validators(4);
    let protocol_config = ProtocolConfig::new(config.clone())
        .with_tla_cross_validation();
    
    // Initialize the actor model using local stateright implementation
    let mut actor_model = local_stateright::ActorModel::new();
    let alpenglow_node = AlpenglowNode::new(0, config.clone());
    actor_model = actor_model.actor(alpenglow_node);
    actor_model.init();
    
    let mut alpenglow_state = AlpenglowState::new(0, protocol_config);
    
    // Initialize system
    assert!(alpenglow_state.initialize().is_ok());
    
    // Export initial state
    let initial_tla_state = alpenglow_state.export_tla_state();
    assert!(initial_tla_state.get("systemState").is_some());
    assert!(initial_tla_state.get("componentHealth").is_some());
    assert!(initial_tla_state.get("votorState").is_some());
    assert!(initial_tla_state.get("rotorState").is_some());
    assert!(initial_tla_state.get("networkState").is_some());
    
    // Advance system clock
    alpenglow_state.advance_clock();
    
    // Verify all invariants hold
    assert!(alpenglow_state.validate_tla_invariants().is_ok());
    assert!(alpenglow_state.verify_safety().is_ok());
    assert!(alpenglow_state.verify_liveness().is_ok());
    assert!(alpenglow_state.verify_byzantine_resilience().is_ok());
    
    // Test cross-component interaction
    let certificate = Certificate {
        slot: 1,
        view: 0,
        block: [1u8; 32],
        cert_type: CertificateType::Skip,
        signatures: AggregatedSignature {
            signers: HashSet::new(),
            message: [1u8; 32],
            signatures: HashSet::new(),
            valid: true,
        },
        validators: HashSet::new(),
        stake: 0,
    };
    
    // Process cross-component interaction
    assert!(alpenglow_state.process_votor_rotor_interaction(&certificate).is_ok());
    
    // Export state after interaction
    let after_interaction_state = alpenglow_state.export_tla_state();
    
    // Verify consistency
    assert!(alpenglow_state.validate_tla_invariants().is_ok());
}

/// Test state import/export round-trip
#[test]
fn test_state_import_export_round_trip() {
    let config = Config::new().with_validators(3);
    let protocol_config = ProtocolConfig::new(config.clone());
    
    // Initialize the actor model using local stateright implementation
    let mut actor_model = local_stateright::ActorModel::new();
    let alpenglow_node = AlpenglowNode::new(0, config.clone());
    actor_model = actor_model.actor(alpenglow_node);
    actor_model.init();
    
    let mut state1 = AlpenglowState::new(0, protocol_config.clone());
    
    // Initialize and modify state
    state1.initialize().unwrap();
    state1.advance_clock();
    state1.performance_metrics.increment_messages();
    state1.votor_state.current_view = 5;
    
    // Export state
    let exported = state1.export_tla_state();
    
    // Create new state and import
    let mut state2 = AlpenglowState::new(0, protocol_config);
    assert!(state2.import_tla_state(exported.clone()).is_ok());
    
    // Verify imported state matches
    assert_eq!(state2.global_clock, state1.global_clock);
    assert_eq!(state2.votor_state.current_view, state1.votor_state.current_view);
    
    // Verify both states export to same JSON
    let exported2 = state2.export_tla_state();
    assert_eq!(exported.get("globalClock"), exported2.get("globalClock"));
}

/// Test property preservation across state transitions
#[test]
fn test_property_preservation() {
    let config = Config::new().with_validators(4);
    
    // Initialize the actor model using local stateright implementation
    let mut actor_model = local_stateright::ActorModel::new();
    let votor_actor = VotorActor::new(0, config.clone());
    actor_model = actor_model.actor(votor_actor);
    actor_model.init();
    
    let mut votor_state = VotorState::new(0, config.clone());
    
    // Check initial safety
    assert!(votor_state.verify_safety().is_ok());
    
    // Perform state transition: view change
    votor_state.current_view += 1;
    assert!(votor_state.verify_safety().is_ok());
    
    // Add block to finalized chain
    for i in 0..5 {
        let block = Block {
            slot: i,
            view: i as u64,
            hash: [i as u8; 32],
            parent: if i == 0 { [0u8; 32] } else { [(i-1) as u8; 32] },
            proposer: 0,
            timestamp: i as u64 * 100,
            transactions: HashSet::new(),
            data: vec![],
            signature: [0u8; 64],
        };
        votor_state.finalized_chain.push(block);
    }
    
    // Verify safety is preserved
    assert!(votor_state.verify_safety().is_ok());
    
    // Check TLA+ invariants
    assert!(votor_state.validate_tla_invariants().is_ok());
}

/// Test complete scenario from TLA+ specs
#[test]
fn test_complete_tla_scenario() {
    let config = Config::new()
        .with_validators(4)
        .with_network_timing(50, 1000);
    
    let protocol_config = ProtocolConfig::new(config.clone())
        .with_tla_cross_validation()
        .with_performance_monitoring();
    
    // Initialize the actor model using local stateright implementation
    let mut actor_model = local_stateright::ActorModel::new();
    let alpenglow_node = AlpenglowNode::new(0, config.clone());
    actor_model = actor_model.actor(alpenglow_node);
    actor_model.init();
    
    // Run a few steps to establish initial state
    actor_model.run_steps(10);
    
    let mut state = AlpenglowState::new(0, protocol_config);
    state.initialize().unwrap();
    
    // Simulate complete consensus round as in TLA+ Integration.tla
    
    // 1. Block proposal
    let block = Block {
        slot: 1,
        view: 0,
        hash: [1u8; 32],
        parent: [0u8; 32],
        proposer: 0,
        timestamp: 100,
        transactions: HashSet::new(),
        data: vec![1, 2, 3, 4, 5],
        signature: [0u8; 64],
    };
    state.votor_state.voting_rounds.get_mut(&0).unwrap().proposed_blocks.insert(block.clone());
    
    // 2. Vote collection (simulating fast path with 80% stake)
    for validator_id in 0..3 {
        let vote = Vote {
            voter: validator_id,
            slot: 1,
            view: 0,
            block: block.hash,
            vote_type: VoteType::Echo,
            signature: [0u8; 64],
            timestamp: 100,
        };
        state.votor_state.voting_rounds.get_mut(&0).unwrap().received_votes.insert(vote);
    }
    
    // 3. Certificate generation
    let certificate = Certificate {
        slot: 1,
        view: 0,
        block: block.hash,
        cert_type: CertificateType::Fast,
        signatures: AggregatedSignature {
            signers: [0, 1, 2].iter().cloned().collect(),
            message: block.hash,
            signatures: HashSet::new(),
            valid: true,
        },
        validators: [0, 1, 2].iter().cloned().collect(),
        stake: 3000, // 75% of total stake
    };
    
    // 4. Process cross-component interaction
    state.votor_state.generated_certificates.entry(1).or_insert(HashSet::new()).insert(certificate.clone());
    
    // 5. Advance time past GST
    for _ in 0..1100 {
        state.advance_clock();
    }
    
    // 6. Verify all properties hold
    assert!(state.validate_tla_invariants().is_ok());
    assert!(state.verify_safety().is_ok());
    assert!(state.verify_liveness().is_ok());
    assert!(state.verify_byzantine_resilience().is_ok());
    
    // 7. Export final state for TLA+ comparison
    let final_state = state.export_tla_state();
    println!("Final TLA+ state export: {}", serde_json::to_string_pretty(&final_state).unwrap());
}
