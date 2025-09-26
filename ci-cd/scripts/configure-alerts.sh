#!/bin/bash

#############################################################################
# Alert Configuration Script
# 
# Configures email and Slack alerting for Alpenglow verification pipeline
# with customizable thresholds and notification channels.
#############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ALERTS_DIR="$PROJECT_ROOT/ci-cd/monitoring/alerts"

# Default configuration
EMAIL=""
SLACK_WEBHOOK=""
SLACK_CHANNEL=""
ALERT_THRESHOLD="critical"
NOTIFICATION_COOLDOWN=300  # 5 minutes

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

print_banner() {
    echo -e "${PURPLE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${NC} ${BLUE}$1${NC} ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════════════════════╝${NC}"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

show_help() {
    cat << EOF
Alpenglow Verification Alert Configuration

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --email EMAIL           Email address for alerts
    --slack WEBHOOK_URL     Slack webhook URL for notifications
    --slack-channel CHANNEL Slack channel name (e.g., #alpenglow-verification)
    --threshold LEVEL       Alert threshold: info, warning, critical (default: critical)
    --cooldown SECONDS      Notification cooldown period (default: 300)
    --test                  Send test notifications
    --help                  Show this help message

EXAMPLES:
    $0 --email team@company.com --slack-channel #alpenglow-verification
    $0 --email alerts@company.com --threshold warning --cooldown 600
    $0 --test  # Send test notifications
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --email)
            EMAIL="$2"
            shift 2
            ;;
        --slack)
            SLACK_WEBHOOK="$2"
            shift 2
            ;;
        --slack-channel)
            SLACK_CHANNEL="$2"
            shift 2
            ;;
        --threshold)
            ALERT_THRESHOLD="$2"
            shift 2
            ;;
        --cooldown)
            NOTIFICATION_COOLDOWN="$2"
            shift 2
            ;;
        --test)
            TEST_MODE=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Create alerts directory
mkdir -p "$ALERTS_DIR"

print_banner "Alpenglow Verification Alert Configuration"

# Create alert configuration file
cat > "$ALERTS_DIR/config.json" << EOF
{
  "email": {
    "enabled": $([ -n "$EMAIL" ] && echo "true" || echo "false"),
    "address": "$EMAIL",
    "smtp_server": "localhost",
    "smtp_port": 587
  },
  "slack": {
    "enabled": $([ -n "$SLACK_WEBHOOK" ] && echo "true" || echo "false"),
    "webhook_url": "$SLACK_WEBHOOK",
    "channel": "$SLACK_CHANNEL",
    "username": "Alpenglow Verification Bot",
    "icon_emoji": ":microscope:"
  },
  "thresholds": {
    "level": "$ALERT_THRESHOLD",
    "cooldown_seconds": $NOTIFICATION_COOLDOWN,
    "rules": {
      "verification_failure": {
        "enabled": true,
        "threshold": 1,
        "message": "Verification failure detected"
      },
      "proof_obligation_failure": {
        "enabled": true,
        "threshold": 5,
        "message": "Multiple proof obligations failed"
      },
      "performance_degradation": {
        "enabled": true,
        "threshold": 2400,
        "message": "Verification time exceeded 40 minutes"
      },
      "cross_validation_failure": {
        "enabled": true,
        "threshold": 95,
        "message": "Cross-validation consistency below 95%"
      }
    }
  }
}
EOF

# Create alert sender script
cat > "$ALERTS_DIR/send_alert.py" << 'EOF'
#!/usr/bin/env python3

"""
Alpenglow Verification Alert Sender

Sends alerts via email and Slack based on verification pipeline status.
"""

import json
import smtplib
import requests
import sys
import time
from datetime import datetime
from email.mime.text import MimeText
from email.mime.multipart import MimeMultipart
from pathlib import Path

