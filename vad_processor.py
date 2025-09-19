"""
Voice Activity Detection (VAD) processor for real-time audio streaming
Supports WebRTC VAD and Silero VAD for robust speech detection
"""

import numpy as np
import torch
import webrtcvad
import logging
from typing import Optional, Tuple, List
from collections import deque
import torchaudio

logger = logging.getLogger(__name__)

class VADProcessor:
    """
    Voice Activity Detection processor with multiple VAD backends
    """
    
    def __init__(
        self,
        vad_mode: str = "webrtc",  # "webrtc" or "silero"
        aggressiveness: int = 2,   # WebRTC VAD aggressiveness (0-3)
        sample_rate: int = 16000,
        frame_duration: int = 30,  # ms
        speech_threshold: float = 0.5,  # Silero VAD threshold
        min_speech_duration: float = 0.3,  # seconds
        min_silence_duration: float = 0.5,  # seconds
        speech_pad_ms: int = 300,  # padding around speech
    ):
        self.vad_mode = vad_mode
        self.sample_rate = sample_rate
        self.frame_duration = frame_duration
        self.frame_size = int(sample_rate * frame_duration / 1000)
        self.speech_threshold = speech_threshold
        self.min_speech_duration = min_speech_duration
        self.min_silence_duration = min_silence_duration
        self.speech_pad_samples = int(speech_pad_ms * sample_rate / 1000)
        
        # Initialize VAD
        if vad_mode == "webrtc":
            self.vad = webrtcvad.Vad(aggressiveness)
            logger.info(f"Initialized WebRTC VAD with aggressiveness {aggressiveness}")
        elif vad_mode == "silero":
            self._init_silero_vad()
        else:
            raise ValueError(f"Unsupported VAD mode: {vad_mode}")
        
        # State tracking
        self.reset_state()
    
    def _init_silero_vad(self):
        """Initialize Silero VAD model"""
        try:
            self.silero_model, _ = torch.hub.load(
                repo_or_dir='snakers4/silero-vad',
                model='silero_vad',
                force_reload=False,
                onnx=False
            )
            self.silero_model.eval()
            logger.info("Initialized Silero VAD")
        except Exception as e:
            logger.error(f"Failed to initialize Silero VAD: {e}")
            raise
    
    def reset_state(self):
        """Reset VAD state"""
        self.is_speaking = False
        self.speech_frames = deque()
        self.silence_frames = deque()
        self.current_speech = []
        self.speech_start_time = None
        self.silence_start_time = None
        self.frame_count = 0
        
    def process_audio_chunk(self, audio_chunk: np.ndarray) -> Tuple[bool, Optional[np.ndarray], dict]:
        """
        Process audio chunk and detect speech activity
        
        Args:
            audio_chunk: Audio data as numpy array (16kHz, mono)
            
        Returns:
            Tuple of (is_speech_detected, speech_audio, vad_info)
        """
        # Ensure audio is in correct format
        if audio_chunk.dtype != np.int16:
            audio_chunk = (audio_chunk * 32767).astype(np.int16)
        
        # Process in frames
        speech_detected = False
        speech_audio = None
        vad_info = {
            "is_speaking": self.is_speaking,
            "speech_probability": 0.0,
            "frame_count": self.frame_count
        }
        
        # Split audio into frames
        frames = self._split_into_frames(audio_chunk)
        
        for frame in frames:
            self.frame_count += 1
            
            # Run VAD on frame
            is_speech = self._detect_speech_in_frame(frame)
            
            if self.vad_mode == "silero":
                # Get speech probability for Silero VAD
                vad_info["speech_probability"] = self._get_silero_probability(frame)
            
            # Update state machine
            speech_result = self._update_speech_state(frame, is_speech)
            
            if speech_result is not None:
                speech_detected = True
                speech_audio = speech_result
                break
        
        vad_info["is_speaking"] = self.is_speaking
        return speech_detected, speech_audio, vad_info
    
    def _split_into_frames(self, audio_chunk: np.ndarray) -> List[np.ndarray]:
        """Split audio chunk into VAD frames"""
        frames = []
        for i in range(0, len(audio_chunk), self.frame_size):
            frame = audio_chunk[i:i + self.frame_size]
            if len(frame) == self.frame_size:
                frames.append(frame)
        return frames
    
    def _detect_speech_in_frame(self, frame: np.ndarray) -> bool:
        """Detect speech in a single frame"""
        if self.vad_mode == "webrtc":
            return self.vad.is_speech(frame.tobytes(), self.sample_rate)
        elif self.vad_mode == "silero":
            prob = self._get_silero_probability(frame)
            return prob > self.speech_threshold
        return False
    
    def _get_silero_probability(self, frame: np.ndarray) -> float:
        """Get speech probability from Silero VAD"""
        try:
            # Convert to float32 and normalize
            audio_float = frame.astype(np.float32) / 32767.0
            audio_tensor = torch.from_numpy(audio_float).unsqueeze(0)
            
            with torch.no_grad():
                speech_prob = self.silero_model(audio_tensor, self.sample_rate).item()
            
            return speech_prob
        except Exception as e:
            logger.warning(f"Silero VAD error: {e}")
            return 0.0
    
    def _update_speech_state(self, frame: np.ndarray, is_speech: bool) -> Optional[np.ndarray]:
        """Update speech state machine and return complete speech if detected"""
        current_time = self.frame_count * self.frame_duration / 1000.0
        
        if is_speech:
            # Add frame to current speech
            self.current_speech.append(frame)
            
            if not self.is_speaking:
                # Start of speech
                self.is_speaking = True
                self.speech_start_time = current_time
                self.silence_start_time = None
                logger.debug(f"Speech started at {current_time:.2f}s")
        else:
            # Silence frame
            if self.is_speaking:
                # We were speaking, now silence
                if self.silence_start_time is None:
                    self.silence_start_time = current_time
                
                silence_duration = current_time - self.silence_start_time
                
                if silence_duration >= self.min_silence_duration:
                    # End of speech detected
                    speech_duration = current_time - self.speech_start_time
                    
                    if speech_duration >= self.min_speech_duration:
                        # Valid speech segment
                        speech_audio = self._finalize_speech_segment()
                        logger.debug(f"Speech ended at {current_time:.2f}s, duration: {speech_duration:.2f}s")
                        return speech_audio
                    else:
                        # Too short, discard
                        logger.debug(f"Speech too short ({speech_duration:.2f}s), discarding")
                        self._reset_current_speech()
                else:
                    # Still in silence grace period, add frame to speech
                    self.current_speech.append(frame)
        
        return None
    
    def _finalize_speech_segment(self) -> np.ndarray:
        """Finalize and return the current speech segment"""
        if not self.current_speech:
            return np.array([], dtype=np.int16)
        
        # Concatenate all speech frames
        speech_audio = np.concatenate(self.current_speech)
        
        # Add padding if needed
        if self.speech_pad_samples > 0:
            pad_start = np.zeros(self.speech_pad_samples, dtype=np.int16)
            pad_end = np.zeros(self.speech_pad_samples, dtype=np.int16)
            speech_audio = np.concatenate([pad_start, speech_audio, pad_end])
        
        self._reset_current_speech()
        return speech_audio
    
    def _reset_current_speech(self):
        """Reset current speech state"""
        self.is_speaking = False
        self.current_speech = []
        self.speech_start_time = None
        self.silence_start_time = None
    
    def force_finalize_speech(self) -> Optional[np.ndarray]:
        """Force finalize current speech (e.g., on connection close)"""
        if self.current_speech and self.is_speaking:
            return self._finalize_speech_segment()
        return None

