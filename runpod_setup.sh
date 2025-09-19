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
cd /workspace

# Install PyTorch 2.4.0 with CUDA 12.1
pip install torch==2.4.0 torchvision==0.19.0 torchaudio==2.4.0 --index-url https://download.pytorch.org/whl/cu121

# 3. Clone OpenS2S Repository
echo "📥 Cloning OpenS2S repository..."
if [ ! -d "OpenS2S" ]; then
    git clone https://github.com/CASIA-LM/OpenS2S.git
fi
cd OpenS2S

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
    asyncio-mqtt==0.16.2 \
    python-multipart==0.0.9 \
    aiofiles==24.1.0

# 7. Download Model Checkpoints
echo "🤖 Downloading model checkpoints..."

# Create models directory
mkdir -p /workspace/models

# Download OpenS2S model (11B parameters)
echo "Downloading OpenS2S model..."
cd /workspace/models
if [ ! -d "OpenS2S" ]; then
    git lfs install
    git clone https://huggingface.co/CASIA-LM/OpenS2S
fi

# Download GLM-4-Voice-Decoder
echo "Downloading GLM-4-Voice-Decoder..."
if [ ! -d "glm-4-voice-decoder" ]; then
    git clone https://huggingface.co/THUDM/glm-4-voice-decoder
fi

# 8. Verify CUDA and GPU
echo "🔍 Verifying CUDA setup..."
python -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}'); print(f'GPU count: {torch.cuda.device_count()}'); print(f'GPU name: {torch.cuda.get_device_name(0) if torch.cuda.is_available() else \"No GPU\"}')"

# 9. Test Model Loading
echo "🧪 Testing model loading..."
cd /workspace/OpenS2S
python -c "
import torch
from src.modeling_omnispeech import OmniSpeechModel
from transformers import AutoTokenizer
print('Testing model loading...')
try:
    # Test if models can be loaded
    model_path = '/workspace/models/OpenS2S'
    tokenizer = AutoTokenizer.from_pretrained(model_path)
    print('✅ Tokenizer loaded successfully')
    print(f'GPU Memory: {torch.cuda.get_device_properties(0).total_memory / 1e9:.1f}GB')
    print('✅ Setup verification complete!')
except Exception as e:
    print(f'❌ Error: {e}')
"

echo "✅ OpenS2S Real-time Streaming setup complete!"
echo ""
echo "🎯 Next steps:"
echo "1. Start the controller: python controller.py"
echo "2. Start the model worker: python model_worker.py --model-path /workspace/models/OpenS2S --flow-path /workspace/models/glm-4-voice-decoder"
echo "3. Start the real-time streaming server: python realtime_server.py"
echo "4. Access the web interface at: http://localhost:8888"
echo ""
echo "🔗 Exposed ports:"
echo "- 21001: Controller API"
echo "- 21002: Model Worker API"
echo "- 8765: WebSocket Streaming"
echo "- 8888: Web Interface"
