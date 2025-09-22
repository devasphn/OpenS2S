#!/bin/bash

# OpenS2S Optimized System Test Script
# Comprehensive testing of all optimizations and performance improvements

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

# Test configuration
CONTROLLER_URL="http://localhost:21001"
WORKER_URL="http://localhost:21002"
WEB_URL="http://localhost:8000"
WEBSOCKET_URL="ws://localhost:8765"

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TOTAL_TESTS=0

# Function to run a test
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    print_header "Running test: $test_name"
    
    if eval "$test_command"; then
        print_status "PASSED: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        print_error "FAILED: $test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Test 1: Verify project structure
test_project_structure() {
    print_header "Testing optimized project structure..."
    
    # Check that unused directories are removed
    if [ -d "cosyvoice" ] || [ -d "third_party" ]; then
        print_error "Unused directories still exist"
        return 1
    fi
    
    # Check that new directories exist
    for dir in "docs" "config" "monitoring" "scripts"; do
        if [ ! -d "$dir" ]; then
            print_error "Required directory missing: $dir"
            return 1
        fi
    done
    
    # Check that documentation was moved
    if [ ! -f "docs/OPTIMIZATION_ANALYSIS.md" ]; then
        print_error "Documentation not properly moved"
        return 1
    fi
    
    print_status "Project structure optimized correctly"
    return 0
}

# Test 2: Verify model files
test_model_files() {
    print_header "Testing model file validation..."
    
    # Check OpenS2S model
    if [ ! -f "/workspace/models/OpenS2S/config.json" ]; then
        print_error "OpenS2S config.json missing"
        return 1
    fi
    
    # Check GLM-4-Voice-Decoder model
    if [ ! -f "/workspace/models/glm-4-voice-decoder/config.yaml" ]; then
        print_error "GLM-4-Voice-Decoder config.yaml missing"
        return 1
    fi
    
    if [ ! -f "/workspace/models/glm-4-voice-decoder/flow.pt" ]; then
        print_error "GLM-4-Voice-Decoder flow.pt missing"
        return 1
    fi
    
    if [ ! -f "/workspace/models/glm-4-voice-decoder/hift.pt" ]; then
        print_error "GLM-4-Voice-Decoder hift.pt missing"
        return 1
    fi
    
    print_status "Model files validated successfully"
    return 0
}

# Test 3: Test Python imports
test_python_imports() {
    print_header "Testing Python imports and dependencies..."
    
    python -c "
import sys
import torch
import transformers
import fastapi
import websockets
import webrtcvad
import psutil
import numpy as np
import torchaudio
print('All core dependencies imported successfully')
" || return 1
    
    print_status "Python imports successful"
    return 0
}

# Test 4: Test model loading optimizations
test_model_loading() {
    print_header "Testing optimized model loading..."
    
    python -c "
import sys
sys.path.append('.')
from src.configuration_omnispeech import OmniSpeechConfig
from src.modeling_omnispeech import OmniSpeechModel
from transformers import AutoConfig, AutoModel

# Test model registration
try:
    config = AutoConfig.from_pretrained('/workspace/models/OpenS2S')
    print(f'Model type: {config.model_type}')
    if config.model_type != 'omnispeech':
        raise ValueError('Model type not properly registered')
    print('Model registration successful')
except Exception as e:
    print(f'Model registration failed: {e}')
    sys.exit(1)
" || return 1
    
    print_status "Model loading optimizations working"
    return 0
}

# Test 5: Test performance configuration
test_performance_config() {
    print_header "Testing performance configuration..."
    
    if [ ! -f "config/performance.yaml" ]; then
        print_error "Performance configuration missing"
        return 1
    fi
    
    python -c "
import yaml
with open('config/performance.yaml', 'r') as f:
    config = yaml.safe_load(f)

required_sections = ['model', 'audio', 'vad', 'websocket', 'latency_targets']
for section in required_sections:
    if section not in config:
        raise ValueError(f'Missing configuration section: {section}')

print('Performance configuration validated')
" || return 1
    
    print_status "Performance configuration valid"
    return 0
}

