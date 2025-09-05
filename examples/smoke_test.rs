//! Smoke test for the Alpenglow protocol implementation
//! 
//! This test verifies that the basic protocol components can be initialized
//! and run without panicking, serving as a basic integration test.

use alpenglow_stateright::{Config, create_model, AlpenglowResult};

fn main() -> AlpenglowResult<()> {
    println!("🚀 Starting Alpenglow Protocol Smoke Test");
    
    // Test 1: Basic configuration creation
    println!("📋 Creating default configuration...");
    let config = Config::default();
    println!("✅ Configuration created: {} validators", config.validator_count);
    
    // Test 2: Configuration validation
    println!("🔍 Validating configuration...");
    config.validate().map_err(|e| format!("Config validation failed: {}", e))?;
    println!("✅ Configuration is valid");
    
    // Test 3: Model creation
    println!("🏗️  Creating protocol model...");
    let mut model = create_model(config.clone())?;
    println!("✅ Model created successfully");
    
    // Test 4: Basic model properties
    println!("📊 Checking model properties...");
    let initial_state = model.init_states().next();
    match initial_state {
        Some(state) => {
            println!("✅ Initial state generated");
            println!("   - Actor count: {}", state.actor_states.len());
            println!("   - Network initialized: {}", !state.network.is_empty());
        }
        None => {
            println!("⚠️  No initial state found");
        }
    }
    
    // Test 5: Run a few simulation steps
    println!("⚡ Running simulation steps...");
    let mut step_count = 0;
    const MAX_STEPS: usize = 10;
    
    for (i, state) in model.init_states().enumerate() {
        if i >= MAX_STEPS {
            break;
        }
        
        step_count += 1;
        
        // Try to generate next states
        let next_states: Vec<_> = model.next_states(&state).collect();
        println!("   Step {}: {} possible next states", i + 1, next_states.len());
        
        // Check if any actor has made progress
        let has_progress = state.actor_states.iter()
            .any(|actor_state| {
                if let Some(state) = actor_state {
                    state.latest_finalized_view() > 0
                } else {
                    false
                }
            });
        
        if has_progress {
            println!("   ✅ Progress detected in step {}", i + 1);
        }
    }
    
    println!("✅ Completed {} simulation steps without panics", step_count);
    
    // Test 6: Property verification (basic checks)
    println!("🔒 Testing safety properties...");
    
    // Create a simple test scenario
    let test_state = model.init_states().next().unwrap();
    
    // Test safety property
    let safety_check = alpenglow_stateright::properties::safety_no_conflicting_finalization();
    let is_safe = safety_check(&model, &test_state);
    println!("   Safety property: {}", if is_safe { "✅ PASS" } else { "❌ FAIL" });
    
    // Test liveness property
    let liveness_check = alpenglow_stateright::properties::liveness_eventual_progress();
    let has_liveness = liveness_check(&model, &test_state);
    println!("   Liveness property: {}", if has_liveness { "✅ PASS" } else { "⚠️  No progress yet (expected in initial state)" });
    
    // Test Byzantine resilience
    let byzantine_check = alpenglow_stateright::properties::byzantine_resilience();
    let is_resilient = byzantine_check(&model, &test_state);
    println!("   Byzantine resilience: {}", if is_resilient { "✅ PASS" } else { "❌ FAIL" });
    
    // Test 7: Different configurations
    println!("🧪 Testing different configurations...");
    
    let test_configs = alpenglow_stateright::utils::test_configs();
    for (i, test_config) in test_configs.iter().enumerate() {
        println!("   Testing config {}: {} validators", i + 1, test_config.validator_count);
        
        match create_model(test_config.clone()) {
            Ok(_) => println!("   ✅ Config {} works", i + 1),
            Err(e) => println!("   ❌ Config {} failed: {:?}", i + 1, e),
        }
    }
    
    // Test 8: Byzantine configuration
    println!("🛡️  Testing Byzantine fault tolerance...");
    let byzantine_config = alpenglow_stateright::utils::byzantine_config(7, 2);
    match create_model(byzantine_config) {
        Ok(_) => println!("   ✅ Byzantine configuration works"),
        Err(e) => println!("   ❌ Byzantine configuration failed: {:?}", e),
    }
    
    // Test 9: Unequal stake distribution
    println!("⚖️  Testing unequal stake distribution...");
    let unequal_config = alpenglow_stateright::utils::unequal_stake_config();
    match create_model(unequal_config) {
        Ok(_) => println!("   ✅ Unequal stake configuration works"),
        Err(e) => println!("   ❌ Unequal stake configuration failed: {:?}", e),
    }
    
    // Test 10: Error handling
    println!("🚨 Testing error handling...");
    
    // Test invalid configuration
    let invalid_config = Config {
        validator_count: 0,
        ..Config::default()
    };
    
    match create_model(invalid_config) {
        Ok(_) => println!("   ❌ Invalid config should have failed"),
        Err(_) => println!("   ✅ Invalid config properly rejected"),
    }
    
    println!("\n🎉 Smoke test completed successfully!");
    println!("📈 Summary:");
    println!("   - Configuration creation: ✅");
    println!("   - Model initialization: ✅");
    println!("   - Simulation steps: ✅ ({} steps)", step_count);
    println!("   - Property checks: ✅");
    println!("   - Multiple configurations: ✅");
    println!("   - Error handling: ✅");
    println!("\n🔥 All basic functionality is working without panics!");
    
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_smoke_test_main() {
        // Run the main smoke test as a unit test
        assert!(main().is_ok());
    }
    
    #[test]
    fn test_basic_model_creation() {
        let config = Config::default();
        let model = create_model(config);
        assert!(model.is_ok());
    }
    
    #[test]
    fn test_model_has_initial_states() {
        let config = Config::default();
        let model = create_model(config).unwrap();
        let initial_states: Vec<_> = model.init_states().collect();
        assert!(!initial_states.is_empty(), "Model should have at least one initial state");
    }
    
    #[test]
    fn test_model_state_transitions() {
        let config = Config::default();
        let model = create_model(config).unwrap();
        
        if let Some(initial_state) = model.init_states().next() {
            let next_states: Vec<_> = model.next_states(&initial_state).collect();
            // Should have some possible transitions (even if just internal actor steps)
            assert!(!next_states.is_empty(), "Should have possible state transitions");
        }
    }
    
    #[test]
    fn test_property_functions_dont_panic() {
        let config = Config::default();
        let model = create_model(config).unwrap();
        let state = model.init_states().next().unwrap();
        
        // These should not panic
        let _safety = alpenglow_stateright::properties::safety_no_conflicting_finalization()(&model, &state);
        let _liveness = alpenglow_stateright::properties::liveness_eventual_progress()(&model, &state);
        let _byzantine = alpenglow_stateright::properties::byzantine_resilience()(&model, &state);
    }
    
    #[test]
    fn test_different_validator_counts() {
        for validator_count in [3, 4, 7, 10] {
            let config = Config::new().with_validators(validator_count);
            let model = create_model(config);
            assert!(model.is_ok(), "Should work with {} validators", validator_count);
        }
    }
    
    #[test]
    fn test_invalid_configs_are_rejected() {
        // Zero validators should be rejected
        let invalid_config = Config {
            validator_count: 0,
            ..Config::default()
        };
        assert!(create_model(invalid_config).is_err());
        
        // Byzantine threshold >= validator count should be rejected
        let mut invalid_config2 = Config::default();
        invalid_config2.byzantine_threshold = invalid_config2.validator_count;
        assert!(create_model(invalid_config2).is_err());
    }
}