# FILE: vad.py
import torch
import numpy as np

class VAD:
    def __init__(self):
        self.model, self.utils = torch.hub.load(
            repo_or_dir='snakers4/silero-vad',
            model='silero_vad',
            force_reload=False
        )
        self.reset_states()

    def reset_states(self):
        self.model.reset_states()

    def __call__(self, audio_chunk):
        audio_int16 = np.frombuffer(audio_chunk, np.int16)
        audio_float32 = self.int2float(audio_int16)
        confidence = self.model(torch.from_numpy(audio_float32), 16000).item()
        return confidence

    @staticmethod
    def int2float(sound):
        abs_max = np.abs(sound).max()
        if abs_max > 0:
            sound = sound.astype('float32') / abs_max
        return sound
