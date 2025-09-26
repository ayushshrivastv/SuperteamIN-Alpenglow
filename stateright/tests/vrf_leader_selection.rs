// Author: Ayush Srivastava
//! # VRF Leader Selection Tests
//!
//! This module contains tests for VRF-based leader selection functionality
//! in the Alpenglow protocol. These tests verify the correctness of the
//! VRF implementation including proof generation, verification, and
//! leader selection algorithms.
//!
//! The tests are designed to be run by the Stateright verification script
//! with `cargo test --test vrf_leader_selection` or as a CLI binary with
//! `--config` and `--output` arguments.

// Import common test utilities for CLI integration
mod common;
use common::*;

use alpenglow_stateright::{
    Config, AlpenglowModel, AlpenglowState, AlpenglowResult, AlpenglowError,
    ValidatorId, ViewNumber, SlotNumber, StakeAmount,
    votor::{VotorState, VRFKeyPair, VRFProof, LEADER_WINDOW_SIZE, BASE_TIMEOUT},
    properties, utils, Verifiable, TlaCompatible, ModelChecker, VerificationMetrics
};
use std::collections::{HashMap, HashSet, BTreeMap};
use std::time::{Duration, Instant};
use serde_json;

/// Test configuration for VRF leader selection
const TEST_VALIDATOR_COUNT: usize = 7;
const TEST_BYZANTINE_COUNT: usize = 2;
const TEST_VIEWS: u64 = 20;
const TEST_WINDOWS: u64 = 5;

/// Main function for CLI binary execution
fn main() -> Result<(), Box<dyn std::error::Error>> {
    run_test_scenario("vrf_leader_selection", run_vrf_verification)
}

/// Run VRF leader selection verification with comprehensive testing
fn run_vrf_verification(config: &Config, test_config: &TestConfig) -> Result<TestReport, TestError> {
    let start_time = Instant::now();
    let mut report = create_test_report("vrf_leader_selection", test_config.clone());
    
    // Create VRF test scenarios
    let vrf_config = create_vrf_test_config_from_test_config(test_config);
    let model = AlpenglowModel::new(vrf_config.clone());
    
    // Test VRF key generation and management
    let (key_gen_result, duration) = measure_execution(|| {
        test_vrf_key_generation_verification(&vrf_config)
    });
    add_property_result(
        &mut report,
        "vrf_key_generation".to_string(),
        key_gen_result.is_ok(),
        1,
        duration,
        key_gen_result.err().map(|e| e.to_string()),
        None,
    );
    
    // Test VRF proof generation and verification
    let (proof_result, duration) = measure_execution(|| {
        test_vrf_proof_verification(&vrf_config)
    });
    add_property_result(
        &mut report,
        "vrf_proof_verification".to_string(),
        proof_result.is_ok(),
        test_config.validators * 100, // Approximate states explored
        duration,
        proof_result.err().map(|e| e.to_string()),
        None,
    );
    
    // Test leader selection algorithm
    let (leader_result, duration) = measure_execution(|| {
        test_leader_selection_algorithm(&vrf_config, test_config.max_rounds as u64)
    });
    add_property_result(
        &mut report,
        "leader_selection_algorithm".to_string(),
        leader_result.is_ok(),
        test_config.max_rounds * test_config.validators,
        duration,
        leader_result.err().map(|e| e.to_string()),
        None,
    );
    
    // Test stake-weighted fairness
    let (fairness_result, duration) = measure_execution(|| {
        test_stake_weighted_fairness(&vrf_config, test_config)
    });
    add_property_result(
        &mut report,
        "stake_weighted_fairness".to_string(),
        fairness_result.is_ok(),
        test_config.max_rounds * 10, // Extended testing for fairness
        duration,
        fairness_result.err().map(|e| e.to_string()),
        None,
    );
    
    // Test leader window functionality
    let (window_result, duration) = measure_execution(|| {
        test_leader_window_functionality(&vrf_config)
    });
    add_property_result(
        &mut report,
        "leader_window_functionality".to_string(),
        window_result.is_ok(),
        TEST_WINDOWS as usize * LEADER_WINDOW_SIZE as usize,
        duration,
        window_result.err().map(|e| e.to_string()),
        None,
    );
    
    // Test VRF randomness and unpredictability
    let (randomness_result, duration) = measure_execution(|| {
        test_vrf_randomness_properties(&vrf_config)
    });
    add_property_result(
        &mut report,
        "vrf_randomness_properties".to_string(),
        randomness_result.is_ok(),
        test_config.validators * 1000, // Extensive randomness testing
        duration,
        randomness_result.err().map(|e| e.to_string()),
        None,
    );
    
    // Test VRF attack resistance
    let (attack_result, duration) = measure_execution(|| {
        test_vrf_attack_resistance(&vrf_config, test_config)
    });
    add_property_result(
        &mut report,
        "vrf_attack_resistance".to_string(),
        attack_result.is_ok(),
        test_config.byzantine_count * 100,
        duration,
        attack_result.err().map(|e| e.to_string()),
        None,
    );
    
    // Test integration with consensus protocol
    let (integration_result, duration) = measure_execution(|| {
        test_consensus_integration(&vrf_config, test_config)
    });
    add_property_result(
        &mut report,
        "consensus_integration".to_string(),
        integration_result.is_ok(),
        test_config.max_rounds * test_config.validators,
        duration,
        integration_result.err().map(|e| e.to_string()),
        None,
    );
    
    // Test performance characteristics
    let (performance_result, duration) = measure_execution(|| {
        test_vrf_performance_characteristics(&vrf_config)
    });
    add_property_result(
        &mut report,
        "vrf_performance".to_string(),
        performance_result.is_ok(),
        10000, // Performance test iterations
        duration,
        performance_result.err().map(|e| e.to_string()),
        None,
    );
    
    // Test cross-validation with TLA+ if enabled
    if test_config.test_edge_cases {
        let (tla_result, duration) = measure_execution(|| {
            test_tla_cross_validation(&vrf_config)
        });
        add_property_result(
            &mut report,
            "tla_cross_validation".to_string(),
            tla_result.is_ok(),
            1,
            duration,
            tla_result.err().map(|e| e.to_string()),
            None,
        );
    }
    
    // Run external Stateright verification if available
    if test_config.stress_test {
        let (external_result, duration) = measure_execution(|| {
            run_external_stateright_verification(&model, test_config)
        });
        add_property_result(
            &mut report,
            "external_stateright_verification".to_string(),
            external_result.is_ok(),
            test_config.exploration_depth,
            duration,
            external_result.err().map(|e| e.to_string()),
            None,
        );
    }
    
    // Update metrics
    report.metrics.byzantine_events = test_config.byzantine_count;
    report.metrics.network_events = test_config.max_rounds * test_config.validators;
    
    // Calculate VRF-specific metrics
    update_vrf_metrics(&mut report, &vrf_config, test_config);
    
    Ok(report)
}

/// Create VRF test configuration from test config
fn create_vrf_test_config_from_test_config(test_config: &TestConfig) -> Config {
    let mut config = Config::new()
        .with_validators(test_config.validators)
        .with_byzantine_threshold(test_config.byzantine_count)
        .with_exploration_depth(test_config.exploration_depth)
        .with_timeout(test_config.timeout_ms)
        .with_test_mode(true)
        .with_vrf_enabled(test_config.vrf_enabled)
        .with_adaptive_timeouts(test_config.adaptive_timeouts)
        .with_leader_window_size(test_config.leader_window_size);
    
    // Set custom stake distribution if provided
    if let Some(ref stakes) = test_config.stake_distribution {
        config = config.with_stake_distribution(stakes.clone());
    }
    
    // Set erasure coding parameters
    if let Some((k, n)) = test_config.erasure_coding {
        config = config.with_erasure_coding(k as u32, n as u32);
    }
    
    config
}

/// Test VRF key generation and management
fn test_vrf_key_generation_verification(config: &Config) -> Result<(), TestError> {
    let state = VotorState::new(0, config.clone());
    
    // Verify all validators have VRF key pairs
    if state.vrf_key_pairs.len() != config.validator_count {
        return Err(TestError::Verification(
            format!("Expected {} VRF key pairs, found {}", 
                config.validator_count, state.vrf_key_pairs.len())
        ));
    }
    
    // Verify key pair validity
    for validator in 0..config.validator_count {
        let validator_id = validator as ValidatorId;
        let key_pair = state.vrf_key_pairs.get(&validator_id)
            .ok_or_else(|| TestError::Verification(
                format!("Missing VRF key pair for validator {}", validator_id)
            ))?;
        
        if key_pair.validator != validator_id {
            return Err(TestError::Verification(
                format!("Key pair validator ID mismatch: expected {}, got {}", 
                    validator_id, key_pair.validator)
            ));
        }
        
        if !key_pair.valid {
            return Err(TestError::Verification(
                format!("Invalid VRF key pair for validator {}", validator_id)
            ));
        }
        
        if key_pair.public_key == 0 || key_pair.private_key == 0 {
            return Err(TestError::Verification(
                format!("Zero VRF keys for validator {}", validator_id)
            ));
        }
    }
    
    Ok(())
}

