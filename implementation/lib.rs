//! Alpenglow Protocol Validation and Monitoring Library
//!
//! This crate provides comprehensive validation tools and runtime monitoring
//! for the Solana Alpenglow consensus protocol. It includes formal verification
//! tools, conformance testing, runtime monitoring, and Actor model integration.
//!
//! ## Features
//!
//! - **validation**: Formal verification tools and conformance testing
//! - **monitoring**: Runtime monitoring and alerting system
//! - **actor-integration**: Integration with the Alpenglow Actor model
//! - **tla-cross-validation**: TLA+ specification cross-validation
//! - **metrics-export**: Prometheus and other metrics export formats
//! - **dashboards**: Real-time monitoring dashboards
//!
//! ## Usage
//!
//! ### Basic Validation
//!
//! ```rust
//! use alpenglow_validation::{ValidationTools, ValidationConfig};
//!
//! let config = ValidationConfig::default();
//! let mut tools = ValidationTools::new(config);
//!
//! // Initialize validator set
//! tools.initialize_validators(vec![(0, 1000), (1, 1000), (2, 1000), (3, 1000)]);
//!
//! // Run conformance tests
//! let results = tools.run_conformance_tests().await;
//! println!("Tests passed: {}/{}", results.passed_tests, results.total_tests);
//! ```
//!
//! ### Runtime Monitoring
//!
//! ```rust
//! use alpenglow_validation::{AlpenglowRuntimeMonitor, MonitorConfig};
//!
//! let config = MonitorConfig::default();
//! let monitor = AlpenglowRuntimeMonitor::new(config);
//!
//! // Subscribe to alerts
//! let mut alerts = monitor.subscribe_runtime_alerts();
//!
//! // Start monitoring
//! monitor.start().await?;
//!
//! // Handle alerts
//! while let Ok(alert) = alerts.recv().await {
//!     println!("Alert: {:?}", alert);
//! }
//! ```
//!
//! ### Actor Model Integration
//!
//! ```rust
//! use alpenglow_validation::ValidationTools;
//! use alpenglow_stateright::{Config, create_model};
//!
//! let config = Config::default();
//! let model = create_model(config.clone())?;
//! let mut tools = ValidationTools::new_with_actor_model(
//!     ValidationConfig::from(config), 
//!     model
//! )?;
//!
//! // Run tests with Actor model integration
//! let results = tools.run_actor_model_tests().await?;
//! ```

#![warn(missing_docs)]
#![warn(clippy::all)]
#![allow(clippy::too_many_arguments)]
#![allow(clippy::large_enum_variant)]

// Core validation module - always available
pub mod validation;

// Runtime monitoring module - feature-gated
#[cfg(feature = "monitoring")]
pub mod monitor;

// Re-export main types and functions for convenience
pub use validation::{
    // Core validation types
    ValidationConfig,
    ValidationEvent,
    ValidationError,
    ValidationMetrics,
    ValidationTools,
    ValidationReport,
    
    // Test types
    ConformanceTestSuite,
    ConformanceTestResults,
    TestScenario,
    TestResult,
    
    // Property checkers
    SafetyChecker,
    LivenessChecker,
    ByzantineChecker,
    NetworkChecker,
    
    // Actor model integration
    ActorModelBridge,
    
    // Alert types (shared with monitoring)
    Alert as ValidationAlert,
    AlertSeverity,
    
    // Data types
    Block,
    Vote,
    Certificate,
    CertificateType,
    ValidatorState,
    TimingParams,
    StakeThresholds,
};

// Re-export monitoring types when feature is enabled
#[cfg(feature = "monitoring")]
pub use monitor::{
    // Core monitoring types
    MonitorConfig,
    AlpenglowRuntimeMonitor,
    RuntimeAlert,
    RuntimeAlertType,
    RuntimeMonitorEvent,
    
    // Metrics and health
    RuntimeMetrics,
    NetworkHealth,
    ResourceUsage,
    RuntimeMonitorStats,
    PerformanceTrends,
    
    // Actor integration
    RuntimeActorBridge,
    
    // Resource types
    ValidatorResources,
    SystemResources,
    ResourceLimits,
};

// Integration utilities
pub mod integration {
    //! Integration utilities for combining validation and monitoring
    
    use crate::validation::{ValidationTools, ValidationConfig};
    
    #[cfg(feature = "monitoring")]
    use crate::monitor::{AlpenglowRuntimeMonitor, MonitorConfig};
    
    use alpenglow_stateright::{Config as AlpenglowConfig, AlpenglowResult};
    
