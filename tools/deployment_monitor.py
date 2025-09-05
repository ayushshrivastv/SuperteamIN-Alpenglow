#!/usr/bin/env python3
"""
Deployment monitoring and validation tool for Alpenglow consensus protocol.
Provides real-time monitoring of consensus health, performance metrics, and
automated alerting for production deployments.
"""

import json
import time
import logging
import argparse
import subprocess
import threading
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass, asdict
from pathlib import Path

@dataclass
class ConsensusMetrics:
    """Consensus protocol health metrics"""
    finalization_rate: float
    average_finalization_time: float
    view_changes_per_hour: int
    byzantine_detection_count: int
    network_partition_events: int
    validator_participation_rate: float
    stake_distribution_gini: float
    block_production_rate: float
    
@dataclass
class PerformanceMetrics:
    """System performance metrics"""
    cpu_usage_percent: float
    memory_usage_mb: float
    network_bandwidth_mbps: float
    disk_io_ops_per_sec: float
    verification_time_ms: float
    state_size_mb: float
    
@dataclass
class AlertThresholds:
    """Configurable alert thresholds"""
    min_finalization_rate: float = 0.95
    max_finalization_time_ms: float = 5000.0
    max_view_changes_per_hour: int = 10
    min_participation_rate: float = 0.90
    max_cpu_usage: float = 80.0
    max_memory_usage_mb: float = 8192.0
    max_verification_time_ms: float = 1000.0

