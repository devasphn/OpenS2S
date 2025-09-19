#!/bin/bash

# Model Verification Script for OpenS2S Real-time Streaming
# Verifies that all required models are downloaded and functional

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

echo "🔍 OpenS2S Model Verification"
echo "============================="

# Check models directory
print_header "Checking models directory..."
if [ ! -d "/workspace/models" ]; then
    print_error "Models directory not found: /workspace/models"
    exit 1
fi

print_status "Models directory exists: /workspace/models"

# Function to check model directory with comprehensive validation
check_model() {
    local model_name="$1"
    local model_path="$2"
    shift 2
    local required_files=("$@")

    print_header "Checking $model_name model..."

    if [ ! -d "$model_path" ]; then
        print_error "$model_name directory not found: $model_path"
        return 1
    fi

    print_status "$model_name directory exists"

    # Check required files with size validation
    local missing_files=0
    for file in "${required_files[@]}"; do
        if [ -f "$model_path/$file" ]; then
            local file_size=$(stat -c%s "$model_path/$file" 2>/dev/null || echo "0")
            if [ "$file_size" -eq 0 ]; then
                print_error "$file found but is empty (0 bytes)"
                missing_files=$((missing_files + 1))
            elif [ "$file_size" -lt 50 ]; then
                print_warning "$file found but suspiciously small ($file_size bytes)"
                print_status "$file found (but check content)"
            else
                print_status "$file found ($file_size bytes)"
            fi
        else
            print_error "$file missing"
            missing_files=$((missing_files + 1))
        fi
    done

    # Model-specific validation
    if [ "$model_name" = "OpenS2S" ]; then
        # Check for model weight files
        local has_weights=false

        # Check for various weight file formats
        if [ -f "$model_path/pytorch_model.bin" ]; then
            print_status "pytorch_model.bin found"
            has_weights=true
        elif [ -f "$model_path/model.safetensors" ]; then
            print_status "model.safetensors found"
            has_weights=true
        elif ls "$model_path"/*.safetensors 1> /dev/null 2>&1; then
            local safetensors_count=$(ls "$model_path"/*.safetensors | wc -l)
            print_status "$safetensors_count safetensors files found"
            has_weights=true
        elif ls "$model_path"/*.bin 1> /dev/null 2>&1; then
            local bin_count=$(ls "$model_path"/*.bin | wc -l)
            print_status "$bin_count bin files found"
            has_weights=true
        fi

        if [ "$has_weights" = false ]; then
            print_error "No model weight files found (.bin or .safetensors)"
            missing_files=$((missing_files + 1))
        fi
    elif [ "$model_name" = "GLM-4-Voice-Decoder" ]; then
        # Specific validation for GLM-4-Voice-Decoder
        if [ -f "$model_path/flow.pt" ]; then
            local flow_size=$(stat -c%s "$model_path/flow.pt" 2>/dev/null || echo "0")
            if [ "$flow_size" -gt 1000000 ]; then  # Should be > 1MB
                print_status "flow.pt found and valid size ($flow_size bytes)"
            else
                print_error "flow.pt found but invalid size ($flow_size bytes)"
                missing_files=$((missing_files + 1))
            fi
        fi

        if [ -f "$model_path/hift.pt" ]; then
            local hift_size=$(stat -c%s "$model_path/hift.pt" 2>/dev/null || echo "0")
            if [ "$hift_size" -gt 1000000 ]; then  # Should be > 1MB
                print_status "hift.pt found and valid size ($hift_size bytes)"
            else
                print_error "hift.pt found but invalid size ($hift_size bytes)"
                missing_files=$((missing_files + 1))
            fi
        fi
    fi

    # Show directory size and file count
    local dir_size=$(du -sh "$model_path" 2>/dev/null | cut -f1 || echo "unknown")
    local file_count=$(find "$model_path" -type f | wc -l)
    print_status "$model_name size: $dir_size ($file_count files)"

    if [ $missing_files -eq 0 ]; then
        print_status "$model_name verification PASSED"
        return 0
    else
        print_error "$model_name verification FAILED ($missing_files missing/invalid files)"
        return 1
    fi
}

# Check OpenS2S model with comprehensive file list
openspeech_files=("config.json" "tokenizer.json" "tokenizer_config.json")
check_openspeech=$(check_model "OpenS2S" "/workspace/models/OpenS2S" "${openspeech_files[@]}")
openspeech_status=$?

# Check GLM-4-Voice-Decoder model with all required files
glm_files=("config.json" "flow.pt" "hift.pt")
check_glm=$(check_model "GLM-4-Voice-Decoder" "/workspace/models/glm-4-voice-decoder" "${glm_files[@]}")
glm_status=$?

# Test model loading with Python
print_header "Testing model loading..."

python3 << 'EOF'
import sys
import os
sys.path.append('/workspace/OpenS2S')

def test_model_loading():
    try:
        # Test OpenS2S model loading
        print("Testing OpenS2S model loading...")
        from transformers import AutoTokenizer, AutoConfig
        
        openspeech_path = "/workspace/models/OpenS2S"
        if os.path.exists(openspeech_path):
            config = AutoConfig.from_pretrained(openspeech_path)
            print(f"✅ OpenS2S config loaded: {config.model_type if hasattr(config, 'model_type') else 'Unknown type'}")
            
            try:
                tokenizer = AutoTokenizer.from_pretrained(openspeech_path)
                print(f"✅ OpenS2S tokenizer loaded: {len(tokenizer)} tokens")
            except Exception as e:
                print(f"⚠️  OpenS2S tokenizer loading failed: {e}")
        else:
            print("❌ OpenS2S model path not found")
            return False
        
        # Test GLM-4-Voice-Decoder
        print("Testing GLM-4-Voice-Decoder...")
        glm_path = "/workspace/models/glm-4-voice-decoder"
        if os.path.exists(glm_path):
            config = AutoConfig.from_pretrained(glm_path)
            print(f"✅ GLM-4-Voice-Decoder config loaded: {config.model_type if hasattr(config, 'model_type') else 'Unknown type'}")
        else:
            print("❌ GLM-4-Voice-Decoder path not found")
            return False
        
        print("✅ Model loading test completed successfully")
        return True
        
    except Exception as e:
        print(f"❌ Model loading test failed: {e}")
        return False

if __name__ == "__main__":
    success = test_model_loading()
    sys.exit(0 if success else 1)
EOF

python_test_status=$?

# Summary
echo ""
print_header "Verification Summary"
echo "===================="

if [ $openspeech_status -eq 0 ]; then
    print_status "OpenS2S model: READY"
else
    print_error "OpenS2S model: FAILED"
fi

if [ $glm_status -eq 0 ]; then
    print_status "GLM-4-Voice-Decoder: READY"
else
    print_error "GLM-4-Voice-Decoder: FAILED"
fi

if [ $python_test_status -eq 0 ]; then
    print_status "Python model loading: WORKING"
else
    print_error "Python model loading: FAILED"
fi

# Overall status
total_failures=$((openspeech_status + glm_status + python_test_status))

if [ $total_failures -eq 0 ]; then
    echo ""
    print_status "🎉 All models verified successfully!"
    print_header "You can now start the real-time streaming services:"
    echo "  ./start_realtime_services.sh"
    echo "  Access interface: http://your-runpod-url:8000"
    exit 0
else
    echo ""
    print_error "❌ Model verification failed ($total_failures issues)"
    print_header "To fix model issues:"
    echo "  1. Run manual download: ./download_models_manual.sh"
    echo "  2. Or use Python downloader: python model_downloader.py"
    echo "  3. Check disk space: df -h"
    echo "  4. Check network connectivity"
    exit 1
fi
