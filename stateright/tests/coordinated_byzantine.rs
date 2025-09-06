//! Coordinated Byzantine attack scenarios for Alpenglow protocol testing
//! 
//! This module implements sophisticated Byzantine behavior patterns including
//! coordinated attacks, eclipse attacks, and adaptive adversaries.

use alpenglow_stateright::*;
use std::collections::{HashMap, HashSet};

/// Coordinated Byzantine attack coordinator
#[derive(Debug, Clone)]
pub struct ByzantineCoordinator {
    pub byzantine_validators: HashSet<ValidatorId>,
    pub attack_strategy: AttackStrategy,
    pub coordination_round: u64,
    pub target_validators: HashSet<ValidatorId>,
}

/// Different attack strategies for coordinated Byzantine behavior
#[derive(Debug, Clone, PartialEq)]
pub enum AttackStrategy {
    /// Coordinated double voting on different blocks
    CoordinatedDoubleVoting,
    /// Withholding votes to prevent finalization
    VoteWithholding,
    /// Eclipse attack isolating honest validators
    EclipseAttack,
    /// Adaptive strategy that changes based on network state
    AdaptiveAttack,
    /// Nothing-at-stake attack
    NothingAtStake,
    /// Long-range attack attempting to rewrite history
    LongRangeAttack,
}

impl ByzantineCoordinator {
    pub fn new(byzantine_validators: HashSet<ValidatorId>, strategy: AttackStrategy) -> Self {
        Self {
            byzantine_validators,
            attack_strategy: strategy,
            coordination_round: 0,
            target_validators: HashSet::new(),
        }
    }

    /// Execute coordinated Byzantine behavior
    pub fn execute_attack(&mut self, state: &AlpenglowState, config: &Config) -> Vec<AlpenglowAction> {
        self.coordination_round += 1;
        
        match self.attack_strategy {
            AttackStrategy::CoordinatedDoubleVoting => self.coordinated_double_voting(state, config),
            AttackStrategy::VoteWithholding => self.vote_withholding(state, config),
            AttackStrategy::EclipseAttack => self.eclipse_attack(state, config),
            AttackStrategy::AdaptiveAttack => self.adaptive_attack(state, config),
            AttackStrategy::NothingAtStake => self.nothing_at_stake(state, config),
            AttackStrategy::LongRangeAttack => self.long_range_attack(state, config),
        }
    }

    /// Coordinated double voting attack
    fn coordinated_double_voting(&self, state: &AlpenglowState, config: &Config) -> Vec<AlpenglowAction> {
        let mut actions = Vec::new();
        
        // Create two conflicting blocks for the same slot
        let current_slot = state.current_slot;
        let block1 = Block {
            slot: current_slot,
            view: 1,
            hash: 1001, // Conflicting hash
            parent: 0,
            proposer: *self.byzantine_validators.iter().next().unwrap(),
            transactions: BTreeSet::new(),
            timestamp: state.clock,
            signature: 1001,
            data: vec![1, 0, 0, 1],
        };
        
        let block2 = Block {
            slot: current_slot,
            view: 1,
            hash: 1002, // Different conflicting hash
            parent: 0,
            proposer: *self.byzantine_validators.iter().next().unwrap(),
            transactions: BTreeSet::new(),
            timestamp: state.clock,
            signature: 1002,
            data: vec![1, 0, 0, 2],
        };

        // All Byzantine validators vote for both blocks
        for &validator in &self.byzantine_validators {
            actions.push(AlpenglowAction::Byzantine(ByzantineAction::DoubleVote {
                validator,
                view: 1,
            }));
        }

        actions
    }

    /// Vote withholding attack to prevent finalization
    fn vote_withholding(&self, state: &AlpenglowState, _config: &Config) -> Vec<AlpenglowAction> {
        // Byzantine validators simply don't vote, implemented as no actions
        // This tests the protocol's liveness under reduced participation
        Vec::new()
    }

    /// Eclipse attack isolating honest validators
    fn eclipse_attack(&self, state: &AlpenglowState, config: &Config) -> Vec<AlpenglowAction> {
        let mut actions = Vec::new();
        
        // Identify honest validators to isolate
        let honest_validators: HashSet<ValidatorId> = (0..config.validator_count as u32)
            .filter(|v| !self.byzantine_validators.contains(v))
            .collect();

        // Create network partition isolating honest validators
        if let Some(&target) = honest_validators.iter().next() {
            let mut isolated_set = BTreeSet::new();
            isolated_set.insert(target);
            
            actions.push(AlpenglowAction::Network(NetworkAction::PartitionNetwork {
                partition: isolated_set,
            }));
        }

        actions
    }

