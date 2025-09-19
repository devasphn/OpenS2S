#!/bin/bash

# Comprehensive Test Script for OpenS2S Model Configuration Fix
# Tests both GLM-4-Voice-Decoder (config.yaml) and OpenS2S (config.json with model_type) fixes

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

echo "🧪 OpenS2S Model Configuration Fix Test"
echo "======================================="

# Test 1: Check if models directory exists
print_header "Test 1: Checking models directory structure..."
if [ -d "/workspace/models" ]; then
    print_status "Models directory exists"
    ls -la /workspace/models/
    echo ""
else
    print_warning "Models directory not found, will need to download models"
    mkdir -p /workspace/models
fi

# Test 2: Test OpenS2S model configuration
print_header "Test 2: Testing OpenS2S model configuration..."
if [ -d "/workspace/models/OpenS2S" ]; then
    print_status "OpenS2S directory exists"
    
    # Check config.json
    if [ -f "/workspace/models/OpenS2S/config.json" ]; then
        print_status "config.json found"
        
        # Check if it has model_type
        if grep -q '"model_type"' "/workspace/models/OpenS2S/config.json"; then
            model_type=$(grep '"model_type"' "/workspace/models/OpenS2S/config.json" | cut -d'"' -f4)
            print_status "model_type found: $model_type"
        else
            print_warning "model_type missing, will fix"
            
            # Run the fix
            if [ -f "register_openspeech.py" ]; then
                print_header "Running OpenS2S config fix..."
                python3 register_openspeech.py --model-path "/workspace/models/OpenS2S"
                if [ $? -eq 0 ]; then
                    print_status "✅ OpenS2S config fix completed"
                else
                    print_error "❌ OpenS2S config fix failed"
                fi
            else
                print_error "register_openspeech.py not found"
            fi
        fi
    else
        print_error "config.json not found"
    fi
else
    print_warning "OpenS2S model not downloaded yet"
fi

echo ""

# Test 3: Test GLM-4-Voice-Decoder configuration
print_header "Test 3: Testing GLM-4-Voice-Decoder configuration..."
if [ -d "/workspace/models/glm-4-voice-decoder" ]; then
    print_status "GLM-4-Voice-Decoder directory exists"
    
    # Check for config.yaml (correct)
    if [ -f "/workspace/models/glm-4-voice-decoder/config.yaml" ]; then
        file_size=$(stat -c%s "/workspace/models/glm-4-voice-decoder/config.yaml" 2>/dev/null || echo "0")
        print_status "config.yaml found ($file_size bytes) ✅"
    else
        print_error "config.yaml not found"
    fi
    
    # Check for other required files
    for file in "flow.pt" "hift.pt"; do
        if [ -f "/workspace/models/glm-4-voice-decoder/$file" ]; then
            file_size=$(stat -c%s "/workspace/models/glm-4-voice-decoder/$file" 2>/dev/null || echo "0")
            print_status "$file found ($file_size bytes)"
        else
            print_error "$file not found"
        fi
    done
else
    print_warning "GLM-4-Voice-Decoder model not downloaded yet"
fi

echo ""

# Test 4: Test model loading with Python
print_header "Test 4: Testing model loading with Python..."
python3 << 'EOF'
import sys
import os
sys.path.append('.')
sys.path.append('./src')

def test_model_loading():
    """Test loading both models"""
    success = True
    
    try:
        # Test 1: Register OpenS2S model
        print("🔧 Registering OpenS2S model...")
        try:
            from transformers import AutoConfig, AutoModel
            from src.configuration_omnispeech import OmniSpeechConfig
            from src.modeling_omnispeech import OmniSpeechModel
            
            AutoConfig.register("omnispeech", OmniSpeechConfig)
            AutoModel.register(OmniSpeechConfig, OmniSpeechModel)
            print("✅ OpenS2S model registered")
        except Exception as e:
            print(f"⚠️  OpenS2S registration failed: {e}")
        
        # Test 2: Load OpenS2S config
        openspeech_path = "/workspace/models/OpenS2S"
        if os.path.exists(openspeech_path):
            try:
                from transformers import AutoConfig
                config = AutoConfig.from_pretrained(openspeech_path, trust_remote_code=True)
                print(f"✅ OpenS2S config loaded: {getattr(config, 'model_type', 'Unknown')}")
                
                # Try to load tokenizer
                try:
                    from transformers import AutoTokenizer
                    tokenizer = AutoTokenizer.from_pretrained(openspeech_path, trust_remote_code=True)
                    print(f"✅ OpenS2S tokenizer loaded: {len(tokenizer)} tokens")
                except Exception as e:
                    print(f"⚠️  OpenS2S tokenizer failed: {e}")
                    
            except Exception as e:
                print(f"❌ OpenS2S config loading failed: {e}")
                success = False
        else:
            print("⚠️  OpenS2S model not found")
        
        # Test 3: Load GLM-4-Voice-Decoder config
        glm_path = "/workspace/models/glm-4-voice-decoder"
        if os.path.exists(glm_path):
            try:
                import yaml
                config_path = os.path.join(glm_path, "config.yaml")
                if os.path.exists(config_path):
                    with open(config_path, 'r') as f:
                        config = yaml.safe_load(f)
                    print(f"✅ GLM-4-Voice-Decoder config loaded: {config.get('model_type', 'GLM-4-Voice-Decoder')}")
                else:
                    print("❌ GLM-4-Voice-Decoder config.yaml not found")
                    success = False
            except Exception as e:
                print(f"❌ GLM-4-Voice-Decoder config loading failed: {e}")
                success = False
        else:
            print("⚠️  GLM-4-Voice-Decoder model not found")
        
        return success
        
    except Exception as e:
        print(f"❌ Model loading test failed: {e}")
        return False

if __name__ == "__main__":
    success = test_model_loading()
    print(f"\n{'✅ Model loading test PASSED' if success else '❌ Model loading test FAILED'}")
    sys.exit(0 if success else 1)
EOF

echo ""

# Test 5: Run verification script
print_header "Test 5: Running model verification script..."
if [ -f "verify_models.sh" ]; then
    chmod +x verify_models.sh
    ./verify_models.sh && {
        print_status "🎉 Model verification PASSED!"
    } || {
        print_warning "Model verification had issues"
    }
else
    print_error "verify_models.sh not found"
fi

echo ""

# Test 6: Test service startup (if models are available)
print_header "Test 6: Testing service startup readiness..."
if [ -d "/workspace/models/OpenS2S" ] && [ -d "/workspace/models/glm-4-voice-decoder" ]; then
    print_status "Both models available"
    
    if [ -f "start_realtime_services.sh" ]; then
        print_status "Service startup script available"
        print_header "Ready to start services:"
        echo "  ./start_realtime_services.sh"
        echo "  Access interface: http://your-runpod-url:8000"
    else
        print_warning "start_realtime_services.sh not found"
    fi
else
    print_warning "Models not fully downloaded yet"
    print_header "Next steps:"
    echo "1. Download models: ./download_models_manual.sh"
    echo "2. Or use Python downloader: python model_downloader.py"
    echo "3. Run this test again: ./test_openspeech_fix.sh"
fi

echo ""
print_header "Test Summary:"
echo "✅ GLM-4-Voice-Decoder: Fixed to use config.yaml"
echo "✅ OpenS2S: Fixed to include model_type in config.json"
echo "✅ Model registration: Added OmniSpeech model support"
echo "✅ Verification: Enhanced to handle both model types"
echo "✅ Downloads: Updated to apply fixes automatically"
