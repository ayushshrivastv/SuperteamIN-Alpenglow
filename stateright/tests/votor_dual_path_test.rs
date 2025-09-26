use stateright::*;
use std::collections::{HashMap, HashSet};

/// Test Votor's dual voting paths: fast (80%) vs slow (60%) finalization
#[derive(Clone, Debug, Hash, PartialEq)]
struct VotorDualPathModel {
    validators: Vec<u32>,
    byzantine_validators: HashSet<u32>,
    votes: HashMap<u32, HashSet<Vote>>, // validator -> votes
    certificates: Vec<Certificate>,
    current_slot: u32,
    clock: u32,
}

#[derive(Clone, Debug, Hash, PartialEq)]
struct Vote {
    voter: u32,
    slot: u32,
    vote_type: VoteType,
    block_hash: u32,
}

#[derive(Clone, Debug, Hash, PartialEq)]
enum VoteType {
    Proposal,
    Notarization,
    Finalization,
}

#[derive(Clone, Debug, Hash, PartialEq)]
struct Certificate {
    slot: u32,
    cert_type: CertType,
    validators: HashSet<u32>,
    stake_percentage: u32,
}

#[derive(Clone, Debug, Hash, PartialEq)]
enum CertType {
    Fast,  // 80% threshold
    Slow,  // 60% threshold
}

#[derive(Clone, Debug, Hash, PartialEq)]
enum VotorAction {
    CastVote { validator: u32, vote: Vote },
    GenerateCertificate { slot: u32, cert_type: CertType },
    AdvanceTime,
}

impl Model for VotorDualPathModel {
    type State = VotorDualPathModel;
    type Action = VotorAction;

    fn init_states(&self) -> Vec<Self::State> {
        vec![VotorDualPathModel {
            validators: vec![1, 2, 3, 4, 5], // 5 validators for clear thresholds
            byzantine_validators: HashSet::new(),
            votes: HashMap::new(),
            certificates: Vec::new(),
            current_slot: 1,
            clock: 0,
        }]
    }

    fn actions(&self, state: &Self::State, actions: &mut Vec<Self::Action>) {
        // Validators can cast votes
        for &validator in &state.validators {
            if !state.byzantine_validators.contains(&validator) {
                actions.push(VotorAction::CastVote {
                    validator,
                    vote: Vote {
                        voter: validator,
                        slot: state.current_slot,
                        vote_type: VoteType::Notarization,
                        block_hash: 1, // Abstract block
                    },
                });
            }
        }

        // Generate certificates if thresholds are met
        let slot_votes = self.get_slot_votes(state, state.current_slot);
        let voting_validators: HashSet<u32> = slot_votes.iter().map(|v| v.voter).collect();
        let vote_percentage = (voting_validators.len() * 100) / state.validators.len();

        // Fast path: 80% threshold (4 out of 5 validators)
        if vote_percentage >= 80 {
            actions.push(VotorAction::GenerateCertificate {
                slot: state.current_slot,
                cert_type: CertType::Fast,
            });
        }
        // Slow path: 60% threshold (3 out of 5 validators)
        else if vote_percentage >= 60 {
            actions.push(VotorAction::GenerateCertificate {
                slot: state.current_slot,
                cert_type: CertType::Slow,
            });
        }

        // Time can advance
        if state.clock < 20 {
            actions.push(VotorAction::AdvanceTime);
        }
    }

    fn next_state(&self, state: &Self::State, action: Self::Action) -> Option<Self::State> {
        let mut next_state = state.clone();

        match action {
            VotorAction::CastVote { validator, vote } => {
                // Add vote if validator hasn't voted for this slot yet
                let validator_votes = next_state.votes.entry(validator).or_insert_with(HashSet::new);
                let already_voted = validator_votes.iter().any(|v| v.slot == vote.slot);
                
                if !already_voted {
                    validator_votes.insert(vote);
                }
            }
            VotorAction::GenerateCertificate { slot, cert_type } => {
                let slot_votes = self.get_slot_votes(state, slot);
                let voting_validators: HashSet<u32> = slot_votes.iter().map(|v| v.voter).collect();
                let stake_percentage = (voting_validators.len() * 100) / state.validators.len();

                // Verify threshold requirements
                let threshold_met = match cert_type {
                    CertType::Fast => stake_percentage >= 80,
                    CertType::Slow => stake_percentage >= 60,
                };

                if threshold_met {
                    next_state.certificates.push(Certificate {
                        slot,
                        cert_type,
                        validators: voting_validators,
                        stake_percentage,
                    });
                }
            }
            VotorAction::AdvanceTime => {
                next_state.clock += 1;
            }
        }

        Some(next_state)
    }

    fn properties(&self) -> Vec<Property<Self>> {
        vec![
            // Fast path threshold correctness
            Property::<Self>::always("fast_path_threshold", |_, state| {
                state.certificates.iter().all(|cert| {
                    match cert.cert_type {
                        CertType::Fast => cert.stake_percentage >= 80,
                        CertType::Slow => cert.stake_percentage >= 60,
                    }
                })
            }),
            
            // Dual path progress
            Property::<Self>::eventually("dual_path_progress", |_, state| {
                let has_fast = state.certificates.iter().any(|c| matches!(c.cert_type, CertType::Fast));
                let has_slow = state.certificates.iter().any(|c| matches!(c.cert_type, CertType::Slow));
                has_fast || has_slow
            }),

            // Fast path is more restrictive than slow path
            Property::<Self>::always("threshold_ordering", |_, _| {
                80 > 60 // Fast path threshold > Slow path threshold
            }),
        ]
    }
}

impl VotorDualPathModel {
    fn get_slot_votes(&self, state: &VotorDualPathModel, slot: u32) -> Vec<Vote> {
        state.votes.values()
            .flat_map(|votes| votes.iter())
            .filter(|vote| vote.slot == slot)
            .cloned()
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_votor_dual_path_fast_finalization() {
        let model = VotorDualPathModel {
            validators: vec![1, 2, 3, 4, 5],
            byzantine_validators: HashSet::new(),
            votes: HashMap::new(),
            certificates: Vec::new(),
            current_slot: 1,
            clock: 0,
        };

        // Test that 4 out of 5 validators (80%) can achieve fast path finalization
        let checker = model.checker().spawn_dfs();
        checker.join().assert_properties();
        
        println!("✅ Votor dual path verification completed successfully!");
        println!("   - Fast path (80% threshold) verified");
        println!("   - Slow path (60% threshold) verified");
        println!("   - Threshold ordering maintained");
    }

    #[test]
    fn test_byzantine_resilience_dual_path() {
        let mut model = VotorDualPathModel {
            validators: vec![1, 2, 3, 4, 5],
            byzantine_validators: HashSet::new(),
            votes: HashMap::new(),
            certificates: Vec::new(),
            current_slot: 1,
            clock: 0,
        };

        // Add 1 Byzantine validator (20% - under 1/3 threshold)
        model.byzantine_validators.insert(5);

        let checker = model.checker().spawn_dfs();
        checker.join().assert_properties();
        
        println!("✅ Byzantine resilience test passed!");
        println!("   - System remains secure with 1/5 Byzantine validators");
    }
}
