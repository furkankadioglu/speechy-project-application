"""Speechy Transcription API - Speech-to-Text web service powered by Whisper."""

import os
import time
import tempfile
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, UploadFile, File, Form, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from faster_whisper import WhisperModel

# --- Configuration ---
MODEL_SIZE = os.getenv("WHISPER_MODEL", "small")
COMPUTE_TYPE = os.getenv("WHISPER_COMPUTE", "int8")
CPU_THREADS = int(os.getenv("CPU_THREADS", "2"))
MAX_FILE_SIZE = int(os.getenv("MAX_FILE_SIZE_MB", "25")) * 1024 * 1024  # 25MB default
API_KEY = os.getenv("SPEECHY_API_KEY", "")  # Empty = no auth required
PORT = int(os.getenv("PORT", "3002"))

ALLOWED_EXTENSIONS = {".wav", ".mp3", ".m4a", ".webm", ".ogg", ".flac", ".mp4", ".opus", ".aac"}

SUPPORTED_LANGUAGES = {
    "auto", "en", "tr", "de", "fr", "es", "it", "pt", "nl", "pl", "ru",
    "ja", "ko", "zh", "ar", "hi", "sv", "da", "fi", "no", "uk", "cs",
    "el", "hu", "ro", "bg", "hr", "sk", "sl",
}

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("speechy-api")

# --- Model loading ---
model: WhisperModel = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global model
    logger.info(f"Loading Whisper model: {MODEL_SIZE} (compute: {COMPUTE_TYPE}, threads: {CPU_THREADS})")
    start = time.time()
    model = WhisperModel(
        MODEL_SIZE,
        device="cpu",
        compute_type=COMPUTE_TYPE,
        cpu_threads=CPU_THREADS,
        num_workers=1,
    )
    logger.info(f"Model loaded in {time.time() - start:.1f}s")
    yield
    logger.info("Shutting down")


# --- App ---
app = FastAPI(
    title="Speechy Transcription API",
    description="Speech-to-Text API powered by Whisper",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["POST", "GET", "OPTIONS"],
    allow_headers=["*"],
)


# --- Auth middleware ---
@app.middleware("http")
async def check_api_key(request: Request, call_next):
    # Skip auth for health/docs endpoints
    if request.url.path in ("/", "/health", "/docs", "/openapi.json"):
        return await call_next(request)

    # Skip if no API key configured
    if not API_KEY:
        return await call_next(request)

    key = request.headers.get("X-API-Key") or request.query_params.get("api_key")
    if key != API_KEY:
        return JSONResponse(status_code=401, content={"error": "Invalid or missing API key"})

    return await call_next(request)


# --- Endpoints ---
@app.get("/")
async def root():
    return {"service": "Speechy Transcription API", "version": "1.0.0", "status": "running"}


@app.get("/health")
async def health():
    return {"status": "ok", "model": MODEL_SIZE, "compute": COMPUTE_TYPE}


@app.post("/api/transcribe")
async def transcribe(
    audio: UploadFile = File(..., description="Audio file (wav, mp3, m4a, webm, ogg, flac, opus)"),
    language: str = Form(default="auto", description="Language code (e.g. 'en', 'tr', 'de') or 'auto' for detection"),
):
    # Validate language
    if language not in SUPPORTED_LANGUAGES:
        raise HTTPException(status_code=400, detail=f"Unsupported language: {language}. Supported: {sorted(SUPPORTED_LANGUAGES)}")

    # Validate file extension
    ext = os.path.splitext(audio.filename or "")[1].lower()
    if ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(status_code=400, detail=f"Unsupported file type: {ext}. Allowed: {sorted(ALLOWED_EXTENSIONS)}")

    # Read and validate file size
    content = await audio.read()
    if len(content) > MAX_FILE_SIZE:
        raise HTTPException(status_code=413, detail=f"File too large. Max: {MAX_FILE_SIZE // (1024*1024)}MB")

    if len(content) == 0:
        raise HTTPException(status_code=400, detail="Empty audio file")

    # Save to temp file
    tmp_path = None
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=ext) as tmp:
            tmp.write(content)
            tmp_path = tmp.name

        # Transcribe with max performance settings
        start = time.time()
        lang_param = None if language == "auto" else language
        segments, info = model.transcribe(
            tmp_path,
            language=lang_param,
            beam_size=1,                       # Greedy decoding (fastest)
            best_of=1,                         # No sampling alternatives
            temperature=0.0,                   # Deterministic output
            condition_on_previous_text=False,   # Skip context conditioning
            vad_filter=True,                   # Skip silence segments
            vad_parameters=dict(
                min_silence_duration_ms=300,    # Aggressive silence detection
                speech_pad_ms=100,
            ),
            log_prob_threshold=-1.0,           # Accept all segments
            no_speech_threshold=0.45,          # Faster no-speech filtering
        )

        # Collect segments
        text_parts = []
        for segment in segments:
            text_parts.append(segment.text.strip())

        text = " ".join(text_parts).strip()
        elapsed = time.time() - start

        logger.info(f"Transcribed {len(content)/1024:.0f}KB audio in {elapsed:.1f}s | lang={info.language} | {len(text)} chars")

        return {
            "text": text,
            "language": info.language,
            "language_probability": round(info.language_probability, 3),
            "duration": round(info.duration, 2),
            "processing_time": round(elapsed, 2),
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Transcription failed: {e}")
        raise HTTPException(status_code=500, detail="Transcription failed. Please try again.")
    finally:
        if tmp_path and os.path.exists(tmp_path):
            os.unlink(tmp_path)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=PORT)
