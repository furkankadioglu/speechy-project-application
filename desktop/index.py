#!/usr/bin/env python3
"""Hızlı speech-to-text - Whisper ile sesli not alma"""

import os
import sys
import tempfile
import threading
import numpy as np
import sounddevice as sd
from scipy.io.wavfile import write

# Global model - bir kere yükle, hep kullan
_model = None
_model_lock = threading.Lock()

def get_model():
    """Model'i lazy-load et (sadece ilk kullanımda yükle)"""
    global _model
    if _model is None:
        with _model_lock:
            if _model is None:
                from faster_whisper import WhisperModel
                print("Model yükleniyor (ilk seferde biraz sürer)...")
                os.makedirs("./models", exist_ok=True)
                # base model: hızlı ve yeterince iyi
                _model = WhisperModel(
                    "base",
                    device="cpu",
                    compute_type="int8",
                    download_root="./models",
                    cpu_threads=os.cpu_count() or 4
                )
                print("Model hazır!")
    return _model

def record_until_silence(max_duration=30, silence_threshold=0.01, silence_duration=1.5):
    """Sessizlik algılayana kadar kaydet"""
    sample_rate = 16000
    chunk_size = int(sample_rate * 0.1)  # 100ms chunks

    print("🎤 Konuşun... (sessiz kalınca otomatik durur)")

    chunks = []
    silent_chunks = 0
    max_silent = int(silence_duration / 0.1)
    speaking_started = False

    def callback(indata, frames, time, status):
        nonlocal silent_chunks, speaking_started
        level = np.abs(indata).mean()
        chunks.append(indata.copy())

        if level > silence_threshold:
            speaking_started = True
            silent_chunks = 0
        elif speaking_started:
            silent_chunks += 1

    with sd.InputStream(samplerate=sample_rate, channels=1, dtype='float32',
                        blocksize=chunk_size, callback=callback):
        while True:
            sd.sleep(100)
            if speaking_started and silent_chunks >= max_silent:
                break
            if len(chunks) * 0.1 >= max_duration:
                break

    print("✓ Kayıt tamamlandı")
    return np.concatenate(chunks), sample_rate

def record_fixed(duration=5):
    """Sabit süreli kayıt"""
    sample_rate = 16000
    print(f"🎤 {duration} saniye kayıt...")
    recording = sd.rec(int(duration * sample_rate), samplerate=sample_rate,
                       channels=1, dtype="float32")
    sd.wait()
    print("✓ Kayıt tamamlandı")
    return recording, sample_rate

def transcribe(audio_data, sample_rate):
    """Sesi metne çevir"""
    # Geçici dosyaya kaydet
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        temp_path = f.name

    # Normalize et
    if np.max(np.abs(audio_data)) > 0:
        audio_data = audio_data / np.max(np.abs(audio_data))
    write(temp_path, sample_rate, np.int16(audio_data * 32767))

    try:
        model = get_model()
        segments, _ = model.transcribe(
            temp_path,
            language="tr",
            beam_size=1,      # Hızlı
            vad_filter=True,  # Sessiz kısımları atla
        )
        return " ".join(s.text for s in segments).strip()
    finally:
        os.unlink(temp_path)

def main():
    import argparse
    parser = argparse.ArgumentParser(description="Sesli not - konuş, metne çevir")
    parser.add_argument("-s", "--sure", type=int, help="Sabit kayıt süresi (saniye)")
    parser.add_argument("-d", "--dongu", action="store_true", help="Sürekli dinle")
    args = parser.parse_args()

    # Model'i önceden yükle
    get_model()

    try:
        while True:
            # Kayıt
            if args.sure:
                audio, sr = record_fixed(args.sure)
            else:
                audio, sr = record_until_silence()

            # Transkripsiyon
            text = transcribe(audio, sr)

            if text:
                print(f"\n📝 {text}\n")
            else:
                print("\n(ses algılanamadı)\n")

            if not args.dongu:
                break
            print("-" * 40)

    except KeyboardInterrupt:
        print("\nÇıkış.")

if __name__ == "__main__":
    main()