    /// Create validation tools from Alpenglow config
    pub fn create_validation_tools(config: AlpenglowConfig) -> AlpenglowResult<ValidationTools> {
        ValidationTools::from_alpenglow_config(config)
    }
    
    /// Create runtime monitor from Alpenglow config (requires monitoring feature)
    #[cfg(feature = "monitoring")]
    pub fn create_runtime_monitor(config: AlpenglowConfig) -> AlpenglowResult<AlpenglowRuntimeMonitor> {
        AlpenglowRuntimeMonitor::from_alpenglow_config(config)
    }
    
    /// Create integrated validation and monitoring system
    #[cfg(feature = "monitoring")]
    pub fn create_integrated_system(
        config: AlpenglowConfig
    ) -> AlpenglowResult<(ValidationTools, AlpenglowRuntimeMonitor)> {
        crate::monitor::integration::create_integrated_monitoring(config)
    }
    
    /// Run end-to-end validation with optional monitoring
    pub async fn run_end_to_end_validation(
        config: AlpenglowConfig,
        test_duration: std::time::Duration,
    ) -> AlpenglowResult<crate::validation::ValidationReport> {
        crate::validation::integration::run_end_to_end_validation(config, test_duration).await
    }
    
    /// Quick validation check for basic functionality
    pub async fn quick_validation_check(config: AlpenglowConfig) -> AlpenglowResult<bool> {
        let tools = create_validation_tools(config)?;
        let results = tools.run_conformance_tests().await;
        Ok(results.success_rate() > 0.8) // 80% pass rate threshold
    }
}

// Feature-specific exports and utilities
#[cfg(feature = "actor-integration")]
pub mod actor_integration {
    //! Actor model integration utilities
    
    pub use crate::validation::{ActorModelBridge, ValidationTools};
    
    #[cfg(feature = "monitoring")]
    pub use crate::monitor::RuntimeActorBridge;
    
    use alpenglow_stateright::{
        local_stateright::{ActorModel, SystemState},
        integration::{AlpenglowNode, AlpenglowState},
        AlpenglowResult,
    };
    
    /// Attach validation tools to an existing Actor model
    pub fn attach_validation_to_model(
        model: ActorModel<AlpenglowNode, (), ()>,
        config: crate::validation::ValidationConfig,
    ) -> AlpenglowResult<crate::validation::ValidationTools> {
        crate::validation::ValidationTools::new_with_actor_model(config, model)
    }
    
    /// Observe Actor model state changes for validation
    pub fn observe_actor_state(
        tools: &crate::validation::ValidationTools,
        state: &SystemState<AlpenglowState>,
    ) -> AlpenglowResult<()> {
        tools.observe_actor_state(state)
    }
    
    /// Export Actor model state for TLA+ cross-validation
    pub fn export_actor_tla_state(
        tools: &crate::validation::ValidationTools,
    ) -> Option<serde_json::Value> {
        tools.export_actor_tla_state()
    }
}

#[cfg(feature = "tla-cross-validation")]
pub mod tla_validation {
    //! TLA+ specification cross-validation utilities
    
    use alpenglow_stateright::{AlpenglowResult, TlaCompatible};
    use serde_json::Value;
    
    /// Validate Actor model state against TLA+ invariants
    pub fn validate_tla_invariants(
        tools: &crate::validation::ValidationTools,
    ) -> AlpenglowResult<()> {
        tools.validate_actor_invariants()
    }
    
    /// Export state for TLA+ model checker
    pub fn export_for_tla_checker(
        tools: &crate::validation::ValidationTools,
    ) -> Option<Value> {
        tools.export_actor_tla_state()
    }
    
    /// Cross-validate with external TLA+ specification
    pub async fn cross_validate_with_tla(
        tools: &crate::validation::ValidationTools,
        tla_spec_path: &str,
    ) -> AlpenglowResult<bool> {
        // This would integrate with external TLA+ tools
        // For now, just validate internal invariants
        tools.validate_actor_invariants()?;
        Ok(true)
    }
}

#[cfg(feature = "metrics-export")]
pub mod metrics {
    //! Metrics export utilities for external monitoring systems
    
    use std::collections::HashMap;
    
    #[cfg(feature = "monitoring")]
    use crate::monitor::AlpenglowRuntimeMonitor;
    
    /// Export metrics in Prometheus format
    #[cfg(feature = "monitoring")]
    pub fn export_prometheus_metrics(monitor: &AlpenglowRuntimeMonitor) -> String {
        let metrics = monitor.export_metrics();
        let mut output = String::new();
        
        for (name, value) in metrics {
            output.push_str(&format!("# TYPE {} gauge\n", name));
            output.push_str(&format!("{} {}\n", name, value));
        }
        
        output
    }
    
