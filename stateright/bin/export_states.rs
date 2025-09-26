// Author: Ayush Srivastava
//! Utility binary for exporting sample states from Stateright verification
//! 
//! This tool exports representative states from Stateright model checking
//! runs in formats suitable for TLA+ cross-validation and analysis.

use alpenglow_stateright::{
    AlpenglowState, Config, ModelChecker, TlaCompatible,
    AlpenglowResult, AlpenglowError, StateInfo, VerificationResult,
};
use clap::{Arg, Command};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;

/// Configuration for state export
#[derive(Debug, Clone)]
struct ExportConfig {
    pub config: Config,
    pub output_dir: PathBuf,
    pub format: ExportFormat,
    pub max_states: usize,
    pub include_traces: bool,
    pub filter_properties: Vec<String>,
    pub export_mode: ExportMode,
}

/// Supported export formats
#[derive(Debug, Clone)]
enum ExportFormat {
    Json,
    TlaPlus,
    Csv,
    All,
}

/// Export modes for different use cases
#[derive(Debug, Clone)]
enum ExportMode {
    /// Export initial states for TLA+ model initialization
    InitialStates,
    /// Export states that violate specific properties
    ViolatingStates,
    /// Export representative states from successful runs
    RepresentativeStates,
    /// Export complete state traces
    CompleteTraces,
    /// Export states for specific scenarios
    ScenarioStates(String),
}

/// Exported state information
#[derive(Debug, Clone)]
struct ExportedState {
    pub state_id: String,
    pub step_number: usize,
    pub state_type: String,
    pub alpenglow_state: AlpenglowState,
    pub properties_satisfied: Vec<String>,
    pub properties_violated: Vec<String>,
    pub metadata: HashMap<String, Value>,
}

/// State export utility
struct StateExporter {
    config: ExportConfig,
    property_mapping: Option<Value>,
}

impl StateExporter {
    /// Create a new state exporter
    fn new(config: ExportConfig) -> AlpenglowResult<Self> {
        // Load property mapping if available
        let property_mapping = Self::load_property_mapping();
        
        Ok(Self {
            config,
            property_mapping,
        })
    }
    
    /// Load property mapping file
    fn load_property_mapping() -> Option<Value> {
        let mapping_paths = vec![
            PathBuf::from("../scripts/property_mapping.json"),
            PathBuf::from("../../scripts/property_mapping.json"),
            PathBuf::from("scripts/property_mapping.json"),
        ];
        
        for path in mapping_paths {
            if path.exists() {
                if let Ok(content) = fs::read_to_string(&path) {
                    if let Ok(mapping) = serde_json::from_str(&content) {
                        return Some(mapping);
                    }
                }
            }
        }
        
        None
    }
    
    /// Run model checking and collect states for export
    fn collect_states(&self) -> AlpenglowResult<Vec<ExportedState>> {
        let mut model_checker = ModelChecker::new(self.config.config.clone());
        
        // Configure model checker for state collection
        model_checker.enable_state_collection();
        model_checker.set_max_states(self.config.max_states);
        
        match &self.config.export_mode {
            ExportMode::InitialStates => {
                model_checker.set_exploration_depth(1);
            }
            ExportMode::ViolatingStates => {
                model_checker.enable_violation_collection();
            }
            ExportMode::RepresentativeStates => {
                model_checker.enable_representative_sampling();
            }
            ExportMode::CompleteTraces => {
                model_checker.enable_trace_collection();
            }
            ExportMode::ScenarioStates(scenario) => {
                model_checker.set_scenario_filter(scenario.clone());
            }
        }
        
        // Run verification
        println!("Running model checking to collect states...");
        let verification_result = model_checker.verify_model()?;
        
        // Extract states from verification result
        let mut exported_states = Vec::new();
        
        for (step_num, state_info) in verification_result.collected_states.iter().enumerate() {
            let state_id = format!("state_{:06}", step_num);
            
            // Validate invariants for this state
            let (satisfied_props, violated_props) = self.validate_state_properties(&state_info.state)?;
            
            let exported_state = ExportedState {
                state_id,
                step_number: step_num,
                state_type: state_info.state_type.clone(),
                alpenglow_state: state_info.state.clone(),
                properties_satisfied: satisfied_props,
                properties_violated: violated_props,
                metadata: state_info.metadata.clone(),
            };
            
            // Apply property filters if specified
            if self.should_include_state(&exported_state) {
                exported_states.push(exported_state);
            }
        }
        
        println!("Collected {} states for export", exported_states.len());
        Ok(exported_states)
    }
    
