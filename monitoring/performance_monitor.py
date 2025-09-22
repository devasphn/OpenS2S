#!/usr/bin/env python3
"""
OpenS2S Performance Monitor
Real-time monitoring of latency, throughput, and system resources
"""

import asyncio
import websockets
import json
import time
import psutil
import logging
import argparse
from datetime import datetime
from typing import Dict, List, Optional
from collections import defaultdict, deque
import requests
import torch

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class PerformanceMonitor:
    """
    Real-time performance monitor for OpenS2S services
    """
    
    def __init__(
        self,
        controller_url: str = "http://localhost:21001",
        worker_url: str = "http://localhost:21002", 
        websocket_url: str = "ws://localhost:8765",
        web_url: str = "http://localhost:8000",
        monitor_interval: float = 5.0
    ):
        self.controller_url = controller_url
        self.worker_url = worker_url
        self.websocket_url = websocket_url
        self.web_url = web_url
        self.monitor_interval = monitor_interval
        
        # Performance metrics
        self.metrics = defaultdict(deque)
        self.latency_history = deque(maxlen=1000)
        self.throughput_history = deque(maxlen=1000)
        
        # System monitoring
        self.process_monitor = psutil.Process()
        
    async def monitor_services(self):
        """Monitor all OpenS2S services"""
        logger.info("Starting performance monitoring...")
        
        while True:
            try:
                timestamp = datetime.now()
                
                # Monitor system resources
                await self._monitor_system_resources(timestamp)
                
                # Monitor service health
                await self._monitor_service_health(timestamp)
                
                # Monitor GPU if available
                if torch.cuda.is_available():
                    await self._monitor_gpu_resources(timestamp)
                
                # Log performance summary
                self._log_performance_summary()
                
                await asyncio.sleep(self.monitor_interval)
                
            except Exception as e:
                logger.error(f"Monitoring error: {e}")
                await asyncio.sleep(1)
    
    async def _monitor_system_resources(self, timestamp: datetime):
        """Monitor CPU, memory, and disk usage"""
        try:
            # CPU usage
            cpu_percent = psutil.cpu_percent(interval=1)
            self.metrics['cpu_usage'].append((timestamp, cpu_percent))
            
            # Memory usage
            memory = psutil.virtual_memory()
            self.metrics['memory_usage'].append((timestamp, memory.percent))
            self.metrics['memory_available'].append((timestamp, memory.available / 1024 / 1024))  # MB
            
            # Disk usage
            disk = psutil.disk_usage('/')
            self.metrics['disk_usage'].append((timestamp, disk.percent))
            
            # Network I/O
            net_io = psutil.net_io_counters()
            self.metrics['network_sent'].append((timestamp, net_io.bytes_sent))
            self.metrics['network_recv'].append((timestamp, net_io.bytes_recv))
            
        except Exception as e:
            logger.error(f"System monitoring error: {e}")
    
    async def _monitor_service_health(self, timestamp: datetime):
        """Monitor health of all services"""
        services = {
            'controller': self.controller_url + '/list_models',
            'worker': self.worker_url + '/worker_get_status',
            'web': self.web_url + '/health'
        }
        
        for service_name, url in services.items():
            try:
                start_time = time.time()
                response = requests.get(url, timeout=5)
                response_time = (time.time() - start_time) * 1000  # ms
                
                if response.status_code == 200:
                    self.metrics[f'{service_name}_response_time'].append((timestamp, response_time))
                    self.metrics[f'{service_name}_status'].append((timestamp, 1))  # healthy
                else:
                    self.metrics[f'{service_name}_status'].append((timestamp, 0))  # unhealthy
                    
            except Exception as e:
                logger.warning(f"Service {service_name} health check failed: {e}")
                self.metrics[f'{service_name}_status'].append((timestamp, 0))
    
    async def _monitor_gpu_resources(self, timestamp: datetime):
        """Monitor GPU resources"""
        try:
            # GPU memory
            gpu_memory_allocated = torch.cuda.memory_allocated() / 1024 / 1024  # MB
            gpu_memory_reserved = torch.cuda.memory_reserved() / 1024 / 1024  # MB
            
            self.metrics['gpu_memory_allocated'].append((timestamp, gpu_memory_allocated))
            self.metrics['gpu_memory_reserved'].append((timestamp, gpu_memory_reserved))
            
            # GPU utilization (if nvidia-ml-py is available)
            try:
                import pynvml
                pynvml.nvmlInit()
                handle = pynvml.nvmlDeviceGetHandleByIndex(0)
                gpu_util = pynvml.nvmlDeviceGetUtilizationRates(handle)
                self.metrics['gpu_utilization'].append((timestamp, gpu_util.gpu))
                
                # GPU temperature
                temp = pynvml.nvmlDeviceGetTemperature(handle, pynvml.NVML_TEMPERATURE_GPU)
                self.metrics['gpu_temperature'].append((timestamp, temp))
                
            except ImportError:
                pass  # pynvml not available
                
        except Exception as e:
            logger.error(f"GPU monitoring error: {e}")
    
    def _log_performance_summary(self):
        """Log performance summary"""
        if len(self.metrics['cpu_usage']) < 2:
            return
            
        # Calculate averages for recent metrics
        recent_window = 10  # last 10 measurements
        
        summary = {}
        for metric_name, values in self.metrics.items():
            if len(values) >= 2:
                recent_values = [v[1] for v in list(values)[-recent_window:]]
                summary[metric_name] = {
                    'avg': sum(recent_values) / len(recent_values),
                    'min': min(recent_values),
                    'max': max(recent_values),
                    'current': recent_values[-1]
                }
        
        # Log key metrics
        logger.info("=== Performance Summary ===")
        
        if 'cpu_usage' in summary:
            cpu = summary['cpu_usage']
            logger.info(f"CPU: {cpu['current']:.1f}% (avg: {cpu['avg']:.1f}%)")
        
        if 'memory_usage' in summary:
            mem = summary['memory_usage']
            logger.info(f"Memory: {mem['current']:.1f}% (avg: {mem['avg']:.1f}%)")
        
        if 'gpu_memory_allocated' in summary:
            gpu_mem = summary['gpu_memory_allocated']
            logger.info(f"GPU Memory: {gpu_mem['current']:.1f}MB (avg: {gpu_mem['avg']:.1f}MB)")
        
        # Service response times
        for service in ['controller', 'worker', 'web']:
            metric_name = f'{service}_response_time'
            if metric_name in summary:
                resp = summary[metric_name]
                logger.info(f"{service.title()} Response: {resp['current']:.1f}ms (avg: {resp['avg']:.1f}ms)")
    
    async def test_latency(self, num_tests: int = 10):
        """Test end-to-end latency"""
        logger.info(f"Testing end-to-end latency with {num_tests} requests...")
        
        latencies = []
        
        for i in range(num_tests):
            try:
                start_time = time.time()
                
                # Simulate a simple request to the worker
                response = requests.post(
                    f"{self.worker_url}/worker_generate_stream",
                    json={
                        "model": "omnispeech",
                        "messages": [{"role": "user", "content": "Hello"}],
                        "max_tokens": 10
                    },
                    timeout=30
                )
                
                end_time = time.time()
                latency = (end_time - start_time) * 1000  # ms
                latencies.append(latency)
                
                logger.info(f"Test {i+1}/{num_tests}: {latency:.1f}ms")
                
            except Exception as e:
                logger.error(f"Latency test {i+1} failed: {e}")
        
        if latencies:
            avg_latency = sum(latencies) / len(latencies)
            min_latency = min(latencies)
            max_latency = max(latencies)
            
            logger.info("=== Latency Test Results ===")
            logger.info(f"Average: {avg_latency:.1f}ms")
            logger.info(f"Minimum: {min_latency:.1f}ms")
            logger.info(f"Maximum: {max_latency:.1f}ms")
            logger.info(f"Success rate: {len(latencies)}/{num_tests} ({len(latencies)/num_tests*100:.1f}%)")
            
            return {
                'average': avg_latency,
                'minimum': min_latency,
                'maximum': max_latency,
                'success_rate': len(latencies) / num_tests
            }
        
        return None

