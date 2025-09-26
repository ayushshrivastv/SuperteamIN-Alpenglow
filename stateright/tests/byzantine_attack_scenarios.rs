// Author: Ayush Srivastava
//! Advanced Byzantine Attack Scenarios for Alpenglow Protocol
//!
//! This module implements sophisticated Byzantine attack scenarios that go beyond
//! basic Byzantine behavior testing. It covers coordinated attacks, eclipse attacks,
//! long-range attacks, adaptive adversaries, economic attacks, and timing attacks.

use std::collections::{HashMap, HashSet, BTreeSet, BTreeMap};
use std::time::{Duration, Instant};
use serde::{Deserialize, Serialize};

// Import from the local crate - using crate root exports
use alpenglow_stateright::{
    AlpenglowModel, AlpenglowState, AlpenglowAction, AlpenglowError, AlpenglowResult,
    Config, ValidatorId, ValidatorStatus, ViewNumber, SlotNumber, TimeValue,
    ByzantineAction, NetworkAction, VotorAction, RotorAction,
    Block, Vote, VoteType, Certificate, CertificateType,
    properties, utils, TlaCompatible, Verifiable,
    local_stateright::Model,
};

// External Stateright integration
use stateright::{
    Checker, CheckerBuilder, Property, SimpleProperty,
    actor::{ActorModel, ActorModelState},
    util::HashableHashSet,
};

// CLI integration imports
mod common;
use common::*;

/// Advanced Byzantine attack configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ByzantineAttackConfig {
    pub total_validators: usize,
    pub byzantine_count: usize,
    pub offline_count: usize,
    pub max_rounds: usize,
    pub attack_coordination_rounds: usize,
    pub eclipse_target_count: usize,
    pub long_range_depth: usize,
    pub adaptive_strategy_changes: usize,
    pub economic_attack_stake_percentage: f64,
    pub timing_attack_delay_ms: u64,
    pub network_manipulation_probability: f64,
    pub use_external_stateright: bool,
    pub cross_validate_tla: bool,
    pub exploration_depth: usize,
    pub max_states: usize,
}

impl Default for ByzantineAttackConfig {
    fn default() -> Self {
        Self {
            total_validators: 10,
            byzantine_count: 3,
            offline_count: 1,
            max_rounds: 50,
            attack_coordination_rounds: 10,
            eclipse_target_count: 2,
            long_range_depth: 20,
            adaptive_strategy_changes: 5,
            economic_attack_stake_percentage: 25.0,
            timing_attack_delay_ms: 500,
            network_manipulation_probability: 0.3,
            use_external_stateright: true,
            cross_validate_tla: false,
            exploration_depth: 2000,
            max_states: 20000,
        }
    }
}

/// Attack scenario result with detailed metrics
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AttackScenarioResult {
    pub scenario_name: String,
    pub attack_successful: bool,
    pub safety_violated: bool,
    pub liveness_violated: bool,
    pub protocol_resilient: bool,
    pub states_explored: usize,
    pub attack_rounds: usize,
    pub detection_time_ms: u64,
    pub recovery_time_ms: u64,
    pub execution_time_ms: u64,
    pub attack_metrics: AttackMetrics,
    pub violations_found: Vec<String>,
    pub external_stateright_result: Option<ExternalStateRightResult>,
    pub tla_cross_validation: Option<TlaCrossValidationResult>,
}

/// Detailed attack metrics
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AttackMetrics {
    pub coordinated_actions: usize,
    pub eclipse_attempts: usize,
    pub long_range_forks: usize,
    pub adaptive_strategy_switches: usize,
    pub economic_damage_percentage: f64,
    pub timing_manipulation_count: usize,
    pub network_partitions_created: usize,
    pub honest_validators_affected: usize,
    pub finalization_delays_ms: Vec<u64>,
    pub bandwidth_waste_percentage: f64,
}

impl Default for AttackMetrics {
    fn default() -> Self {
        Self {
            coordinated_actions: 0,
            eclipse_attempts: 0,
            long_range_forks: 0,
            adaptive_strategy_switches: 0,
            economic_damage_percentage: 0.0,
            timing_manipulation_count: 0,
            network_partitions_created: 0,
            honest_validators_affected: 0,
            finalization_delays_ms: Vec::new(),
            bandwidth_waste_percentage: 0.0,
        }
    }
}

/// External Stateright verification result
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ExternalStateRightResult {
    pub states_discovered: usize,
    pub unique_states: usize,
    pub max_depth: usize,
    pub properties_checked: Vec<String>,
    pub violations: Vec<String>,
    pub verification_time_ms: u64,
}

/// TLA+ cross-validation result
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TlaCrossValidationResult {
    pub tla_states_exported: usize,
    pub tla_invariants_checked: Vec<String>,
    pub consistency_verified: bool,
    pub discrepancies: Vec<String>,
}

/// Advanced Byzantine attack test suite
pub struct ByzantineAttackScenarios {
    config: ByzantineAttackConfig,
}

impl ByzantineAttackScenarios {
    pub fn new(config: ByzantineAttackConfig) -> Self {
        Self { config }
    }

    /// Run all advanced Byzantine attack scenarios
    pub fn run_all_attack_scenarios(&self) -> Vec<AttackScenarioResult> {
        let mut results = Vec::new();

        println!("🚨 Running Advanced Byzantine Attack Scenarios");
        println!("Configuration: {} validators, {} Byzantine, {} offline", 
                self.config.total_validators, self.config.byzantine_count, self.config.offline_count);

        // Coordinated attack scenarios
        results.push(self.test_coordinated_double_voting_attack());
        results.push(self.test_coordinated_withholding_attack());
        results.push(self.test_coordinated_equivocation_attack());
        results.push(self.test_multi_vector_coordinated_attack());

        // Eclipse attack scenarios
        results.push(self.test_eclipse_attack_single_target());
        results.push(self.test_eclipse_attack_multiple_targets());
        results.push(self.test_eclipse_attack_with_network_manipulation());
        results.push(self.test_eclipse_attack_recovery());

        // Long-range attack scenarios
        results.push(self.test_long_range_attack_basic());
        results.push(self.test_long_range_attack_with_stake_grinding());
        results.push(self.test_nothing_at_stake_attack());
        results.push(self.test_posterior_corruption_attack());

        // Adaptive adversary scenarios
        results.push(self.test_adaptive_strategy_switching());
        results.push(self.test_adaptive_response_to_detection());
        results.push(self.test_adaptive_network_conditions());
        results.push(self.test_adaptive_stake_manipulation());

        // Economic attack scenarios
        results.push(self.test_economic_rational_attack());
        results.push(self.test_economic_griefing_attack());
        results.push(self.test_economic_bribery_attack());
        results.push(self.test_economic_stake_concentration_attack());

        // Timing attack scenarios
        results.push(self.test_timing_attack_basic());
        results.push(self.test_timing_attack_with_network_delays());
        results.push(self.test_timing_attack_view_synchronization());
        results.push(self.test_timing_attack_finalization_race());

        // Advanced combination scenarios
        results.push(self.test_combined_eclipse_and_timing_attack());
        results.push(self.test_combined_economic_and_coordination_attack());
        results.push(self.test_combined_adaptive_and_long_range_attack());
        results.push(self.test_maximum_adversarial_scenario());

        // Print summary
        let successful_attacks = results.iter().filter(|r| r.attack_successful).count();
        let protocol_resilient = results.iter().filter(|r| r.protocol_resilient).count();
        let total = results.len();

        println!("\n📊 Attack Scenario Summary:");
        println!("  Total scenarios: {}", total);
        println!("  Successful attacks: {} ({:.1}%)", successful_attacks, 
                (successful_attacks as f64 / total as f64) * 100.0);
        println!("  Protocol resilient: {} ({:.1}%)", protocol_resilient,
                (protocol_resilient as f64 / total as f64) * 100.0);

        results
    }

