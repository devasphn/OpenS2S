#!/usr/bin/env python3
"""
OpenS2S Health Check Script
Comprehensive health monitoring for all services
"""

import asyncio
import aiohttp
import json
import time
import sys
import argparse
from typing import Dict, List, Optional, Tuple
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class HealthChecker:
    """
    Comprehensive health checker for OpenS2S services
    """
    
    def __init__(
        self,
        controller_url: str = "http://localhost:21001",
        worker_url: str = "http://localhost:21002",
        web_url: str = "http://localhost:8000",
        websocket_url: str = "ws://localhost:8765",
        timeout: float = 10.0
    ):
        self.controller_url = controller_url
        self.worker_url = worker_url
        self.web_url = web_url
        self.websocket_url = websocket_url
        self.timeout = timeout
        
        self.health_status = {}
        
    async def check_all_services(self) -> Dict[str, bool]:
        """Check health of all services"""
        logger.info("Starting comprehensive health check...")
        
        async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=self.timeout)) as session:
            # Check all services concurrently
            tasks = [
                self._check_controller(session),
                self._check_worker(session),
                self._check_web_interface(session),
                self._check_websocket_connection(),
                self._check_model_availability(session),
                self._check_system_resources()
            ]
            
            results = await asyncio.gather(*tasks, return_exceptions=True)
            
            # Process results
            service_names = ['controller', 'worker', 'web', 'websocket', 'models', 'system']
            for i, result in enumerate(results):
                service_name = service_names[i]
                if isinstance(result, Exception):
                    logger.error(f"{service_name} check failed: {result}")
                    self.health_status[service_name] = False
                else:
                    self.health_status[service_name] = result
        
        return self.health_status
    
    async def _check_controller(self, session: aiohttp.ClientSession) -> bool:
        """Check controller service health"""
        try:
            async with session.get(f"{self.controller_url}/list_models") as response:
                if response.status == 200:
                    data = await response.json()
                    logger.info("✅ Controller: Healthy")
                    return True
                else:
                    logger.error(f"❌ Controller: HTTP {response.status}")
                    return False
        except Exception as e:
            logger.error(f"❌ Controller: {e}")
            return False
    
    async def _check_worker(self, session: aiohttp.ClientSession) -> bool:
        """Check worker service health"""
        try:
            async with session.get(f"{self.worker_url}/worker_get_status") as response:
                if response.status == 200:
                    data = await response.json()
                    logger.info("✅ Worker: Healthy")
                    return True
                else:
                    logger.error(f"❌ Worker: HTTP {response.status}")
                    return False
        except Exception as e:
            logger.error(f"❌ Worker: {e}")
            return False
    
    async def _check_web_interface(self, session: aiohttp.ClientSession) -> bool:
        """Check web interface health"""
        try:
            async with session.get(f"{self.web_url}/health") as response:
                if response.status == 200:
                    logger.info("✅ Web Interface: Healthy")
                    return True
                else:
                    logger.error(f"❌ Web Interface: HTTP {response.status}")
                    return False
        except Exception as e:
            logger.error(f"❌ Web Interface: {e}")
            return False
    
    async def _check_websocket_connection(self) -> bool:
        """Check WebSocket server health"""
        try:
            import websockets
            
            async with websockets.connect(self.websocket_url) as websocket:
                # Send a ping message
                await websocket.send(json.dumps({
                    "type": "ping",
                    "timestamp": time.time()
                }))
                
                # Wait for response
                response = await asyncio.wait_for(websocket.recv(), timeout=5.0)
                data = json.loads(response)
                
                if data.get("type") == "pong":
                    logger.info("✅ WebSocket: Healthy")
                    return True
                else:
                    logger.error("❌ WebSocket: Invalid response")
                    return False
                    
        except Exception as e:
            logger.error(f"❌ WebSocket: {e}")
            return False
    
    async def _check_model_availability(self, session: aiohttp.ClientSession) -> bool:
        """Check if models are loaded and available"""
        try:
            # Check if models are listed in controller
            async with session.get(f"{self.controller_url}/list_models") as response:
                if response.status == 200:
                    data = await response.json()
                    models = data.get("models", [])
                    
                    if "omnispeech" in models:
                        logger.info("✅ Models: OpenS2S model available")
                        return True
                    else:
                        logger.error("❌ Models: OpenS2S model not available")
                        return False
                else:
                    logger.error(f"❌ Models: Cannot check model list (HTTP {response.status})")
                    return False
                    
        except Exception as e:
            logger.error(f"❌ Models: {e}")
            return False
    
    async def _check_system_resources(self) -> bool:
        """Check system resources"""
        try:
            import psutil
            import torch
            
            # Check CPU usage
            cpu_percent = psutil.cpu_percent(interval=1)
            if cpu_percent > 90:
                logger.warning(f"⚠️  High CPU usage: {cpu_percent:.1f}%")
            
            # Check memory usage
            memory = psutil.virtual_memory()
            if memory.percent > 90:
                logger.warning(f"⚠️  High memory usage: {memory.percent:.1f}%")
            
            # Check disk space
            disk = psutil.disk_usage('/')
            if disk.percent > 90:
                logger.warning(f"⚠️  Low disk space: {disk.percent:.1f}% used")
            
            # Check GPU if available
            if torch.cuda.is_available():
                gpu_memory = torch.cuda.memory_allocated() / torch.cuda.max_memory_allocated() * 100
                if gpu_memory > 90:
                    logger.warning(f"⚠️  High GPU memory usage: {gpu_memory:.1f}%")
                
                logger.info(f"✅ System: CPU {cpu_percent:.1f}%, Memory {memory.percent:.1f}%, GPU {gpu_memory:.1f}%")
            else:
                logger.info(f"✅ System: CPU {cpu_percent:.1f}%, Memory {memory.percent:.1f}%")
            
            return True
            
        except Exception as e:
            logger.error(f"❌ System: {e}")
            return False
    
    async def run_performance_test(self) -> Dict[str, float]:
        """Run a simple performance test"""
        logger.info("Running performance test...")
        
        try:
            async with aiohttp.ClientSession() as session:
                # Test simple inference
                start_time = time.time()
                
                async with session.post(
                    f"{self.worker_url}/worker_generate_stream",
                    json={
                        "model": "omnispeech",
                        "messages": [{"role": "user", "content": "Hello, how are you?"}],
                        "max_tokens": 50,
                        "temperature": 0.7
                    }
                ) as response:
                    if response.status == 200:
                        # Read the streaming response
                        async for chunk in response.content.iter_chunked(1024):
                            pass  # Just consume the response
                        
                        end_time = time.time()
                        latency = (end_time - start_time) * 1000  # ms
                        
                        logger.info(f"✅ Performance Test: {latency:.1f}ms latency")
                        return {"latency_ms": latency}
                    else:
                        logger.error(f"❌ Performance Test: HTTP {response.status}")
                        return {"latency_ms": -1}
                        
        except Exception as e:
            logger.error(f"❌ Performance Test: {e}")
            return {"latency_ms": -1}
    
    def print_health_summary(self):
        """Print health check summary"""
        print("\n" + "="*50)
        print("OpenS2S Health Check Summary")
        print("="*50)
        
        all_healthy = True
        for service, healthy in self.health_status.items():
            status = "✅ HEALTHY" if healthy else "❌ UNHEALTHY"
            print(f"{service.title():15} {status}")
            if not healthy:
                all_healthy = False
        
        print("="*50)
        if all_healthy:
            print("🎉 All services are healthy!")
            print("✅ OpenS2S is ready for production use")
        else:
            print("⚠️  Some services are unhealthy")
            print("❌ Please check the logs and fix issues before deployment")
        print("="*50)
        
        return all_healthy