class AlertSender:
    def __init__(self, config_file):
        with open(config_file, 'r') as f:
            self.config = json.load(f)
        
        self.cooldown_file = Path(config_file).parent / 'cooldown.json'
        self.load_cooldown_state()
    
    def load_cooldown_state(self):
        """Load cooldown state to prevent spam."""
        try:
            if self.cooldown_file.exists():
                with open(self.cooldown_file, 'r') as f:
                    self.cooldown_state = json.load(f)
            else:
                self.cooldown_state = {}
        except:
            self.cooldown_state = {}
    
    def save_cooldown_state(self):
        """Save cooldown state."""
        try:
            with open(self.cooldown_file, 'w') as f:
                json.dump(self.cooldown_state, f)
        except Exception as e:
            print(f"Warning: Could not save cooldown state: {e}")
    
    def should_send_alert(self, alert_type):
        """Check if alert should be sent based on cooldown."""
        now = time.time()
        last_sent = self.cooldown_state.get(alert_type, 0)
        cooldown = self.config['thresholds']['cooldown_seconds']
        
        return (now - last_sent) >= cooldown
    
    def send_email_alert(self, subject, message):
        """Send email alert."""
        if not self.config['email']['enabled']:
            return False
        
        try:
            msg = MimeMultipart()
            msg['From'] = 'alpenglow-verification@localhost'
            msg['To'] = self.config['email']['address']
            msg['Subject'] = subject
            
            msg.attach(MimeText(message, 'plain'))
            
            server = smtplib.SMTP(
                self.config['email']['smtp_server'],
                self.config['email']['smtp_port']
            )
            server.send_message(msg)
            server.quit()
            
            return True
        except Exception as e:
            print(f"Email alert failed: {e}")
            return False
    
    def send_slack_alert(self, message, color="danger"):
        """Send Slack alert."""
        if not self.config['slack']['enabled']:
            return False
        
        try:
            payload = {
                "channel": self.config['slack']['channel'],
                "username": self.config['slack']['username'],
                "icon_emoji": self.config['slack']['icon_emoji'],
                "attachments": [{
                    "color": color,
                    "title": "🔬 Alpenglow Verification Alert",
                    "text": message,
                    "timestamp": int(time.time())
                }]
            }
            
            response = requests.post(
                self.config['slack']['webhook_url'],
                json=payload,
                timeout=10
            )
            
            return response.status_code == 200
        except Exception as e:
            print(f"Slack alert failed: {e}")
            return False
    
    def send_alert(self, alert_type, subject, message, severity="critical"):
        """Send alert via configured channels."""
        if not self.should_send_alert(alert_type):
            print(f"Alert {alert_type} in cooldown, skipping")
            return
        
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        full_message = f"[{timestamp}] {message}"
        
        success = False
        
        # Send email
        if self.config['email']['enabled']:
            if self.send_email_alert(subject, full_message):
                print(f"✓ Email alert sent for {alert_type}")
                success = True
            else:
                print(f"✗ Email alert failed for {alert_type}")
        
        # Send Slack
        if self.config['slack']['enabled']:
            color = {
                "info": "good",
                "warning": "warning", 
                "critical": "danger"
            }.get(severity, "danger")
            
            if self.send_slack_alert(full_message, color):
                print(f"✓ Slack alert sent for {alert_type}")
                success = True
            else:
                print(f"✗ Slack alert failed for {alert_type}")
        
        if success:
            # Update cooldown state
            self.cooldown_state[alert_type] = time.time()
            self.save_cooldown_state()
    
    def send_test_alert(self):
        """Send test alerts to verify configuration."""
        test_message = "This is a test alert from Alpenglow Verification system. Configuration is working correctly!"
        
        print("Sending test alerts...")
        self.send_alert(
            "test",
            "🧪 Alpenglow Verification Test Alert",
            test_message,
            "info"
        )

