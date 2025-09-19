# OpenS2S Model Download Troubleshooting Guide

## 🚨 Common Issues and Solutions

### Issue 1: Git LFS Not Available
**Error**: `git: 'lfs' is not a git command`

**Solution**:
```bash
# Install Git LFS system-wide
apt-get update
apt-get install -y git-lfs

# Initialize Git LFS
git lfs install

# Verify installation
git lfs version
```

### Issue 2: Hugging Face Hub Download Fails
**Error**: `HfHubHTTPError` or connection timeouts

**Solutions**:
```bash
# Method 1: Use manual download script
chmod +x download_models_manual.sh
./download_models_manual.sh

# Method 2: Use Python downloader directly
python model_downloader.py --models-dir /workspace/models

# Method 3: Install/upgrade huggingface-hub
pip install --upgrade huggingface-hub>=0.25.0
```

### Issue 3: Insufficient Disk Space
**Error**: `No space left on device`

**Check disk space**:
```bash
df -h
du -sh /workspace/models
```

**Solutions**:
- Ensure at least 50GB free space
- Clean up unnecessary files: `docker system prune -a`
- Use a larger RunPod instance

### Issue 4: Network Connectivity Issues
**Error**: Connection timeouts or DNS resolution failures

**Solutions**:
```bash
# Test connectivity
ping huggingface.co
curl -I https://huggingface.co

# Use alternative download method
wget https://huggingface.co/CASIA-LM/OpenS2S/resolve/main/config.json -O /tmp/test_download.json
```

### Issue 5: Partial Downloads
**Error**: Models exist but verification fails (missing config.json, flow.pt, hift.pt, etc.)

**Quick Fix**:
```bash
# Use cleanup utility to remove only incomplete downloads
chmod +x cleanup_models.sh
./cleanup_models.sh
# Choose option 4: "Clean up only incomplete/partial downloads"

# Re-download missing models
python model_downloader.py --models-dir /workspace/models
```

**Manual Cleanup**:
```bash
# Remove specific partial downloads
rm -rf /workspace/models/OpenS2S        # If OpenS2S is incomplete
rm -rf /workspace/models/glm-4-voice-decoder  # If GLM-4 is incomplete

# Re-download with enhanced validation
./download_models_manual.sh
```

**Comprehensive Validation**:
```bash
# Check what's missing
./verify_models.sh

# Use Python downloader with detailed status
python model_downloader.py --models-dir /workspace/models
```

## 🔧 Manual Download Methods

### Method 1: Emergency Manual Script
```bash
chmod +x download_models_manual.sh
./download_models_manual.sh
```

### Method 2: Python-based Downloader
```bash
python model_downloader.py --model OpenS2S
python model_downloader.py --model glm-4-voice-decoder
```

### Method 3: Individual File Download
```bash
# Create directories
mkdir -p /workspace/models/OpenS2S
mkdir -p /workspace/models/glm-4-voice-decoder

# Download essential files for OpenS2S
cd /workspace/models/OpenS2S
wget https://huggingface.co/CASIA-LM/OpenS2S/resolve/main/config.json
wget https://huggingface.co/CASIA-LM/OpenS2S/resolve/main/tokenizer.json
# Note: Model weights are too large for direct wget, use huggingface-hub

# Download essential files for GLM-4-Voice-Decoder
cd /workspace/models/glm-4-voice-decoder
wget https://huggingface.co/THUDM/glm-4-voice-decoder/resolve/main/config.json
```

### Method 4: Using Hugging Face CLI
```bash
# Install Hugging Face CLI
pip install huggingface_hub[cli]

# Download models
huggingface-cli download CASIA-LM/OpenS2S --local-dir /workspace/models/OpenS2S
huggingface-cli download THUDM/glm-4-voice-decoder --local-dir /workspace/models/glm-4-voice-decoder
```

## 🔍 Verification Commands

### Check Model Files
```bash
# Run comprehensive verification
chmod +x verify_models.sh
./verify_models.sh

# Manual verification
ls -la /workspace/models/OpenS2S/
ls -la /workspace/models/glm-4-voice-decoder/

# Check for required files
test -f /workspace/models/OpenS2S/config.json && echo "✅ OpenS2S config found"
test -f /workspace/models/glm-4-voice-decoder/config.json && echo "✅ GLM config found"
```

