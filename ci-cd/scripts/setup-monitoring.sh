#!/bin/bash

#############################################################################
# Monitoring Dashboard Setup Script
# 
# Sets up real-time monitoring dashboard for Alpenglow verification pipeline
# with metrics collection, visualization, and alerting capabilities.
#############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MONITORING_DIR="$PROJECT_ROOT/ci-cd/monitoring"
DASHBOARD_PORT=8080

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

# Create monitoring directory structure
mkdir -p "$MONITORING_DIR"/{dashboard,metrics,logs,config}

print_banner "Alpenglow Verification Monitoring Setup"
print_info "Setting up monitoring dashboard on port $DASHBOARD_PORT"

# Create monitoring dashboard HTML
cat > "$MONITORING_DIR/dashboard/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Alpenglow Verification Dashboard</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: #333;
            min-height: 100vh;
        }
        .container { max-width: 1400px; margin: 0 auto; padding: 20px; }
        .header { 
            background: rgba(255,255,255,0.95);
            padding: 20px;
            border-radius: 10px;
            margin-bottom: 20px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        .header h1 { color: #4a5568; margin-bottom: 10px; }
        .status-grid { 
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 20px;
        }
        .status-card {
            background: rgba(255,255,255,0.95);
            padding: 20px;
            border-radius: 10px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        .status-card h3 { color: #4a5568; margin-bottom: 15px; }
        .metric { 
            display: flex;
            justify-content: space-between;
            margin-bottom: 10px;
            padding: 8px 0;
            border-bottom: 1px solid #e2e8f0;
        }
        .metric:last-child { border-bottom: none; }
        .metric-value { font-weight: bold; }
        .success { color: #38a169; }
        .warning { color: #d69e2e; }
        .error { color: #e53e3e; }
        .progress-bar {
            width: 100%;
            height: 20px;
            background: #e2e8f0;
            border-radius: 10px;
            overflow: hidden;
            margin: 10px 0;
        }
        .progress-fill {
            height: 100%;
            background: linear-gradient(90deg, #38a169, #48bb78);
            transition: width 0.3s ease;
        }
        .logs {
            background: rgba(255,255,255,0.95);
            padding: 20px;
            border-radius: 10px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
            max-height: 400px;
            overflow-y: auto;
        }
        .log-entry {
            padding: 8px;
            margin: 5px 0;
            border-radius: 5px;
            font-family: monospace;
            font-size: 14px;
        }
        .log-info { background: #e6fffa; }
        .log-success { background: #f0fff4; }
        .log-warning { background: #fffbeb; }
        .log-error { background: #fed7d7; }
        .refresh-btn {
            background: #4299e1;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 5px;
            cursor: pointer;
            margin-left: 10px;
        }
        .refresh-btn:hover { background: #3182ce; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔬 Alpenglow Formal Verification Dashboard</h1>
            <p>Real-time monitoring of verification pipeline status and metrics</p>
            <button class="refresh-btn" onclick="refreshData()">🔄 Refresh</button>
            <span id="lastUpdate">Last updated: Loading...</span>
        </div>

        <div class="status-grid">
            <div class="status-card">
                <h3>📊 Overall Status</h3>
                <div class="metric">
                    <span>Total Modules:</span>
                    <span class="metric-value" id="totalModules">-</span>
                </div>
                <div class="metric">
                    <span>Verified Modules:</span>
                    <span class="metric-value success" id="verifiedModules">-</span>
                </div>
                <div class="metric">
                    <span>Failed Modules:</span>
                    <span class="metric-value error" id="failedModules">-</span>
                </div>
                <div class="progress-bar">
                    <div class="progress-fill" id="moduleProgress" style="width: 0%"></div>
                </div>
            </div>

            <div class="status-card">
                <h3>🎯 Proof Obligations</h3>
                <div class="metric">
                    <span>Total Obligations:</span>
                    <span class="metric-value" id="totalObligations">-</span>
                </div>
                <div class="metric">
                    <span>Verified:</span>
                    <span class="metric-value success" id="verifiedObligations">-</span>
                </div>
                <div class="metric">
                    <span>Success Rate:</span>
                    <span class="metric-value" id="obligationRate">-</span>
                </div>
                <div class="progress-bar">
                    <div class="progress-fill" id="obligationProgress" style="width: 0%"></div>
                </div>
            </div>

            <div class="status-card">
                <h3>⚡ Performance</h3>
                <div class="metric">
                    <span>Total Runtime:</span>
                    <span class="metric-value" id="totalRuntime">-</span>
                </div>
                <div class="metric">
                    <span>Average per Module:</span>
                    <span class="metric-value" id="avgModuleTime">-</span>
                </div>
                <div class="metric">
                    <span>Parallel Workers:</span>
                    <span class="metric-value" id="parallelWorkers">-</span>
                </div>
                <div class="metric">
                    <span>Target: <40min:</span>
                    <span class="metric-value" id="targetStatus">-</span>
                </div>
            </div>

            <div class="status-card">
                <h3>🔄 Cross-Validation</h3>
                <div class="metric">
                    <span>TLA+ vs Stateright:</span>
                    <span class="metric-value" id="crossValidation">-</span>
                </div>
                <div class="metric">
                    <span>Trace Equivalence:</span>
                    <span class="metric-value" id="traceEquivalence">-</span>
                </div>
                <div class="metric">
                    <span>Performance Speedup:</span>
                    <span class="metric-value" id="performanceSpeedup">-</span>
                </div>
            </div>
        </div>

        <div class="logs">
            <h3>📝 Recent Activity</h3>
            <div id="logContainer">
                <div class="log-entry log-info">Dashboard initialized - waiting for data...</div>
            </div>
        </div>
    </div>

    <script>
        let refreshInterval;

        function refreshData() {
            fetch('/api/status')
                .then(response => response.json())
                .then(data => updateDashboard(data))
                .catch(error => {
                    console.error('Error fetching data:', error);
                    addLogEntry('error', 'Failed to fetch verification status');
                });
        }

        function updateDashboard(data) {
            // Update overall status
            document.getElementById('totalModules').textContent = data.total_modules || '-';
            document.getElementById('verifiedModules').textContent = data.verified_modules || '-';
            document.getElementById('failedModules').textContent = data.failed_modules || '-';
            
            const moduleProgress = data.total_modules > 0 ? 
                (data.verified_modules / data.total_modules * 100) : 0;
            document.getElementById('moduleProgress').style.width = moduleProgress + '%';

            // Update proof obligations
            document.getElementById('totalObligations').textContent = data.total_obligations || '-';
            document.getElementById('verifiedObligations').textContent = data.verified_obligations || '-';
            document.getElementById('obligationRate').textContent = 
                data.obligation_success_rate ? data.obligation_success_rate + '%' : '-';
            
            const obligationProgress = data.total_obligations > 0 ? 
                (data.verified_obligations / data.total_obligations * 100) : 0;
            document.getElementById('obligationProgress').style.width = obligationProgress + '%';

            // Update performance
            document.getElementById('totalRuntime').textContent = 
                data.total_runtime ? formatTime(data.total_runtime) : '-';
            document.getElementById('avgModuleTime').textContent = 
                data.avg_module_time ? formatTime(data.avg_module_time) : '-';
            document.getElementById('parallelWorkers').textContent = data.parallel_workers || '-';
            
            const targetStatus = data.total_runtime && data.total_runtime < 2400 ? 
                '✅ Met' : '⚠️ Exceeded';
            document.getElementById('targetStatus').textContent = targetStatus;

            // Update cross-validation
            document.getElementById('crossValidation').textContent = 
                data.cross_validation_rate ? data.cross_validation_rate + '%' : '-';
            document.getElementById('traceEquivalence').textContent = 
                data.trace_equivalence_rate ? data.trace_equivalence_rate + '%' : '-';
            document.getElementById('performanceSpeedup').textContent = 
                data.performance_speedup ? data.performance_speedup + 'x' : '-';

            // Update timestamp
            document.getElementById('lastUpdate').textContent = 
                'Last updated: ' + new Date().toLocaleTimeString();

            // Add log entry for successful update
            addLogEntry('success', 'Dashboard data refreshed successfully');
        }

        function formatTime(seconds) {
            const minutes = Math.floor(seconds / 60);
            const remainingSeconds = seconds % 60;
            return `${minutes}m ${remainingSeconds}s`;
        }

        function addLogEntry(type, message) {
            const logContainer = document.getElementById('logContainer');
            const entry = document.createElement('div');
            entry.className = `log-entry log-${type}`;
            entry.textContent = `[${new Date().toLocaleTimeString()}] ${message}`;
            
            logContainer.insertBefore(entry, logContainer.firstChild);
            
            // Keep only last 20 entries
            while (logContainer.children.length > 20) {
                logContainer.removeChild(logContainer.lastChild);
            }
        }

        // Initialize dashboard
        document.addEventListener('DOMContentLoaded', function() {
            refreshData();
            refreshInterval = setInterval(refreshData, 30000); // Refresh every 30 seconds
        });
    </script>
</body>
</html>
EOF

# Create monitoring server script
cat > "$MONITORING_DIR/server.py" << 'EOF'
#!/usr/bin/env python3

"""
Alpenglow Verification Monitoring Server

Provides real-time monitoring dashboard and API for verification pipeline status.
"""

import json
import os
import time
from pathlib import Path
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse
import threading
import glob

class MonitoringHandler(BaseHTTPRequestHandler):
    def __init__(self, *args, monitoring_dir=None, **kwargs):
        self.monitoring_dir = Path(monitoring_dir) if monitoring_dir else Path('.')
        super().__init__(*args, **kwargs)
    
    def do_GET(self):
        parsed_path = urlparse(self.path)
        
        if parsed_path.path == '/':
            self.serve_dashboard()
        elif parsed_path.path == '/api/status':
            self.serve_status_api()
        else:
            self.send_error(404)
    
    def serve_dashboard(self):
        dashboard_file = self.monitoring_dir / 'dashboard' / 'index.html'
        try:
            with open(dashboard_file, 'r') as f:
                content = f.read()
            
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            self.wfile.write(content.encode())
        except FileNotFoundError:
            self.send_error(404, 'Dashboard not found')
    
    def serve_status_api(self):
        try:
            status_data = self.collect_status_data()
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(json.dumps(status_data).encode())
        except Exception as e:
            self.send_error(500, f'Error collecting status: {str(e)}')
    
    def collect_status_data(self):
        """Collect current verification status from result files."""
        project_root = self.monitoring_dir.parent.parent
        
        # Default status
        status = {
            'timestamp': time.time(),
            'total_modules': 0,
            'verified_modules': 0,
            'failed_modules': 0,
            'total_obligations': 0,
            'verified_obligations': 0,
            'obligation_success_rate': 0,
            'total_runtime': 0,
            'avg_module_time': 0,
            'parallel_workers': 0,
            'cross_validation_rate': 0,
            'trace_equivalence_rate': 0,
            'performance_speedup': 0
        }
        
        # Check for recent regression test results
        regression_results = project_root / 'ci-cd' / 'results' / 'regression_test_report.json'
        if regression_results.exists():
            try:
                with open(regression_results, 'r') as f:
                    data = json.load(f)
                
                status.update({
                    'total_modules': data.get('total_modules', 0),
                    'total_obligations': data.get('total_obligations', 0),
                    'verified_obligations': data.get('verified_obligations', 0),
                    'obligation_success_rate': data.get('success_rate', 0),
                    'total_runtime': data.get('total_time_seconds', 0)
                })
                
                # Calculate verified/failed modules
                failed_count = len(data.get('failed_modules', []))
                status['failed_modules'] = failed_count
                status['verified_modules'] = status['total_modules'] - failed_count
                
                # Calculate average module time
                if status['total_modules'] > 0:
                    status['avg_module_time'] = status['total_runtime'] // status['total_modules']
                    
            except Exception as e:
                print(f"Error reading regression results: {e}")
        
        # Check for parallel verification results
        parallel_results = project_root / 'ci-cd' / 'results' / 'parallel' / 'parallel_verification_report.json'
        if parallel_results.exists():
            try:
                with open(parallel_results, 'r') as f:
                    data = json.load(f)
                
                config = data.get('configuration', {})
                results = data.get('results', {})
                
                status['parallel_workers'] = config.get('workers', 0)
                
                # Update with parallel results if more recent
                if results.get('total_time_seconds', 0) > 0:
                    status.update({
                        'total_runtime': results.get('total_time_seconds', 0),
                        'total_obligations': results.get('total_obligations', 0),
                        'verified_obligations': results.get('verified_obligations', 0),
                        'obligation_success_rate': results.get('obligation_success_rate', 0)
                    })
                    
            except Exception as e:
                print(f"Error reading parallel results: {e}")
        
        # Check for cross-validation results
        cross_val_results = project_root / 'cross-validation' / 'results' / 'dual_framework_summary.json'
        if cross_val_results.exists():
            try:
                with open(cross_val_results, 'r') as f:
                    data = json.load(f)
                
                status['cross_validation_rate'] = data.get('consistency_rate', 0)
                    
            except Exception as e:
                print(f"Error reading cross-validation results: {e}")
        
        # Check for trace equivalence results
        trace_results = project_root / 'cross-validation' / 'results' / 'trace_comparison.json'
        if trace_results.exists():
            try:
                with open(trace_results, 'r') as f:
                    data = json.load(f)
                
                status['trace_equivalence_rate'] = data.get('equivalence_rate', 0)
                    
            except Exception as e:
                print(f"Error reading trace results: {e}")
        
        # Check for performance comparison results
        perf_results = project_root / 'cross-validation' / 'results' / 'performance_comparison.json'
        if perf_results.exists():
            try:
                with open(perf_results, 'r') as f:
                    data = json.load(f)
                
                benchmarks = data.get('benchmarks', {})
                if benchmarks:
                    speedups = [bench.get('speedup', 0) for bench in benchmarks.values()]
                    if speedups:
                        status['performance_speedup'] = sum(speedups) / len(speedups)
                    
            except Exception as e:
                print(f"Error reading performance results: {e}")
        
        return status
    
    def log_message(self, format, *args):
        # Suppress default logging
        pass

def create_handler(monitoring_dir):
    def handler(*args, **kwargs):
        return MonitoringHandler(*args, monitoring_dir=monitoring_dir, **kwargs)
    return handler

def start_monitoring_server(port=8080, monitoring_dir='.'):
    """Start the monitoring server."""
    handler = create_handler(monitoring_dir)
    server = HTTPServer(('localhost', port), handler)
    
    print(f"🚀 Alpenglow Verification Dashboard started")
    print(f"📊 Dashboard: http://localhost:{port}")
    print(f"🔌 API: http://localhost:{port}/api/status")
    print(f"📁 Monitoring directory: {monitoring_dir}")
    print("Press Ctrl+C to stop")
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n🛑 Monitoring server stopped")
        server.shutdown()

if __name__ == '__main__':
    import sys
    
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    monitoring_dir = sys.argv[2] if len(sys.argv) > 2 else '.'
    
    start_monitoring_server(port, monitoring_dir)
EOF

# Make server executable
chmod +x "$MONITORING_DIR/server.py"

# Create systemd service file (optional)
cat > "$MONITORING_DIR/config/alpenglow-monitoring.service" << EOF
[Unit]
Description=Alpenglow Verification Monitoring Dashboard
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$MONITORING_DIR
ExecStart=/usr/bin/python3 $MONITORING_DIR/server.py $DASHBOARD_PORT $MONITORING_DIR
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Create startup script
cat > "$MONITORING_DIR/start-monitoring.sh" << EOF
#!/bin/bash

MONITORING_DIR="$MONITORING_DIR"
PORT=$DASHBOARD_PORT

echo "🚀 Starting Alpenglow Verification Monitoring Dashboard..."
echo "📊 Dashboard will be available at: http://localhost:\$PORT"

cd "\$MONITORING_DIR"
python3 server.py \$PORT "\$MONITORING_DIR"
EOF

chmod +x "$MONITORING_DIR/start-monitoring.sh"

print_success "✓ Monitoring dashboard setup completed"
print_info "📁 Monitoring directory: $MONITORING_DIR"
print_info "🌐 Dashboard port: $DASHBOARD_PORT"
print_info ""
print_info "To start the monitoring dashboard:"
print_info "  cd $MONITORING_DIR"
print_info "  ./start-monitoring.sh"
print_info ""
print_info "Or run directly:"
print_info "  python3 $MONITORING_DIR/server.py $DASHBOARD_PORT $MONITORING_DIR"
print_info ""
print_info "Dashboard will be available at: http://localhost:$DASHBOARD_PORT"

# Start the monitoring server in background if requested
if [[ "${1:-}" == "--start" ]]; then
    print_info "🚀 Starting monitoring server..."
    cd "$MONITORING_DIR"
    python3 server.py $DASHBOARD_PORT "$MONITORING_DIR" &
    MONITOR_PID=$!
    
    sleep 2
    if kill -0 $MONITOR_PID 2>/dev/null; then
        print_success "✓ Monitoring server started (PID: $MONITOR_PID)"
        print_info "📊 Dashboard: http://localhost:$DASHBOARD_PORT"
        echo $MONITOR_PID > "$MONITORING_DIR/monitor.pid"
    else
        print_error "✗ Failed to start monitoring server"
        exit 1
    fi
fi

exit 0
