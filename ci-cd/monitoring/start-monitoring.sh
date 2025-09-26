#!/bin/bash

MONITORING_DIR="/Users/ayushsrivastava/SuperteamIN/ci-cd/monitoring"
PORT=8080

echo "🚀 Starting Alpenglow Verification Monitoring Dashboard..."
echo "📊 Dashboard will be available at: http://localhost:$PORT"

cd "$MONITORING_DIR"
python3 server.py $PORT "$MONITORING_DIR"
