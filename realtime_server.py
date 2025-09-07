# FILE: realtime_server.py
import asyncio
import base64
import json
import logging
from io import BytesIO

import requests
import soundfile as sf
import uvicorn
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from vad import VAD

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI()
app.mount("/static", StaticFiles(directory="static"), name="static")

vad = VAD()

CONTROLLER_URL = "http://localhost:21001"
MODEL_WORKER_URL = "http://localhost:21002" # Directly calling worker for simplicity

class ConnectionManager:
    def __init__(self):
        self.active_connections: list[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)
        logger.info(f"New client connected: {websocket.client}")

    def disconnect(self, websocket: WebSocket):
        self.active_connections.remove(websocket)
        logger.info(f"Client disconnected: {websocket.client}")

    async def send_json(self, data: dict, websocket: WebSocket):
        await websocket.send_json(data)

manager = ConnectionManager()

async def audio_processing_task(websocket: WebSocket):
    """Handles receiving audio, VAD, and sending to the model worker."""
    audio_buffer = bytearray()
    is_speaking = False
    speech_started = False
    min_speech_duration_ms = 250  # Minimum duration of speech to be considered valid
    max_silence_duration_ms = 700  # Maximum silence duration to trigger end of speech

    min_speech_samples = 16 * min_speech_duration_ms
    max_silence_samples = 16 * max_silence_duration_ms
    silence_counter = 0

    try:
        while True:
            audio_chunk = await websocket.receive_bytes()
            confidence = vad(audio_chunk)

            if confidence > 0.5:
                is_speaking = True
                silence_counter = 0
                if not speech_started:
                    speech_started = True
                    logger.info("Speech started.")
                    await manager.send_json({"status": "speech_started"}, websocket)
            else:
                if is_speaking:
                    silence_counter += len(audio_chunk) // 2  # 16-bit samples
                    if silence_counter > max_silence_samples:
                        is_speaking = False
                        speech_started = False
                        logger.info("Speech ended.")
                        await manager.send_json({"status": "speech_ended"}, websocket)

            if speech_started:
                audio_buffer.extend(audio_chunk)

            if not is_speaking and len(audio_buffer) > min_speech_samples:
                logger.info(f"Processing audio buffer of size {len(audio_buffer)}")
                await process_and_stream_response(audio_buffer, websocket)
                audio_buffer.clear()
                vad.reset_states()

    except WebSocketDisconnect:
        manager.disconnect(websocket)
    except Exception as e:
        logger.error(f"Error in audio processing task: {e}")
        manager.disconnect(websocket)

async def process_and_stream_response(buffer: bytearray, websocket: WebSocket):
    """Converts audio buffer to WAV, sends to model worker, and streams response."""
    # Convert raw PCM to WAV in memory
    wav_buffer = BytesIO()
    with sf.SoundFile(wav_buffer, 'w', samplerate=16000, channels=1, subtype='PCM_16', format='WAV') as f:
        f.write(np.frombuffer(buffer, dtype=np.int16))
    wav_buffer.seek(0)
    
    audio_b64 = base64.b64encode(wav_buffer.read()).decode("utf-8")

    payload = {
        "model": "omnispeech",
        "messages": [{"role": "user", "content": [{"audio": audio_b64}]}],
        "temperature": 0.2,
        "top_p": 0.8,
        "max_new_tokens": 512,
    }

    try:
        response = requests.post(
            f"{MODEL_WORKER_URL}/worker_generate_stream",
            json=payload,
            stream=True,
            timeout=120
        )
        response.raise_for_status()

        for chunk in response.iter_lines(decode_unicode=False, delimiter=b"\0"):
            if chunk:
                data = json.loads(chunk.decode("utf-8"))
                await manager.send_json(data, websocket)

    except requests.RequestException as e:
        logger.error(f"Error calling model worker: {e}")
        await manager.send_json({"error": "Failed to get response from model."}, websocket)

@app.get("/")
async def get():
    return FileResponse("static/index.html")

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    asyncio.create_task(audio_processing_task(websocket))

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