    /// Validate properties for a specific state
    fn validate_state_properties(&self, state: &AlpenglowState) -> AlpenglowResult<(Vec<String>, Vec<String>)> {
        let mut satisfied = Vec::new();
        let mut violated = Vec::new();
        
        // Validate TLA+ invariants on the main state
        match state.validate_tla_invariants() {
            Ok(violations) => {
                if violations.is_empty() {
                    satisfied.push("TlaInvariants".to_string());
                } else {
                    violated.push("TlaInvariants".to_string());
                }
            }
            Err(_) => violated.push("TlaInvariants".to_string()),
        }
        
        // Check individual properties using the properties module
        use alpenglow_stateright::properties;
        
        // Safety properties
        if properties::safety_no_conflicting_finalization(state) {
            satisfied.push("VotorSafety".to_string());
        } else {
            violated.push("VotorSafety".to_string());
        }
        
        if properties::certificate_validity(state, &self.config.config) {
            satisfied.push("CertificateValidity".to_string());
        } else {
            violated.push("CertificateValidity".to_string());
        }
        
        if properties::bandwidth_safety(state, &self.config.config) {
            satisfied.push("BandwidthSafety".to_string());
        } else {
            violated.push("BandwidthSafety".to_string());
        }
        
        if properties::erasure_coding_validity(state, &self.config.config) {
            satisfied.push("ErasureCodingValidity".to_string());
        } else {
            violated.push("ErasureCodingValidity".to_string());
        }
        
        // Liveness properties
        if properties::liveness_eventual_progress(state) {
            satisfied.push("LivenessProgress".to_string());
        } else {
            violated.push("LivenessProgress".to_string());
        }
        
        if properties::progress_guarantee(state, &self.config.config) {
            satisfied.push("ProgressGuarantee".to_string());
        } else {
            violated.push("ProgressGuarantee".to_string());
        }
        
        // Byzantine resilience
        if properties::byzantine_resilience(state, &self.config.config) {
            satisfied.push("ByzantineResilience".to_string());
        } else {
            violated.push("ByzantineResilience".to_string());
        }
        
        Ok((satisfied, violated))
    }
    
    /// Check if a state should be included based on filters
    fn should_include_state(&self, state: &ExportedState) -> bool {
        if self.config.filter_properties.is_empty() {
            return true;
        }
        
        // Include state if it satisfies or violates any of the filtered properties
        for filter_prop in &self.config.filter_properties {
            if state.properties_satisfied.contains(filter_prop) || 
               state.properties_violated.contains(filter_prop) {
                return true;
            }
        }
        
        false
    }
    
    /// Export states in the specified format
    fn export_states(&self, states: &[ExportedState]) -> AlpenglowResult<()> {
        fs::create_dir_all(&self.config.output_dir)
            .map_err(|e| AlpenglowError::Io(format!("Failed to create output directory: {}", e)))?;
        
        match self.config.format {
            ExportFormat::Json => self.export_json(states)?,
            ExportFormat::TlaPlus => self.export_tla_plus(states)?,
            ExportFormat::Csv => self.export_csv(states)?,
            ExportFormat::All => {
                self.export_json(states)?;
                self.export_tla_plus(states)?;
                self.export_csv(states)?;
            }
        }
        
        // Export metadata
        self.export_metadata(states)?;
        
        Ok(())
    }
    
    /// Export states as JSON
    fn export_json(&self, states: &[ExportedState]) -> AlpenglowResult<()> {
        let json_output = json!({
            "export_info": {
                "timestamp": chrono::Utc::now().to_rfc3339(),
                "config": format!("{:?}", self.config.config),
                "export_mode": format!("{:?}", self.config.export_mode),
                "total_states": states.len(),
                "property_mapping_available": self.property_mapping.is_some()
            },
            "states": states.iter().map(|state| {
                json!({
                    "state_id": state.state_id,
                    "step_number": state.step_number,
                    "state_type": state.state_type,
                    "alpenglow_state": state.alpenglow_state.export_tla_state().unwrap_or_default(),
                    "properties": {
                        "satisfied": state.properties_satisfied,
                        "violated": state.properties_violated
                    },
                    "metadata": state.metadata
                })
            }).collect::<Vec<_>>()
        });
        
        let output_file = self.config.output_dir.join("exported_states.json");
        fs::write(&output_file, serde_json::to_string_pretty(&json_output)?)
            .map_err(|e| AlpenglowError::Io(format!("Failed to write JSON file: {}", e)))?;
        
        println!("Exported {} states to JSON: {}", states.len(), output_file.display());
        Ok(())
    }
    