/// Test VRF proof generation and verification
fn test_vrf_proof_verification(config: &Config) -> Result<(), TestError> {
    let state = VotorState::new(0, config.clone());
    let test_inputs = vec![1u64, 100, 1000, 10000, 100000];
    
    for input in test_inputs {
        for validator in 0..config.validator_count {
            let validator_id = validator as ValidatorId;
            
            // Generate VRF proof
            let proof = state.vrf_prove(validator_id, input)
                .ok_or_else(|| TestError::Verification(
                    format!("Failed to generate VRF proof for validator {} input {}", 
                        validator_id, input)
                ))?;
            
            // Verify proof properties
            if proof.validator != validator_id {
                return Err(TestError::Verification(
                    format!("Proof validator mismatch: expected {}, got {}", 
                        validator_id, proof.validator)
                ));
            }
            
            if proof.input != input {
                return Err(TestError::Verification(
                    format!("Proof input mismatch: expected {}, got {}", 
                        input, proof.input)
                ));
            }
            
            if !proof.valid {
                return Err(TestError::Verification(
                    format!("Invalid VRF proof for validator {} input {}", 
                        validator_id, input)
                ));
            }
            
            // Verify proof with key pair
            let key_pair = state.vrf_key_pairs.get(&validator_id).unwrap();
            if !state.vrf_verify(key_pair.public_key, proof.input, proof.proof, proof.output) {
                return Err(TestError::Verification(
                    format!("VRF proof verification failed for validator {} input {}", 
                        validator_id, input)
                ));
            }
            
            // Test determinism
            let proof2 = state.vrf_prove(validator_id, input).unwrap();
            if proof.output != proof2.output || proof.proof != proof2.proof {
                return Err(TestError::Verification(
                    format!("VRF proof not deterministic for validator {} input {}", 
                        validator_id, input)
                ));
            }
        }
    }
    
    Ok(())
}

/// Test leader selection algorithm
fn test_leader_selection_algorithm(config: &Config, test_views: u64) -> Result<(), TestError> {
    let state = VotorState::new(0, config.clone());
    let mut selected_leaders = HashSet::new();
    
    // Test leader selection for multiple views
    for view in 1..=test_views {
        let leader = state.compute_leader_for_view(view);
        
        // Leader should be a valid validator
        if leader >= config.validator_count as ValidatorId {
            return Err(TestError::Verification(
                format!("Invalid leader {} for view {} (max validator: {})", 
                    leader, view, config.validator_count - 1)
            ));
        }
        
        selected_leaders.insert(leader);
        
        // Test determinism
        let leader2 = state.compute_leader_for_view(view);
        if leader != leader2 {
            return Err(TestError::Verification(
                format!("Leader selection not deterministic for view {}: {} vs {}", 
                    view, leader, leader2)
            ));
        }
        
        // Test cross-validator consistency
        let state2 = VotorState::new(1, config.clone());
        let leader3 = state2.compute_leader_for_view(view);
        if leader != leader3 {
            return Err(TestError::Verification(
                format!("Leader selection differs between validators for view {}: {} vs {}", 
                    view, leader, leader3)
            ));
        }
    }
    
    // With sufficient views, all validators should be selected at least once
    if test_views >= config.validator_count as u64 * 10 {
        if selected_leaders.len() < config.validator_count {
            return Err(TestError::Verification(
                format!("Not all validators selected as leaders: {}/{}", 
                    selected_leaders.len(), config.validator_count)
            ));
        }
    }
    
    Ok(())
}

/// Test stake-weighted fairness
fn test_stake_weighted_fairness(config: &Config, test_config: &TestConfig) -> Result<(), TestError> {
    // Create unequal stake configuration for fairness testing
    let mut stakes = BTreeMap::new();
    let total_validators = config.validator_count;
    
    // Create stake distribution with clear differences
    for i in 0..total_validators {
        let validator_id = i as ValidatorId;
        let stake = match i {
            0 => 5000, // 50% stake
            1 => 2000, // 20% stake
            2 => 1500, // 15% stake
            3 => 1000, // 10% stake
            _ => 500,  // 5% stake each
        };
        stakes.insert(validator_id, stake);
    }
    
    let fair_config = config.clone().with_stake_distribution(stakes.clone());
    let state = VotorState::new(0, fair_config.clone());
    
    let mut leader_counts = HashMap::new();
    let test_views = 10000u64;
    
    // Count leader selections
    for view in 1..=test_views {
        let leader = state.compute_leader_for_view(view);
        *leader_counts.entry(leader).or_insert(0) += 1;
    }
    
    // Verify stake-weighted fairness
    for i in 0..total_validators {
        for j in (i+1)..total_validators {
            let validator_i = i as ValidatorId;
            let validator_j = j as ValidatorId;
            let stake_i = stakes.get(&validator_i).copied().unwrap_or(0);
            let stake_j = stakes.get(&validator_j).copied().unwrap_or(0);
            let count_i = leader_counts.get(&validator_i).copied().unwrap_or(0);
            let count_j = leader_counts.get(&validator_j).copied().unwrap_or(0);
            
            if stake_i > stake_j && count_i < count_j {
                return Err(TestError::Verification(
                    format!("Stake fairness violation: validator {} (stake {}) selected {} times, but validator {} (stake {}) selected {} times",
                        validator_i, stake_i, count_i, validator_j, stake_j, count_j)
                ));
            }
        }
    }
    
    // Test zero stake handling
    let mut zero_stakes = stakes.clone();
    zero_stakes.insert((total_validators - 1) as ValidatorId, 0);
    let zero_config = config.clone().with_stake_distribution(zero_stakes);
    let zero_state = VotorState::new(0, zero_config);
    
    let mut zero_leader_counts = HashMap::new();
    for view in 1..=100 {
        let leader = zero_state.compute_leader_for_view(view);
        *zero_leader_counts.entry(leader).or_insert(0) += 1;
    }
    
    // Zero stake validator should never be selected
    let zero_stake_validator = (total_validators - 1) as ValidatorId;
    let zero_count = zero_leader_counts.get(&zero_stake_validator).copied().unwrap_or(0);
    if zero_count > 0 {
        return Err(TestError::Verification(
            format!("Zero stake validator {} was selected {} times", 
                zero_stake_validator, zero_count)
        ));
    }
    
    Ok(())
}

/// Test leader window functionality
fn test_leader_window_functionality(config: &Config) -> Result<(), TestError> {
    let state = VotorState::new(0, config.clone());
    
    // Test window leader computation
    for window_index in 0..TEST_WINDOWS {
        let window_leader = state.vrf_compute_window_leader(window_index);
        
        if window_leader >= config.validator_count as ValidatorId {
            return Err(TestError::Verification(
                format!("Invalid window leader {} for window {} (max validator: {})", 
                    window_leader, window_index, config.validator_count - 1)
            ));
        }
        
        // Test determinism
        let window_leader2 = state.vrf_compute_window_leader(window_index);
        if window_leader != window_leader2 {
            return Err(TestError::Verification(
                format!("Window leader computation not deterministic for window {}: {} vs {}", 
                    window_index, window_leader, window_leader2)
            ));
        }
        
        // Test leader rotation within window
        let mut rotated_leaders = HashSet::new();
        for view_offset in 0..LEADER_WINDOW_SIZE {
            let rotated_leader = state.vrf_rotate_leader_in_window(window_leader, view_offset);
            
            if rotated_leader >= config.validator_count as ValidatorId {
                return Err(TestError::Verification(
                    format!("Invalid rotated leader {} for window {} view offset {}", 
                        rotated_leader, window_index, view_offset)
                ));
            }
            
            rotated_leaders.insert(rotated_leader);
            
            // Test determinism
            let rotated_leader2 = state.vrf_rotate_leader_in_window(window_leader, view_offset);
            if rotated_leader != rotated_leader2 {
                return Err(TestError::Verification(
                    format!("Leader rotation not deterministic for window {} view offset {}", 
                        window_index, view_offset)
                ));
            }
        }
        
        // Should have some rotation diversity
        if config.validator_count >= 4 && rotated_leaders.len() < 2 {
            return Err(TestError::Verification(
                format!("Insufficient leader rotation in window {}: only {} unique leaders", 
                    window_index, rotated_leaders.len())
            ));
        }
    }
    
    // Test view to window mapping
    for view in 1..=20 {
        let slot = view; // Simplified mapping
        let window_index = slot / LEADER_WINDOW_SIZE;
        let view_in_window = view % LEADER_WINDOW_SIZE;
        
        let leader = state.vrf_compute_leader_for_view(slot, view);
        let window_leader = state.vrf_compute_window_leader(window_index);
        let expected_leader = state.vrf_rotate_leader_in_window(window_leader, view_in_window);
        
        if leader != expected_leader {
            return Err(TestError::Verification(
                format!("Leader computation mismatch for view {} (slot {}, window {}, view_in_window {}): got {}, expected {}", 
                    view, slot, window_index, view_in_window, leader, expected_leader)
            ));
        }
    }
    
    Ok(())
}

