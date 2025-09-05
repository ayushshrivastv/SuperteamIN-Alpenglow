#!/usr/bin/env python3
"""
Automated Verification Status Tracking System for Alpenglow Whitepaper Theorems

This system continuously monitors the verification status of all whitepaper theorems,
automatically updates mapping documentation, maintains historical logs, and generates
alerts when verification status changes or issues are detected.

Features:
- Periodic verification audits using correspondence verification script
- Automatic WhitepaperMapping.md document updates
- Historical verification status tracking
- CI/CD pipeline integration
- Discrepancy detection and alerting
- Evidence-backed claim validation
"""

import os
import sys
import json
import time
import logging
import hashlib
import subprocess
import threading
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Any, Set
from dataclasses import dataclass, asdict
from enum import Enum
import re
import tempfile
import shutil
import argparse
import yaml
from concurrent.futures import ThreadPoolExecutor, as_completed

# Configuration
SCRIPT_DIR = Path(__file__).parent
PROJECT_ROOT = SCRIPT_DIR.parent
VERIFICATION_SCRIPT = PROJECT_ROOT / "scripts" / "verify_whitepaper_correspondence.sh"
MAPPING_DOC = PROJECT_ROOT / "docs" / "WhitepaperMapping.md"
TRACKING_DATA_DIR = PROJECT_ROOT / "verification_tracking"
LOGS_DIR = TRACKING_DATA_DIR / "logs"
HISTORY_DIR = TRACKING_DATA_DIR / "history"
ALERTS_DIR = TRACKING_DATA_DIR / "alerts"
CONFIG_FILE = TRACKING_DATA_DIR / "config.yaml"

# Ensure directories exist
for directory in [TRACKING_DATA_DIR, LOGS_DIR, HISTORY_DIR, ALERTS_DIR]:
    directory.mkdir(parents=True, exist_ok=True)

# Logging setup
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOGS_DIR / f"verification_tracking_{datetime.now().strftime('%Y%m%d')}.log"),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

class VerificationStatus(Enum):
    """Verification status enumeration"""
    PROVED = "proved"
    FAILED = "failed"
    PARTIAL = "partial"
    UNKNOWN = "unknown"
    NOT_PROCESSED = "not_processed"
    ERROR = "error"

class AlertLevel(Enum):
    """Alert severity levels"""
    INFO = "info"
    WARNING = "warning"
    ERROR = "error"
    CRITICAL = "critical"

@dataclass
class TheoremInfo:
    """Information about a theorem or lemma"""
    name: str
    type: str  # "THEOREM" or "LEMMA"
    line_number: int
    status: VerificationStatus
    proof_obligations: Dict[str, Any]
    errors: List[str]
    last_verified: Optional[datetime] = None
    verification_time: Optional[float] = None
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization"""
        result = asdict(self)
        result['status'] = self.status.value
        if self.last_verified:
            result['last_verified'] = self.last_verified.isoformat()
        return result
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'TheoremInfo':
        """Create from dictionary"""
        if 'last_verified' in data and data['last_verified']:
            data['last_verified'] = datetime.fromisoformat(data['last_verified'])
        data['status'] = VerificationStatus(data['status'])
        return cls(**data)

@dataclass
class VerificationReport:
    """Complete verification report"""
    timestamp: datetime
    total_theorems: int
    verification_status: Dict[str, int]
    success_rate: float
    verification_complete: bool
    correspondence_complete: bool
    blocking_issues: List[Dict[str, Any]]
    theorems: List[TheoremInfo]
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization"""
        result = asdict(self)
        result['timestamp'] = self.timestamp.isoformat()
        result['theorems'] = [t.to_dict() for t in self.theorems]
        return result
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'VerificationReport':
        """Create from dictionary"""
        data['timestamp'] = datetime.fromisoformat(data['timestamp'])
        data['theorems'] = [TheoremInfo.from_dict(t) for t in data['theorems']]
        return cls(**data)

