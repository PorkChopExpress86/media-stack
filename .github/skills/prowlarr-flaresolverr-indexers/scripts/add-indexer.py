#!/usr/bin/env python3
"""
Add a new indexer instance to Prowlarr.

Usage:
  python3 add-indexer.py --definition 1337x --name "1337x" --tag 1 --enable
  python3 add-indexer.py --definition eztv --name "EZTV" --tag 1
  python3 add-indexer.py --help
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from prowlarr_utils import api_request, load_api_key, print_json


def add_indexer(
    api_key: str,
    definition: str,
    name: str,
    tag: int = None,
    enable: bool = False,
) -> None:
    """Add a new indexer instance from a definition."""
    
    # Get schema to find the definition
    status, schema = api_request("GET", "/indexer/schema", api_key)
    if status != 200:
        print(f"Error fetching schema: HTTP {status}")
        return
    
    # Find the definition by definitionName
    indexer_schema = next(
        (s for s in schema if s.get("definitionName") == definition),
        None,
    )
    if not indexer_schema:
        print(f"Definition '{definition}' not found in schema")
        print(f"Available definitions: {[s.get('definitionName') for s in schema if s.get('implementationName') == 'Cardigann'][:10]}...")
        return
    
    # Build payload from schema
    payload = {
        "implementation": indexer_schema.get("implementation"),
        "implementationName": indexer_schema.get("implementationName"),
        "configContract": indexer_schema.get("configContract"),
        "name": name,
        "definitionName": definition,
        "fields": indexer_schema.get("fields", []),
        "enable": enable,
        "priority": 25,
        "appProfileId": 1,
        "downloadClientId": 0,
        "tags": [tag] if tag is not None else [],
    }
    
    # Remove auto-generated fields
    for key in [
        "id",
        "added",
        "capabilities",
        "description",
        "infoLink",
        "language",
        "legacyUrls",
        "privacy",
        "protocol",
        "redirect",
        "sortName",
        "supportsRedirect",
        "supportsRss",
        "supportsSearch",
        "supportsPagination",
    ]:
        payload.pop(key, None)
    
    # POST to create indexer
    try:
        status, data = api_request("POST", "/indexer", api_key, body=payload)
    except Exception as e:
        print(f"Error creating indexer: {e}")
        return
    
    if status in [200, 201, 202]:
        print(
            f"✓ Added indexer: "
            f"id={data.get('id')} "
            f"name={data.get('name')} "
            f"enabled={data.get('enable')} "
            f"tags={data.get('tags', [])}"
        )
    else:
        print(f"✗ Failed to create indexer (HTTP {status})")
        print_json(data)


def main():
    parser = argparse.ArgumentParser(
        description="Add a new indexer instance to Prowlarr",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 add-indexer.py --definition 1337x --name "1337x" --tag 1 --enable
  python3 add-indexer.py --definition eztv --name "EZTV" --tag 1
  python3 add-indexer.py --definition kickasstorrents-ws --name "kickass.ws"
        """,
    )
    
    parser.add_argument("--definition", required=True, help="Indexer definition name (e.g., '1337x', 'eztv')")
    parser.add_argument("--name", required=True, help="Display name for the indexer instance")
    parser.add_argument("--tag", type=int, help="Tag ID to assign (e.g., 1 for 'flaresolverr')")
    parser.add_argument(
        "--enable",
        action="store_true",
        help="Enable the indexer immediately (default: disabled)",
    )
    
    args = parser.parse_args()
    
    try:
        api_key = load_api_key()
    except (FileNotFoundError, ValueError) as e:
        print(f"Error: {e}")
        sys.exit(1)
    
    add_indexer(api_key, args.definition, args.name, tag=args.tag, enable=args.enable)


if __name__ == "__main__":
    main()
