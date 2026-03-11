# Transcription API - Speech-to-Text Web Service

## Overview
A REST API that accepts audio files and returns transcribed text, powered by Whisper (faster-whisper with int8 quantization).

## Tech Stack
- **Framework:** Python 3.11 + FastAPI + Uvicorn
- **ML Engine:** faster-whisper 1.1.0 (CTranslate2 backend)
- **Model:** Whisper Small (int8 quantized, ~500MB RAM)
- **Server:** Debian 12, systemd service on port 3002
- **Proxy:** Nginx reverse proxy at /api/transcribe

## Endpoint

### POST /api/transcribe
- **Auth:** `X-API-Key` header (or `api_key` query param)
- **Body:** multipart/form-data
  - `audio` (file): Audio file (wav, mp3, m4a, webm, ogg, flac, opus, aac, mp4)
  - `language` (string): Language code or "auto" for detection
- **Response:**
  ```json
  {
    "text": "Transcribed text here",
    "language": "en",
    "language_probability": 0.98,
    "duration": 3.39,
    "processing_time": 19.31
  }
  ```

### GET /health
- No auth required
- Returns model status

## Supported Languages
auto, en, tr, de, fr, es, it, pt, nl, pl, ru, ja, ko, zh, ar, hi, sv, da, fi, no, uk, cs, el, hu, ro, bg, hr, sk, sl

## Deployment
- **Location:** `/Domains/speechy.frkn.com.tr/transcription-api/`
- **Service:** `systemctl restart speechy-api`
- **Logs:** `journalctl -u speechy-api -f`

## Files
- `web-api/main.py` - FastAPI application
- `web-api/requirements.txt` - Python dependencies
- `web-api/.env.example` - Environment variables template