@dataclass
class Alert:
    """Alert information"""
    timestamp: datetime
    level: AlertLevel
    title: str
    message: str
    theorem_name: Optional[str] = None
    details: Optional[Dict[str, Any]] = None
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization"""
        result = asdict(self)
        result['timestamp'] = self.timestamp.isoformat()
        result['level'] = self.level.value
        return result
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'Alert':
        """Create from dictionary"""
        data['timestamp'] = datetime.fromisoformat(data['timestamp'])
        data['level'] = AlertLevel(data['level'])
        return cls(**data)

class ConfigManager:
    """Configuration management"""
    
    DEFAULT_CONFIG = {
        'verification': {
            'check_interval_minutes': 60,
            'timeout_seconds': 1800,
            'max_retries': 3,
            'parallel_checks': True
        },
        'alerts': {
            'enabled': True,
            'email_notifications': False,
            'slack_webhook': None,
            'alert_on_status_change': True,
            'alert_on_new_issues': True,
            'alert_on_regression': True
        },
        'documentation': {
            'auto_update_mapping': True,
            'backup_before_update': True,
            'update_on_status_change': True
        },
        'history': {
            'keep_days': 90,
            'compress_old_reports': True
        },
        'ci_cd': {
            'enabled': False,
            'fail_on_regression': True,
            'fail_on_incomplete_verification': False,
            'generate_junit_xml': True
        }
    }
    
    def __init__(self):
        self.config = self.load_config()
    
    def load_config(self) -> Dict[str, Any]:
        """Load configuration from file or create default"""
        if CONFIG_FILE.exists():
            try:
                with open(CONFIG_FILE, 'r') as f:
                    config = yaml.safe_load(f)
                # Merge with defaults
                return self._merge_config(self.DEFAULT_CONFIG, config)
            except Exception as e:
                logger.warning(f"Failed to load config: {e}, using defaults")
        
        # Create default config file
        self.save_config(self.DEFAULT_CONFIG)
        return self.DEFAULT_CONFIG.copy()
    
    def save_config(self, config: Dict[str, Any]):
        """Save configuration to file"""
        try:
            with open(CONFIG_FILE, 'w') as f:
                yaml.dump(config, f, default_flow_style=False, indent=2)
        except Exception as e:
            logger.error(f"Failed to save config: {e}")
    
    def _merge_config(self, default: Dict[str, Any], user: Dict[str, Any]) -> Dict[str, Any]:
        """Merge user config with defaults"""
        result = default.copy()
        for key, value in user.items():
            if key in result and isinstance(result[key], dict) and isinstance(value, dict):
                result[key] = self._merge_config(result[key], value)
            else:
                result[key] = value
        return result

class VerificationRunner:
    """Runs verification checks and parses results"""
    
    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.timeout = config['verification']['timeout_seconds']
        self.max_retries = config['verification']['max_retries']
    
    def run_verification(self) -> Optional[VerificationReport]:
        """Run verification script and parse results"""
        for attempt in range(self.max_retries):
            try:
                logger.info(f"Running verification attempt {attempt + 1}/{self.max_retries}")
                result = self._execute_verification_script()
                if result:
                    return result
            except Exception as e:
                logger.error(f"Verification attempt {attempt + 1} failed: {e}")
                if attempt < self.max_retries - 1:
                    time.sleep(5 * (attempt + 1))  # Exponential backoff
        
        logger.error("All verification attempts failed")
        return None
    
    def _execute_verification_script(self) -> Optional[VerificationReport]:
        """Execute the verification script and parse output"""
        if not VERIFICATION_SCRIPT.exists():
            logger.error(f"Verification script not found: {VERIFICATION_SCRIPT}")
            return None
        
        try:
            # Make script executable
            os.chmod(VERIFICATION_SCRIPT, 0o755)
            
            # Run verification script
            start_time = time.time()
            result = subprocess.run(
                [str(VERIFICATION_SCRIPT)],
                cwd=PROJECT_ROOT,
                capture_output=True,
                text=True,
                timeout=self.timeout
            )
            execution_time = time.time() - start_time
            
            logger.info(f"Verification script completed in {execution_time:.2f}s with exit code {result.returncode}")
            
            # Parse output to find JSON report
            report_data = self._parse_verification_output(result.stdout, result.stderr)
            if not report_data:
                logger.error("Failed to parse verification output")
                return None
            
            # Convert to VerificationReport
            return self._create_verification_report(report_data, execution_time)
            
        except subprocess.TimeoutExpired:
            logger.error(f"Verification script timed out after {self.timeout}s")
            return None
        except Exception as e:
            logger.error(f"Failed to execute verification script: {e}")
            return None
    
    def _parse_verification_output(self, stdout: str, stderr: str) -> Optional[Dict[str, Any]]:
        """Parse verification script output to extract JSON report"""
        # Look for JSON report file mentioned in output
        report_pattern = r'Verification report written to: (.+\.json)'
        match = re.search(report_pattern, stdout)
        
        if match:
            report_file = Path(match.group(1))
            if report_file.exists():
                try:
                    with open(report_file, 'r') as f:
                        return json.load(f)
                except Exception as e:
                    logger.error(f"Failed to read report file {report_file}: {e}")
        
        # Try to extract JSON from stdout directly
        try:
            # Look for JSON blocks in output
            json_start = stdout.find('{')
            json_end = stdout.rfind('}') + 1
            if json_start >= 0 and json_end > json_start:
                json_str = stdout[json_start:json_end]
                return json.loads(json_str)
        except Exception as e:
            logger.debug(f"Failed to parse JSON from stdout: {e}")
        
        logger.error("Could not find or parse verification report")
        logger.debug(f"STDOUT: {stdout}")
        logger.debug(f"STDERR: {stderr}")
        return None
    
    def _create_verification_report(self, data: Dict[str, Any], execution_time: float) -> VerificationReport:
        """Create VerificationReport from parsed data"""
        timestamp = datetime.now()
        
        # Extract summary information
        summary = data.get('summary', {})
        total_theorems = summary.get('total_theorems', 0)
        verification_status = summary.get('verification_status', {})
        success_rate = summary.get('success_rate', 0.0)
        verification_complete = summary.get('verification_complete', False)
        
        # Extract correspondence information
        correspondence = data.get('correspondence_analysis', {})
        correspondence_complete = correspondence.get('correspondence_complete', False)
        
        # Extract blocking issues
        blocking_issues = summary.get('blocking_issues', [])
        
        # Convert TLA+ theorems to TheoremInfo objects
        theorems = []
        tla_theorems = data.get('tla_theorems', [])
        for theorem_data in tla_theorems:
            try:
                status = VerificationStatus(theorem_data.get('status', 'unknown'))
                theorem = TheoremInfo(
                    name=theorem_data.get('name', ''),
                    type=theorem_data.get('type', 'UNKNOWN'),
                    line_number=theorem_data.get('line_number', 0),
                    status=status,
                    proof_obligations=theorem_data.get('proof_obligations', {}),
                    errors=theorem_data.get('errors', []),
                    last_verified=timestamp if status == VerificationStatus.PROVED else None,
                    verification_time=execution_time
                )
                theorems.append(theorem)
            except Exception as e:
                logger.warning(f"Failed to parse theorem data: {e}")
        
        return VerificationReport(
            timestamp=timestamp,
            total_theorems=total_theorems,
            verification_status=verification_status,
            success_rate=success_rate,
            verification_complete=verification_complete,
            correspondence_complete=correspondence_complete,
            blocking_issues=blocking_issues,
            theorems=theorems
        )

class HistoryManager:
    """Manages verification history and change detection"""
    
    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.keep_days = config['history']['keep_days']
    
    def save_report(self, report: VerificationReport) -> Path:
        """Save verification report to history"""
        timestamp_str = report.timestamp.strftime('%Y%m%d_%H%M%S')
        filename = f"verification_report_{timestamp_str}.json"
        filepath = HISTORY_DIR / filename
        
        try:
            with open(filepath, 'w') as f:
                json.dump(report.to_dict(), f, indent=2)
            logger.info(f"Saved verification report to {filepath}")
            return filepath
        except Exception as e:
            logger.error(f"Failed to save report: {e}")
            raise
    
    def get_latest_report(self) -> Optional[VerificationReport]:
        """Get the most recent verification report"""
        try:
            report_files = list(HISTORY_DIR.glob("verification_report_*.json"))
            if not report_files:
                return None
            
            # Sort by timestamp in filename
            latest_file = max(report_files, key=lambda f: f.stem.split('_')[-2:])
            
            with open(latest_file, 'r') as f:
                data = json.load(f)
            
            return VerificationReport.from_dict(data)
        except Exception as e:
            logger.error(f"Failed to load latest report: {e}")
            return None
    
    def get_report_history(self, days: int = 30) -> List[VerificationReport]:
        """Get verification reports from the last N days"""
        cutoff_date = datetime.now() - timedelta(days=days)
        reports = []
        
        try:
            for report_file in HISTORY_DIR.glob("verification_report_*.json"):
                try:
                    with open(report_file, 'r') as f:
                        data = json.load(f)
                    
                    report = VerificationReport.from_dict(data)
                    if report.timestamp >= cutoff_date:
                        reports.append(report)
                except Exception as e:
                    logger.warning(f"Failed to load report {report_file}: {e}")
            
            # Sort by timestamp
            reports.sort(key=lambda r: r.timestamp)
            return reports
        except Exception as e:
            logger.error(f"Failed to get report history: {e}")
            return []
    
    def detect_changes(self, current: VerificationReport, previous: Optional[VerificationReport]) -> List[Dict[str, Any]]:
        """Detect changes between verification reports"""
        if not previous:
            return []
        
        changes = []
        
        # Check overall status changes
        if current.verification_complete != previous.verification_complete:
            changes.append({
                'type': 'verification_complete_changed',
                'from': previous.verification_complete,
                'to': current.verification_complete,
                'severity': 'high' if not current.verification_complete else 'medium'
            })
        
        if current.correspondence_complete != previous.correspondence_complete:
            changes.append({
                'type': 'correspondence_complete_changed',
                'from': previous.correspondence_complete,
                'to': current.correspondence_complete,
                'severity': 'high' if not current.correspondence_complete else 'medium'
            })
        
        # Check success rate changes
        rate_change = current.success_rate - previous.success_rate
        if abs(rate_change) > 1.0:  # More than 1% change
            changes.append({
                'type': 'success_rate_changed',
                'from': previous.success_rate,
                'to': current.success_rate,
                'change': rate_change,
                'severity': 'high' if rate_change < 0 else 'low'
            })
        
        # Check individual theorem status changes
        prev_theorems = {t.name: t for t in previous.theorems}
        for theorem in current.theorems:
            if theorem.name in prev_theorems:
                prev_theorem = prev_theorems[theorem.name]
                if theorem.status != prev_theorem.status:
                    changes.append({
                        'type': 'theorem_status_changed',
                        'theorem': theorem.name,
                        'from': prev_theorem.status.value,
                        'to': theorem.status.value,
                        'severity': self._get_status_change_severity(prev_theorem.status, theorem.status)
                    })
        
        # Check for new blocking issues
        prev_issues = {issue.get('theorem', '') for issue in previous.blocking_issues}
        for issue in current.blocking_issues:
            theorem_name = issue.get('theorem', '')
            if theorem_name not in prev_issues:
                changes.append({
                    'type': 'new_blocking_issue',
                    'theorem': theorem_name,
                    'issue': issue,
                    'severity': 'high'
                })
        
        return changes
    
    def _get_status_change_severity(self, from_status: VerificationStatus, to_status: VerificationStatus) -> str:
        """Determine severity of status change"""
        if from_status == VerificationStatus.PROVED and to_status != VerificationStatus.PROVED:
            return 'critical'  # Regression
        elif to_status == VerificationStatus.PROVED and from_status != VerificationStatus.PROVED:
            return 'low'  # Improvement
        elif to_status == VerificationStatus.FAILED:
            return 'high'  # New failure
        else:
            return 'medium'
    
    def cleanup_old_reports(self):
        """Remove old verification reports"""
        cutoff_date = datetime.now() - timedelta(days=self.keep_days)
        
        try:
            for report_file in HISTORY_DIR.glob("verification_report_*.json"):
                try:
                    # Extract timestamp from filename
                    timestamp_str = '_'.join(report_file.stem.split('_')[-2:])
                    timestamp = datetime.strptime(timestamp_str, '%Y%m%d_%H%M%S')
                    
                    if timestamp < cutoff_date:
                        if self.config['history']['compress_old_reports']:
                            # TODO: Implement compression
                            pass
                        else:
                            report_file.unlink()
                            logger.info(f"Removed old report: {report_file}")
                except Exception as e:
                    logger.warning(f"Failed to process old report {report_file}: {e}")
        except Exception as e:
            logger.error(f"Failed to cleanup old reports: {e}")

class AlertManager:
    """Manages alerts and notifications"""
    
    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.enabled = config['alerts']['enabled']
    
    def create_alert(self, level: AlertLevel, title: str, message: str, 
                    theorem_name: Optional[str] = None, details: Optional[Dict[str, Any]] = None) -> Alert:
        """Create a new alert"""
        alert = Alert(
            timestamp=datetime.now(),
            level=level,
            title=title,
            message=message,
            theorem_name=theorem_name,
            details=details
        )
        
        if self.enabled:
            self._save_alert(alert)
            self._send_notifications(alert)
        
        return alert
    
    def process_changes(self, changes: List[Dict[str, Any]]) -> List[Alert]:
        """Process changes and create appropriate alerts"""
        alerts = []
        
        if not self.enabled:
            return alerts
        
        for change in changes:
            alert = self._create_alert_from_change(change)
            if alert:
                alerts.append(alert)
        
        return alerts
    
    def _create_alert_from_change(self, change: Dict[str, Any]) -> Optional[Alert]:
        """Create alert from a detected change"""
        change_type = change['type']
        severity = change.get('severity', 'medium')
        
        # Map severity to alert level
        level_map = {
            'low': AlertLevel.INFO,
            'medium': AlertLevel.WARNING,
            'high': AlertLevel.ERROR,
            'critical': AlertLevel.CRITICAL
        }
        level = level_map.get(severity, AlertLevel.WARNING)
        
        if change_type == 'theorem_status_changed':
            if not self.config['alerts']['alert_on_status_change']:
                return None
            
            theorem = change['theorem']
            from_status = change['from']
            to_status = change['to']
            
            if severity == 'critical':
                title = f"REGRESSION: {theorem} verification failed"
                message = f"Theorem {theorem} status changed from {from_status} to {to_status}. This is a verification regression!"
            else:
                title = f"Theorem status changed: {theorem}"
                message = f"Theorem {theorem} status changed from {from_status} to {to_status}"
            
            return self.create_alert(level, title, message, theorem, change)
        
        elif change_type == 'new_blocking_issue':
            if not self.config['alerts']['alert_on_new_issues']:
                return None
            
            theorem = change['theorem']
            title = f"New blocking issue: {theorem}"
            message = f"New blocking issue detected for theorem {theorem}"
            
            return self.create_alert(level, title, message, theorem, change)
        
        elif change_type == 'verification_complete_changed':
            if change['to'] == False:  # Verification became incomplete
                title = "Verification completeness regression"
                message = "Overall verification is no longer complete"
                return self.create_alert(AlertLevel.CRITICAL, title, message, details=change)
        
        elif change_type == 'success_rate_changed':
            rate_change = change['change']
            if rate_change < -5.0:  # More than 5% decrease
                title = "Verification success rate decreased"
                message = f"Success rate decreased by {abs(rate_change):.1f}% (from {change['from']:.1f}% to {change['to']:.1f}%)"
                return self.create_alert(AlertLevel.ERROR, title, message, details=change)
        
        return None
    
    def _save_alert(self, alert: Alert):
        """Save alert to file"""
        try:
            timestamp_str = alert.timestamp.strftime('%Y%m%d_%H%M%S')
            filename = f"alert_{timestamp_str}_{alert.level.value}.json"
            filepath = ALERTS_DIR / filename
            
            with open(filepath, 'w') as f:
                json.dump(alert.to_dict(), f, indent=2)
            
            logger.info(f"Saved alert: {alert.title}")
        except Exception as e:
            logger.error(f"Failed to save alert: {e}")
    
    def _send_notifications(self, alert: Alert):
        """Send alert notifications"""
        try:
            # Log alert
            log_level = {
                AlertLevel.INFO: logging.INFO,
                AlertLevel.WARNING: logging.WARNING,
                AlertLevel.ERROR: logging.ERROR,
                AlertLevel.CRITICAL: logging.CRITICAL
            }[alert.level]
            
            logger.log(log_level, f"ALERT [{alert.level.value.upper()}]: {alert.title} - {alert.message}")
            
            # TODO: Implement email notifications
            if self.config['alerts']['email_notifications']:
                pass
            
            # TODO: Implement Slack notifications
            if self.config['alerts']['slack_webhook']:
                pass
                
        except Exception as e:
            logger.error(f"Failed to send notifications: {e}")

class DocumentationUpdater:
    """Updates WhitepaperMapping.md with current verification status"""
    
    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.auto_update = config['documentation']['auto_update_mapping']
        self.backup_before_update = config['documentation']['backup_before_update']
    
    def update_mapping_document(self, report: VerificationReport) -> bool:
        """Update the WhitepaperMapping.md document with current status"""
        if not self.auto_update:
            logger.info("Auto-update disabled, skipping documentation update")
            return True
        
        try:
            # Backup original if requested
            if self.backup_before_update:
                self._backup_mapping_document()
            
            # Read current document
            if not MAPPING_DOC.exists():
                logger.error(f"Mapping document not found: {MAPPING_DOC}")
                return False
            
            with open(MAPPING_DOC, 'r') as f:
                content = f.read()
            
            # Update content with current verification status
            updated_content = self._update_document_content(content, report)
            
            # Write updated content
            with open(MAPPING_DOC, 'w') as f:
                f.write(updated_content)
            
            logger.info("Successfully updated WhitepaperMapping.md")
            return True
            
        except Exception as e:
            logger.error(f"Failed to update mapping document: {e}")
            return False
    
    def _backup_mapping_document(self):
        """Create backup of mapping document"""
        try:
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            backup_path = MAPPING_DOC.parent / f"WhitepaperMapping_backup_{timestamp}.md"
            shutil.copy2(MAPPING_DOC, backup_path)
            logger.info(f"Created backup: {backup_path}")
        except Exception as e:
            logger.warning(f"Failed to create backup: {e}")
    
    def _update_document_content(self, content: str, report: VerificationReport) -> str:
        """Update document content with current verification status"""
        # Update executive summary
        content = self._update_executive_summary(content, report)
        
        # Update individual theorem status
        content = self._update_theorem_status(content, report)
        
        # Add verification audit results section
        content = self._add_verification_audit_section(content, report)
        
        # Update traceability matrix
        content = self._update_traceability_matrix(content, report)
        
        return content
    
    def _update_executive_summary(self, content: str, report: VerificationReport) -> str:
        """Update the executive summary with current status"""
        # Replace the "100% Complete" claim with actual status
        if report.verification_complete:
            status_text = f"✅ **{report.success_rate:.1f}% Complete** (Verified: {report.timestamp.strftime('%Y-%m-%d %H:%M')})"
        else:
            status_text = f"⚠️ **{report.success_rate:.1f}% Complete** (Issues detected - see audit results below)"
        
        # Update mapping coverage section
        pattern = r'### Mapping Coverage: \*\*.*?\*\*'
        replacement = f'### Mapping Coverage: **{report.success_rate:.1f}% Complete**'
        content = re.sub(pattern, replacement, content)
        
        # Update status indicators
        main_theorems_status = "✅" if self._check_main_theorems_status(report) else "⚠️"
        supporting_lemmas_status = "✅" if self._check_supporting_lemmas_status(report) else "⚠️"
        
        # Update the status list
        status_section = f"""
{main_theorems_status} **Main Theorems**: Safety (Theorem 1) and Liveness (Theorem 2) - {self._get_main_theorems_summary(report)}
{supporting_lemmas_status} **Supporting Lemmas**: {self._get_supporting_lemmas_summary(report)}
✅ **Traceability**: Direct correspondence between whitepaper statements and TLA+ proofs  
{'✅' if report.verification_complete else '⚠️'} **Machine Verification**: {self._get_verification_summary(report)}
"""
        
        # Replace the existing status section
        pattern = r'✅ \*\*Main Theorems\*\*:.*?✅ \*\*Machine Verification\*\*:.*?\n'
        content = re.sub(pattern, status_section.strip() + '\n', content, flags=re.DOTALL)
        
        return content
    
    def _update_theorem_status(self, content: str, report: VerificationReport) -> str:
        """Update individual theorem verification status"""
        for theorem in report.theorems:
            # Update status in theorem tables
            status_symbol = self._get_status_symbol(theorem.status)
            status_text = self._get_status_text(theorem.status)
            
            # Look for theorem entries in tables
            pattern = rf'\| \*\*{re.escape(theorem.name)}\*\* \|.*?\| .*? \|'
            replacement = f'| **{theorem.name}** | `WhitepaperTheorems.tla:{theorem.line_number}` | {status_text} | {status_symbol} |'
            content = re.sub(pattern, replacement, content)
        
        return content
    
    def _add_verification_audit_section(self, content: str, report: VerificationReport) -> str:
        """Add or update verification audit results section"""
        audit_section = self._generate_audit_section(report)
        
        # Look for existing audit section
        pattern = r'## \d+\. Verification Audit Results.*?(?=## \d+\.|\Z)'
        if re.search(pattern, content, re.DOTALL):
            # Replace existing section
            content = re.sub(pattern, audit_section, content, flags=re.DOTALL)
        else:
            # Add new section before conclusion
            conclusion_pattern = r'(## \d+\. Conclusion)'
            if re.search(conclusion_pattern, content):
                content = re.sub(conclusion_pattern, audit_section + r'\n\1', content)
            else:
                # Add at the end
                content += '\n\n' + audit_section
        
        return content
    
    def _generate_audit_section(self, report: VerificationReport) -> str:
        """Generate verification audit results section"""
        timestamp_str = report.timestamp.strftime('%Y-%m-%d %H:%M:%S UTC')
        
        section = f"""## Verification Audit Results

