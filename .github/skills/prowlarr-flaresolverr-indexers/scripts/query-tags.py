#!/usr/bin/env python3
"""
Manage Prowlarr tags.

Usage:
  python3 query-tags.py list                    # List all tags
  python3 query-tags.py create <label>          # Create a new tag
  python3 query-tags.py delete <tag_id>         # Delete a tag
  python3 query-tags.py --help                  # Show help
"""
import argparse
import json
import sys
from pathlib import Path

# Add parent directory to path for prowlarr_utils import
sys.path.insert(0, str(Path(__file__).parent))
from prowlarr_utils import api_request, load_api_key, print_json, print_table


def list_tags(api_key: str) -> None:
    """List all tags."""
    status, data = api_request("GET", "/tag", api_key)
    if status != 200:
        print(f"Error fetching tags: HTTP {status}")
        print_json(data)
        return
    
    if not data:
        print("No tags found")
        return
    
    headers = ["id", "label"]
    rows = [{"id": t.get("id"), "label": t.get("label")} for t in data]
    print_table(headers, rows)


def create_tag(api_key: str, label: str) -> None:
    """Create a new tag."""
    payload = {"label": label}
    
    try:
        status, data = api_request("POST", "/tag", api_key, body=payload)
    except Exception as e:
        print(f"Error creating tag: {e}")
        return
    
    if status in [200, 201]:
        print(f"✓ Created tag: id={data.get('id')} label={data.get('label')}")
    else:
        print(f"✗ Failed to create tag (HTTP {status})")
        print_json(data)


def delete_tag(api_key: str, tag_id: int) -> None:
    """Delete a tag by ID."""
    try:
        status, data = api_request("DELETE", f"/tag/{tag_id}", api_key)
    except Exception as e:
        print(f"Error deleting tag: {e}")
        return
    
    if status in [200, 204]:
        print(f"✓ Deleted tag id={tag_id}")
    else:
        print(f"✗ Failed to delete tag (HTTP {status})")
        if data:
            print_json(data)


def main():
    parser = argparse.ArgumentParser(
        description="Manage Prowlarr tags",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 query-tags.py list
  python3 query-tags.py create flaresolverr
  python3 query-tags.py delete 1
        """,
    )
    
    subparsers = parser.add_subparsers(dest="command", help="Command to run")
    subparsers.add_parser("list", help="List all tags")
    
    create_parser = subparsers.add_parser("create", help="Create a new tag")
    create_parser.add_argument("label", help="Tag label (e.g., 'flaresolverr')")
    
    delete_parser = subparsers.add_parser("delete", help="Delete a tag")
    delete_parser.add_argument("tag_id", type=int, help="Tag ID to delete")
    
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
        list_tags(api_key)
    elif args.command == "create":
        create_tag(api_key, args.label)
    elif args.command == "delete":
        delete_tag(api_key, args.tag_id)


if __name__ == "__main__":
    main()
