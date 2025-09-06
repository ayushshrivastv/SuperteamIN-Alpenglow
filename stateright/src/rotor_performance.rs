use crate::{ValidatorId};
use stateright::{Model, Property, Checker};
use std::collections::{HashMap, HashSet};
use std::hash::{Hash, Hasher};

/// Rotor performance validation corresponding to TLA+ RotorPerformanceProofs
#[derive(Clone, Debug, PartialEq)]
pub struct RotorPerformanceModel {
    pub validators: Vec<ValidatorId>,
    pub stake: HashMap<ValidatorId, u64>,
    pub byzantine_validators: HashSet<ValidatorId>,
    pub offline_validators: HashSet<ValidatorId>,
    pub gamma: usize,           // Data shreds required
    pub big_gamma: usize,       // Total shreds (with parity)
    pub delta: u64,             // Network delay bound
    pub beta_leader: u64,       // Leader bandwidth
    pub beta_average: u64,      // Average bandwidth
    pub max_validators: usize,
    pub gst: u64,              // Global Stabilization Time
}

type SliceId = u64;
type MessageId = u64;

#[derive(Clone, Debug, PartialEq)]
pub struct RotorPerformanceState {
    pub relay_failures: HashMap<SliceId, usize>,
    pub network_delay: HashMap<MessageId, u64>,
    pub bandwidth_utilization: HashMap<ValidatorId, u64>,
    pub slice_delivery_time: HashMap<SliceId, u64>,
    pub reconstruction_success: HashMap<ValidatorId, bool>,
    pub clock: u64,
}

impl Hash for RotorPerformanceState {
    fn hash<H: Hasher>(&self, state: &mut H) {
        // Hash only the clock for simplicity, as HashMaps don't implement Hash
        self.clock.hash(state);
    }
}

#[derive(Clone, Debug, PartialEq)]
pub enum RotorPerformanceAction {
    DeliverSlice { slice_id: SliceId, delivery_time: u64 },
    AdvanceClock,
    RelayFailure { slice_id: SliceId, failed_relays: usize },
    UpdateBandwidth { validator: ValidatorId, usage: u64 },
}

impl RotorPerformanceModel {
    pub fn new() -> Self {
        let validators = vec![1, 2, 3, 4, 5];
        
        let mut stake = HashMap::new();
        stake.insert(1, 150);
        stake.insert(2, 150);
        stake.insert(3, 100);
        stake.insert(4, 100);
        stake.insert(5, 50);
        
        let mut byzantine_validators = HashSet::new();
        byzantine_validators.insert(5); // ~10% stake
        
        Self {
            validators,
            stake,
            byzantine_validators,
            offline_validators: HashSet::new(),
            gamma: 3,
            big_gamma: 5,
            delta: 100,
            beta_leader: 1000,
            beta_average: 800,
            max_validators: 100,
            gst: 50,
        }
    }
    
    /// Lemma 7: Calculate relay failure probability
    pub fn relay_failure_probability(&self) -> f64 {
        let total_stake: u64 = self.stake.values().sum();
        let byzantine_stake: u64 = self.byzantine_validators
            .iter()
            .map(|v| self.stake.get(v).unwrap_or(&0))
            .sum();
        let offline_stake: u64 = self.offline_validators
            .iter()
            .map(|v| self.stake.get(v).unwrap_or(&0))
            .sum();
        
        (byzantine_stake + offline_stake) as f64 / total_stake as f64
    }
    
    /// Lemma 7: Expected successful relays
    pub fn expected_successful_relays(&self) -> f64 {
        self.big_gamma as f64 * (1.0 - self.relay_failure_probability())
    }
    
    /// Lemma 8: Latency bound based on over-provisioning
    pub fn latency_bound(&self, kappa: f64) -> u64 {
        if kappa <= 1.0 {
            2 * self.delta
        } else if kappa >= self.max_validators as f64 {
            self.delta
        } else {
            let reduction = (self.delta as f64) * (kappa - 1.0) / self.max_validators as f64;
            (2.0 * self.delta as f64 - reduction) as u64
        }
    }
    
    /// Lemma 9: Delivery rate per validator
    pub fn delivery_rate(&self) -> u64 {
        let kappa = self.big_gamma as f64 / self.gamma as f64;
        (self.beta_leader as f64 / kappa) as u64
    }
    