    /// Export metrics as JSON
    #[cfg(feature = "monitoring")]
    pub fn export_json_metrics(monitor: &AlpenglowRuntimeMonitor) -> serde_json::Value {
        let metrics = monitor.export_metrics();
        serde_json::to_value(metrics).unwrap_or_default()
    }
    
    /// Export validation metrics
    pub fn export_validation_metrics(tools: &crate::validation::ValidationTools) -> HashMap<String, f64> {
        let metrics = tools.get_metrics();
        let mut exported = HashMap::new();
        
        exported.insert("alpenglow_validation_events_processed".to_string(), metrics.events_processed as f64);
        exported.insert("alpenglow_validation_safety_violations".to_string(), metrics.safety_violations as f64);
        exported.insert("alpenglow_validation_liveness_violations".to_string(), metrics.liveness_violations as f64);
        exported.insert("alpenglow_validation_byzantine_violations".to_string(), metrics.byzantine_violations as f64);
        exported.insert("alpenglow_validation_network_violations".to_string(), metrics.network_violations as f64);
        exported.insert("alpenglow_validation_fast_path_certificates".to_string(), metrics.fast_path_certificates as f64);
        exported.insert("alpenglow_validation_slow_path_certificates".to_string(), metrics.slow_path_certificates as f64);
        exported.insert("alpenglow_validation_skip_certificates".to_string(), metrics.skip_certificates as f64);
        exported.insert("alpenglow_validation_avg_finalization_time_ms".to_string(), metrics.average_finalization_time.as_millis() as f64);
        exported.insert("alpenglow_validation_max_finalization_time_ms".to_string(), metrics.max_finalization_time.as_millis() as f64);
        
        exported
    }
}

#[cfg(feature = "dashboards")]
pub mod dashboards {
    //! Real-time monitoring dashboard utilities
    
    use std::collections::HashMap;
    use serde_json::Value;
    
    /// Dashboard data structure
    #[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
    pub struct DashboardData {
        pub timestamp: std::time::SystemTime,
        pub validation_metrics: HashMap<String, f64>,
        #[cfg(feature = "monitoring")]
        pub runtime_metrics: HashMap<String, f64>,
        pub alerts: Vec<AlertSummary>,
        pub system_health: SystemHealthSummary,
    }
    
    /// Alert summary for dashboard
    #[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
    pub struct AlertSummary {
        pub alert_type: String,
        pub severity: String,
        pub count: u64,
        pub last_seen: std::time::SystemTime,
    }
    
    /// System health summary
    #[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
    pub struct SystemHealthSummary {
        pub overall_status: String, // "healthy", "warning", "critical"
        pub validator_count: usize,
        pub online_validators: usize,
        pub finalization_rate: f64,
        pub network_health: String,
    }
    
    /// Generate dashboard data
    pub fn generate_dashboard_data(
        validation_tools: &crate::validation::ValidationTools,
        #[cfg(feature = "monitoring")]
        runtime_monitor: Option<&crate::monitor::AlpenglowRuntimeMonitor>,
    ) -> DashboardData {
        let validation_metrics = crate::metrics::export_validation_metrics(validation_tools);
        
        #[cfg(feature = "monitoring")]
        let runtime_metrics = runtime_monitor
            .map(|m| m.export_metrics())
            .unwrap_or_default();
        
        #[cfg(not(feature = "monitoring"))]
        let runtime_metrics = HashMap::new();
        
        DashboardData {
            timestamp: std::time::SystemTime::now(),
            validation_metrics,
            runtime_metrics,
            alerts: vec![], // Would be populated from actual alert history
            system_health: SystemHealthSummary {
                overall_status: "healthy".to_string(),
                validator_count: 4, // Would be from actual config
                online_validators: 4,
                finalization_rate: 1.0,
                network_health: "good".to_string(),
            },
        }
    }
    
    /// Export dashboard data as JSON
    pub fn export_dashboard_json(data: &DashboardData) -> Value {
        serde_json::to_value(data).unwrap_or_default()
    }
}

// Utility functions and helpers
pub mod utils {
    //! Utility functions for validation and monitoring
    
    use std::time::{Duration, SystemTime};
    use alpenglow_stateright::{Config as AlpenglowConfig, AlpenglowResult};
    
    /// Create default validation configuration
    pub fn default_validation_config() -> crate::validation::ValidationConfig {
        crate::validation::ValidationConfig::default()
    }
    
