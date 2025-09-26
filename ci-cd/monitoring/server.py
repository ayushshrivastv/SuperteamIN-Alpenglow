#!/usr/bin/env python3
# Author: Ayush Srivastava

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