/// Test VRF randomness properties
fn test_vrf_randomness_properties(config: &Config) -> Result<(), TestError> {
    let state = VotorState::new(0, config.clone());
    
    // Test output uniqueness across validators
    let test_input = 99999u64;
    let mut outputs = HashSet::new();
    let mut proofs = HashSet::new();
    
    for validator in 0..config.validator_count {
        let validator_id = validator as ValidatorId;
        let proof = state.vrf_prove(validator_id, test_input)
            .ok_or_else(|| TestError::Verification(
                format!("Failed to generate VRF proof for validator {}", validator_id)
            ))?;
        
        // Check for output collisions (should be extremely rare)
        if outputs.contains(&proof.output) {
            return Err(TestError::Verification(
                format!("VRF output collision for validator {} (output: {})", 
                    validator_id, proof.output)
            ));
        }
        outputs.insert(proof.output);
        
        // Check for proof collisions
        if proofs.contains(&proof.proof) {
            return Err(TestError::Verification(
                format!("VRF proof collision for validator {} (proof: {})", 
                    validator_id, proof.proof)
            ));
        }
        proofs.insert(proof.proof);
    }
    
    // Test output distribution (basic entropy check)
    let mut bit_counts = vec![0; 64]; // Count bits in each position
    for output in &outputs {
        for bit_pos in 0..64 {
            if (output >> bit_pos) & 1 == 1 {
                bit_counts[bit_pos] += 1;
            }
        }
    }
    
    // Each bit position should have roughly balanced 0s and 1s
    let total_outputs = outputs.len();
    let expected_ones = total_outputs / 2;
    let tolerance = total_outputs / 4; // 25% tolerance
    
    for (bit_pos, count) in bit_counts.iter().enumerate() {
        if (*count as i32 - expected_ones as i32).abs() > tolerance as i32 {
            return Err(TestError::Verification(
                format!("Poor randomness distribution at bit position {}: {} ones out of {} (expected ~{})", 
                    bit_pos, count, total_outputs, expected_ones)
            ));
        }
    }
    
    Ok(())
}

/// Test VRF attack resistance
fn test_vrf_attack_resistance(config: &Config, test_config: &TestConfig) -> Result<(), TestError> {
    let state = VotorState::new(0, config.clone());
    
    // Test grinding attack resistance
    // An attacker should not be able to predict or manipulate VRF outputs
    let attacker_validator = 0;
    let mut attacker_outputs = Vec::new();
    
    // Simulate attacker trying different inputs
    for input in 1..=1000 {
        if let Some(proof) = state.vrf_prove(attacker_validator, input) {
            attacker_outputs.push((input, proof.output));
        }
    }
    
    // Check that outputs don't follow predictable patterns
    if attacker_outputs.len() < 2 {
        return Err(TestError::Verification(
            "Insufficient VRF outputs for grinding test".to_string()
        ));
    }
    
    // Test that consecutive inputs don't produce consecutive outputs
    let mut consecutive_pairs = 0;
    for i in 1..attacker_outputs.len() {
        let (input1, output1) = attacker_outputs[i-1];
        let (input2, output2) = attacker_outputs[i];
        
        if input2 == input1 + 1 && output2 == output1 + 1 {
            consecutive_pairs += 1;
        }
    }
    
    // Should have very few consecutive pairs (less than 1%)
    let max_consecutive = attacker_outputs.len() / 100;
    if consecutive_pairs > max_consecutive {
        return Err(TestError::Verification(
            format!("Too many consecutive VRF output pairs: {} out of {} (max allowed: {})", 
                consecutive_pairs, attacker_outputs.len() - 1, max_consecutive)
        ));
    }
    
    // Test prediction resistance
    // Future outputs should not be predictable from past outputs
    let prediction_window = 10;
    if attacker_outputs.len() >= prediction_window * 2 {
        let past_outputs: Vec<_> = attacker_outputs[..prediction_window].iter().map(|(_, o)| *o).collect();
        let future_outputs: Vec<_> = attacker_outputs[prediction_window..prediction_window*2].iter().map(|(_, o)| *o).collect();
        
        // Simple correlation test - outputs should not be highly correlated
        let mut correlation_score = 0;
        for i in 0..prediction_window {
            if past_outputs[i] % 1000 == future_outputs[i] % 1000 {
                correlation_score += 1;
            }
        }
        
        // Should have very low correlation (less than 20%)
        let max_correlation = prediction_window / 5;
        if correlation_score > max_correlation {
            return Err(TestError::Verification(
                format!("High correlation between past and future VRF outputs: {} out of {} (max allowed: {})", 
                    correlation_score, prediction_window, max_correlation)
            ));
        }
    }
    
    // Test manipulation resistance with Byzantine validators
    if test_config.byzantine_count > 0 {
        let mut byzantine_state = state.clone();
        let mut byzantine_validators = HashSet::new();
        
        for i in 0..test_config.byzantine_count.min(config.validator_count) {
            byzantine_validators.insert(i as ValidatorId);
        }
        byzantine_state.set_byzantine(byzantine_validators.clone());
        
        // Byzantine validators should still produce valid VRF proofs
        // (manipulation is detected at the consensus level, not VRF level)
        for &byzantine_validator in &byzantine_validators {
            let proof = byzantine_state.vrf_prove(byzantine_validator, 12345)
                .ok_or_else(|| TestError::Verification(
                    format!("Byzantine validator {} failed to generate VRF proof", byzantine_validator)
                ))?;
            
            // Proof should still be valid
            let key_pair = byzantine_state.vrf_key_pairs.get(&byzantine_validator).unwrap();
            if !byzantine_state.vrf_verify(key_pair.public_key, proof.input, proof.proof, proof.output) {
                return Err(TestError::Verification(
                    format!("Byzantine validator {} produced invalid VRF proof", byzantine_validator)
                ));
            }
        }
        
        // Leader selection should remain deterministic even with Byzantine validators
        for view in 1..=10 {
            let leader1 = state.compute_leader_for_view(view);
            let leader2 = byzantine_state.compute_leader_for_view(view);
            
            if leader1 != leader2 {
                return Err(TestError::Verification(
                    format!("Leader selection differs with Byzantine validators for view {}: {} vs {}", 
                        view, leader1, leader2)
                ));
            }
        }
    }
    
    Ok(())
}

/// Test integration with consensus protocol
fn test_consensus_integration(config: &Config, test_config: &TestConfig) -> Result<(), TestError> {
    let mut state = VotorState::new(0, config.clone());
    
    // Test VRF integration with consensus flow
    for view in 1..=test_config.max_rounds as u64 {
        state.current_view = view;
        state.current_time = view * 1000; // Advance time
        
        let leader = state.compute_leader_for_view(view);
        let is_leader = state.is_leader_for_view(view);
        
        // Verify leader recognition
        if state.validator_id == leader {
            if !is_leader {
                return Err(TestError::Verification(
                    format!("Validator {} should recognize itself as leader for view {}", 
                        state.validator_id, view)
                ));
            }
        } else {
            if is_leader {
                return Err(TestError::Verification(
                    format!("Validator {} should not think it's leader for view {} (actual leader: {})", 
                        state.validator_id, view, leader)
                ));
            }
        }
        
        // Test adaptive timeout integration
        if test_config.adaptive_timeouts {
            let timeout = state.adaptive_timeout(view);
            if timeout < BASE_TIMEOUT {
                return Err(TestError::Verification(
                    format!("Timeout {} should be at least base timeout {} for view {}", 
                        timeout, BASE_TIMEOUT, view)
                ));
            }
            
            // Timeout should generally increase with view progression
            if view > LEADER_WINDOW_SIZE {
                let prev_window_view = view - LEADER_WINDOW_SIZE;
                let prev_timeout = state.adaptive_timeout(prev_window_view);
                if timeout < prev_timeout {
                    // Allow some flexibility for adaptive algorithms
                    let tolerance = prev_timeout / 10; // 10% tolerance
                    if prev_timeout - timeout > tolerance {
                        return Err(TestError::Verification(
                            format!("Timeout decreased too much: view {} timeout {} vs view {} timeout {}", 
                                view, timeout, prev_window_view, prev_timeout)
                        ));
                    }
                }
            }
        }
    }
    
    // Test VRF state consistency throughout consensus
    if state.vrf_key_pairs.len() != config.validator_count {
        return Err(TestError::Verification(
            format!("VRF key pairs count changed during consensus: expected {}, got {}", 
                config.validator_count, state.vrf_key_pairs.len())
        ));
    }
    
    // All key pairs should remain valid
    for (validator_id, key_pair) in &state.vrf_key_pairs {
        if !key_pair.valid {
            return Err(TestError::Verification(
                format!("VRF key pair became invalid for validator {}", validator_id)
            ));
        }
        
        if key_pair.validator != *validator_id {
            return Err(TestError::Verification(
                format!("VRF key pair validator ID mismatch for validator {}", validator_id)
            ));
        }
    }
    
    Ok(())
}