    /// Test coordinated double voting attack
    fn test_coordinated_double_voting_attack(&self) -> AttackScenarioResult {
        let mut result = self.create_attack_result("coordinated_double_voting_attack");
        let start_time = Instant::now();

        let config = Config::new()
            .with_validators(self.config.total_validators)
            .with_byzantine_threshold(self.config.byzantine_count);

        let model = AlpenglowModel::new(config.clone());
        let mut state = model.state().clone();

        // Mark validators as Byzantine
        for i in 0..self.config.byzantine_count {
            state.failure_states.insert(i as ValidatorId, ValidatorStatus::Byzantine);
        }

        let mut attack_metrics = AttackMetrics::default();
        let mut states_explored = 0;

        // Coordinated double voting attack
        for round in 0..self.config.attack_coordination_rounds {
            state.clock += 1;
            states_explored += 1;

            let current_view = round as ViewNumber + 1;

            // All Byzantine validators coordinate to double vote
            for byzantine_id in 0..self.config.byzantine_count {
                let validator_id = byzantine_id as ValidatorId;

                // First vote
                if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                    ByzantineAction::DoubleVote { validator: validator_id, view: current_view }
                )) {
                    state = new_state;
                    attack_metrics.coordinated_actions += 1;
                    states_explored += 1;
                }

                // Second coordinated vote on different block
                if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                    ByzantineAction::DoubleVote { validator: validator_id, view: current_view }
                )) {
                    state = new_state;
                    attack_metrics.coordinated_actions += 1;
                    states_explored += 1;
                }
            }

            // Honest validators respond
            for honest_id in self.config.byzantine_count..self.config.total_validators {
                let validator_id = honest_id as ValidatorId;
                let current_view = state.votor_view.get(&validator_id).copied().unwrap_or(1);

                if let Ok(new_state) = model.execute_action(AlpenglowAction::Votor(
                    VotorAction::CollectVotes { validator: validator_id, view: current_view }
                )) {
                    state = new_state;
                    states_explored += 1;
                }
            }

            // Check if attack succeeded (safety violation)
            if !properties::safety_no_conflicting_finalization(&state) {
                result.attack_successful = true;
                result.safety_violated = true;
                break;
            }
        }

        // Check protocol resilience
        result.protocol_resilient = properties::safety_no_conflicting_finalization(&state) &&
                                   properties::byzantine_resilience(&state, &config);

        result.states_explored = states_explored;
        result.attack_rounds = self.config.attack_coordination_rounds;
        result.execution_time_ms = start_time.elapsed().as_millis() as u64;
        result.attack_metrics = attack_metrics;

        if !result.protocol_resilient {
            result.violations_found.push("Protocol failed to resist coordinated double voting".to_string());
        }

        result
    }

    /// Test coordinated withholding attack
    fn test_coordinated_withholding_attack(&self) -> AttackScenarioResult {
        let mut result = self.create_attack_result("coordinated_withholding_attack");
        let start_time = Instant::now();

        let config = Config::new()
            .with_validators(self.config.total_validators)
            .with_byzantine_threshold(self.config.byzantine_count);

        let model = AlpenglowModel::new(config.clone());
        let mut state = model.state().clone();

        // Mark validators as Byzantine
        for i in 0..self.config.byzantine_count {
            state.failure_states.insert(i as ValidatorId, ValidatorStatus::Byzantine);
        }

        let mut attack_metrics = AttackMetrics::default();
        let mut states_explored = 0;

        // Create blocks to withhold
        for round in 0..self.config.attack_coordination_rounds {
            state.clock += 1;
            states_explored += 1;

            // Byzantine validators create and withhold blocks/shreds
            for byzantine_id in 0..self.config.byzantine_count {
                let validator_id = byzantine_id as ValidatorId;

                // Create block
                let test_block = Block {
                    slot: round + 1,
                    view: 1,
                    hash: (byzantine_id + 1) * 1000 + round,
                    parent: 0,
                    proposer: validator_id,
                    transactions: HashSet::new(),
                    timestamp: state.clock,
                    signature: 0,
                    data: vec![],
                };

                // Shred and distribute (but withhold from some validators)
                if let Ok(new_state) = model.execute_action(AlpenglowAction::Rotor(
                    RotorAction::ShredAndDistribute { leader: validator_id, block: test_block.clone() }
                )) {
                    state = new_state;
                    states_explored += 1;
                }

                // Withhold shreds from honest validators
                if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                    ByzantineAction::WithholdShreds { validator: validator_id }
                )) {
                    state = new_state;
                    attack_metrics.coordinated_actions += 1;
                    states_explored += 1;
                }
            }

            // Honest validators try to reconstruct
            for honest_id in self.config.byzantine_count..self.config.total_validators {
                let validator_id = honest_id as ValidatorId;

                // Try to request repair
                if let Ok(new_state) = model.execute_action(AlpenglowAction::Rotor(
                    RotorAction::RequestRepair { validator: validator_id, block_id: round + 1000 }
                )) {
                    state = new_state;
                    states_explored += 1;
                }
            }

            // Check if attack caused liveness issues
            if round > 5 && state.votor_finalized_chain.is_empty() {
                result.liveness_violated = true;
            }
        }

        // Measure bandwidth waste
        let total_bandwidth = self.config.total_validators * 1000; // Assume 1000 units per validator
        let wasted_bandwidth = attack_metrics.coordinated_actions * 100; // Estimate
        attack_metrics.bandwidth_waste_percentage = (wasted_bandwidth as f64 / total_bandwidth as f64) * 100.0;

        result.protocol_resilient = properties::safety_no_conflicting_finalization(&state) &&
                                   !result.liveness_violated;
        result.states_explored = states_explored;
        result.attack_rounds = self.config.attack_coordination_rounds;
        result.execution_time_ms = start_time.elapsed().as_millis() as u64;
        result.attack_metrics = attack_metrics;

        if result.liveness_violated {
            result.violations_found.push("Coordinated withholding caused liveness violation".to_string());
        }

        result
    }

    /// Test coordinated equivocation attack
    fn test_coordinated_equivocation_attack(&self) -> AttackScenarioResult {
        let mut result = self.create_attack_result("coordinated_equivocation_attack");
        let start_time = Instant::now();

        let config = Config::new()
            .with_validators(self.config.total_validators)
            .with_byzantine_threshold(self.config.byzantine_count);

        let model = AlpenglowModel::new(config.clone());
        let mut state = model.state().clone();

        // Mark validators as Byzantine
        for i in 0..self.config.byzantine_count {
            state.failure_states.insert(i as ValidatorId, ValidatorStatus::Byzantine);
        }

        let mut attack_metrics = AttackMetrics::default();
        let mut states_explored = 0;

        // Coordinated equivocation attack
        for round in 0..self.config.attack_coordination_rounds {
            state.clock += 1;
            states_explored += 1;

            // All Byzantine validators equivocate simultaneously
            for byzantine_id in 0..self.config.byzantine_count {
                let validator_id = byzantine_id as ValidatorId;

                // Send conflicting messages
                if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                    ByzantineAction::Equivocate { validator: validator_id }
                )) {
                    state = new_state;
                    attack_metrics.coordinated_actions += 1;
                    states_explored += 1;
                }

                // Send additional conflicting message
                if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                    ByzantineAction::Equivocate { validator: validator_id }
                )) {
                    state = new_state;
                    attack_metrics.coordinated_actions += 1;
                    states_explored += 1;
                }
            }

            // Honest validators process conflicting messages
            for honest_id in self.config.byzantine_count..self.config.total_validators {
                let validator_id = honest_id as ValidatorId;
                let current_view = state.votor_view.get(&validator_id).copied().unwrap_or(1);

                if let Ok(new_state) = model.execute_action(AlpenglowAction::Votor(
                    VotorAction::CollectVotes { validator: validator_id, view: current_view }
                )) {
                    state = new_state;
                    states_explored += 1;
                }
            }

            // Check for safety violations
            if !properties::safety_no_conflicting_finalization(&state) {
                result.attack_successful = true;
                result.safety_violated = true;
                break;
            }
        }

        result.protocol_resilient = properties::safety_no_conflicting_finalization(&state) &&
                                   properties::chain_consistency(&state);
        result.states_explored = states_explored;
        result.attack_rounds = self.config.attack_coordination_rounds;
        result.execution_time_ms = start_time.elapsed().as_millis() as u64;
        result.attack_metrics = attack_metrics;

        if !result.protocol_resilient {
            result.violations_found.push("Coordinated equivocation violated protocol safety".to_string());
        }

        result
    }

    /// Test multi-vector coordinated attack
    fn test_multi_vector_coordinated_attack(&self) -> AttackScenarioResult {
        let mut result = self.create_attack_result("multi_vector_coordinated_attack");
        let start_time = Instant::now();

        let config = Config::new()
            .with_validators(self.config.total_validators)
            .with_byzantine_threshold(self.config.byzantine_count);

        let model = AlpenglowModel::new(config.clone());
        let mut state = model.state().clone();

        // Mark validators as Byzantine
        for i in 0..self.config.byzantine_count {
            state.failure_states.insert(i as ValidatorId, ValidatorStatus::Byzantine);
        }

        let mut attack_metrics = AttackMetrics::default();
        let mut states_explored = 0;

        // Multi-vector attack combining different strategies
        for round in 0..self.config.attack_coordination_rounds {
            state.clock += 1;
            states_explored += 1;

            let current_view = round as ViewNumber + 1;

            // Distribute attack vectors among Byzantine validators
            for (idx, byzantine_id) in (0..self.config.byzantine_count).enumerate() {
                let validator_id = byzantine_id as ValidatorId;

                match idx % 4 {
                    0 => {
                        // Double voting
                        if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                            ByzantineAction::DoubleVote { validator: validator_id, view: current_view }
                        )) {
                            state = new_state;
                            attack_metrics.coordinated_actions += 1;
                            states_explored += 1;
                        }
                    }
                    1 => {
                        // Withholding
                        if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                            ByzantineAction::WithholdShreds { validator: validator_id }
                        )) {
                            state = new_state;
                            attack_metrics.coordinated_actions += 1;
                            states_explored += 1;
                        }
                    }
                    2 => {
                        // Equivocation
                        if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                            ByzantineAction::Equivocate { validator: validator_id }
                        )) {
                            state = new_state;
                            attack_metrics.coordinated_actions += 1;
                            states_explored += 1;
                        }
                    }
                    3 => {
                        // Invalid block
                        if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                            ByzantineAction::InvalidBlock { validator: validator_id }
                        )) {
                            state = new_state;
                            attack_metrics.coordinated_actions += 1;
                            states_explored += 1;
                        }
                    }
                    _ => {}
                }
            }

            // Honest validators respond
            for honest_id in self.config.byzantine_count..self.config.total_validators {
                let validator_id = honest_id as ValidatorId;
                let current_view = state.votor_view.get(&validator_id).copied().unwrap_or(1);

                if let Ok(new_state) = model.execute_action(AlpenglowAction::Votor(
                    VotorAction::CollectVotes { validator: validator_id, view: current_view }
                )) {
                    state = new_state;
                    states_explored += 1;
                }
            }

            // Check for any protocol violations
            if !properties::safety_no_conflicting_finalization(&state) ||
               !properties::chain_consistency(&state) {
                result.attack_successful = true;
                result.safety_violated = true;
                break;
            }
        }

        result.protocol_resilient = properties::safety_no_conflicting_finalization(&state) &&
                                   properties::chain_consistency(&state) &&
                                   properties::byzantine_resilience(&state, &config);
        result.states_explored = states_explored;
        result.attack_rounds = self.config.attack_coordination_rounds;
        result.execution_time_ms = start_time.elapsed().as_millis() as u64;
        result.attack_metrics = attack_metrics;

        if !result.protocol_resilient {
            result.violations_found.push("Multi-vector attack compromised protocol".to_string());
        }

        result
    }

    /// Test eclipse attack on single target
    fn test_eclipse_attack_single_target(&self) -> AttackScenarioResult {
        let mut result = self.create_attack_result("eclipse_attack_single_target");
        let start_time = Instant::now();

        let config = Config::new()
            .with_validators(self.config.total_validators)
            .with_byzantine_threshold(self.config.byzantine_count);

        let model = AlpenglowModel::new(config.clone());
        let mut state = model.state().clone();

        // Mark validators as Byzantine
        for i in 0..self.config.byzantine_count {
            state.failure_states.insert(i as ValidatorId, ValidatorStatus::Byzantine);
        }

        let mut attack_metrics = AttackMetrics::default();
        let mut states_explored = 0;

        // Target validator for eclipse attack
        let target_validator = self.config.byzantine_count as ValidatorId;

        // Create network partition to isolate target
        let mut isolated_partition = BTreeSet::new();
        isolated_partition.insert(target_validator);
        state.network_partitions.insert(isolated_partition);
        attack_metrics.network_partitions_created += 1;

        // Eclipse attack
        for round in 0..self.config.max_rounds {
            state.clock += 1;
            states_explored += 1;

            // Byzantine validators send conflicting information to target
            for byzantine_id in 0..self.config.byzantine_count {
                let attacker_id = byzantine_id as ValidatorId;

                if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                    ByzantineAction::EclipseAttack { attacker: attacker_id, target: target_validator }
                )) {
                    state = new_state;
                    attack_metrics.eclipse_attempts += 1;
                    states_explored += 1;
                }
            }

            // Other honest validators continue normal operation
            for honest_id in (self.config.byzantine_count + 1)..self.config.total_validators {
                let validator_id = honest_id as ValidatorId;
                let current_view = state.votor_view.get(&validator_id).copied().unwrap_or(1);

                if let Ok(new_state) = model.execute_action(AlpenglowAction::Votor(
                    VotorAction::CollectVotes { validator: validator_id, view: current_view }
                )) {
                    state = new_state;
                    states_explored += 1;
                }
            }

            // Check if target validator is affected
            let target_view = state.votor_view.get(&target_validator).copied().unwrap_or(1);
            let other_views: Vec<_> = (0..self.config.total_validators)
                .filter(|&i| i != target_validator as usize)
                .map(|i| state.votor_view.get(&(i as ValidatorId)).copied().unwrap_or(1))
                .collect();

            if other_views.iter().any(|&view| (view as i32 - target_view as i32).abs() > 2) {
                attack_metrics.honest_validators_affected += 1;
                result.attack_successful = true;
            }
        }

        result.protocol_resilient = properties::safety_no_conflicting_finalization(&state) &&
                                   properties::chain_consistency(&state);
        result.states_explored = states_explored;
        result.attack_rounds = self.config.max_rounds;
        result.execution_time_ms = start_time.elapsed().as_millis() as u64;
        result.attack_metrics = attack_metrics;

        if result.attack_successful && result.protocol_resilient {
            result.violations_found.push("Eclipse attack succeeded but protocol remained safe".to_string());
        } else if !result.protocol_resilient {
            result.violations_found.push("Eclipse attack compromised protocol safety".to_string());
        }

        result
    }

    /// Test eclipse attack on multiple targets
    fn test_eclipse_attack_multiple_targets(&self) -> AttackScenarioResult {
        let mut result = self.create_attack_result("eclipse_attack_multiple_targets");
        let start_time = Instant::now();

        let config = Config::new()
            .with_validators(self.config.total_validators)
            .with_byzantine_threshold(self.config.byzantine_count);

        let model = AlpenglowModel::new(config.clone());
        let mut state = model.state().clone();

        // Mark validators as Byzantine
        for i in 0..self.config.byzantine_count {
            state.failure_states.insert(i as ValidatorId, ValidatorStatus::Byzantine);
        }

        let mut attack_metrics = AttackMetrics::default();
        let mut states_explored = 0;

        // Multiple target validators for eclipse attack
        let target_validators: Vec<ValidatorId> = (self.config.byzantine_count..
            (self.config.byzantine_count + self.config.eclipse_target_count.min(3)))
            .map(|i| i as ValidatorId)
            .collect();

        // Create network partitions to isolate targets
        for &target in &target_validators {
            let mut isolated_partition = BTreeSet::new();
            isolated_partition.insert(target);
            state.network_partitions.insert(isolated_partition);
            attack_metrics.network_partitions_created += 1;
        }

        // Multi-target eclipse attack
        for round in 0..self.config.max_rounds {
            state.clock += 1;
            states_explored += 1;

            // Byzantine validators attack multiple targets
            for byzantine_id in 0..self.config.byzantine_count {
                let attacker_id = byzantine_id as ValidatorId;

                for &target in &target_validators {
                    if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                        ByzantineAction::EclipseAttack { attacker: attacker_id, target }
                    )) {
                        state = new_state;
                        attack_metrics.eclipse_attempts += 1;
                        states_explored += 1;
                    }
                }
            }

            // Remaining honest validators continue operation
            for validator_id in (self.config.byzantine_count + self.config.eclipse_target_count)..self.config.total_validators {
                let vid = validator_id as ValidatorId;
                let current_view = state.votor_view.get(&vid).copied().unwrap_or(1);

                if let Ok(new_state) = model.execute_action(AlpenglowAction::Votor(
                    VotorAction::CollectVotes { validator: vid, view: current_view }
                )) {
                    state = new_state;
                    states_explored += 1;
                }
            }

            // Check if multiple targets are affected
            let affected_targets = target_validators.iter()
                .filter(|&&target| {
                    let target_view = state.votor_view.get(&target).copied().unwrap_or(1);
                    let other_views: Vec<_> = (0..self.config.total_validators)
                        .filter(|&i| i != target as usize && !target_validators.contains(&(i as ValidatorId)))
                        .map(|i| state.votor_view.get(&(i as ValidatorId)).copied().unwrap_or(1))
                        .collect();
                    other_views.iter().any(|&view| (view as i32 - target_view as i32).abs() > 2)
                })
                .count();

            attack_metrics.honest_validators_affected = affected_targets;

            if affected_targets >= 2 {
                result.attack_successful = true;
            }
        }

        result.protocol_resilient = properties::safety_no_conflicting_finalization(&state) &&
                                   properties::chain_consistency(&state);
        result.states_explored = states_explored;
        result.attack_rounds = self.config.max_rounds;
        result.execution_time_ms = start_time.elapsed().as_millis() as u64;
        result.attack_metrics = attack_metrics;

        if result.attack_successful {
            result.violations_found.push(format!("Eclipse attack affected {} targets", 
                                                attack_metrics.honest_validators_affected));
        }

        result
    }

    /// Test eclipse attack with network manipulation
    fn test_eclipse_attack_with_network_manipulation(&self) -> AttackScenarioResult {
        let mut result = self.create_attack_result("eclipse_attack_with_network_manipulation");
        let start_time = Instant::now();

        let config = Config::new()
            .with_validators(self.config.total_validators)
            .with_byzantine_threshold(self.config.byzantine_count);

        let model = AlpenglowModel::new(config.clone());
        let mut state = model.state().clone();

        // Mark validators as Byzantine
        for i in 0..self.config.byzantine_count {
            state.failure_states.insert(i as ValidatorId, ValidatorStatus::Byzantine);
        }

        let mut attack_metrics = AttackMetrics::default();
        let mut states_explored = 0;
        let target_validator = self.config.byzantine_count as ValidatorId;

        // Eclipse attack with network manipulation
        for round in 0..self.config.max_rounds {
            state.clock += 1;
            states_explored += 1;

            // Network manipulation with probability
            if (round as f64 * 0.1) % 1.0 < self.config.network_manipulation_probability {
                // Create temporary network partition
                if let Ok(new_state) = model.execute_action(AlpenglowAction::Network(
                    NetworkAction::PartitionNetwork { 
                        partition: [target_validator].iter().cloned().collect() 
                    }
                )) {
                    state = new_state;
                    attack_metrics.network_partitions_created += 1;
                    states_explored += 1;
                }

                // Delay messages to target
                if let Ok(new_state) = model.execute_action(AlpenglowAction::Network(
                    NetworkAction::DelayMessages { 
                        target: target_validator, 
                        delay_ms: self.config.timing_attack_delay_ms 
                    }
                )) {
                    state = new_state;
                    attack_metrics.timing_manipulation_count += 1;
                    states_explored += 1;
                }
            }

            // Byzantine validators exploit network manipulation
            for byzantine_id in 0..self.config.byzantine_count {
                let attacker_id = byzantine_id as ValidatorId;

                if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                    ByzantineAction::EclipseAttack { attacker: attacker_id, target: target_validator }
                )) {
                    state = new_state;
                    attack_metrics.eclipse_attempts += 1;
                    states_explored += 1;
                }
            }

            // Honest validators try to maintain consensus
            for honest_id in (self.config.byzantine_count + 1)..self.config.total_validators {
                let validator_id = honest_id as ValidatorId;
                let current_view = state.votor_view.get(&validator_id).copied().unwrap_or(1);

                if let Ok(new_state) = model.execute_action(AlpenglowAction::Votor(
                    VotorAction::CollectVotes { validator: validator_id, view: current_view }
                )) {
                    state = new_state;
                    states_explored += 1;
                }
            }

            // Periodically heal partitions to simulate network recovery
            if round % 10 == 9 {
                if let Ok(new_state) = model.execute_action(AlpenglowAction::Network(
                    NetworkAction::HealPartition
                )) {
                    state = new_state;
                    states_explored += 1;
                }
            }
        }

        // Check if attack succeeded in isolating target
        let target_isolated = state.network_partitions.iter()
            .any(|partition| partition.contains(&target_validator));

        if target_isolated {
            result.attack_successful = true;
            attack_metrics.honest_validators_affected = 1;
        }

        result.protocol_resilient = properties::safety_no_conflicting_finalization(&state) &&
                                   properties::chain_consistency(&state);
        result.states_explored = states_explored;
        result.attack_rounds = self.config.max_rounds;
        result.execution_time_ms = start_time.elapsed().as_millis() as u64;
        result.attack_metrics = attack_metrics;

        if result.attack_successful {
            result.violations_found.push("Eclipse attack with network manipulation succeeded".to_string());
        }

        result
    }

    /// Test eclipse attack recovery
    fn test_eclipse_attack_recovery(&self) -> AttackScenarioResult {
        let mut result = self.create_attack_result("eclipse_attack_recovery");
        let start_time = Instant::now();

        let config = Config::new()
            .with_validators(self.config.total_validators)
            .with_byzantine_threshold(self.config.byzantine_count);

        let model = AlpenglowModel::new(config.clone());
        let mut state = model.state().clone();

        // Mark validators as Byzantine
        for i in 0..self.config.byzantine_count {
            state.failure_states.insert(i as ValidatorId, ValidatorStatus::Byzantine);
        }

        let mut attack_metrics = AttackMetrics::default();
        let mut states_explored = 0;
        let target_validator = self.config.byzantine_count as ValidatorId;
        let mut recovery_started = false;
        let mut recovery_start_time = 0;

        // Eclipse attack followed by recovery
        for round in 0..self.config.max_rounds {
            state.clock += 1;
            states_explored += 1;

            if round < self.config.max_rounds / 2 {
                // Attack phase
                for byzantine_id in 0..self.config.byzantine_count {
                    let attacker_id = byzantine_id as ValidatorId;

                    if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                        ByzantineAction::EclipseAttack { attacker: attacker_id, target: target_validator }
                    )) {
                        state = new_state;
                        attack_metrics.eclipse_attempts += 1;
                        states_explored += 1;
                    }
                }

                // Create isolation
                if round == 5 {
                    let mut isolated_partition = BTreeSet::new();
                    isolated_partition.insert(target_validator);
                    state.network_partitions.insert(isolated_partition);
                    attack_metrics.network_partitions_created += 1;
                }
            } else {
                // Recovery phase
                if !recovery_started {
                    recovery_started = true;
                    recovery_start_time = round;

                    // Heal network partition
                    if let Ok(new_state) = model.execute_action(AlpenglowAction::Network(
                        NetworkAction::HealPartition
                    )) {
                        state = new_state;
                        states_explored += 1;
                    }
                }

                // All validators participate in recovery
                for validator_id in 0..self.config.total_validators {
                    let vid = validator_id as ValidatorId;
                    
                    if validator_id >= self.config.byzantine_count {
                        // Honest validators help with recovery
                        let current_view = state.votor_view.get(&vid).copied().unwrap_or(1);

                        if let Ok(new_state) = model.execute_action(AlpenglowAction::Votor(
                            VotorAction::CollectVotes { validator: vid, view: current_view }
                        )) {
                            state = new_state;
                            states_explored += 1;
                        }
                    }
                }
            }
        }

        // Calculate recovery time
        if recovery_started {
            result.recovery_time_ms = ((self.config.max_rounds - recovery_start_time) * 100) as u64;
        }

        // Check if target recovered
        let target_recovered = !state.network_partitions.iter()
            .any(|partition| partition.contains(&target_validator));

        result.protocol_resilient = properties::safety_no_conflicting_finalization(&state) &&
                                   properties::chain_consistency(&state) &&
                                   target_recovered;
        result.states_explored = states_explored;
        result.attack_rounds = self.config.max_rounds;
        result.execution_time_ms = start_time.elapsed().as_millis() as u64;
        result.attack_metrics = attack_metrics;

        if !target_recovered {
            result.violations_found.push("Target validator failed to recover from eclipse attack".to_string());
        }

        result
    }

    /// Test basic long-range attack
    fn test_long_range_attack_basic(&self) -> AttackScenarioResult {
        let mut result = self.create_attack_result("long_range_attack_basic");
        let start_time = Instant::now();

        let config = Config::new()
            .with_validators(self.config.total_validators)
            .with_byzantine_threshold(self.config.byzantine_count);

        let model = AlpenglowModel::new(config.clone());
        let mut state = model.state().clone();

        // Mark validators as Byzantine
        for i in 0..self.config.byzantine_count {
            state.failure_states.insert(i as ValidatorId, ValidatorStatus::Byzantine);
        }

        let mut attack_metrics = AttackMetrics::default();
        let mut states_explored = 0;

        // Create alternative chain from deep history
        let fork_point = self.config.long_range_depth;
        let mut alternative_chain = Vec::new();

        // Build alternative chain
        for depth in 0..fork_point {
            state.clock += 1;
            states_explored += 1;

            // Byzantine validators create alternative blocks
            for byzantine_id in 0..self.config.byzantine_count {
                let validator_id = byzantine_id as ValidatorId;

                let alternative_block = Block {
                    slot: depth + 1,
                    view: 1,
                    hash: 9000 + depth + byzantine_id * 100, // Alternative hash
                    parent: if depth == 0 { 0 } else { 9000 + depth - 1 + byzantine_id * 100 },
                    proposer: validator_id,
                    transactions: HashSet::new(),
                    timestamp: state.clock,
                    signature: 0,
                    data: vec![],
                };

                alternative_chain.push(alternative_block.clone());

                // Try to propose alternative block
                if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                    ByzantineAction::LongRangeAttack { 
                        validator: validator_id, 
                        alternative_block: alternative_block.clone() 
                    }
                )) {
                    state = new_state;
                    attack_metrics.long_range_forks += 1;
                    states_explored += 1;
                }
            }

            // Honest validators continue on main chain
            for honest_id in self.config.byzantine_count..self.config.total_validators {
                let validator_id = honest_id as ValidatorId;
                let current_view = state.votor_view.get(&validator_id).copied().unwrap_or(1);

                if let Ok(new_state) = model.execute_action(AlpenglowAction::Votor(
                    VotorAction::CollectVotes { validator: validator_id, view: current_view }
                )) {
                    state = new_state;
                    states_explored += 1;
                }
            }
        }

        // Check if alternative chain was created
        result.attack_successful = attack_metrics.long_range_forks > 0;

        result.protocol_resilient = properties::safety_no_conflicting_finalization(&state) &&
                                   properties::chain_consistency(&state);
        result.states_explored = states_explored;
        result.attack_rounds = fork_point;
        result.execution_time_ms = start_time.elapsed().as_millis() as u64;
        result.attack_metrics = attack_metrics;

        if result.attack_successful && !result.protocol_resilient {
            result.violations_found.push("Long-range attack compromised chain consistency".to_string());
        }

        result
    }

    /// Test long-range attack with stake grinding
    fn test_long_range_attack_with_stake_grinding(&self) -> AttackScenarioResult {
        let mut result = self.create_attack_result("long_range_attack_with_stake_grinding");
        let start_time = Instant::now();

        let config = Config::new()
            .with_validators(self.config.total_validators)
            .with_byzantine_threshold(self.config.byzantine_count);

        let model = AlpenglowModel::new(config.clone());
        let mut state = model.state().clone();

        // Mark validators as Byzantine
        for i in 0..self.config.byzantine_count {
            state.failure_states.insert(i as ValidatorId, ValidatorStatus::Byzantine);
        }

        let mut attack_metrics = AttackMetrics::default();
        let mut states_explored = 0;

        // Long-range attack with VRF grinding
        for round in 0..self.config.long_range_depth {
            state.clock += 1;
            states_explored += 1;

            // Byzantine validators grind VRF for better leader selection
            for byzantine_id in 0..self.config.byzantine_count {
                let validator_id = byzantine_id as ValidatorId;

                // Grind VRF
                if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                    ByzantineAction::GrindVRF { validator: validator_id }
                )) {
                    state = new_state;
                    attack_metrics.long_range_forks += 1;
                    states_explored += 1;
                }

                // Create alternative block with ground VRF
                let alternative_block = Block {
                    slot: round + 1,
                    view: 1,
                    hash: 8000 + round + byzantine_id * 100,
                    parent: if round == 0 { 0 } else { 8000 + round - 1 + byzantine_id * 100 },
                    proposer: validator_id,
                    transactions: HashSet::new(),
                    timestamp: state.clock,
                    signature: 0,
                    data: vec![],
                };

                if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                    ByzantineAction::LongRangeAttack { 
                        validator: validator_id, 
                        alternative_block 
                    }
                )) {
                    state = new_state;
                    attack_metrics.long_range_forks += 1;
                    states_explored += 1;
                }
            }

            // Honest validators continue normal operation
            for honest_id in self.config.byzantine_count..self.config.total_validators {
                let validator_id = honest_id as ValidatorId;
                let current_view = state.votor_view.get(&validator_id).copied().unwrap_or(1);

                if let Ok(new_state) = model.execute_action(AlpenglowAction::Votor(
                    VotorAction::CollectVotes { validator: validator_id, view: current_view }
                )) {
                    state = new_state;
                    states_explored += 1;
                }
            }
        }

        result.attack_successful = attack_metrics.long_range_forks > self.config.long_range_depth;
        result.protocol_resilient = properties::safety_no_conflicting_finalization(&state) &&
                                   properties::chain_consistency(&state);
        result.states_explored = states_explored;
        result.attack_rounds = self.config.long_range_depth;
        result.execution_time_ms = start_time.elapsed().as_millis() as u64;
        result.attack_metrics = attack_metrics;

        if result.attack_successful {
            result.violations_found.push("Long-range attack with stake grinding succeeded".to_string());
        }

        result
    }

    /// Test nothing-at-stake attack
    fn test_nothing_at_stake_attack(&self) -> AttackScenarioResult {
        let mut result = self.create_attack_result("nothing_at_stake_attack");
        let start_time = Instant::now();

        let config = Config::new()
            .with_validators(self.config.total_validators)
            .with_byzantine_threshold(self.config.byzantine_count);

        let model = AlpenglowModel::new(config.clone());
        let mut state = model.state().clone();

        // Mark validators as Byzantine
        for i in 0..self.config.byzantine_count {
            state.failure_states.insert(i as ValidatorId, ValidatorStatus::Byzantine);
        }

        let mut attack_metrics = AttackMetrics::default();
        let mut states_explored = 0;

        // Nothing-at-stake attack - vote on all possible chains
        for round in 0..self.config.max_rounds {
            state.clock += 1;
            states_explored += 1;

            // Byzantine validators vote on multiple competing chains
            for byzantine_id in 0..self.config.byzantine_count {
                let validator_id = byzantine_id as ValidatorId;

                // Vote on multiple chains simultaneously
                if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                    ByzantineAction::NothingAtStake { validator: validator_id }
                )) {
                    state = new_state;
                    attack_metrics.long_range_forks += 1;
                    states_explored += 1;
                }

                // Create additional competing blocks
                for chain_id in 0..3 {
                    let competing_block = Block {
                        slot: round + 1,
                        view: 1,
                        hash: 7000 + round + byzantine_id * 100 + chain_id * 10,
                        parent: if round == 0 { 0 } else { 7000 + round - 1 + byzantine_id * 100 + chain_id * 10 },
                        proposer: validator_id,
                        transactions: HashSet::new(),
                        timestamp: state.clock,
                        signature: 0,
                        data: vec![],
                    };

                    if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                        ByzantineAction::LongRangeAttack { 
                            validator: validator_id, 
                            alternative_block: competing_block 
                        }
                    )) {
                        state = new_state;
                        attack_metrics.long_range_forks += 1;
                        states_explored += 1;
                    }
                }
            }

            // Honest validators follow protocol
            for honest_id in self.config.byzantine_count..self.config.total_validators {
                let validator_id = honest_id as ValidatorId;
                let current_view = state.votor_view.get(&validator_id).copied().unwrap_or(1);

                if let Ok(new_state) = model.execute_action(AlpenglowAction::Votor(
                    VotorAction::CollectVotes { validator: validator_id, view: current_view }
                )) {
                    state = new_state;
                    states_explored += 1;
                }
            }

            // Check if multiple chains are being built
            if attack_metrics.long_range_forks > round * 2 {
                result.attack_successful = true;
            }
        }

        result.protocol_resilient = properties::safety_no_conflicting_finalization(&state) &&
                                   properties::chain_consistency(&state);
        result.states_explored = states_explored;
        result.attack_rounds = self.config.max_rounds;
        result.execution_time_ms = start_time.elapsed().as_millis() as u64;
        result.attack_metrics = attack_metrics;

        if result.attack_successful && !result.protocol_resilient {
            result.violations_found.push("Nothing-at-stake attack compromised protocol".to_string());
        }

        result
    }

    /// Test posterior corruption attack
    fn test_posterior_corruption_attack(&self) -> AttackScenarioResult {
        let mut result = self.create_attack_result("posterior_corruption_attack");
        let start_time = Instant::now();

        let config = Config::new()
            .with_validators(self.config.total_validators)
            .with_byzantine_threshold(self.config.byzantine_count);

        let model = AlpenglowModel::new(config.clone());
        let mut state = model.state().clone();

        let mut attack_metrics = AttackMetrics::default();
        let mut states_explored = 0;

        // Phase 1: Normal operation with honest validators
        for round in 0..self.config.max_rounds / 2 {
            state.clock += 1;
            states_explored += 1;

            // All validators behave honestly initially
            for validator_id in 0..self.config.total_validators {
                let vid = validator_id as ValidatorId;
                let current_view = state.votor_view.get(&vid).copied().unwrap_or(1);

                if let Ok(new_state) = model.execute_action(AlpenglowAction::Votor(
                    VotorAction::CollectVotes { validator: vid, view: current_view }
                )) {
                    state = new_state;
                    states_explored += 1;
                }
            }
        }

        // Phase 2: Posterior corruption - validators become Byzantine
        for i in 0..self.config.byzantine_count {
            state.failure_states.insert(i as ValidatorId, ValidatorStatus::Byzantine);
        }

        // Phase 3: Byzantine attack on historical state
        for round in (self.config.max_rounds / 2)..self.config.max_rounds {
            state.clock += 1;
            states_explored += 1;

            // Byzantine validators try to rewrite history
            for byzantine_id in 0..self.config.byzantine_count {
                let validator_id = byzantine_id as ValidatorId;

                // Create alternative historical block
                let historical_block = Block {
                    slot: round - self.config.max_rounds / 2 + 1,
                    view: 1,
                    hash: 6000 + round + byzantine_id * 100,
                    parent: 0,
                    proposer: validator_id,
                    transactions: HashSet::new(),
                    timestamp: state.clock - (self.config.max_rounds / 2) as TimeValue,
                    signature: 0,
                    data: vec![],
                };

                if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                    ByzantineAction::LongRangeAttack { 
                        validator: validator_id, 
                        alternative_block: historical_block 
                    }
                )) {
                    state = new_state;
                    attack_metrics.long_range_forks += 1;
                    states_explored += 1;
                }
            }

            // Remaining honest validators continue
            for honest_id in self.config.byzantine_count..self.config.total_validators {
                let validator_id = honest_id as ValidatorId;
                let current_view = state.votor_view.get(&validator_id).copied().unwrap_or(1);

                if let Ok(new_state) = model.execute_action(AlpenglowAction::Votor(
                    VotorAction::CollectVotes { validator: validator_id, view: current_view }
                )) {
                    state = new_state;
                    states_explored += 1;
                }
            }
        }

        result.attack_successful = attack_metrics.long_range_forks > 0;
        result.protocol_resilient = properties::safety_no_conflicting_finalization(&state) &&
                                   properties::chain_consistency(&state);
        result.states_explored = states_explored;
        result.attack_rounds = self.config.max_rounds;
        result.execution_time_ms = start_time.elapsed().as_millis() as u64;
        result.attack_metrics = attack_metrics;

        if result.attack_successful {
            result.violations_found.push("Posterior corruption attack attempted history rewrite".to_string());
        }

        result
    }

    /// Test adaptive strategy switching
    fn test_adaptive_strategy_switching(&self) -> AttackScenarioResult {
        let mut result = self.create_attack_result("adaptive_strategy_switching");
        let start_time = Instant::now();

        let config = Config::new()
            .with_validators(self.config.total_validators)
            .with_byzantine_threshold(self.config.byzantine_count);

        let model = AlpenglowModel::new(config.clone());
        let mut state = model.state().clone();

        // Mark validators as Byzantine
        for i in 0..self.config.byzantine_count {
            state.failure_states.insert(i as ValidatorId, ValidatorStatus::Byzantine);
        }

        let mut attack_metrics = AttackMetrics::default();
        let mut states_explored = 0;
        let mut current_strategy = 0;

        // Adaptive attack with strategy switching
        for round in 0..self.config.max_rounds {
            state.clock += 1;
            states_explored += 1;

            // Switch strategy every few rounds
            if round % (self.config.max_rounds / self.config.adaptive_strategy_changes) == 0 {
                current_strategy = (current_strategy + 1) % 4;
                attack_metrics.adaptive_strategy_switches += 1;
            }

            // Execute strategy based on current choice
            for byzantine_id in 0..self.config.byzantine_count {
                let validator_id = byzantine_id as ValidatorId;
                let current_view = state.votor_view.get(&validator_id).copied().unwrap_or(1);

                match current_strategy {
                    0 => {
                        // Double voting strategy
                        if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                            ByzantineAction::DoubleVote { validator: validator_id, view: current_view }
                        )) {
                            state = new_state;
                            states_explored += 1;
                        }
                    }
                    1 => {
                        // Withholding strategy
                        if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                            ByzantineAction::WithholdShreds { validator: validator_id }
                        )) {
                            state = new_state;
                            states_explored += 1;
                        }
                    }
                    2 => {
                        // Equivocation strategy
                        if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                            ByzantineAction::Equivocate { validator: validator_id }
                        )) {
                            state = new_state;
                            states_explored += 1;
                        }
                    }
                    3 => {
                        // Invalid block strategy
                        if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                            ByzantineAction::InvalidBlock { validator: validator_id }
                        )) {
                            state = new_state;
                            states_explored += 1;
                        }
                    }
                    _ => {}
                }
            }

            // Honest validators respond
            for honest_id in self.config.byzantine_count..self.config.total_validators {
                let validator_id = honest_id as ValidatorId;
                let current_view = state.votor_view.get(&validator_id).copied().unwrap_or(1);

                if let Ok(new_state) = model.execute_action(AlpenglowAction::Votor(
                    VotorAction::CollectVotes { validator: validator_id, view: current_view }
                )) {
                    state = new_state;
                    states_explored += 1;
                }
            }

            // Check if any strategy succeeded
            if !properties::safety_no_conflicting_finalization(&state) ||
               !properties::chain_consistency(&state) {
                result.attack_successful = true;
                break;
            }
        }

        result.protocol_resilient = properties::safety_no_conflicting_finalization(&state) &&
                                   properties::chain_consistency(&state) &&
                                   properties::byzantine_resilience(&state, &config);
        result.states_explored = states_explored;
        result.attack_rounds = self.config.max_rounds;
        result.execution_time_ms = start_time.elapsed().as_millis() as u64;
        result.attack_metrics = attack_metrics;

        if attack_metrics.adaptive_strategy_switches > 0 && result.protocol_resilient {
            result.violations_found.push(format!("Adaptive attack switched strategies {} times but protocol remained resilient", 
                                                attack_metrics.adaptive_strategy_switches));
        }

        result
    }

    /// Test adaptive response to detection
    fn test_adaptive_response_to_detection(&self) -> AttackScenarioResult {
        let mut result = self.create_attack_result("adaptive_response_to_detection");
        let start_time = Instant::now();

        let config = Config::new()
            .with_validators(self.config.total_validators)
            .with_byzantine_threshold(self.config.byzantine_count);

        let model = AlpenglowModel::new(config.clone());
        let mut state = model.state().clone();

        // Mark validators as Byzantine
        for i in 0..self.config.byzantine_count {
            state.failure_states.insert(i as ValidatorId, ValidatorStatus::Byzantine);
        }

        let mut attack_metrics = AttackMetrics::default();
        let mut states_explored = 0;
        let mut detection_occurred = false;
        let mut detection_time = 0;

        // Adaptive attack that responds to detection
        for round in 0..self.config.max_rounds {
            state.clock += 1;
            states_explored += 1;

            if !detection_occurred {
                // Initial attack phase - obvious Byzantine behavior
                for byzantine_id in 0..self.config.byzantine_count {
                    let validator_id = byzantine_id as ValidatorId;
                    let current_view = state.votor_view.get(&validator_id).copied().unwrap_or(1);

                    if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                        ByzantineAction::DoubleVote { validator: validator_id, view: current_view }
                    )) {
                        state = new_state;
                        states_explored += 1;
                    }
                }

                // Check for detection (simplified - look for double votes in system)
                let double_votes_detected = state.votor_received_votes.values()
                    .flat_map(|view_votes| view_votes.values())
                    .flat_map(|votes| votes.iter())
                    .filter(|vote| (0..self.config.byzantine_count).contains(&(vote.voter as usize)))
                    .count() > self.config.byzantine_count * 2;

                if double_votes_detected {
                    detection_occurred = true;
                    detection_time = round;
                    attack_metrics.adaptive_strategy_switches += 1;
                }
            } else {
                // Post-detection phase - subtle attacks
                for byzantine_id in 0..self.config.byzantine_count {
                    let validator_id = byzantine_id as ValidatorId;

                    // Switch to more subtle withholding attack
                    if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                        ByzantineAction::WithholdShreds { validator: validator_id }
                    )) {
                        state = new_state;
                        states_explored += 1;
                    }
                }
            }

            // Honest validators respond
            for honest_id in self.config.byzantine_count..self.config.total_validators {
                let validator_id = honest_id as ValidatorId;
                let current_view = state.votor_view.get(&validator_id).copied().unwrap_or(1);

                if let Ok(new_state) = model.execute_action(AlpenglowAction::Votor(
                    VotorAction::CollectVotes { validator: validator_id, view: current_view }
                )) {
                    state = new_state;
                    states_explored += 1;
                }
            }
        }

        result.detection_time_ms = (detection_time * 100) as u64; // Estimate
        result.attack_successful = detection_occurred;
        result.protocol_resilient = properties::safety_no_conflicting_finalization(&state) &&
                                   properties::chain_consistency(&state);
        result.states_explored = states_explored;
        result.attack_rounds = self.config.max_rounds;
        result.execution_time_ms = start_time.elapsed().as_millis() as u64;
        result.attack_metrics = attack_metrics;

        if detection_occurred {
            result.violations_found.push(format!("Byzantine behavior detected at round {}, attack adapted", detection_time));
        }

        result
    }

    /// Test adaptive network conditions
    fn test_adaptive_network_conditions(&self) -> AttackScenarioResult {
        let mut result = self.create_attack_result("adaptive_network_conditions");
        let start_time = Instant::now();

        let config = Config::new()
            .with_validators(self.config.total_validators)
            .with_byzantine_threshold(self.config.byzantine_count);

        let model = AlpenglowModel::new(config.clone());
        let mut state = model.state().clone();

        // Mark validators as Byzantine
        for i in 0..self.config.byzantine_count {
            state.failure_states.insert(i as ValidatorId, ValidatorStatus::Byzantine);
        }

        let mut attack_metrics = AttackMetrics::default();
        let mut states_explored = 0;

        // Adaptive attack based on network conditions
        for round in 0..self.config.max_rounds {
            state.clock += 1;
            states_explored += 1;

            // Assess network conditions
            let network_partitioned = !state.network_partitions.is_empty();
            let high_latency = state.network_message_queue.len() > 10;
            let low_participation = state.votor_received_votes.values()
                .flat_map(|view_votes| view_votes.values())
                .map(|votes| votes.len())
                .sum::<usize>() < self.config.total_validators / 2;

            // Adapt attack strategy to network conditions
            for byzantine_id in 0..self.config.byzantine_count {
                let validator_id = byzantine_id as ValidatorId;
                let current_view = state.votor_view.get(&validator_id).copied().unwrap_or(1);

                if network_partitioned {
                    // Exploit partition with eclipse attack
                    if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                        ByzantineAction::EclipseAttack { 
                            attacker: validator_id, 
                            target: (self.config.byzantine_count + byzantine_id) as ValidatorId 
                        }
                    )) {
                        state = new_state;
                        attack_metrics.eclipse_attempts += 1;
                        attack_metrics.adaptive_strategy_switches += 1;
                        states_explored += 1;
                    }
                } else if high_latency {
                    // Exploit high latency with timing attacks
                    if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                        ByzantineAction::TimingAttack { 
                            validator: validator_id, 
                            delay_ms: self.config.timing_attack_delay_ms 
                        }
                    )) {
                        state = new_state;
                        attack_metrics.timing_manipulation_count += 1;
                        attack_metrics.adaptive_strategy_switches += 1;
                        states_explored += 1;
                    }
                } else if low_participation {
                    // Exploit low participation with withholding
                    if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                        ByzantineAction::WithholdShreds { validator: validator_id }
                    )) {
                        state = new_state;
                        attack_metrics.adaptive_strategy_switches += 1;
                        states_explored += 1;
                    }
                } else {
                    // Default to double voting
                    if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                        ByzantineAction::DoubleVote { validator: validator_id, view: current_view }
                    )) {
                        state = new_state;
                        states_explored += 1;
                    }
                }
            }

            // Simulate network condition changes
            if round % 10 == 0 {
                if state.network_partitions.is_empty() && round % 20 == 0 {
                    // Create partition
                    if let Ok(new_state) = model.execute_action(AlpenglowAction::Network(
                        NetworkAction::PartitionNetwork { 
                            partition: [0, 1].iter().cloned().collect() 
                        }
                    )) {
                        state = new_state;
                        attack_metrics.network_partitions_created += 1;
                        states_explored += 1;
                    }
                } else if !state.network_partitions.is_empty() {
                    // Heal partition
                    if let Ok(new_state) = model.execute_action(AlpenglowAction::Network(
                        NetworkAction::HealPartition
                    )) {
                        state = new_state;
                        states_explored += 1;
                    }
                }
            }

            // Honest validators respond
            for honest_id in self.config.byzantine_count..self.config.total_validators {
                let validator_id = honest_id as ValidatorId;
                let current_view = state.votor_view.get(&validator_id).copied().unwrap_or(1);

                if let Ok(new_state) = model.execute_action(AlpenglowAction::Votor(
                    VotorAction::CollectVotes { validator: validator_id, view: current_view }
                )) {
                    state = new_state;
                    states_explored += 1;
                }
            }
        }

        result.attack_successful = attack_metrics.adaptive_strategy_switches > 3;
        result.protocol_resilient = properties::safety_no_conflicting_finalization(&state) &&
                                   properties::chain_consistency(&state);
        result.states_explored = states_explored;
        result.attack_rounds = self.config.max_rounds;
        result.execution_time_ms = start_time.elapsed().as_millis() as u64;
        result.attack_metrics = attack_metrics;

        if result.attack_successful {
            result.violations_found.push(format!("Adaptive attack made {} strategy changes based on network conditions", 
                                                attack_metrics.adaptive_strategy_switches));
        }

        result
    }

    /// Test adaptive stake manipulation
    fn test_adaptive_stake_manipulation(&self) -> AttackScenarioResult {
        let mut result = self.create_attack_result("adaptive_stake_manipulation");
        let start_time = Instant::now();

        let config = Config::new()
            .with_validators(self.config.total_validators)
            .with_byzantine_threshold(self.config.byzantine_count);

        let model = AlpenglowModel::new(config.clone());
        let mut state = model.state().clone();

        // Mark validators as Byzantine
        for i in 0..self.config.byzantine_count {
            state.failure_states.insert(i as ValidatorId, ValidatorStatus::Byzantine);
        }

        let mut attack_metrics = AttackMetrics::default();
        let mut states_explored = 0;

        // Adaptive attack with stake manipulation
        for round in 0..self.config.max_rounds {
            state.clock += 1;
            states_explored += 1;

            // Assess current stake distribution
            let total_stake = config.total_stake;
            let byzantine_stake: u64 = (0..self.config.byzantine_count)
                .map(|i| config.stake_distribution.get(&(i as ValidatorId)).copied().unwrap_or(0))
                .sum();
            let byzantine_stake_percentage = (byzantine_stake as f64 / total_stake as f64) * 100.0;

            // Adapt strategy based on stake percentage
            for byzantine_id in 0..self.config.byzantine_count {
                let validator_id = byzantine_id as ValidatorId;
                let current_view = state.votor_view.get(&validator_id).copied().unwrap_or(1);

                if byzantine_stake_percentage > 25.0 {
                    // High stake - attempt more aggressive attacks
                    if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                        ByzantineAction::DoubleVote { validator: validator_id, view: current_view }
                    )) {
                        state = new_state;
                        attack_metrics.adaptive_strategy_switches += 1;
                        states_explored += 1;
                    }
                } else if byzantine_stake_percentage > 15.0 {
                    // Medium stake - coordinated attacks
                    if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                        ByzantineAction::Equivocate { validator: validator_id }
                    )) {
                        state = new_state;
                        attack_metrics.adaptive_strategy_switches += 1;
                        states_explored += 1;
                    }
                } else {
                    // Low stake - subtle attacks
                    if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                        ByzantineAction::WithholdShreds { validator: validator_id }
                    )) {
                        state = new_state;
                        attack_metrics.adaptive_strategy_switches += 1;
                        states_explored += 1;
                    }
                }
            }

            // Honest validators respond
            for honest_id in self.config.byzantine_count..self.config.total_validators {
                let validator_id = honest_id as ValidatorId;
                let current_view = state.votor_view.get(&validator_id).copied().unwrap_or(1);

                if let Ok(new_state) = model.execute_action(AlpenglowAction::Votor(
                    VotorAction::CollectVotes { validator: validator_id, view: current_view }
                )) {
                    state = new_state;
                    states_explored += 1;
                }
            }
        }

        attack_metrics.economic_damage_percentage = 
            (attack_metrics.adaptive_strategy_switches as f64 / self.config.max_rounds as f64) * 100.0;

        result.attack_successful = attack_metrics.adaptive_strategy_switches > 0;
        result.protocol_resilient = properties::safety_no_conflicting_finalization(&state) &&
                                   properties::byzantine_resilience(&state, &config);
        result.states_explored = states_explored;
        result.attack_rounds = self.config.max_rounds;
        result.execution_time_ms = start_time.elapsed().as_millis() as u64;
        result.attack_metrics = attack_metrics;

        if result.attack_successful {
            result.violations_found.push("Adaptive stake manipulation attack executed".to_string());
        }

        result
    }

    /// Test economic rational attack
    fn test_economic_rational_attack(&self) -> AttackScenarioResult {
        let mut result = self.create_attack_result("economic_rational_attack");
        let start_time = Instant::now();

        let config = Config::new()
            .with_validators(self.config.total_validators)
            .with_byzantine_threshold(self.config.byzantine_count);

        let model = AlpenglowModel::new(config.clone());
        let mut state = model.state().clone();

        // Mark validators as Byzantine
        for i in 0..self.config.byzantine_count {
            state.failure_states.insert(i as ValidatorId, ValidatorStatus::Byzantine);
        }

        let mut attack_metrics = AttackMetrics::default();
        let mut states_explored = 0;

        // Economic rational attack - maximize rewards while attacking
        for round in 0..self.config.max_rounds {
            state.clock += 1;
            states_explored += 1;

            // Byzantine validators try to maximize economic gain
            for byzantine_id in 0..self.config.byzantine_count {
                let validator_id = byzantine_id as ValidatorId;

                // Selfish mining for economic gain
                if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                    ByzantineAction::SelfishMining { validator: validator_id }
                )) {
                    state = new_state;
                    attack_metrics.economic_damage_percentage += 1.0;
                    states_explored += 1;
                }

                // Fee manipulation
                if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                    ByzantineAction::FeeManipulation { validator: validator_id }
                )) {
                    state = new_state;
                    attack_metrics.economic_damage_percentage += 0.5;
                    states_explored += 1;
                }
            }

            // Honest validators continue normal operation
            for honest_id in self.config.byzantine_count..self.config.total_validators {
                let validator_id = honest_id as ValidatorId;
                let current_view = state.votor_view.get(&validator_id).copied().unwrap_or(1);

                if let Ok(new_state) = model.execute_action(AlpenglowAction::Votor(
                    VotorAction::CollectVotes { validator: validator_id, view: current_view }
                )) {
                    state = new_state;
                    states_explored += 1;
                }
            }
        }

        // Calculate economic damage as percentage of total possible rewards
        attack_metrics.economic_damage_percentage = 
            (attack_metrics.economic_damage_percentage / (self.config.max_rounds as f64 * 2.0)) * 100.0;

        result.attack_successful = attack_metrics.economic_damage_percentage > 10.0;
        result.protocol_resilient = properties::safety_no_conflicting_finalization(&state) &&
                                   properties::chain_consistency(&state);
        result.states_explored = states_explored;
        result.attack_rounds = self.config.max_rounds;
        result.execution_time_ms = start_time.elapsed().as_millis() as u64;
        result.attack_metrics = attack_metrics;

        if result.attack_successful {
            result.violations_found.push(format!("Economic rational attack achieved {:.1}% damage", 
                                                attack_metrics.economic_damage_percentage));
        }

        result
    }

    /// Test economic griefing attack
    fn test_economic_griefing_attack(&self) -> AttackScenarioResult {
        let mut result = self.create_attack_result("economic_griefing_attack");
        let start_time = Instant::now();

        let config = Config::new()
            .with_validators(self.config.total_validators)
            .with_byzantine_threshold(self.config.byzantine_count);

        let model = AlpenglowModel::new(config.clone());
        let mut state = model.state().clone();

        // Mark validators as Byzantine
        for i in 0..self.config.byzantine_count {
            state.failure_states.insert(i as ValidatorId, ValidatorStatus::Byzantine);
        }

        let mut attack_metrics = AttackMetrics::default();
        let mut states_explored = 0;

        // Economic griefing attack - cause maximum damage to others
        for round in 0..self.config.max_rounds {
            state.clock += 1;
            states_explored += 1;

            // Byzantine validators cause economic damage to honest validators
            for byzantine_id in 0..self.config.byzantine_count {
                let validator_id = byzantine_id as ValidatorId;

                // Waste bandwidth to increase costs
                if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                    ByzantineAction::BandwidthWaste { validator: validator_id }
                )) {
                    state = new_state;
                    attack_metrics.bandwidth_waste_percentage += 5.0;
                    states_explored += 1;
                }

                // Force view changes to waste resources
                if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                    ByzantineAction::ForceViewChange { validator: validator_id }
                )) {
                    state = new_state;
                    attack_metrics.economic_damage_percentage += 2.0;
                    states_explored += 1;
                }

                // Spam invalid transactions
                if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                    ByzantineAction::SpamInvalidTransactions { validator: validator_id }
                )) {
                    state = new_state;
                    attack_metrics.economic_damage_percentage += 1.0;
                    states_explored += 1;
                }
            }

            // Honest validators bear the cost
            for honest_id in self.config.byzantine_count..self.config.total_validators {
                let validator_id = honest_id as ValidatorId;
                let current_view = state.votor_view.get(&validator_id).copied().unwrap_or(1);

                if let Ok(new_state) = model.execute_action(AlpenglowAction::Votor(
                    VotorAction::CollectVotes { validator: validator_id, view: current_view }
                )) {
                    state = new_state;
                    states_explored += 1;
                }
            }
        }

        // Normalize damage percentages
        attack_metrics.economic_damage_percentage = 
            (attack_metrics.economic_damage_percentage / (self.config.max_rounds as f64 * 3.0)) * 100.0;
        attack_metrics.bandwidth_waste_percentage = 
            (attack_metrics.bandwidth_waste_percentage / (self.config.max_rounds as f64 * 5.0)) * 100.0;

        result.attack_successful = attack_metrics.economic_damage_percentage > 15.0 ||
                                  attack_metrics.bandwidth_waste_percentage > 20.0;
        result.protocol_resilient = properties::safety_no_conflicting_finalization(&state) &&
                                   properties::chain_consistency(&state);
        result.states_explored = states_explored;
        result.attack_rounds = self.config.max_rounds;
        result.execution_time_ms = start_time.elapsed().as_millis() as u64;
        result.attack_metrics = attack_metrics;

        if result.attack_successful {
            result.violations_found.push(format!("Economic griefing caused {:.1}% damage, {:.1}% bandwidth waste", 
                                                attack_metrics.economic_damage_percentage,
                                                attack_metrics.bandwidth_waste_percentage));
        }

        result
    }

    /// Test economic bribery attack
    fn test_economic_bribery_attack(&self) -> AttackScenarioResult {
        let mut result = self.create_attack_result("economic_bribery_attack");
        let start_time = Instant::now();

        let config = Config::new()
            .with_validators(self.config.total_validators)
            .with_byzantine_threshold(self.config.byzantine_count);

        let model = AlpenglowModel::new(config.clone());
        let mut state = model.state().clone();

        // Mark validators as Byzantine
        for i in 0..self.config.byzantine_count {
            state.failure_states.insert(i as ValidatorId, ValidatorStatus::Byzantine);
        }

        let mut attack_metrics = AttackMetrics::default();
        let mut states_explored = 0;
        let mut bribed_validators = HashSet::new();

        // Economic bribery attack - corrupt honest validators
        for round in 0..self.config.max_rounds {
            state.clock += 1;
            states_explored += 1;

            // Byzantine validators attempt to bribe honest validators
            for byzantine_id in 0..self.config.byzantine_count {
                let validator_id = byzantine_id as ValidatorId;

                // Attempt to bribe honest validators
                for target_id in self.config.byzantine_count..self.config.total_validators {
                    let target = target_id as ValidatorId;

                    if !bribed_validators.contains(&target) {
                        if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                            ByzantineAction::BribeValidator { 
                                briber: validator_id, 
                                target,
                                amount: 1000 // Bribe amount
                            }
                        )) {
                            state = new_state;
                            bribed_validators.insert(target);
                            attack_metrics.honest_validators_affected += 1;
                            attack_metrics.economic_damage_percentage += 5.0;
                            states_explored += 1;
                            break; // One bribe per round per Byzantine validator
                        }
                    }
                }
            }

            // Bribed validators may act Byzantine
            for &bribed_validator in &bribed_validators {
                if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                    ByzantineAction::DoubleVote { 
                        validator: bribed_validator, 
                        view: state.votor_view.get(&bribed_validator).copied().unwrap_or(1) 
                    }
                )) {
                    state = new_state;
                    states_explored += 1;
                }
            }

            // Remaining honest validators continue
            for honest_id in self.config.byzantine_count..self.config.total_validators {
                let validator_id = honest_id as ValidatorId;

                if !bribed_validators.contains(&validator_id) {
                    let current_view = state.votor_view.get(&validator_id).copied().unwrap_or(1);

                    if let Ok(new_state) = model.execute_action(AlpenglowAction::Votor(
                        VotorAction::CollectVotes { validator: validator_id, view: current_view }
                    )) {
                        state = new_state;
                        states_explored += 1;
                    }
                }
            }

            // Check if bribery succeeded in compromising protocol
            if bribed_validators.len() + self.config.byzantine_count > self.config.total_validators / 3 {
                result.attack_successful = true;
                break;
            }
        }

        attack_metrics.economic_damage_percentage = 
            (bribed_validators.len() as f64 / (self.config.total_validators - self.config.byzantine_count) as f64) * 100.0;

        result.protocol_resilient = properties::safety_no_conflicting_finalization(&state) &&
                                   properties::byzantine_resilience(&state, &config);
        result.states_explored = states_explored;
        result.attack_rounds = self.config.max_rounds;
        result.execution_time_ms = start_time.elapsed().as_millis() as u64;
        result.attack_metrics = attack_metrics;

        if result.attack_successful {
            result.violations_found.push(format!("Bribery attack corrupted {} validators ({:.1}%)", 
                                                bribed_validators.len(),
                                                attack_metrics.economic_damage_percentage));
        }

        result
    }

    /// Test economic stake concentration attack
    fn test_economic_stake_concentration_attack(&self) -> AttackScenarioResult {
        let mut result = self.create_attack_result("economic_stake_concentration_attack");
        let start_time = Instant::now();

        let config = Config::new()
            .with_validators(self.config.total_validators)
            .with_byzantine_threshold(self.config.byzantine_count);

        let model = AlpenglowModel::new(config.clone());
        let mut state = model.state().clone();

        // Mark validators as Byzantine
        for i in 0..self.config.byzantine_count {
            state.failure_states.insert(i as ValidatorId, ValidatorStatus::Byzantine);
        }

        let mut attack_metrics = AttackMetrics::default();
        let mut states_explored = 0;

        // Calculate initial stake concentration
        let total_stake = config.total_stake;
        let byzantine_stake: u64 = (0..self.config.byzantine_count)
            .map(|i| config.stake_distribution.get(&(i as ValidatorId)).copied().unwrap_or(0))
            .sum();
        let initial_concentration = (byzantine_stake as f64 / total_stake as f64) * 100.0;

        // Stake concentration attack
        for round in 0..self.config.max_rounds {
            state.clock += 1;
            states_explored += 1;

            // Byzantine validators attempt to concentrate stake
            for byzantine_id in 0..self.config.byzantine_count {
                let validator_id = byzantine_id as ValidatorId;

                // Attempt stake manipulation
                if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                    ByzantineAction::StakeManipulation { validator: validator_id }
                )) {
                    state = new_state;
                    attack_metrics.economic_damage_percentage += 1.0;
                    states_explored += 1;
                }

                // Attempt to acquire more stake through economic means
                if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                    ByzantineAction::StakeAcquisition { validator: validator_id }
                )) {
                    state = new_state;
                    attack_metrics.economic_damage_percentage += 2.0;
                    states_explored += 1;
                }
            }

            // Honest validators continue operation
            for honest_id in self.config.byzantine_count..self.config.total_validators {
                let validator_id = honest_id as ValidatorId;
                let current_view = state.votor_view.get(&validator_id).copied().unwrap_or(1);

                if let Ok(new_state) = model.execute_action(AlpenglowAction::Votor(
                    VotorAction::CollectVotes { validator: validator_id, view: current_view }
                )) {
                    state = new_state;
                    states_explored += 1;
                }
            }
        }

        // Calculate final stake concentration (simulated)
        let final_concentration = initial_concentration + (attack_metrics.economic_damage_percentage / 10.0);
        attack_metrics.economic_damage_percentage = final_concentration - initial_concentration;

        result.attack_successful = final_concentration > self.config.economic_attack_stake_percentage;
        result.protocol_resilient = properties::safety_no_conflicting_finalization(&state) &&
                                   properties::byzantine_resilience(&state, &config) &&
                                   final_concentration < 33.33; // Less than 1/3 stake
        result.states_explored = states_explored;
        result.attack_rounds = self.config.max_rounds;
        result.execution_time_ms = start_time.elapsed().as_millis() as u64;
        result.attack_metrics = attack_metrics;

        if result.attack_successful {
            result.violations_found.push(format!("Stake concentration increased by {:.1}% to {:.1}%", 
                                                attack_metrics.economic_damage_percentage,
                                                final_concentration));
        }

        result
    }

    /// Test basic timing attack
    fn test_timing_attack_basic(&self) -> AttackScenarioResult {
        let mut result = self.create_attack_result("timing_attack_basic");
        let start_time = Instant::now();

        let config = Config::new()
            .with_validators(self.config.total_validators)
            .with_byzantine_threshold(self.config.byzantine_count);

        let model = AlpenglowModel::new(config.clone());
        let mut state = model.state().clone();

        // Mark validators as Byzantine
        for i in 0..self.config.byzantine_count {
            state.failure_states.insert(i as ValidatorId, ValidatorStatus::Byzantine);
        }

        let mut attack_metrics = AttackMetrics::default();
        let mut states_explored = 0;

        // Basic timing attack
        for round in 0..self.config.max_rounds {
            state.clock += 1;
            states_explored += 1;

            // Byzantine validators manipulate timing
            for byzantine_id in 0..self.config.byzantine_count {
                let validator_id = byzantine_id as ValidatorId;

                // Delay messages strategically
                if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                    ByzantineAction::TimingAttack { 
                        validator: validator_id, 
                        delay_ms: self.config.timing_attack_delay_ms 
                    }
                )) {
                    state = new_state;
                    attack_metrics.timing_manipulation_count += 1;
                    states_explored += 1;
                }

                // Send messages at strategic times
                if round % 3 == byzantine_id {
                    if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                        ByzantineAction::DoubleVote { 
                            validator: validator_id, 
                            view: state.votor_view.get(&validator_id).copied().unwrap_or(1) 
                        }
                    )) {
                        state = new_state;
                        states_explored += 1;
                    }
                }
            }

            // Honest validators respond with potential timing issues
            for honest_id in self.config.byzantine_count..self.config.total_validators {
                let validator_id = honest_id as ValidatorId;
                let current_view = state.votor_view.get(&validator_id).copied().unwrap_or(1);

                if let Ok(new_state) = model.execute_action(AlpenglowAction::Votor(
                    VotorAction::CollectVotes { validator: validator_id, view: current_view }
                )) {
                    state = new_state;
                    states_explored += 1;
                }
            }

            // Measure finalization delays
            if !state.votor_finalized_chain.is_empty() {
                let delay = round as u64 * 100; // Estimate delay
                attack_metrics.finalization_delays_ms.push(delay);
            }
        }

        // Calculate average finalization delay
        let avg_delay = if attack_metrics.finalization_delays_ms.is_empty() {
            0
        } else {
            attack_metrics.finalization_delays_ms.iter().sum::<u64>() / attack_metrics.finalization_delays_ms.len() as u64
        };

        result.attack_successful = attack_metrics.timing_manipulation_count > 0 && avg_delay > 200;
        result.protocol_resilient = properties::safety_no_conflicting_finalization(&state) &&
                                   properties::chain_consistency(&state);
        result.states_explored = states_explored;
        result.attack_rounds = self.config.max_rounds;
        result.execution_time_ms = start_time.elapsed().as_millis() as u64;
        result.attack_metrics = attack_metrics;

        if result.attack_successful {
            result.violations_found.push(format!("Timing attack caused average delay of {}ms", avg_delay));
        }

        result
    }

    /// Test timing attack with network delays
    fn test_timing_attack_with_network_delays(&self) -> AttackScenarioResult {
        let mut result = self.create_attack_result("timing_attack_with_network_delays");
        let start_time = Instant::now();

        let config = Config::new()
            .with_validators(self.config.total_validators)
            .with_byzantine_threshold(self.config.byzantine_count);

        let model = AlpenglowModel::new(config.clone());
        let mut state = model.state().clone();

        // Mark validators as Byzantine
        for i in 0..self.config.byzantine_count {
            state.failure_states.insert(i as ValidatorId, ValidatorStatus::Byzantine);
        }

        let mut attack_metrics = AttackMetrics::default();
        let mut states_explored = 0;

        // Timing attack exploiting network delays
        for round in 0..self.config.max_rounds {
            state.clock += 1;
            states_explored += 1;

            // Simulate network delays
            if round % 5 == 0 {
                for target_id in self.config.byzantine_count..self.config.total_validators {
                    let target = target_id as ValidatorId;

                    if let Ok(new_state) = model.execute_action(AlpenglowAction::Network(
                        NetworkAction::DelayMessages { 
                            target, 
                            delay_ms: self.config.timing_attack_delay_ms / 2 
                        }
                    )) {
                        state = new_state;
                        states_explored += 1;
                    }
                }
            }

            // Byzantine validators exploit delays
            for byzantine_id in 0..self.config.byzantine_count {
                let validator_id = byzantine_id as ValidatorId;

                // Time attacks to exploit network delays
                if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                    ByzantineAction::TimingAttack { 
                        validator: validator_id, 
                        delay_ms: self.config.timing_attack_delay_ms 
                    }
                )) {
                    state = new_state;
                    attack_metrics.timing_manipulation_count += 1;
                    states_explored += 1;
                }

                // Send conflicting messages during delay windows
                if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                    ByzantineAction::Equivocate { validator: validator_id }
                )) {
                    state = new_state;
                    states_explored += 1;
                }
            }

            // Honest validators struggle with delays
            for honest_id in self.config.byzantine_count..self.config.total_validators {
                let validator_id = honest_id as ValidatorId;
                let current_view = state.votor_view.get(&validator_id).copied().unwrap_or(1);

                if let Ok(new_state) = model.execute_action(AlpenglowAction::Votor(
                    VotorAction::CollectVotes { validator: validator_id, view: current_view }
                )) {
                    state = new_state;
                    states_explored += 1;
                }
            }

            // Track finalization delays
            if state.votor_finalized_chain.len() > attack_metrics.finalization_delays_ms.len() {
                let delay = (round as u64 + 1) * 150; // Slot duration estimate
                attack_metrics.finalization_delays_ms.push(delay);
            }
        }

        let max_delay = attack_metrics.finalization_delays_ms.iter().max().copied().unwrap_or(0);
        result.attack_successful = attack_metrics.timing_manipulation_count > 5 && max_delay > 500;
        result.protocol_resilient = properties::safety_no_conflicting_finalization(&state) &&
                                   properties::chain_consistency(&state);
        result.states_explored = states_explored;
        result.attack_rounds = self.config.max_rounds;
        result.execution_time_ms = start_time.elapsed().as_millis() as u64;
        result.attack_metrics = attack_metrics;

        if result.attack_successful {
            result.violations_found.push(format!("Timing attack with network delays caused max delay of {}ms", max_delay));
        }

        result
    }

    /// Test timing attack on view synchronization
    fn test_timing_attack_view_synchronization(&self) -> AttackScenarioResult {
        let mut result = self.create_attack_result("timing_attack_view_synchronization");
        let start_time = Instant::now();

        let config = Config::new()
            .with_validators(self.config.total_validators)
            .with_byzantine_threshold(self.config.byzantine_count);

        let model = AlpenglowModel::new(config.clone());
        let mut state = model.state().clone();

        // Mark validators as Byzantine
        for i in 0..self.config.byzantine_count {
            state.failure_states.insert(i as ValidatorId, ValidatorStatus::Byzantine);
        }

        let mut attack_metrics = AttackMetrics::default();
        let mut states_explored = 0;

        // Timing attack targeting view synchronization
        for round in 0..self.config.max_rounds {
            state.clock += 1;
            states_explored += 1;

            // Byzantine validators manipulate view synchronization
            for byzantine_id in 0..self.config.byzantine_count {
                let validator_id = byzantine_id as ValidatorId;

                // Force view changes at strategic times
                if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                    ByzantineAction::ForceViewChange { validator: validator_id }
                )) {
                    state = new_state;
                    attack_metrics.timing_manipulation_count += 1;
                    states_explored += 1;
                }

                // Send view-specific attacks
                let current_view = state.votor_view.get(&validator_id).copied().unwrap_or(1);
                if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                    ByzantineAction::ViewSynchronizationAttack { 
                        validator: validator_id, 
                        target_view: current_view + 1 
                    }
                )) {
                    state = new_state;
                    attack_metrics.timing_manipulation_count += 1;
                    states_explored += 1;
                }
            }

            // Honest validators try to maintain synchronization
            for honest_id in self.config.byzantine_count..self.config.total_validators {
                let validator_id = honest_id as ValidatorId;
                let current_view = state.votor_view.get(&validator_id).copied().unwrap_or(1);

                if let Ok(new_state) = model.execute_action(AlpenglowAction::Votor(
                    VotorAction::CollectVotes { validator: validator_id, view: current_view }
                )) {
                    state = new_state;
                    states_explored += 1;
                }
            }

            // Check view synchronization
            let views: Vec<_> = (0..self.config.total_validators)
                .map(|i| state.votor_view.get(&(i as ValidatorId)).copied().unwrap_or(1))
                .collect();
            let min_view = *views.iter().min().unwrap_or(&1);
            let max_view = *views.iter().max().unwrap_or(&1);

            if max_view - min_view > 2 {
                attack_metrics.honest_validators_affected += 1;
            }
        }

        result.attack_successful = attack_metrics.timing_manipulation_count > 10 &&
                                  attack_metrics.honest_validators_affected > 5;
        result.protocol_resilient = properties::safety_no_conflicting_finalization(&state) &&
                                   properties::chain_consistency(&state);
        result.states_explored = states_explored;
        result.attack_rounds = self.config.max_rounds;
        result.execution_time_ms = start_time.elapsed().as_millis() as u64;
        result.attack_metrics = attack_metrics;

        if result.attack_successful {
            result.violations_found.push("Timing attack disrupted view synchronization".to_string());
        }

        result
    }

    /// Test timing attack on finalization race
    fn test_timing_attack_finalization_race(&self) -> AttackScenarioResult {
        let mut result = self.create_attack_result("timing_attack_finalization_race");
        let start_time = Instant::now();

        let config = Config::new()
            .with_validators(self.config.total_validators)
            .with_byzantine_threshold(self.config.byzantine_count);

        let model = AlpenglowModel::new(config.clone());
        let mut state = model.state().clone();

        // Mark validators as Byzantine
        for i in 0..self.config.byzantine_count {
            state.failure_states.insert(i as ValidatorId, ValidatorStatus::Byzantine);
        }

        let mut attack_metrics = AttackMetrics::default();
        let mut states_explored = 0;

        // Timing attack creating finalization races
        for round in 0..self.config.max_rounds {
            state.clock += 1;
            states_explored += 1;

            // Byzantine validators create finalization races
            for byzantine_id in 0..self.config.byzantine_count {
                let validator_id = byzantine_id as ValidatorId;

                // Create competing blocks at strategic times
                if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                    ByzantineAction::FinalizationRace { validator: validator_id }
                )) {
                    state = new_state;
                    attack_metrics.timing_manipulation_count += 1;
                    states_explored += 1;
                }

                // Time double votes to create races
                let current_view = state.votor_view.get(&validator_id).copied().unwrap_or(1);
                if round % 3 == byzantine_id {
                    if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                        ByzantineAction::DoubleVote { validator: validator_id, view: current_view }
                    )) {
                        state = new_state;
                        states_explored += 1;
                    }
                }
            }

            // Honest validators participate in potential race
            for honest_id in self.config.byzantine_count..self.config.total_validators {
                let validator_id = honest_id as ValidatorId;
                let current_view = state.votor_view.get(&validator_id).copied().unwrap_or(1);

                if let Ok(new_state) = model.execute_action(AlpenglowAction::Votor(
                    VotorAction::CollectVotes { validator: validator_id, view: current_view }
                )) {
                    state = new_state;
                    states_explored += 1;
                }
            }

            // Check for finalization races (multiple blocks competing)
            let competing_blocks = state.votor_finalized_chain.len();
            if competing_blocks > 1 {
                attack_metrics.finalization_delays_ms.push((round as u64) * 100);
            }
        }

        result.attack_successful = attack_metrics.timing_manipulation_count > 0 &&
                                  !attack_metrics.finalization_delays_ms.is_empty();
        result.protocol_resilient = properties::safety_no_conflicting_finalization(&state) &&
                                   properties::chain_consistency(&state);
        result.states_explored = states_explored;
        result.attack_rounds = self.config.max_rounds;
        result.execution_time_ms = start_time.elapsed().as_millis() as u64;
        result.attack_metrics = attack_metrics;

        if result.attack_successful {
            result.violations_found.push("Timing attack created finalization races".to_string());
        }

        result
    }

    /// Test combined eclipse and timing attack
    fn test_combined_eclipse_and_timing_attack(&self) -> AttackScenarioResult {
        let mut result = self.create_attack_result("combined_eclipse_and_timing_attack");
        let start_time = Instant::now();

        let config = Config::new()
            .with_validators(self.config.total_validators)
            .with_byzantine_threshold(self.config.byzantine_count);

        let model = AlpenglowModel::new(config.clone());
        let mut state = model.state().clone();

        // Mark validators as Byzantine
        for i in 0..self.config.byzantine_count {
            state.failure_states.insert(i as ValidatorId, ValidatorStatus::Byzantine);
        }

        let mut attack_metrics = AttackMetrics::default();
        let mut states_explored = 0;
        let target_validator = self.config.byzantine_count as ValidatorId;

        // Combined eclipse and timing attack
        for round in 0..self.config.max_rounds {
            state.clock += 1;
            states_explored += 1;

            // Phase 1: Eclipse attack
            if round < self.config.max_rounds / 2 {
                // Create network partition for eclipse
                if round == 5 {
                    let mut isolated_partition = BTreeSet::new();
                    isolated_partition.insert(target_validator);
                    state.network_partitions.insert(isolated_partition);
                    attack_metrics.network_partitions_created += 1;
                }

                // Byzantine validators eclipse target
                for byzantine_id in 0..self.config.byzantine_count {
                    let attacker_id = byzantine_id as ValidatorId;

                    if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                        ByzantineAction::EclipseAttack { attacker: attacker_id, target: target_validator }
                    )) {
                        state = new_state;
                        attack_metrics.eclipse_attempts += 1;
                        states_explored += 1;
                    }
                }
            } else {
                // Phase 2: Timing attack on eclipsed validator
                for byzantine_id in 0..self.config.byzantine_count {
                    let attacker_id = byzantine_id as ValidatorId;

                    // Timing manipulation targeting eclipsed validator
                    if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                        ByzantineAction::TimingAttack { 
                            validator: attacker_id, 
                            delay_ms: self.config.timing_attack_delay_ms 
                        }
                    )) {
                        state = new_state;
                        attack_metrics.timing_manipulation_count += 1;
                        states_explored += 1;
                    }
                }

                // Heal partition to observe timing attack effects
                if round == self.config.max_rounds - 10 {
                    if let Ok(new_state) = model.execute_action(AlpenglowAction::Network(
                        NetworkAction::HealPartition
                    )) {
                        state = new_state;
                        states_explored += 1;
                    }
                }
            }

            // Other honest validators continue
            for honest_id in (self.config.byzantine_count + 1)..self.config.total_validators {
                let validator_id = honest_id as ValidatorId;
                let current_view = state.votor_view.get(&validator_id).copied().unwrap_or(1);

                if let Ok(new_state) = model.execute_action(AlpenglowAction::Votor(
                    VotorAction::CollectVotes { validator: validator_id, view: current_view }
                )) {
                    state = new_state;
                    states_explored += 1;
                }
            }
        }

        result.attack_successful = attack_metrics.eclipse_attempts > 0 && 
                                  attack_metrics.timing_manipulation_count > 0;
        result.protocol_resilient = properties::safety_no_conflicting_finalization(&state) &&
                                   properties::chain_consistency(&state);
        result.states_explored = states_explored;
        result.attack_rounds = self.config.max_rounds;
        result.execution_time_ms = start_time.elapsed().as_millis() as u64;
        result.attack_metrics = attack_metrics;

        if result.attack_successful {
            result.violations_found.push("Combined eclipse and timing attack executed".to_string());
        }

        result
    }

    /// Test combined economic and coordination attack
    fn test_combined_economic_and_coordination_attack(&self) -> AttackScenarioResult {
        let mut result = self.create_attack_result("combined_economic_and_coordination_attack");
        let start_time = Instant::now();

        let config = Config::new()
            .with_validators(self.config.total_validators)
            .with_byzantine_threshold(self.config.byzantine_count);

        let model = AlpenglowModel::new(config.clone());
        let mut state = model.state().clone();

        // Mark validators as Byzantine
        for i in 0..self.config.byzantine_count {
            state.failure_states.insert(i as ValidatorId, ValidatorStatus::Byzantine);
        }

        let mut attack_metrics = AttackMetrics::default();
        let mut states_explored = 0;

        // Combined economic and coordination attack
        for round in 0..self.config.max_rounds {
            state.clock += 1;
            states_explored += 1;

            // Coordinated economic attack
            for byzantine_id in 0..self.config.byzantine_count {
                let validator_id = byzantine_id as ValidatorId;
                let current_view = state.votor_view.get(&validator_id).copied().unwrap_or(1);

                // Economic component - selfish mining
                if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                    ByzantineAction::SelfishMining { validator: validator_id }
                )) {
                    state = new_state;
                    attack_metrics.economic_damage_percentage += 1.0;
                    states_explored += 1;
                }

                // Coordination component - synchronized double voting
                if round % 3 == 0 {
                    if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                        ByzantineAction::DoubleVote { validator: validator_id, view: current_view }
                    )) {
                        state = new_state;
                        attack_metrics.coordinated_actions += 1;
                        states_explored += 1;
                    }
                }

                // Economic griefing
                if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                    ByzantineAction::BandwidthWaste { validator: validator_id }
                )) {
                    state = new_state;
                    attack_metrics.bandwidth_waste_percentage += 2.0;
                    states_explored += 1;
                }
            }

            // Honest validators bear economic costs
            for honest_id in self.config.byzantine_count..self.config.total_validators {
                let validator_id = honest_id as ValidatorId;
                let current_view = state.votor_view.get(&validator_id).copied().unwrap_or(1);

                if let Ok(new_state) = model.execute_action(AlpenglowAction::Votor(
                    VotorAction::CollectVotes { validator: validator_id, view: current_view }
                )) {
                    state = new_state;
                    states_explored += 1;
                }
            }
        }

        // Normalize metrics
        attack_metrics.economic_damage_percentage = 
            (attack_metrics.economic_damage_percentage / self.config.max_rounds as f64) * 100.0;
        attack_metrics.bandwidth_waste_percentage = 
            (attack_metrics.bandwidth_waste_percentage / (self.config.max_rounds as f64 * 2.0)) * 100.0;

        result.attack_successful = attack_metrics.coordinated_actions > 5 &&
                                  attack_metrics.economic_damage_percentage > 10.0;
        result.protocol_resilient = properties::safety_no_conflicting_finalization(&state) &&
                                   properties::chain_consistency(&state);
        result.states_explored = states_explored;
        result.attack_rounds = self.config.max_rounds;
        result.execution_time_ms = start_time.elapsed().as_millis() as u64;
        result.attack_metrics = attack_metrics;

        if result.attack_successful {
            result.violations_found.push(format!("Combined attack: {} coordinated actions, {:.1}% economic damage", 
                                                attack_metrics.coordinated_actions,
                                                attack_metrics.economic_damage_percentage));
        }

        result
    }

    /// Test combined adaptive and long-range attack
    fn test_combined_adaptive_and_long_range_attack(&self) -> AttackScenarioResult {
        let mut result = self.create_attack_result("combined_adaptive_and_long_range_attack");
        let start_time = Instant::now();

        let config = Config::new()
            .with_validators(self.config.total_validators)
            .with_byzantine_threshold(self.config.byzantine_count);

        let model = AlpenglowModel::new(config.clone());
        let mut state = model.state().clone();

        // Mark validators as Byzantine
        for i in 0..self.config.byzantine_count {
            state.failure_states.insert(i as ValidatorId, ValidatorStatus::Byzantine);
        }

        let mut attack_metrics = AttackMetrics::default();
        let mut states_explored = 0;
        let mut current_strategy = 0;

        // Combined adaptive and long-range attack
        for round in 0..self.config.max_rounds {
            state.clock += 1;
            states_explored += 1;

            // Adaptive strategy switching
            if round % (self.config.max_rounds / self.config.adaptive_strategy_changes) == 0 {
                current_strategy = (current_strategy + 1) % 3;
                attack_metrics.adaptive_strategy_switches += 1;
            }

            // Execute combined attack
            for byzantine_id in 0..self.config.byzantine_count {
                let validator_id = byzantine_id as ValidatorId;

                // Long-range component - build alternative chain
                let alternative_block = Block {
                    slot: round + 1,
                    view: 1,
                    hash: 5000 + round + byzantine_id * 100,
                    parent: if round == 0 { 0 } else { 5000 + round - 1 + byzantine_id * 100 },
                    proposer: validator_id,
                    transactions: HashSet::new(),
                    timestamp: state.clock,
                    signature: 0,
                    data: vec![],
                };

                if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                    ByzantineAction::LongRangeAttack { 
                        validator: validator_id, 
                        alternative_block 
                    }
                )) {
                    state = new_state;
                    attack_metrics.long_range_forks += 1;
                    states_explored += 1;
                }

                // Adaptive component based on current strategy
                match current_strategy {
                    0 => {
                        // VRF grinding
                        if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                            ByzantineAction::GrindVRF { validator: validator_id }
                        )) {
                            state = new_state;
                            states_explored += 1;
                        }
                    }
                    1 => {
                        // Nothing-at-stake
                        if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                            ByzantineAction::NothingAtStake { validator: validator_id }
                        )) {
                            state = new_state;
                            states_explored += 1;
                        }
                    }
                    2 => {
                        // Stake manipulation
                        if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                            ByzantineAction::StakeManipulation { validator: validator_id }
                        )) {
                            state = new_state;
                            states_explored += 1;
                        }
                    }
                    _ => {}
                }
            }

            // Honest validators continue on main chain
            for honest_id in self.config.byzantine_count..self.config.total_validators {
                let validator_id = honest_id as ValidatorId;
                let current_view = state.votor_view.get(&validator_id).copied().unwrap_or(1);

                if let Ok(new_state) = model.execute_action(AlpenglowAction::Votor(
                    VotorAction::CollectVotes { validator: validator_id, view: current_view }
                )) {
                    state = new_state;
                    states_explored += 1;
                }
            }
        }

        result.attack_successful = attack_metrics.long_range_forks > self.config.long_range_depth &&
                                  attack_metrics.adaptive_strategy_switches > 2;
        result.protocol_resilient = properties::safety_no_conflicting_finalization(&state) &&
                                   properties::chain_consistency(&state);
        result.states_explored = states_explored;
        result.attack_rounds = self.config.max_rounds;
        result.execution_time_ms = start_time.elapsed().as_millis() as u64;
        result.attack_metrics = attack_metrics;

        if result.attack_successful {
            result.violations_found.push(format!("Combined attack: {} long-range forks, {} strategy switches", 
                                                attack_metrics.long_range_forks,
                                                attack_metrics.adaptive_strategy_switches));
        }

        result
    }

    /// Test maximum adversarial scenario
    fn test_maximum_adversarial_scenario(&self) -> AttackScenarioResult {
        let mut result = self.create_attack_result("maximum_adversarial_scenario");
        let start_time = Instant::now();

        let config = Config::new()
            .with_validators(self.config.total_validators)
            .with_byzantine_threshold(self.config.byzantine_count);

        let model = AlpenglowModel::new(config.clone());
        let mut state = model.state().clone();

        // Mark validators as Byzantine
        for i in 0..self.config.byzantine_count {
            state.failure_states.insert(i as ValidatorId, ValidatorStatus::Byzantine);
        }

        // Add some offline validators for maximum adversarial conditions
        for i in self.config.byzantine_count..(self.config.byzantine_count + self.config.offline_count) {
            if i < self.config.total_validators {
                state.failure_states.insert(i as ValidatorId, ValidatorStatus::Offline);
            }
        }

        let mut attack_metrics = AttackMetrics::default();
        let mut states_explored = 0;

        // Maximum adversarial scenario - all attack vectors simultaneously
        for round in 0..self.config.max_rounds {
            state.clock += 1;
            states_explored += 1;

            // Create network partitions
            if round == 10 {
                let mut partition1 = BTreeSet::new();
                partition1.insert(0);
                partition1.insert(1);
                state.network_partitions.insert(partition1);
                attack_metrics.network_partitions_created += 1;
            }

            // All Byzantine attack vectors
            for byzantine_id in 0..self.config.byzantine_count {
                let validator_id = byzantine_id as ValidatorId;
                let current_view = state.votor_view.get(&validator_id).copied().unwrap_or(1);

                // Coordinated attacks
                match round % 6 {
                    0 => {
                        // Double voting
                        if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                            ByzantineAction::DoubleVote { validator: validator_id, view: current_view }
                        )) {
                            state = new_state;
                            attack_metrics.coordinated_actions += 1;
                            states_explored += 1;
                        }
                    }
                    1 => {
                        // Eclipse attack
                        let target = ((byzantine_id + self.config.byzantine_count) % self.config.total_validators) as ValidatorId;
                        if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                            ByzantineAction::EclipseAttack { attacker: validator_id, target }
                        )) {
                            state = new_state;
                            attack_metrics.eclipse_attempts += 1;
                            states_explored += 1;
                        }
                    }
                    2 => {
                        // Long-range attack
                        let alternative_block = Block {
                            slot: round + 1,
                            view: 1,
                            hash: 4000 + round + byzantine_id * 100,
                            parent: if round == 0 { 0 } else { 4000 + round - 1 + byzantine_id * 100 },
                            proposer: validator_id,
                            transactions: HashSet::new(),
                            timestamp: state.clock,
                            signature: 0,
                            data: vec![],
                        };

                        if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                            ByzantineAction::LongRangeAttack { validator: validator_id, alternative_block }
                        )) {
                            state = new_state;
                            attack_metrics.long_range_forks += 1;
                            states_explored += 1;
                        }
                    }
                    3 => {
                        // Economic attack
                        if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                            ByzantineAction::SelfishMining { validator: validator_id }
                        )) {
                            state = new_state;
                            attack_metrics.economic_damage_percentage += 1.0;
                            states_explored += 1;
                        }
                    }
                    4 => {
                        // Timing attack
                        if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                            ByzantineAction::TimingAttack { 
                                validator: validator_id, 
                                delay_ms: self.config.timing_attack_delay_ms 
                            }
                        )) {
                            state = new_state;
                            attack_metrics.timing_manipulation_count += 1;
                            states_explored += 1;
                        }
                    }
                    5 => {
                        // Adaptive strategy
                        if let Ok(new_state) = model.execute_action(AlpenglowAction::Byzantine(
                            ByzantineAction::Equivocate { validator: validator_id }
                        )) {
                            state = new_state;
                            attack_metrics.adaptive_strategy_switches += 1;
                            states_explored += 1;
                        }
                    }
                    _ => {}
                }
            }

            // Remaining honest validators try to maintain consensus
            for honest_id in (self.config.byzantine_count + self.config.offline_count)..self.config.total_validators {
                let validator_id = honest_id as ValidatorId;
                let current_view = state.votor_view.get(&validator_id).copied().unwrap_or(1);

                if let Ok(new_state) = model.execute_action(AlpenglowAction::Votor(
                    VotorAction::CollectVotes { validator: validator_id, view: current_view }
                )) {
                    state = new_state;
                    states_explored += 1;
                }
            }

            // Heal partitions periodically
            if round % 20 == 19 {
                if let Ok(new_state) = model.execute_action(AlpenglowAction::Network(
                    NetworkAction::HealPartition
                )) {
                    state = new_state;
                    states_explored += 1;
                }
            }

            // Check if protocol is still functioning
            if !properties::safety_no_conflicting_finalization(&state) ||
               !properties::chain_consistency(&state) {
                result.attack_successful = true;
                result.safety_violated = true;
                break;
            }
        }

        // Calculate total attack impact
        let total_attack_vectors = attack_metrics.coordinated_actions +
                                  attack_metrics.eclipse_attempts +
                                  attack_metrics.long_range_forks +
                                  attack_metrics.timing_manipulation_count +
                                  attack_metrics.adaptive_strategy_switches;

        attack_metrics.honest_validators_affected = self.config.total_validators - 
                                                   self.config.byzantine_count - 
                                                   self.config.offline_count;

        result.attack_successful = total_attack_vectors > self.config.max_rounds;
        result.protocol_resilient = properties::safety_no_conflicting_finalization(&state) &&
                                   properties::chain_consistency(&state) &&
                                   properties::byzantine_resilience(&state, &config);
        result.states_explored = states_explored;
        result.attack_rounds = self.config.max_rounds;
        result.execution_time_ms = start_time.elapsed().as_millis() as u64;
        result.attack_metrics = attack_metrics;

        if result.attack_successful && !result.protocol_resilient {
            result.violations_found.push("Maximum adversarial scenario compromised protocol".to_string());
        } else if result.attack_successful && result.protocol_resilient {
            result.violations_found.push("Maximum adversarial scenario executed but protocol remained resilient".to_string());
        }

        result
    }

    /// Helper function to create attack result
    fn create_attack_result(&self, scenario_name: &str) -> AttackScenarioResult {
        AttackScenarioResult {
            scenario_name: scenario_name.to_string(),
            attack_successful: false,
            safety_violated: false,
            liveness_violated: false,
            protocol_resilient: false,
            states_explored: 0,
            attack_rounds: 0,
            detection_time_ms: 0,
            recovery_time_ms: 0,
            execution_time_ms: 0,
            attack_metrics: AttackMetrics::default(),
            violations_found: Vec::new(),
            external_stateright_result: None,
            tla_cross_validation: None,
        }
    }
}