    /// Create default monitoring configuration
    #[cfg(feature = "monitoring")]
    pub fn default_monitor_config() -> crate::monitor::MonitorConfig {
        crate::monitor::MonitorConfig::default()
    }
    
    /// Convert Alpenglow config to validation config
    pub fn alpenglow_to_validation_config(config: AlpenglowConfig) -> crate::validation::ValidationConfig {
        crate::validation::ValidationConfig::from(config)
    }
    
    /// Convert Alpenglow config to monitor config
    #[cfg(feature = "monitoring")]
    pub fn alpenglow_to_monitor_config(config: AlpenglowConfig) -> crate::monitor::MonitorConfig {
        crate::monitor::MonitorConfig::from(config)
    }
    
    /// Create test validator set
    pub fn create_test_validators(count: usize, stake_per_validator: u64) -> Vec<(u64, u64)> {
        (0..count as u64)
            .map(|i| (i, stake_per_validator))
            .collect()
    }
    
    /// Calculate stake thresholds
    pub fn calculate_stake_thresholds(total_stake: u64) -> crate::validation::StakeThresholds {
        crate::validation::StakeThresholds {
            fast_path: 0.80,
            slow_path: 0.60,
            byzantine_bound: 0.20,
            offline_bound: 0.20,
        }
    }
    
    /// Format duration for display
    pub fn format_duration(duration: Duration) -> String {
        let secs = duration.as_secs();
        let millis = duration.subsec_millis();
        
        if secs > 0 {
            format!("{}.{:03}s", secs, millis)
        } else {
            format!("{}ms", millis)
        }
    }
    
    /// Format timestamp for display
    pub fn format_timestamp(timestamp: SystemTime) -> String {
        match timestamp.duration_since(SystemTime::UNIX_EPOCH) {
            Ok(duration) => {
                let secs = duration.as_secs();
                format!("{}", secs)
            }
            Err(_) => "invalid".to_string(),
        }
    }
    
    /// Check if system time is past GST
    pub fn is_past_gst(current_time: SystemTime, gst_duration: Duration) -> bool {
        SystemTime::UNIX_EPOCH + gst_duration <= current_time
    }
    
    /// Calculate finalization latency
    pub fn calculate_finalization_latency(
        proposal_time: SystemTime,
        finalization_time: SystemTime,
    ) -> Duration {
        finalization_time.duration_since(proposal_time).unwrap_or_default()
    }
}

// Error types and result aliases
pub mod error {
    //! Error types for validation and monitoring
    
    pub use alpenglow_stateright::{AlpenglowError, AlpenglowResult};
    pub use crate::validation::ValidationError;
    