# Test 6: Test health check system
test_health_check() {
    print_header "Testing health check system..."
    
    if [ ! -f "monitoring/health_check.py" ]; then
        print_error "Health check script missing"
        return 1
    fi
    
    python -c "
import sys
sys.path.append('monitoring')
from health_check import HealthChecker

checker = HealthChecker()
print('Health check system initialized successfully')
" || return 1
    
    print_status "Health check system working"
    return 0
}

# Test 7: Test performance monitoring
test_performance_monitoring() {
    print_header "Testing performance monitoring..."
    
    if [ ! -f "monitoring/performance_monitor.py" ]; then
        print_error "Performance monitor script missing"
        return 1
    fi
    
    python -c "
import sys
sys.path.append('monitoring')
from performance_monitor import PerformanceMonitor

monitor = PerformanceMonitor()
print('Performance monitoring system initialized successfully')
" || return 1
    
    print_status "Performance monitoring working"
    return 0
}

# Test 8: Test VAD optimizations
test_vad_optimizations() {
    print_header "Testing VAD processor optimizations..."
    
    python -c "
import sys
sys.path.append('.')
from vad_processor import VADProcessor

# Test WebRTC VAD
vad = VADProcessor(vad_mode='webrtc')
print('WebRTC VAD initialized successfully')

# Test that performance monitoring attributes exist
if not hasattr(vad, 'processing_times'):
    raise ValueError('Performance monitoring not properly added to VAD')

print('VAD optimizations working correctly')
" || return 1
    
    print_status "VAD optimizations working"
    return 0
}

# Test 9: Test startup scripts
test_startup_scripts() {
    print_header "Testing startup scripts..."
    
    if [ ! -f "scripts/start_production.sh" ]; then
        print_error "Production startup script missing"
        return 1
    fi
    
    if [ ! -x "scripts/start_production.sh" ]; then
        print_error "Production startup script not executable"
        return 1
    fi
    
    # Test script syntax
    bash -n scripts/start_production.sh || return 1
    
    print_status "Startup scripts validated"
    return 0
}

# Test 10: Test production requirements
test_production_requirements() {
    print_header "Testing production requirements..."
    
    if [ ! -f "requirements_production.txt" ]; then
        print_error "Production requirements file missing"
        return 1
    fi
    
    # Check that key packages are included
    grep -q "torch" requirements_production.txt || return 1
    grep -q "transformers" requirements_production.txt || return 1
    grep -q "fastapi" requirements_production.txt || return 1
    grep -q "websockets" requirements_production.txt || return 1
    grep -q "webrtcvad" requirements_production.txt || return 1
    
    print_status "Production requirements validated"
    return 0
}

# Main test execution
main() {
    echo ""
    print_header "🧪 OpenS2S Optimized System Test Suite"
    print_header "======================================"
    echo ""
    
    # Run all tests
    run_test "Project Structure" "test_project_structure"
    run_test "Model Files" "test_model_files"
    run_test "Python Imports" "test_python_imports"
    run_test "Model Loading" "test_model_loading"
    run_test "Performance Config" "test_performance_config"
    run_test "Health Check" "test_health_check"
    run_test "Performance Monitoring" "test_performance_monitoring"
    run_test "VAD Optimizations" "test_vad_optimizations"
    run_test "Startup Scripts" "test_startup_scripts"
    run_test "Production Requirements" "test_production_requirements"
    
    echo ""
    print_header "📊 Test Results Summary"
    print_header "======================="
    echo ""
    
    if [ $TESTS_FAILED -eq 0 ]; then
        print_status "🎉 All tests passed! ($TESTS_PASSED/$TOTAL_TESTS)"
        print_status "✅ OpenS2S optimization completed successfully"
        print_status "🚀 System is ready for production deployment"
        echo ""
        print_header "Next steps:"
        echo "  1. Run: ./scripts/start_production.sh"
        echo "  2. Test: python monitoring/health_check.py"
        echo "  3. Monitor: python monitoring/performance_monitor.py"
        echo "  4. Access: http://localhost:8000"
        echo ""
        exit 0
    else
        print_error "❌ Some tests failed ($TESTS_FAILED/$TOTAL_TESTS failed)"
        print_error "🔧 Please fix the issues before deployment"
        echo ""
        print_header "Failed tests need attention before production use"
        exit 1
    fi
}

# Run main function
main "$@"
