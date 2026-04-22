#!/usr/bin/env python3
"""
Remove an indexer instance from Prowlarr.

Usage:
  python3 remove-indexer.py 20
  python3 remove-indexer.py --help
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from prowlarr_utils import api_request, load_api_key, print_json


def remove_indexer(api_key: str, indexer_id: int, force: bool = False) -> None:
    """Remove an indexer instance by ID."""
    
    # Get indexer details first
    status, indexer = api_request("GET", f"/indexer/{indexer_id}", api_key)
    if status != 200:
        print(f"Error fetching indexer {indexer_id}: HTTP {status}")
        return
    
    # Confirm deletion
    if not force:
        name = indexer.get("name", f"ID {indexer_id}")
        response = input(f"Delete indexer '{name}' (id={indexer_id})? (yes/no): ").strip().lower()
        if response not in ("yes", "y"):
            print("Cancelled")
            return
    
    # DELETE
    try:
        status, data = api_request("DELETE", f"/indexer/{indexer_id}", api_key)
    except Exception as e:
        print(f"Error deleting indexer: {e}")
        return
    
    if status in [200, 204]:
        print(f"✓ Deleted indexer id={indexer_id}")
    else:
        print(f"✗ Failed to delete indexer (HTTP {status})")
        if data:
            print_json(data)


def main():
    parser = argparse.ArgumentParser(
        description="Remove an indexer instance from Prowlarr",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 remove-indexer.py 20
  python3 remove-indexer.py 21 --force
        """,
    )
    
    parser.add_argument("indexer_id", type=int, help="Indexer ID to delete")
    parser.add_argument(
        "--force",
        action="store_true",
        help="Skip confirmation prompt",
    )
    
    args = parser.parse_args()
    
    try:
        api_key = load_api_key()
    except (FileNotFoundError, ValueError) as e:
        print(f"Error: {e}")
        sys.exit(1)
    
    remove_indexer(api_key, args.indexer_id, force=args.force)


if __name__ == "__main__":
    main()
