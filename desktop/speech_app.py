#!/usr/bin/env python3
"""
macOS Speech-to-Text Menubar App
Bir tuşa basılı tut -> kaydet -> bırak -> yazıya çevir -> yapıştır
"""

import os
import sys
import tempfile
import threading
import subprocess
import numpy as np
import sounddevice as sd
from scipy.io.wavfile import write
import rumps
from pynput import keyboard
import json

# Config dosyası
CONFIG_PATH = os.path.expanduser("~/.speech_to_text_config.json")
DEFAULT_HOTKEY = "ctrl"  # Varsayılan tuş

# Global state
_model = None
_model_lock = threading.Lock()
_recording = False
_audio_chunks = []
_sample_rate = 16000


def load_config():
    """Ayarları yükle"""
    if os.path.exists(CONFIG_PATH):
        with open(CONFIG_PATH) as f:
            return json.load(f)
    return {"hotkey": DEFAULT_HOTKEY}


def save_config(config):
    """Ayarları kaydet"""
    with open(CONFIG_PATH, "w") as f:
        json.dump(config, f)


def get_model():
    """Whisper modelini yükle (lazy loading)"""
    global _model
    if _model is None:
        with _model_lock:
            if _model is None:
                from faster_whisper import WhisperModel
                models_dir = os.path.join(os.path.dirname(__file__), "models")
                os.makedirs(models_dir, exist_ok=True)
                _model = WhisperModel(
                    "base",
                    device="cpu",
                    compute_type="int8",
                    download_root=models_dir,
                    cpu_threads=os.cpu_count() or 4
                )
    return _model


def transcribe_audio(audio_data, sample_rate):
    """Sesi yazıya çevir"""
    if len(audio_data) == 0:
        return ""

    # Geçici dosyaya kaydet
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        temp_path = f.name

    # Normalize
    audio_data = np.array(audio_data)
    if np.max(np.abs(audio_data)) > 0:
        audio_data = audio_data / np.max(np.abs(audio_data))
    write(temp_path, sample_rate, np.int16(audio_data * 32767))

    try:
        model = get_model()
        segments, _ = model.transcribe(
            temp_path,
            language="tr",
            beam_size=1,
            vad_filter=True,
        )
        return " ".join(s.text for s in segments).strip()
    finally:
        os.unlink(temp_path)


def paste_text(text):
    """Metni clipboard'a kopyala ve yapıştır"""
    if not text:
        return

    # Clipboard'a kopyala
    process = subprocess.Popen(['pbcopy'], stdin=subprocess.PIPE)
    process.communicate(text.encode('utf-8'))

    # Cmd+V ile yapıştır
    subprocess.run([
        'osascript', '-e',
        'tell application "System Events" to keystroke "v" using command down'
    ])