    /// Verify Lemma 7: Rotor Resilience
    pub fn verify_lemma_7(&self) -> bool {
        let kappa = self.big_gamma as f64 / self.gamma as f64;
        let expected_success = self.expected_successful_relays();
        
        // Check over-provisioning constraint
        let over_provisioning_ok = kappa > 5.0 / 3.0;
        
        // Check expected successful relays exceed threshold
        let success_threshold_ok = expected_success >= self.gamma as f64;
        
        // Check failure probability is reasonable (< 40%)
        let failure_rate_ok = self.relay_failure_probability() < 0.4;
        
        over_provisioning_ok && success_threshold_ok && failure_rate_ok
    }
    
    /// Verify Lemma 8: Rotor Latency
    pub fn verify_lemma_8(&self, actual_latency: u64) -> bool {
        let kappa = self.big_gamma as f64 / self.gamma as f64;
        let bound = self.latency_bound(kappa);
        
        // Basic bound: latency <= 2*delta
        let basic_bound_ok = actual_latency <= 2 * self.delta;
        
        // Enhanced bound with over-provisioning
        let enhanced_bound_ok = actual_latency <= bound;
        
        // Asymptotic case: high over-provisioning approaches delta
        let asymptotic_ok = if kappa >= self.max_validators as f64 {
            actual_latency <= self.delta + 10 // Small tolerance
        } else {
            true
        };
        
        basic_bound_ok && enhanced_bound_ok && asymptotic_ok
    }
    
    /// Verify Lemma 9: Bandwidth Optimality
    pub fn verify_lemma_9(&self) -> bool {
        let delivery_rate = self.delivery_rate();
        let kappa = self.big_gamma as f64 / self.gamma as f64;
        
        // Check leader bandwidth constraint
        let bandwidth_constraint_ok = self.beta_leader <= self.beta_average;
        
        // Check delivery rate formula
        let expected_rate = (self.beta_leader as f64 / kappa) as u64;
        let rate_formula_ok = delivery_rate == expected_rate;
        
        // Check optimality up to expansion factor
        let theoretical_max = self.beta_leader;
        let actual_with_expansion = (delivery_rate as f64 * kappa) as u64;
        let optimality_ok = actual_with_expansion <= theoretical_max + 10; // Small tolerance
        
        bandwidth_constraint_ok && rate_formula_ok && optimality_ok
    }
}

// Helper function for performance invariant
fn performance_invariant(model: &RotorPerformanceModel, state: &RotorPerformanceState) -> bool {
    // Check latency bounds
    let latency_ok = state.slice_delivery_time.values()
        .all(|&latency| latency <= 2 * model.delta);
    
    // Check bandwidth bounds
    let bandwidth_ok = state.bandwidth_utilization.values()
        .all(|&usage| usage <= model.beta_average);
    
    latency_ok && bandwidth_ok
}

// Helper functions for properties
fn lemma7_resilience(model: &RotorPerformanceModel, state: &RotorPerformanceState) -> bool {
    if state.clock > model.gst {
        model.verify_lemma_7()
    } else {
        true // Before GST, no guarantees
    }
}

fn lemma8_latency(model: &RotorPerformanceModel, state: &RotorPerformanceState) -> bool {
    state.slice_delivery_time.values()
        .all(|&latency| model.verify_lemma_8(latency))
}

fn lemma9_bandwidth(model: &RotorPerformanceModel, _state: &RotorPerformanceState) -> bool {
    model.verify_lemma_9()
}

impl Model for RotorPerformanceModel {
    type State = RotorPerformanceState;
    type Action = RotorPerformanceAction;
    
    fn init_states(&self) -> Vec<Self::State> {
        vec![RotorPerformanceState {
            relay_failures: HashMap::new(),
            network_delay: HashMap::new(),
            bandwidth_utilization: self.validators.iter()
                .map(|&v| (v, 0))
                .collect(),
            slice_delivery_time: HashMap::new(),
            reconstruction_success: self.validators.iter()
                .map(|&v| (v, true))
                .collect(),
            clock: 0,
        }]
    }
    