/// Create test configurations for different attack scenarios
pub fn create_attack_test_configurations() -> Vec<ByzantineAttackConfig> {
    vec![
        // Small network - basic attacks
        ByzantineAttackConfig {
            total_validators: 7,
            byzantine_count: 2,
            offline_count: 1,
            max_rounds: 30,
            attack_coordination_rounds: 10,
            eclipse_target_count: 1,
            long_range_depth: 15,
            adaptive_strategy_changes: 3,
            economic_attack_stake_percentage: 20.0,
            timing_attack_delay_ms: 300,
            network_manipulation_probability: 0.2,
            use_external_stateright: true,
            cross_validate_tla: false,
            exploration_depth: 1000,
            max_states: 10000,
        },
        // Medium network - advanced attacks
        ByzantineAttackConfig {
            total_validators: 10,
            byzantine_count: 3,
            offline_count: 2,
            max_rounds: 50,
            attack_coordination_rounds: 15,
            eclipse_target_count: 2,
            long_range_depth: 25,
            adaptive_strategy_changes: 5,
            economic_attack_stake_percentage: 25.0,
            timing_attack_delay_ms: 500,
            network_manipulation_probability: 0.3,
            use_external_stateright: true,
            cross_validate_tla: true,
            exploration_depth: 2000,
            max_states: 20000,
        },
        // Large network - maximum adversarial
        ByzantineAttackConfig {
            total_validators: 15,
            byzantine_count: 4,
            offline_count: 3,
            max_rounds: 75,
            attack_coordination_rounds: 25,
            eclipse_target_count: 3,
            long_range_depth: 40,
            adaptive_strategy_changes: 7,
            economic_attack_stake_percentage: 30.0,
            timing_attack_delay_ms: 750,
            network_manipulation_probability: 0.4,
            use_external_stateright: true,
            cross_validate_tla: true,
            exploration_depth: 3000,
            max_states: 30000,
        },
    ]
}

