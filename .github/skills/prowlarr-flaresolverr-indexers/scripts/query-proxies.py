#!/usr/bin/env python3
"""
Manage Prowlarr indexer proxies.

Usage:
  python3 query-proxies.py list                              # List all proxies
  python3 query-proxies.py create-flaresolverr               # Create FlareSolverr proxy
  python3 query-proxies.py bind-to-tag <proxy_id> <tag_id>   # Bind proxy to tag
  python3 query-proxies.py --help                            # Show help
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from prowlarr_utils import api_request, load_api_key, print_json, print_table


def list_proxies(api_key: str) -> None:
    """List all indexer proxies."""
    status, data = api_request("GET", "/indexerproxy", api_key)
    if status != 200:
        print(f"Error fetching proxies: HTTP {status}")
        print_json(data)
        return
    
    if not data:
        print("No proxies found")
        return
    
    headers = ["id", "implementation", "host", "tags"]
    rows = []
    for p in data:
        rows.append({
            "id": p.get("id"),
            "implementation": p.get("implementation"),
            "host": p.get("host", p.get("fields", [{}])[0].get("value", "N/A"))[:50],
            "tags": p.get("tags", []),
        })
    print_table(headers, rows)


def create_flaresolverr_proxy(api_key: str) -> None:
    """Create a FlareSolverr IndexerProxy."""
    # Get schema to build payload
    status, schema = api_request("GET", "/indexerproxy/schema", api_key)
    if status != 200:
        print(f"Error fetching proxy schema: HTTP {status}")
        return
    
    # Find FlareSolverr implementation
    flaresolverr_schema = next(
        (s for s in schema if s.get("implementationName") == "FlareSolverr"),
        None,
    )
    if not flaresolverr_schema:
        print("FlareSolverr proxy implementation not found in schema")
        return
    
    # Build payload
    payload = {
        "implementation": flaresolverr_schema.get("implementation"),
        "implementationName": "FlareSolverr",
        "configContract": flaresolverr_schema.get("configContract"),
        "name": "FlareSolverr",
        "fields": flaresolverr_schema.get("fields", []),
        "tags": [],
    }
    
    # Set FlareSolverr URL field
    for field in payload["fields"]:
        if field.get("name") == "host":
            field["value"] = "http://127.0.0.1:8191/"
            break
    
    try:
        status, data = api_request("POST", "/indexerproxy", api_key, body=payload)
    except Exception as e:
        print(f"Error creating proxy: {e}")
        return
    
    if status in [200, 201]:
        print(
            f"✓ Created FlareSolverr proxy: "
            f"id={data.get('id')} host={data.get('host', 'http://127.0.0.1:8191/')}"
        )
    else:
        print(f"✗ Failed to create proxy (HTTP {status})")
        print_json(data)


def bind_proxy_to_tag(api_key: str, proxy_id: int, tag_id: int) -> None:
    """Bind a proxy to a tag."""
    # Get current proxy
    status, proxy = api_request("GET", f"/indexerproxy/{proxy_id}", api_key)
    if status != 200:
        print(f"Error fetching proxy {proxy_id}: HTTP {status}")
        return
    
    # Update tags
    if tag_id not in proxy.get("tags", []):
        proxy["tags"].append(tag_id)
    
    # PUT back
    try:
        status, data = api_request("PUT", f"/indexerproxy/{proxy_id}", api_key, body=proxy)
    except Exception as e:
        print(f"Error updating proxy: {e}")
        return
    
    if status in [200, 202]:
        print(f"✓ Bound proxy {proxy_id} to tag {tag_id}. Tags: {data.get('tags', [])}")
    else:
        print(f"✗ Failed to bind proxy (HTTP {status})")
        print_json(data)


def main():
    parser = argparse.ArgumentParser(
        description="Manage Prowlarr indexer proxies",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 query-proxies.py list
  python3 query-proxies.py create-flaresolverr
  python3 query-proxies.py bind-to-tag 1 1
        """,
    )
    
    subparsers = parser.add_subparsers(dest="command", help="Command to run")
    subparsers.add_parser("list", help="List all proxies")
    subparsers.add_parser("create-flaresolverr", help="Create FlareSolverr proxy")
    
    bind_parser = subparsers.add_parser("bind-to-tag", help="Bind proxy to tag")
    bind_parser.add_argument("proxy_id", type=int, help="Proxy ID")
    bind_parser.add_argument("tag_id", type=int, help="Tag ID")
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return
    
    try:
        api_key = load_api_key()
    except (FileNotFoundError, ValueError) as e:
        print(f"Error: {e}")
        sys.exit(1)
    
    if args.command == "list":
        list_proxies(api_key)
    elif args.command == "create-flaresolverr":
        create_flaresolverr_proxy(api_key)
    elif args.command == "bind-to-tag":
        bind_proxy_to_tag(api_key, args.proxy_id, args.tag_id)


if __name__ == "__main__":
    main()