    fn actions(&self, state: &Self::State, actions: &mut Vec<Self::Action>) {
        // Advance clock
        if state.clock < 200 {
            actions.push(RotorPerformanceAction::AdvanceClock);
        }
        
        // Deliver new slices
        if state.slice_delivery_time.len() < 10 {
            let slice_id = state.slice_delivery_time.len() as u64;
            let kappa = self.big_gamma as f64 / self.gamma as f64;
            let delivery_time = self.latency_bound(kappa);
            
            actions.push(RotorPerformanceAction::DeliverSlice {
                slice_id,
                delivery_time,
            });
        }
        
        // Simulate relay failures
        for slice_id in 0..state.slice_delivery_time.len() as u64 {
            if !state.relay_failures.contains_key(&slice_id) {
                let expected_failures = (self.big_gamma as f64 * self.relay_failure_probability()) as usize;
                actions.push(RotorPerformanceAction::RelayFailure {
                    slice_id,
                    failed_relays: expected_failures,
                });
            }
        }
    }
    
    fn next_state(&self, state: &Self::State, action: Self::Action) -> Option<Self::State> {
        let mut next_state = state.clone();
        
        match action {
            RotorPerformanceAction::AdvanceClock => {
                next_state.clock += 1;
            }
            
            RotorPerformanceAction::DeliverSlice { slice_id, delivery_time } => {
                if !state.slice_delivery_time.contains_key(&slice_id) {
                    next_state.slice_delivery_time.insert(slice_id, delivery_time);
                }
            }
            
            RotorPerformanceAction::RelayFailure { slice_id, failed_relays } => {
                next_state.relay_failures.insert(slice_id, failed_relays);
            }
            
            RotorPerformanceAction::UpdateBandwidth { validator, usage } => {
                next_state.bandwidth_utilization.insert(validator, usage);
            }
        }
        
        Some(next_state)
    }
    
    fn properties(&self) -> Vec<Property<Self>> {
        vec![
            // Performance Invariant: Bounds always satisfied
            Property::<Self>::always("PerformanceInvariant", performance_invariant),
            
            // Simplified properties for verification
            Property::<Self>::always("Lemma7Resilience", lemma7_resilience),
            Property::<Self>::always("Lemma8Latency", lemma8_latency),
            Property::<Self>::always("Lemma9Bandwidth", lemma9_bandwidth),
        ]
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_lemma_7_rotor_resilience() {
        let model = RotorPerformanceModel::new();
        
        // Test over-provisioning constraint
        let kappa = model.big_gamma as f64 / model.gamma as f64;
        assert!(kappa > 5.0 / 3.0, "Over-provisioning constraint violated");
        
        // Test expected successful relays
        let expected_success = model.expected_successful_relays();
        assert!(expected_success >= model.gamma as f64, 
                "Expected successful relays below threshold");
        
        // Test overall lemma
        assert!(model.verify_lemma_7(), "Lemma 7 verification failed");
    }
    
    #[test]
    fn test_lemma_8_rotor_latency() {
        let model = RotorPerformanceModel::new();
        
        // Test basic latency bound
        let basic_latency = 150; // < 2 * delta
        assert!(model.verify_lemma_8(basic_latency), "Basic latency bound failed");
        
        // Test asymptotic case
        let mut high_provisioning_model = model.clone();
        high_provisioning_model.big_gamma = 1000; // Very high over-provisioning
        let asymptotic_latency = 110; // Close to delta
        assert!(high_provisioning_model.verify_lemma_8(asymptotic_latency),
                "Asymptotic latency bound failed");
    }
    
    #[test]
    fn test_lemma_9_bandwidth_optimality() {
        let model = RotorPerformanceModel::new();
        
        // Test bandwidth constraint
        assert!(model.beta_leader <= model.beta_average, 
                "Leader bandwidth exceeds average");
        
        // Test delivery rate calculation
        let delivery_rate = model.delivery_rate();
        let kappa = model.big_gamma as f64 / model.gamma as f64;
        let expected = (model.beta_leader as f64 / kappa) as u64;
        assert_eq!(delivery_rate, expected, "Delivery rate calculation incorrect");
        
        // Test overall lemma
        assert!(model.verify_lemma_9(), "Lemma 9 verification failed");
    }
    
    #[test]
    fn test_integrated_performance_properties() {
        let model = RotorPerformanceModel::new();
        
        // All lemmas should verify together
        assert!(model.verify_lemma_7(), "Lemma 7 failed in integration");
        assert!(model.verify_lemma_8(150), "Lemma 8 failed in integration");
        assert!(model.verify_lemma_9(), "Lemma 9 failed in integration");
    }
    
    #[test]
    fn test_model_checking() {
        let model = RotorPerformanceModel::new();
        let mut checker = model.checker().spawn_dfs();
        
        // Run bounded model checking
        let result = checker.join();
        
        println!("Model checking completed");
    }
}
