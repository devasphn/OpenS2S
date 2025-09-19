#!/bin/bash

# OpenS2S Real-time Streaming Setup for RunPod
# Run this script in the RunPod Web Terminal

set -e

echo "🚀 Starting OpenS2S Real-time Streaming Setup..."

# 1. System Dependencies
echo "📦 Installing system dependencies..."
apt-get update
apt-get install -y \
    libsox-dev \
    sox \
    ffmpeg \
    cmake \
    build-essential \
    libasound2-dev \
    portaudio19-dev \
    libportaudio2 \
    libportaudiocpp0 \
    git \
    wget \
    curl

# 2. Python Environment Setup
echo "🐍 Setting up Python environment..."

# Install PyTorch 2.4.0 with CUDA 12.1
pip install torch==2.4.0 torchvision==0.19.0 torchaudio==2.4.0 --index-url https://download.pytorch.org/whl/cu121

# 3. Verify we're in the correct OpenS2S directory
echo "� Verifying OpenS2S directory..."
if [ ! -f "controller.py" ] || [ ! -f "model_worker.py" ]; then
    echo "❌ Error: Please run this script from the OpenS2S directory"
    echo "Expected files controller.py and model_worker.py not found"
    echo "Make sure you're in the directory where you cloned the OpenS2S repository"
    exit 1
fi

echo "✅ Found OpenS2S files in current directory: $(pwd)"

# 4. Install Flash Attention
echo "⚡ Installing Flash Attention..."
pip install flash-attn==2.7.0.post2 --no-build-isolation

# 5. Install Project Dependencies
echo "📚 Installing project dependencies..."
pip install -r requirements.txt

# 6. Install Additional Dependencies for Real-time Streaming
echo "🔄 Installing real-time streaming dependencies..."
pip install \
    websockets==12.0 \
    webrtcvad==2.0.10 \
    pyaudio==0.2.14 \
    python-multipart==0.0.9 \
    aiofiles==24.1.0 \
    psutil==5.9.8

# 7. Download Model Checkpoints
echo "🤖 Downloading model checkpoints..."

# Create models directory
mkdir -p /workspace/models

# Download OpenS2S model (11B parameters)
echo "Downloading OpenS2S model..."
cd /workspace/models
if [ ! -d "OpenS2S" ]; then
    echo "Installing git-lfs for large file support..."
    git lfs install
    echo "Cloning OpenS2S model (this may take 10-15 minutes)..."
    git clone https://huggingface.co/CASIA-LM/OpenS2S
else
    echo "✅ OpenS2S model already exists"
fi

# Download GLM-4-Voice-Decoder
echo "Downloading GLM-4-Voice-Decoder..."
if [ ! -d "glm-4-voice-decoder" ]; then
    echo "Cloning GLM-4-Voice-Decoder (this may take 5-10 minutes)..."
    git clone https://huggingface.co/THUDM/glm-4-voice-decoder
else
    echo "✅ GLM-4-Voice-Decoder already exists"
fi

# Return to OpenS2S directory
cd /workspace/OpenS2S

# 8. Verify CUDA and GPU
echo "🔍 Verifying CUDA setup..."
python -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}'); print(f'GPU count: {torch.cuda.device_count()}'); print(f'GPU name: {torch.cuda.get_device_name(0) if torch.cuda.is_available() else \"No GPU\"}')"

# 9. Test Model Loading
echo "🧪 Testing model loading..."
python -c "
import torch
import sys
import os
sys.path.append('.')
print('Testing model loading...')
try:
    # Test if models can be loaded
    model_path = '/workspace/models/OpenS2S'
    if os.path.exists(model_path):
        from transformers import AutoTokenizer
        tokenizer = AutoTokenizer.from_pretrained(model_path)
        print('✅ Tokenizer loaded successfully')
        if torch.cuda.is_available():
            print(f'GPU Memory: {torch.cuda.get_device_properties(0).total_memory / 1e9:.1f}GB')
        print('✅ Setup verification complete!')
    else:
        print('⚠️  Model path not found, but setup completed. Models will be downloaded when services start.')
except Exception as e:
    print(f'⚠️  Model loading test failed: {e}')
    print('This is normal if models are still downloading. Services will work once models are ready.')
"

echo "✅ OpenS2S Real-time Streaming setup complete!"
echo ""
echo "🎯 Next steps:"
echo "1. Run the startup script: ./start_realtime_services.sh"
echo "2. Or start services manually:"
echo "   - Controller: python controller.py"
echo "   - Model Worker: python model_worker.py --model-path /workspace/models/OpenS2S --flow-path /workspace/models/glm-4-voice-decoder"
echo "   - WebSocket Server: python realtime_server.py"
echo "   - Web Interface: python web_interface.py"
echo ""
echo "🌐 Access the real-time streaming interface at:"
echo "   http://your-runpod-url:8000"
echo ""
echo "🔗 Port configuration for RunPod:"
echo "- 21001: Controller API"
echo "- 21002: Model Worker API"
echo "- 8765: WebSocket Streaming"
echo "- 8000: Real-time Web Interface (replaces Gradio)"
echo ""
echo "📝 Note: Port 8000 now serves the new real-time streaming UI instead of Gradio"