    /// Export states in TLA+ format
    fn export_tla_plus(&self, states: &[ExportedState]) -> AlpenglowResult<()> {
        let mut tla_content = String::new();
        
        // TLA+ module header
        tla_content.push_str("---- MODULE ExportedStates ----\n");
        tla_content.push_str("EXTENDS Integers, Sequences, FiniteSets\n\n");
        
        // Export constants
        tla_content.push_str("CONSTANTS\n");
        tla_content.push_str("    N,  \\* Number of nodes\n");
        tla_content.push_str("    F   \\* Number of Byzantine nodes\n\n");
        
        // Export state definitions
        tla_content.push_str("\\* Exported states from Stateright verification\n");
        tla_content.push_str("ExportedStates == {\n");
        
        for (i, state) in states.iter().enumerate() {
            let tla_repr = state.alpenglow_state.export_tla_state().unwrap_or_default();
            
            tla_content.push_str(&format!("    \\* State {}: {}\n", i + 1, state.state_id));
            tla_content.push_str(&format!("    {},\n", self.format_tla_state(&tla_repr)?));
        }
        
        // Remove trailing comma and close set
        if !states.is_empty() {
            tla_content.pop(); // Remove last comma
            tla_content.pop(); // Remove last newline
            tla_content.push('\n');
        }
        tla_content.push_str("}\n\n");
        
        // Add property definitions if property mapping is available
        if let Some(mapping) = &self.property_mapping {
            tla_content.push_str("\\* Property mappings from Rust to TLA+\n");
            if let Some(safety_props) = mapping["mappings"]["safety_properties"]["rust_to_tla"].as_object() {
                for (rust_prop, tla_prop) in safety_props {
                    tla_content.push_str(&format!("\\* {} -> {}\n", rust_prop, tla_prop.as_str().unwrap_or("Unknown")));
                }
            }
            tla_content.push('\n');
        }
        
        tla_content.push_str("====\n");
        
        let output_file = self.config.output_dir.join("ExportedStates.tla");
        fs::write(&output_file, tla_content)
            .map_err(|e| AlpenglowError::Io(format!("Failed to write TLA+ file: {}", e)))?;
        
        println!("Exported {} states to TLA+: {}", states.len(), output_file.display());
        Ok(())
    }
    
    /// Format a state for TLA+ representation
    fn format_tla_state(&self, tla_repr: &Value) -> AlpenglowResult<String> {
        // Convert JSON representation to TLA+ record format
        let mut tla_state = String::new();
        tla_state.push('[');
        
        if let Some(obj) = tla_repr.as_object() {
            let mut first = true;
            for (key, value) in obj {
                if !first {
                    tla_state.push_str(", ");
                }
                first = false;
                
                tla_state.push_str(&format!("{} |-> {}", key, self.format_tla_value(value)?));
            }
        }
        
        tla_state.push(']');
        Ok(tla_state)
    }
    
    /// Format a JSON value for TLA+ representation
    fn format_tla_value(&self, value: &Value) -> AlpenglowResult<String> {
        match value {
            Value::Null => Ok("NULL".to_string()),
            Value::Bool(b) => Ok(if *b { "TRUE" } else { "FALSE" }),
            Value::Number(n) => Ok(n.to_string()),
            Value::String(s) => Ok(format!("\"{}\"", s)),
            Value::Array(arr) => {
                let elements: Result<Vec<_>, _> = arr.iter()
                    .map(|v| self.format_tla_value(v))
                    .collect();
                Ok(format!("<<{}>>", elements?.join(", ")))
            }
            Value::Object(obj) => {
                let mut record = String::new();
                record.push('[');
                let mut first = true;
                for (key, val) in obj {
                    if !first {
                        record.push_str(", ");
                    }
                    first = false;
                    record.push_str(&format!("{} |-> {}", key, self.format_tla_value(val)?));
                }
                record.push(']');
                Ok(record)
            }
        }
    }
    
