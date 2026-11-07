"""Server-only OpenAI Responses transport. No SDK, key logging or automatic paid retries."""
import base64
import json
from pathlib import Path
import time
import urllib.error
import urllib.request

MAX_RESPONSE_BYTES = 2_000_000


def load_api_key(config):
    path = Path(config["apiKeyFile"])
    if path.is_symlink() or path.stat().st_mode & 0o077:
        raise RuntimeError("API-Schlüsseldatei muss privat sein (0600).")
    for line in path.read_text().splitlines():
        if line.startswith("OPENAI_API_KEY="):
            key = line.partition("=")[2].strip().strip("\"'")
            if key.startswith("sk-") and not any(c.isspace() for c in key): return key
    raise RuntimeError("OpenAI API-Schlüssel ist nicht eingerichtet.")


class NoRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        # Never forward a bearer key to a redirect destination.
        return None


def run_response(job_dir, config, prompt, schema, model, effort, *, photo_only, attach_images, stop=None):
    if stop is not None and stop.is_set(): raise InterruptedError("Worker stopped")
    content = [{"type": "input_text", "text": prompt}]
    if attach_images:
        for side in ("front.jpg", "back.jpg"):
            photo = job_dir / side
            if photo.exists():
                pixels = photo.read_bytes()
                mime = "image/png" if pixels.startswith(b"\x89PNG\r\n\x1a\n") else "image/jpeg"
                content.append({"type": "input_image", "detail": "high",
                    "image_url": "data:" + mime + ";base64," + base64.b64encode(pixels).decode()})
    if photo_only and len(content) == 1: raise ValueError("Identification requires a photo")
    payload = {
        "model": model, "store": False,
        "service_tier": config.get("apiServiceTier", "fast"),
        "input": [{"role": "user", "content": content}],
        "reasoning": {"effort": effort or "medium"},
        "text": {"format": {"type": "json_schema", "name": "card_scout", "strict": True, "schema": schema}},
        "max_output_tokens": config.get("apiIdentificationMaxOutputTokens", 6000) if photo_only else config.get("apiMaxOutputTokens", 24000),
        "tools": [],
    }
    # Retrieval happens on our server. Never enable billable hosted tools,
    # including when an old configuration still says webSearch=live.
    request = urllib.request.Request("https://api.openai.com/v1/responses", method="POST",
        data=json.dumps(payload).encode(), headers={"Authorization": "Bearer " + load_api_key(config),
                                                   "Content-Type": "application/json"})
    started = time.monotonic()
    try:
        opener = urllib.request.build_opener(NoRedirects())
        with opener.open(request, timeout=config.get("apiIdentificationTimeoutSeconds", 90) if photo_only else config.get("apiTimeoutSeconds", 300)) as response:
            raw = response.read(MAX_RESPONSE_BYTES + 1)
    except urllib.error.HTTPError as error:
        # Provider error bodies may echo input. Persist only the numeric status.
        code = error.code
        error.close()
        raise RuntimeError(f"OpenAI API nicht verfügbar (HTTP {code}). API-Zugang, Guthaben und Limits prüfen.") from None
    except (urllib.error.URLError, TimeoutError, OSError):
        raise RuntimeError("OpenAI API nicht erreichbar oder Zeitlimit überschritten.") from None
    if stop is not None and stop.is_set(): raise InterruptedError("Worker stopped")
    if len(raw) > MAX_RESPONSE_BYTES: raise ValueError("API response too large")
    response = json.loads(raw)
    # Log only transport/accounting metadata, never request/response bodies or credentials.
    metadata = {"backend": "openai-api", "model": model, "requestedTier": payload["service_tier"],
                "actualTier": response.get("service_tier"), "status": response.get("status"),
                "seconds": round(time.monotonic() - started, 2), "usage": response.get("usage"),
                "webSearchCalls": sum(item.get("type") == "web_search_call" for item in response.get("output", []))}
    with (job_dir / "worker.log").open("a") as log: log.write("\n[card-scout] " + json.dumps(metadata) + "\n")
    if response.get("status") != "completed":
        raise RuntimeError("API-Analyse unvollständig. Bitte erneut versuchen.")
    texts = []
    for item in response.get("output", []):
        if item.get("type") != "message": continue
        for part in item.get("content", []):
            if part.get("type") == "refusal": raise RuntimeError("API konnte dieses Foto nicht auswerten.")
            if part.get("type") == "output_text": texts.append(part["text"])
    if not texts: raise ValueError("API returned no structured result")
    return json.loads("".join(texts))