class SpeechToTextApp(rumps.App):
    def __init__(self):
        super().__init__("🎤", quit_button=None)

        self.config = load_config()
        self.is_recording = False
        self.audio_chunks = []
        self.stream = None

        # Menu items
        self.menu = [
            rumps.MenuItem("Durum: Hazır", callback=None),
            None,  # Separator
            rumps.MenuItem("Tuş Ayarla", callback=self.show_hotkey_menu),
            rumps.MenuItem("Model Yükle", callback=self.preload_model),
            None,
            rumps.MenuItem("Çıkış", callback=self.quit_app),
        ]

        # Hotkey listener başlat
        self.start_hotkey_listener()

        # Model'i arka planda yükle
        threading.Thread(target=self._preload_model_bg, daemon=True).start()

    def _preload_model_bg(self):
        """Model'i arka planda yükle"""
        self.menu["Durum: Hazır"].title = "Durum: Model yükleniyor..."
        self.title = "⏳"
        get_model()
        self.menu["Durum: Hazır"].title = f"Durum: Hazır ({self.config['hotkey']} tuşu)"
        self.title = "🎤"

    @rumps.clicked("Model Yükle")
    def preload_model(self, _):
        threading.Thread(target=self._preload_model_bg, daemon=True).start()

    def show_hotkey_menu(self, _):
        """Hotkey seçim menüsü"""
        keys = ["ctrl", "alt", "shift", "cmd", "f1", "f2", "f3", "f4", "f5", "f6"]

        response = rumps.Window(
            message=f"Hangi tuşu kullanmak istiyorsunuz?\n\nMevcut seçenekler:\n{', '.join(keys)}\n\nŞu anki: {self.config['hotkey']}",
            title="Tuş Ayarla",
            default_text=self.config['hotkey'],
            ok="Kaydet",
            cancel="İptal"
        ).run()

        if response.clicked and response.text.lower() in keys:
            self.config['hotkey'] = response.text.lower()
            save_config(self.config)
            self.menu["Durum: Hazır"].title = f"Durum: Hazır ({self.config['hotkey']} tuşu)"
            # Listener'ı yeniden başlat
            self.start_hotkey_listener()
            rumps.notification("Speech to Text", "", f"Tuş değiştirildi: {self.config['hotkey']}")

    def start_hotkey_listener(self):
        """Global hotkey listener başlat"""
        hotkey = self.config['hotkey']

        # Key mapping
        key_map = {
            'ctrl': keyboard.Key.ctrl,
            'alt': keyboard.Key.alt,
            'shift': keyboard.Key.shift,
            'cmd': keyboard.Key.cmd,
            'f1': keyboard.Key.f1,
            'f2': keyboard.Key.f2,
            'f3': keyboard.Key.f3,
            'f4': keyboard.Key.f4,
            'f5': keyboard.Key.f5,
            'f6': keyboard.Key.f6,
        }

        self.trigger_key = key_map.get(hotkey, keyboard.Key.ctrl)

        def on_press(key):
            if key == self.trigger_key and not self.is_recording:
                self.start_recording()

        def on_release(key):
            if key == self.trigger_key and self.is_recording:
                self.stop_recording()

        # Önceki listener'ı durdur
        if hasattr(self, 'key_listener') and self.key_listener:
            self.key_listener.stop()

        self.key_listener = keyboard.Listener(on_press=on_press, on_release=on_release)
        self.key_listener.start()

    def start_recording(self):
        """Kayda başla"""
        self.is_recording = True
        self.audio_chunks = []
        self.title = "🔴"
        self.menu["Durum: Hazır"].title = "Durum: Kaydediliyor..."

        def audio_callback(indata, frames, time, status):
            if self.is_recording:
                self.audio_chunks.append(indata.copy())

        self.stream = sd.InputStream(
            samplerate=_sample_rate,
            channels=1,
            dtype='float32',
            blocksize=1024,
            callback=audio_callback
        )
        self.stream.start()

    def stop_recording(self):
        """Kaydı durdur ve işle"""
        self.is_recording = False
        self.title = "⏳"
        self.menu["Durum: Hazır"].title = "Durum: Yazıya çevriliyor..."

        if self.stream:
            self.stream.stop()
            self.stream.close()
            self.stream = None

        # Arka planda işle
        audio_data = np.concatenate(self.audio_chunks) if self.audio_chunks else np.array([])
        threading.Thread(target=self._process_audio, args=(audio_data,), daemon=True).start()

    def _process_audio(self, audio_data):
        """Sesi işle ve yapıştır"""
        try:
            if len(audio_data) < _sample_rate * 0.3:  # 300ms'den kısa
                self.title = "🎤"
                self.menu["Durum: Hazır"].title = f"Durum: Hazır ({self.config['hotkey']} tuşu)"
                return

            text = transcribe_audio(audio_data, _sample_rate)

            if text:
                paste_text(text)
                rumps.notification("Speech to Text", "", text[:50] + "..." if len(text) > 50 else text)

        except Exception as e:
            rumps.notification("Hata", "", str(e))
        finally:
            self.title = "🎤"
            self.menu["Durum: Hazır"].title = f"Durum: Hazır ({self.config['hotkey']} tuşu)"

    def quit_app(self, _):
        """Uygulamayı kapat"""
        if hasattr(self, 'key_listener'):
            self.key_listener.stop()
        rumps.quit_application()


if __name__ == "__main__":
    # Accessibility izni kontrolü
    print("""
╔════════════════════════════════════════════════════════════╗
║  Speech to Text - macOS Menubar App                        ║
╠════════════════════════════════════════════════════════════╣
║  İlk kullanımda şu izinleri vermeniz gerekiyor:           ║
║                                                            ║
║  1. System Preferences > Security & Privacy > Privacy      ║
║     > Accessibility > Terminal (veya iTerm/VS Code)        ║
║                                                            ║
║  2. System Preferences > Security & Privacy > Privacy      ║
║     > Microphone > Terminal (veya iTerm/VS Code)           ║
║                                                            ║
║  Varsayılan tuş: CTRL (basılı tut = kaydet, bırak = yaz)  ║
╚════════════════════════════════════════════════════════════╝
""")

    app = SpeechToTextApp()
    app.run()
