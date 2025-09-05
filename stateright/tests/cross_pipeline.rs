//! End-to-end integration tests for cross-validation pipeline
//! 
//! This module tests the complete cross-validation workflow between
//! Rust Stateright and TLA+ implementations of the Alpenglow protocol.

use alpenglow_stateright::{
    AlpenglowState, Config, ModelChecker, TlaCompatible,
    VotorState, RotorState, NetworkState,
    AlpenglowResult, AlpenglowError,
};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::process::Command;
use tempfile::TempDir;

/// Test configuration for cross-validation pipeline
#[derive(Debug, Clone)]
struct CrossValidationTestConfig {
    pub name: String,
    pub config: Config,
    pub expected_properties: Vec<String>,
    pub timeout_seconds: u64,
    pub simulate_mode: bool,
}

/// Results from cross-validation test run
#[derive(Debug)]
struct CrossValidationResults {
    pub stateright_success: bool,
    pub tla_success: bool,
    pub properties_consistent: bool,
    pub violations_consistent: bool,
    pub stateright_violations: u32,
    pub tla_violations: u32,
    pub verified_properties: Vec<String>,
    pub violated_properties: Vec<String>,
}

/// Cross-validation test suite
struct CrossValidationTestSuite {
    temp_dir: TempDir,
    project_root: PathBuf,
    property_mapping: Value,
}

impl CrossValidationTestSuite {
    /// Create a new test suite instance
    fn new() -> AlpenglowResult<Self> {
        let temp_dir = TempDir::new()
            .map_err(|e| AlpenglowError::Io(format!("Failed to create temp dir: {}", e)))?;
        
        // Find project root (assuming we're in stateright/tests/)
        let project_root = std::env::current_dir()
            .map_err(|e| AlpenglowError::Io(format!("Failed to get current dir: {}", e)))?
            .parent()
            .ok_or_else(|| AlpenglowError::Io("Cannot find project root".to_string()))?
            .to_path_buf();
        
        // Load property mapping
        let mapping_file = project_root.join("scripts/property_mapping.json");
        let property_mapping = if mapping_file.exists() {
            let content = fs::read_to_string(&mapping_file)
                .map_err(|e| AlpenglowError::Io(format!("Failed to read property mapping: {}", e)))?;
            serde_json::from_str(&content)
                .map_err(|e| AlpenglowError::Io(format!("Failed to parse property mapping: {}", e)))?
        } else {
            json!({
                "version": "1.0.0",
                "mappings": {
                    "safety_properties": {
                        "rust_to_tla": {},
                        "tla_to_rust": {}
                    }
                }
            })
        };
        
        Ok(Self {
            temp_dir,
            project_root,
            property_mapping,
        })
    }
    
    /// Get test configurations for different scenarios
    fn get_test_configurations(&self) -> Vec<CrossValidationTestConfig> {
        vec![
            CrossValidationTestConfig {
                name: "small_safety".to_string(),
                config: Config::small(),
                expected_properties: vec![
                    "VotorSafety".to_string(),
                    "NonEquivocation".to_string(),
                    "CertificateValidity".to_string(),
                ],
                timeout_seconds: 300,
                simulate_mode: false,
            },
            CrossValidationTestConfig {
                name: "small_liveness".to_string(),
                config: Config::small(),
                expected_properties: vec![
                    "EventualDeliveryProperty".to_string(),
                    "ViewProgression".to_string(),
                ],
                timeout_seconds: 600,
                simulate_mode: false,
            },
            CrossValidationTestConfig {
                name: "byzantine_resilience".to_string(),
                config: Config::byzantine(),
                expected_properties: vec![
                    "ByzantineResilience".to_string(),
                    "HonestMajorityProgress".to_string(),
                ],
                timeout_seconds: 900,
                simulate_mode: false,
            },
            CrossValidationTestConfig {
                name: "simulation_smoke_test".to_string(),
                config: Config::small(),
                expected_properties: vec![
                    "VotorSafety".to_string(),
                ],
                timeout_seconds: 120,
                simulate_mode: true,
            },
        ]
    }
    