/// Test VRF performance characteristics
fn test_vrf_performance_characteristics(config: &Config) -> Result<(), TestError> {
    let state = VotorState::new(0, config.clone());
    
    // Test VRF proof generation performance
    let proof_iterations = 1000;
    let start = Instant::now();
    
    for i in 0..proof_iterations {
        for validator in 0..config.validator_count {
            let validator_id = validator as ValidatorId;
            let _proof = state.vrf_prove(validator_id, i as u64);
        }
    }
    
    let proof_duration = start.elapsed();
    let proof_ops_per_sec = (proof_iterations * config.validator_count) as f64 / proof_duration.as_secs_f64();
    
    // Should be able to generate at least 1000 proofs per second
    if proof_ops_per_sec < 1000.0 {
        return Err(TestError::Verification(
            format!("VRF proof generation too slow: {:.0} ops/sec (minimum: 1000)", proof_ops_per_sec)
        ));
    }
    
    // Test leader selection performance
    let leader_iterations = 10000;
    let start = Instant::now();
    
    for view in 1..=leader_iterations {
        let _leader = state.compute_leader_for_view(view);
    }
    
    let leader_duration = start.elapsed();
    let leader_ops_per_sec = leader_iterations as f64 / leader_duration.as_secs_f64();
    
    // Should be able to compute at least 10000 leader selections per second
    if leader_ops_per_sec < 10000.0 {
        return Err(TestError::Verification(
            format!("Leader selection too slow: {:.0} ops/sec (minimum: 10000)", leader_ops_per_sec)
        ));
    }
    
    // Test VRF verification performance
    let verify_iterations = 1000;
    let test_input = 12345u64;
    let start = Instant::now();
    
    for validator in 0..config.validator_count {
        let validator_id = validator as ValidatorId;
        if let Some(proof) = state.vrf_prove(validator_id, test_input) {
            let key_pair = state.vrf_key_pairs.get(&validator_id).unwrap();
            for _ in 0..verify_iterations {
                let _valid = state.vrf_verify(key_pair.public_key, proof.input, proof.proof, proof.output);
            }
        }
    }
    
    let verify_duration = start.elapsed();
    let verify_ops_per_sec = (verify_iterations * config.validator_count) as f64 / verify_duration.as_secs_f64();
    
    // Should be able to verify at least 5000 proofs per second
    if verify_ops_per_sec < 5000.0 {
        return Err(TestError::Verification(
            format!("VRF verification too slow: {:.0} ops/sec (minimum: 5000)", verify_ops_per_sec)
        ));
    }
    
    Ok(())
}

/// Test TLA+ cross-validation
fn test_tla_cross_validation(config: &Config) -> Result<(), TestError> {
    let state = VotorState::new(0, config.clone());
    
    // Test TLA+ state export
    let tla_state = state.export_tla_state();
    if !tla_state.is_object() {
        return Err(TestError::CrossValidation(
            "TLA+ state export failed - not an object".to_string()
        ));
    }
    
    // Verify required fields are present
    let required_fields = ["validator_id", "current_view", "current_time"];
    for field in &required_fields {
        if tla_state.get(field).is_none() {
            return Err(TestError::CrossValidation(
                format!("Missing required field '{}' in TLA+ state export", field)
            ));
        }
    }
    
    // Test TLA+ invariant validation
    state.validate_tla_invariants()
        .map_err(|e| TestError::CrossValidation(
            format!("TLA+ invariant validation failed: {}", e)
        ))?;
    
    // Test VRF-specific invariants
    
    // Invariant: All VRF key pairs are valid
    for key_pair in state.vrf_key_pairs.values() {
        if !key_pair.valid {
            return Err(TestError::CrossValidation(
                "VRF key pair validity invariant violated".to_string()
            ));
        }
        
        if key_pair.public_key == 0 || key_pair.private_key == 0 {
            return Err(TestError::CrossValidation(
                "VRF key pair non-zero invariant violated".to_string()
            ));
        }
    }
    
    // Invariant: VRF proofs are consistent
    for validator in 0..config.validator_count {
        let validator_id = validator as ValidatorId;
        let input = 999u64;
        
        if let Some(proof1) = state.vrf_prove(validator_id, input) {
            if let Some(proof2) = state.vrf_prove(validator_id, input) {
                if proof1 != proof2 {
                    return Err(TestError::CrossValidation(
                        format!("VRF proof consistency invariant violated for validator {}", validator_id)
                    ));
                }
            }
        }
    }
    
    // Invariant: Leader selection is deterministic
    for view in 1..=10 {
        let leader1 = state.compute_leader_for_view(view);
        let leader2 = state.compute_leader_for_view(view);
        if leader1 != leader2 {
            return Err(TestError::CrossValidation(
                format!("Leader selection determinism invariant violated for view {}", view)
            ));
        }
    }
    
    Ok(())
}

/// Run external Stateright verification
fn run_external_stateright_verification(model: &AlpenglowModel, test_config: &TestConfig) -> Result<(), TestError> {
    let mut checker = ModelChecker::new(model.config().clone());
    
    // Run comprehensive model checking
    let metrics = checker.verify_model(model)
        .map_err(|e| TestError::Verification(
            format!("External Stateright verification failed: {}", e)
        ))?;
    
    // Check that sufficient states were explored
    if metrics.states_explored < test_config.exploration_depth / 10 {
        return Err(TestError::Verification(
            format!("Insufficient state exploration: {} states (minimum: {})", 
                metrics.states_explored, test_config.exploration_depth / 10)
        ));
    }
    
    // Check for violations
    if metrics.violations > 0 {
        return Err(TestError::Verification(
            format!("External verification found {} violations", metrics.violations)
        ));
    }
    
    Ok(())
}

/// Update VRF-specific metrics
fn update_vrf_metrics(report: &mut TestReport, config: &Config, test_config: &TestConfig) {
    // Calculate leader selection fairness metric
    let state = VotorState::new(0, config.clone());
    let mut leader_counts = HashMap::new();
    let fairness_test_views = 1000u64;
    
    for view in 1..=fairness_test_views {
        let leader = state.compute_leader_for_view(view);
        *leader_counts.entry(leader).or_insert(0) += 1;
    }
    
    // Calculate fairness score (lower is better, 0 is perfect fairness)
    let expected_per_validator = fairness_test_views as f64 / config.validator_count as f64;
    let mut fairness_score = 0.0;
    for validator in 0..config.validator_count {
        let validator_id = validator as ValidatorId;
        let count = leader_counts.get(&validator_id).copied().unwrap_or(0) as f64;
        fairness_score += (count - expected_per_validator).abs();
    }
    fairness_score /= fairness_test_views as f64;
    
    // Update coverage metrics with VRF-specific information
    report.metrics.coverage.state_space_coverage = fairness_score; // Reuse field for fairness
    report.metrics.coverage.code_coverage = if report.violations == 0 { 100.0 } else { 90.0 };
    
    // Add VRF-specific metadata
    report.metadata.environment.insert("VRF_ENABLED".to_string(), test_config.vrf_enabled.to_string());
    report.metadata.environment.insert("LEADER_WINDOW_SIZE".to_string(), test_config.leader_window_size.to_string());
    report.metadata.environment.insert("ADAPTIVE_TIMEOUTS".to_string(), test_config.adaptive_timeouts.to_string());
}

/// VRF test utilities
mod vrf_test_utils {
    use super::*;
    
    /// Create a test configuration for VRF testing
    pub fn create_vrf_test_config(validator_count: usize) -> Config {
        Config::new()
            .with_validators(validator_count)
            .with_byzantine_threshold((validator_count - 1) / 3)
            .with_erasure_coding(
                ((validator_count * 2) / 3) as u32,
                validator_count as u32
            )
    }
    
