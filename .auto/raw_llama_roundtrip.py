#!/usr/bin/env python3
"""Direct llama-server cleanup roundtrip benchmark for Local Wispr.

Measures wall-clock time from issuing an HTTP request on an existing loopback
connection until the full response body is read. Uses only synthetic text.
"""

from __future__ import annotations

import http.client
import json
import os
import re
import statistics
import sys
import time
from dataclasses import dataclass
from typing import Iterable
from urllib.parse import urlparse


@dataclass(frozen=True)
class Case:
    id: str
    transcript: str
    expected: tuple[str, ...]
    forbidden: tuple[str, ...] = ("um", "uh", "<|im", "Transcript:", "Cleaned:")


CASES: tuple[Case, ...] = (
    Case(
        "meeting-followup",
        "um can you send john the notes from the meeting and ask if friday works uh also mention that we can move it if needed",
        ("John", "Friday", "meeting"),
    ),
    Case(
        "email-subject",
        "please write an email subject about moving the product review to monday and mention that the beta feedback is ready",
        ("product review", "Monday", "beta feedback"),
    ),
    Case(
        "status-update",
        "i finished the app packaging checklist and the permission reset script is working now but we still need to check the release notes and make sure the local cleanup model does not slow down the hotkey release path",
        ("app packaging checklist", "permission reset", "release notes", "hotkey release"),
    ),
    Case(
        "list-request",
        "make this a bullet list first check microphone permission second run the local engine smoke test third summarize the timing log",
        ("microphone permission", "local engine smoke test", "timing log"),
    ),
    Case(
        "slack-message",
        "draft a slack message to nina saying the onboarding checklist is ready and ask whether three pm still works for the walkthrough",
        ("Nina", "onboarding checklist", "walkthrough"),
    ),
    Case(
        "readme-note",
        "remind me to update the local wispr readme with the llama server setup notes and the loopback only warning",
        ("local wispr", "readme", "llama server", "loopback"),
    ),
)


def env_int(name: str, default: int) -> int:
    raw = os.environ.get(name)
    if raw is None or raw == "":
        return default
    try:
        value = int(raw)
    except ValueError:
        raise SystemExit(f"{name} must be an integer, got {raw!r}")
    return value


def env_float(name: str, default: float) -> float:
    raw = os.environ.get(name)
    if raw is None or raw == "":
        return default
    try:
        return float(raw)
    except ValueError:
        raise SystemExit(f"{name} must be a float, got {raw!r}")


def bool_env(name: str, default: bool) -> bool:
    raw = os.environ.get(name)
    if raw is None or raw == "":
        return default
    return raw.lower() in {"1", "true", "yes", "on"}


def cleanup_prompt(transcript: str, style: str) -> str:
    if style == "chatml":
        return (
            "<|im_start|>system\n"
            "You clean up dictated text with minimal edits. Return only the final cleaned text.\n"
            "Preserve wording, first-person perspective, meaning, order, names, dates, numbers, URLs, emails, file paths, and task items.\n"
            "Fix capitalization and punctuation. Remove only obvious spoken filler words.\n"
            "Do not summarize, paraphrase, add facts, explain, or repeat instructions.\n"
            "<|im_end|>\n"
            "<|im_start|>user\n"
            f"Transcript:\n{transcript}\n"
            "<|im_end|>\n"
            "<|im_start|>assistant\n"
        )
    if style == "chatml-filler":
        return (
            "<|im_start|>system\n"
            "You clean up dictated text with minimal edits. Return only the final cleaned text.\n"
            "Preserve wording, first-person perspective, meaning, order, names, dates, numbers, URLs, emails, file paths, and task items.\n"
            "Fix capitalization and punctuation. Remove filler words exactly like um, uh, erm, and ah.\n"
            "Do not summarize, paraphrase, add facts, explain, or repeat instructions.\n"
            "<|im_end|>\n"
            "<|im_start|>user\n"
            f"Transcript:\n{transcript}\n"
            "<|im_end|>\n"
            "<|im_start|>assistant\n"
        )
    if style == "strict-chatml":
        return (
            "<|im_start|>system\n"
            "You are a dictation cleanup filter. Return only the final cleaned text.\n"
            "Delete filler words such as um, uh, erm, and ah. Fix capitalization and punctuation.\n"
            "Preserve the speaker's wording, first-person perspective, meaning, order, names, dates, numbers, URLs, emails, file paths, and task items.\n"
            "Do not add labels, explanations, greetings, new facts, or extra items.\n"
            "<|im_end|>\n"
            "<|im_start|>user\n"
            f"{transcript}\n"
            "<|im_end|>\n"
            "<|im_start|>assistant\n"
        )
    if style == "terse-chatml":
        return (
            "<|im_start|>system\n"
            "Clean dictated text. Fix caps/punctuation, delete filler words like um and uh, preserve meaning. Return only cleaned text.\n"
            "<|im_end|>\n"
            "<|im_start|>user\n"
            f"{transcript}\n"
            "<|im_end|>\n"
            "<|im_start|>assistant\n"
        )
    if style == "plain":
        return (
            "Clean dictated text. Fix capitalization and punctuation, remove fillers, preserve meaning. "
            "Return only the cleaned text.\n"
            f"Input: {transcript}\n"
            "Cleaned:"
        )
    if style == "minimal":
        return f"Clean this dictated text, preserving meaning. Output only cleaned text.\n{transcript}\n"
    if style == "rewrite":
        return f"Rewrite with punctuation/capitalization only; remove fillers; output only text.\nInput: {transcript}\nOutput:"
    raise SystemExit(f"Unknown LOCAL_WISPR_RAW_PROMPT_STYLE={style!r}")


