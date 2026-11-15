"""Bounded, authenticated upload receiver; PostgreSQL is private to the server."""

import hmac
import json
import os
import zlib

from fastapi import FastAPI, HTTPException, Request
from starlette.concurrency import run_in_threadpool
import psycopg

from .contract import validate_batch
from .database import Conflict, ingest

MAX_WIRE = 2 * 1024 * 1024
MAX_JSON = 8 * 1024 * 1024
app = FastAPI(title="Profit Market Receiver", version="0.1.0", docs_url=None, redoc_url=None, openapi_url=None)


def authenticate(header):
    configured = os.environ.get("UPLOAD_KEYS_JSON")
    keys = json.loads(configured) if configured else {os.environ.get("UPLOAD_CONTRIBUTOR", "pilot"): os.environ.get("UPLOAD_TOKEN", "")}
    supplied = header[7:] if header and header.startswith("Bearer ") else ""
    for contributor, token in keys.items():
        if isinstance(token, str) and len(token) >= 32 and hmac.compare_digest(supplied.encode(), token.encode()):
            return contributor
    raise HTTPException(401, "Invalid upload key")


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate JSON key")
        result[key] = value
    return result


@app.get("/healthz")
def health():
    try:
        with psycopg.connect(os.environ["DATABASE_URL"], connect_timeout=3) as connection:
            version = connection.execute("SELECT version FROM market.schema_version").fetchone()
        if version != (1,):
            raise ValueError("Unsupported schema")
        return {"status": "ok", "schema_version": 1}
    except (psycopg.Error, ValueError, KeyError):
        raise HTTPException(503, "Database is not ready") from None


@app.post("/api/v1/uploads")
async def upload(request: Request):
    contributor = authenticate(request.headers.get("authorization"))
    if request.headers.get("content-type", "").split(";")[0] != "application/json":
        raise HTTPException(415, "Expected application/json")
    body = bytearray()
    async for chunk in request.stream():
        body.extend(chunk)
        if len(body) > MAX_WIRE:
            raise HTTPException(413, "Upload part is too large")
    try:
        encoding = request.headers.get("content-encoding", "identity")
        if encoding == "gzip":
            decoder = zlib.decompressobj(16 + zlib.MAX_WBITS)
            raw = decoder.decompress(bytes(body), MAX_JSON + 1)
            if len(raw) > MAX_JSON or decoder.unconsumed_tail:
                raise HTTPException(413, "Expanded upload is too large")
            if not decoder.eof or decoder.unused_data:
                raise ValueError("Invalid gzip stream")
        elif encoding == "identity":
            raw = bytes(body)
        else:
            raise HTTPException(415, "Unsupported content encoding")
        def invalid_constant(value):
            raise ValueError("Non-finite JSON number")
        batch = validate_batch(json.loads(raw, object_pairs_hook=unique_object, parse_constant=invalid_constant))
    except (ValueError, TypeError, KeyError, IndexError, AttributeError, OverflowError, RecursionError, zlib.error):
        raise HTTPException(422, "Invalid market upload") from None
    try:
        return await run_in_threadpool(ingest, batch, contributor)
    except Conflict:
        raise HTTPException(409, "Upload identity conflicts with an earlier upload") from None
    except psycopg.Error:
        raise HTTPException(503, "Database could not commit the upload; retry later") from None
