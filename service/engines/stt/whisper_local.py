import asyncio
import numpy as np
from .base import STTEngine


def _best_device() -> tuple[str, str]:
    """Return (device, compute_type) using CUDA float16 if available, else CPU int8."""
    try:
        import ctranslate2
        if ctranslate2.get_cuda_device_count() > 0:
            return "cuda", "float16"
    except Exception:
        pass
    return "cpu", "int8"


class LocalWhisperEngine(STTEngine):
    def __init__(self, model_size: str = "small", compute_type: str = "int8_float16", beam_size: int = 3):
        # Import lazily so the service starts even if faster-whisper isn't installed
        from faster_whisper import WhisperModel

        device, fallback_compute_type = _best_device()
        compute_type = compute_type if device == "cuda" else fallback_compute_type
        self._beam_size = max(1, beam_size)
        print(
            f"[WhisperLocal] loading model '{model_size}' on {device} ({compute_type}) "
            "(first run downloads from Hugging Face, then caches locally)..."
        )
        # GPU doesn't benefit from multiple CPU workers
        self._model = WhisperModel(model_size, device=device, compute_type=compute_type,
                                   num_workers=1 if device == "cuda" else 2)
        self._device = device
        print(f"[WhisperLocal] model '{model_size}' ready on {device}")

    async def transcribe(
        self, audio_bytes: bytes, sample_rate: int, language: str | None = None,
        prompt: str | None = None,
    ) -> tuple[str, str]:
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(None, self._run, audio_bytes, sample_rate, language, prompt)

    def _run(self, audio_bytes: bytes, sample_rate: int, language: str | None = None,
             prompt: str | None = None) -> tuple[str, str]:
        audio = np.frombuffer(audio_bytes, dtype=np.int16).astype(np.float32) / 32768.0
        segments, info = self._model.transcribe(
            audio,
            language=language,
            initial_prompt=prompt or "",
            beam_size=self._beam_size if self._device == "cuda" else 1,
            vad_filter=True,
            # 更快把自然停顿识别为句间边界，同时在边界两侧保留少量语音，
            # 避免固定窗口把日语助词或句尾吞掉。
            vad_parameters={
                "min_silence_duration_ms": 350,
                "speech_pad_ms": 220,
            },
            condition_on_previous_text=False,
            no_speech_threshold=0.8,
            repetition_penalty=1.3,
            compression_ratio_threshold=2.0,
        )
        text = _strip_repetitions(" ".join(seg.text for seg in segments).strip())
        return text, info.language


def _strip_repetitions(text: str) -> str:
    """Remove repeated phrase loops that Whisper hallucinates on noisy audio.
    Finds the first repeating block of 3+ words and truncates at it."""
    words = text.split()
    n = len(words)
    for window in range(n // 2, 2, -1):
        for start in range(n - window * 2 + 1):
            if words[start:start + window] == words[start + window:start + window * 2]:
                return " ".join(words[:start + window]).strip()
    return text