def main():
    if len(sys.argv) < 2:
        print("Usage: send_alert.py <config_file> [--test]")
        sys.exit(1)
    
    config_file = sys.argv[1]
    
    try:
        sender = AlertSender(config_file)
        
        if len(sys.argv) > 2 and sys.argv[2] == '--test':
            sender.send_test_alert()
        else:
            # Read alert details from stdin or command line
            if len(sys.argv) >= 5:
                alert_type = sys.argv[2]
                subject = sys.argv[3]
                message = sys.argv[4]
                severity = sys.argv[5] if len(sys.argv) > 5 else "critical"
                
                sender.send_alert(alert_type, subject, message, severity)
            else:
                print("Usage: send_alert.py <config_file> <type> <subject> <message> [severity]")
                sys.exit(1)
                
    except Exception as e:
        print(f"Alert system error: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
EOF

chmod +x "$ALERTS_DIR/send_alert.py"

# Create alert monitoring script
cat > "$ALERTS_DIR/monitor.py" << 'EOF'
#!/usr/bin/env python3

"""
Alpenglow Verification Alert Monitor

Continuously monitors verification results and sends alerts based on configured rules.
"""

import json
import time
import sys
from pathlib import Path
from subprocess import run, PIPE

class VerificationMonitor:
    def __init__(self, config_file, project_root):
        self.config_file = Path(config_file)
        self.project_root = Path(project_root)
        self.alert_sender = self.config_file.parent / 'send_alert.py'
        
        with open(config_file, 'r') as f:
            self.config = json.load(f)
    
    def check_verification_status(self):
        """Check current verification status and trigger alerts if needed."""
        alerts_triggered = []
        
        # Check regression test results
        regression_file = self.project_root / 'ci-cd' / 'results' / 'regression_test_report.json'
        if regression_file.exists():
            try:
                with open(regression_file, 'r') as f:
                    data = json.load(f)
                
                # Check for verification failures
                failed_modules = data.get('failed_modules', [])
                if len(failed_modules) > 0:
                    self.send_alert(
                        'verification_failure',
                        f'🚨 Verification Failure: {len(failed_modules)} modules failed',
                        f'Failed modules: {", ".join(failed_modules)}',
                        'critical'
                    )
                    alerts_triggered.append('verification_failure')
                
                # Check performance
                total_time = data.get('total_time_seconds', 0)
                if total_time > self.config['thresholds']['rules']['performance_degradation']['threshold']:
                    self.send_alert(
                        'performance_degradation',
                        f'⚠️ Performance Alert: Verification took {total_time//60}m {total_time%60}s',
                        f'Verification exceeded 40-minute target by {(total_time-2400)//60} minutes',
                        'warning'
                    )
                    alerts_triggered.append('performance_degradation')
                
                # Check proof obligations
                total_obligations = data.get('total_obligations', 0)
                verified_obligations = data.get('verified_obligations', 0)
                failed_obligations = total_obligations - verified_obligations
                
                if failed_obligations >= self.config['thresholds']['rules']['proof_obligation_failure']['threshold']:
                    self.send_alert(
                        'proof_obligation_failure',
                        f'❌ Proof Obligation Failures: {failed_obligations} failed',
                        f'Failed to verify {failed_obligations}/{total_obligations} proof obligations',
                        'critical'
                    )
                    alerts_triggered.append('proof_obligation_failure')
                    
            except Exception as e:
                print(f"Error checking regression results: {e}")
        
        # Check cross-validation results
        cross_val_file = self.project_root / 'cross-validation' / 'results' / 'dual_framework_summary.json'
        if cross_val_file.exists():
            try:
                with open(cross_val_file, 'r') as f:
                    data = json.load(f)
                
                consistency_rate = data.get('consistency_rate', 100)
                threshold = self.config['thresholds']['rules']['cross_validation_failure']['threshold']
                
                if consistency_rate < threshold:
                    self.send_alert(
                        'cross_validation_failure',
                        f'🔄 Cross-Validation Alert: {consistency_rate}% consistency',
                        f'TLA+ vs Stateright consistency below {threshold}% threshold',
                        'warning'
                    )
                    alerts_triggered.append('cross_validation_failure')
                    
            except Exception as e:
                print(f"Error checking cross-validation results: {e}")
        
        return alerts_triggered
    
    def send_alert(self, alert_type, subject, message, severity):
        """Send alert using the alert sender script."""
        try:
            result = run([
                'python3', str(self.alert_sender),
                str(self.config_file),
                alert_type, subject, message, severity
            ], capture_output=True, text=True)
            
            if result.returncode == 0:
                print(f"Alert sent: {alert_type}")
            else:
                print(f"Alert failed: {alert_type} - {result.stderr}")
                
        except Exception as e:
            print(f"Error sending alert {alert_type}: {e}")
    
    def run_monitor(self, interval=60):
        """Run continuous monitoring loop."""
        print(f"🔍 Starting Alpenglow verification monitoring (interval: {interval}s)")
        print(f"📧 Email alerts: {'enabled' if self.config['email']['enabled'] else 'disabled'}")
        print(f"💬 Slack alerts: {'enabled' if self.config['slack']['enabled'] else 'disabled'}")
        print("Press Ctrl+C to stop")
        
        try:
            while True:
                alerts = self.check_verification_status()
                if alerts:
                    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Triggered alerts: {', '.join(alerts)}")
                else:
                    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] No alerts triggered")
                
                time.sleep(interval)
                
        except KeyboardInterrupt:
            print("\n🛑 Monitoring stopped")

