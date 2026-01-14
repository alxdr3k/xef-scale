"""
API integration test for Feature 3: Filtered Total Amount API.

This script verifies that the TransactionListResponse schema correctly
includes the total_amount field and that it's properly serialized.
"""

import sys
import os

# Add project root to Python path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from backend.api.schemas import TransactionListResponse, TransactionResponse


def test_schema_includes_total_amount():
    """Test that TransactionListResponse schema includes total_amount field."""
    print("Testing Feature 3: API Schema Validation")
    print("=" * 60)

    # Create a sample response
    sample_transaction = TransactionResponse(
        id=1,
        date="2025.01.10",
        category="식비",
        merchant_name="Test Merchant",
        amount=10000,
        institution="Test Card",
        transaction_year=2025,
        transaction_month=1,
        category_id=1,
        institution_id=1,
        created_at="2025-01-10T10:00:00Z"
    )

    # Create TransactionListResponse with all required fields including total_amount
    response = TransactionListResponse(
        data=[sample_transaction],
        total=100,
        page=1,
        limit=50,
        total_pages=2,
        total_amount=1234567  # NEW FIELD
    )

    print("\nTest 1: Schema validation")
    print(f"✓ TransactionListResponse created successfully")
    print(f"  - total (count): {response.total}")
    print(f"  - total_amount (sum): {response.total_amount:,}원")

    # Test serialization
    print("\nTest 2: JSON serialization")
    response_dict = response.model_dump()
    print(f"✓ Serialized to dict successfully")

    # Verify total_amount is in the output
    if 'total_amount' in response_dict:
        print(f"✓ PASS: 'total_amount' field present in serialized response")
        print(f"  Value: {response_dict['total_amount']:,}원")
    else:
        print(f"✗ FAIL: 'total_amount' field missing from serialized response")
        print(f"  Available fields: {list(response_dict.keys())}")
        return False

    # Test that both 'total' and 'total_amount' are different concepts
    print("\nTest 3: Field semantics")
    print(f"  - 'total' (transaction count): {response.total}")
    print(f"  - 'total_amount' (sum of amounts): {response.total_amount:,}원")
    if response.total != response.total_amount:
        print(f"✓ PASS: 'total' and 'total_amount' are distinct fields")
    else:
        print(f"⚠ WARNING: 'total' and 'total_amount' have the same value")
        print(f"  This is coincidental; they represent different concepts")

    # Test JSON export
    print("\nTest 4: JSON export compatibility")
    json_str = response.model_dump_json()
    print(f"✓ Exported to JSON string successfully")
    print(f"  Length: {len(json_str)} bytes")

    import json
    parsed = json.loads(json_str)
    if 'total_amount' in parsed:
        print(f"✓ PASS: 'total_amount' preserved in JSON export")
    else:
        print(f"✗ FAIL: 'total_amount' lost in JSON export")
        return False

    # Verify schema documentation
    print("\nTest 5: Schema documentation")
    schema = TransactionListResponse.model_json_schema()
    if 'total_amount' in schema['properties']:
        print(f"✓ PASS: 'total_amount' documented in JSON schema")
        total_amount_schema = schema['properties']['total_amount']
        print(f"  Type: {total_amount_schema.get('type', 'N/A')}")
        print(f"  Title: {total_amount_schema.get('title', 'N/A')}")
    else:
        print(f"✗ FAIL: 'total_amount' not documented in JSON schema")
        print(f"  Available properties: {list(schema['properties'].keys())}")
        return False

    print("\n" + "=" * 60)
    print("Feature 3 API schema testing complete!")
    print("\nSummary:")
    print("✓ TransactionListResponse includes 'total_amount' field")
    print("✓ Field is properly serialized to JSON")
    print("✓ Field is documented in JSON schema")
    print("✓ Backend is ready for frontend integration")

    return True


if __name__ == "__main__":
    try:
        success = test_schema_includes_total_amount()
        sys.exit(0 if success else 1)
    except Exception as e:
        print(f"\n✗ ERROR: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
