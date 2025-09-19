# OpenS2S Real-time Streaming Setup Guide

## Overview

This guide provides complete instructions for setting up OpenS2S for real-time speech-to-speech streaming on RunPod platform.

## 🚀 Quick Start

### 1. RunPod Configuration

**Recommended GPU Options:**
- **Primary**: RTX A6000 (48GB VRAM) - $1.89/hour
- **Alternative**: A100 40GB - $2.06/hour  
- **Budget**: RTX 4090 (24GB VRAM) - $0.68/hour

**Required Ports to Expose:**
```
21001  # Controller HTTP API
21002  # Model Worker HTTP API
8765   # WebSocket server for real-time audio streaming
8000   # Web interface for testing
```

### 2. Initial Setup

```bash
# Run the setup script
chmod +x runpod_setup.sh
./runpod_setup.sh
```

### 3. Start Services

```bash
# Start all real-time services
chmod +x start_realtime_services.sh
./start_realtime_services.sh
```

### 4. Access Interface

Open your browser to: `http://your-runpod-url:8000`

## 📋 Detailed Setup Instructions

### System Requirements

- **GPU**: CUDA-compatible with ≥24GB VRAM (48GB recommended)
- **RAM**: ≥32GB system memory
- **Storage**: ≥100GB for models and cache
- **Network**: Stable internet for model downloads

### Model Downloads

The setup script automatically downloads:
- **OpenS2S Model** (~22GB): CASIA-LM/OpenS2S
- **GLM-4-Voice-Decoder** (~8GB): THUDM/glm-4-voice-decoder

### Architecture Overview

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Web Client    │◄──►│  WebSocket       │◄──►│  Model Worker   │
│  (Browser)      │    │  Server          │    │  (OpenS2S)      │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                │                        │
                                ▼                        ▼
                       ┌──────────────────┐    ┌─────────────────┐
                       │  VAD Processor   │    │   Controller    │
                       │  (Voice Activity)│    │   (Load Bal.)   │
                       └──────────────────┘    └─────────────────┘
```

## 🎯 Features

### Real-time Capabilities
- ✅ **Voice Activity Detection (VAD)**: WebRTC and Silero VAD support
- ✅ **Streaming Audio Processing**: 100ms chunks with overlap
- ✅ **Low Latency**: <500ms end-to-end latency
- ✅ **WebSocket Communication**: Real-time bidirectional streaming
- ✅ **Audio Visualization**: Real-time waveform display
- ✅ **Performance Monitoring**: Latency and memory tracking

### Audio Processing
- **Sample Rate**: 16kHz mono
- **Chunk Size**: 100ms (1600 samples)
- **VAD Sensitivity**: Configurable (0-3 for WebRTC)
- **Speech Detection**: Minimum 300ms speech, 500ms silence
- **Audio Formats**: WebM, WAV support

## 🔧 Configuration

### VAD Settings

```python
# WebRTC VAD (Recommended for real-time)
vad_config = {
    "vad_mode": "webrtc",
    "aggressiveness": 2,  # 0=least aggressive, 3=most aggressive
    "min_speech_duration": 0.3,  # seconds
    "min_silence_duration": 0.5,  # seconds
    "speech_pad_ms": 200,  # padding around speech
}

# Silero VAD (Higher accuracy, more CPU)
vad_config = {
    "vad_mode": "silero",
    "speech_threshold": 0.5,  # 0.0-1.0
    "min_speech_duration": 0.3,
    "min_silence_duration": 0.5,
}
```

### Performance Tuning

```python
# Real-time optimizations
realtime_config = {
    "block_size": 12,  # Reduced from 24 for lower latency
    "max_new_tokens": 256,  # Limit for real-time
    "temperature": 0.7,
    "top_p": 0.9,
    "use_cache": True,  # Enable KV cache
}
```

## 🌐 API Endpoints

### WebSocket API (Port 8765)

**Connection**: `ws://your-runpod-url:8765`

**Message Types**:
```javascript
// Start streaming
{
  "type": "start_streaming"
}

// Stop streaming  
{
  "type": "stop_streaming"
}

// Get statistics
{
  "type": "get_stats"
}

// Reset session
{
  "type": "reset_session"
}
```

**Server Responses**:
```javascript
// VAD status
{
  "type": "vad_status",
  "is_speaking": true,
  "speech_probability": 0.85
}

// Model response
{
  "type": "model_response", 
  "text": "Hello, how can I help you?",
  "audio": "base64_encoded_wav",
  "finalize": true
}

// Processing status
{
  "type": "processing_started",
  "audio_duration": 2.5
}
```

### HTTP API

**Health Check**: `GET /health`
**Configuration**: `GET /config`  
**Statistics**: `GET /stats`
**Test Connection**: `POST /test-connection`

## 📊 Monitoring