def percentile(values: list[float], q: float) -> float:
    ordered = sorted(values)
    if not ordered:
        return 0.0
    if len(ordered) == 1:
        return ordered[0]
    index = (len(ordered) - 1) * q
    lo = int(index)
    hi = min(lo + 1, len(ordered) - 1)
    frac = index - lo
    return ordered[lo] * (1 - frac) + ordered[hi] * frac


def metric(name: str, value: float | int | str) -> None:
    if isinstance(value, float):
        print(f"METRIC {name}={value:.3f}")
    else:
        print(f"METRIC {name}={value}")


def normalize_for_match(text: str) -> str:
    text = text.lower().replace("-", " ")
    return re.sub(r"\s+", " ", text).strip()


def contains_forbidden(normalized_text: str, forbidden: str) -> bool:
    needle = normalize_for_match(forbidden)
    if re.fullmatch(r"[a-z]+", needle):
        return re.search(rf"(?<![a-z]){re.escape(needle)}(?![a-z])", normalized_text) is not None
    return needle in normalized_text


def validate(case: Case, content: str, strict: bool) -> list[str]:
    text = content.strip()
    failures: list[str] = []
    if not text:
        failures.append("empty output")
        return failures

    normalized = normalize_for_match(text)
    for forbidden in case.forbidden:
        if contains_forbidden(normalized, forbidden):
            failures.append(f"contains forbidden {forbidden!r}")

    if strict:
        for expected in case.expected:
            if normalize_for_match(expected) not in normalized:
                failures.append(f"missing expected {expected!r}")

    return failures


class BenchClient:
    def __init__(self, endpoint: str, timeout_seconds: float) -> None:
        parsed = urlparse(endpoint)
        if parsed.scheme != "http":
            raise SystemExit(f"Only http loopback endpoints are supported, got {endpoint}")
        host = parsed.hostname or ""
        if host.lower() not in {"127.0.0.1", "localhost", "::1"} and os.environ.get("LOCAL_WISPR_ALLOW_NON_LOOPBACK_LLAMA") != "1":
            raise SystemExit(f"Refusing non-loopback llama endpoint: {endpoint}")
        self.host = host
        self.port = parsed.port or 80
        self.path = parsed.path or "/completion"
        if self.path == "/":
            self.path = "/completion"
        if parsed.query:
            self.path += "?" + parsed.query
        self.conn = http.client.HTTPConnection(self.host, self.port, timeout=timeout_seconds)

    def close(self) -> None:
        self.conn.close()

    def post(self, payload: dict) -> tuple[float, str, int]:
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json",
            "Connection": "keep-alive",
        }
        started = time.perf_counter_ns()
        self.conn.request("POST", self.path, body=body, headers=headers)
        response = self.conn.getresponse()
        data = response.read()
        finished = time.perf_counter_ns()
        elapsed_ms = (finished - started) / 1_000_000
        if response.status != 200:
            return elapsed_ms, f"HTTP {response.status}: {data[:200]!r}", response.status
        try:
            decoded = json.loads(data)
        except json.JSONDecodeError as exc:
            return elapsed_ms, f"decode error: {exc}; body={data[:200]!r}", response.status
        content = decoded.get("content")
        if not isinstance(content, str):
            content = decoded.get("response") if isinstance(decoded.get("response"), str) else ""
        return elapsed_ms, content, response.status


def make_payload(case: Case, prompt_style: str, n_predict: int, temperature: float, cache_prompt: bool, stop: list[str]) -> dict:
    payload: dict = {
        "prompt": cleanup_prompt(case.transcript, prompt_style),
        "n_predict": n_predict,
        "temperature": temperature,
        "cache_prompt": cache_prompt,
        "stream": False,
    }
    if stop:
        payload["stop"] = stop
    seed = os.environ.get("LOCAL_WISPR_RAW_SEED")
    if seed not in (None, ""):
        payload["seed"] = int(seed)
    samplers = os.environ.get("LOCAL_WISPR_RAW_SAMPLERS")
    if samplers:
        payload["samplers"] = samplers
    if bool_env("LOCAL_WISPR_RAW_IGNORE_EOS", False):
        payload["ignore_eos"] = True
    return payload


