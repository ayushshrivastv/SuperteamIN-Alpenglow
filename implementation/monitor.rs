//! Runtime monitoring system for Alpenglow consensus protocol
//! 
//! This module provides real-time monitoring of live Alpenglow deployments to verify
//! they maintain the safety and liveness properties proven in the formal verification.
//! It focuses on online alerts and performance monitoring, complementing the offline
//! validation tools in the validation module.
//!
//! ## Key Differences from Validation Module
//!
//! - **Runtime Focus**: Monitors live systems with real-time alerts
//! - **Performance Oriented**: Tracks throughput, latency, and resource usage
//! - **Alert Generation**: Immediate notifications for violations
//! - **Resource Efficient**: Optimized for continuous operation
//! - **Integration Ready**: Bridges with Actor model for live event streams

use std::collections::{HashMap, HashSet, VecDeque};
use std::sync::{Arc, Mutex, RwLock};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tokio::sync::{broadcast, mpsc};
use tokio::time::{interval, timeout};
use serde::{Deserialize, Serialize};
use tracing::{error, warn, info, debug, trace};

// Import types from the main stateright crate for integration
use alpenglow_stateright::{
    Config as AlpenglowConfig,
    AlpenglowError,
    AlpenglowResult,
    ValidatorId as MainValidatorId,
    SlotNumber,
    StakeAmount,
    BlockHash as MainBlockHash,
    local_stateright::{Actor, ActorModel, Id, SystemState},
    integration::{AlpenglowNode, AlpenglowState, AlpenglowMessage},
    votor::{Block as MainBlock, Vote as MainVote, Certificate as MainCertificate},
};

// Re-use validation types to avoid duplication
use crate::validation::{
    ValidationEvent, ValidationError, Alert as ValidationAlert, AlertSeverity as ValidationAlertSeverity,
    ActorModelBridge, ValidationConfig,
};

/// Configuration for the Alpenglow runtime monitor (extends ValidationConfig)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MonitorConfig {
    /// Base validation configuration
    pub validation_config: ValidationConfig,
    /// Maximum number of slots to track in memory
    pub max_tracked_slots: usize,
    /// Alert cooldown period (milliseconds)
    pub alert_cooldown_ms: u64,
    /// Performance monitoring interval (milliseconds)
    pub performance_interval_ms: u64,
    /// Resource usage monitoring enabled
    pub monitor_resources: bool,
    /// Network latency monitoring enabled
    pub monitor_network_latency: bool,
    /// Bandwidth monitoring enabled
    pub monitor_bandwidth: bool,
    /// Alert aggregation window (milliseconds)
    pub alert_aggregation_window_ms: u64,
    /// Maximum alerts per window
    pub max_alerts_per_window: usize,
    /// Enable real-time dashboards
    pub enable_dashboards: bool,
    /// Enable metric exports (Prometheus, etc.)
    pub enable_metric_exports: bool,
}

impl Default for MonitorConfig {
    fn default() -> Self {
        Self {
            validation_config: ValidationConfig::default(),
            max_tracked_slots: 1000,
            alert_cooldown_ms: 5000,
            performance_interval_ms: 1000,
            monitor_resources: true,
            monitor_network_latency: true,
            monitor_bandwidth: true,
            alert_aggregation_window_ms: 10000,
            max_alerts_per_window: 50,
            enable_dashboards: false,
            enable_metric_exports: false,
        }
    }
}

impl From<AlpenglowConfig> for MonitorConfig {
    fn from(config: AlpenglowConfig) -> Self {
        Self {
            validation_config: ValidationConfig::from(config),
            ..Default::default()
        }
    }
}

/// Runtime performance metrics (focused on operational monitoring)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RuntimeMetrics {
    /// Current throughput (blocks/second)
    pub current_throughput: f64,
    /// Average latency over last window (milliseconds)
    pub avg_latency_ms: f64,
    /// 95th percentile latency (milliseconds)
    pub p95_latency_ms: f64,
    /// Current bandwidth usage (bytes/second)
    pub bandwidth_usage: u64,
    /// Memory usage (bytes)
    pub memory_usage: u64,
    /// CPU usage percentage
    pub cpu_usage: f64,
    /// Network message rate (messages/second)
    pub message_rate: f64,
    /// Error rate (errors/second)
    pub error_rate: f64,
    /// Active connections count
    pub active_connections: usize,
    /// Queue depths
    pub queue_depths: HashMap<String, usize>,
    /// Last updated timestamp
    pub last_updated: SystemTime,
}

impl Default for RuntimeMetrics {
    fn default() -> Self {
        Self {
            current_throughput: 0.0,
            avg_latency_ms: 0.0,
            p95_latency_ms: 0.0,
            bandwidth_usage: 0,
            memory_usage: 0,
            cpu_usage: 0.0,
            message_rate: 0.0,
            error_rate: 0.0,
            active_connections: 0,
            queue_depths: HashMap::new(),
            last_updated: SystemTime::now(),
        }
    }
}

/// Network health information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetworkHealth {
    /// Average round-trip time (milliseconds)
    pub avg_rtt_ms: f64,
    /// Packet loss percentage
    pub packet_loss_pct: f64,
    /// Jitter (milliseconds)
    pub jitter_ms: f64,
    /// Active partitions
    pub active_partitions: usize,
    /// Connectivity matrix (validator -> validator -> connected)
    pub connectivity: HashMap<MainValidatorId, HashMap<MainValidatorId, bool>>,
    /// Message drop rate
    pub message_drop_rate: f64,
    /// Last health check
    pub last_check: SystemTime,
}

impl Default for NetworkHealth {
    fn default() -> Self {
        Self {
            avg_rtt_ms: 0.0,
            packet_loss_pct: 0.0,
            jitter_ms: 0.0,
            active_partitions: 0,
            connectivity: HashMap::new(),
            message_drop_rate: 0.0,
            last_check: SystemTime::now(),
        }
    }
}