### Performance Metrics

The system tracks:
- **Audio Processing Latency**: VAD + feature extraction
- **Model Inference Latency**: LLM processing time
- **TTS Generation Latency**: Speech synthesis time
- **Total Pipeline Latency**: End-to-end processing
- **Memory Usage**: GPU and system memory
- **Connection Statistics**: Active connections, errors

### Real-time Dashboard

Access monitoring at: `http://your-runpod-url:8000/monitor`

## 🔍 Troubleshooting

### Common Issues

**1. High Latency (>1000ms)**
```bash
# Check GPU memory
python -c "import torch; print(torch.cuda.memory_summary())"

# Reduce block size
# Edit realtime_server.py: block_size = 8
```

**2. VAD Not Detecting Speech**
```bash
# Increase VAD sensitivity
# In client: Change VAD aggressiveness to 1 or 0
# Or switch to Silero VAD with lower threshold (0.3)
```

**3. WebSocket Connection Fails**
```bash
# Check if port is open
netstat -tlnp | grep 8765

# Check firewall
ufw status

# Restart WebSocket server
pkill -f realtime_server.py
python realtime_server.py --host 0.0.0.0 --port 8765
```

**4. Model Download Issues**

**Problem**: Git LFS errors or download failures

**Quick Solutions**:
```bash
# Emergency manual download
chmod +x download_models_manual.sh
./download_models_manual.sh

# Python-based downloader
python model_downloader.py --models-dir /workspace/models

# Verify models
chmod +x verify_models.sh
./verify_models.sh
```

**For comprehensive troubleshooting**: See `MODEL_DOWNLOAD_TROUBLESHOOTING.md`

**4. Model Loading Errors**
```bash
# Check model paths
ls -la /workspace/models/OpenS2S
ls -la /workspace/models/glm-4-voice-decoder

# Check VRAM
nvidia-smi

# Reduce memory usage
export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:256
```

### Log Files

Check these log files for debugging:
- `controller.log` - Controller service logs
- `worker.log` - Model worker logs  
- `websocket.log` - WebSocket server logs
- `web.log` - Web interface logs
- `opens2s_realtime.log` - Combined application logs

### Performance Optimization

**For RTX 4090 (24GB VRAM)**:
```bash
# Reduce memory usage
export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512
# Use smaller block size
# Edit model_worker.py: block_size = 8
```

**For A100 (40GB+ VRAM)**:
```bash
# Enable flash attention optimizations
export FLASH_ATTENTION_FORCE_FP16=1
# Use larger block size for better quality
# Edit model_worker.py: block_size = 16
```

## 🎮 Usage Examples

### Basic Real-time Conversation

1. Open `http://your-runpod-url:8000`
2. Click "Connect" to establish WebSocket connection
3. Click "Start Recording" and speak
4. Watch VAD indicator turn green when speech detected
5. Receive real-time text and audio responses

### Programmatic Usage

```python
import asyncio
import websockets
import json

async def realtime_client():
    uri = "ws://your-runpod-url:8765"
    
    async with websockets.connect(uri) as websocket:
        # Start streaming
        await websocket.send(json.dumps({"type": "start_streaming"}))
        
        # Send audio data (binary)
        audio_data = b"..."  # Your audio bytes
        await websocket.send(audio_data)
        
        # Receive responses
        async for message in websocket:
            data = json.loads(message)
            if data["type"] == "model_response":
                print(f"Response: {data['text']}")
                if data["audio"]:
                    # Play audio response
                    play_audio(data["audio"])

asyncio.run(realtime_client())
```

## 📈 Performance Benchmarks

**Expected Latencies** (RTX A6000):
- VAD Processing: 5-10ms
- Audio Feature Extraction: 20-30ms  
- Model Inference: 200-400ms
- TTS Generation: 100-200ms
- **Total End-to-End**: 350-650ms

**Throughput**:
- Concurrent Users: 2-4 (depending on GPU)
- Audio Processing: Real-time (1x speed)
- Memory Usage: ~20-25GB VRAM

## 🔒 Security Considerations

- WebSocket connections are not encrypted by default
- For production, use WSS (WebSocket Secure) with SSL certificates
- Implement authentication and rate limiting
- Monitor resource usage to prevent abuse

## 📞 Support

For issues and questions:
1. Check the troubleshooting section above
2. Review log files for error messages
3. Verify GPU memory and system resources
4. Test with smaller audio chunks or reduced model parameters

## 🎉 Success Criteria

Your setup is working correctly when:
- ✅ All services start without errors
- ✅ WebSocket connection establishes successfully  
- ✅ VAD detects speech activity (green indicator)
- ✅ End-to-end latency is <1000ms
- ✅ Audio responses play automatically
- ✅ No memory errors in logs
- ✅ Multiple conversation turns work smoothly