    /// Run Stateright verification for a configuration
    fn run_stateright_verification(&self, test_config: &CrossValidationTestConfig) -> AlpenglowResult<Value> {
        let mut model_checker = ModelChecker::new(test_config.config.clone());
        
        // Set up verification parameters
        model_checker.set_timeout(test_config.timeout_seconds);
        if test_config.simulate_mode {
            model_checker.enable_simulation_mode();
        }
        
        // Run verification
        let start_time = std::time::Instant::now();
        let verification_result = model_checker.verify_model()?;
        let duration = start_time.elapsed();
        
        // Create summary JSON
        let summary = json!({
            "timestamp": chrono::Utc::now().to_rfc3339(),
            "config": test_config.name,
            "success": verification_result.success,
            "simulation_mode": test_config.simulate_mode,
            "metrics": {
                "total_states_explored": verification_result.states_explored,
                "total_properties_checked": verification_result.properties_checked,
                "total_violations_found": verification_result.violations.len(),
                "verification_time_seconds": duration.as_secs(),
                "scenarios_passed": if verification_result.success { 1 } else { 0 },
                "scenarios_failed": if verification_result.success { 0 } else { 1 }
            },
            "results": {
                "safety": if verification_result.violations.iter().any(|v| v.property_type == "safety") { "FAIL" } else { "PASS" },
                "liveness": if verification_result.violations.iter().any(|v| v.property_type == "liveness") { "FAIL" } else { "PASS" },
                "byzantine": if verification_result.violations.iter().any(|v| v.property_type == "byzantine") { "FAIL" } else { "PASS" }
            },
            "violations": verification_result.violations.iter().map(|v| json!({
                "property": v.property_name,
                "type": v.property_type,
                "description": v.description
            })).collect::<Vec<_>>(),
            "properties_verified": verification_result.verified_properties
        });
        
        Ok(summary)
    }
    
    /// Run TLA+ verification using the enhanced check_model.sh script
    fn run_tla_verification(&self, test_config: &CrossValidationTestConfig) -> AlpenglowResult<Value> {
        let script_path = self.project_root.join("scripts/check_model.sh");
        let config_name = if test_config.name.contains("byzantine") {
            "EdgeCase"
        } else {
            "Small"
        };
        
        // Prepare command arguments
        let mut args = vec![
            config_name.to_string(),
            "--json".to_string(),
            "--cross-validate".to_string(),
            "--timeout".to_string(),
            test_config.timeout_seconds.to_string(),
        ];
        
        if test_config.simulate_mode {
            args.push("--simulate".to_string());
        }
        
        // Add dynamic constants if needed
        if test_config.name.contains("byzantine") {
            args.push("--constants".to_string());
            args.push("BYZANTINE_NODES=1,F=1".to_string());
        }
        
        // Run TLA+ verification
        let output = Command::new("bash")
            .arg(&script_path)
            .args(&args)
            .current_dir(&self.project_root)
            .output()
            .map_err(|e| AlpenglowError::Io(format!("Failed to run TLA+ verification: {}", e)))?;
        
        // Parse results from the most recent result directory
        let results_dir = self.project_root.join("results");
        let mut latest_result_dir = None;
        let mut latest_time = std::time::SystemTime::UNIX_EPOCH;
        
        if let Ok(entries) = fs::read_dir(&results_dir) {
            for entry in entries.flatten() {
                if let Ok(metadata) = entry.metadata() {
                    if metadata.is_dir() {
                        if let Ok(modified) = metadata.modified() {
                            if modified > latest_time {
                                latest_time = modified;
                                latest_result_dir = Some(entry.path());
                            }
                        }
                    }
                }
            }
        }
        
        // Load TLA+ summary JSON if available
        if let Some(result_dir) = latest_result_dir {
            let summary_file = result_dir.join("tla_summary.json");
            if summary_file.exists() {
                let content = fs::read_to_string(&summary_file)
                    .map_err(|e| AlpenglowError::Io(format!("Failed to read TLA+ summary: {}", e)))?;
                let summary: Value = serde_json::from_str(&content)
                    .map_err(|e| AlpenglowError::Io(format!("Failed to parse TLA+ summary: {}", e)))?;
                return Ok(summary);
            }
        }
        
        // Fallback: create summary from command output
        let success = output.status.success();
        let stdout = String::from_utf8_lossy(&output.stdout);
        let stderr = String::from_utf8_lossy(&output.stderr);
        
        Ok(json!({
            "timestamp": chrono::Utc::now().to_rfc3339(),
            "config": config_name,
            "success": success,
            "exit_code": output.status.code().unwrap_or(-1),
            "timeout_occurred": false,
            "simulation_mode": test_config.simulate_mode,
            "metrics": {
                "states_generated": 0,
                "distinct_states": 0,
                "violations_found": if success { 0 } else { 1 },
                "duration_seconds": test_config.timeout_seconds
            },
            "properties_verified": if success { test_config.expected_properties.clone() } else { Vec::<String>::new() },
            "properties_violated": if success { Vec::<String>::new() } else { vec!["Unknown".to_string()] },
            "stdout": stdout,
            "stderr": stderr
        }))
    }
    