**Last Updated**: {timestamp_str}

### Overall Status

- **Total Theorems**: {report.total_theorems}
- **Verification Success Rate**: {report.success_rate:.1f}%
- **Verification Complete**: {'✅ Yes' if report.verification_complete else '❌ No'}
- **Correspondence Complete**: {'✅ Yes' if report.correspondence_complete else '❌ No'}

### Detailed Status Breakdown

| Status | Count | Percentage |
|--------|-------|------------|
"""
        
        for status, count in report.verification_status.items():
            percentage = (count / report.total_theorems * 100) if report.total_theorems > 0 else 0
            symbol = self._get_status_symbol(VerificationStatus(status))
            section += f"| {symbol} {status.title()} | {count} | {percentage:.1f}% |\n"
        
        # Add blocking issues if any
        if report.blocking_issues:
            section += "\n### Blocking Issues\n\n"
            for issue in report.blocking_issues:
                theorem = issue.get('theorem', 'Unknown')
                status = issue.get('status', 'unknown')
                issues = issue.get('issues', [])
                
                section += f"**{theorem}** ({status}):\n"
                for issue_detail in issues:
                    section += f"- {issue_detail}\n"
                section += "\n"
        
        # Add individual theorem details
        section += "\n### Individual Theorem Status\n\n"
        section += "| Theorem | Type | Status | Last Verified | Issues |\n"
        section += "|---------|------|--------|---------------|--------|\n"
        
        for theorem in sorted(report.theorems, key=lambda t: t.name):
            status_symbol = self._get_status_symbol(theorem.status)
            last_verified = theorem.last_verified.strftime('%Y-%m-%d') if theorem.last_verified else 'Never'
            issues_count = len(theorem.errors)
            issues_text = f"{issues_count} issues" if issues_count > 0 else "None"
            
            section += f"| {theorem.name} | {theorem.type} | {status_symbol} {theorem.status.value} | {last_verified} | {issues_text} |\n"
        
        return section
    
    def _update_traceability_matrix(self, content: str, report: VerificationReport) -> str:
        """Update traceability matrix with actual verification status"""
        # Find and update the quick reference table
        pattern = r'(\| \*\*Theorem \d+ \(.*?\)\*\* \| Section .*? \| `.*?` \| )✅ Proven( \|)'
        
        for theorem in report.theorems:
            if 'Theorem' in theorem.name:
                status_symbol = self._get_status_symbol(theorem.status)
                status_text = f"{status_symbol} {theorem.status.value.title()}"
                
                # Update specific theorem entry
                theorem_pattern = rf'(\| \*\*{re.escape(theorem.name)}.*?\| )✅ Proven( \|)'
                content = re.sub(theorem_pattern, rf'\1{status_text}\2', content)
        
        return content
    
    def _get_status_symbol(self, status: VerificationStatus) -> str:
        """Get emoji symbol for verification status"""
        symbols = {
            VerificationStatus.PROVED: "✅",
            VerificationStatus.FAILED: "❌",
            VerificationStatus.PARTIAL: "⚠️",
            VerificationStatus.UNKNOWN: "❓",
            VerificationStatus.NOT_PROCESSED: "⏸️",
            VerificationStatus.ERROR: "🔥"
        }
        return symbols.get(status, "❓")
    
    def _get_status_text(self, status: VerificationStatus) -> str:
        """Get human-readable status text"""
        return status.value.replace('_', ' ').title()
    
    def _check_main_theorems_status(self, report: VerificationReport) -> bool:
        """Check if main theorems (1 and 2) are verified"""
        main_theorems = [t for t in report.theorems if 'Theorem' in t.name and t.name in ['WhitepaperTheorem1', 'WhitepaperTheorem2']]
        return all(t.status == VerificationStatus.PROVED for t in main_theorems)
    
    def _check_supporting_lemmas_status(self, report: VerificationReport) -> bool:
        """Check if supporting lemmas are verified"""
        lemmas = [t for t in report.theorems if t.type == 'LEMMA']
        if not lemmas:
            return False
        proved_count = sum(1 for t in lemmas if t.status == VerificationStatus.PROVED)
        return (proved_count / len(lemmas)) >= 0.8  # At least 80% proved
    
    def _get_main_theorems_summary(self, report: VerificationReport) -> str:
        """Get summary of main theorems status"""
        main_theorems = [t for t in report.theorems if 'Theorem' in t.name and t.name in ['WhitepaperTheorem1', 'WhitepaperTheorem2']]
        proved_count = sum(1 for t in main_theorems if t.status == VerificationStatus.PROVED)
        return f"{proved_count}/2 verified"
    
    def _get_supporting_lemmas_summary(self, report: VerificationReport) -> str:
        """Get summary of supporting lemmas status"""
        lemmas = [t for t in report.theorems if t.type == 'LEMMA']
        if not lemmas:
            return "No lemmas found"
        proved_count = sum(1 for t in lemmas if t.status == VerificationStatus.PROVED)
        return f"{proved_count}/{len(lemmas)} verified"
    
    def _get_verification_summary(self, report: VerificationReport) -> str:
        """Get overall verification summary"""
        if report.verification_complete:
            return "All proofs verified by TLAPS"
        else:
            return f"{report.success_rate:.1f}% verified, {len(report.blocking_issues)} blocking issues"

class CICDIntegration:
    """CI/CD pipeline integration"""
    
    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.enabled = config['ci_cd']['enabled']
        self.fail_on_regression = config['ci_cd']['fail_on_regression']
        self.fail_on_incomplete = config['ci_cd']['fail_on_incomplete_verification']
        self.generate_junit = config['ci_cd']['generate_junit_xml']
    
    def check_ci_conditions(self, report: VerificationReport, changes: List[Dict[str, Any]]) -> Tuple[bool, str]:
        """Check if CI should pass or fail based on verification results"""
        if not self.enabled:
            return True, "CI/CD integration disabled"
        
        # Check for regressions
        if self.fail_on_regression:
            regressions = [c for c in changes if c.get('severity') == 'critical']
            if regressions:
                return False, f"Verification regressions detected: {len(regressions)} critical issues"
        
        # Check for incomplete verification
        if self.fail_on_incomplete and not report.verification_complete:
            return False, f"Verification incomplete: {report.success_rate:.1f}% success rate"
        
        return True, "All CI conditions passed"
    
    def generate_junit_xml(self, report: VerificationReport) -> Optional[Path]:
        """Generate JUnit XML report for CI systems"""
        if not self.generate_junit:
            return None
        
        try:
            from xml.etree.ElementTree import Element, SubElement, tostring
            from xml.dom import minidom
            
            # Create root element
            testsuites = Element('testsuites')
            testsuites.set('name', 'Alpenglow Verification')
            testsuites.set('tests', str(len(report.theorems)))
            testsuites.set('failures', str(sum(1 for t in report.theorems if t.status == VerificationStatus.FAILED)))
            testsuites.set('errors', str(sum(1 for t in report.theorems if t.status == VerificationStatus.ERROR)))
            testsuites.set('time', str(sum(t.verification_time or 0 for t in report.theorems)))
            
            # Create testsuite
            testsuite = SubElement(testsuites, 'testsuite')
            testsuite.set('name', 'Whitepaper Theorems')
            testsuite.set('tests', str(len(report.theorems)))
            
            # Add test cases
            for theorem in report.theorems:
                testcase = SubElement(testsuite, 'testcase')
                testcase.set('name', theorem.name)
                testcase.set('classname', f'Alpenglow.{theorem.type}')
                testcase.set('time', str(theorem.verification_time or 0))
                
                if theorem.status == VerificationStatus.FAILED:
                    failure = SubElement(testcase, 'failure')
                    failure.set('message', f'Verification failed for {theorem.name}')
                    failure.text = '\n'.join(theorem.errors)
                elif theorem.status == VerificationStatus.ERROR:
                    error = SubElement(testcase, 'error')
                    error.set('message', f'Verification error for {theorem.name}')
                    error.text = '\n'.join(theorem.errors)
                elif theorem.status in [VerificationStatus.UNKNOWN, VerificationStatus.NOT_PROCESSED]:
                    skipped = SubElement(testcase, 'skipped')
                    skipped.set('message', f'Verification not completed for {theorem.name}')
            
            # Write to file
            xml_str = minidom.parseString(tostring(testsuites)).toprettyxml(indent="  ")
            junit_file = PROJECT_ROOT / "verification_junit.xml"
            
            with open(junit_file, 'w') as f:
                f.write(xml_str)
            
            logger.info(f"Generated JUnit XML: {junit_file}")
            return junit_file
            
        except Exception as e:
            logger.error(f"Failed to generate JUnit XML: {e}")
            return None

class VerificationTracker:
    """Main verification tracking system"""
    
    def __init__(self, config_path: Optional[Path] = None):
        self.config_manager = ConfigManager()
        self.config = self.config_manager.config
        
        self.verification_runner = VerificationRunner(self.config)
        self.history_manager = HistoryManager(self.config)
        self.alert_manager = AlertManager(self.config)
        self.documentation_updater = DocumentationUpdater(self.config)
        self.ci_cd = CICDIntegration(self.config)
        
        self.running = False
        self.check_interval = self.config['verification']['check_interval_minutes'] * 60
    
    def run_single_check(self) -> bool:
        """Run a single verification check"""
        logger.info("Starting verification check")
        
        try:
            # Run verification
            current_report = self.verification_runner.run_verification()
            if not current_report:
                logger.error("Verification failed")
                return False
            
            # Get previous report for comparison
            previous_report = self.history_manager.get_latest_report()
            
            # Save current report
            self.history_manager.save_report(current_report)
            
            # Detect changes
            changes = self.history_manager.detect_changes(current_report, previous_report)
            
            # Process alerts
            alerts = self.alert_manager.process_changes(changes)
            
            # Update documentation if needed
            if self.config['documentation']['update_on_status_change'] and changes:
                self.documentation_updater.update_mapping_document(current_report)
            elif not previous_report:  # First run
                self.documentation_updater.update_mapping_document(current_report)
            
            # Check CI/CD conditions
            ci_pass, ci_message = self.ci_cd.check_ci_conditions(current_report, changes)
            logger.info(f"CI/CD status: {'PASS' if ci_pass else 'FAIL'} - {ci_message}")
            
            # Generate JUnit XML if requested
            self.ci_cd.generate_junit_xml(current_report)
            
            # Log summary
            logger.info(f"Verification check completed: {current_report.success_rate:.1f}% success rate, "
                       f"{len(changes)} changes detected, {len(alerts)} alerts generated")
            
            return ci_pass
            
        except Exception as e:
            logger.error(f"Verification check failed: {e}")
            return False
    
    def start_continuous_monitoring(self):
        """Start continuous verification monitoring"""
        logger.info(f"Starting continuous monitoring (check interval: {self.check_interval}s)")
        self.running = True
        
        try:
            while self.running:
                self.run_single_check()
                
                # Cleanup old reports periodically
                self.history_manager.cleanup_old_reports()
                
                # Wait for next check
                time.sleep(self.check_interval)
                
        except KeyboardInterrupt:
            logger.info("Monitoring stopped by user")
        except Exception as e:
            logger.error(f"Monitoring failed: {e}")
        finally:
            self.running = False
    
    def stop_monitoring(self):
        """Stop continuous monitoring"""
        self.running = False
    
    def get_status_summary(self) -> Dict[str, Any]:
        """Get current verification status summary"""
        latest_report = self.history_manager.get_latest_report()
        if not latest_report:
            return {"status": "no_data", "message": "No verification reports available"}
        
        return {
            "status": "complete" if latest_report.verification_complete else "incomplete",
            "success_rate": latest_report.success_rate,
            "total_theorems": latest_report.total_theorems,
            "last_check": latest_report.timestamp.isoformat(),
            "verification_status": latest_report.verification_status,
            "blocking_issues": len(latest_report.blocking_issues)
        }
    
    def validate_claims(self) -> List[Dict[str, Any]]:
        """Validate that all claims in mapping document are backed by evidence"""
        discrepancies = []
        
        try:
            # Read mapping document
            if not MAPPING_DOC.exists():
                return [{"type": "missing_document", "message": "WhitepaperMapping.md not found"}]
            
            with open(MAPPING_DOC, 'r') as f:
                content = f.read()
            
            # Get latest verification report
            latest_report = self.history_manager.get_latest_report()
            if not latest_report:
                return [{"type": "no_verification_data", "message": "No verification reports available"}]
            
            # Check for "100% Complete" claims
            if "100% Complete" in content and not latest_report.verification_complete:
                discrepancies.append({
                    "type": "false_completeness_claim",
                    "message": f"Document claims 100% complete but actual rate is {latest_report.success_rate:.1f}%"
                })
            
            # Check individual theorem status claims
            proven_pattern = r'✅ Proven'
            proven_matches = re.findall(proven_pattern, content)
            actual_proven = sum(1 for t in latest_report.theorems if t.status == VerificationStatus.PROVED)
            
            if len(proven_matches) > actual_proven:
                discrepancies.append({
                    "type": "inflated_proven_count",
                    "message": f"Document shows {len(proven_matches)} proven theorems but only {actual_proven} are actually proven"
                })
            
            # Check for outdated status information
            for theorem in latest_report.theorems:
                if theorem.status != VerificationStatus.PROVED:
                    # Look for this theorem being marked as proven in the document
                    theorem_pattern = rf'{re.escape(theorem.name)}.*?✅ Proven'
                    if re.search(theorem_pattern, content, re.DOTALL):
                        discrepancies.append({
                            "type": "outdated_theorem_status",
                            "theorem": theorem.name,
                            "claimed_status": "proven",
                            "actual_status": theorem.status.value,
                            "message": f"Document claims {theorem.name} is proven but actual status is {theorem.status.value}"
                        })
            
            return discrepancies
            
        except Exception as e:
            logger.error(f"Failed to validate claims: {e}")
            return [{"type": "validation_error", "message": str(e)}]

def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description="Alpenglow Verification Tracking System")
    parser.add_argument('--mode', choices=['single', 'continuous', 'status', 'validate'], 
                       default='single', help='Operation mode')
    parser.add_argument('--config', type=Path, help='Configuration file path')
    parser.add_argument('--ci', action='store_true', help='CI/CD mode (exit with error code on failure)')
    parser.add_argument('--update-docs', action='store_true', help='Force documentation update')
    parser.add_argument('--verbose', '-v', action='store_true', help='Verbose logging')
    
    args = parser.parse_args()
    
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    # Initialize tracker
    tracker = VerificationTracker(args.config)
    
    try:
        if args.mode == 'single':
            success = tracker.run_single_check()
            if args.update_docs:
                latest_report = tracker.history_manager.get_latest_report()
                if latest_report:
                    tracker.documentation_updater.update_mapping_document(latest_report)
            
            if args.ci and not success:
                sys.exit(1)
                
        elif args.mode == 'continuous':
            tracker.start_continuous_monitoring()
            
        elif args.mode == 'status':
            status = tracker.get_status_summary()
            print(json.dumps(status, indent=2))
            
        elif args.mode == 'validate':
            discrepancies = tracker.validate_claims()
            if discrepancies:
                print("Validation discrepancies found:")
                for disc in discrepancies:
                    print(f"- {disc['type']}: {disc['message']}")
                if args.ci:
                    sys.exit(1)
            else:
                print("All claims validated successfully")
                
    except KeyboardInterrupt:
        logger.info("Operation interrupted by user")
        sys.exit(0)
    except Exception as e:
        logger.error(f"Operation failed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()