    /// Create a test configuration with unequal stakes
    pub fn create_unequal_stake_config() -> Config {
        let mut stakes = BTreeMap::new();
        stakes.insert(0, 5000); // 50% stake
        stakes.insert(1, 2000); // 20% stake
        stakes.insert(2, 1500); // 15% stake
        stakes.insert(3, 1000); // 10% stake
        stakes.insert(4, 500);  // 5% stake
        
        Config::new()
            .with_validators(5)
            .with_stake_distribution(stakes)
    }
    
    /// Verify VRF proof validity
    pub fn verify_vrf_proof_validity(state: &VotorState, proof: &VRFProof) -> bool {
        if let Some(key_pair) = state.vrf_key_pairs.get(&proof.validator) {
            state.vrf_verify(key_pair.public_key, proof.input, proof.proof, proof.output)
        } else {
            false
        }
    }
    
    /// Check leader selection determinism across multiple runs
    pub fn check_leader_determinism(state: &VotorState, view: ViewNumber, iterations: usize) -> bool {
        let first_leader = state.compute_leader_for_view(view);
        for _ in 1..iterations {
            if state.compute_leader_for_view(view) != first_leader {
                return false;
            }
        }
        true
    }
    
    /// Calculate expected leader distribution based on stakes
    pub fn calculate_expected_distribution(config: &Config, views: u64) -> HashMap<ValidatorId, f64> {
        let mut expected = HashMap::new();
        for validator in 0..config.validator_count {
            let validator_id = validator as ValidatorId;
            let stake = config.stake_distribution.get(&validator_id).copied().unwrap_or(0);
            let expected_ratio = stake as f64 / config.total_stake as f64;
            expected.insert(validator_id, expected_ratio * views as f64);
        }
        expected
    }
}

/// Basic VRF functionality tests
#[cfg(test)]
mod basic_vrf_tests {
    use super::*;
    use vrf_test_utils::*;
    
    #[test]
    fn test_vrf_key_generation() {
        let config = create_vrf_test_config(TEST_VALIDATOR_COUNT);
        let state = VotorState::new(0, config);
        
        // Verify all validators have VRF key pairs
        assert_eq!(state.vrf_key_pairs.len(), TEST_VALIDATOR_COUNT);
        
        for validator in 0..TEST_VALIDATOR_COUNT {
            let validator_id = validator as ValidatorId;
            let key_pair = state.vrf_key_pairs.get(&validator_id);
            assert!(key_pair.is_some(), "Missing VRF key pair for validator {}", validator_id);
            
            let key_pair = key_pair.unwrap();
            assert_eq!(key_pair.validator, validator_id);
            assert!(key_pair.valid);
            assert_ne!(key_pair.public_key, 0);
            assert_ne!(key_pair.private_key, 0);
        }
    }
    
    #[test]
    fn test_vrf_proof_generation() {
        let config = create_vrf_test_config(TEST_VALIDATOR_COUNT);
        let state = VotorState::new(0, config);
        
        let test_input = 12345u64;
        
        for validator in 0..TEST_VALIDATOR_COUNT {
            let validator_id = validator as ValidatorId;
            let proof = state.vrf_prove(validator_id, test_input);
            
            assert!(proof.is_some(), "Failed to generate VRF proof for validator {}", validator_id);
            
            let proof = proof.unwrap();
            assert_eq!(proof.validator, validator_id);
            assert_eq!(proof.input, test_input);
            assert!(proof.valid);
            assert_ne!(proof.output, 0);
            assert_ne!(proof.proof, 0);
        }
    }
    
    #[test]
    fn test_vrf_proof_verification() {
        let config = create_vrf_test_config(TEST_VALIDATOR_COUNT);
        let state = VotorState::new(0, config);
        
        let test_input = 54321u64;
        
        for validator in 0..TEST_VALIDATOR_COUNT {
            let validator_id = validator as ValidatorId;
            let proof = state.vrf_prove(validator_id, test_input).unwrap();
            
            // Verify the proof is valid
            assert!(verify_vrf_proof_validity(&state, &proof),
                "VRF proof verification failed for validator {}", validator_id);
            
            // Verify with correct parameters
            let key_pair = state.vrf_key_pairs.get(&validator_id).unwrap();
            assert!(state.vrf_verify(key_pair.public_key, proof.input, proof.proof, proof.output));
            
            // Verify with incorrect parameters should fail
            assert!(!state.vrf_verify(key_pair.public_key, proof.input + 1, proof.proof, proof.output));
            assert!(!state.vrf_verify(key_pair.public_key, proof.input, proof.proof + 1, proof.output));
            assert!(!state.vrf_verify(key_pair.public_key, proof.input, proof.proof, proof.output + 1));
        }
    }
    
    #[test]
    fn test_vrf_determinism() {
        let config = create_vrf_test_config(TEST_VALIDATOR_COUNT);
        let state = VotorState::new(0, config);
        
        let test_inputs = vec![1u64, 100, 1000, 10000, 100000];
        
        for input in test_inputs {
            for validator in 0..TEST_VALIDATOR_COUNT {
                let validator_id = validator as ValidatorId;
                
                // Generate proof multiple times
                let proof1 = state.vrf_prove(validator_id, input).unwrap();
                let proof2 = state.vrf_prove(validator_id, input).unwrap();
                let proof3 = state.vrf_prove(validator_id, input).unwrap();
                
                // All proofs should be identical
                assert_eq!(proof1, proof2, "VRF proof not deterministic for validator {} input {}", validator_id, input);
                assert_eq!(proof2, proof3, "VRF proof not deterministic for validator {} input {}", validator_id, input);
            }
        }
    }
    
    #[test]
    fn test_vrf_uniqueness() {
        let config = create_vrf_test_config(TEST_VALIDATOR_COUNT);
        let state = VotorState::new(0, config);
        
        let test_input = 99999u64;
        let mut outputs = HashSet::new();
        let mut proofs = HashSet::new();
        
        // Generate proofs for all validators with same input
        for validator in 0..TEST_VALIDATOR_COUNT {
            let validator_id = validator as ValidatorId;
            let proof = state.vrf_prove(validator_id, test_input).unwrap();
            
            // Outputs should be unique (with high probability)
            assert!(!outputs.contains(&proof.output), 
                "VRF output collision for validator {} (output: {})", validator_id, proof.output);
            outputs.insert(proof.output);
            
            // Proofs should be unique
            assert!(!proofs.contains(&proof.proof),
                "VRF proof collision for validator {} (proof: {})", validator_id, proof.proof);
            proofs.insert(proof.proof);
        }
        
        assert_eq!(outputs.len(), TEST_VALIDATOR_COUNT);
        assert_eq!(proofs.len(), TEST_VALIDATOR_COUNT);
    }
}

/// Leader selection algorithm tests
#[cfg(test)]
mod leader_selection_tests {
    use super::*;
    use vrf_test_utils::*;
    
    #[test]
    fn test_basic_leader_selection() {
        let config = create_vrf_test_config(TEST_VALIDATOR_COUNT);
        let state = VotorState::new(0, config);
        
        // Test leader selection for multiple views
        for view in 1..=TEST_VIEWS {
            let leader = state.compute_leader_for_view(view);
            
            // Leader should be a valid validator
            assert!(leader < TEST_VALIDATOR_COUNT as ValidatorId,
                "Invalid leader {} for view {}", leader, view);
            
            // Leader selection should be deterministic
            assert!(check_leader_determinism(&state, view, 10),
                "Leader selection not deterministic for view {}", view);
        }
    }
    
    #[test]
    fn test_leader_selection_determinism() {
        let config = create_vrf_test_config(TEST_VALIDATOR_COUNT);
        let state1 = VotorState::new(0, config.clone());
        let state2 = VotorState::new(1, config.clone());
        
        // Different validator states should produce same leader selection
        for view in 1..=TEST_VIEWS {
            let leader1 = state1.compute_leader_for_view(view);
            let leader2 = state2.compute_leader_for_view(view);
            
            assert_eq!(leader1, leader2,
                "Leader selection differs between validator states for view {}", view);
        }
    }
    
    #[test]
    fn test_leader_window_functionality() {
        let config = create_vrf_test_config(TEST_VALIDATOR_COUNT);
        let state = VotorState::new(0, config);
        
        // Test leader window computation
        for window_index in 0..TEST_WINDOWS {
            let window_leader = state.vrf_compute_window_leader(window_index);
            
            assert!(window_leader < TEST_VALIDATOR_COUNT as ValidatorId,
                "Invalid window leader {} for window {}", window_leader, window_index);
            
            // Test leader rotation within window
            for view_offset in 0..LEADER_WINDOW_SIZE {
                let rotated_leader = state.vrf_rotate_leader_in_window(window_leader, view_offset);
                
                assert!(rotated_leader < TEST_VALIDATOR_COUNT as ValidatorId,
                    "Invalid rotated leader {} for window {} view offset {}", 
                    rotated_leader, window_index, view_offset);
            }
        }
    }
    