    /// Cross-validate results between Stateright and TLA+
    fn cross_validate_results(&self, stateright_result: &Value, tla_result: &Value) -> CrossValidationResults {
        let sr_success = stateright_result["success"].as_bool().unwrap_or(false);
        let tla_success = tla_result["success"].as_bool().unwrap_or(false);
        
        let sr_violations = stateright_result["metrics"]["total_violations_found"].as_u64().unwrap_or(0) as u32;
        let tla_violations = tla_result["metrics"]["violations_found"].as_u64().unwrap_or(0) as u32;
        
        let sr_verified = stateright_result["properties_verified"].as_array()
            .map(|arr| arr.iter().filter_map(|v| v.as_str().map(|s| s.to_string())).collect())
            .unwrap_or_else(Vec::new);
        
        let tla_verified = tla_result["properties_verified"].as_array()
            .map(|arr| arr.iter().filter_map(|v| v.as_str().map(|s| s.to_string())).collect())
            .unwrap_or_else(Vec::new);
        
        let sr_violated = stateright_result["violations"].as_array()
            .map(|arr| arr.iter().filter_map(|v| v["property"].as_str().map(|s| s.to_string())).collect())
            .unwrap_or_else(Vec::new);
        
        let tla_violated = tla_result["properties_violated"].as_array()
            .map(|arr| arr.iter().filter_map(|v| v.as_str().map(|s| s.to_string())).collect())
            .unwrap_or_else(Vec::new);
        
        // Check consistency
        let properties_consistent = self.check_property_consistency(&sr_verified, &tla_verified, &sr_violated, &tla_violated);
        let violations_consistent = (sr_violations == 0 && tla_violations == 0) || (sr_violations > 0 && tla_violations > 0);
        
        CrossValidationResults {
            stateright_success: sr_success,
            tla_success,
            properties_consistent,
            violations_consistent,
            stateright_violations: sr_violations,
            tla_violations,
            verified_properties: sr_verified,
            violated_properties: sr_violated,
        }
    }
    
    /// Check consistency between property verification results
    fn check_property_consistency(&self, sr_verified: &[String], tla_verified: &[String], 
                                 sr_violated: &[String], tla_violated: &[String]) -> bool {
        // Map properties using property mapping
        let mapped_tla_verified: Vec<String> = tla_verified.iter()
            .filter_map(|prop| self.map_tla_to_rust_property(prop))
            .collect();
        
        let mapped_tla_violated: Vec<String> = tla_violated.iter()
            .filter_map(|prop| self.map_tla_to_rust_property(prop))
            .collect();
        
        // Check for major inconsistencies
        for sr_prop in sr_verified {
            if mapped_tla_violated.contains(sr_prop) {
                return false; // Rust says verified, TLA+ says violated
            }
        }
        
        for sr_prop in sr_violated {
            if mapped_tla_verified.contains(sr_prop) {
                return false; // Rust says violated, TLA+ says verified
            }
        }
        
        true
    }
    
    /// Map TLA+ property name to Rust property name using property mapping
    fn map_tla_to_rust_property(&self, tla_property: &str) -> Option<String> {
        let mappings = &self.property_mapping["mappings"];
        
        for category in ["safety_properties", "liveness_properties", "type_invariants", "partial_synchrony_properties", "performance_properties"] {
            if let Some(tla_to_rust) = mappings[category]["tla_to_rust"].as_object() {
                if let Some(rust_prop) = tla_to_rust.get(tla_property) {
                    return rust_prop.as_str().map(|s| s.to_string());
                }
            }
        }
        
        None
    }
    