    /// Export states as CSV
    fn export_csv(&self, states: &[ExportedState]) -> AlpenglowResult<()> {
        let mut csv_content = String::new();
        
        // CSV header
        csv_content.push_str("state_id,step_number,state_type,properties_satisfied,properties_violated,votor_view,rotor_epoch,network_partition\n");
        
        // CSV rows
        for state in states {
            let satisfied_props = state.properties_satisfied.join(";");
            let violated_props = state.properties_violated.join(";");
            
            // Extract key state information from the flattened structure
            let votor_view = state.alpenglow_state.votor_view.values()
                .max()
                .map(|v| v.to_string())
                .unwrap_or_else(|| "N/A".to_string());
            
            let rotor_epoch = state.alpenglow_state.current_slot.to_string();
            
            let network_partition = if state.alpenglow_state.network_partitions.is_empty() {
                "false"
            } else {
                "true"
            };
            
            csv_content.push_str(&format!(
                "{},{},{},\"{}\",\"{}\",{},{},{}\n",
                state.state_id,
                state.step_number,
                state.state_type,
                satisfied_props,
                violated_props,
                votor_view,
                rotor_epoch,
                network_partition
            ));
        }
        
        let output_file = self.config.output_dir.join("exported_states.csv");
        fs::write(&output_file, csv_content)
            .map_err(|e| AlpenglowError::Io(format!("Failed to write CSV file: {}", e)))?;
        
        println!("Exported {} states to CSV: {}", states.len(), output_file.display());
        Ok(())
    }
    
    /// Export metadata about the export process
    fn export_metadata(&self, states: &[ExportedState]) -> AlpenglowResult<()> {
        let metadata = json!({
            "export_summary": {
                "timestamp": chrono::Utc::now().to_rfc3339(),
                "total_states_exported": states.len(),
                "export_config": {
                    "format": format!("{:?}", self.config.format),
                    "mode": format!("{:?}", self.config.export_mode),
                    "max_states": self.config.max_states,
                    "include_traces": self.config.include_traces,
                    "filter_properties": self.config.filter_properties
                },
                "model_config": format!("{:?}", self.config.config),
                "property_mapping_available": self.property_mapping.is_some()
            },
            "state_statistics": {
                "by_type": self.get_state_type_statistics(states),
                "by_properties": self.get_property_statistics(states)
            },
            "files_generated": self.get_generated_files()
        });
        
        let metadata_file = self.config.output_dir.join("export_metadata.json");
        fs::write(&metadata_file, serde_json::to_string_pretty(&metadata)?)
            .map_err(|e| AlpenglowError::Io(format!("Failed to write metadata: {}", e)))?;
        
        println!("Export metadata saved to: {}", metadata_file.display());
        Ok(())
    }
    
    /// Get statistics about state types
    fn get_state_type_statistics(&self, states: &[ExportedState]) -> HashMap<String, usize> {
        let mut stats = HashMap::new();
        for state in states {
            *stats.entry(state.state_type.clone()).or_insert(0) += 1;
        }
        stats
    }
    
    /// Get statistics about properties
    fn get_property_statistics(&self, states: &[ExportedState]) -> HashMap<String, HashMap<String, usize>> {
        let mut stats = HashMap::new();
        
        for state in states {
            for prop in &state.properties_satisfied {
                *stats.entry(prop.clone()).or_insert_with(HashMap::new).entry("satisfied".to_string()).or_insert(0) += 1;
            }
            for prop in &state.properties_violated {
                *stats.entry(prop.clone()).or_insert_with(HashMap::new).entry("violated".to_string()).or_insert(0) += 1;
            }
        }
        
        stats
    }
    
