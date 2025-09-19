"""
Performance optimization configuration for OpenS2S real-time streaming
"""

import os
import torch
import logging
from typing import Dict, Any

logger = logging.getLogger(__name__)

class PerformanceOptimizer:
    """
    Performance optimization utilities for real-time streaming
    """
    
    @staticmethod
    def setup_cuda_optimizations():
        """Setup CUDA optimizations for real-time performance"""
        if not torch.cuda.is_available():
            logger.warning("CUDA not available, skipping GPU optimizations")
            return
        
        # Enable CUDA optimizations
        torch.backends.cudnn.benchmark = True
        torch.backends.cudnn.deterministic = False
        torch.backends.cudnn.allow_tf32 = True
        torch.backends.cuda.matmul.allow_tf32 = True
        
        # Set memory management
        torch.cuda.empty_cache()
        
        # Get GPU info
        device_props = torch.cuda.get_device_properties(0)
        total_memory = device_props.total_memory / (1024**3)  # GB
        
        logger.info(f"GPU: {device_props.name}")
        logger.info(f"Total VRAM: {total_memory:.1f}GB")
        logger.info(f"CUDA Compute Capability: {device_props.major}.{device_props.minor}")
        
        # Set memory fraction based on available VRAM
        if total_memory >= 40:  # A100 40GB or higher
            memory_fraction = 0.9
        elif total_memory >= 24:  # RTX 4090, A6000
            memory_fraction = 0.85
        else:  # Lower VRAM GPUs
            memory_fraction = 0.8
            
        torch.cuda.set_per_process_memory_fraction(memory_fraction)
        logger.info(f"Set CUDA memory fraction to {memory_fraction}")
    
    @staticmethod
    def setup_environment_variables():
        """Setup environment variables for optimal performance"""
        env_vars = {
            # PyTorch optimizations
            "PYTORCH_CUDA_ALLOC_CONF": "max_split_size_mb:512",
            "CUDA_LAUNCH_BLOCKING": "0",
            
            # Transformers optimizations
            "TOKENIZERS_PARALLELISM": "false",  # Avoid warnings in multiprocessing
            
            # Flash Attention
            "FLASH_ATTENTION_FORCE_FP16": "1",
            
            # Memory optimizations
            "PYTORCH_KERNEL_CACHE_PATH": "/tmp/pytorch_kernel_cache",
            
            # Networking optimizations
            "UVLOOP_ENABLED": "1",
        }
        
        for key, value in env_vars.items():
            os.environ[key] = value
            logger.info(f"Set {key}={value}")
    
    @staticmethod
    def get_optimal_batch_size(model_size_gb: float, available_vram_gb: float) -> int:
        """Calculate optimal batch size based on model and VRAM"""
        # Conservative estimation
        if available_vram_gb >= 40:  # A100 40GB+
            return 4 if model_size_gb <= 20 else 2
        elif available_vram_gb >= 24:  # RTX 4090, A6000
            return 2 if model_size_gb <= 15 else 1
        else:  # Lower VRAM
            return 1
    
    @staticmethod
    def get_realtime_config() -> Dict[str, Any]:
        """Get optimized configuration for real-time processing"""
        return {
            # Model generation parameters
            "generation": {
                "max_new_tokens": 256,  # Limit for real-time
                "do_sample": True,
                "temperature": 0.7,
                "top_p": 0.9,
                "use_cache": True,  # Enable KV cache
                "pad_token_id": None,  # Will be set by tokenizer
            },
            
            # TTS parameters
            "tts": {
                "block_size": 12,  # Reduced for lower latency
                "do_sample": True,
                "temperature": 1.0,
                "top_p": 1.0,
            },
            
            # Audio processing
            "audio": {
                "sample_rate": 16000,
                "chunk_duration": 0.1,  # 100ms chunks
                "max_audio_duration": 30.0,
                "overlap_duration": 0.02,  # 20ms overlap
            },
            
            # VAD settings
            "vad": {
                "mode": "webrtc",  # or "silero"
                "aggressiveness": 2,  # 0-3 for WebRTC
                "min_speech_duration": 0.3,
                "min_silence_duration": 0.5,
                "speech_pad_ms": 200,
            },
            
            # Streaming settings
            "streaming": {
                "buffer_size": 8192,
                "timeout": 30,
                "ping_interval": 20,
                "ping_timeout": 10,
                "max_message_size": 10 * 1024 * 1024,  # 10MB
            },
            
            # Performance monitoring
            "monitoring": {
                "log_latency": True,
                "log_memory_usage": True,
                "stats_interval": 5.0,  # seconds
            }
        }
    
    @staticmethod
    def setup_logging(log_level: str = "INFO"):
        """Setup optimized logging for real-time systems"""
        logging.basicConfig(
            level=getattr(logging, log_level.upper()),
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.StreamHandler(),
                logging.FileHandler('opens2s_realtime.log', mode='a')
            ]
        )
        
        # Reduce logging for noisy libraries
        logging.getLogger("transformers").setLevel(logging.WARNING)
        logging.getLogger("torch").setLevel(logging.WARNING)
        logging.getLogger("websockets").setLevel(logging.WARNING)
        logging.getLogger("uvicorn").setLevel(logging.WARNING)