def run_phase(
    client: BenchClient,
    name: str,
    cases: list[Case],
    iterations: int,
    warmup: int,
    prompt_style: str,
    n_predict: int,
    temperature: float,
    cache_prompt: bool,
    stop: list[str],
    strict: bool,
    show_outputs: bool,
) -> tuple[list[float], int]:
    latencies: list[float] = []
    invalid = 0
    total = warmup + iterations
    for i in range(total):
        measured = i >= warmup
        case = cases[i % len(cases)]
        payload = make_payload(case, prompt_style, n_predict, temperature, cache_prompt, stop)
        try:
            elapsed_ms, content, status = client.post(payload)
        except (http.client.HTTPException, OSError) as exc:
            # Reconnect once outside the timing sample and retry the same request.
            client.close()
            client.conn = http.client.HTTPConnection(client.host, client.port, timeout=10)
            elapsed_ms, content, status = client.post(payload)
            content = content or f"retry after {exc!r}"
        failures = validate(case, content, strict)
        if measured:
            latencies.append(elapsed_ms)
            if status != 200 or failures:
                invalid += 1
            if show_outputs and (i - warmup < min(6, iterations)):
                printable = content.strip().replace("\n", "\\n")[:240]
                suffix = f" failures={failures}" if failures else ""
                print(f"OUTPUT {name} {case.id} {elapsed_ms:.3f}ms: {printable}{suffix}", file=sys.stderr)
    return latencies, invalid


def main() -> int:
    endpoint = os.environ.get("LOCAL_WISPR_LLAMA_SERVER_URL") or os.environ.get("LOCAL_WISPR_LLAMA_SERVER_ENDPOINT") or "http://127.0.0.1:8080/completion"
    iterations = env_int("LOCAL_WISPR_RAW_ITERATIONS", 60)
    warmup = env_int("LOCAL_WISPR_RAW_WARMUP", 8)
    n_predict = env_int("LOCAL_WISPR_RAW_N_PREDICT", env_int("LOCAL_WISPR_CLEANUP_NUM_PREDICT", 38))
    temperature = env_float("LOCAL_WISPR_RAW_TEMPERATURE", 0.0)
    prompt_style = os.environ.get("LOCAL_WISPR_RAW_PROMPT_STYLE", "chatml-filler")
    cache_prompt = bool_env("LOCAL_WISPR_RAW_CACHE_PROMPT", True)
    strict = bool_env("LOCAL_WISPR_RAW_STRICT_EXPECTED", True)
    show_outputs = bool_env("LOCAL_WISPR_RAW_SHOW_OUTPUTS", False)
    stop_mode = os.environ.get("LOCAL_WISPR_RAW_STOP_MODE", "chatml")
    timeout = env_float("LOCAL_WISPR_RAW_TIMEOUT_SECONDS", 10.0)

    if stop_mode == "none":
        stop: list[str] = []
    elif stop_mode == "newline":
        stop = ["\n", "<|im_end|>", "<|endoftext|>"]
    elif stop_mode == "chatml":
        stop = ["<|im_end|>", "<|endoftext|>"]
    else:
        stop = [part for part in stop_mode.split("|") if part]

    repeated_case_id = os.environ.get("LOCAL_WISPR_RAW_REPEATED_CASE", "email-subject")
    repeated_case = next((case for case in CASES if case.id == repeated_case_id), CASES[1])
    varied_cases = list(CASES)

    print(f"INFO endpoint={endpoint}", file=sys.stderr)
    print(
        "INFO prompt_style=%s n_predict=%d temperature=%.3f cache_prompt=%s stop_mode=%s iterations=%d warmup=%d"
        % (prompt_style, n_predict, temperature, cache_prompt, stop_mode, iterations, warmup),
        file=sys.stderr,
    )

    client = BenchClient(endpoint, timeout)
    try:
        repeated, repeated_invalid = run_phase(
            client,
            "repeated",
            [repeated_case],
            iterations,
            warmup,
            prompt_style,
            n_predict,
            temperature,
            cache_prompt,
            stop,
            strict,
            show_outputs,
        )
        varied, varied_invalid = run_phase(
            client,
            "varied",
            varied_cases,
            iterations,
            warmup,
            prompt_style,
            n_predict,
            temperature,
            cache_prompt,
            stop,
            strict,
            show_outputs,
        )
    finally:
        client.close()

    metric("raw_llama_repeated_ms_avg", statistics.fmean(repeated) if repeated else 0.0)
    metric("raw_llama_repeated_ms_median", statistics.median(repeated) if repeated else 0.0)
    metric("raw_llama_repeated_ms_p95", percentile(repeated, 0.95))
    metric("raw_llama_repeated_invalid", repeated_invalid)
    metric("raw_llama_varied_ms_avg", statistics.fmean(varied) if varied else 0.0)
    metric("raw_llama_varied_ms_median", statistics.median(varied) if varied else 0.0)
    metric("raw_llama_varied_ms_p95", percentile(varied, 0.95))
    metric("raw_llama_varied_invalid", varied_invalid)
    metric("raw_llama_iterations", iterations)
    metric("raw_llama_n_predict", n_predict)
    metric("raw_llama_prompt_style", prompt_style)
    metric("raw_llama_stop_mode", stop_mode)
    metric("raw_llama_cache_prompt", 1 if cache_prompt else 0)

    return 2 if repeated_invalid or varied_invalid else 0


if __name__ == "__main__":
    raise SystemExit(main())
