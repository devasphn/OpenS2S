# OpenS2S Production Deployment Guide

## 🚀 Ultra-Low Latency Real-time Streaming System

This guide provides comprehensive instructions for deploying the optimized OpenS2S real-time streaming system in production environments, specifically optimized for RunPod platform.

## 📋 Prerequisites

### Hardware Requirements
- **GPU**: NVIDIA RTX A6000, A100, or RTX 4090 (minimum 24GB VRAM)
- **CPU**: 8+ cores, 3.0GHz+ (Intel Xeon or AMD EPYC recommended)
- **RAM**: 32GB+ system memory
- **Storage**: 100GB+ SSD storage for models and cache
- **Network**: High-bandwidth internet connection (1Gbps+ recommended)

### Software Requirements
- **OS**: Ubuntu 20.04+ or compatible Linux distribution
- **Python**: 3.9+ (3.10 recommended)
- **CUDA**: 11.8+ or 12.1+
- **Docker**: 20.10+ (optional, for containerized deployment)

## 🏗️ Architecture Overview

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Web Client    │◄──►│  Web Interface  │◄──►│ Realtime Server │
│  (Port 8000)    │    │   (Port 8000)   │    │  (Port 8765)    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                        │
                                                        ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Controller    │◄──►│  Model Worker   │◄──►│ Audio Processor │
│  (Port 21001)   │    │  (Port 21002)   │    │   (In-process)  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 📦 Installation Steps

### 1. Clone and Setup Repository
```bash
git clone <repository-url>
cd OpenS2S
```

### 2. Install Dependencies
```bash
# Install production requirements
pip install -r requirements_production.txt

# Verify GPU setup
python -c "import torch; print(f'CUDA: {torch.cuda.is_available()}, Devices: {torch.cuda.device_count()}')"
```

### 3. Download Models
```bash
# Download required models
python model_downloader.py --model-name OpenS2S --model-name GLM-4-Voice-Decoder

# Verify model downloads
./verify_models.sh
```

### 4. Configure Performance Settings
```bash
# Copy performance configuration
cp config/performance.yaml config/production.yaml

# Edit configuration for your hardware
nano config/production.yaml
```

## 🚀 Deployment Options

### Option 1: Quick Start (Recommended)
```bash
# Make startup script executable
chmod +x scripts/start_production.sh

# Start all services
./scripts/start_production.sh
```

### Option 2: Manual Service Start
```bash
# Start Controller
python controller.py --host 0.0.0.0 --port 21001 &

# Start Model Worker
python model_worker.py \
    --host 0.0.0.0 \
    --port 21002 \
    --model-path "/workspace/models/OpenS2S" \
    --flow-path "/workspace/models/glm-4-voice-decoder" \
    --controller-address "http://localhost:21001" \
    --limit-model-concurrency 4 &

# Start WebSocket Server
python realtime_server.py \
    --host 0.0.0.0 \
    --port 8765 \
    --controller-url "http://localhost:21001" &

# Start Web Interface
python web_interface.py \
    --host 0.0.0.0 \
    --port 8000 \
    --realtime-ws-url "ws://localhost:8765" &
```

## 🔧 Performance Optimization

### GPU Optimizations
```bash
# Set CUDA environment variables
export CUDA_VISIBLE_DEVICES=0
export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512

# Enable mixed precision
export TORCH_CUDNN_V8_API_ENABLED=1
```

### Memory Optimizations
```bash
# Optimize memory allocation
export OMP_NUM_THREADS=4
export MKL_NUM_THREADS=4
export MALLOC_TRIM_THRESHOLD_=100000
```

### Network Optimizations
```bash
# Increase network buffer sizes
echo 'net.core.rmem_max = 134217728' >> /etc/sysctl.conf
echo 'net.core.wmem_max = 134217728' >> /etc/sysctl.conf
sysctl -p
```

## 📊 Monitoring and Health Checks

### Health Check
```bash
# Run comprehensive health check
python monitoring/health_check.py

# Continuous monitoring
python monitoring/health_check.py --continuous --interval 30
```

