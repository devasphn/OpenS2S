#!/bin/bash

# OpenS2S Production Startup Script
# Optimized for ultra-low latency real-time streaming

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Configuration
CONTROLLER_PORT=21001
WORKER_PORT=21002
WEB_PORT=8000
WEBSOCKET_PORT=8765

MODEL_PATH="/workspace/models/OpenS2S"
FLOW_PATH="/workspace/models/glm-4-voice-decoder"

# Performance settings
export CUDA_VISIBLE_DEVICES=0
export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512
export OMP_NUM_THREADS=4
export MKL_NUM_THREADS=4

# Process IDs for cleanup
CONTROLLER_PID=""
WORKER_PID=""
WEB_PID=""
WEBSOCKET_PID=""

# Cleanup function
cleanup() {
    print_header "Shutting down services..."
    
    if [ ! -z "$WEBSOCKET_PID" ]; then
        kill $WEBSOCKET_PID 2>/dev/null || true
        print_status "WebSocket server stopped"
    fi
    
    if [ ! -z "$WEB_PID" ]; then
        kill $WEB_PID 2>/dev/null || true
        print_status "Web interface stopped"
    fi
    
    if [ ! -z "$WORKER_PID" ]; then
        kill $WORKER_PID 2>/dev/null || true
        print_status "Model worker stopped"
    fi
    
    if [ ! -z "$CONTROLLER_PID" ]; then
        kill $CONTROLLER_PID 2>/dev/null || true
        print_status "Controller stopped"
    fi
    
    # Clean up log files
    rm -f *.log
    
    print_header "Cleanup completed"
}

# Set up signal handlers
trap cleanup EXIT INT TERM

# Function to wait for service to be ready
wait_for_service() {
    local url=$1
    local name=$2
    local max_attempts=30
    local attempt=1
    
    print_header "Waiting for $name to be ready..."
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s "$url" > /dev/null 2>&1; then
            print_status "$name is ready"
            return 0
        fi
        
        sleep 1
        attempt=$((attempt + 1))
    done
    
    print_error "$name failed to start within $max_attempts seconds"
    return 1
}

# Verify models exist
print_header "Verifying models..."
if [ ! -d "$MODEL_PATH" ]; then
    print_error "OpenS2S model not found at $MODEL_PATH"
    print_error "Please run model download first"
    exit 1
fi

if [ ! -d "$FLOW_PATH" ]; then
    print_error "GLM-4-Voice-Decoder model not found at $FLOW_PATH"
    print_error "Please run model download first"
    exit 1
fi

print_status "Models verified"

# Check GPU availability
print_header "Checking GPU availability..."
python -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}'); print(f'GPU count: {torch.cuda.device_count()}')" || {
    print_error "GPU check failed"
    exit 1
}

echo ""
print_header "🚀 Starting OpenS2S Production Services"
print_header "========================================"

# Start Controller
print_header "🎛️  Starting Controller"
python controller.py \
    --host 0.0.0.0 \
    --port $CONTROLLER_PORT \
    --dispatch-method shortest_queue \
    > controller.log 2>&1 &
CONTROLLER_PID=$!
print_status "Controller started (PID: $CONTROLLER_PID)"

# Wait for controller to be ready
wait_for_service "http://localhost:$CONTROLLER_PORT/list_models" "Controller" || {
    print_error "Controller failed to start"
    exit 1
}

# Start Model Worker with optimizations
print_header "🤖 Starting Optimized Model Worker"
python model_worker.py \
    --host 0.0.0.0 \
    --port $WORKER_PORT \
    --model-path "$MODEL_PATH" \
    --flow-path "$FLOW_PATH" \
    --controller-address "http://localhost:$CONTROLLER_PORT" \
    --worker-address "http://localhost:$WORKER_PORT" \
    --limit-model-concurrency 4 \
    --stream-interval 1 \
    > worker.log 2>&1 &
WORKER_PID=$!
print_status "Model Worker started (PID: $WORKER_PID)"

# Wait for worker to be ready
wait_for_service "http://localhost:$WORKER_PORT/worker_get_status" "Model Worker" || {
    print_error "Model Worker failed to start"
    exit 1
}

# Start WebSocket Server
print_header "🔌 Starting WebSocket Server"
python realtime_server.py \
    --host 0.0.0.0 \
    --port $WEBSOCKET_PORT \
    --controller-url "http://localhost:$CONTROLLER_PORT" \
    > websocket.log 2>&1 &
WEBSOCKET_PID=$!
print_status "WebSocket Server started (PID: $WEBSOCKET_PID)"

# Give WebSocket server time to start
sleep 3

# Start Web Interface
print_header "🌐 Starting Web Interface"
python web_interface.py \
    --host 0.0.0.0 \
    --port $WEB_PORT \
    --realtime-ws-url "ws://localhost:$WEBSOCKET_PORT" \
    --controller-url "http://localhost:$CONTROLLER_PORT" \
    > web.log 2>&1 &
WEB_PID=$!
print_status "Web Interface started (PID: $WEB_PID)"

# Wait for web interface to be ready
wait_for_service "http://localhost:$WEB_PORT/health" "Web Interface" || {
    print_error "Web Interface failed to start"
    exit 1
}

echo ""
print_header "✅ All services started successfully!"
print_header "=================================="
echo ""
print_status "🌐 Web Interface: http://localhost:$WEB_PORT"
print_status "🔌 WebSocket Server: ws://localhost:$WEBSOCKET_PORT"
print_status "🎛️  Controller API: http://localhost:$CONTROLLER_PORT"
print_status "🤖 Model Worker API: http://localhost:$WORKER_PORT"
echo ""
print_header "📊 Service Status:"
echo "  Controller PID: $CONTROLLER_PID"
echo "  Worker PID: $WORKER_PID"
echo "  WebSocket PID: $WEBSOCKET_PID"
echo "  Web Interface PID: $WEB_PID"
echo ""
print_header "📝 Log files:"
echo "  controller.log - Controller logs"
echo "  worker.log - Model worker logs"
echo "  websocket.log - WebSocket server logs"
echo "  web.log - Web interface logs"
echo ""
print_header "🛑 To stop all services, press Ctrl+C"

# Keep script running and monitor services
while true; do
    sleep 10
    
    # Check if all processes are still running
    if ! kill -0 $CONTROLLER_PID 2>/dev/null; then
        print_error "Controller process died"
        exit 1
    fi
    
    if ! kill -0 $WORKER_PID 2>/dev/null; then
        print_error "Worker process died"
        exit 1
    fi
    
    if ! kill -0 $WEBSOCKET_PID 2>/dev/null; then
        print_error "WebSocket process died"
        exit 1
    fi
    
    if ! kill -0 $WEB_PID 2>/dev/null; then
        print_error "Web interface process died"
        exit 1
    fi
done
