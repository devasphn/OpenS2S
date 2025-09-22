# OpenS2S Dependency Conflict Resolution Guide

## 🚨 Problem Description

The original `requirements.txt` contains a dependency conflict:
- `vllm==0.6.1.post1` requires `outlines` (versions 0.0.43-0.0.46)
- `outlines` depends on `pyairports` 
- This creates a circular dependency that pip cannot resolve

## ✅ Complete Solution

### Method 1: Automated Fix (Recommended)

```bash
# 1. Use the optimized installation script
chmod +x install_dependencies.sh
./install_dependencies.sh

# 2. Continue with setup
./runpod_setup.sh
```

### Method 2: Manual Step-by-Step Installation

```bash
# 1. Upgrade pip first
pip install --upgrade pip setuptools wheel

# 2. Install PyTorch with CUDA 12.1
pip install torch==2.4.0 torchvision==0.19.0 torchaudio==2.4.0 --index-url https://download.pytorch.org/whl/cu121

# 3. Install core packages (avoiding conflicts)
pip install -r requirements_fixed.txt

# 4. Install Flash Attention (optional, may require compilation)
pip install flash-attn==2.7.0.post2 --no-build-isolation

# 5. Verify installation
python -c "import torch; print(f'CUDA: {torch.cuda.is_available()}')"
```

### Method 3: Emergency Fallback

If the above methods fail:

```bash
# Install without problematic packages
grep -v "vllm\|diffusers\|lightning\|modelscope\|natten" requirements.txt > requirements_minimal.txt
pip install -r requirements_minimal.txt

# Install real-time streaming essentials
pip install websockets==12.0 webrtcvad==2.0.10 fastapi==0.115.0 uvicorn==0.30.6
```

## 🔍 Root Cause Analysis

### Why This Happens:
1. **vllm** is designed for large-scale inference serving
2. **outlines** is a structured generation library with complex dependencies
3. **pyairports** has version conflicts with other packages
4. For real-time streaming, we don't need vllm's full functionality

### Packages Removed/Modified:
- ❌ `vllm==0.6.1.post1` - Causes dependency conflicts
- ❌ `diffusers==0.32.2` - Not needed for core functionality  
- ❌ `lightning==2.5.1` - Not needed for inference
- ❌ `modelscope==1.27.1` - Not needed for core functionality
- ❌ `natten==0.17.5` - Not needed for core functionality
- ✅ `transformers==4.45.2` - Downgraded for compatibility
- ✅ `fastapi==0.115.0` - Updated for real-time streaming

## 🧪 Compatibility Testing

### Critical Packages for Real-time Streaming:
```python
# Test script to verify all critical packages work
import torch
import transformers
import websockets
import webrtcvad
import fastapi
import librosa
import soundfile
import numpy as np

print("✅ All packages imported successfully!")
print(f"PyTorch: {torch.__version__}")
print(f"CUDA: {torch.cuda.is_available()}")
```

### Real-time Streaming Components:
- ✅ **WebSocket Server**: `websockets==12.0`
- ✅ **VAD Processor**: `webrtcvad==2.0.10`
- ✅ **Web Interface**: `fastapi==0.115.0`, `uvicorn==0.30.6`
- ✅ **Audio Processing**: `librosa==0.10.1`, `soundfile==0.13.1`
- ✅ **ML Models**: `torch==2.4.0`, `transformers==4.45.2`

## 🔧 Troubleshooting Common Issues

### Issue 1: Flash Attention Compilation Fails
```bash
# Solution: Install without build isolation
pip install flash-attn==2.7.0.post2 --no-build-isolation

# If still fails, skip it (optional for basic functionality)
echo "Flash attention is optional - continuing without it"
```

### Issue 2: CUDA Not Available
```bash
# Verify CUDA installation
nvidia-smi
python -c "import torch; print(torch.cuda.is_available())"

# Reinstall PyTorch with correct CUDA version
pip uninstall torch torchvision torchaudio
pip install torch==2.4.0 torchvision==0.19.0 torchaudio==2.4.0 --index-url https://download.pytorch.org/whl/cu121
```

### Issue 3: WebRTC VAD Installation Fails
```bash
# Install system dependencies first
apt-get update
apt-get install -y build-essential

# Then install WebRTC VAD
pip install webrtcvad==2.0.10
```

### Issue 4: Memory Issues During Installation
```bash
# Use pip with no cache to reduce memory usage
pip install --no-cache-dir -r requirements_fixed.txt

# Or install packages one by one
while read requirement; do pip install --no-cache-dir $requirement; done < requirements_fixed.txt
```

## 🚀 Production Deployment Checklist

### Before Running Services:
- [ ] All packages installed without conflicts
- [ ] CUDA available and working
- [ ] Models downloaded successfully
- [ ] Ports configured correctly (8000, 8765, 21001, 21002)

### Verification Commands:
```bash
# 1. Check Python packages
pip check

# 2. Verify CUDA
python -c "import torch; assert torch.cuda.is_available()"

# 3. Test model loading
python -c "from transformers import AutoTokenizer; print('✅ Transformers working')"

# 4. Test real-time components
python -c "import websockets, webrtcvad, fastapi; print('✅ Real-time components working')"
```

## 📋 Alternative Package Versions

If you encounter issues with specific versions:

### PyTorch Alternatives:
```bash
# For older CUDA (11.8)
pip install torch==2.4.0 torchvision==0.19.0 torchaudio==2.4.0 --index-url https://download.pytorch.org/whl/cu118

# For CPU-only (not recommended for production)
pip install torch==2.4.0 torchvision==0.19.0 torchaudio==2.4.0 --index-url https://download.pytorch.org/whl/cpu
```

### Transformers Alternatives:
```bash
# Stable version
pip install transformers==4.44.0

# Latest compatible
pip install transformers==4.45.2
```

## 🎯 Success Criteria

After following this guide, you should have:
- ✅ No dependency conflicts (`pip check` passes)
- ✅ CUDA working (`torch.cuda.is_available()` returns `True`)
- ✅ All real-time streaming components functional
- ✅ Models can be loaded without errors
- ✅ Services start successfully on correct ports

## 📞 Emergency Contact

If you still encounter issues:
1. Check the error logs in detail
2. Verify your Python version (3.8-3.11 recommended)
3. Ensure sufficient disk space (>50GB)
4. Verify GPU memory (>24GB VRAM recommended)
5. Try the emergency fallback method above