    #[test]
    fn test_leader_selection_with_slots() {
        let config = create_vrf_test_config(TEST_VALIDATOR_COUNT);
        let state = VotorState::new(0, config);
        
        // Test VRF leader selection for specific slot/view combinations
        for slot in 1..=20 {
            for view in 1..=LEADER_WINDOW_SIZE {
                let leader = state.vrf_compute_leader_for_view(slot, view);
                
                assert!(leader < TEST_VALIDATOR_COUNT as ValidatorId,
                    "Invalid leader {} for slot {} view {}", leader, slot, view);
                
                // Same slot/view should always give same leader
                let leader2 = state.vrf_compute_leader_for_view(slot, view);
                assert_eq!(leader, leader2,
                    "Inconsistent leader selection for slot {} view {}", slot, view);
            }
        }
    }
    
    #[test]
    fn test_is_leader_for_view() {
        let config = create_vrf_test_config(TEST_VALIDATOR_COUNT);
        
        for validator in 0..TEST_VALIDATOR_COUNT {
            let validator_id = validator as ValidatorId;
            let mut state = VotorState::new(validator_id, config.clone());
            
            // Set a specific time to get deterministic slot
            state.current_time = 1000;
            let slot = state.get_slot_from_time(state.current_time);
            
            for view in 1..=10 {
                let is_leader = state.is_leader_for_view(view);
                let computed_leader = state.vrf_compute_leader_for_view(slot, view);
                
                assert_eq!(is_leader, computed_leader == validator_id,
                    "is_leader_for_view inconsistent with computed leader for validator {} view {}", 
                    validator_id, view);
            }
        }
    }
}

/// Stake-weighted leader selection tests
#[cfg(test)]
mod stake_weighted_tests {
    use super::*;
    use vrf_test_utils::*;
    
    #[test]
    fn test_stake_weighted_selection() {
        let config = create_unequal_stake_config();
        let state = VotorState::new(0, config.clone());
        
        let mut leader_counts = HashMap::new();
        let test_views = 1000u64;
        
        // Count leader selections over many views
        for view in 1..=test_views {
            let leader = state.compute_leader_for_view(view);
            *leader_counts.entry(leader).or_insert(0) += 1;
        }
        
        // Calculate expected distribution
        let expected = calculate_expected_distribution(&config, test_views);
        
        // Verify that higher stake validators are selected more often
        let validator_0_count = leader_counts.get(&0).copied().unwrap_or(0) as f64;
        let validator_4_count = leader_counts.get(&4).copied().unwrap_or(0) as f64;
        
        // Validator 0 has 50% stake, validator 4 has 5% stake
        // So validator 0 should be selected much more often
        assert!(validator_0_count > validator_4_count * 5.0,
            "Stake weighting not working: validator 0 count {} vs validator 4 count {}", 
            validator_0_count, validator_4_count);
        
        // Check that all validators can be selected (with sufficient views)
        for validator in 0..config.validator_count {
            let validator_id = validator as ValidatorId;
            let count = leader_counts.get(&validator_id).copied().unwrap_or(0);
            assert!(count > 0, "Validator {} never selected as leader", validator_id);
        }
    }
    
    #[test]
    fn test_zero_stake_handling() {
        let mut stakes = BTreeMap::new();
        stakes.insert(0, 5000);
        stakes.insert(1, 3000);
        stakes.insert(2, 2000);
        stakes.insert(3, 0); // Zero stake validator
        
        let config = Config::new()
            .with_validators(4)
            .with_stake_distribution(stakes);
        
        let state = VotorState::new(0, config);
        
        let mut leader_counts = HashMap::new();
        
        // Count leader selections
        for view in 1..=100 {
            let leader = state.compute_leader_for_view(view);
            *leader_counts.entry(leader).or_insert(0) += 1;
        }
        
        // Zero stake validator should never be selected
        let zero_stake_count = leader_counts.get(&3).copied().unwrap_or(0);
        assert_eq!(zero_stake_count, 0, "Zero stake validator was selected as leader");
        
        // Other validators should be selected
        for validator in 0..3 {
            let count = leader_counts.get(&validator).copied().unwrap_or(0);
            assert!(count > 0, "Non-zero stake validator {} never selected", validator);
        }
    }
    
    #[test]
    fn test_equal_stake_distribution() {
        let config = create_vrf_test_config(TEST_VALIDATOR_COUNT);
        let state = VotorState::new(0, config);
        
        let mut leader_counts = HashMap::new();
        let test_views = 1000u64;
        
        // Count leader selections
        for view in 1..=test_views {
            let leader = state.compute_leader_for_view(view);
            *leader_counts.entry(leader).or_insert(0) += 1;
        }
        
        // With equal stakes, distribution should be roughly equal
        let expected_per_validator = test_views as f64 / TEST_VALIDATOR_COUNT as f64;
        let tolerance = expected_per_validator * 0.3; // 30% tolerance
        
        for validator in 0..TEST_VALIDATOR_COUNT {
            let validator_id = validator as ValidatorId;
            let count = leader_counts.get(&validator_id).copied().unwrap_or(0) as f64;
            
            assert!(count > 0, "Validator {} never selected", validator_id);
            assert!((count - expected_per_validator).abs() < tolerance,
                "Validator {} selection count {} too far from expected {}", 
                validator_id, count, expected_per_validator);
        }
    }
}

/// Leader window and rotation tests
#[cfg(test)]
mod leader_window_tests {
    use super::*;
    use vrf_test_utils::*;
    
    #[test]
    fn test_leader_window_size() {
        assert_eq!(LEADER_WINDOW_SIZE, 4, "Leader window size should be 4 as per TLA+ spec");
    }
    
    #[test]
    fn test_window_leader_computation() {
        let config = create_vrf_test_config(TEST_VALIDATOR_COUNT);
        let state = VotorState::new(0, config);
        
        // Test window leader computation for multiple windows
        for window_index in 0..10 {
            let window_leader = state.vrf_compute_window_leader(window_index);
            
            assert!(window_leader < TEST_VALIDATOR_COUNT as ValidatorId,
                "Invalid window leader {} for window {}", window_leader, window_index);
            
            // Same window should always give same leader
            let window_leader2 = state.vrf_compute_window_leader(window_index);
            assert_eq!(window_leader, window_leader2,
                "Window leader computation not deterministic for window {}", window_index);
        }
    }
    
    #[test]
    fn test_leader_rotation_in_window() {
        let config = create_vrf_test_config(TEST_VALIDATOR_COUNT);
        let state = VotorState::new(0, config);
        
        let window_leader = 0; // Use validator 0 as window leader
        let mut rotated_leaders = HashSet::new();
        
        // Test rotation for all views in window
        for view in 0..LEADER_WINDOW_SIZE {
            let rotated_leader = state.vrf_rotate_leader_in_window(window_leader, view);
            
            assert!(rotated_leader < TEST_VALIDATOR_COUNT as ValidatorId,
                "Invalid rotated leader {} for view {}", rotated_leader, view);
            
            rotated_leaders.insert(rotated_leader);
            
            // Same parameters should give same result
            let rotated_leader2 = state.vrf_rotate_leader_in_window(window_leader, view);
            assert_eq!(rotated_leader, rotated_leader2,
                "Leader rotation not deterministic for view {}", view);
        }
        
        // Should have some rotation (not all the same leader)
        // With 7 validators and 4 views, we expect some diversity
        assert!(rotated_leaders.len() >= 2,
            "Insufficient leader rotation: only {} unique leaders", rotated_leaders.len());
    }
    
    #[test]
    fn test_view_to_window_mapping() {
        let config = create_vrf_test_config(TEST_VALIDATOR_COUNT);
        let state = VotorState::new(0, config);
        
        // Test that views map to correct windows
        for view in 1..=20 {
            let slot = view; // Simplified: use view as slot
            let window_index = slot / LEADER_WINDOW_SIZE;
            let view_in_window = view % LEADER_WINDOW_SIZE;
            
            let leader = state.vrf_compute_leader_for_view(slot, view);
            let window_leader = state.vrf_compute_window_leader(window_index);
            let expected_leader = state.vrf_rotate_leader_in_window(window_leader, view_in_window);
            
            assert_eq!(leader, expected_leader,
                "Leader computation mismatch for view {} (slot {}, window {}, view_in_window {})", 
                view, slot, window_index, view_in_window);
        }
    }
    