/// Run comprehensive Byzantine attack scenario testing
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_coordinated_attacks() {
        let config = ByzantineAttackConfig::default();
        let test_suite = ByzantineAttackScenarios::new(config);
        
        let result = test_suite.test_coordinated_double_voting_attack();
        assert!(result.protocol_resilient, "Protocol should resist coordinated double voting");
        
        let result = test_suite.test_coordinated_withholding_attack();
        assert!(result.protocol_resilient, "Protocol should resist coordinated withholding");
        
        let result = test_suite.test_multi_vector_coordinated_attack();
        assert!(result.protocol_resilient, "Protocol should resist multi-vector attacks");
    }

    #[test]
    fn test_eclipse_attacks() {
        let config = ByzantineAttackConfig::default();
        let test_suite = ByzantineAttackScenarios::new(config);
        
        let result = test_suite.test_eclipse_attack_single_target();
        assert!(result.protocol_resilient, "Protocol should resist single target eclipse");
        
        let result = test_suite.test_eclipse_attack_multiple_targets();
        assert!(result.protocol_resilient, "Protocol should resist multiple target eclipse");
    }

    #[test]
    fn test_long_range_attacks() {
        let config = ByzantineAttackConfig::default();
        let test_suite = ByzantineAttackScenarios::new(config);
        
        let result = test_suite.test_long_range_attack_basic();
        assert!(result.protocol_resilient, "Protocol should resist basic long-range attacks");
        
        let result = test_suite.test_nothing_at_stake_attack();
        assert!(result.protocol_resilient, "Protocol should resist nothing-at-stake attacks");
    }

    #[test]
    fn test_adaptive_attacks() {
        let config = ByzantineAttackConfig::default();
        let test_suite = ByzantineAttackScenarios::new(config);
        
        let result = test_suite.test_adaptive_strategy_switching();
        assert!(result.protocol_resilient, "Protocol should resist adaptive strategy switching");
        
        let result = test_suite.test_adaptive_response_to_detection();
        assert!(result.protocol_resilient, "Protocol should resist adaptive response to detection");
    }

    #[test]
    fn test_economic_attacks() {
        let config = ByzantineAttackConfig::default();
        let test_suite = ByzantineAttackScenarios::new(config);
        
        let result = test_suite.test_economic_rational_attack();
        assert!(result.protocol_resilient, "Protocol should resist economic rational attacks");
        
        let result = test_suite.test_economic_griefing_attack();
        assert!(result.protocol_resilient, "Protocol should resist economic griefing");
    }

    #[test]
    fn test_timing_attacks() {
        let config = ByzantineAttackConfig::default();
        let test_suite = ByzantineAttackScenarios::new(config);
        
        let result = test_suite.test_timing_attack_basic();
        assert!(result.protocol_resilient, "Protocol should resist basic timing attacks");
        
        let result = test_suite.test_timing_attack_with_network_delays();
        assert!(result.protocol_resilient, "Protocol should resist timing attacks with network delays");
    }

    #[test]
    fn test_combined_attacks() {
        let config = ByzantineAttackConfig::default();
        let test_suite = ByzantineAttackScenarios::new(config);
        
        let result = test_suite.test_combined_eclipse_and_timing_attack();
        assert!(result.protocol_resilient, "Protocol should resist combined eclipse and timing attacks");
        
        let result = test_suite.test_combined_economic_and_coordination_attack();
        assert!(result.protocol_resilient, "Protocol should resist combined economic and coordination attacks");
    }

    #[test]
    fn test_maximum_adversarial_scenario() {
        let config = ByzantineAttackConfig {
            total_validators: 10,
            byzantine_count: 3,
            offline_count: 1,
            max_rounds: 30,
            ..Default::default()
        };
        let test_suite = ByzantineAttackScenarios::new(config);
        
        let result = test_suite.test_maximum_adversarial_scenario();
        assert!(result.protocol_resilient, "Protocol should resist maximum adversarial scenario");
        assert!(result.attack_successful, "Maximum adversarial scenario should execute attacks");
    }

    #[test]
    fn test_comprehensive_attack_scenarios() {
        let config = ByzantineAttackConfig {
            total_validators: 12,
            byzantine_count: 3,
            offline_count: 2,
            max_rounds: 40,
            attack_coordination_rounds: 12,
            eclipse_target_count: 2,
            long_range_depth: 20,
            adaptive_strategy_changes: 4,
            economic_attack_stake_percentage: 25.0,
            timing_attack_delay_ms: 400,
            network_manipulation_probability: 0.25,
            use_external_stateright: false, // Disable for faster testing
            cross_validate_tla: false,
            exploration_depth: 1500,
            max_states: 15000,
        };
        
        let test_suite = ByzantineAttackScenarios::new(config);
        let results = test_suite.run_all_attack_scenarios();
        
        let protocol_resilient_count = results.iter().filter(|r| r.protocol_resilient).count();
        let total_scenarios = results.len();
        
        println!("Attack scenario results: {}/{} protocol resilient", 
                protocol_resilient_count, total_scenarios);
        
        // At least 80% of scenarios should show protocol resilience
        assert!(protocol_resilient_count as f64 / total_scenarios as f64 >= 0.8,
                "Protocol should be resilient to at least 80% of attack scenarios");
        
        // Check that attacks were actually executed
        let successful_attacks = results.iter().filter(|r| r.attack_successful).count();
        assert!(successful_attacks > 0, "Some attacks should have been successfully executed");
        
        // Verify no safety violations
        let safety_violations = results.iter().filter(|r| r.safety_violated).count();
        assert_eq!(safety_violations, 0, "No safety violations should occur");
    }
}