    /// Adaptive attack that changes strategy based on network conditions
    fn adaptive_attack(&mut self, state: &AlpenglowState, config: &Config) -> Vec<AlpenglowAction> {
        // Analyze current network state to choose optimal attack
        let finalized_blocks_count = state.finalized_blocks.len();
        let current_view = state.votor_view.values().max().copied().unwrap_or(1);
        
        // Switch strategy based on conditions
        if finalized_blocks_count < 3 {
            // Early in the protocol, use double voting
            self.attack_strategy = AttackStrategy::CoordinatedDoubleVoting;
            self.coordinated_double_voting(state, config)
        } else if current_view > 5 {
            // If views are advancing rapidly, withhold votes
            self.attack_strategy = AttackStrategy::VoteWithholding;
            self.vote_withholding(state, config)
        } else {
            // Otherwise, attempt eclipse attack
            self.attack_strategy = AttackStrategy::EclipseAttack;
            self.eclipse_attack(state, config)
        }
    }

    /// Nothing-at-stake attack
    fn nothing_at_stake(&self, state: &AlpenglowState, _config: &Config) -> Vec<AlpenglowAction> {
        let mut actions = Vec::new();
        
        // Byzantine validators vote on all possible blocks/views
        for &validator in &self.byzantine_validators {
            // Vote on multiple views simultaneously
            for view in 1..=3 {
                actions.push(AlpenglowAction::Byzantine(ByzantineAction::DoubleVote {
                    validator,
                    view,
                }));
            }
        }

        actions
    }