class LatencyMonitor:
    """
    Monitor and track latency metrics for real-time performance
    """
    
    def __init__(self):
        self.metrics = {
            "audio_processing": [],
            "model_inference": [],
            "tts_generation": [],
            "total_pipeline": [],
        }
        self.max_samples = 1000  # Keep last 1000 samples
    
    def record_latency(self, metric_name: str, latency_ms: float):
        """Record a latency measurement"""
        if metric_name in self.metrics:
            self.metrics[metric_name].append(latency_ms)
            # Keep only recent samples
            if len(self.metrics[metric_name]) > self.max_samples:
                self.metrics[metric_name] = self.metrics[metric_name][-self.max_samples:]
    
    def get_stats(self, metric_name: str = None) -> Dict[str, Any]:
        """Get latency statistics"""
        if metric_name:
            if metric_name not in self.metrics or not self.metrics[metric_name]:
                return {"error": f"No data for metric {metric_name}"}
            
            values = self.metrics[metric_name]
            return {
                "count": len(values),
                "mean": sum(values) / len(values),
                "min": min(values),
                "max": max(values),
                "p50": sorted(values)[len(values)//2],
                "p95": sorted(values)[int(len(values)*0.95)],
                "p99": sorted(values)[int(len(values)*0.99)],
            }
        else:
            # Return stats for all metrics
            return {
                name: self.get_stats(name) 
                for name in self.metrics.keys()
            }
    
    def reset(self):
        """Reset all metrics"""
        for metric_name in self.metrics:
            self.metrics[metric_name] = []

class MemoryMonitor:
    """
    Monitor GPU and system memory usage
    """
    
    @staticmethod
    def get_gpu_memory_info() -> Dict[str, float]:
        """Get GPU memory information"""
        if not torch.cuda.is_available():
            return {"error": "CUDA not available"}
        
        allocated = torch.cuda.memory_allocated() / (1024**3)  # GB
        reserved = torch.cuda.memory_reserved() / (1024**3)   # GB
        total = torch.cuda.get_device_properties(0).total_memory / (1024**3)  # GB
        
        return {
            "allocated_gb": allocated,
            "reserved_gb": reserved,
            "total_gb": total,
            "free_gb": total - reserved,
            "utilization_percent": (reserved / total) * 100
        }
    
    @staticmethod
    def get_system_memory_info() -> Dict[str, float]:
        """Get system memory information"""
        try:
            import psutil
            memory = psutil.virtual_memory()
            return {
                "total_gb": memory.total / (1024**3),
                "available_gb": memory.available / (1024**3),
                "used_gb": memory.used / (1024**3),
                "utilization_percent": memory.percent
            }
        except ImportError:
            return {"error": "psutil not available"}
    
    @staticmethod
    def cleanup_gpu_memory():
        """Clean up GPU memory"""
        if torch.cuda.is_available():
            torch.cuda.empty_cache()
            torch.cuda.synchronize()

# Global instances
latency_monitor = LatencyMonitor()
performance_optimizer = PerformanceOptimizer()

def initialize_performance_optimizations():
    """Initialize all performance optimizations"""
    logger.info("Initializing performance optimizations...")
    
    # Setup environment variables
    performance_optimizer.setup_environment_variables()
    
    # Setup CUDA optimizations
    performance_optimizer.setup_cuda_optimizations()
    
    # Setup logging
    performance_optimizer.setup_logging()
    
    logger.info("Performance optimizations initialized")

def get_system_info() -> Dict[str, Any]:
    """Get comprehensive system information"""
    info = {
        "gpu": MemoryMonitor.get_gpu_memory_info(),
        "system": MemoryMonitor.get_system_memory_info(),
        "torch_version": torch.__version__,
        "cuda_version": torch.version.cuda if torch.cuda.is_available() else None,
        "device_count": torch.cuda.device_count() if torch.cuda.is_available() else 0,
    }
    
    if torch.cuda.is_available():
        props = torch.cuda.get_device_properties(0)
        info["gpu_details"] = {
            "name": props.name,
            "compute_capability": f"{props.major}.{props.minor}",
            "multiprocessor_count": props.multi_processor_count,
        }
    
    return info

if __name__ == "__main__":
    # Test performance optimizations
    initialize_performance_optimizations()
    
    print("System Information:")
    import json
    print(json.dumps(get_system_info(), indent=2))
    
    print("\nOptimal Configuration:")
    print(json.dumps(performance_optimizer.get_realtime_config(), indent=2))