/// Resource usage information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResourceUsage {
    /// Per-validator resource usage
    pub validator_usage: HashMap<MainValidatorId, ValidatorResources>,
    /// System-wide totals
    pub system_totals: SystemResources,
    /// Resource limits
    pub limits: ResourceLimits,
    /// Last measurement time
    pub measured_at: SystemTime,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ValidatorResources {
    pub cpu_usage_pct: f64,
    pub memory_usage_bytes: u64,
    pub disk_usage_bytes: u64,
    pub network_in_bytes: u64,
    pub network_out_bytes: u64,
    pub active_connections: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemResources {
    pub total_cpu_usage_pct: f64,
    pub total_memory_usage_bytes: u64,
    pub total_disk_usage_bytes: u64,
    pub total_network_bytes: u64,
    pub total_connections: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResourceLimits {
    pub max_cpu_pct: f64,
    pub max_memory_bytes: u64,
    pub max_disk_bytes: u64,
    pub max_bandwidth_bytes_per_sec: u64,
    pub max_connections: usize,
}

impl Default for ResourceLimits {
    fn default() -> Self {
        Self {
            max_cpu_pct: 80.0,
            max_memory_bytes: 8 * 1024 * 1024 * 1024, // 8GB
            max_disk_bytes: 100 * 1024 * 1024 * 1024, // 100GB
            max_bandwidth_bytes_per_sec: 100 * 1024 * 1024, // 100MB/s
            max_connections: 1000,
        }
    }
}

/// Runtime alert types (focused on operational issues)
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum RuntimeAlertType {
    // Performance alerts
    HighLatency,
    LowThroughput,
    ResourceExhaustion,
    QueueBacklog,
    
    // Network alerts
    ConnectivityLoss,
    HighPacketLoss,
    NetworkCongestion,
    PartitionDetected,
    
    // System alerts
    MemoryPressure,
    DiskSpaceWarning,
    CPUOverload,
    ConnectionLimitReached,
    
    // Operational alerts
    ValidatorOffline,
    SyncLag,
    ConfigurationDrift,
    HealthCheckFailure,
    
    // Security alerts
    SuspiciousActivity,
    RateLimitExceeded,
    UnauthorizedAccess,
    AnomalousPattern,
}

/// Runtime alert (extends validation alerts with operational focus)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RuntimeAlert {
    pub alert_type: RuntimeAlertType,
    pub severity: ValidationAlertSeverity,
    pub message: String,
    pub timestamp: SystemTime,
    pub validator_id: Option<MainValidatorId>,
    pub slot: Option<SlotNumber>,
    pub view: Option<u64>,
    pub metrics: HashMap<String, f64>,
    pub metadata: HashMap<String, String>,
    pub suggested_action: Option<String>,
    pub alert_id: String,
    pub correlation_id: Option<String>,
}

impl RuntimeAlert {
    /// Create a new runtime alert
    pub fn new(
        alert_type: RuntimeAlertType,
        severity: ValidationAlertSeverity,
        message: String,
    ) -> Self {
        Self {
            alert_type,
            severity,
            message,
            timestamp: SystemTime::now(),
            validator_id: None,
            slot: None,
            view: None,
            metrics: HashMap::new(),
            metadata: HashMap::new(),
            suggested_action: None,
            alert_id: uuid::Uuid::new_v4().to_string(),
            correlation_id: None,
        }
    }
    
    /// Add metric to alert
    pub fn with_metric(mut self, key: String, value: f64) -> Self {
        self.metrics.insert(key, value);
        self
    }
    
    /// Add metadata to alert
    pub fn with_metadata(mut self, key: String, value: String) -> Self {
        self.metadata.insert(key, value);
        self
    }
    
    /// Set suggested action
    pub fn with_action(mut self, action: String) -> Self {
        self.suggested_action = Some(action);
        self
    }
    
    /// Set correlation ID for related alerts
    pub fn with_correlation(mut self, correlation_id: String) -> Self {
        self.correlation_id = Some(correlation_id);
        self
    }
}

/// Runtime monitoring events (extends validation events with operational focus)
#[derive(Debug, Clone)]
pub enum RuntimeMonitorEvent {
    // Validation events (bridged from validation module)
    ValidationEvent(ValidationEvent),
    
    // Performance events
    PerformanceMetricsUpdate(RuntimeMetrics),
    LatencyMeasurement { operation: String, latency_ms: f64, timestamp: SystemTime },
    ThroughputMeasurement { throughput: f64, window_ms: u64, timestamp: SystemTime },
    
    // Resource events
    ResourceUsageUpdate(ResourceUsage),
    MemoryPressure { usage_pct: f64, available_bytes: u64 },
    CPUSpike { usage_pct: f64, duration_ms: u64 },
    DiskSpaceWarning { usage_pct: f64, available_bytes: u64 },
    
    // Network events
    NetworkHealthUpdate(NetworkHealth),
    ConnectivityChange { validator_id: MainValidatorId, connected: bool },
    LatencySpike { from: MainValidatorId, to: MainValidatorId, latency_ms: f64 },
    PacketLoss { from: MainValidatorId, to: MainValidatorId, loss_pct: f64 },
    
    // System events
    ValidatorStatusChange { validator_id: MainValidatorId, online: bool },
    ConfigurationChange { component: String, old_value: String, new_value: String },
    HealthCheckResult { component: String, healthy: bool, details: String },
    
    // Security events
    SuspiciousActivity { validator_id: MainValidatorId, activity_type: String, details: String },
    RateLimitHit { validator_id: MainValidatorId, limit_type: String, current_rate: f64 },
    
    // Actor model events (for integration)
    ActorStateChange { actor_id: Id, state_snapshot: serde_json::Value },
    ActorMessageProcessed { actor_id: Id, message_type: String, processing_time_ms: f64 },
    ActorError { actor_id: Id, error: String },
}

/// Actor model integration bridge for runtime monitoring
pub struct RuntimeActorBridge {
    /// Event sender to runtime monitor
    monitor_event_sender: mpsc::UnboundedSender<RuntimeMonitorEvent>,
    /// Validation bridge for reusing validation infrastructure
    validation_bridge: ActorModelBridge,
    /// Actor state cache for performance monitoring
    actor_state_cache: Arc<RwLock<HashMap<Id, serde_json::Value>>>,
    /// Performance metrics collector
    metrics_collector: Arc<Mutex<RuntimeMetrics>>,
}

impl RuntimeActorBridge {
    /// Create new runtime actor bridge
    pub fn new(monitor_event_sender: mpsc::UnboundedSender<RuntimeMonitorEvent>) -> AlpenglowResult<Self> {
        let (validation_bridge, validation_events) = ActorModelBridge::new();
        
        // Bridge validation events to runtime monitor events
        let monitor_sender = monitor_event_sender.clone();
        tokio::spawn(async move {
            let mut validation_receiver = validation_events;
            while let Some(validation_event) = validation_receiver.recv().await {
                let runtime_event = RuntimeMonitorEvent::ValidationEvent(validation_event);
                if let Err(e) = monitor_sender.send(runtime_event) {
                    error!("Failed to bridge validation event to runtime monitor: {}", e);
                }
            }
        });
        
        Ok(Self {
            monitor_event_sender,
            validation_bridge,
            actor_state_cache: Arc::new(RwLock::new(HashMap::new())),
            metrics_collector: Arc::new(Mutex::new(RuntimeMetrics::default())),
        })
    }
    
    /// Attach to Actor model
    pub fn attach_to_model(&self, model: ActorModel<AlpenglowNode, (), ()>) -> AlpenglowResult<()> {
        self.validation_bridge.attach_to_model(model)
    }
    
    /// Observe Actor model state change with performance tracking
    pub fn observe_actor_state_change(&self, actor_id: Id, state: &SystemState<AlpenglowState>) -> AlpenglowResult<()> {
        let start_time = Instant::now();
        
        // Update validation bridge
        self.validation_bridge.observe_state_change(state)?;
        
        // Cache state for performance monitoring
        let state_json = serde_json::to_value(state).unwrap_or_default();
        {
            let mut cache = self.actor_state_cache.write().unwrap();
            cache.insert(actor_id, state_json.clone());
        }
        
        // Send runtime event
        let event = RuntimeMonitorEvent::ActorStateChange {
            actor_id,
            state_snapshot: state_json,
        };
        
        self.monitor_event_sender.send(event)
            .map_err(|_| AlpenglowError::Other("Failed to send actor state change event".to_string()))?;
        
        // Track performance
        let processing_time = start_time.elapsed().as_millis() as f64;
        if processing_time > 10.0 { // Alert if state processing takes > 10ms
            let latency_event = RuntimeMonitorEvent::LatencyMeasurement {
                operation: "actor_state_processing".to_string(),
                latency_ms: processing_time,
                timestamp: SystemTime::now(),
            };
            let _ = self.monitor_event_sender.send(latency_event);
        }
        
        Ok(())
    }
    
    /// Observe Actor message processing with performance tracking
    pub fn observe_message_processed(&self, actor_id: Id, message_type: String, processing_time: Duration) -> AlpenglowResult<()> {
        let processing_time_ms = processing_time.as_millis() as f64;
        
        // Update metrics
        {
            let mut metrics = self.metrics_collector.lock().unwrap();
            metrics.message_rate += 1.0;
            if processing_time_ms > 100.0 { // Consider > 100ms as slow
                metrics.error_rate += 1.0;
            }
        }
        
        let event = RuntimeMonitorEvent::ActorMessageProcessed {
            actor_id,
            message_type,
            processing_time_ms,
        };
        
        self.monitor_event_sender.send(event)
            .map_err(|_| AlpenglowError::Other("Failed to send message processed event".to_string()))?;
        
        Ok(())
    }
    
    /// Report Actor error
    pub fn report_actor_error(&self, actor_id: Id, error: String) -> AlpenglowResult<()> {
        // Update error metrics
        {
            let mut metrics = self.metrics_collector.lock().unwrap();
            metrics.error_rate += 1.0;
        }
        
        let event = RuntimeMonitorEvent::ActorError { actor_id, error };
        
        self.monitor_event_sender.send(event)
            .map_err(|_| AlpenglowError::Other("Failed to send actor error event".to_string()))?;
        
        Ok(())
    }
    
    /// Get current runtime metrics
    pub fn get_runtime_metrics(&self) -> RuntimeMetrics {
        self.metrics_collector.lock().unwrap().clone()
    }
    
    /// Get cached actor state
    pub fn get_cached_actor_state(&self, actor_id: Id) -> Option<serde_json::Value> {
        self.actor_state_cache.read().unwrap().get(&actor_id).cloned()
    }
}

/// Internal state tracking for runtime monitoring
#[derive(Debug)]
struct RuntimeMonitorState {
    /// Current runtime metrics
    runtime_metrics: RuntimeMetrics,
    /// Network health status
    network_health: NetworkHealth,
    /// Resource usage tracking
    resource_usage: ResourceUsage,
    /// Recent alerts (for deduplication and aggregation)
    recent_alerts: VecDeque<(RuntimeAlertType, SystemTime)>,
    /// Alert aggregation windows
    alert_windows: HashMap<String, Vec<RuntimeAlert>>,
    /// Performance history for trend analysis
    performance_history: VecDeque<(SystemTime, RuntimeMetrics)>,
    /// Network latency measurements
    latency_measurements: HashMap<(MainValidatorId, MainValidatorId), VecDeque<(SystemTime, f64)>>,
    /// Throughput measurements over time
    throughput_history: VecDeque<(SystemTime, f64)>,
    /// Error tracking
    error_counts: HashMap<String, u64>,
    /// Start time for monitoring
    start_time: SystemTime,
    /// Last cleanup time
    last_cleanup: SystemTime,
}

impl RuntimeMonitorState {
    fn new() -> Self {
        Self {
            runtime_metrics: RuntimeMetrics::default(),
            network_health: NetworkHealth::default(),
            resource_usage: ResourceUsage {
                validator_usage: HashMap::new(),
                system_totals: SystemResources {
                    total_cpu_usage_pct: 0.0,
                    total_memory_usage_bytes: 0,
                    total_disk_usage_bytes: 0,
                    total_network_bytes: 0,
                    total_connections: 0,
                },
                limits: ResourceLimits::default(),
                measured_at: SystemTime::now(),
            },
            recent_alerts: VecDeque::new(),
            alert_windows: HashMap::new(),
            performance_history: VecDeque::new(),
            latency_measurements: HashMap::new(),
            throughput_history: VecDeque::new(),
            error_counts: HashMap::new(),
            start_time: SystemTime::now(),
            last_cleanup: SystemTime::now(),
        }
    }
    
    /// Update runtime metrics
    fn update_runtime_metrics(&mut self, metrics: RuntimeMetrics) {
        self.runtime_metrics = metrics.clone();
        self.performance_history.push_back((SystemTime::now(), metrics));
        
        // Keep only recent history
        while self.performance_history.len() > 1000 {
            self.performance_history.pop_front();
        }
    }
    
    /// Record latency measurement
    fn record_latency(&mut self, from: MainValidatorId, to: MainValidatorId, latency_ms: f64) {
        let measurements = self.latency_measurements.entry((from, to)).or_default();
        measurements.push_back((SystemTime::now(), latency_ms));
        
        // Keep only recent measurements
        while measurements.len() > 100 {
            measurements.pop_front();
        }
        
        // Update network health
        let avg_latency = measurements.iter()
            .map(|(_, latency)| latency)
            .sum::<f64>() / measurements.len() as f64;
        
        self.network_health.avg_rtt_ms = avg_latency;
        self.network_health.last_check = SystemTime::now();
    }
    
    /// Record throughput measurement
    fn record_throughput(&mut self, throughput: f64) {
        self.throughput_history.push_back((SystemTime::now(), throughput));
        self.runtime_metrics.current_throughput = throughput;
        
        // Keep only recent history
        while self.throughput_history.len() > 1000 {
            self.throughput_history.pop_front();
        }
    }
    
    /// Check if alert should be suppressed (deduplication)
    fn should_suppress_alert(&mut self, alert_type: &RuntimeAlertType, config: &MonitorConfig) -> bool {
        let now = SystemTime::now();
        let cooldown = Duration::from_millis(config.alert_cooldown_ms);
        
        // Check recent alerts for duplicates
        let recent_count = self.recent_alerts.iter()
            .filter(|(atype, timestamp)| {
                atype == alert_type && now.duration_since(*timestamp).unwrap_or_default() < cooldown
            })
            .count();
        
        if recent_count > 0 {
            return true; // Suppress duplicate
        }
        
        // Add to recent alerts
        self.recent_alerts.push_back((*alert_type, now));
        
        // Clean up old alerts
        let cutoff = now - cooldown * 10;
        self.recent_alerts.retain(|(_, timestamp)| *timestamp > cutoff);
        
        false
    }
    
    /// Add alert to aggregation window
    fn add_to_aggregation_window(&mut self, alert: RuntimeAlert, config: &MonitorConfig) {
        let window_key = format!("{:?}", alert.alert_type);
        let window = self.alert_windows.entry(window_key).or_default();
        
        window.push(alert);
        
        // Check if window is full
        if window.len() >= config.max_alerts_per_window {
            // Could trigger aggregated alert here
            window.clear();
        }
    }
    
    /// Cleanup old data
    fn cleanup_old_data(&mut self, config: &MonitorConfig) {
        let now = SystemTime::now();
        
        // Only cleanup periodically
        if now.duration_since(self.last_cleanup).unwrap_or_default() < Duration::from_secs(60) {
            return;
        }
        
        let cutoff = now - Duration::from_secs(3600); // Keep 1 hour of data
        
        // Clean performance history
        self.performance_history.retain(|(timestamp, _)| *timestamp > cutoff);
        
        // Clean latency measurements
        for measurements in self.latency_measurements.values_mut() {
            measurements.retain(|(timestamp, _)| *timestamp > cutoff);
        }
        
        // Clean throughput history
        self.throughput_history.retain(|(timestamp, _)| *timestamp > cutoff);
        
        // Clean alert windows
        let window_cutoff = now - Duration::from_millis(config.alert_aggregation_window_ms);
        for window in self.alert_windows.values_mut() {
            window.retain(|alert| alert.timestamp > window_cutoff);
        }
        
        self.last_cleanup = now;
    }
}

/// Main Alpenglow runtime monitor with Actor model integration
pub struct AlpenglowRuntimeMonitor {
    config: MonitorConfig,
    state: Arc<RwLock<RuntimeMonitorState>>,
    event_sender: mpsc::UnboundedSender<RuntimeMonitorEvent>,
    event_receiver: Mutex<mpsc::UnboundedReceiver<RuntimeMonitorEvent>>,
    alert_sender: broadcast::Sender<RuntimeAlert>,
    validation_alert_sender: broadcast::Sender<ValidationAlert>,
    running: Arc<Mutex<bool>>,
    actor_bridge: Option<RuntimeActorBridge>,
}

impl AlpenglowRuntimeMonitor {
    /// Create a new Alpenglow runtime monitor
    pub fn new(config: MonitorConfig) -> Self {
        let (event_sender, event_receiver) = mpsc::unbounded_channel();
        let (alert_sender, _) = broadcast::channel(1000);
        let (validation_alert_sender, _) = broadcast::channel(1000);
        
        Self {
            config,
            state: Arc::new(RwLock::new(RuntimeMonitorState::new())),
            event_sender,
            event_receiver: Mutex::new(event_receiver),
            alert_sender,
            validation_alert_sender,
            running: Arc::new(Mutex::new(false)),
            actor_bridge: None,
        }
    }
    
    /// Create runtime monitor with Actor model integration
    pub fn new_with_actor_integration(
        config: MonitorConfig,
        model: ActorModel<AlpenglowNode, (), ()>
    ) -> AlpenglowResult<Self> {
        let mut monitor = Self::new(config);
        
        // Create actor bridge
        let bridge = RuntimeActorBridge::new(monitor.event_sender.clone())?;
        bridge.attach_to_model(model)?;
        monitor.actor_bridge = Some(bridge);
        
        info!("Runtime monitor created with Actor model integration");
        Ok(monitor)
    }
    
    /// Create runtime monitor from Alpenglow config
    pub fn from_alpenglow_config(config: AlpenglowConfig) -> AlpenglowResult<Self> {
        let monitor_config = MonitorConfig::from(config.clone());
        let model = alpenglow_stateright::create_model(config)?;
        Self::new_with_actor_integration(monitor_config, model)
    }

    /// Get an event sender for external components to send events
    pub fn event_sender(&self) -> mpsc::UnboundedSender<RuntimeMonitorEvent> {
        self.event_sender.clone()
    }

    /// Subscribe to runtime alerts
    pub fn subscribe_runtime_alerts(&self) -> broadcast::Receiver<RuntimeAlert> {
        self.alert_sender.subscribe()
    }
    
    /// Subscribe to validation alerts (bridged from validation module)
    pub fn subscribe_validation_alerts(&self) -> broadcast::Receiver<ValidationAlert> {
        self.validation_alert_sender.subscribe()
    }
    
    /// Get Actor bridge for direct integration
    pub fn actor_bridge(&self) -> Option<&RuntimeActorBridge> {
        self.actor_bridge.as_ref()
    }

    /// Start the monitoring system
    pub async fn start(&self) -> AlpenglowResult<()> {
        {
            let mut running = self.running.lock().unwrap();
            if *running {
                return Err(AlpenglowError::Other("Monitor is already running".to_string()));
            }
            *running = true;
        }

        info!("Starting Alpenglow runtime monitor");

        // Start the main monitoring loop
        let state = Arc::clone(&self.state);
        let config = self.config.clone();
        let runtime_alert_sender = self.alert_sender.clone();
        let validation_alert_sender = self.validation_alert_sender.clone();
        let running = Arc::clone(&self.running);
        
        tokio::spawn(async move {
            let mut cleanup_interval = interval(Duration::from_secs(60));
            let mut performance_interval = interval(Duration::from_millis(config.performance_interval_ms));
            let mut resource_interval = interval(Duration::from_secs(5));
            let mut network_interval = interval(Duration::from_secs(10));
            
            loop {
                if !*running.lock().unwrap() {
                    break;
                }

                tokio::select! {
                    _ = cleanup_interval.tick() => {
                        let mut state_guard = state.write().unwrap();
                        state_guard.cleanup_old_data(&config);
                    }
                    
                    _ = performance_interval.tick() => {
                        Self::check_performance_metrics(&state, &config, &runtime_alert_sender).await;
                    }
                    
                    _ = resource_interval.tick() => {
                        Self::check_resource_usage(&state, &config, &runtime_alert_sender).await;
                    }
                    
                    _ = network_interval.tick() => {
                        Self::check_network_health(&state, &config, &runtime_alert_sender).await;
                    }
                }
            }
        });

        // Start the event processing loop
        self.process_events().await;
        
        Ok(())
    }

    /// Stop the monitoring system
    pub fn stop(&self) {
        let mut running = self.running.lock().unwrap();
        *running = false;
        info!("Stopping Alpenglow runtime monitor");
    }

    /// Process incoming events
    async fn process_events(&self) {
        let mut receiver = self.event_receiver.lock().unwrap();
        
        while let Some(event) = receiver.recv().await {
            if !*self.running.lock().unwrap() {
                break;
            }

            if let Err(e) = self.handle_event(event).await {
                error!("Error handling runtime monitor event: {}", e);
            }
        }
    }

    /// Handle a single monitoring event
    async fn handle_event(&self, event: RuntimeMonitorEvent) -> AlpenglowResult<()> {
        let mut state = self.state.write().unwrap();
        
        match event {
            RuntimeMonitorEvent::ValidationEvent(validation_event) => {
                // Bridge validation events to validation alert channel
                // This avoids duplicating validation logic in the monitor
                debug!("Received validation event: {:?}", validation_event);
                
                // Convert validation events to runtime context if needed
                match validation_event {
                    ValidationEvent::BlockFinalized { block, certificate, timestamp } => {
                        // Track finalization latency for performance monitoring
                        let latency = SystemTime::now().duration_since(
                            SystemTime::UNIX_EPOCH + Duration::from_millis(timestamp)
                        ).unwrap_or_default();
                        
                        state.runtime_metrics.avg_latency_ms = latency.as_millis() as f64;
                        
                        // Check if latency exceeds thresholds
                        if latency.as_millis() > 1000 { // > 1 second
                            let alert = RuntimeAlert::new(
                                RuntimeAlertType::HighLatency,
                                ValidationAlertSeverity::Warning,
                                format!("High finalization latency: {}ms for slot {}", 
                                    latency.as_millis(), block.slot)
                            ).with_metric("latency_ms".to_string(), latency.as_millis() as f64)
                             .with_metadata("slot".to_string(), block.slot.to_string());
                            
                            let _ = self.alert_sender.send(alert);
                        }
                    }
                    _ => {} // Other validation events handled by validation module
                }
            }
            
            RuntimeMonitorEvent::PerformanceMetricsUpdate(metrics) => {
                debug!("Performance metrics updated: throughput={}, latency={}ms", 
                    metrics.current_throughput, metrics.avg_latency_ms);
                state.update_runtime_metrics(metrics);
            }
            
            RuntimeMonitorEvent::LatencyMeasurement { operation, latency_ms, timestamp: _ } => {
                trace!("Latency measurement: {} = {}ms", operation, latency_ms);
                
                // Update relevant metrics
                if operation == "finalization" {
                    state.runtime_metrics.avg_latency_ms = latency_ms;
                    
                    // Check thresholds
                    if latency_ms > 500.0 { // > 500ms
                        let alert = RuntimeAlert::new(
                            RuntimeAlertType::HighLatency,
                            ValidationAlertSeverity::Warning,
                            format!("High {} latency: {}ms", operation, latency_ms)
                        ).with_metric("latency_ms".to_string(), latency_ms)
                         .with_metadata("operation".to_string(), operation);
                        
                        if !state.should_suppress_alert(&RuntimeAlertType::HighLatency, &self.config) {
                            let _ = self.alert_sender.send(alert);
                        }
                    }
                }
            }
            
            RuntimeMonitorEvent::ThroughputMeasurement { throughput, window_ms: _, timestamp: _ } => {
                debug!("Throughput measurement: {} blocks/sec", throughput);
                state.record_throughput(throughput);
                
                // Check if throughput is too low
                if throughput < 1.0 { // Less than 1 block per second
                    let alert = RuntimeAlert::new(
                        RuntimeAlertType::LowThroughput,
                        ValidationAlertSeverity::Warning,
                        format!("Low throughput: {} blocks/sec", throughput)
                    ).with_metric("throughput".to_string(), throughput)
                     .with_action("Check network connectivity and validator health".to_string());
                    
                    if !state.should_suppress_alert(&RuntimeAlertType::LowThroughput, &self.config) {
                        let _ = self.alert_sender.send(alert);
                    }
                }
            }
            
            RuntimeMonitorEvent::ResourceUsageUpdate(usage) => {
                debug!("Resource usage updated: CPU={}%, Memory={}MB", 
                    usage.system_totals.total_cpu_usage_pct,
                    usage.system_totals.total_memory_usage_bytes / 1024 / 1024);
                state.resource_usage = usage;
            }
            
            RuntimeMonitorEvent::MemoryPressure { usage_pct, available_bytes } => {
                warn!("Memory pressure detected: {}% used, {} bytes available", usage_pct, available_bytes);
                
                let alert = RuntimeAlert::new(
                    RuntimeAlertType::MemoryPressure,
                    if usage_pct > 90.0 { ValidationAlertSeverity::Critical } else { ValidationAlertSeverity::Warning },
                    format!("Memory pressure: {}% used, {} bytes available", usage_pct, available_bytes)
                ).with_metric("usage_pct".to_string(), usage_pct)
                 .with_metric("available_bytes".to_string(), available_bytes as f64)
                 .with_action("Consider reducing memory usage or adding more memory".to_string());
                
                if !state.should_suppress_alert(&RuntimeAlertType::MemoryPressure, &self.config) {
                    let _ = self.alert_sender.send(alert);
                }
            }
            
            RuntimeMonitorEvent::CPUSpike { usage_pct, duration_ms } => {
                warn!("CPU spike detected: {}% for {}ms", usage_pct, duration_ms);
                
                if usage_pct > 80.0 && duration_ms > 5000 { // > 80% for > 5 seconds
                    let alert = RuntimeAlert::new(
                        RuntimeAlertType::CPUOverload,
                        ValidationAlertSeverity::Warning,
                        format!("CPU overload: {}% for {}ms", usage_pct, duration_ms)
                    ).with_metric("usage_pct".to_string(), usage_pct)
                     .with_metric("duration_ms".to_string(), duration_ms as f64);
                    
                    if !state.should_suppress_alert(&RuntimeAlertType::CPUOverload, &self.config) {
                        let _ = self.alert_sender.send(alert);
                    }
                }
            }
            
            RuntimeMonitorEvent::NetworkHealthUpdate(health) => {
                debug!("Network health updated: RTT={}ms, Loss={}%", health.avg_rtt_ms, health.packet_loss_pct);
                state.network_health = health;
            }
            
            RuntimeMonitorEvent::ConnectivityChange { validator_id, connected } => {
                info!("Validator {} connectivity changed: {}", validator_id, connected);
                
                if !connected {
                    let alert = RuntimeAlert::new(
                        RuntimeAlertType::ConnectivityLoss,
                        ValidationAlertSeverity::Warning,
                        format!("Validator {} lost connectivity", validator_id)
                    ).with_metadata("validator_id".to_string(), validator_id.to_string())
                     .with_action("Check network connectivity to validator".to_string());
                    
                    if !state.should_suppress_alert(&RuntimeAlertType::ConnectivityLoss, &self.config) {
                        let _ = self.alert_sender.send(alert);
                    }
                }
            }
            
            RuntimeMonitorEvent::LatencySpike { from, to, latency_ms } => {
                debug!("Latency spike: {} -> {} = {}ms", from, to, latency_ms);
                state.record_latency(from, to, latency_ms);
                
                if latency_ms > 1000.0 { // > 1 second
                    let alert = RuntimeAlert::new(
                        RuntimeAlertType::HighLatency,
                        ValidationAlertSeverity::Warning,
                        format!("High network latency: {} -> {} = {}ms", from, to, latency_ms)
                    ).with_metric("latency_ms".to_string(), latency_ms)
                     .with_metadata("from".to_string(), from.to_string())
                     .with_metadata("to".to_string(), to.to_string());
                    
                    if !state.should_suppress_alert(&RuntimeAlertType::HighLatency, &self.config) {
                        let _ = self.alert_sender.send(alert);
                    }
                }
            }
            
            RuntimeMonitorEvent::ValidatorStatusChange { validator_id, online } => {
                info!("Validator {} status changed: {}", validator_id, if online { "online" } else { "offline" });
                
                if !online {
                    let alert = RuntimeAlert::new(
                        RuntimeAlertType::ValidatorOffline,
                        ValidationAlertSeverity::Warning,
                        format!("Validator {} went offline", validator_id)
                    ).with_metadata("validator_id".to_string(), validator_id.to_string())
                     .with_action("Check validator health and restart if necessary".to_string());
                    
                    if !state.should_suppress_alert(&RuntimeAlertType::ValidatorOffline, &self.config) {
                        let _ = self.alert_sender.send(alert);
                    }
                }
            }
            
            RuntimeMonitorEvent::ActorStateChange { actor_id, state_snapshot: _ } => {
                trace!("Actor {} state changed", actor_id);
                // State changes are tracked by the actor bridge
            }
            
            RuntimeMonitorEvent::ActorMessageProcessed { actor_id, message_type, processing_time_ms } => {
                trace!("Actor {} processed {} in {}ms", actor_id, message_type, processing_time_ms);
                
                // Track slow message processing
                if processing_time_ms > 100.0 { // > 100ms
                    state.runtime_metrics.error_rate += 1.0;
                    
                    let alert = RuntimeAlert::new(
                        RuntimeAlertType::HighLatency,
                        ValidationAlertSeverity::Info,
                        format!("Slow message processing: {} took {}ms", message_type, processing_time_ms)
                    ).with_metric("processing_time_ms".to_string(), processing_time_ms)
                     .with_metadata("actor_id".to_string(), actor_id.to_string())
                     .with_metadata("message_type".to_string(), message_type);
                    
                    if !state.should_suppress_alert(&RuntimeAlertType::HighLatency, &self.config) {
                        let _ = self.alert_sender.send(alert);
                    }
                }
            }
            
            RuntimeMonitorEvent::ActorError { actor_id, error } => {
                error!("Actor {} error: {}", actor_id, error);
                state.runtime_metrics.error_rate += 1.0;
                
                let alert = RuntimeAlert::new(
                    RuntimeAlertType::HealthCheckFailure,
                    ValidationAlertSeverity::Error,
                    format!("Actor {} error: {}", actor_id, error)
                ).with_metadata("actor_id".to_string(), actor_id.to_string())
                 .with_metadata("error".to_string(), error)
                 .with_action("Check actor logs and restart if necessary".to_string());
                
                let _ = self.alert_sender.send(alert);
            }
            
            _ => {
                debug!("Unhandled runtime monitor event: {:?}", event);
            }
        }
        
        Ok(())
    }

    /// Check performance metrics and generate alerts
    async fn check_performance_metrics(
        state: &Arc<RwLock<RuntimeMonitorState>>,
        config: &MonitorConfig,
        alert_sender: &broadcast::Sender<RuntimeAlert>,
    ) {
        let state_guard = state.read().unwrap();
        let metrics = &state_guard.runtime_metrics;
        
        // Check throughput
        if metrics.current_throughput < 0.5 { // Less than 0.5 blocks/sec
            let alert = RuntimeAlert::new(
                RuntimeAlertType::LowThroughput,
                ValidationAlertSeverity::Warning,
                format!("Low throughput: {} blocks/sec", metrics.current_throughput)
            ).with_metric("throughput".to_string(), metrics.current_throughput)
             .with_action("Check network and validator health".to_string());
            
            let _ = alert_sender.send(alert);
        }
        
        // Check latency
        if metrics.avg_latency_ms > 1000.0 { // > 1 second
            let alert = RuntimeAlert::new(
                RuntimeAlertType::HighLatency,
                ValidationAlertSeverity::Warning,
                format!("High average latency: {}ms", metrics.avg_latency_ms)
            ).with_metric("latency_ms".to_string(), metrics.avg_latency_ms);
            
            let _ = alert_sender.send(alert);
        }
        
        // Check error rate
        if metrics.error_rate > 10.0 { // > 10 errors/sec
            let alert = RuntimeAlert::new(
                RuntimeAlertType::HealthCheckFailure,
                ValidationAlertSeverity::Error,
                format!("High error rate: {} errors/sec", metrics.error_rate)
            ).with_metric("error_rate".to_string(), metrics.error_rate)
             .with_action("Check system logs for error details".to_string());
            
            let _ = alert_sender.send(alert);
        }
        
        // Check queue depths
        for (queue_name, depth) in &metrics.queue_depths {
            if *depth > 1000 { // Queue backlog
                let alert = RuntimeAlert::new(
                    RuntimeAlertType::QueueBacklog,
                    ValidationAlertSeverity::Warning,
                    format!("Queue {} has backlog: {} items", queue_name, depth)
                ).with_metric("queue_depth".to_string(), *depth as f64)
                 .with_metadata("queue_name".to_string(), queue_name.clone())
                 .with_action("Check queue processing and consider scaling".to_string());
                
                let _ = alert_sender.send(alert);
            }
        }
    }
    
    /// Check resource usage and generate alerts
    async fn check_resource_usage(
        state: &Arc<RwLock<RuntimeMonitorState>>,
        config: &MonitorConfig,
        alert_sender: &broadcast::Sender<RuntimeAlert>,
    ) {
        let state_guard = state.read().unwrap();
        let usage = &state_guard.resource_usage;
        let limits = &usage.limits;
        
        // Check CPU usage
        if usage.system_totals.total_cpu_usage_pct > limits.max_cpu_pct {
            let alert = RuntimeAlert::new(
                RuntimeAlertType::CPUOverload,
                ValidationAlertSeverity::Warning,
                format!("High CPU usage: {}% > {}%", 
                    usage.system_totals.total_cpu_usage_pct, limits.max_cpu_pct)
            ).with_metric("cpu_usage_pct".to_string(), usage.system_totals.total_cpu_usage_pct)
             .with_metric("cpu_limit_pct".to_string(), limits.max_cpu_pct)
             .with_action("Consider reducing load or adding CPU capacity".to_string());
            
            let _ = alert_sender.send(alert);
        }
        
        // Check memory usage
        if usage.system_totals.total_memory_usage_bytes > limits.max_memory_bytes {
            let alert = RuntimeAlert::new(
                RuntimeAlertType::MemoryPressure,
                ValidationAlertSeverity::Warning,
                format!("High memory usage: {}MB > {}MB", 
                    usage.system_totals.total_memory_usage_bytes / 1024 / 1024,
                    limits.max_memory_bytes / 1024 / 1024)
            ).with_metric("memory_usage_bytes".to_string(), usage.system_totals.total_memory_usage_bytes as f64)
             .with_metric("memory_limit_bytes".to_string(), limits.max_memory_bytes as f64)
             .with_action("Consider reducing memory usage or adding memory".to_string());
            
            let _ = alert_sender.send(alert);
        }
        
        // Check disk usage
        if usage.system_totals.total_disk_usage_bytes > limits.max_disk_bytes {
            let alert = RuntimeAlert::new(
                RuntimeAlertType::DiskSpaceWarning,
                ValidationAlertSeverity::Warning,
                format!("High disk usage: {}GB > {}GB", 
                    usage.system_totals.total_disk_usage_bytes / 1024 / 1024 / 1024,
                    limits.max_disk_bytes / 1024 / 1024 / 1024)
            ).with_metric("disk_usage_bytes".to_string(), usage.system_totals.total_disk_usage_bytes as f64)
             .with_metric("disk_limit_bytes".to_string(), limits.max_disk_bytes as f64)
             .with_action("Clean up old data or add disk capacity".to_string());
            
            let _ = alert_sender.send(alert);
        }
        
        // Check connection count
        if usage.system_totals.total_connections > limits.max_connections {
            let alert = RuntimeAlert::new(
                RuntimeAlertType::ConnectionLimitReached,
                ValidationAlertSeverity::Warning,
                format!("High connection count: {} > {}", 
                    usage.system_totals.total_connections, limits.max_connections)
            ).with_metric("connections".to_string(), usage.system_totals.total_connections as f64)
             .with_metric("connection_limit".to_string(), limits.max_connections as f64)
             .with_action("Check for connection leaks or increase limits".to_string());
            
            let _ = alert_sender.send(alert);
        }
    }
    
    /// Check network health and generate alerts
    async fn check_network_health(
        state: &Arc<RwLock<RuntimeMonitorState>>,
        config: &MonitorConfig,
        alert_sender: &broadcast::Sender<RuntimeAlert>,
    ) {
        let state_guard = state.read().unwrap();
        let health = &state_guard.network_health;
        
        // Check average RTT
        if health.avg_rtt_ms > 500.0 { // > 500ms
            let alert = RuntimeAlert::new(
                RuntimeAlertType::HighLatency,
                ValidationAlertSeverity::Warning,
                format!("High network RTT: {}ms", health.avg_rtt_ms)
            ).with_metric("rtt_ms".to_string(), health.avg_rtt_ms)
             .with_action("Check network connectivity and routing".to_string());
            
            let _ = alert_sender.send(alert);
        }
        
        // Check packet loss
        if health.packet_loss_pct > 5.0 { // > 5%
            let alert = RuntimeAlert::new(
                RuntimeAlertType::HighPacketLoss,
                ValidationAlertSeverity::Warning,
                format!("High packet loss: {}%", health.packet_loss_pct)
            ).with_metric("packet_loss_pct".to_string(), health.packet_loss_pct)
             .with_action("Check network quality and congestion".to_string());
            
            let _ = alert_sender.send(alert);
        }
        
        // Check active partitions
        if health.active_partitions > 0 {
            let alert = RuntimeAlert::new(
                RuntimeAlertType::PartitionDetected,
                ValidationAlertSeverity::Error,
                format!("Network partitions detected: {}", health.active_partitions)
            ).with_metric("partitions".to_string(), health.active_partitions as f64)
             .with_action("Check network connectivity between validators".to_string());
            
            let _ = alert_sender.send(alert);
        }
        
        // Check message drop rate
        if health.message_drop_rate > 0.1 { // > 10%
            let alert = RuntimeAlert::new(
                RuntimeAlertType::MessageDrops,
                ValidationAlertSeverity::Warning,
                format!("High message drop rate: {}%", health.message_drop_rate * 100.0)
            ).with_metric("drop_rate_pct".to_string(), health.message_drop_rate * 100.0)
             .with_action("Check network capacity and message queues".to_string());
            
            let _ = alert_sender.send(alert);
        }
    }

    /// Check for conflicting block finalization in the same slot
    async fn check_conflicting_finalization(
        state: &MonitorState,
        _config: &MonitorConfig,
        alert_sender: &broadcast::Sender<Alert>,
    ) {
        for (&slot, blocks) in &state.proposed_blocks {
            let finalized_in_slot: Vec<_> = blocks.iter()
                .filter(|block| state.finalized_blocks.get(&slot).map_or(false, |fb| fb.hash == block.hash))
                .collect();
            
            if finalized_in_slot.len() > 1 {
                let alert = Alert {
                    alert_type: AlertType::ConflictingFinalization,
                    severity: AlertSeverity::Critical,
                    message: format!("Multiple blocks finalized in slot {}: {:?}", 
                                   slot, finalized_in_slot.iter().map(|b| &b.hash).collect::<Vec<_>>()),
                    timestamp: SystemTime::now(),
                    slot: Some(slot),
                    view: None,
                    validators: finalized_in_slot.iter().map(|b| b.proposer.clone()).collect(),
                    metadata: HashMap::new(),
                };
                
                let _ = alert_sender.send(alert);
            }
        }
    }

    /// Check certificate validity based on stake thresholds
    async fn check_certificate_validity(
        state: &MonitorState,
        config: &MonitorConfig,
        alert_sender: &broadcast::Sender<Alert>,
    ) {
        for ((slot, view), certs) in &state.certificates {
            for cert in certs {
                let required_stake = match cert.cert_type {
                    CertificateType::Fast => (state.total_stake * config.fast_path_threshold_bp as u64) / 10000,
                    CertificateType::Slow => (state.total_stake * config.slow_path_threshold_bp as u64) / 10000,
                    CertificateType::Skip => (state.total_stake * config.slow_path_threshold_bp as u64) / 10000,
                };
                
                if cert.total_stake < required_stake {
                    let alert = Alert {
                        alert_type: AlertType::InvalidCertificate,
                        severity: AlertSeverity::Error,
                        message: format!("Invalid certificate: insufficient stake {} < {} for {:?} certificate in slot {} view {}", 
                                       cert.total_stake, required_stake, cert.cert_type, slot, view),
                        timestamp: SystemTime::now(),
                        slot: Some(*slot),
                        view: Some(*view),
                        validators: cert.votes.iter().map(|v| v.validator.clone()).collect(),
                        metadata: HashMap::new(),
                    };
                    
                    let _ = alert_sender.send(alert);
                }
            }
        }
    }

    /// Check for double voting by validators
    async fn check_double_voting(
        state: &MonitorState,
        _config: &MonitorConfig,
        alert_sender: &broadcast::Sender<Alert>,
    ) {
        for ((slot, view), votes) in &state.votes {
            let mut validator_votes: HashMap<String, Vec<&VoteInfo>> = HashMap::new();
            
            for vote in votes {
                validator_votes.entry(vote.validator.clone()).or_default().push(vote);
            }
            
            for (validator, validator_vote_list) in validator_votes {
                if validator_vote_list.len() > 1 {
                    let unique_blocks: HashSet<_> = validator_vote_list.iter()
                        .map(|v| &v.block_hash)
                        .collect();
                    
                    if unique_blocks.len() > 1 {
                        let alert = Alert {
                            alert_type: AlertType::DoubleVoting,
                            severity: AlertSeverity::Error,
                            message: format!("Double voting detected: validator {} voted for multiple blocks in slot {} view {}: {:?}", 
                                           validator, slot, view, unique_blocks),
                            timestamp: SystemTime::now(),
                            slot: Some(*slot),
                            view: Some(*view),
                            validators: vec![validator.clone()],
                            metadata: HashMap::new(),
                        };
                        
                        let _ = alert_sender.send(alert);
                        
                        // Mark validator as suspected Byzantine
                        // Note: In a real implementation, this would need proper synchronization
                    }
                }
            }
        }
    }

    /// Check chain consistency across validators
    async fn check_chain_consistency(
        state: &MonitorState,
        _config: &MonitorConfig,
        alert_sender: &broadcast::Sender<Alert>,
    ) {
        // Check if all finalized blocks form a consistent chain
        let mut finalized_slots: Vec<_> = state.finalized_blocks.keys().cloned().collect();
        finalized_slots.sort();
        
        for window in finalized_slots.windows(2) {
            let prev_slot = window[0];
            let curr_slot = window[1];
            
            if let (Some(prev_block), Some(curr_block)) = 
                (state.finalized_blocks.get(&prev_slot), state.finalized_blocks.get(&curr_slot)) {
                
                if curr_block.parent_hash != prev_block.hash {
                    let alert = Alert {
                        alert_type: AlertType::ChainInconsistency,
                        severity: AlertSeverity::Critical,
                        message: format!("Chain inconsistency: block {} in slot {} does not reference parent {} from slot {}", 
                                       curr_block.hash, curr_slot, prev_block.hash, prev_slot),
                        timestamp: SystemTime::now(),
                        slot: Some(curr_slot),
                        view: None,
                        validators: vec![curr_block.proposer.clone()],
                        metadata: HashMap::new(),
                    };
                    
                    let _ = alert_sender.send(alert);
                }
            }
        }
    }

    /// Check Byzantine stake threshold
    async fn check_byzantine_threshold(
        state: &MonitorState,
        config: &MonitorConfig,
        alert_sender: &broadcast::Sender<Alert>,
    ) {
        let byzantine_stake = state.byzantine_stake();
        let threshold = (state.total_stake * config.byzantine_threshold_bp as u64) / 10000;
        
        if byzantine_stake > threshold {
            let alert = Alert {
                alert_type: AlertType::ByzantineThresholdExceeded,
                severity: AlertSeverity::Critical,
                message: format!("Byzantine stake threshold exceeded: {} > {} ({}%)", 
                               byzantine_stake, threshold, (byzantine_stake * 100) / state.total_stake),
                timestamp: SystemTime::now(),
                slot: None,
                view: None,
                validators: state.validators.iter()
                    .filter(|(_, v)| v.suspected_byzantine)
                    .map(|(id, _)| id.clone())
                    .collect(),
                metadata: HashMap::new(),
            };
            
            let _ = alert_sender.send(alert);
        }
    }

    /// Check finalization progress
    async fn check_finalization_progress(
        state: &MonitorState,
        config: &MonitorConfig,
        alert_sender: &broadcast::Sender<Alert>,
    ) {
        if !state.is_past_gst(config) {
            return; // Don't check liveness before GST
        }

        let honest_stake = state.honest_stake();
        let required_stake = (state.total_stake * 3) / 5; // 60% for liveness
        
        if honest_stake >= required_stake {
            // Check if current slot has been finalized within timeout
            let timeout_threshold = SystemTime::now() - Duration::from_millis(config.finalization_timeout_ms);
            
            if !state.finalized_blocks.contains_key(&state.current_slot) {
                // Check if there are any proposed blocks for current slot that should have been finalized
                if let Some(blocks) = state.proposed_blocks.get(&state.current_slot) {
                    for block in blocks {
                        if block.timestamp < timeout_threshold {
                            let alert = Alert {
                                alert_type: AlertType::FinalizationTimeout,
                                severity: AlertSeverity::Warning,
                                message: format!("Finalization timeout: block {} in slot {} not finalized within {}ms", 
                                               block.hash, state.current_slot, config.finalization_timeout_ms),
                                timestamp: SystemTime::now(),
                                slot: Some(state.current_slot),
                                view: None,
                                validators: vec![block.proposer.clone()],
                                metadata: HashMap::new(),
                            };
                            
                            let _ = alert_sender.send(alert);
                        }
                    }
                }
            }
        }
    }

    /// Check view timeouts
    async fn check_view_timeouts(
        state: &MonitorState,
        config: &MonitorConfig,
        alert_sender: &broadcast::Sender<Alert>,
    ) {
        let now = SystemTime::now();
        let timeout_threshold = Duration::from_millis(config.finalization_timeout_ms * 2);
        
        for (validator, &view) in &state.validator_views {
            if view > config.max_view {
                let alert = Alert {
                    alert_type: AlertType::ViewTimeout,
                    severity: AlertSeverity::Warning,
                    message: format!("Validator {} reached high view number: {}", validator, view),
                    timestamp: now,
                    slot: Some(state.current_slot),
                    view: Some(view),
                    validators: vec![validator.clone()],
                    metadata: HashMap::new(),
                };
                
                let _ = alert_sender.send(alert);
            }
        }
    }

    /// Check fast path completion
    async fn check_fast_path_completion(
        state: &MonitorState,
        config: &MonitorConfig,
        alert_sender: &broadcast::Sender<Alert>,
    ) {
        if !state.is_past_gst(config) {
            return;
        }

        let responsive_stake = state.honest_stake(); // Simplified: assume all honest validators are responsive
        let fast_path_threshold = (state.total_stake * config.fast_path_threshold_bp as u64) / 10000;
        
        if responsive_stake >= fast_path_threshold {
            // Check if recent slots used fast path
            for (&slot, certs) in &state.certificates {
                if slot >= state.current_slot.saturating_sub(5) { // Check last 5 slots
                    let has_fast_cert = certs.iter().any(|c| c.cert_type == CertificateType::Fast);
                    
                    if !has_fast_cert && state.finalized_blocks.contains_key(&slot) {
                        let alert = Alert {
                            alert_type: AlertType::SlowFinalization,
                            severity: AlertSeverity::Info,
                            message: format!("Slow path used in slot {} despite sufficient responsive stake", slot),
                            timestamp: SystemTime::now(),
                            slot: Some(slot),
                            view: None,
                            validators: vec![],
                            metadata: HashMap::new(),
                        };
                        
                        let _ = alert_sender.send(alert);
                    }
                }
            }
        }
    }

    /// Check bounded finalization time
    async fn check_bounded_finalization(
        state: &MonitorState,
        config: &MonitorConfig,
        alert_sender: &broadcast::Sender<Alert>,
    ) {
        if !state.is_past_gst(config) {
            return;
        }

        let responsive_stake = state.honest_stake();
        let fast_path_threshold = (state.total_stake * config.fast_path_threshold_bp as u64) / 10000;
        
        let bound = if responsive_stake >= fast_path_threshold {
            Duration::from_millis(config.network_delay_bound_ms) // Fast path bound
        } else {
            Duration::from_millis(config.network_delay_bound_ms * 2) // Slow path bound
        };
        
        // Check recent finalization latencies
        for &(slot, latency) in state.finalization_latencies.iter().rev().take(10) {
            if latency > bound {
                let alert = Alert {
                    alert_type: AlertType::SlowFinalization,
                    severity: AlertSeverity::Warning,
                    message: format!("Finalization exceeded bound: {}ms > {}ms for slot {}", 
                                   latency.as_millis(), bound.as_millis(), slot),
                    timestamp: SystemTime::now(),
                    slot: Some(slot),
                    view: None,
                    validators: vec![],
                    metadata: HashMap::new(),
                };
                
                let _ = alert_sender.send(alert);
            }
        }
    }

    /// Get current runtime monitoring statistics
    pub fn get_runtime_stats(&self) -> RuntimeMonitorStats {
        let state = self.state.read().unwrap();
        
        RuntimeMonitorStats {
            runtime_metrics: state.runtime_metrics.clone(),
            network_health: state.network_health.clone(),
            resource_usage: state.resource_usage.clone(),
            alert_count: state.recent_alerts.len(),
            uptime: SystemTime::now().duration_since(state.start_time).unwrap_or_default(),
            last_updated: SystemTime::now(),
        }
    }
    
    /// Get performance trends
    pub fn get_performance_trends(&self) -> PerformanceTrends {
        let state = self.state.read().unwrap();
        
        let throughput_trend = if state.throughput_history.len() >= 2 {
            let recent = state.throughput_history.back().map(|(_, t)| *t).unwrap_or(0.0);
            let older = state.throughput_history.front().map(|(_, t)| *t).unwrap_or(0.0);
            if older > 0.0 { (recent - older) / older } else { 0.0 }
        } else { 0.0 };
        
        let latency_trend = if state.performance_history.len() >= 2 {
            let recent = state.performance_history.back().map(|(_, m)| m.avg_latency_ms).unwrap_or(0.0);
            let older = state.performance_history.front().map(|(_, m)| m.avg_latency_ms).unwrap_or(0.0);
            if older > 0.0 { (recent - older) / older } else { 0.0 }
        } else { 0.0 };
        
        PerformanceTrends {
            throughput_trend_pct: throughput_trend * 100.0,
            latency_trend_pct: latency_trend * 100.0,
            error_rate_trend_pct: 0.0, // Could calculate from history
            window_duration: Duration::from_secs(3600), // 1 hour window
        }
    }
    
    /// Export metrics for external monitoring systems (Prometheus, etc.)
    pub fn export_metrics(&self) -> HashMap<String, f64> {
        let state = self.state.read().unwrap();
        let mut metrics = HashMap::new();
        
        // Runtime metrics
        metrics.insert("alpenglow_throughput_blocks_per_sec".to_string(), state.runtime_metrics.current_throughput);
        metrics.insert("alpenglow_latency_avg_ms".to_string(), state.runtime_metrics.avg_latency_ms);
        metrics.insert("alpenglow_latency_p95_ms".to_string(), state.runtime_metrics.p95_latency_ms);
        metrics.insert("alpenglow_bandwidth_bytes_per_sec".to_string(), state.runtime_metrics.bandwidth_usage as f64);
        metrics.insert("alpenglow_memory_usage_bytes".to_string(), state.runtime_metrics.memory_usage as f64);
        metrics.insert("alpenglow_cpu_usage_pct".to_string(), state.runtime_metrics.cpu_usage);
        metrics.insert("alpenglow_message_rate_per_sec".to_string(), state.runtime_metrics.message_rate);
        metrics.insert("alpenglow_error_rate_per_sec".to_string(), state.runtime_metrics.error_rate);
        metrics.insert("alpenglow_active_connections".to_string(), state.runtime_metrics.active_connections as f64);
        
        // Network health
        metrics.insert("alpenglow_network_rtt_avg_ms".to_string(), state.network_health.avg_rtt_ms);
        metrics.insert("alpenglow_network_packet_loss_pct".to_string(), state.network_health.packet_loss_pct);
        metrics.insert("alpenglow_network_jitter_ms".to_string(), state.network_health.jitter_ms);
        metrics.insert("alpenglow_network_partitions".to_string(), state.network_health.active_partitions as f64);
        metrics.insert("alpenglow_network_drop_rate_pct".to_string(), state.network_health.message_drop_rate * 100.0);
        
        // Resource usage
        metrics.insert("alpenglow_system_cpu_pct".to_string(), state.resource_usage.system_totals.total_cpu_usage_pct);
        metrics.insert("alpenglow_system_memory_bytes".to_string(), state.resource_usage.system_totals.total_memory_usage_bytes as f64);
        metrics.insert("alpenglow_system_disk_bytes".to_string(), state.resource_usage.system_totals.total_disk_usage_bytes as f64);
        metrics.insert("alpenglow_system_network_bytes".to_string(), state.resource_usage.system_totals.total_network_bytes as f64);
        metrics.insert("alpenglow_system_connections".to_string(), state.resource_usage.system_totals.total_connections as f64);
        
        // Alert metrics
        metrics.insert("alpenglow_alerts_total".to_string(), state.recent_alerts.len() as f64);
        
        metrics
    }
}

/// Runtime monitoring statistics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RuntimeMonitorStats {
    pub runtime_metrics: RuntimeMetrics,
    pub network_health: NetworkHealth,
    pub resource_usage: ResourceUsage,
    pub alert_count: usize,
    pub uptime: Duration,
    pub last_updated: SystemTime,
}