### Performance Monitoring
```bash
# Start performance monitor
python monitoring/performance_monitor.py

# Run latency test
python monitoring/performance_monitor.py --test-latency --num-tests 20
```

### Log Monitoring
```bash
# Monitor all service logs
tail -f *.log

# Monitor specific service
tail -f worker.log
```

## 🎯 Performance Targets

### Latency Targets
- **End-to-end latency**: <500ms (target: <300ms)
- **VAD detection**: <50ms
- **Model inference**: <200ms
- **Audio generation**: <150ms
- **Network overhead**: <50ms

### Throughput Targets
- **Concurrent users**: 10+ simultaneous streams
- **Audio quality**: 16kHz, 16-bit
- **Real-time factor**: <0.3 (faster than real-time)

## 🔒 Security Considerations

### Network Security
```bash
# Configure firewall (example for Ubuntu)
ufw allow 8000/tcp   # Web interface
ufw allow 8765/tcp   # WebSocket
ufw deny 21001/tcp   # Controller (internal only)
ufw deny 21002/tcp   # Worker (internal only)
```

### SSL/TLS Configuration
```bash
# For production, use reverse proxy with SSL
# Example nginx configuration in docs/nginx.conf
```

## 🐳 Docker Deployment (Optional)

### Build Docker Image
```bash
# Build production image
docker build -f Dockerfile.production -t openspeech:latest .
```

### Run Container
```bash
# Run with GPU support
docker run --gpus all \
    -p 8000:8000 \
    -p 8765:8765 \
    -v /path/to/models:/workspace/models \
    openspeech:latest
```

## 🔧 Troubleshooting

### Common Issues

#### GPU Memory Issues
```bash
# Clear GPU cache
python -c "import torch; torch.cuda.empty_cache()"

# Monitor GPU usage
nvidia-smi -l 1
```

#### Model Loading Issues
```bash
# Verify model files
ls -la /workspace/models/OpenS2S/
ls -la /workspace/models/glm-4-voice-decoder/

# Re-register models
python register_openspeech.py
```

#### Network Connection Issues
```bash
# Check port availability
netstat -tlnp | grep -E '(8000|8765|21001|21002)'

# Test WebSocket connection
python -c "import websockets; import asyncio; asyncio.run(websockets.connect('ws://localhost:8765'))"
```

### Performance Issues
```bash
# Check system resources
htop
nvidia-smi

# Profile application
python -m py_spy top --pid <worker_pid>
```

## 📈 Scaling and Load Balancing

### Horizontal Scaling
```bash
# Start multiple workers
python model_worker.py --port 21003 --worker-address "http://localhost:21003" &
python model_worker.py --port 21004 --worker-address "http://localhost:21004" &
```

### Load Balancer Configuration
```nginx
# Example nginx load balancer configuration
upstream openspeech_workers {
    server localhost:21002;
    server localhost:21003;
    server localhost:21004;
}
```

## 🔄 Maintenance and Updates

### Regular Maintenance
```bash
# Clean up logs (weekly)
find . -name "*.log" -mtime +7 -delete

# Update dependencies (monthly)
pip install -r requirements_production.txt --upgrade

# Model cache cleanup
rm -rf ~/.cache/huggingface/transformers/
```

### Backup Procedures
```bash
# Backup configuration
tar -czf config_backup_$(date +%Y%m%d).tar.gz config/

# Backup models (if customized)
tar -czf models_backup_$(date +%Y%m%d).tar.gz /workspace/models/
```

## 📞 Support and Contact

For production support and advanced configuration:
- Check logs in the current directory (*.log files)
- Run health checks: `python monitoring/health_check.py`
- Monitor performance: `python monitoring/performance_monitor.py`
- Review configuration: `config/performance.yaml`

## 🎉 Success Verification

After deployment, verify the system is working:

1. **Health Check**: All services show ✅ HEALTHY
2. **Web Interface**: Accessible at http://your-server:8000
3. **WebSocket**: Real-time audio streaming works
4. **Latency**: End-to-end latency <500ms
5. **Performance**: System handles concurrent users

Your OpenS2S real-time streaming system is now ready for production use!