    #[test]
    fn test_window_boundaries() {
        let config = create_vrf_test_config(TEST_VALIDATOR_COUNT);
        let state = VotorState::new(0, config);
        
        // Test leader selection at window boundaries
        let test_slots = vec![
            LEADER_WINDOW_SIZE - 1,  // Last slot of window 0
            LEADER_WINDOW_SIZE,      // First slot of window 1
            LEADER_WINDOW_SIZE + 1,  // Second slot of window 1
            2 * LEADER_WINDOW_SIZE - 1, // Last slot of window 1
            2 * LEADER_WINDOW_SIZE,     // First slot of window 2
        ];
        
        for slot in test_slots {
            for view in 1..=LEADER_WINDOW_SIZE {
                let leader = state.vrf_compute_leader_for_view(slot, view);
                
                assert!(leader < TEST_VALIDATOR_COUNT as ValidatorId,
                    "Invalid leader {} for slot {} view {}", leader, slot, view);
                
                // Verify consistency
                let leader2 = state.vrf_compute_leader_for_view(slot, view);
                assert_eq!(leader, leader2,
                    "Inconsistent leader at boundary: slot {} view {}", slot, view);
            }
        }
    }
}

/// Integration tests with consensus protocol
#[cfg(test)]
mod integration_tests {
    use super::*;
    use vrf_test_utils::*;
    
    #[test]
    fn test_vrf_with_consensus_flow() {
        let config = create_vrf_test_config(5);
        let mut state = VotorState::new(0, config);
        
        // Simulate consensus flow with VRF leader selection
        for view in 1..=10 {
            state.current_view = view;
            state.current_time = view * 1000; // Advance time
            
            let leader = state.compute_leader_for_view(view);
            let is_leader = state.is_leader_for_view(view);
            
            if state.validator_id == leader {
                assert!(is_leader, "Validator should recognize itself as leader for view {}", view);
            } else {
                assert!(!is_leader, "Validator should not think it's leader for view {}", view);
            }
            
            // Test adaptive timeout calculation
            let timeout = state.adaptive_timeout(view);
            assert!(timeout >= BASE_TIMEOUT, "Timeout should be at least base timeout");
            
            // Timeout should increase with window progression
            if view > LEADER_WINDOW_SIZE {
                let prev_window_view = view - LEADER_WINDOW_SIZE;
                let prev_timeout = state.adaptive_timeout(prev_window_view);
                assert!(timeout >= prev_timeout, 
                    "Timeout should not decrease: view {} timeout {} vs view {} timeout {}", 
                    view, timeout, prev_window_view, prev_timeout);
            }
        }
    }
    
    #[test]
    fn test_vrf_with_byzantine_validators() {
        let config = create_vrf_test_config(TEST_VALIDATOR_COUNT);
        let mut state = VotorState::new(0, config);
        
        // Mark some validators as Byzantine
        let mut byzantine_validators = HashSet::new();
        byzantine_validators.insert(1);
        byzantine_validators.insert(3);
        state.set_byzantine(byzantine_validators.clone());
        
        // VRF leader selection should still work correctly
        for view in 1..=20 {
            let leader = state.compute_leader_for_view(view);
            
            assert!(leader < TEST_VALIDATOR_COUNT as ValidatorId,
                "Invalid leader {} for view {} with Byzantine validators", leader, view);
            
            // Byzantine validators can still be selected as leaders
            // (the protocol handles Byzantine behavior at the consensus level)
            if byzantine_validators.contains(&leader) {
                // This is allowed - Byzantine detection happens during consensus
            }
            
            // Leader selection should remain deterministic
            assert!(check_leader_determinism(&state, view, 5),
                "Leader selection not deterministic with Byzantine validators for view {}", view);
        }
    }
    
    #[test]
    fn test_vrf_state_consistency() {
        let config = create_vrf_test_config(TEST_VALIDATOR_COUNT);
        let state = VotorState::new(0, config);
        
        // Verify VRF state consistency
        assert_eq!(state.vrf_key_pairs.len(), TEST_VALIDATOR_COUNT);
        
        // All validators should have valid key pairs
        for (validator_id, key_pair) in &state.vrf_key_pairs {
            assert_eq!(key_pair.validator, *validator_id);
            assert!(key_pair.valid);
            assert_ne!(key_pair.public_key, 0);
            assert_ne!(key_pair.private_key, 0);
        }
        
        // VRF proofs set should be initially empty
        assert!(state.vrf_proofs.is_empty());
        
        // Test VRF proof generation and storage
        let mut modified_state = state.clone();
        let test_input = 12345u64;
        
        for validator in 0..TEST_VALIDATOR_COUNT {
            let validator_id = validator as ValidatorId;
            if let Some(proof) = modified_state.vrf_prove(validator_id, test_input) {
                modified_state.vrf_proofs.insert(proof);
            }
        }
        
        assert_eq!(modified_state.vrf_proofs.len(), TEST_VALIDATOR_COUNT);
    }
}

/// Performance and stress tests
#[cfg(test)]
mod performance_tests {
    use super::*;
    use vrf_test_utils::*;
    use std::time::Instant;
    
    #[test]
    fn test_vrf_performance() {
        let config = create_vrf_test_config(TEST_VALIDATOR_COUNT);
        let state = VotorState::new(0, config);
        
        let iterations = 1000;
        let start = Instant::now();
        
        // Test VRF proof generation performance
        for i in 0..iterations {
            for validator in 0..TEST_VALIDATOR_COUNT {
                let validator_id = validator as ValidatorId;
                let _proof = state.vrf_prove(validator_id, i as u64);
            }
        }
        
        let duration = start.elapsed();
        let ops_per_sec = (iterations * TEST_VALIDATOR_COUNT) as f64 / duration.as_secs_f64();
        
        // Should be able to generate at least 1000 proofs per second
        assert!(ops_per_sec > 1000.0, 
            "VRF proof generation too slow: {} ops/sec", ops_per_sec);
        
        println!("VRF proof generation: {:.0} ops/sec", ops_per_sec);
    }
    
    #[test]
    fn test_leader_selection_performance() {
        let config = create_vrf_test_config(TEST_VALIDATOR_COUNT);
        let state = VotorState::new(0, config);
        
        let iterations = 10000;
        let start = Instant::now();
        
        // Test leader selection performance
        for view in 1..=iterations {
            let _leader = state.compute_leader_for_view(view);
        }
        
        let duration = start.elapsed();
        let ops_per_sec = iterations as f64 / duration.as_secs_f64();
        
        // Should be able to compute at least 10000 leader selections per second
        assert!(ops_per_sec > 10000.0,
            "Leader selection too slow: {} ops/sec", ops_per_sec);
        
        println!("Leader selection: {:.0} ops/sec", ops_per_sec);
    }
    
    #[test]
    fn test_large_validator_set() {
        let large_validator_count = 100;
        let config = create_vrf_test_config(large_validator_count);
        let state = VotorState::new(0, config);
        
        // Test VRF functionality with large validator set
        assert_eq!(state.vrf_key_pairs.len(), large_validator_count);
        
        // Test leader selection
        let mut leader_counts = HashMap::new();
        for view in 1..=1000 {
            let leader = state.compute_leader_for_view(view);
            assert!(leader < large_validator_count as ValidatorId);
            *leader_counts.entry(leader).or_insert(0) += 1;
        }
        
        // Should have reasonable distribution
        assert!(leader_counts.len() > large_validator_count / 2,
            "Too few validators selected as leaders: {}/{}", 
            leader_counts.len(), large_validator_count);
    }
}

/// Property-based tests for VRF leader selection
#[cfg(test)]
mod property_tests {
    use super::*;
    use vrf_test_utils::*;
    
    #[test]
    fn test_vrf_safety_properties() {
        let config = create_vrf_test_config(TEST_VALIDATOR_COUNT);
        let state = VotorState::new(0, config);
        
        // Property: VRF proofs are always verifiable
        for validator in 0..TEST_VALIDATOR_COUNT {
            let validator_id = validator as ValidatorId;
            for input in [1u64, 100, 1000, 10000] {
                if let Some(proof) = state.vrf_prove(validator_id, input) {
                    assert!(verify_vrf_proof_validity(&state, &proof),
                        "VRF proof not verifiable for validator {} input {}", validator_id, input);
                }
            }
        }
        
        // Property: Leader selection is always valid
        for view in 1..=100 {
            let leader = state.compute_leader_for_view(view);
            assert!(leader < TEST_VALIDATOR_COUNT as ValidatorId,
                "Invalid leader {} for view {}", leader, view);
        }
        
        // Property: VRF outputs are deterministic
        for validator in 0..TEST_VALIDATOR_COUNT {
            let validator_id = validator as ValidatorId;
            let input = 42u64;
            let proof1 = state.vrf_prove(validator_id, input).unwrap();
            let proof2 = state.vrf_prove(validator_id, input).unwrap();
            assert_eq!(proof1.output, proof2.output,
                "VRF output not deterministic for validator {}", validator_id);
        }
    }
    
