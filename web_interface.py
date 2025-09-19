"""
Web interface server for OpenS2S real-time streaming
Serves the HTML client and provides monitoring endpoints
"""

import os
import json
import logging
from datetime import datetime
from typing import Dict, Any
import asyncio

from fastapi import FastAPI, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse, FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
import uvicorn

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class WebInterfaceServer:
    """
    Web interface server for OpenS2S real-time streaming
    """
    
    def __init__(
        self,
        host: str = "0.0.0.0",
        port: int = 8000,
        realtime_ws_url: str = "ws://localhost:8765",
        controller_url: str = "http://localhost:21002"
    ):
        self.host = host
        self.port = port
        self.realtime_ws_url = realtime_ws_url
        self.controller_url = controller_url
        
        # Initialize FastAPI app
        self.app = FastAPI(
            title="OpenS2S Real-time Interface",
            description="Web interface for OpenS2S real-time speech-to-speech",
            version="1.0.0"
        )
        
        # Setup routes
        self.setup_routes()
        
        # Connection monitoring
        self.active_connections: Dict[str, Dict[str, Any]] = {}
        
        logger.info(f"Initialized WebInterfaceServer on {host}:{port}")
    
    def setup_routes(self):
        """Setup FastAPI routes"""
        
        @self.app.get("/", response_class=HTMLResponse)
        async def serve_client():
            """Serve the main client interface"""
            try:
                with open("realtime_client.html", "r", encoding="utf-8") as f:
                    html_content = f.read()
                
                # Replace WebSocket URL placeholder if needed
                html_content = html_content.replace(
                    'value="ws://localhost:8765"',
                    f'value="{self.realtime_ws_url}"'
                )
                
                return HTMLResponse(content=html_content)
            except FileNotFoundError:
                return HTMLResponse(
                    content="<h1>Error: realtime_client.html not found</h1>",
                    status_code=404
                )
        
        @self.app.get("/health")
        async def health_check():
            """Health check endpoint"""
            return {
                "status": "healthy",
                "timestamp": datetime.now().isoformat(),
                "service": "OpenS2S Web Interface",
                "version": "1.0.0"
            }
        
        @self.app.get("/config")
        async def get_config():
            """Get client configuration"""
            return {
                "realtime_ws_url": self.realtime_ws_url,
                "controller_url": self.controller_url,
                "features": {
                    "vad_modes": ["webrtc", "silero"],
                    "audio_formats": ["webm", "wav"],
                    "sample_rates": [16000],
                    "max_audio_duration": 30.0
                }
            }
        
        @self.app.get("/stats")
        async def get_stats():
            """Get server statistics"""
            return {
                "active_connections": len(self.active_connections),
                "connections": [
                    {
                        "id": conn_id,
                        "connected_at": conn_data.get("connected_at"),
                        "last_activity": conn_data.get("last_activity"),
                        "user_agent": conn_data.get("user_agent", "unknown")
                    }
                    for conn_id, conn_data in self.active_connections.items()
                ],
                "server_uptime": datetime.now().isoformat()
            }
        
        @self.app.websocket("/monitor")
        async def websocket_monitor(websocket: WebSocket):
            """WebSocket endpoint for real-time monitoring"""
            await websocket.accept()
            connection_id = f"monitor_{datetime.now().timestamp()}"
            
            try:
                # Send initial stats
                await websocket.send_json({
                    "type": "initial_stats",
                    "data": await self.get_monitoring_data()
                })
                
                # Keep connection alive and send periodic updates
                while True:
                    await asyncio.sleep(5)  # Update every 5 seconds
                    stats = await self.get_monitoring_data()
                    await websocket.send_json({
                        "type": "stats_update",
                        "data": stats,
                        "timestamp": datetime.now().isoformat()
                    })
                    
            except WebSocketDisconnect:
                logger.info(f"Monitor connection {connection_id} disconnected")
            except Exception as e:
                logger.error(f"Monitor WebSocket error: {e}")
        
        @self.app.get("/logs")
        async def get_logs():
            """Get recent log entries (if log file exists)"""
            try:
                # This is a simple implementation - in production you'd want proper log management
                logs = []
                log_file = "opens2s.log"
                if os.path.exists(log_file):
                    with open(log_file, "r") as f:
                        lines = f.readlines()
                        # Get last 100 lines
                        logs = [line.strip() for line in lines[-100:]]
                
                return {
                    "logs": logs,
                    "count": len(logs),
                    "timestamp": datetime.now().isoformat()
                }
            except Exception as e:
                return {
                    "error": str(e),
                    "logs": [],
                    "count": 0
                }
        
        @self.app.post("/test-connection")
        async def test_connection():
            """Test connection to OpenS2S services"""
            import aiohttp
            
            results = {}
            
            # Test controller connection
            try:
                async with aiohttp.ClientSession() as session:
                    async with session.post(
                        f"{self.controller_url}/list_models",
                        timeout=aiohttp.ClientTimeout(total=5)
                    ) as response:
                        if response.status == 200:
                            data = await response.json()
                            results["controller"] = {
                                "status": "connected",
                                "models": data.get("models", [])
                            }
                        else:
                            results["controller"] = {
                                "status": "error",
                                "error": f"HTTP {response.status}"
                            }
            except Exception as e:
                results["controller"] = {
                    "status": "error",
                    "error": str(e)
                }
            
            # Test WebSocket connection
            try:
                import websockets
                async with websockets.connect(
                    self.realtime_ws_url,
                    timeout=5
                ) as websocket:
                    await websocket.send(json.dumps({"type": "ping"}))
                    results["websocket"] = {"status": "connected"}
            except Exception as e:
                results["websocket"] = {
                    "status": "error",
                    "error": str(e)
                }
            
            return {
                "timestamp": datetime.now().isoformat(),
                "results": results
            }
    
    async def get_monitoring_data(self) -> Dict[str, Any]:
        """Get comprehensive monitoring data"""
        return {
            "server": {
                "host": self.host,
                "port": self.port,
                "uptime": datetime.now().isoformat()
            },
            "connections": {
                "active": len(self.active_connections),
                "details": list(self.active_connections.values())
            },
            "services": {
                "realtime_ws_url": self.realtime_ws_url,
                "controller_url": self.controller_url
            }
        }
    
    def run(self):
        """Run the web interface server"""
        logger.info(f"Starting web interface server on http://{self.host}:{self.port}")
        uvicorn.run(
            self.app,
            host=self.host,
            port=self.port,
            log_level="info",
            access_log=True
        )

def main():
    """Main entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(description="OpenS2S Web Interface Server")
    parser.add_argument("--host", default="0.0.0.0", help="Server host")
    parser.add_argument("--port", type=int, default=8000, help="Server port")
    parser.add_argument("--realtime-ws-url", default="ws://localhost:8765",
                       help="Real-time WebSocket server URL")
    parser.add_argument("--controller-url", default="http://localhost:21002",
                       help="OpenS2S controller URL")
    
    args = parser.parse_args()
    
    # Create and run server
    server = WebInterfaceServer(
        host=args.host,
        port=args.port,
        realtime_ws_url=args.realtime_ws_url,
        controller_url=args.controller_url
    )
    
    try:
        server.run()
    except KeyboardInterrupt:
        logger.info("Server stopped by user")
    except Exception as e:
        logger.error(f"Server error: {e}")

if __name__ == "__main__":
    main()