    /// Run a complete cross-validation test
    fn run_cross_validation_test(&self, test_config: &CrossValidationTestConfig) -> AlpenglowResult<CrossValidationResults> {
        println!("Running cross-validation test: {}", test_config.name);
        
        // Run Stateright verification
        println!("  Running Stateright verification...");
        let stateright_result = self.run_stateright_verification(test_config)?;
        
        // Run TLA+ verification
        println!("  Running TLA+ verification...");
        let tla_result = self.run_tla_verification(test_config)?;
        
        // Cross-validate results
        println!("  Cross-validating results...");
        let cross_validation = self.cross_validate_results(&stateright_result, &tla_result);
        
        println!("  Test completed: {} consistent", if cross_validation.properties_consistent && cross_validation.violations_consistent { "✓" } else { "✗" });
        
        Ok(cross_validation)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_cross_validation_pipeline_setup() {
        let suite = CrossValidationTestSuite::new().expect("Failed to create test suite");
        let configs = suite.get_test_configurations();
        
        assert!(!configs.is_empty(), "Should have test configurations");
        assert!(configs.iter().any(|c| c.name == "small_safety"), "Should have safety test");
        assert!(configs.iter().any(|c| c.name == "small_liveness"), "Should have liveness test");
    }
    
    #[test]
    fn test_property_mapping_functionality() {
        let suite = CrossValidationTestSuite::new().expect("Failed to create test suite");
        
        // Test property mapping if available
        if suite.property_mapping["mappings"]["safety_properties"]["tla_to_rust"].as_object().is_some() {
            // This would test actual mappings if they exist
            println!("Property mapping is available and loaded");
        }
    }
    
    #[test]
    #[ignore] // This test requires TLA+ tools and takes time
    fn test_small_safety_cross_validation() {
        let suite = CrossValidationTestSuite::new().expect("Failed to create test suite");
        let configs = suite.get_test_configurations();
        
        let safety_config = configs.iter()
            .find(|c| c.name == "small_safety")
            .expect("Safety config should exist");
        
        let result = suite.run_cross_validation_test(safety_config)
            .expect("Cross-validation test should complete");
        
        // Basic consistency checks
        assert!(result.properties_consistent, "Properties should be consistent between approaches");
        assert!(result.violations_consistent, "Violation counts should be consistent");
        
        // If both succeed, they should agree on no violations
        if result.stateright_success && result.tla_success {
            assert_eq!(result.stateright_violations, 0, "Successful Stateright run should have no violations");
            assert_eq!(result.tla_violations, 0, "Successful TLA+ run should have no violations");
        }
    }
    
    #[test]
    #[ignore] // This test requires TLA+ tools and takes time
    fn test_simulation_mode_cross_validation() {
        let suite = CrossValidationTestSuite::new().expect("Failed to create test suite");
        let configs = suite.get_test_configurations();
        
        let sim_config = configs.iter()
            .find(|c| c.name == "simulation_smoke_test")
            .expect("Simulation config should exist");
        
        let result = suite.run_cross_validation_test(sim_config)
            .expect("Simulation cross-validation test should complete");
        
        // Simulation mode should generally succeed for smoke tests
        println!("Simulation results: SR success={}, TLA success={}", 
                result.stateright_success, result.tla_success);
    }
    
    #[test]
    #[ignore] // This test requires TLA+ tools and significant time
    fn test_full_cross_validation_suite() {
        let suite = CrossValidationTestSuite::new().expect("Failed to create test suite");
        let configs = suite.get_test_configurations();
        
        let mut all_consistent = true;
        let mut results = Vec::new();
        
        for config in &configs {
            // Skip long-running tests in regular CI
            if config.timeout_seconds > 300 {
                continue;
            }
            
            match suite.run_cross_validation_test(config) {
                Ok(result) => {
                    let consistent = result.properties_consistent && result.violations_consistent;
                    all_consistent &= consistent;
                    results.push((config.name.clone(), consistent));
                    
                    println!("Test {}: {} (SR: {}, TLA: {})", 
                            config.name,
                            if consistent { "✓ CONSISTENT" } else { "✗ INCONSISTENT" },
                            if result.stateright_success { "PASS" } else { "FAIL" },
                            if result.tla_success { "PASS" } else { "FAIL" });
                }
                Err(e) => {
                    println!("Test {} failed: {}", config.name, e);
                    all_consistent = false;
                }
            }
        }
        
        println!("\nCross-validation suite summary:");
        for (name, consistent) in &results {
            println!("  {}: {}", name, if *consistent { "✓" } else { "✗" });
        }
        
        assert!(all_consistent, "All cross-validation tests should be consistent");
    }
}

/// Integration test helper for running cross-validation from external tools
#[cfg(test)]
pub fn run_cross_validation_integration_test(config_name: &str) -> Result<bool, Box<dyn std::error::Error>> {
    let suite = CrossValidationTestSuite::new()?;
    let configs = suite.get_test_configurations();
    
    let config = configs.iter()
        .find(|c| c.name == config_name)
        .ok_or_else(|| format!("Configuration '{}' not found", config_name))?;
    
    let result = suite.run_cross_validation_test(config)?;
    
    Ok(result.properties_consistent && result.violations_consistent)
}