class AudioBuffer:
    """
    Circular audio buffer for real-time processing
    """
    
    def __init__(self, max_duration: float = 10.0, sample_rate: int = 16000):
        self.max_samples = int(max_duration * sample_rate)
        self.sample_rate = sample_rate
        self.buffer = np.zeros(self.max_samples, dtype=np.int16)
        self.write_pos = 0
        self.available_samples = 0
    
    def add_audio(self, audio_data: np.ndarray):
        """Add audio data to the buffer"""
        audio_data = audio_data.astype(np.int16)
        samples_to_add = len(audio_data)
        
        if samples_to_add > self.max_samples:
            # If audio is longer than buffer, take the last part
            audio_data = audio_data[-self.max_samples:]
            samples_to_add = self.max_samples
        
        # Handle circular buffer wrapping
        if self.write_pos + samples_to_add <= self.max_samples:
            self.buffer[self.write_pos:self.write_pos + samples_to_add] = audio_data
        else:
            # Wrap around
            first_part = self.max_samples - self.write_pos
            self.buffer[self.write_pos:] = audio_data[:first_part]
            self.buffer[:samples_to_add - first_part] = audio_data[first_part:]
        
        self.write_pos = (self.write_pos + samples_to_add) % self.max_samples
        self.available_samples = min(self.available_samples + samples_to_add, self.max_samples)
    
    def get_audio(self, duration: float) -> np.ndarray:
        """Get audio data from buffer"""
        samples_needed = int(duration * self.sample_rate)
        samples_needed = min(samples_needed, self.available_samples)
        
        if samples_needed == 0:
            return np.array([], dtype=np.int16)
        
        # Calculate read position
        read_pos = (self.write_pos - samples_needed) % self.max_samples
        
        if read_pos + samples_needed <= self.max_samples:
            return self.buffer[read_pos:read_pos + samples_needed].copy()
        else:
            # Wrap around
            first_part = self.max_samples - read_pos
            result = np.concatenate([
                self.buffer[read_pos:],
                self.buffer[:samples_needed - first_part]
            ])
            return result
    
    def clear(self):
        """Clear the buffer"""
        self.buffer.fill(0)
        self.write_pos = 0
        self.available_samples = 0