### Test Model Loading
```bash
python3 << 'EOF'
from transformers import AutoConfig, AutoTokenizer
import os

# Test OpenS2S
try:
    config = AutoConfig.from_pretrained("/workspace/models/OpenS2S")
    print("✅ OpenS2S config loads successfully")
    tokenizer = AutoTokenizer.from_pretrained("/workspace/models/OpenS2S")
    print("✅ OpenS2S tokenizer loads successfully")
except Exception as e:
    print(f"❌ OpenS2S loading failed: {e}")

# Test GLM-4-Voice-Decoder
try:
    config = AutoConfig.from_pretrained("/workspace/models/glm-4-voice-decoder")
    print("✅ GLM-4-Voice-Decoder config loads successfully")
except Exception as e:
    print(f"❌ GLM-4-Voice-Decoder loading failed: {e}")
EOF
```

## 🚀 Alternative Model Sources

### If Hugging Face is Inaccessible
1. **ModelScope** (China-based):
   ```bash
   pip install modelscope
   # Use ModelScope API to download models
   ```

2. **Local Model Files**:
   - Upload models manually to RunPod storage
   - Use shared network drives
   - Download on local machine and transfer

3. **Mirror Sites**:
   - Check for Hugging Face mirrors in your region
   - Use VPN if necessary

## 📊 Expected Model Sizes and Required Files

| Model | Size | Required Files | Description |
|-------|------|----------------|-------------|
| OpenS2S | ~20GB | config.json, tokenizer.json, tokenizer_config.json, *.safetensors/*.bin | Main speech-to-speech model with tokenizer |
| GLM-4-Voice-Decoder | ~5GB | config.json, flow.pt, hift.pt | Voice decoder with flow and hift models |

### Critical File Validation:
- **config.json**: Must exist and be >50 bytes
- **tokenizer.json**: Must exist and be >1KB
- **flow.pt**: Must exist and be >1MB
- **hift.pt**: Must exist and be >1MB
- **Model weights**: At least one *.safetensors or *.bin file >100MB

## 🔄 Recovery Procedures

### Complete Reset
```bash
# Remove all models
rm -rf /workspace/models

# Start fresh
mkdir -p /workspace/models
python model_downloader.py --models-dir /workspace/models
```

### Partial Recovery
```bash
# Keep existing downloads, only download missing
python model_downloader.py --models-dir /workspace/models
```

## 🆘 Emergency Contacts

### If All Methods Fail:
1. **Check RunPod Status**: Verify internet connectivity
2. **Try Different Region**: Some regions may have better connectivity
3. **Contact Support**: RunPod support for network issues
4. **Alternative Approach**: Use smaller models for testing

### Minimal Setup for Testing
```bash
# Use smaller models for initial testing
pip install transformers torch
python -c "from transformers import AutoTokenizer; print('Basic setup working')"
```

## 📝 Logging and Debugging

### Enable Verbose Logging
```bash
export HF_HUB_VERBOSITY=debug
python model_downloader.py --models-dir /workspace/models
```

### Check Download Progress
```bash
# Monitor disk usage during download
watch -n 5 'du -sh /workspace/models/*'

# Monitor network activity
netstat -i
```

### Save Logs
```bash
# Save download logs
./download_models_manual.sh 2>&1 | tee model_download.log
```

## ✅ Success Criteria

After successful model download:
- [ ] `/workspace/models/OpenS2S/config.json` exists
- [ ] `/workspace/models/OpenS2S/tokenizer.json` exists  
- [ ] OpenS2S model weights (*.safetensors or *.bin) exist
- [ ] `/workspace/models/glm-4-voice-decoder/config.json` exists
- [ ] GLM-4-Voice-Decoder model weights exist
- [ ] `./verify_models.sh` passes all checks
- [ ] `./start_realtime_services.sh` starts without model path errors
- [ ] Real-time interface accessible at port 8000
