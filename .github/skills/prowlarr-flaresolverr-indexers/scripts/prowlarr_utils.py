#!/usr/bin/env python3
"""
Shared utilities for Prowlarr API interaction.
"""
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Dict, Optional, Tuple


def load_api_key(env_file: str = ".env") -> str:
    """Load PROWLARR_API_KEY from .env file."""
    if not Path(env_file).exists():
        raise FileNotFoundError(f"{env_file} not found. Run from workspace root.")
    
    for line in Path(env_file).read_text().splitlines():
        line = line.lstrip()
        if line.startswith("#") or not line.strip():
            continue
        m = re.match(r"\s*PROWLARR_API_KEY=(.*)$", line.rstrip("\n"))
        if m:
            v = m.group(1).strip()
            # Remove quotes if present
            if len(v) >= 2 and ((v[0] == v[-1] == '"') or (v[0] == v[-1] == "'")):
                return v[1:-1]
            return v
    
    raise ValueError("PROWLARR_API_KEY not found in .env")


def api_request(
    method: str,
    endpoint: str,
    api_key: str,
    base_url: str = "http://127.0.0.1:9696/api/v1",
    body: Optional[Dict[str, Any]] = None,
    timeout: int = 30,
) -> Tuple[int, Any]:
    """Make HTTP request to Prowlarr API.
    
    Args:
        method: HTTP method (GET, POST, PUT, DELETE)
        endpoint: API endpoint path (e.g., /indexer, /tag)
        api_key: Prowlarr API key
        base_url: Prowlarr API base URL
        body: JSON body for POST/PUT requests
        timeout: Request timeout in seconds
    
    Returns:
        Tuple of (status_code, response_data)
        response_data is parsed JSON or None
    
    Raises:
        urllib.error.HTTPError: For HTTP errors
        Exception: For other errors
    """
    headers = {"X-Api-Key": api_key, "Content-Type": "application/json"}
    url = base_url + endpoint
    
    data = None
    if body:
        data = json.dumps(body).encode("utf-8")
    
    req = urllib.request.Request(url, headers=headers, data=data, method=method)
    
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            text = resp.read().decode("utf-8")
            response_data = json.loads(text) if text else None
            return resp.status, response_data
    except urllib.error.HTTPError as e:
        error_body = e.read().decode("utf-8", errors="replace")
        try:
            error_json = json.loads(error_body)
        except json.JSONDecodeError:
            error_json = {"raw": error_body}
        raise Exception(f"HTTP {e.code}: {error_json}") from e


def print_json(data: Any, indent: int = 2) -> None:
    """Pretty-print JSON data."""
    print(json.dumps(data, indent=indent, default=str))


def print_table(headers: list, rows: list) -> None:
    """Print simple table from list of dicts.
    
    Args:
        headers: List of column names
        rows: List of dicts with header keys
    """
    if not rows:
        print("(no results)")
        return
    
    # Calculate column widths
    widths = {h: len(h) for h in headers}
    for row in rows:
        for h in headers:
            val = str(row.get(h, ""))
            widths[h] = max(widths[h], len(val))
    
    # Print header
    header_row = " | ".join(h.ljust(widths[h]) for h in headers)
    print(header_row)
    print("-" * len(header_row))
    
    # Print rows
    for row in rows:
        print(" | ".join(str(row.get(h, "")).ljust(widths[h]) for h in headers))