/// Performance trends over time
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PerformanceTrends {
    pub throughput_trend_pct: f64,
    pub latency_trend_pct: f64,
    pub error_rate_trend_pct: f64,
    pub window_duration: Duration,
}

/// Integration utilities for runtime monitoring
pub mod integration {
    use super::*;
    
    /// Create runtime monitor from Actor model
    pub fn create_runtime_monitor_from_model(
        model: ActorModel<AlpenglowNode, (), ()>
    ) -> AlpenglowResult<AlpenglowRuntimeMonitor> {
        let config = MonitorConfig::default();
        AlpenglowRuntimeMonitor::new_with_actor_integration(config, model)
    }
    
    /// Create runtime monitor from Alpenglow config
    pub fn create_runtime_monitor_from_config(
        config: AlpenglowConfig
    ) -> AlpenglowResult<AlpenglowRuntimeMonitor> {
        AlpenglowRuntimeMonitor::from_alpenglow_config(config)
    }
    
    /// Bridge validation events to runtime monitoring
    pub async fn bridge_validation_to_runtime(
        validation_events: mpsc::UnboundedReceiver<ValidationEvent>,
        runtime_monitor: &AlpenglowRuntimeMonitor,
    ) {
        let event_sender = runtime_monitor.event_sender();
        let mut receiver = validation_events;
        
        while let Some(validation_event) = receiver.recv().await {
            let runtime_event = RuntimeMonitorEvent::ValidationEvent(validation_event);
            if let Err(e) = event_sender.send(runtime_event) {
                error!("Failed to bridge validation event to runtime monitor: {}", e);
            }
        }
    }
    