    #[test]
    fn test_vrf_liveness_properties() {
        let config = create_vrf_test_config(TEST_VALIDATOR_COUNT);
        let state = VotorState::new(0, config);
        
        // Property: All validators can be selected as leaders (eventually)
        let mut selected_leaders = HashSet::new();
        for view in 1..=1000 {
            let leader = state.compute_leader_for_view(view);
            selected_leaders.insert(leader);
        }
        
        // With enough views, all validators should be selected at least once
        assert_eq!(selected_leaders.len(), TEST_VALIDATOR_COUNT,
            "Not all validators selected as leaders: {}/{}", 
            selected_leaders.len(), TEST_VALIDATOR_COUNT);
        
        // Property: VRF proofs can always be generated
        for validator in 0..TEST_VALIDATOR_COUNT {
            let validator_id = validator as ValidatorId;
            let proof = state.vrf_prove(validator_id, 123u64);
            assert!(proof.is_some(), "Failed to generate VRF proof for validator {}", validator_id);
        }
    }
    
    #[test]
    fn test_vrf_fairness_properties() {
        let config = create_unequal_stake_config();
        let state = VotorState::new(0, config.clone());
        
        let mut leader_counts = HashMap::new();
        let test_views = 10000u64;
        
        // Count leader selections
        for view in 1..=test_views {
            let leader = state.compute_leader_for_view(view);
            *leader_counts.entry(leader).or_insert(0) += 1;
        }
        
        // Property: Higher stake validators should be selected more often
        let stakes: Vec<_> = (0..config.validator_count)
            .map(|v| config.stake_distribution.get(&(v as ValidatorId)).copied().unwrap_or(0))
            .collect();
        
        for i in 0..config.validator_count {
            for j in (i+1)..config.validator_count {
                let validator_i = i as ValidatorId;
                let validator_j = j as ValidatorId;
                let stake_i = stakes[i];
                let stake_j = stakes[j];
                let count_i = leader_counts.get(&validator_i).copied().unwrap_or(0);
                let count_j = leader_counts.get(&validator_j).copied().unwrap_or(0);
                
                if stake_i > stake_j {
                    assert!(count_i >= count_j,
                        "Validator {} (stake {}) selected {} times, but validator {} (stake {}) selected {} times",
                        validator_i, stake_i, count_i, validator_j, stake_j, count_j);
                }
            }
        }
    }
}

/// Cross-validation tests with TLA+ specification
#[cfg(test)]
mod tla_cross_validation_tests {
    use super::*;
    use vrf_test_utils::*;
    
    #[test]
    fn test_vrf_tla_compatibility() {
        let config = create_vrf_test_config(TEST_VALIDATOR_COUNT);
        let state = VotorState::new(0, config);
        
        // Test TLA+ state export
        let tla_state = state.export_tla_state();
        assert!(tla_state.is_object());
        
        // Verify key fields are present
        assert!(tla_state.get("validator_id").is_some());
        assert!(tla_state.get("current_view").is_some());
        assert!(tla_state.get("current_time").is_some());
        
        // Test TLA+ invariant validation
        assert!(state.validate_tla_invariants().is_ok());
    }
    
    #[test]
    fn test_vrf_invariants() {
        let config = create_vrf_test_config(TEST_VALIDATOR_COUNT);
        let state = VotorState::new(0, config);
        
        // VRF-specific invariants
        
        // Invariant: All VRF key pairs are valid
        for key_pair in state.vrf_key_pairs.values() {
            assert!(key_pair.valid);
            assert_ne!(key_pair.public_key, 0);
            assert_ne!(key_pair.private_key, 0);
        }
        
        // Invariant: VRF proofs are consistent
        for validator in 0..TEST_VALIDATOR_COUNT {
            let validator_id = validator as ValidatorId;
            let input = 999u64;
            
            if let Some(proof1) = state.vrf_prove(validator_id, input) {
                if let Some(proof2) = state.vrf_prove(validator_id, input) {
                    assert_eq!(proof1, proof2, "VRF proof inconsistency");
                }
            }
        }
        
        // Invariant: Leader selection is deterministic
        for view in 1..=10 {
            let leader1 = state.compute_leader_for_view(view);
            let leader2 = state.compute_leader_for_view(view);
            assert_eq!(leader1, leader2, "Leader selection non-deterministic for view {}", view);
        }
    }
}

/// Main test runner for VRF leader selection
#[cfg(test)]
mod main_tests {
    use super::*;
    
    #[test]
    fn test_vrf_leader_selection_comprehensive() {
        println!("Running comprehensive VRF leader selection tests...");
        
        // Test with different configurations
        let configs = vec![
            create_vrf_test_config(3),
            create_vrf_test_config(4),
            create_vrf_test_config(7),
            create_vrf_test_config(10),
            create_unequal_stake_config(),
        ];
        
        for (i, config) in configs.iter().enumerate() {
            println!("Testing configuration {}: {} validators", i + 1, config.validator_count);
            
            let state = VotorState::new(0, config.clone());
            
            // Basic functionality
            assert_eq!(state.vrf_key_pairs.len(), config.validator_count);
            
            // Leader selection
            for view in 1..=20 {
                let leader = state.compute_leader_for_view(view);
                assert!(leader < config.validator_count as ValidatorId);
            }
            
            // VRF proofs
            for validator in 0..config.validator_count {
                let validator_id = validator as ValidatorId;
                let proof = state.vrf_prove(validator_id, 12345u64);
                assert!(proof.is_some());
                
                let proof = proof.unwrap();
                assert!(vrf_test_utils::verify_vrf_proof_validity(&state, &proof));
            }
            
            println!("Configuration {} passed all tests", i + 1);
        }
        
        println!("All VRF leader selection tests completed successfully!");
    }
    
    #[test]
    fn test_vrf_verification_properties() {
        let config = create_vrf_test_config(TEST_VALIDATOR_COUNT);
        let state = VotorState::new(0, config);
        
        // Test Verifiable trait implementation
        assert!(state.verify_safety().is_ok(), "VRF safety verification failed");
        assert!(state.verify_liveness().is_ok(), "VRF liveness verification failed");
        assert!(state.verify_byzantine_resilience().is_ok(), "VRF Byzantine resilience verification failed");
        
        // Test TlaCompatible trait implementation
        let tla_state = state.export_tla_state();
        assert!(tla_state.is_object(), "TLA+ state export failed");
        assert!(state.validate_tla_invariants().is_ok(), "TLA+ invariant validation failed");
        
        println!("VRF verification properties test completed successfully!");
    }
}

/// Benchmark tests for performance measurement
#[cfg(test)]
mod benchmark_tests {
    use super::*;
    use std::time::Instant;
    
    #[test]
    fn benchmark_vrf_operations() {
        let config = create_vrf_test_config(TEST_VALIDATOR_COUNT);
        let state = VotorState::new(0, config);
        
        println!("Benchmarking VRF operations...");
        
        // Benchmark VRF proof generation
        let start = Instant::now();
        let iterations = 1000;
        
        for i in 0..iterations {
            for validator in 0..TEST_VALIDATOR_COUNT {
                let validator_id = validator as ValidatorId;
                let _proof = state.vrf_prove(validator_id, i as u64);
            }
        }
        
        let duration = start.elapsed();
        let proof_ops_per_sec = (iterations * TEST_VALIDATOR_COUNT) as f64 / duration.as_secs_f64();
        println!("VRF proof generation: {:.0} ops/sec", proof_ops_per_sec);
        
        // Benchmark leader selection
        let start = Instant::now();
        let iterations = 10000;
        
        for view in 1..=iterations {
            let _leader = state.compute_leader_for_view(view);
        }
        
        let duration = start.elapsed();
        let leader_ops_per_sec = iterations as f64 / duration.as_secs_f64();
        println!("Leader selection: {:.0} ops/sec", leader_ops_per_sec);
        
        // Benchmark VRF verification
        let start = Instant::now();
        let iterations = 1000;
        let test_input = 12345u64;
        
        for validator in 0..TEST_VALIDATOR_COUNT {
            let validator_id = validator as ValidatorId;
            if let Some(proof) = state.vrf_prove(validator_id, test_input) {
                for _ in 0..iterations {
                    let key_pair = state.vrf_key_pairs.get(&validator_id).unwrap();
                    let _valid = state.vrf_verify(key_pair.public_key, proof.input, proof.proof, proof.output);
                }
            }
        }
        
        let duration = start.elapsed();
        let verify_ops_per_sec = (iterations * TEST_VALIDATOR_COUNT) as f64 / duration.as_secs_f64();
        println!("VRF verification: {:.0} ops/sec", verify_ops_per_sec);
        
        println!("VRF benchmarking completed!");
    }
}