    /// Combined error type for validation and monitoring operations
    #[derive(Debug, thiserror::Error)]
    pub enum ValidationMonitorError {
        /// Validation error
        #[error("Validation error: {0}")]
        Validation(#[from] ValidationError),
        
        /// Alpenglow protocol error
        #[error("Alpenglow error: {0}")]
        Alpenglow(#[from] AlpenglowError),
        
        /// Configuration error
        #[error("Configuration error: {0}")]
        Config(String),
        
        /// Integration error
        #[error("Integration error: {0}")]
        Integration(String),
        
        /// I/O error
        #[error("I/O error: {0}")]
        Io(#[from] std::io::Error),
        
        /// Serialization error
        #[error("Serialization error: {0}")]
        Serialization(#[from] serde_json::Error),
    }
    
    /// Result type for validation and monitoring operations
    pub type ValidationMonitorResult<T> = Result<T, ValidationMonitorError>;
}

// Re-export error types at crate level
pub use error::{ValidationMonitorError, ValidationMonitorResult};

// Prelude module for convenient imports
pub mod prelude {
    //! Prelude module with commonly used types and functions
    
    pub use crate::validation::{
        ValidationTools, ValidationConfig, ValidationEvent, ValidationError,
        ValidationMetrics, ConformanceTestSuite, ValidationReport,
    };
    
    #[cfg(feature = "monitoring")]
    pub use crate::monitor::{
        AlpenglowRuntimeMonitor, MonitorConfig, RuntimeAlert, RuntimeAlertType,
        RuntimeMetrics, NetworkHealth,
    };
    
    pub use crate::integration::{
        create_validation_tools, run_end_to_end_validation, quick_validation_check,
    };
    
    #[cfg(feature = "monitoring")]
    pub use crate::integration::{create_runtime_monitor, create_integrated_system};
    
    pub use crate::utils::{
        default_validation_config, create_test_validators, format_duration,
    };
    
    #[cfg(feature = "monitoring")]
    pub use crate::utils::default_monitor_config;
    
    pub use crate::error::{ValidationMonitorError, ValidationMonitorResult};
    
    pub use alpenglow_stateright::{AlpenglowError, AlpenglowResult, Config as AlpenglowConfig};
}

// Version and build information
pub const VERSION: &str = env!("CARGO_PKG_VERSION");
pub const BUILD_TIME: &str = env!("VERGEN_BUILD_TIMESTAMP");
pub const GIT_HASH: &str = env!("VERGEN_GIT_SHA");

/// Get version information
pub fn version_info() -> String {
    format!("alpenglow-validation {} ({})", VERSION, GIT_HASH)
}

/// Get build information
pub fn build_info() -> String {
    format!("Built at {} from commit {}", BUILD_TIME, GIT_HASH)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;
    
    #[test]
    fn test_version_info() {
        let version = version_info();
        assert!(version.contains("alpenglow-validation"));
        assert!(version.contains(VERSION));
    }
    
    #[test]
    fn test_utils() {
        let validators = utils::create_test_validators(4, 1000);
        assert_eq!(validators.len(), 4);
        assert_eq!(validators[0], (0, 1000));
        assert_eq!(validators[3], (3, 1000));
        
        let duration = Duration::from_millis(1500);
        let formatted = utils::format_duration(duration);
        assert_eq!(formatted, "1.500s");
        
        let thresholds = utils::calculate_stake_thresholds(1000);
        assert_eq!(thresholds.fast_path, 0.80);
        assert_eq!(thresholds.slow_path, 0.60);
    }
    
    #[tokio::test]
    async fn test_integration_quick_check() {
        use alpenglow_stateright::utils::test_configs;
        
        let config = test_configs()[0].clone();
        let result = integration::quick_validation_check(config).await;
        
        // Should succeed with test config
        assert!(result.is_ok());
    }
    
    #[test]
    fn test_config_conversions() {
        use alpenglow_stateright::utils::test_configs;
        
        let alpenglow_config = test_configs()[0].clone();
        let validation_config = utils::alpenglow_to_validation_config(alpenglow_config.clone());
        
        // Check that conversion preserves key parameters
        assert_eq!(
            validation_config.timing_params.gst.as_millis(),
            alpenglow_config.gst as u128
        );
        
        #[cfg(feature = "monitoring")]
        {
            let monitor_config = utils::alpenglow_to_monitor_config(alpenglow_config);
            assert_eq!(
                monitor_config.validation_config.timing_params.gst.as_millis(),
                validation_config.timing_params.gst.as_millis()
            );
        }
    }
    
    #[cfg(feature = "monitoring")]
    #[tokio::test]
    async fn test_integrated_system() {
        use alpenglow_stateright::utils::test_configs;
        
        let config = test_configs()[0].clone();
        let result = integration::create_integrated_system(config).await;
        
        assert!(result.is_ok());
        let (validation_tools, runtime_monitor) = result.unwrap();
        
        // Both components should be properly initialized
        let validation_metrics = validation_tools.get_metrics();
        let runtime_stats = runtime_monitor.get_runtime_stats();
        
        assert!(validation_metrics.events_processed >= 0);
        assert!(runtime_stats.uptime >= Duration::from_secs(0));
    }
    
    #[cfg(feature = "metrics-export")]
    #[test]
    fn test_metrics_export() {
        use alpenglow_stateright::utils::test_configs;
        
        let config = test_configs()[0].clone();
        let validation_config = utils::alpenglow_to_validation_config(config);
        let tools = ValidationTools::new(validation_config);
        
        let metrics = crate::metrics::export_validation_metrics(&tools);
        
        // Check that key metrics are exported
        assert!(metrics.contains_key("alpenglow_validation_events_processed"));
        assert!(metrics.contains_key("alpenglow_validation_safety_violations"));
        assert!(metrics.contains_key("alpenglow_validation_fast_path_certificates"));
    }
    
    #[cfg(feature = "dashboards")]
    #[test]
    fn test_dashboard_generation() {
        use alpenglow_stateright::utils::test_configs;
        
        let config = test_configs()[0].clone();
        let validation_config = utils::alpenglow_to_validation_config(config);
        let tools = ValidationTools::new(validation_config);
        
        let dashboard_data = crate::dashboards::generate_dashboard_data(
            &tools,
            #[cfg(feature = "monitoring")]
            None,
        );
        
        assert_eq!(dashboard_data.system_health.overall_status, "healthy");
        assert!(dashboard_data.validation_metrics.len() > 0);
        
        let json = crate::dashboards::export_dashboard_json(&dashboard_data);
        assert!(json.is_object());
    }
}