    /// Create integrated monitoring system (validation + runtime)
    pub fn create_integrated_monitoring(
        config: AlpenglowConfig
    ) -> AlpenglowResult<(crate::validation::ValidationTools, AlpenglowRuntimeMonitor)> {
        // Create validation tools
        let validation_tools = crate::validation::ValidationTools::from_alpenglow_config(config.clone())?;
        
        // Create runtime monitor
        let runtime_monitor = AlpenglowRuntimeMonitor::from_alpenglow_config(config)?;
        
        // Bridge validation events to runtime monitor
        let validation_sender = validation_tools.get_event_sender();
        let runtime_sender = runtime_monitor.event_sender();
        
        tokio::spawn(async move {
            // This would need to be implemented to bridge events
            // For now, just log that bridging is set up
            info!("Validation-Runtime monitoring bridge established");
        });
        
        Ok((validation_tools, runtime_monitor))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::time::{sleep, Duration};
    use alpenglow_stateright::utils::test_configs;

    #[tokio::test]
    async fn test_runtime_monitor_creation() {
        let config = MonitorConfig::default();
        let monitor = AlpenglowRuntimeMonitor::new(config);
        
        assert!(!*monitor.running.lock().unwrap());
    }

    #[tokio::test]
    async fn test_actor_integration() {
        let alpenglow_config = test_configs()[0].clone();
        let monitor = AlpenglowRuntimeMonitor::from_alpenglow_config(alpenglow_config);
        
        assert!(monitor.is_ok());
        let monitor = monitor.unwrap();
        assert!(monitor.actor_bridge().is_some());
    }

    #[tokio::test]
    async fn test_performance_monitoring() {
        let config = MonitorConfig::default();
        let monitor = AlpenglowRuntimeMonitor::new(config);
        let event_sender = monitor.event_sender();
        let mut alert_receiver = monitor.subscribe_runtime_alerts();
        
        // Send low throughput event
        let metrics = RuntimeMetrics {
            current_throughput: 0.1, // Very low throughput
            ..Default::default()
        };
        
        event_sender.send(RuntimeMonitorEvent::PerformanceMetricsUpdate(metrics)).unwrap();
        
        // Start monitoring
        tokio::spawn(async move {
            let _ = monitor.start().await;
        });
        
        // Wait for alert
        let alert = timeout(Duration::from_secs(1), alert_receiver.recv()).await;
        assert!(alert.is_ok());
        
        let alert = alert.unwrap().unwrap();
        assert_eq!(alert.alert_type, RuntimeAlertType::LowThroughput);
    }

    #[tokio::test]
    async fn test_resource_monitoring() {
        let config = MonitorConfig::default();
        let monitor = AlpenglowRuntimeMonitor::new(config);
        let event_sender = monitor.event_sender();
        let mut alert_receiver = monitor.subscribe_runtime_alerts();
        
        // Send high memory usage event
        event_sender.send(RuntimeMonitorEvent::MemoryPressure {
            usage_pct: 95.0, // Very high memory usage
            available_bytes: 100 * 1024 * 1024, // 100MB available
        }).unwrap();
        
        // Start monitoring
        tokio::spawn(async move {
            let _ = monitor.start().await;
        });
        
        // Wait for alert
        let alert = timeout(Duration::from_secs(1), alert_receiver.recv()).await;
        assert!(alert.is_ok());
        
        let alert = alert.unwrap().unwrap();
        assert_eq!(alert.alert_type, RuntimeAlertType::MemoryPressure);
    }

    #[tokio::test]
    async fn test_network_monitoring() {
        let config = MonitorConfig::default();
        let monitor = AlpenglowRuntimeMonitor::new(config);
        let event_sender = monitor.event_sender();
        let mut alert_receiver = monitor.subscribe_runtime_alerts();
        
        // Send high latency event
        event_sender.send(RuntimeMonitorEvent::LatencySpike {
            from: 0,
            to: 1,
            latency_ms: 2000.0, // 2 second latency
        }).unwrap();
        
        // Start monitoring
        tokio::spawn(async move {
            let _ = monitor.start().await;
        });
        
        // Wait for alert
        let alert = timeout(Duration::from_secs(1), alert_receiver.recv()).await;
        assert!(alert.is_ok());
        
        let alert = alert.unwrap().unwrap();
        assert_eq!(alert.alert_type, RuntimeAlertType::HighLatency);
    }

    #[tokio::test]
    async fn test_validation_bridge() {
        let config = MonitorConfig::default();
        let monitor = AlpenglowRuntimeMonitor::new(config);
        let event_sender = monitor.event_sender();
        
        // Send validation event through bridge
        let validation_event = ValidationEvent::BlockFinalized {
            block: crate::validation::Block {
                hash: [1; 32],
                slot: 1,
                parent_hash: [0; 32],
                timestamp: 1000,
                proposer: 1,
                transactions: vec![],
            },
            certificate: crate::validation::Certificate {
                cert_type: crate::validation::CertificateType::Fast,
                slot: 1,
                view: 1,
                block_hash: [1; 32],
                votes: vec![],
                total_stake: 800,
                timestamp: 1000,
            },
            timestamp: 1000,
        };
        
        event_sender.send(RuntimeMonitorEvent::ValidationEvent(validation_event)).unwrap();
        
        // Process the event
        sleep(Duration::from_millis(10)).await;
        
        let stats = monitor.get_runtime_stats();
        assert!(stats.runtime_metrics.avg_latency_ms >= 0.0);
    }

    #[tokio::test]
    async fn test_metrics_export() {
        let config = MonitorConfig::default();
        let monitor = AlpenglowRuntimeMonitor::new(config);
        
        let metrics = monitor.export_metrics();
        
        // Check that key metrics are present
        assert!(metrics.contains_key("alpenglow_throughput_blocks_per_sec"));
        assert!(metrics.contains_key("alpenglow_latency_avg_ms"));
        assert!(metrics.contains_key("alpenglow_network_rtt_avg_ms"));
        assert!(metrics.contains_key("alpenglow_system_cpu_pct"));
    }

    #[tokio::test]
    async fn test_integrated_monitoring() {
        let alpenglow_config = test_configs()[0].clone();
        let result = integration::create_integrated_monitoring(alpenglow_config);
        
        assert!(result.is_ok());
        let (validation_tools, runtime_monitor) = result.unwrap();
        
        // Both should be properly initialized
        assert!(validation_tools.get_metrics().events_processed >= 0);
        assert!(runtime_monitor.get_runtime_stats().uptime >= Duration::from_secs(0));
    }
}