async def main():
    parser = argparse.ArgumentParser(description="OpenS2S Health Check")
    parser.add_argument("--controller-url", default="http://localhost:21001",
                       help="Controller URL")
    parser.add_argument("--worker-url", default="http://localhost:21002",
                       help="Worker URL")
    parser.add_argument("--web-url", default="http://localhost:8000",
                       help="Web interface URL")
    parser.add_argument("--websocket-url", default="ws://localhost:8765",
                       help="WebSocket URL")
    parser.add_argument("--timeout", type=float, default=10.0,
                       help="Request timeout in seconds")
    parser.add_argument("--performance-test", action="store_true",
                       help="Run performance test")
    parser.add_argument("--continuous", action="store_true",
                       help="Run continuous health checks")
    parser.add_argument("--interval", type=float, default=30.0,
                       help="Interval for continuous checks (seconds)")
    
    args = parser.parse_args()
    
    checker = HealthChecker(
        controller_url=args.controller_url,
        worker_url=args.worker_url,
        web_url=args.web_url,
        websocket_url=args.websocket_url,
        timeout=args.timeout
    )
    
    if args.continuous:
        # Run continuous health checks
        logger.info(f"Starting continuous health checks (interval: {args.interval}s)")
        
        while True:
            try:
                await checker.check_all_services()
                checker.print_health_summary()
                
                if args.performance_test:
                    perf_results = await checker.run_performance_test()
                    print(f"Performance: {perf_results}")
                
                await asyncio.sleep(args.interval)
                
            except KeyboardInterrupt:
                logger.info("Health check stopped by user")
                break
            except Exception as e:
                logger.error(f"Health check error: {e}")
                await asyncio.sleep(5)
    else:
        # Run single health check
        await checker.check_all_services()
        
        if args.performance_test:
            perf_results = await checker.run_performance_test()
            print(f"Performance Results: {perf_results}")
        
        all_healthy = checker.print_health_summary()
        
        # Exit with appropriate code
        sys.exit(0 if all_healthy else 1)

if __name__ == "__main__":
    asyncio.run(main())
