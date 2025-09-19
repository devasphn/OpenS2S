#!/bin/bash

# Emergency Manual Model Download Script for OpenS2S
# Use this if automated download fails due to Git LFS issues

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

echo "🚨 Emergency Manual Model Download for OpenS2S"
echo "=============================================="

# Check if we're in the right directory
if [ ! -f "controller.py" ] || [ ! -f "model_worker.py" ]; then
    print_error "Please run this script from the OpenS2S directory"
    print_error "Current directory: $(pwd)"
    exit 1
fi

# Create models directory
print_header "Creating models directory..."
mkdir -p /workspace/models
cd /workspace/models

# Install huggingface-hub if not available
print_header "Installing huggingface-hub for downloads..."
pip install huggingface-hub>=0.25.0 || {
    print_error "Failed to install huggingface-hub"
    exit 1
}

# Check if OpenS2S already exists and is complete
print_header "Checking OpenS2S model status..."
if [ -d "/workspace/models/OpenS2S" ]; then
    print_warning "OpenS2S directory exists, checking completeness..."

    # Check for required files
    missing_openspeech=0
    required_openspeech_files=("config.json" "tokenizer.json" "tokenizer_config.json")

    for file in "${required_openspeech_files[@]}"; do
        if [ ! -f "/workspace/models/OpenS2S/$file" ]; then
            print_error "Missing: $file"
            missing_openspeech=$((missing_openspeech + 1))
        fi
    done

    # Check for weight files
    if ! ls /workspace/models/OpenS2S/*.safetensors 1> /dev/null 2>&1 && ! ls /workspace/models/OpenS2S/*.bin 1> /dev/null 2>&1; then
        print_error "Missing: model weight files"
        missing_openspeech=$((missing_openspeech + 1))
    fi

    if [ $missing_openspeech -gt 0 ]; then
        print_warning "OpenS2S incomplete ($missing_openspeech missing files), cleaning up..."
        rm -rf /workspace/models/OpenS2S
    else
        print_status "OpenS2S already complete, skipping download"
    fi
fi

# Download OpenS2S model using Python (only if needed)
if [ ! -d "/workspace/models/OpenS2S" ]; then
    print_header "Downloading OpenS2S model (11B parameters - this will take 10-15 minutes)..."
    python3 << 'EOF'
import os
from huggingface_hub import snapshot_download
import sys

try:
    print("Starting OpenS2S model download...")
    snapshot_download(
        repo_id="CASIA-LM/OpenS2S",
        local_dir="/workspace/models/OpenS2S",
        local_dir_use_symlinks=False,
        resume_download=True,
        ignore_patterns=["*.git*", "README.md", "*.md", ".gitattributes"]
    )
    print("✅ OpenS2S model downloaded successfully!")
except Exception as e:
    print(f"❌ Error downloading OpenS2S model: {e}")
    sys.exit(1)
EOF

    if [ $? -ne 0 ]; then
        print_error "OpenS2S model download failed"
        exit 1
    fi
fi

# Check if GLM-4-Voice-Decoder already exists and is complete
print_header "Checking GLM-4-Voice-Decoder model status..."
if [ -d "/workspace/models/glm-4-voice-decoder" ]; then
    print_warning "GLM-4-Voice-Decoder directory exists, checking completeness..."

    # Check for required files with comprehensive validation (GLM-4 uses YAML config)
    missing_glm=0
    required_glm_files=("config.yaml" "flow.pt" "hift.pt")

    for file in "${required_glm_files[@]}"; do
        if [ ! -f "/workspace/models/glm-4-voice-decoder/$file" ]; then
            print_error "Missing: $file"
            missing_glm=$((missing_glm + 1))
        else
            # Check file size for .pt files
            if [[ "$file" == *.pt ]]; then
                file_size=$(stat -c%s "/workspace/models/glm-4-voice-decoder/$file" 2>/dev/null || echo "0")
                if [ "$file_size" -lt 1000000 ]; then  # Less than 1MB is suspicious
                    print_error "$file exists but is too small ($file_size bytes)"
                    missing_glm=$((missing_glm + 1))
                else
                    print_status "$file found and valid size ($file_size bytes)"
                fi
            else
                print_status "$file found"
            fi
        fi
    done

    if [ $missing_glm -gt 0 ]; then
        print_warning "GLM-4-Voice-Decoder incomplete ($missing_glm missing/invalid files), cleaning up..."
        rm -rf /workspace/models/glm-4-voice-decoder
    else
        print_status "GLM-4-Voice-Decoder already complete, skipping download"
    fi
fi

# Download GLM-4-Voice-Decoder using Python (only if needed)
if [ ! -d "/workspace/models/glm-4-voice-decoder" ]; then
    print_header "Downloading GLM-4-Voice-Decoder (this will take 5-10 minutes)..."
    python3 << 'EOF'
import os
from huggingface_hub import snapshot_download, hf_hub_download
import sys

try:
    print("Starting GLM-4-Voice-Decoder download...")
    snapshot_download(
        repo_id="THUDM/glm-4-voice-decoder",
        local_dir="/workspace/models/glm-4-voice-decoder",
        local_dir_use_symlinks=False,
        resume_download=True,
        ignore_patterns=["*.git*", "README.md", "*.md", ".gitattributes"]
    )

    # Verify critical files are present (GLM-4 uses YAML config)
    required_files = ["config.yaml", "flow.pt", "hift.pt"]
    missing_files = []

    for file in required_files:
        file_path = f"/workspace/models/glm-4-voice-decoder/{file}"
        if not os.path.exists(file_path):
            missing_files.append(file)
        elif os.path.getsize(file_path) == 0:
            missing_files.append(f"{file} (empty)")

    if missing_files:
        print(f"⚠️  Missing files after download: {missing_files}")
        print("🔄 Attempting to download missing files individually...")

        for file in ["config.yaml", "flow.pt", "hift.pt"]:
            file_path = f"/workspace/models/glm-4-voice-decoder/{file}"
            if not os.path.exists(file_path) or os.path.getsize(file_path) == 0:
                try:
                    print(f"📥 Downloading {file}...")
                    hf_hub_download(
                        repo_id="THUDM/glm-4-voice-decoder",
                        filename=file,
                        local_dir="/workspace/models/glm-4-voice-decoder",
                        local_dir_use_symlinks=False
                    )
                except Exception as e:
                    print(f"❌ Failed to download {file}: {e}")
                    sys.exit(1)

    print("✅ GLM-4-Voice-Decoder downloaded successfully!")
except Exception as e:
    print(f"❌ Error downloading GLM-4-Voice-Decoder: {e}")
    sys.exit(1)
EOF

    if [ $? -ne 0 ]; then
        print_error "GLM-4-Voice-Decoder download failed"
        exit 1
    fi
fi

# Comprehensive verification of downloads
print_header "Verifying downloaded models with comprehensive checks..."

# Verify OpenS2S model
print_header "Verifying OpenS2S model..."
openspeech_errors=0

required_openspeech_files=("config.json" "tokenizer.json" "tokenizer_config.json")
for file in "${required_openspeech_files[@]}"; do
    if [ -f "/workspace/models/OpenS2S/$file" ]; then
        file_size=$(stat -c%s "/workspace/models/OpenS2S/$file" 2>/dev/null || echo "0")
        if [ "$file_size" -gt 0 ]; then
            print_status "✅ OpenS2S $file found ($file_size bytes)"
        else
            print_error "❌ OpenS2S $file is empty"
            openspeech_errors=$((openspeech_errors + 1))
        fi
    else
        print_error "❌ OpenS2S $file missing"
        openspeech_errors=$((openspeech_errors + 1))
    fi
done

# Check for model weight files
if ls /workspace/models/OpenS2S/*.safetensors 1> /dev/null 2>&1; then
    weight_count=$(ls /workspace/models/OpenS2S/*.safetensors | wc -l)
    print_status "✅ OpenS2S model weights found ($weight_count safetensors files)"
elif ls /workspace/models/OpenS2S/*.bin 1> /dev/null 2>&1; then
    weight_count=$(ls /workspace/models/OpenS2S/*.bin | wc -l)
    print_status "✅ OpenS2S model weights found ($weight_count bin files)"
else
    print_error "❌ OpenS2S model weight files missing"
    openspeech_errors=$((openspeech_errors + 1))
fi

# Verify GLM-4-Voice-Decoder model (uses YAML config)
print_header "Verifying GLM-4-Voice-Decoder model..."
glm_errors=0

required_glm_files=("config.yaml" "flow.pt" "hift.pt")
for file in "${required_glm_files[@]}"; do
    if [ -f "/workspace/models/glm-4-voice-decoder/$file" ]; then
        file_size=$(stat -c%s "/workspace/models/glm-4-voice-decoder/$file" 2>/dev/null || echo "0")
        if [ "$file_size" -gt 0 ]; then
            if [[ "$file" == *.pt ]] && [ "$file_size" -lt 1000000 ]; then
                print_error "❌ GLM-4-Voice-Decoder $file too small ($file_size bytes)"
                glm_errors=$((glm_errors + 1))
            else
                print_status "✅ GLM-4-Voice-Decoder $file found ($file_size bytes)"
            fi
        else
            print_error "❌ GLM-4-Voice-Decoder $file is empty"
            glm_errors=$((glm_errors + 1))
        fi
    else
        print_error "❌ GLM-4-Voice-Decoder $file missing"
        glm_errors=$((glm_errors + 1))
    fi
done

# Overall verification result
total_errors=$((openspeech_errors + glm_errors))
if [ $total_errors -gt 0 ]; then
    print_error "❌ Model verification failed ($total_errors errors total)"
    print_header "Errors found:"
    echo "  - OpenS2S: $openspeech_errors errors"
    echo "  - GLM-4-Voice-Decoder: $glm_errors errors"
    exit 1
fi

# Show disk usage
print_header "Model download summary:"
echo "OpenS2S model size: $(du -sh /workspace/models/OpenS2S 2>/dev/null | cut -f1 || echo 'unknown')"
echo "GLM-4-Voice-Decoder size: $(du -sh /workspace/models/glm-4-voice-decoder 2>/dev/null | cut -f1 || echo 'unknown')"
echo "Total models size: $(du -sh /workspace/models 2>/dev/null | cut -f1 || echo 'unknown')"

print_status "✅ Manual model download completed successfully!"
echo ""
print_header "Next steps:"
echo "1. Return to OpenS2S directory: cd /workspace/OpenS2S"
echo "2. Start the services: ./start_realtime_services.sh"
echo "3. Access interface: http://your-runpod-url:8000"

# Return to original directory
cd /workspace/OpenS2S
