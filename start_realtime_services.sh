#!/bin/bash

# OpenS2S Real-time Services Startup Script
# This script starts all necessary services for real-time speech-to-speech

set -e

# Configuration
MODEL_PATH="/workspace/models/OpenS2S"
FLOW_PATH="/workspace/models/glm-4-voice-decoder"
CONTROLLER_PORT=21001
WORKER_PORT=21002
WEBSOCKET_PORT=8765
WEB_PORT=8888

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Function to check if a port is in use
check_port() {
    local port=$1
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
        return 0  # Port is in use
    else
        return 1  # Port is free
    fi
}

# Function to wait for service to be ready
wait_for_service() {
    local url=$1
    local service_name=$2
    local max_attempts=30
    local attempt=1
    
    print_status "Waiting for $service_name to be ready..."
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s "$url" >/dev/null 2>&1; then
            print_status "$service_name is ready!"
            return 0
        fi
        
        echo -n "."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    print_error "$service_name failed to start within $((max_attempts * 2)) seconds"
    return 1
}

# Function to cleanup background processes
cleanup() {
    print_warning "Shutting down services..."
    
    # Kill background processes
    if [ ! -z "$CONTROLLER_PID" ]; then
        kill $CONTROLLER_PID 2>/dev/null || true
    fi
    if [ ! -z "$WORKER_PID" ]; then
        kill $WORKER_PID 2>/dev/null || true
    fi
    if [ ! -z "$WEBSOCKET_PID" ]; then
        kill $WEBSOCKET_PID 2>/dev/null || true
    fi
    if [ ! -z "$WEB_PID" ]; then
        kill $WEB_PID 2>/dev/null || true
    fi
    
    # Wait a moment for graceful shutdown
    sleep 2
    
    # Force kill if necessary
    pkill -f "controller.py" 2>/dev/null || true
    pkill -f "model_worker.py" 2>/dev/null || true
    pkill -f "realtime_server.py" 2>/dev/null || true
    pkill -f "web_interface.py" 2>/dev/null || true
    
    print_status "Cleanup complete"
    exit 0
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

print_header "🚀 Starting OpenS2S Real-time Services"

# Check if we're in the right directory
if [ ! -f "controller.py" ] || [ ! -f "model_worker.py" ]; then
    print_error "Please run this script from the OpenS2S directory"
    exit 1
fi

# Check if model paths exist
if [ ! -d "$MODEL_PATH" ]; then
    print_error "Model path not found: $MODEL_PATH"
    print_warning "Please ensure models are downloaded to the correct location"
    exit 1
fi

if [ ! -d "$FLOW_PATH" ]; then
    print_error "Flow model path not found: $FLOW_PATH"
    print_warning "Please ensure GLM-4-Voice-Decoder is downloaded to the correct location"
    exit 1
fi

# Check for required Python packages
print_header "📦 Checking dependencies"
python -c "import torch; import websockets; import webrtcvad; import fastapi" 2>/dev/null || {
    print_error "Missing required Python packages. Please run the setup script first."
    exit 1
}

# Check GPU availability
print_header "🔍 Checking GPU"
python -c "import torch; assert torch.cuda.is_available(), 'CUDA not available'; print(f'GPU: {torch.cuda.get_device_name(0)}')" || {
    print_error "CUDA GPU not available. This system requires a CUDA-compatible GPU."
    exit 1
}

# Check if ports are available
print_header "🔌 Checking ports"
for port in $CONTROLLER_PORT $WORKER_PORT $WEBSOCKET_PORT $WEB_PORT; do
    if check_port $port; then
        print_warning "Port $port is already in use. Attempting to free it..."
        # Try to kill processes using the port
        lsof -ti:$port | xargs kill -9 2>/dev/null || true
        sleep 2
        if check_port $port; then
            print_error "Could not free port $port. Please check for running services."
            exit 1
        fi
    fi
done

print_status "All ports are available"

# Start services in order
print_header "🎯 Starting Controller"
python controller.py --host 0.0.0.0 --port $CONTROLLER_PORT > controller.log 2>&1 &
CONTROLLER_PID=$!
print_status "Controller started (PID: $CONTROLLER_PID)"

# Wait for controller to be ready
wait_for_service "http://localhost:$CONTROLLER_PORT/list_models" "Controller" || {
    print_error "Controller failed to start"
    cleanup
    exit 1
}

print_header "🤖 Starting Model Worker"
python model_worker.py \
    --host 0.0.0.0 \
    --port $WORKER_PORT \
    --model-path "$MODEL_PATH" \
    --flow-path "$FLOW_PATH" \
    --controller-address "http://localhost:$CONTROLLER_PORT" \
    --worker-address "http://localhost:$WORKER_PORT" \
    > worker.log 2>&1 &
WORKER_PID=$!
print_status "Model Worker started (PID: $WORKER_PID)"

# Wait for worker to be ready
wait_for_service "http://localhost:$WORKER_PORT/worker_get_status" "Model Worker" || {
    print_error "Model Worker failed to start"
    cleanup
    exit 1
}

print_header "🎙️ Starting Real-time WebSocket Server"
python realtime_server.py \
    --host 0.0.0.0 \
    --port $WEBSOCKET_PORT \
    --controller-url "http://localhost:$WORKER_PORT" \
    > websocket.log 2>&1 &
WEBSOCKET_PID=$!
print_status "WebSocket Server started (PID: $WEBSOCKET_PID)"

# Give WebSocket server time to start
sleep 5

print_header "🌐 Starting Web Interface"
python web_interface.py \
    --host 0.0.0.0 \
    --port $WEB_PORT \
    --realtime-ws-url "ws://localhost:$WEBSOCKET_PORT" \
    --controller-url "http://localhost:$WORKER_PORT" \
    > web.log 2>&1 &
WEB_PID=$!
print_status "Web Interface started (PID: $WEB_PID)"

# Wait for web interface to be ready
wait_for_service "http://localhost:$WEB_PORT/health" "Web Interface" || {
    print_error "Web Interface failed to start"
    cleanup
    exit 1
}

# Display service status
print_header "✅ All Services Started Successfully!"
echo ""
echo -e "${GREEN}🎉 OpenS2S Real-time Services are now running!${NC}"
echo ""
echo "📊 Service Status:"
echo "  • Controller:     http://localhost:$CONTROLLER_PORT"
echo "  • Model Worker:   http://localhost:$WORKER_PORT"
echo "  • WebSocket:      ws://localhost:$WEBSOCKET_PORT"
echo "  • Web Interface:  http://localhost:$WEB_PORT"
echo ""
echo "🌐 Access the real-time interface at:"
echo "  http://localhost:$WEB_PORT"
echo ""
echo "📋 Process IDs:"
echo "  • Controller: $CONTROLLER_PID"
echo "  • Worker: $WORKER_PID"
echo "  • WebSocket: $WEBSOCKET_PID"
echo "  • Web: $WEB_PID"
echo ""
echo "📝 Log files:"
echo "  • controller.log"
echo "  • worker.log"
echo "  • websocket.log"
echo "  • web.log"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop all services${NC}"

# Keep script running and monitor services
while true; do
    # Check if all services are still running
    if ! kill -0 $CONTROLLER_PID 2>/dev/null; then
        print_error "Controller process died"
        cleanup
        exit 1
    fi
    
    if ! kill -0 $WORKER_PID 2>/dev/null; then
        print_error "Worker process died"
        cleanup
        exit 1
    fi
    
    if ! kill -0 $WEBSOCKET_PID 2>/dev/null; then
        print_error "WebSocket process died"
        cleanup
        exit 1
    fi
    
    if ! kill -0 $WEB_PID 2>/dev/null; then
        print_error "Web interface process died"
        cleanup
        exit 1
    fi
    
    sleep 10
done
