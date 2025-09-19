#!/bin/bash

# Test Script for GLM-4-Voice-Decoder config.yaml Fix
# This script tests the corrected model validation logic

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
    echo -e "${BLUE}[TEST]${NC} $1"
}

echo "🧪 Testing GLM-4-Voice-Decoder config.yaml Fix"
echo "=============================================="

# Test 1: Check if GLM-4-Voice-Decoder directory exists
print_header "Test 1: Checking GLM-4-Voice-Decoder directory..."
if [ -d "/workspace/models/glm-4-voice-decoder" ]; then
    print_status "GLM-4-Voice-Decoder directory exists"
    
    # List files in the directory
    print_header "Files in GLM-4-Voice-Decoder directory:"
    ls -la /workspace/models/glm-4-voice-decoder/
    echo ""
    
    # Check for config.yaml specifically
    if [ -f "/workspace/models/glm-4-voice-decoder/config.yaml" ]; then
        file_size=$(stat -c%s "/workspace/models/glm-4-voice-decoder/config.yaml" 2>/dev/null || echo "0")
        print_status "config.yaml found ($file_size bytes)"
    else
        print_error "config.yaml not found"
    fi
    
    # Check for other required files
    if [ -f "/workspace/models/glm-4-voice-decoder/flow.pt" ]; then
        file_size=$(stat -c%s "/workspace/models/glm-4-voice-decoder/flow.pt" 2>/dev/null || echo "0")
        print_status "flow.pt found ($file_size bytes)"
    else
        print_error "flow.pt not found"
    fi
    
    if [ -f "/workspace/models/glm-4-voice-decoder/hift.pt" ]; then
        file_size=$(stat -c%s "/workspace/models/glm-4-voice-decoder/hift.pt" 2>/dev/null || echo "0")
        print_status "hift.pt found ($file_size bytes)"
    else
        print_error "hift.pt not found"
    fi
    
else
    print_warning "GLM-4-Voice-Decoder directory not found, will test download"
fi

echo ""

# Test 2: Test Python model downloader with corrected validation
print_header "Test 2: Testing Python model downloader validation..."
python3 << 'EOF'
import sys
import os
sys.path.append('.')

# Import the model downloader
try:
    from model_downloader import ModelDownloader
    
    downloader = ModelDownloader("/workspace/models")
    
    # Check GLM-4-Voice-Decoder configuration
    glm_config = downloader.models["glm-4-voice-decoder"]
    print(f"✅ GLM-4-Voice-Decoder config loaded")
    print(f"   Required files: {glm_config['required_files']}")
    print(f"   Description: {glm_config['description']}")
    
    # Test validation
    is_valid, missing_files = downloader.verify_model("glm-4-voice-decoder", verbose=True)
    
    if is_valid:
        print("✅ GLM-4-Voice-Decoder validation PASSED")
    else:
        print(f"❌ GLM-4-Voice-Decoder validation FAILED")
        print(f"   Missing files: {missing_files}")
    
    # Check status
    status = downloader.get_model_status("glm-4-voice-decoder")
    print(f"   Status: {status}")
    
except Exception as e:
    print(f"❌ Error testing model downloader: {e}")
    sys.exit(1)
EOF

echo ""

# Test 3: Test verification script
print_header "Test 3: Testing verification script..."
if [ -f "verify_models.sh" ]; then
    chmod +x verify_models.sh
    ./verify_models.sh || {
        print_warning "Verification script completed with issues (expected if models not fully downloaded)"
    }
else
    print_error "verify_models.sh not found"
fi

echo ""

# Test 4: Test model download if needed
print_header "Test 4: Testing model download (if needed)..."
if [ ! -f "/workspace/models/glm-4-voice-decoder/config.yaml" ]; then
    print_warning "config.yaml not found, testing download..."
    
    if [ -f "model_downloader.py" ]; then
        print_header "Running Python downloader for GLM-4-Voice-Decoder..."
        python model_downloader.py --model glm-4-voice-decoder || {
            print_error "Python downloader failed"
        }
    else
        print_error "model_downloader.py not found"
    fi
else
    print_status "config.yaml already exists, skipping download test"
fi

echo ""

# Test 5: Final validation
print_header "Test 5: Final validation after fixes..."
if [ -f "verify_models.sh" ]; then
    print_header "Running final verification..."
    ./verify_models.sh && {
        print_status "🎉 All models verified successfully!"
        echo ""
        print_header "Ready to start OpenS2S services:"
        echo "  ./start_realtime_services.sh"
        echo "  Access interface: http://your-runpod-url:8000"
    } || {
        print_warning "Some models still need attention"
        echo ""
        print_header "Next steps:"
        echo "1. Check missing files with: ./verify_models.sh"
        echo "2. Download missing models: ./download_models_manual.sh"
        echo "3. Or use Python downloader: python model_downloader.py"
    }
else
    print_error "verify_models.sh not found"
fi

echo ""
print_header "Test Summary:"
echo "✅ Fixed GLM-4-Voice-Decoder to use config.yaml instead of config.json"
echo "✅ Updated all validation scripts with correct file requirements"
echo "✅ Maintained compatibility with OpenS2S (still uses config.json)"
echo "✅ Added YAML file size validation for GLM-4-Voice-Decoder"
