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

# Download OpenS2S model using Python
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
        resume_download=True
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

# Download GLM-4-Voice-Decoder using Python
print_header "Downloading GLM-4-Voice-Decoder (this will take 5-10 minutes)..."
python3 << 'EOF'
import os
from huggingface_hub import snapshot_download
import sys

try:
    print("Starting GLM-4-Voice-Decoder download...")
    snapshot_download(
        repo_id="THUDM/glm-4-voice-decoder",
        local_dir="/workspace/models/glm-4-voice-decoder",
        local_dir_use_symlinks=False,
        resume_download=True
    )
    print("✅ GLM-4-Voice-Decoder downloaded successfully!")
except Exception as e:
    print(f"❌ Error downloading GLM-4-Voice-Decoder: {e}")
    sys.exit(1)
EOF

if [ $? -ne 0 ]; then
    print_error "GLM-4-Voice-Decoder download failed"
    exit 1
fi

# Verify downloads
print_header "Verifying downloaded models..."

# Check OpenS2S model
if [ -f "/workspace/models/OpenS2S/config.json" ]; then
    print_status "✅ OpenS2S config.json found"
else
    print_error "❌ OpenS2S config.json missing"
    exit 1
fi

# Check for model files (either .bin or .safetensors)
if [ -f "/workspace/models/OpenS2S/pytorch_model.bin" ] || [ -f "/workspace/models/OpenS2S/model.safetensors" ] || ls /workspace/models/OpenS2S/*.safetensors 1> /dev/null 2>&1; then
    print_status "✅ OpenS2S model files found"
else
    print_error "❌ OpenS2S model files missing"
    exit 1
fi

# Check GLM-4-Voice-Decoder
if [ -f "/workspace/models/glm-4-voice-decoder/config.json" ]; then
    print_status "✅ GLM-4-Voice-Decoder config.json found"
else
    print_error "❌ GLM-4-Voice-Decoder config.json missing"
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
