#!/usr/bin/env python3
"""
Query and manage Prowlarr indexer instances.

Usage:
  python3 query-indexers.py list                              # List all indexer instances
  python3 query-indexers.py list --filter tag=1               # Filter by tag ID
  python3 query-indexers.py list --filter enabled=True        # Filter by enabled status
  python3 query-indexers.py show <indexer_id>                 # Show detailed info
  python3 query-indexers.py --help                            # Show help
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from prowlarr_utils import api_request, load_api_key, print_json, print_table


def parse_filter(filter_str: str) -> tuple:
    """Parse filter string like 'tag=1' into (key, value)."""
    if "=" not in filter_str:
        raise ValueError(f"Invalid filter format: {filter_str}. Use key=value")
    key, val = filter_str.split("=", 1)
    # Try to parse as int or bool
    if val.lower() in ("true", "false"):
        val = val.lower() == "true"
    elif val.isdigit():
        val = int(val)
    return key, val


def matches_filter(indexer: dict, key: str, value) -> bool:
    """Check if indexer matches filter criteria."""
    if key == "tag":
        return value in indexer.get("tags", [])
    elif key == "enabled":
        return indexer.get("enable") == value
    elif key == "name":
        return value.lower() in indexer.get("name", "").lower()
    elif key == "definition":
        return indexer.get("definitionName") == value
    else:
        return indexer.get(key) == value


def list_indexers(api_key: str, filter_str: str = "") -> None:
    """List indexer instances with optional filter."""
    status, data = api_request("GET", "/indexer", api_key)
    if status != 200:
        print(f"Error fetching indexers: HTTP {status}")
        print_json(data)
        return
    
    if not data:
        print("No indexers found")
        return
    
    # Apply filter
    if filter_str:
        try:
            key, val = parse_filter(filter_str)
            data = [i for i in data if matches_filter(i, key, val)]
        except ValueError as e:
            print(f"Error: {e}")
            return
    
    # Display as table
    headers = ["id", "name", "definition", "enabled", "tags"]
    rows = [
        {
            "id": i.get("id"),
            "name": i.get("name"),
            "definition": i.get("definitionName"),
            "enabled": i.get("enable"),
            "tags": i.get("tags", []),
        }
        for i in data
    ]
    
    print(f"Found {len(rows)} indexer(s):")
    print_table(headers, rows)


def show_indexer(api_key: str, indexer_id: int) -> None:
    """Show detailed information about an indexer."""
    status, data = api_request("GET", f"/indexer/{indexer_id}", api_key)
    if status != 200:
        print(f"Error fetching indexer {indexer_id}: HTTP {status}")
        print_json(data)
        return
    
    print(f"Indexer ID {indexer_id}:")
    print(f"  Name: {data.get('name')}")
    print(f"  Definition: {data.get('definitionName')}")
    print(f"  Enabled: {data.get('enable')}")
    print(f"  Tags: {data.get('tags', [])}")
    print(f"  Priority: {data.get('priority')}")
    print(f"  Added: {data.get('added')}")
    print(f"  Implementation: {data.get('implementation')}")
    print(f"  Download Client: {data.get('downloadClientId')}")
    
    # Show fields with non-default values
    fields = data.get("fields", [])
    if fields:
        print(f"\n  Configuration fields:")
        for field in fields:
            val = field.get("value")
            if val and val != field.get("defaultValue"):
                print(f"    {field.get('name')}: {val}")


def main():
    parser = argparse.ArgumentParser(
        description="Query Prowlarr indexer instances",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 query-indexers.py list
  python3 query-indexers.py list --filter tag=1
  python3 query-indexers.py list --filter enabled=True
  python3 query-indexers.py list --filter name=1337x
  python3 query-indexers.py show 21
        """,
    )
    
    subparsers = parser.add_subparsers(dest="command", help="Command to run")
    list_parser = subparsers.add_parser("list", help="List indexer instances")
    list_parser.add_argument(
        "--filter",
        default="",
        help="Filter by field (e.g., 'tag=1', 'enabled=True', 'name=1337x')",
    )
    
    show_parser = subparsers.add_parser("show", help="Show indexer details")
    show_parser.add_argument("indexer_id", type=int, help="Indexer ID")
    
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
        list_indexers(api_key, filter_str=args.filter)
    elif args.command == "show":
        show_indexer(api_key, args.indexer_id)


if __name__ == "__main__":
    main()