class AlpenglowMonitor:
    """Main monitoring class for Alpenglow deployment"""
    
    def __init__(self, config_path: str, log_level: str = "INFO"):
        self.config = self._load_config(config_path)
        self.thresholds = AlertThresholds(**self.config.get("thresholds", {}))
        self.monitoring_active = False
        self.metrics_history: List[Tuple[datetime, ConsensusMetrics, PerformanceMetrics]] = []
        
        # Setup logging
        logging.basicConfig(
            level=getattr(logging, log_level),
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler('alpenglow_monitor.log'),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger(__name__)
        
    def _load_config(self, config_path: str) -> Dict:
        """Load monitoring configuration"""
        try:
            with open(config_path, 'r') as f:
                return json.load(f)
        except FileNotFoundError:
            self.logger.warning(f"Config file {config_path} not found, using defaults")
            return self._default_config()
    
    def _default_config(self) -> Dict:
        """Default monitoring configuration"""
        return {
            "monitoring_interval_seconds": 30,
            "metrics_retention_hours": 24,
            "validator_endpoints": ["http://localhost:8899"],
            "consensus_rpc_port": 8900,
            "alerts": {
                "email_enabled": False,
                "slack_webhook": None,
                "pagerduty_key": None
            },
            "thresholds": asdict(AlertThresholds())
        }
    
    def collect_consensus_metrics(self) -> ConsensusMetrics:
        """Collect consensus protocol metrics"""
        try:
            # Simulate metrics collection from validator nodes
            # In production, this would query actual validator APIs
            
            # Query finalization status
            finalization_data = self._query_validator_api("/finalization_status")
            finalization_rate = finalization_data.get("rate", 0.98)
            avg_finalization_time = finalization_data.get("avg_time_ms", 2500.0)
            
            # Query view change statistics
            view_data = self._query_validator_api("/view_statistics")
            view_changes = view_data.get("changes_last_hour", 2)
            
            # Query Byzantine detection
            byzantine_data = self._query_validator_api("/byzantine_detection")
            byzantine_count = byzantine_data.get("detected_count", 0)
            
            # Query network health
            network_data = self._query_validator_api("/network_health")
            partition_events = network_data.get("partition_events", 0)
            participation_rate = network_data.get("participation_rate", 0.95)
            
            # Calculate stake distribution metrics
            stake_data = self._query_validator_api("/stake_distribution")
            gini_coefficient = self._calculate_gini_coefficient(stake_data.get("stakes", []))
            
            # Query block production
            block_data = self._query_validator_api("/block_production")
            block_rate = block_data.get("blocks_per_second", 0.5)
            
            return ConsensusMetrics(
                finalization_rate=finalization_rate,
                average_finalization_time=avg_finalization_time,
                view_changes_per_hour=view_changes,
                byzantine_detection_count=byzantine_count,
                network_partition_events=partition_events,
                validator_participation_rate=participation_rate,
                stake_distribution_gini=gini_coefficient,
                block_production_rate=block_rate
            )
            
        except Exception as e:
            self.logger.error(f"Failed to collect consensus metrics: {e}")
            return ConsensusMetrics(0, 0, 0, 0, 0, 0, 0, 0)
    
    def collect_performance_metrics(self) -> PerformanceMetrics:
        """Collect system performance metrics"""
        try:
            # CPU usage
            cpu_result = subprocess.run(
                ["top", "-l", "1", "-n", "0"], 
                capture_output=True, text=True, timeout=5
            )
            cpu_usage = self._parse_cpu_usage(cpu_result.stdout)
            
            # Memory usage
            memory_result = subprocess.run(
                ["vm_stat"], 
                capture_output=True, text=True, timeout=5
            )
            memory_usage = self._parse_memory_usage(memory_result.stdout)
            
            # Network bandwidth (simplified)
            network_bandwidth = self._estimate_network_bandwidth()
            
            # Disk I/O
            disk_io = self._estimate_disk_io()
            
            # Verification time (from recent logs)
            verification_time = self._get_recent_verification_time()
            
            # State size
            state_size = self._calculate_state_size()
            
            return PerformanceMetrics(
                cpu_usage_percent=cpu_usage,
                memory_usage_mb=memory_usage,
                network_bandwidth_mbps=network_bandwidth,
                disk_io_ops_per_sec=disk_io,
                verification_time_ms=verification_time,
                state_size_mb=state_size
            )
            
        except Exception as e:
            self.logger.error(f"Failed to collect performance metrics: {e}")
            return PerformanceMetrics(0, 0, 0, 0, 0, 0)
    
    def _query_validator_api(self, endpoint: str) -> Dict:
        """Query validator API endpoint"""
        # Simulate API response - in production would use actual HTTP requests
        mock_responses = {
            "/finalization_status": {"rate": 0.98, "avg_time_ms": 2500.0},
            "/view_statistics": {"changes_last_hour": 2},
            "/byzantine_detection": {"detected_count": 0},
            "/network_health": {"partition_events": 0, "participation_rate": 0.95},
            "/stake_distribution": {"stakes": [100, 150, 200, 100, 50]},
            "/block_production": {"blocks_per_second": 0.5}
        }
        return mock_responses.get(endpoint, {})
    
    def _calculate_gini_coefficient(self, stakes: List[float]) -> float:
        """Calculate Gini coefficient for stake distribution"""
        if not stakes:
            return 0.0
        
        stakes = sorted(stakes)
        n = len(stakes)
        cumsum = sum(stakes)
        
        if cumsum == 0:
            return 0.0
        
        gini = (2 * sum((i + 1) * stake for i, stake in enumerate(stakes))) / (n * cumsum) - (n + 1) / n
        return max(0.0, gini)
    
    def _parse_cpu_usage(self, top_output: str) -> float:
        """Parse CPU usage from top command output"""
        # Simplified parsing - in production would be more robust
        lines = top_output.split('\n')
        for line in lines:
            if 'CPU usage' in line:
                # Extract percentage (mock implementation)
                return 25.5
        return 0.0
    
    def _parse_memory_usage(self, vm_stat_output: str) -> float:
        """Parse memory usage from vm_stat output"""
        # Simplified parsing - in production would calculate actual usage
        return 4096.0  # Mock 4GB usage
    
    def _estimate_network_bandwidth(self) -> float:
        """Estimate current network bandwidth usage"""
        # Mock implementation - in production would use netstat or similar
        return 50.0  # Mock 50 Mbps
    
    def _estimate_disk_io(self) -> float:
        """Estimate disk I/O operations per second"""
        # Mock implementation - in production would use iostat
        return 100.0  # Mock 100 ops/sec
    
    def _get_recent_verification_time(self) -> float:
        """Get recent verification time from logs"""
        # Mock implementation - in production would parse actual logs
        return 500.0  # Mock 500ms
    
    def _calculate_state_size(self) -> float:
        """Calculate current state size"""
        # Mock implementation - in production would check actual state files
        return 256.0  # Mock 256MB
    
    def check_alerts(self, consensus_metrics: ConsensusMetrics, 
                    performance_metrics: PerformanceMetrics) -> List[str]:
        """Check metrics against thresholds and generate alerts"""
        alerts = []
        
        # Consensus alerts
        if consensus_metrics.finalization_rate < self.thresholds.min_finalization_rate:
            alerts.append(f"Low finalization rate: {consensus_metrics.finalization_rate:.2%}")
        
        if consensus_metrics.average_finalization_time > self.thresholds.max_finalization_time_ms:
            alerts.append(f"High finalization time: {consensus_metrics.average_finalization_time:.0f}ms")
        
        if consensus_metrics.view_changes_per_hour > self.thresholds.max_view_changes_per_hour:
            alerts.append(f"Excessive view changes: {consensus_metrics.view_changes_per_hour}/hour")
        
        if consensus_metrics.validator_participation_rate < self.thresholds.min_participation_rate:
            alerts.append(f"Low participation: {consensus_metrics.validator_participation_rate:.2%}")
        
        # Performance alerts
        if performance_metrics.cpu_usage_percent > self.thresholds.max_cpu_usage:
            alerts.append(f"High CPU usage: {performance_metrics.cpu_usage_percent:.1f}%")
        
        if performance_metrics.memory_usage_mb > self.thresholds.max_memory_usage_mb:
            alerts.append(f"High memory usage: {performance_metrics.memory_usage_mb:.0f}MB")
        
        if performance_metrics.verification_time_ms > self.thresholds.max_verification_time_ms:
            alerts.append(f"Slow verification: {performance_metrics.verification_time_ms:.0f}ms")
        
        return alerts
    
    def send_alerts(self, alerts: List[str]):
        """Send alerts via configured channels"""
        if not alerts:
            return
        
        alert_message = f"Alpenglow Alert [{datetime.now()}]:\n" + "\n".join(f"- {alert}" for alert in alerts)
        
        # Log alerts
        self.logger.warning(f"ALERTS TRIGGERED: {len(alerts)} issues detected")
        for alert in alerts:
            self.logger.warning(f"ALERT: {alert}")
        
        # Send via configured channels
        alert_config = self.config.get("alerts", {})
        
        if alert_config.get("email_enabled"):
            self._send_email_alert(alert_message)
        
        if alert_config.get("slack_webhook"):
            self._send_slack_alert(alert_message)
        
        if alert_config.get("pagerduty_key"):
            self._send_pagerduty_alert(alert_message)
    
    def _send_email_alert(self, message: str):
        """Send email alert (mock implementation)"""
        self.logger.info("Email alert sent (mock)")
    
    def _send_slack_alert(self, message: str):
        """Send Slack alert (mock implementation)"""
        self.logger.info("Slack alert sent (mock)")
    
    def _send_pagerduty_alert(self, message: str):
        """Send PagerDuty alert (mock implementation)"""
        self.logger.info("PagerDuty alert sent (mock)")
    
    def generate_report(self) -> str:
        """Generate monitoring report"""
        if not self.metrics_history:
            return "No metrics data available"
        
        latest_time, latest_consensus, latest_performance = self.metrics_history[-1]
        
        report = f"""
Alpenglow Consensus Monitoring Report
Generated: {datetime.now()}
Monitoring Period: {len(self.metrics_history)} samples

=== CONSENSUS HEALTH ===
Finalization Rate: {latest_consensus.finalization_rate:.2%}
Avg Finalization Time: {latest_consensus.average_finalization_time:.0f}ms
View Changes/Hour: {latest_consensus.view_changes_per_hour}
Byzantine Detections: {latest_consensus.byzantine_detection_count}
Validator Participation: {latest_consensus.validator_participation_rate:.2%}
Stake Distribution (Gini): {latest_consensus.stake_distribution_gini:.3f}
Block Production Rate: {latest_consensus.block_production_rate:.2f} blocks/sec

=== PERFORMANCE METRICS ===
CPU Usage: {latest_performance.cpu_usage_percent:.1f}%
Memory Usage: {latest_performance.memory_usage_mb:.0f}MB
Network Bandwidth: {latest_performance.network_bandwidth_mbps:.1f}Mbps
Disk I/O: {latest_performance.disk_io_ops_per_sec:.0f} ops/sec
Verification Time: {latest_performance.verification_time_ms:.0f}ms
State Size: {latest_performance.state_size_mb:.0f}MB

=== RECENT ALERTS ===
"""
        
        # Add recent alerts from last hour
        recent_alerts = self._get_recent_alerts()
        if recent_alerts:
            for alert in recent_alerts:
                report += f"- {alert}\n"
        else:
            report += "No recent alerts\n"
        
        return report
    
    def _get_recent_alerts(self) -> List[str]:
        """Get alerts from the last hour"""
        # Mock implementation - in production would query alert history
        return []
    
    def start_monitoring(self):
        """Start continuous monitoring"""
        self.monitoring_active = True
        self.logger.info("Starting Alpenglow monitoring...")
        
        def monitoring_loop():
            while self.monitoring_active:
                try:
                    # Collect metrics
                    consensus_metrics = self.collect_consensus_metrics()
                    performance_metrics = self.collect_performance_metrics()
                    
                    # Store metrics
                    timestamp = datetime.now()
                    self.metrics_history.append((timestamp, consensus_metrics, performance_metrics))
                    
                    # Cleanup old metrics
                    cutoff_time = timestamp - timedelta(hours=self.config.get("metrics_retention_hours", 24))
                    self.metrics_history = [
                        (t, c, p) for t, c, p in self.metrics_history if t > cutoff_time
                    ]
                    
                    # Check for alerts
                    alerts = self.check_alerts(consensus_metrics, performance_metrics)
                    if alerts:
                        self.send_alerts(alerts)
                    
                    # Log status
                    self.logger.info(f"Monitoring cycle complete - {len(alerts)} alerts")
                    
                    # Wait for next cycle
                    time.sleep(self.config.get("monitoring_interval_seconds", 30))
                    
                except Exception as e:
                    self.logger.error(f"Monitoring cycle failed: {e}")
                    time.sleep(10)  # Short retry delay
        
        # Start monitoring in background thread
        self.monitoring_thread = threading.Thread(target=monitoring_loop, daemon=True)
        self.monitoring_thread.start()
    
    def stop_monitoring(self):
        """Stop continuous monitoring"""
        self.monitoring_active = False
        self.logger.info("Stopping Alpenglow monitoring...")

def main():
    parser = argparse.ArgumentParser(description="Alpenglow Deployment Monitor")
    parser.add_argument("--config", default="monitor_config.json", help="Configuration file path")
    parser.add_argument("--log-level", default="INFO", choices=["DEBUG", "INFO", "WARNING", "ERROR"])
    parser.add_argument("--report", action="store_true", help="Generate and print report")
    parser.add_argument("--daemon", action="store_true", help="Run as daemon")
    
    args = parser.parse_args()
    
    monitor = AlpenglowMonitor(args.config, args.log_level)
    
    if args.report:
        print(monitor.generate_report())
    elif args.daemon:
        monitor.start_monitoring()
        try:
            while True:
                time.sleep(60)
                print(f"Monitoring active - {len(monitor.metrics_history)} samples collected")
        except KeyboardInterrupt:
            monitor.stop_monitoring()
            print("Monitoring stopped")
    else:
        # Single metrics collection
        consensus_metrics = monitor.collect_consensus_metrics()
        performance_metrics = monitor.collect_performance_metrics()
        alerts = monitor.check_alerts(consensus_metrics, performance_metrics)
        
        print("=== CURRENT METRICS ===")
        print(f"Consensus: {asdict(consensus_metrics)}")
        print(f"Performance: {asdict(performance_metrics)}")
        if alerts:
            print(f"Alerts: {alerts}")

if __name__ == "__main__":
    main()
