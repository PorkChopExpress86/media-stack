#!/usr/bin/env python3
"""
Query available Prowlarr indexer definitions.

Usage:
  python3 query-definitions.py list                           # List all definitions
  python3 query-definitions.py list --search "1337x"          # Search definitions
  python3 query-definitions.py list --flaresolverr-only       # Only definitions with FlareSolverr support
  python3 query-definitions.py --help                         # Show help
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from prowlarr_utils import api_request, load_api_key, print_json, print_table


def list_definitions(api_key: str, search: str = "", flaresolverr_only: bool = False) -> None:
    """List indexer definitions with optional filters."""
    status, schema = api_request("GET", "/indexer/schema", api_key)
    if status != 200:
        print(f"Error fetching schema: HTTP {status}")
        print_json(schema)
        return
    
    # Filter by Cardigann (extensible via YAML)
    defs = [s for s in schema if s.get("implementationName") == "Cardigann"]
    
    # Filter by search term (case-insensitive)
    if search:
        search_lower = search.lower()
        defs = [
            d for d in defs
            if search_lower in d.get("definitionName", "").lower()
            or search_lower in d.get("name", "").lower()
        ]
    
    # Filter by FlareSolverr support
    if flaresolverr_only:
        defs = [
            d for d in defs
            if any(
                f.get("type") == "info_flaresolverr"
                or "flaresolverr" in f.get("label", "").lower()
                for f in d.get("fields", [])
            )
        ]
    
    if not defs:
        print("No definitions found matching criteria")
        return
    
    # Display as table
    headers = ["definitionName", "name", "flaresolverr"]
    rows = []
    for d in defs:
        has_flare = any(
            f.get("type") == "info_flaresolverr"
            or "flaresolverr" in f.get("label", "").lower()
            for f in d.get("fields", [])
        )
        rows.append({
            "definitionName": d.get("definitionName"),
            "name": d.get("name"),
            "flaresolverr": "✓" if has_flare else "",
        })
    
    print(f"Found {len(rows)} definition(s):")
    print_table(headers, rows)


def main():
    parser = argparse.ArgumentParser(
        description="Query available Prowlarr indexer definitions",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 query-definitions.py list
  python3 query-definitions.py list --search "1337x"
  python3 query-definitions.py list --search "torrent" --flaresolverr-only
        """,
    )
    
    subparsers = parser.add_subparsers(dest="command", help="Command to run")
    list_parser = subparsers.add_parser("list", help="List definitions")
    list_parser.add_argument("--search", default="", help="Search by name or definition name")
    list_parser.add_argument(
        "--flaresolverr-only",
        action="store_true",
        help="Only show definitions with FlareSolverr support",
    )
    
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
        list_definitions(api_key, search=args.search, flaresolverr_only=args.flaresolverr_only)


if __name__ == "__main__":
    main()