async def main():
    parser = argparse.ArgumentParser(description="OpenS2S Performance Monitor")
    parser.add_argument("--controller-url", default="http://localhost:21001",
                       help="Controller URL")
    parser.add_argument("--worker-url", default="http://localhost:21002",
                       help="Worker URL")
    parser.add_argument("--websocket-url", default="ws://localhost:8765",
                       help="WebSocket URL")
    parser.add_argument("--web-url", default="http://localhost:8000",
                       help="Web interface URL")
    parser.add_argument("--interval", type=float, default=5.0,
                       help="Monitoring interval in seconds")
    parser.add_argument("--test-latency", action="store_true",
                       help="Run latency test and exit")
    parser.add_argument("--num-tests", type=int, default=10,
                       help="Number of latency tests to run")
    
    args = parser.parse_args()
    
    monitor = PerformanceMonitor(
        controller_url=args.controller_url,
        worker_url=args.worker_url,
        websocket_url=args.websocket_url,
        web_url=args.web_url,
        monitor_interval=args.interval
    )
    
    if args.test_latency:
        # Run latency test and exit
        results = await monitor.test_latency(args.num_tests)
        if results:
            print(f"\nLatency Test Results:")
            print(f"Average: {results['average']:.1f}ms")
            print(f"Range: {results['minimum']:.1f}ms - {results['maximum']:.1f}ms")
            print(f"Success Rate: {results['success_rate']*100:.1f}%")
    else:
        # Run continuous monitoring
        await monitor.monitor_services()

if __name__ == "__main__":
    asyncio.run(main())