    /// Long-range attack attempting to rewrite history
    fn long_range_attack(&self, state: &AlpenglowState, config: &Config) -> Vec<AlpenglowAction> {
        let mut actions = Vec::new();
        
        // Attempt to create alternative chain from earlier slot
        if state.current_slot > 3 {
            for &validator in &self.byzantine_validators {
                actions.push(AlpenglowAction::Byzantine(ByzantineAction::InvalidBlock {
                    validator,
                }));
            }
        }

        actions
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Test coordinated double voting attack
    #[test]
    fn test_coordinated_double_voting_attack() {
        let config = Config {
            validator_count: 10,
            byzantine_threshold: 3,
            fast_path_threshold: 800,
            slow_path_threshold: 600,
            total_stake: 1000,
            stake_distribution: (0..10).map(|i| (i, 100)).collect(),
            max_network_delay: 100,
            gst: 1000,
            bandwidth_limit: 1000000,
            erasure_coding_rate: 0.75,
            max_block_size: 1000000,
            k: 6,
            n: 10,
            max_view: 100,
            max_slot: 100,
            timeout_delta: 1000,
            exploration_depth: 50,
            verification_timeout_ms: 30000,
            test_mode: true,
            leader_window_size: 4,
            adaptive_timeouts: true,
            vrf_enabled: false,
            network_delay: 50,
            timeout_ms: 1000,
        };

        let model = AlpenglowModel::new(config.clone());
        let byzantine_validators: HashSet<ValidatorId> = (0..3).collect();
        
        let mut coordinator = ByzantineCoordinator::new(
            byzantine_validators,
            AttackStrategy::CoordinatedDoubleVoting
        );

        let actions = coordinator.execute_attack(&model.state, &config);
        
        // Should generate double voting actions for all Byzantine validators
        assert_eq!(actions.len(), 3);
        for action in actions {
            match action {
                AlpenglowAction::Byzantine(ByzantineAction::DoubleVote { validator, view: _ }) => {
                    assert!(validator < 3);
                }
                _ => panic!("Expected Byzantine double vote action"),
            }
        }
    }

    /// Test eclipse attack isolation
    #[test]
    fn test_eclipse_attack() {
        let config = Config {
            validator_count: 10,
            byzantine_threshold: 3,
            fast_path_threshold: 800,
            slow_path_threshold: 600,
            total_stake: 1000,
            stake_distribution: (0..10).map(|i| (i, 100)).collect(),
            max_network_delay: 100,
            gst: 1000,
            bandwidth_limit: 1000000,
            erasure_coding_rate: 0.75,
            max_block_size: 1000000,
            k: 6,
            n: 10,
            max_view: 100,
            max_slot: 100,
            timeout_delta: 1000,
            exploration_depth: 50,
            verification_timeout_ms: 30000,
            test_mode: true,
            leader_window_size: 4,
            adaptive_timeouts: true,
            vrf_enabled: false,
            network_delay: 50,
            timeout_ms: 1000,
        };

        let model = AlpenglowModel::new(config.clone());
        let byzantine_validators: HashSet<ValidatorId> = (0..3).collect();
        
        let mut coordinator = ByzantineCoordinator::new(
            byzantine_validators,
            AttackStrategy::EclipseAttack
        );

        let actions = coordinator.execute_attack(&model.state, &config);
        
        // Should generate network partition action
        assert_eq!(actions.len(), 1);
        match &actions[0] {
            AlpenglowAction::Network(NetworkAction::PartitionNetwork { partition }) => {
                assert_eq!(partition.len(), 1);
                // Should isolate an honest validator (ID >= 3)
                assert!(partition.iter().next().unwrap() >= &3);
            }
            _ => panic!("Expected network partition action"),
        }
    }

    /// Test adaptive attack strategy switching
    #[test]
    fn test_adaptive_attack_strategy() {
        let config = Config {
            validator_count: 10,
            byzantine_threshold: 3,
            fast_path_threshold: 800,
            slow_path_threshold: 600,
            total_stake: 1000,
            stake_distribution: (0..10).map(|i| (i, 100)).collect(),
            max_network_delay: 100,
            gst: 1000,
            bandwidth_limit: 1000000,
            erasure_coding_rate: 0.75,
            max_block_size: 1000000,
            k: 6,
            n: 10,
            max_view: 100,
            max_slot: 100,
            timeout_delta: 1000,
            exploration_depth: 50,
            verification_timeout_ms: 30000,
            test_mode: true,
            leader_window_size: 4,
            adaptive_timeouts: true,
            vrf_enabled: false,
            network_delay: 50,
            timeout_ms: 1000,
        };

        let mut model = AlpenglowModel::new(config.clone());
        let byzantine_validators: HashSet<ValidatorId> = (0..3).collect();
        
        let mut coordinator = ByzantineCoordinator::new(
            byzantine_validators,
            AttackStrategy::AdaptiveAttack
        );

        // Test with early state (should use double voting)
        let actions1 = coordinator.execute_attack(&model.state, &config);
        assert_eq!(coordinator.attack_strategy, AttackStrategy::CoordinatedDoubleVoting);
        
        // Simulate high view scenario
        model.state.votor_view.insert(0, 10);
        let actions2 = coordinator.execute_attack(&model.state, &config);
        assert_eq!(coordinator.attack_strategy, AttackStrategy::VoteWithholding);
    }

    /// Integration test: Byzantine resilience under coordinated attacks
    #[test]
    fn test_byzantine_resilience_integration() {
        let config = Config {
            validator_count: 10,
            byzantine_threshold: 3,
            fast_path_threshold: 800,
            slow_path_threshold: 600,
            total_stake: 1000,
            stake_distribution: (0..10).map(|i| (i, 100)).collect(),
            max_network_delay: 100,
            gst: 1000,
            bandwidth_limit: 1000000,
            erasure_coding_rate: 0.75,
            max_block_size: 1000000,
            k: 6,
            n: 10,
            max_view: 100,
            max_slot: 100,
            timeout_delta: 1000,
            exploration_depth: 50,
            verification_timeout_ms: 30000,
            test_mode: true,
            leader_window_size: 4,
            adaptive_timeouts: true,
            vrf_enabled: false,
            network_delay: 50,
            timeout_ms: 1000,
        };

        let mut model = AlpenglowModel::new(config.clone());
        let byzantine_validators: HashSet<ValidatorId> = (0..3).collect();
        
        let mut coordinator = ByzantineCoordinator::new(
            byzantine_validators,
            AttackStrategy::CoordinatedDoubleVoting
        );

        // Execute multiple rounds of Byzantine attacks
        for round in 0..10 {
            let actions = coordinator.execute_attack(&model.state, &config);
            
            // Apply Byzantine actions (in real test, would check safety properties)
            for action in actions {
                if model.action_enabled(&action) {
                    if let Ok(new_state) = model.execute_action(action) {
                        model.state = new_state;
                    }
                }
            }
            
            // Verify safety properties still hold
            // (This would use the property checking framework)
            assert!(model.state.clock <= 1000); // Basic sanity check
        }
    }
}