    /// Get list of generated files
    fn get_generated_files(&self) -> Vec<String> {
        let mut files = vec!["export_metadata.json".to_string()];
        
        match self.config.format {
            ExportFormat::Json => files.push("exported_states.json".to_string()),
            ExportFormat::TlaPlus => files.push("ExportedStates.tla".to_string()),
            ExportFormat::Csv => files.push("exported_states.csv".to_string()),
            ExportFormat::All => {
                files.extend_from_slice(&[
                    "exported_states.json".to_string(),
                    "ExportedStates.tla".to_string(),
                    "exported_states.csv".to_string(),
                ]);
            }
        }
        
        files
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let matches = Command::new("export_states")
        .version("1.0.0")
        .author("Alpenglow Team")
        .about("Export sample states from Stateright verification for TLA+ cross-validation")
        .arg(Arg::new("config")
            .short('c')
            .long("config")
            .value_name("CONFIG")
            .help("Model configuration (small, medium, large, byzantine)")
            .default_value("small"))
        .arg(Arg::new("output")
            .short('o')
            .long("output")
            .value_name("DIR")
            .help("Output directory for exported states")
            .default_value("./exported_states"))
        .arg(Arg::new("format")
            .short('f')
            .long("format")
            .value_name("FORMAT")
            .help("Export format (json, tla, csv, all)")
            .default_value("json"))
        .arg(Arg::new("mode")
            .short('m')
            .long("mode")
            .value_name("MODE")
            .help("Export mode (initial, violating, representative, traces, scenario)")
            .default_value("representative"))
        .arg(Arg::new("max-states")
            .long("max-states")
            .value_name("N")
            .help("Maximum number of states to export")
            .default_value("100"))
        .arg(Arg::new("properties")
            .short('p')
            .long("properties")
            .value_name("PROPS")
            .help("Filter by properties (comma-separated)")
            .use_value_delimiter(true))
        .arg(Arg::new("scenario")
            .long("scenario")
            .value_name("SCENARIO")
            .help("Scenario name for scenario mode"))
        .arg(Arg::new("traces")
            .long("include-traces")
            .help("Include execution traces")
            .action(clap::ArgAction::SetTrue))
        .get_matches();
    
    // Parse configuration
    let config_name = matches.get_one::<String>("config").unwrap();
    let config = match config_name.as_str() {
        "small" => Config::new().with_validators(3),
        "medium" => Config::new().with_validators(7),
        "large" => Config::new().with_validators(15),
        "byzantine" => Config::new().with_validators(4).with_byzantine_threshold(1),
        _ => {
            eprintln!("Unknown configuration: {}", config_name);
            std::process::exit(1);
        }
    };
    
    // Parse format
    let format_str = matches.get_one::<String>("format").unwrap();
    let format = match format_str.as_str() {
        "json" => ExportFormat::Json,
        "tla" => ExportFormat::TlaPlus,
        "csv" => ExportFormat::Csv,
        "all" => ExportFormat::All,
        _ => {
            eprintln!("Unknown format: {}", format_str);
            std::process::exit(1);
        }
    };
    
    // Parse mode
    let mode_str = matches.get_one::<String>("mode").unwrap();
    let export_mode = match mode_str.as_str() {
        "initial" => ExportMode::InitialStates,
        "violating" => ExportMode::ViolatingStates,
        "representative" => ExportMode::RepresentativeStates,
        "traces" => ExportMode::CompleteTraces,
        "scenario" => {
            let scenario = matches.get_one::<String>("scenario")
                .ok_or("Scenario name required for scenario mode")?;
            ExportMode::ScenarioStates(scenario.clone())
        }
        _ => {
            eprintln!("Unknown mode: {}", mode_str);
            std::process::exit(1);
        }
    };
    
    // Parse other options
    let output_dir = PathBuf::from(matches.get_one::<String>("output").unwrap());
    let max_states: usize = matches.get_one::<String>("max-states").unwrap().parse()?;
    let include_traces = matches.get_flag("traces");
    
    let filter_properties: Vec<String> = matches.get_many::<String>("properties")
        .map(|vals| vals.map(|s| s.to_string()).collect())
        .unwrap_or_default();
    
    // Create export configuration
    let export_config = ExportConfig {
        config,
        output_dir,
        format,
        max_states,
        include_traces,
        filter_properties,
        export_mode,
    };
    
    // Run export
    println!("Starting state export with configuration: {:?}", config_name);
    println!("Export mode: {:?}", export_config.export_mode);
    println!("Output format: {:?}", export_config.format);
    println!("Output directory: {}", export_config.output_dir.display());
    
    let exporter = StateExporter::new(export_config)?;
    let states = exporter.collect_states()?;
    exporter.export_states(&states)?;
    
    println!("State export completed successfully!");
    println!("Exported {} states to {}", states.len(), exporter.config.output_dir.display());
    
    Ok(())
}