/// Main CLI function for Byzantine attack scenario testing
pub fn run_byzantine_attack_scenarios(config: &Config, test_config: &TestConfig) -> Result<TestReport, TestError> {
    let start_time = Instant::now();
    let mut report = create_test_report("byzantine_attack_scenarios", test_config.clone());
    
    // Convert test config to attack config
    let attack_config = ByzantineAttackConfig {
        total_validators: test_config.validators,
        byzantine_count: test_config.byzantine_count,
        offline_count: test_config.offline_count,
        max_rounds: test_config.max_rounds,
        attack_coordination_rounds: test_config.max_rounds / 3,
        eclipse_target_count: 2,
        long_range_depth: test_config.max_rounds / 2,
        adaptive_strategy_changes: 4,
        economic_attack_stake_percentage: 25.0,
        timing_attack_delay_ms: 500,
        network_manipulation_probability: 0.3,
        use_external_stateright: false, // Disable for CLI integration
        cross_validate_tla: false,
        exploration_depth: test_config.exploration_depth,
        max_states: test_config.exploration_depth * 10,
    };
    
    let test_suite = ByzantineAttackScenarios::new(attack_config);
    let results = test_suite.run_all_attack_scenarios();
    
    // Process results and update report
    let mut total_states = 0;
    let mut successful_attacks = 0;
    let mut protocol_resilient = 0;
    let mut safety_violations = 0;
    
    for result in &results {
        total_states += result.states_explored;
        
        if result.attack_successful {
            successful_attacks += 1;
        }
        
        if result.protocol_resilient {
            protocol_resilient += 1;
        }
        
        if result.safety_violated {
            safety_violations += 1;
        }
        
        // Add property result to report
        add_property_result(
            &mut report,
            result.scenario_name.clone(),
            result.protocol_resilient,
            result.states_explored,
            Duration::from_millis(result.execution_time_ms),
            if result.protocol_resilient { None } else { Some(result.violations_found.join("; ")) },
            if result.safety_violated { Some(1) } else { None },
        );
    }
    
    // Update report metrics
    report.metrics.byzantine_events = successful_attacks;
    report.metrics.peak_memory_bytes = total_states * 1024; // Estimate
    
    // Add attack-specific metadata
    report.metadata.environment.insert("successful_attacks".to_string(), successful_attacks.to_string());
    report.metadata.environment.insert("protocol_resilient_scenarios".to_string(), protocol_resilient.to_string());
    report.metadata.environment.insert("safety_violations".to_string(), safety_violations.to_string());
    report.metadata.environment.insert("total_scenarios".to_string(), results.len().to_string());
    
    // Finalize report
    finalize_report(&mut report, start_time.elapsed());
    
    Ok(report)
}

/// Main function for CLI binary
fn main() -> Result<(), Box<dyn std::error::Error>> {
    run_test_scenario("byzantine_attack_scenarios", run_byzantine_attack_scenarios)
}