def main():
    if len(sys.argv) < 3:
        print("Usage: monitor.py <config_file> <project_root> [interval_seconds]")
        sys.exit(1)
    
    config_file = sys.argv[1]
    project_root = sys.argv[2]
    interval = int(sys.argv[3]) if len(sys.argv) > 3 else 60
    
    monitor = VerificationMonitor(config_file, project_root)
    monitor.run_monitor(interval)

if __name__ == '__main__':
    main()
EOF

chmod +x "$ALERTS_DIR/monitor.py"

# Create alert management script
cat > "$ALERTS_DIR/manage_alerts.sh" << EOF
#!/bin/bash

ALERTS_DIR="$ALERTS_DIR"
CONFIG_FILE="\$ALERTS_DIR/config.json"

case "\${1:-help}" in
    start)
        echo "🚀 Starting alert monitoring..."
        python3 "\$ALERTS_DIR/monitor.py" "\$CONFIG_FILE" "$PROJECT_ROOT" 60 &
        echo \$! > "\$ALERTS_DIR/monitor.pid"
        echo "✓ Alert monitoring started (PID: \$(cat \$ALERTS_DIR/monitor.pid))"
        ;;
    stop)
        if [[ -f "\$ALERTS_DIR/monitor.pid" ]]; then
            PID=\$(cat "\$ALERTS_DIR/monitor.pid")
            if kill "\$PID" 2>/dev/null; then
                echo "✓ Alert monitoring stopped (PID: \$PID)"
                rm "\$ALERTS_DIR/monitor.pid"
            else
                echo "⚠ Process \$PID not found"
            fi
        else
            echo "⚠ No monitor PID file found"
        fi
        ;;
    test)
        echo "🧪 Sending test alerts..."
        python3 "\$ALERTS_DIR/send_alert.py" "\$CONFIG_FILE" --test
        ;;
    status)
        if [[ -f "\$ALERTS_DIR/monitor.pid" ]]; then
            PID=\$(cat "\$ALERTS_DIR/monitor.pid")
            if kill -0 "\$PID" 2>/dev/null; then
                echo "✓ Alert monitoring is running (PID: \$PID)"
            else
                echo "✗ Alert monitoring is not running"
                rm "\$ALERTS_DIR/monitor.pid"
            fi
        else
            echo "✗ Alert monitoring is not running"
        fi
        ;;
    *)
        echo "Usage: \$0 {start|stop|test|status}"
        echo ""
        echo "Commands:"
        echo "  start  - Start alert monitoring"
        echo "  stop   - Stop alert monitoring"
        echo "  test   - Send test alerts"
        echo "  status - Check monitoring status"
        ;;
esac
EOF

chmod +x "$ALERTS_DIR/manage_alerts.sh"

print_success "✓ Alert configuration completed"
print_info "📁 Alerts directory: $ALERTS_DIR"
print_info "⚙️ Configuration file: $ALERTS_DIR/config.json"

if [[ -n "$EMAIL" ]]; then
    print_success "📧 Email alerts configured: $EMAIL"
fi

if [[ -n "$SLACK_CHANNEL" ]]; then
    print_success "💬 Slack alerts configured: $SLACK_CHANNEL"
fi

print_info ""
print_info "Alert management commands:"
print_info "  $ALERTS_DIR/manage_alerts.sh start   # Start monitoring"
print_info "  $ALERTS_DIR/manage_alerts.sh test    # Send test alerts"
print_info "  $ALERTS_DIR/manage_alerts.sh status  # Check status"
print_info "  $ALERTS_DIR/manage_alerts.sh stop    # Stop monitoring"

# Send test alerts if requested
if [[ "${TEST_MODE:-false}" == "true" ]]; then
    print_info "🧪 Sending test alerts..."
    python3 "$ALERTS_DIR/send_alert.py" "$ALERTS_DIR/config.json" --test
fi

exit 0
