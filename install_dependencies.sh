#!/bin/bash

# OpenS2S Real-time Streaming Dependencies Installation Script
# This script resolves the vllm/outlines/pyairports dependency conflict

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

echo "🔧 OpenS2S Real-time Streaming Dependencies Installation"
echo "======================================================"

# Check Python version
print_header "Checking Python version..."
python_version=$(python --version 2>&1 | cut -d' ' -f2)
print_status "Python version: $python_version"

# Upgrade pip and essential tools
print_header "Upgrading pip and essential tools..."
pip install --upgrade pip setuptools wheel

# Install PyTorch first (specific CUDA version)
print_header "Installing PyTorch with CUDA 12.1 support..."
pip install torch==2.4.0 torchvision==0.19.0 torchaudio==2.4.0 --index-url https://download.pytorch.org/whl/cu121

# Verify CUDA installation
print_header "Verifying CUDA installation..."
python -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}'); print(f'CUDA version: {torch.version.cuda}')" || {
    print_error "CUDA verification failed"
    exit 1
}

# Install core ML packages
print_header "Installing core ML packages..."
pip install \
    transformers==4.45.2 \
    tokenizers==0.20.0 \
    accelerate==0.34.2 \
    datasets==2.21.0 \
    safetensors==0.4.5 \
    huggingface-hub==0.25.0

# Install audio processing packages
print_header "Installing audio processing packages..."
pip install \
    librosa==0.10.1 \
    soundfile==0.13.1 \
    whisper==1.1.10 \
    phonemizer==3.3.0 \
    piper_phonemize==1.1.0

# Install real-time streaming dependencies
print_header "Installing real-time streaming dependencies..."
pip install \
    fastapi==0.115.0 \
    uvicorn==0.30.6 \
    websockets==12.0 \
    webrtcvad==2.0.10 \
    python-multipart==0.0.9 \
    aiofiles==24.1.0 \
    psutil==5.9.8

# Install scientific computing packages
print_header "Installing scientific computing packages..."
pip install \
    numpy==1.26.4 \
    scipy==1.13.1 \
    matplotlib==3.9.2 \
    pandas==2.2.2

# Install configuration and utility packages
print_header "Installing configuration and utility packages..."
pip install \
    omegaconf==2.3.0 \
    hydra-core==1.3.2 \
    PyYAML==6.0.2 \
    rich==13.8.0 \
    tqdm==4.66.5 \
    packaging==24.1 \
    requests==2.32.3

# Install audio/speech specific packages
print_header "Installing audio/speech specific packages..."
pip install \
    conformer==0.3.2 \
    einops==0.8.0 \
    einops_exts==0.0.4

# Install optional packages
print_header "Installing optional packages..."
pip install \
    gradio==4.44.0 \
    wandb==0.17.8 \
    peft==0.12.0

# Install Flash Attention (requires compilation)
print_header "Installing Flash Attention..."
pip install flash-attn==2.7.0.post2 --no-build-isolation || {
    print_warning "Flash Attention installation failed. This is optional for basic functionality."
    print_warning "You can try installing it later with: pip install flash-attn==2.7.0.post2 --no-build-isolation"
}

# Install additional packages that might be needed (optional)
print_header "Installing additional optional packages..."
pip install \
    onnxruntime==1.22.0 \
    Unidecode==1.3.8 || {
    print_warning "Some optional packages failed to install. Core functionality should still work."
}

# Verify critical packages for real-time streaming
print_header "Verifying critical packages for real-time streaming..."
python -c "
import torch
import transformers
import websockets
import webrtcvad
import fastapi
import librosa
import soundfile
import numpy as np
print('✅ All critical packages imported successfully!')
print(f'PyTorch version: {torch.__version__}')
print(f'Transformers version: {transformers.__version__}')
print(f'CUDA available: {torch.cuda.is_available()}')
" || {
    print_error "Critical package verification failed!"
    exit 1
}

# Check for potential conflicts
print_header "Checking for potential dependency conflicts..."
pip check || {
    print_warning "Some dependency conflicts detected. This may not affect core functionality."
    print_warning "Run 'pip check' to see details."
}

print_status "✅ Dependencies installation completed successfully!"
echo ""
print_header "Next steps:"
echo "1. Verify GPU access: python -c 'import torch; print(torch.cuda.is_available())'"
echo "2. Test model loading: python -c 'from transformers import AutoTokenizer; print(\"Transformers working!\")'"
echo "3. Continue with OpenS2S setup: ./runpod_setup.sh"
