#!/usr/bin/env python3
"""Minimal loopback Moonshine STT HTTP server for Local Wispr.

The default backend is Moonshine Voice, the official optimized ONNX/C++
runtime. A Hugging Face Transformers backend remains available for checkpoint
experiments, but it is not the fast path.
"""

from __future__ import annotations

import argparse
import json
import os
import socket
import sys
import tempfile
import threading
import time
import traceback
import uuid
from email.parser import BytesParser
from email.policy import default as email_policy
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Optional, Protocol
from urllib.parse import urlparse

DEFAULT_TRANSFORMERS_MODEL = "UsefulSensors/moonshine-streaming-small"
DEFAULT_VOICE_LANGUAGE = "en"
DEFAULT_VOICE_ARCH = "medium-streaming"
LOOPBACK_HOSTS = {"127.0.0.1", "localhost", "::1"}


def env_flag(name: str, default: bool = False) -> bool:
    value = os.environ.get(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def infer_device() -> str:
    try:
        import torch

        if torch.backends.mps.is_available():
            return "mps"
        if torch.cuda.is_available():
            return "cuda"
    except Exception:
        pass
    return "cpu"


def transcript_to_text(transcript: Any) -> str:
    lines = getattr(transcript, "lines", [])
    text = " ".join(getattr(line, "text", "") for line in lines)
    return " ".join(text.strip().split())


def arch_from_model_name(model: str) -> str:
    normalized = model.strip().lower().replace("_", "-")
    if "medium-streaming" in normalized:
        return "medium-streaming"
    if "small-streaming" in normalized:
        return "small-streaming"
    if "base-streaming" in normalized:
        return "base-streaming"
    if "tiny-streaming" in normalized or "streaming-tiny" in normalized:
        return "tiny-streaming"
    if normalized.endswith("base") or "moonshine-base" in normalized:
        return "base"
    if normalized.endswith("tiny") or "moonshine-tiny" in normalized:
        return "tiny"
    return DEFAULT_VOICE_ARCH


class Runtime(Protocol):
    model: str
    backend: str

    def load(self) -> Any:
        ...

    def transcribe(self, audio_path: Path) -> str:
        ...


class MoonshineVoiceRuntime:
    backend = "moonshine-voice"

    def __init__(self, language: str, model_arch: str, cache_root: Optional[Path] = None) -> None:
        self.language = language
        self.model_arch = model_arch
        self.cache_root = cache_root
        self.model = f"{language}/{model_arch}"
        self._transcriber: Any = None
        self._load_wav_file: Any = None

    def load(self) -> Any:
        if self._transcriber is not None:
            return self._transcriber

        from moonshine_voice import Transcriber, get_model_for_language, string_to_model_arch, load_wav_file

        self._force_update_flag = Transcriber.MOONSHINE_FLAG_FORCE_UPDATE
        arch = string_to_model_arch(self.model_arch)
        print(
            f"Loading Moonshine Voice model language={self.language} arch={self.model_arch}",
            flush=True,
        )
        model_path, model_arch = get_model_for_language(
            self.language,
            arch,
            cache_root=self.cache_root,
        )
        self._transcriber = Transcriber(model_path, model_arch)
        self._load_wav_file = load_wav_file
        self.model = f"{self.language}/{self.model_arch}"
        print(f"Moonshine Voice model loaded from {model_path}", flush=True)
        return self._transcriber

    def transcribe(self, audio_path: Path) -> str:
        transcriber = self.load()
        audio_data, sample_rate = self._load_wav_file(audio_path)
        transcript = transcriber.transcribe_without_streaming(audio_data, sample_rate)
        return transcript_to_text(transcript)

    def create_session(self, update_interval: float) -> "MoonshineVoiceStreamingSession":
        transcriber = self.load()
        stream = transcriber.create_stream(update_interval=update_interval)
        stream.start()
        return MoonshineVoiceStreamingSession(
            stream=stream,
            update_interval=update_interval,
            force_update_flag=getattr(self, "_force_update_flag", 1),
        )


class MoonshineVoiceStreamingSession:
    def __init__(self, stream: Any, update_interval: float, force_update_flag: int = 1) -> None:
        self.stream = stream
        self.update_interval = max(0.02, update_interval)
        self.force_update_flag = force_update_flag
        self.lock = threading.Lock()
        self.last_update = 0.0
        self.latest_text = ""
        self.closed = False

    def add_audio(self, samples: list[float], sample_rate: int) -> str:
        if not samples:
            return self.latest_text

        with self.lock:
            if self.closed:
                raise RuntimeError("streaming session is closed")

            self.stream.add_audio(samples, sample_rate)
            now = time.perf_counter()
            if now - self.last_update >= self.update_interval:
                transcript = self.stream.update_transcription(self.force_update_flag)
                self.latest_text = transcript_to_text(transcript)
                self.last_update = now
            return self.latest_text

    def finish(self) -> str:
        with self.lock:
            if self.closed:
                return self.latest_text

            try:
                self.stream.stop()
                transcript = self.stream.update_transcription(self.force_update_flag)
                self.latest_text = transcript_to_text(transcript)
            finally:
                self.closed = True
                self.stream.close()
            return self.latest_text

    def cancel(self) -> None:
        with self.lock:
            if self.closed:
                return

            self.closed = True
            try:
                self.stream.stop()
            finally:
                self.stream.close()


def resolve_torch_dtype(torch: Any, dtype_name: str, device: str) -> Optional[Any]:
    dtype_name = dtype_name.strip().lower()
    if dtype_name in {"", "none", "default"}:
        return None
    if dtype_name == "auto":
        return torch.float16 if device in {"mps", "cuda"} else None
    if dtype_name in {"float16", "fp16", "half"}:
        return torch.float16
    if dtype_name in {"bfloat16", "bf16"}:
        return torch.bfloat16
    if dtype_name in {"float32", "fp32"}:
        return torch.float32
    raise ValueError(f"Unsupported dtype {dtype_name!r}")


class TransformersMoonshineRuntime:
    backend = "transformers"

    def __init__(
        self,
        model: str,
        device: str,
        torch_dtype: str,
        max_new_tokens: int,
        attn_implementation: Optional[str],
    ) -> None:
        self.model = model
        self.device = device
        self.torch_dtype = torch_dtype
        self.max_new_tokens = max_new_tokens
        self.attn_implementation = attn_implementation
        self._pipeline = None

    def load(self) -> Any:
        if self._pipeline is not None:
            return self._pipeline

        import torch
        from transformers import pipeline

        model_kwargs: dict[str, Any] = {}
        torch_dtype = resolve_torch_dtype(torch, self.torch_dtype, self.device)
        if torch_dtype is not None:
            model_kwargs["torch_dtype"] = torch_dtype
        if self.attn_implementation:
            model_kwargs["attn_implementation"] = self.attn_implementation

        kwargs: dict[str, Any] = {
            "task": "automatic-speech-recognition",
            "model": self.model,
            "device": self.device,
        }
        if model_kwargs:
            kwargs["model_kwargs"] = model_kwargs

        print(
            f"Loading Transformers Moonshine model {self.model} on {self.device} "
            f"dtype={self.torch_dtype}",
            flush=True,
        )
        self._pipeline = pipeline(**kwargs)
        print("Transformers Moonshine model loaded", flush=True)
        return self._pipeline

    def transcribe(self, audio_path: Path) -> str:
        pipe = self.load()
        kwargs: dict[str, Any] = {}
        if self.max_new_tokens > 0:
            kwargs["generate_kwargs"] = {"max_new_tokens": self.max_new_tokens}

        try:
            import soundfile as sf

            audio, sampling_rate = sf.read(str(audio_path), dtype="float32", always_2d=False)
            if getattr(audio, "ndim", 1) > 1:
                audio = audio.mean(axis=1)
            result = pipe({"array": audio, "sampling_rate": sampling_rate}, **kwargs)
        except Exception:
            result = pipe(str(audio_path), **kwargs)

        if isinstance(result, dict):
            text = result.get("text", "")
        elif isinstance(result, list):
            text = " ".join(str(item.get("text", "")) for item in result if isinstance(item, dict))
        else:
            text = str(result)
        return " ".join(text.strip().split())


class MoonshineHTTPServer(ThreadingHTTPServer):
    def __init__(self, server_address: tuple[str, int], handler_cls: type[BaseHTTPRequestHandler], runtime: Runtime):
        super().__init__(server_address, handler_cls)
        self.runtime = runtime
        self.sessions: dict[str, MoonshineVoiceStreamingSession] = {}
        self.sessions_lock = threading.Lock()


class MoonshineRequestHandler(BaseHTTPRequestHandler):
    server_version = "LocalWisprMoonshine/0.2"

    @property
    def runtime(self) -> Runtime:
        return self.server.runtime  # type: ignore[attr-defined]

    def do_GET(self) -> None:  # noqa: N802 - stdlib naming
        path = urlparse(self.path).path
        if path not in {"/", "/health", "/ready"}:
            self.send_json({"error": "not found"}, HTTPStatus.NOT_FOUND)
            return

        self.send_json(
            {
                "status": "ok",
                "backend": self.runtime.backend,
                "model": self.runtime.model,
                "loaded": True,
            }
        )

    def do_POST(self) -> None:  # noqa: N802 - stdlib naming
        path = urlparse(self.path).path
        if path in {"/transcribe", "/inference"}:
            self.handle_batch_transcription()
            return

        if path == "/sessions":
            self.handle_create_session()
            return

        parts = path.strip("/").split("/")
        if len(parts) == 3 and parts[0] == "sessions" and parts[2] == "audio":
            self.handle_session_audio(parts[1])
            return

        if len(parts) == 3 and parts[0] == "sessions" and parts[2] == "finish":
            self.handle_session_finish(parts[1])
            return

        self.send_json({"error": "not found"}, HTTPStatus.NOT_FOUND)

    def do_DELETE(self) -> None:  # noqa: N802 - stdlib naming
        parts = urlparse(self.path).path.strip("/").split("/")
        if len(parts) != 2 or parts[0] != "sessions":
            self.send_json({"error": "not found"}, HTTPStatus.NOT_FOUND)
            return

        session = self.pop_session(parts[1])
        if session is not None:
            session.cancel()
        self.send_json({"status": "ok"})

    def handle_batch_transcription(self) -> None:
        started = time.perf_counter()
        temp_path: Optional[Path] = None
        try:
            audio_bytes, filename = self.read_audio_upload()
            suffix = Path(filename or "audio.wav").suffix or ".wav"
            with tempfile.NamedTemporaryFile(prefix="local-wispr-moonshine-", suffix=suffix, delete=False) as temp_file:
                temp_file.write(audio_bytes)
                temp_path = Path(temp_file.name)

            text = self.runtime.transcribe(temp_path)
            elapsed_ms = round((time.perf_counter() - started) * 1000, 1)
            self.send_json(
                {
                    "text": text,
                    "backend": self.runtime.backend,
                    "model": self.runtime.model,
                    "duration_ms": elapsed_ms,
                }
            )
        except Exception as error:  # pragma: no cover - used in manual sidecar runs
            self.send_error_json(error)
        finally:
            if temp_path is not None:
                try:
                    temp_path.unlink(missing_ok=True)
                except Exception:
                    pass

    def handle_create_session(self) -> None:
        try:
            if not hasattr(self.runtime, "create_session"):
                self.send_json({"error": "streaming sessions are not supported by this backend"}, HTTPStatus.NOT_IMPLEMENTED)
                return

            payload = self.read_json_body(default={})
            update_interval = float(payload.get("update_interval", os.environ.get("LOCAL_WISPR_MOONSHINE_STREAM_UPDATE_SECONDS", "0.1")))
            session_id = str(uuid.uuid4())
            session = self.runtime.create_session(update_interval=update_interval)  # type: ignore[attr-defined]
            with self.server.sessions_lock:  # type: ignore[attr-defined]
                self.server.sessions[session_id] = session  # type: ignore[attr-defined]
            self.send_json({"id": session_id, "backend": self.runtime.backend, "model": self.runtime.model})
        except Exception as error:
            self.send_error_json(error)

    def handle_session_audio(self, session_id: str) -> None:
        try:
            session = self.get_session(session_id)
            if session is None:
                self.send_json({"error": "unknown streaming session"}, HTTPStatus.NOT_FOUND)
                return

            payload = self.read_json_body()
            samples = payload.get("samples")
            sample_rate = int(float(payload.get("sample_rate", 16000)))
            if not isinstance(samples, list):
                raise ValueError("samples must be an array")

            text = session.add_audio([float(sample) for sample in samples], sample_rate)
            self.send_json({"status": "ok", "text": text})
        except Exception as error:
            self.send_error_json(error)

    def handle_session_finish(self, session_id: str) -> None:
        started = time.perf_counter()
        try:
            session = self.pop_session(session_id)
            if session is None:
                self.send_json({"error": "unknown streaming session"}, HTTPStatus.NOT_FOUND)
                return

            text = session.finish()
            self.send_json(
                {
                    "text": text,
                    "backend": self.runtime.backend,
                    "model": self.runtime.model,
                    "duration_ms": round((time.perf_counter() - started) * 1000, 1),
                }
            )
        except Exception as error:
            self.send_error_json(error)

    def get_session(self, session_id: str) -> Optional[MoonshineVoiceStreamingSession]:
        with self.server.sessions_lock:  # type: ignore[attr-defined]
            return self.server.sessions.get(session_id)  # type: ignore[attr-defined]

    def pop_session(self, session_id: str) -> Optional[MoonshineVoiceStreamingSession]:
        with self.server.sessions_lock:  # type: ignore[attr-defined]
            return self.server.sessions.pop(session_id, None)  # type: ignore[attr-defined]

    def read_json_body(self, default: Optional[dict[str, Any]] = None) -> dict[str, Any]:
        content_length = int(self.headers.get("Content-Length", "0") or "0")
        if content_length <= 0:
            return default if default is not None else {}

        max_bytes = int(os.environ.get("LOCAL_WISPR_MOONSHINE_MAX_JSON_BYTES", "8388608"))
        if content_length > max_bytes:
            raise ValueError(f"JSON request too large: {content_length} bytes")

        body = self.rfile.read(content_length)
        payload = json.loads(body.decode("utf-8"))
        if not isinstance(payload, dict):
            raise ValueError("JSON body must be an object")
        return payload

    def send_error_json(self, error: Exception) -> None:
        if env_flag("LOCAL_WISPR_MOONSHINE_DEBUG"):
            traceback.print_exc()
            detail = traceback.format_exc()
        else:
            detail = str(error)
        self.send_json({"error": detail}, HTTPStatus.INTERNAL_SERVER_ERROR)

    def read_audio_upload(self) -> tuple[bytes, Optional[str]]:
        content_type = self.headers.get("Content-Type", "")
        content_length = int(self.headers.get("Content-Length", "0") or "0")
        if content_length <= 0:
            raise ValueError("empty request body")

        max_bytes = int(os.environ.get("LOCAL_WISPR_MOONSHINE_MAX_UPLOAD_BYTES", "52428800"))
        if content_length > max_bytes:
            raise ValueError(f"audio upload too large: {content_length} bytes")

        body = self.rfile.read(content_length)
        if content_type.startswith("multipart/form-data"):
            return self.parse_multipart(content_type, body)

        if content_type in {"audio/wav", "audio/x-wav", "application/octet-stream"}:
            return body, "audio.wav"

        raise ValueError(f"unsupported Content-Type: {content_type}")

    @staticmethod
    def parse_multipart(content_type: str, body: bytes) -> tuple[bytes, Optional[str]]:
        headers = (
            f"Content-Type: {content_type}\r\n"
            "MIME-Version: 1.0\r\n"
            "\r\n"
        ).encode("utf-8")
        message = BytesParser(policy=email_policy).parsebytes(headers + body)
        if not message.is_multipart():
            raise ValueError("malformed multipart body")

        first_file: Optional[tuple[bytes, Optional[str]]] = None
        for part in message.iter_parts():
            disposition = part.get("Content-Disposition", "")
            name = part.get_param("name", header="content-disposition")
            filename = part.get_filename()
            payload = part.get_payload(decode=True) or b""
            is_file = filename is not None or name in {"file", "audio", "audio_file"}
            if "form-data" in disposition and is_file and payload:
                first_file = (payload, filename)
                if name == "file":
                    break

        if first_file is None:
            raise ValueError("multipart body did not include a file field")
        return first_file

    def send_json(self, payload: dict[str, Any], status: HTTPStatus = HTTPStatus.OK) -> None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status.value)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, format: str, *args: Any) -> None:
        print(f"{self.address_string()} - {format % args}", file=sys.stderr, flush=True)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Local Wispr Moonshine STT sidecar")
    parser.add_argument("--host", default=os.environ.get("LOCAL_WISPR_MOONSHINE_HOST", "127.0.0.1"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("LOCAL_WISPR_MOONSHINE_PORT", "8179")))
    parser.add_argument("--backend", choices=["voice", "transformers"], default=os.environ.get("LOCAL_WISPR_MOONSHINE_BACKEND", "voice"))
    parser.add_argument("--language", default=os.environ.get("LOCAL_WISPR_MOONSHINE_LANGUAGE", DEFAULT_VOICE_LANGUAGE))
    parser.add_argument("--voice-arch", default=os.environ.get("LOCAL_WISPR_MOONSHINE_VOICE_ARCH"))
    parser.add_argument("--voice-cache-root", type=Path, default=os.environ.get("MOONSHINE_VOICE_CACHE"))
    parser.add_argument("--model", default=os.environ.get("LOCAL_WISPR_MOONSHINE_MODEL", DEFAULT_TRANSFORMERS_MODEL))
    parser.add_argument("--device", default=os.environ.get("LOCAL_WISPR_MOONSHINE_DEVICE") or infer_device())
    parser.add_argument("--torch-dtype", default=os.environ.get("LOCAL_WISPR_MOONSHINE_DTYPE", "auto"))
    parser.add_argument("--max-new-tokens", type=int, default=int(os.environ.get("LOCAL_WISPR_MOONSHINE_MAX_NEW_TOKENS", "96")))
    parser.add_argument("--attn-implementation", default=os.environ.get("LOCAL_WISPR_MOONSHINE_ATTN_IMPLEMENTATION"))
    parser.add_argument(
        "--no-preload",
        action="store_true",
        default=not env_flag("LOCAL_WISPR_MOONSHINE_PRELOAD", True),
        help="start HTTP listener before loading the model",
    )
    return parser.parse_args()


def make_runtime(args: argparse.Namespace) -> Runtime:
    if args.backend == "voice":
        return MoonshineVoiceRuntime(
            language=args.language,
            model_arch=args.voice_arch or arch_from_model_name(args.model),
            cache_root=args.voice_cache_root,
        )

    return TransformersMoonshineRuntime(
        model=args.model,
        device=args.device,
        torch_dtype=args.torch_dtype,
        max_new_tokens=args.max_new_tokens,
        attn_implementation=args.attn_implementation,
    )


def main() -> int:
    args = parse_args()
    host = args.host.strip().lower()
    if host not in LOOPBACK_HOSTS:
        print(
            f"Refusing to bind Moonshine server to non-loopback host: {args.host}",
            file=sys.stderr,
        )
        return 2

    runtime = make_runtime(args)

    if not args.no_preload:
        runtime.load()

    if ":" in args.host:
        MoonshineHTTPServer.address_family = socket.AF_INET6

    server = MoonshineHTTPServer((args.host, args.port), MoonshineRequestHandler, runtime)
    print(
        f"Moonshine server listening on http://{args.host}:{args.port}/transcribe "
        f"backend={runtime.backend} model={runtime.model}",
        flush=True,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("Stopping Moonshine server", flush=True)
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
