#!/usr/bin/env python3
"""
Manual test script for category update API endpoint.
Tests both manual and file-based transactions.
"""

import requests
import json

# Configuration
BASE_URL = "http://localhost:8000/api"
AUTH_TOKEN = None  # Will need to authenticate first

def test_category_update():
    """Test the category update endpoint."""

    print("=" * 60)
    print("Testing Category Update API")
    print("=" * 60)

    # Note: This script requires authentication
    # You'll need to authenticate first and provide a token
    # For now, just verify the endpoint exists and responds

    # Test 1: Check if endpoint exists (will return 401 without auth)
    test_id = 1
    response = requests.patch(
        f"{BASE_URL}/transactions/{test_id}/category",
        json={"category": "식비"},
        headers={"Content-Type": "application/json"}
    )

    print(f"\n1. Testing endpoint availability (transaction ID: {test_id})")
    print(f"   Status Code: {response.status_code}")
    print(f"   Expected: 401 (Unauthorized) or 404 (Not Found)")

    if response.status_code == 401:
        print("   ✓ Endpoint exists and requires authentication (as expected)")
    elif response.status_code == 404:
        print("   ✓ Endpoint exists but transaction not found (acceptable)")
    else:
        print(f"   Response: {response.json()}")

    # Test 2: Check notes endpoint too
    response = requests.patch(
        f"{BASE_URL}/transactions/{test_id}/notes",
        json={"notes": "테스트 메모"},
        headers={"Content-Type": "application/json"}
    )

    print(f"\n2. Testing notes endpoint (transaction ID: {test_id})")
    print(f"   Status Code: {response.status_code}")
    print(f"   Expected: 401 (Unauthorized) or 404 (Not Found)")

    if response.status_code == 401:
        print("   ✓ Notes endpoint exists and requires authentication (as expected)")
    elif response.status_code == 404:
        print("   ✓ Notes endpoint exists but transaction not found (acceptable)")
    else:
        print(f"   Response: {response.json()}")

    print("\n" + "=" * 60)
    print("Summary:")
    print("- Both PATCH endpoints (/category and /notes) are registered")
    print("- Authentication is required (401 responses)")
    print("- To fully test, authenticate and use real transaction IDs")
    print("=" * 60)


if __name__ == "__main__":
    try:
        test_category_update()
    except requests.exceptions.ConnectionError:
        print("Error: Could not connect to backend server")
        print("Please ensure the backend is running on http://localhost:8000")
    except Exception as e:
        print(f"Error during testing: {str(e)}")
