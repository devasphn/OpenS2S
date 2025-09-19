"""
Real-time WebSocket streaming server for OpenS2S
Handles continuous audio input, VAD, and real-time speech-to-speech processing
"""

import asyncio
import websockets
import json
import logging
import base64
import numpy as np
import torch
import torchaudio
from typing import Dict, Optional, Set
import uuid
from datetime import datetime
import requests
from io import BytesIO
import tempfile
import os

from vad_processor import VADProcessor, AudioBuffer

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class RealtimeStreamingServer:
    """
    Real-time streaming server for OpenS2S
    """
    
    def __init__(
        self,
        host: str = "0.0.0.0",
        port: int = 8765,
        controller_url: str = "http://localhost:21002",
        sample_rate: int = 16000,
        vad_mode: str = "webrtc",
        vad_aggressiveness: int = 2,
        max_audio_duration: float = 30.0,
        chunk_duration: float = 0.1,  # 100ms chunks
    ):
        self.host = host
        self.port = port
        self.controller_url = controller_url
        self.sample_rate = sample_rate
        self.max_audio_duration = max_audio_duration
        self.chunk_duration = chunk_duration
        self.chunk_size = int(sample_rate * chunk_duration)
        
        # Active connections
        self.connections: Dict[str, Dict] = {}
        
        # Initialize VAD
        self.vad_config = {
            "vad_mode": vad_mode,
            "aggressiveness": vad_aggressiveness,
            "sample_rate": sample_rate,
            "min_speech_duration": 0.5,
            "min_silence_duration": 0.8,
            "speech_pad_ms": 200,
        }
        
        logger.info(f"Initialized RealtimeStreamingServer on {host}:{port}")
    
    async def start_server(self):
        """Start the WebSocket server"""
        logger.info(f"Starting WebSocket server on ws://{self.host}:{self.port}")
        
        async with websockets.serve(
            self.handle_connection,
            self.host,
            self.port,
            ping_interval=20,
            ping_timeout=10,
            max_size=10**7,  # 10MB max message size
        ):
            logger.info("WebSocket server started successfully")
            await asyncio.Future()  # Run forever
    
    async def handle_connection(self, websocket, path):
        """Handle new WebSocket connection"""
        connection_id = str(uuid.uuid4())
        client_ip = websocket.remote_address[0] if websocket.remote_address else "unknown"
        
        logger.info(f"New connection: {connection_id} from {client_ip}")
        
        # Initialize connection state
        self.connections[connection_id] = {
            "websocket": websocket,
            "vad": VADProcessor(**self.vad_config),
            "audio_buffer": AudioBuffer(max_duration=self.max_audio_duration, sample_rate=self.sample_rate),
            "is_processing": False,
            "session_id": str(uuid.uuid4()),
            "connected_at": datetime.now(),
            "stats": {
                "audio_chunks_received": 0,
                "speech_segments_processed": 0,
                "total_audio_duration": 0.0,
                "errors": 0,
            }
        }
        
        try:
            # Send welcome message
            await self.send_message(connection_id, {
                "type": "connection_established",
                "connection_id": connection_id,
                "session_id": self.connections[connection_id]["session_id"],
                "config": {
                    "sample_rate": self.sample_rate,
                    "chunk_duration": self.chunk_duration,
                    "vad_mode": self.vad_config["vad_mode"],
                }
            })
            
            # Handle messages
            async for message in websocket:
                await self.handle_message(connection_id, message)
                
        except websockets.exceptions.ConnectionClosed:
            logger.info(f"Connection {connection_id} closed normally")
        except Exception as e:
            logger.error(f"Error in connection {connection_id}: {e}")
            self.connections[connection_id]["stats"]["errors"] += 1
        finally:
            await self.cleanup_connection(connection_id)
    
    async def handle_message(self, connection_id: str, message):
        """Handle incoming WebSocket message"""
        try:
            if isinstance(message, bytes):
                # Binary audio data
                await self.handle_audio_data(connection_id, message)
            else:
                # JSON message
                data = json.loads(message)
                await self.handle_json_message(connection_id, data)
                
        except Exception as e:
            logger.error(f"Error handling message from {connection_id}: {e}")
            await self.send_error(connection_id, f"Message handling error: {str(e)}")
    
    async def handle_json_message(self, connection_id: str, data: dict):
        """Handle JSON control messages"""
        message_type = data.get("type")
        
        if message_type == "start_streaming":
            logger.info(f"Starting audio streaming for {connection_id}")
            await self.send_message(connection_id, {
                "type": "streaming_started",
                "message": "Ready to receive audio data"
            })
            
        elif message_type == "stop_streaming":
            logger.info(f"Stopping audio streaming for {connection_id}")
            await self.finalize_speech(connection_id)
            
        elif message_type == "reset_session":
            logger.info(f"Resetting session for {connection_id}")
            self.connections[connection_id]["vad"].reset_state()
            self.connections[connection_id]["audio_buffer"].clear()
            
        elif message_type == "get_stats":
            await self.send_stats(connection_id)
            
        else:
            logger.warning(f"Unknown message type: {message_type}")
    
    async def handle_audio_data(self, connection_id: str, audio_data: bytes):
        """Handle incoming audio data"""
        if connection_id not in self.connections:
            return
        
        conn = self.connections[connection_id]
        
        try:
            # Convert bytes to numpy array (assuming 16-bit PCM)
            audio_array = np.frombuffer(audio_data, dtype=np.int16)
            
            # Update stats
            conn["stats"]["audio_chunks_received"] += 1
            conn["stats"]["total_audio_duration"] += len(audio_array) / self.sample_rate
            
            # Add to audio buffer
            conn["audio_buffer"].add_audio(audio_array)
            
            # Process with VAD
            speech_detected, speech_audio, vad_info = conn["vad"].process_audio_chunk(audio_array)
            
            # Send VAD status
            await self.send_message(connection_id, {
                "type": "vad_status",
                "is_speaking": vad_info["is_speaking"],
                "speech_probability": vad_info.get("speech_probability", 0.0),
                "frame_count": vad_info["frame_count"]
            })
            
            # If speech detected, process it
            if speech_detected and speech_audio is not None:
                await self.process_speech_segment(connection_id, speech_audio)
                
        except Exception as e:
            logger.error(f"Error processing audio data from {connection_id}: {e}")
            conn["stats"]["errors"] += 1
            await self.send_error(connection_id, f"Audio processing error: {str(e)}")
    
    async def process_speech_segment(self, connection_id: str, speech_audio: np.ndarray):
        """Process detected speech segment"""
        if connection_id not in self.connections:
            return
        
        conn = self.connections[connection_id]
        
        if conn["is_processing"]:
            logger.warning(f"Already processing speech for {connection_id}, skipping")
            return
        
        conn["is_processing"] = True
        conn["stats"]["speech_segments_processed"] += 1
        
        try:
            logger.info(f"Processing speech segment for {connection_id}, duration: {len(speech_audio)/self.sample_rate:.2f}s")
            
            # Send processing started message
            await self.send_message(connection_id, {
                "type": "processing_started",
                "audio_duration": len(speech_audio) / self.sample_rate
            })
            
            # Convert audio to base64 for API
            audio_base64 = await self.audio_to_base64(speech_audio)
            
            # Send to OpenS2S model worker
            response_generator = await self.call_model_worker(audio_base64)
            
            # Stream response back to client
            async for response_chunk in response_generator:
                await self.send_message(connection_id, response_chunk)
            
            # Send processing completed message
            await self.send_message(connection_id, {
                "type": "processing_completed"
            })
            
        except Exception as e:
            logger.error(f"Error processing speech for {connection_id}: {e}")
            await self.send_error(connection_id, f"Speech processing error: {str(e)}")
        finally:
            conn["is_processing"] = False
    
    async def audio_to_base64(self, audio_array: np.ndarray) -> str:
        """Convert audio array to base64 encoded WAV"""
        # Create temporary WAV file
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as temp_file:
            # Convert to torch tensor and save
            audio_tensor = torch.from_numpy(audio_array.astype(np.float32) / 32767.0).unsqueeze(0)
            torchaudio.save(temp_file.name, audio_tensor, self.sample_rate)
            
            # Read back as bytes
            with open(temp_file.name, "rb") as f:
                audio_bytes = f.read()
            
            # Clean up
            os.unlink(temp_file.name)
            
            # Encode to base64
            return base64.b64encode(audio_bytes).decode("utf-8")
    
    async def call_model_worker(self, audio_base64: str):
        """Call OpenS2S model worker for speech processing"""
        try:
            # Prepare request payload
            payload = {
                "model": "omnispeech",
                "messages": [
                    {
                        "role": "user",
                        "content": {"audio": audio_base64}
                    }
                ],
                "temperature": 0.2,
                "top_p": 0.8,
                "max_new_tokens": 512
            }
            
            # Make streaming request to model worker
            response = requests.post(
                f"{self.controller_url}/worker_generate_stream",
                headers={"User-Agent": "OpenS2S-Realtime"},
                json=payload,
                stream=True,
                timeout=30
            )
            
            # Process streaming response
            for chunk in response.iter_lines(decode_unicode=False, delimiter=b"\0"):
                if chunk:
                    try:
                        data = json.loads(chunk.decode())
                        if data["error_code"] == 0:
                            yield {
                                "type": "model_response",
                                "text": data["text"],
                                "audio": data.get("audio", ""),
                                "finalize": data.get("finalize", False)
                            }
                        else:
                            yield {
                                "type": "model_error",
                                "error": data["text"],
                                "error_code": data["error_code"]
                            }
                    except json.JSONDecodeError as e:
                        logger.error(f"JSON decode error: {e}")
                        continue
                        
        except Exception as e:
            logger.error(f"Model worker call error: {e}")
            yield {
                "type": "model_error",
                "error": f"Model worker error: {str(e)}",
                "error_code": -1
            }
    
    async def finalize_speech(self, connection_id: str):
        """Finalize any pending speech processing"""
        if connection_id not in self.connections:
            return
        
        conn = self.connections[connection_id]
        
        # Force finalize any pending speech in VAD
        final_speech = conn["vad"].force_finalize_speech()
        if final_speech is not None:
            await self.process_speech_segment(connection_id, final_speech)
    
    async def send_message(self, connection_id: str, message: dict):
        """Send message to client"""
        if connection_id not in self.connections:
            return
        
        try:
            websocket = self.connections[connection_id]["websocket"]
            await websocket.send(json.dumps(message))
        except Exception as e:
            logger.error(f"Error sending message to {connection_id}: {e}")
    
    async def send_error(self, connection_id: str, error_message: str):
        """Send error message to client"""
        await self.send_message(connection_id, {
            "type": "error",
            "message": error_message,
            "timestamp": datetime.now().isoformat()
        })
    
    async def send_stats(self, connection_id: str):
        """Send connection statistics"""
        if connection_id not in self.connections:
            return
        
        conn = self.connections[connection_id]
        stats = conn["stats"].copy()
        stats["connected_duration"] = (datetime.now() - conn["connected_at"]).total_seconds()
        stats["is_processing"] = conn["is_processing"]
        
        await self.send_message(connection_id, {
            "type": "stats",
            "stats": stats
        })
    
    async def cleanup_connection(self, connection_id: str):
        """Clean up connection resources"""
        if connection_id in self.connections:
            conn = self.connections[connection_id]
            
            # Log final stats
            stats = conn["stats"]
            duration = (datetime.now() - conn["connected_at"]).total_seconds()
            
            logger.info(f"Connection {connection_id} cleanup - Duration: {duration:.1f}s, "
                       f"Audio chunks: {stats['audio_chunks_received']}, "
                       f"Speech segments: {stats['speech_segments_processed']}, "
                       f"Errors: {stats['errors']}")
            
            # Finalize any pending speech
            await self.finalize_speech(connection_id)
            
            # Remove from connections
            del self.connections[connection_id]

async def main():
    """Main entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(description="OpenS2S Real-time Streaming Server")
    parser.add_argument("--host", default="0.0.0.0", help="Server host")
    parser.add_argument("--port", type=int, default=8765, help="Server port")
    parser.add_argument("--controller-url", default="http://localhost:21002", 
                       help="OpenS2S controller URL")
    parser.add_argument("--vad-mode", choices=["webrtc", "silero"], default="webrtc",
                       help="VAD mode")
    parser.add_argument("--vad-aggressiveness", type=int, default=2, choices=[0,1,2,3],
                       help="WebRTC VAD aggressiveness")
    
    args = parser.parse_args()
    
    # Create and start server
    server = RealtimeStreamingServer(
        host=args.host,
        port=args.port,
        controller_url=args.controller_url,
        vad_mode=args.vad_mode,
        vad_aggressiveness=args.vad_aggressiveness
    )
    
    try:
        await server.start_server()
    except KeyboardInterrupt:
        logger.info("Server stopped by user")
    except Exception as e:
        logger.error(f"Server error: {e}")

if __name__ == "__main__":
    asyncio.run(main())
