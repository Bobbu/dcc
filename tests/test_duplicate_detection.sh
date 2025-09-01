#!/bin/bash

# Test script to verify duplicate detection functionality
set -e

USER_POOL_ID="us-east-1_ecyuILBAu"
CLIENT_ID="2idvhvlhgbheglr0hptel5j55"
BASE_URL="https://dcc.anystupididea.com"
TEST_USERNAME="test-verify-$(date +%s)@dcc-test.com"
TEST_PASSWORD="TempTestPass123!"

echo "🧪 Testing Duplicate Detection Claims"
echo "===================================="

# Create temp admin user
echo "1️⃣ Creating temporary admin user..."
aws cognito-idp admin-create-user \
    --user-pool-id $USER_POOL_ID \
    --username $TEST_USERNAME \
    --user-attributes Name=email,Value=$TEST_USERNAME \
    --temporary-password $TEST_PASSWORD \
    --message-action SUPPRESS >/dev/null 2>&1

aws cognito-idp admin-set-user-password \
    --user-pool-id $USER_POOL_ID \
    --username $TEST_USERNAME \
    --password $TEST_PASSWORD \
    --permanent >/dev/null 2>&1

aws cognito-idp admin-add-user-to-group \
    --user-pool-id $USER_POOL_ID \
    --username $TEST_USERNAME \
    --group-name Admins >/dev/null 2>&1

sleep 2

# Get auth token
echo "2️⃣ Getting authentication token..."
TOKEN=$(aws cognito-idp admin-initiate-auth \
    --user-pool-id $USER_POOL_ID \
    --client-id $CLIENT_ID \
    --auth-flow ADMIN_NO_SRP_AUTH \
    --auth-parameters USERNAME=$TEST_USERNAME,PASSWORD=$TEST_PASSWORD \
    --query 'AuthenticationResult.IdToken' \
    --output text)

# Test 1: Try to create a known duplicate
echo "3️⃣ Testing duplicate detection (should return 409)..."
echo "Attempting to create: 'Test quote for regression testing' by 'Test Author'"
response1=$(curl -s -w "\n%{http_code}" -X POST \
    "$BASE_URL/admin/quotes" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"quote": "Test quote for regression testing", "author": "Test Author", "tags": ["Testing"]}')

status1=$(echo "$response1" | tail -n 1)
body1=$(echo "$response1" | sed '$d')

echo "Status Code: $status1"
if [ "$status1" -eq 409 ]; then
    echo "✅ PASS: Duplicate detected correctly"
    duplicate_count=$(echo "$body1" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('duplicate_count', 0))" 2>/dev/null || echo "0")
    echo "   Found $duplicate_count similar quotes"
    echo "   Response: $body1" | head -c 200
    echo "..."
else
    echo "❌ FAIL: Expected 409, got $status1"
    echo "   Response: $body1"
fi

echo ""

# Test 2: Create a unique quote
echo "4️⃣ Testing unique quote creation (should return 201)..."
unique_quote="Unique verification quote created at $(date +%s)"
response2=$(curl -s -w "\n%{http_code}" -X POST \
    "$BASE_URL/admin/quotes" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"quote\": \"$unique_quote\", \"author\": \"Test Verifier\", \"tags\": [\"Verification\"]}")

status2=$(echo "$response2" | tail -n 1)
body2=$(echo "$response2" | sed '$d')

echo "Status Code: $status2"
if [ "$status2" -eq 201 ]; then
    echo "✅ PASS: Unique quote created successfully"
    quote_id=$(echo "$body2" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data['quote']['id'])" 2>/dev/null || echo "ERROR")
    echo "   Created quote ID: $quote_id"
    
    # Clean up: delete the test quote
    if [ "$quote_id" != "ERROR" ]; then
        echo "   Cleaning up test quote..."
        curl -s -X DELETE \
            "$BASE_URL/admin/quotes/$quote_id" \
            -H "Authorization: Bearer $TOKEN" >/dev/null 2>&1
    fi
else
    echo "❌ FAIL: Expected 201, got $status2"
    echo "   Response: $body2"
fi

echo ""

# Test 3: Test soft matching with variations
echo "5️⃣ Testing soft matching with punctuation variations..."
response3=$(curl -s -w "\n%{http_code}" -X POST \
    "$BASE_URL/admin/quotes" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"quote": "Test quote for regression testing.", "author": "Test Author", "tags": ["Testing"]}')

status3=$(echo "$response3" | tail -n 1)
echo "Status Code: $status3"
if [ "$status3" -eq 409 ]; then
    echo "✅ PASS: Soft matching works (detected punctuation variation)"
else
    echo "❌ FAIL: Soft matching failed, got $status3"
fi

echo ""

# Cleanup
echo "6️⃣ Cleaning up temporary user..."
aws cognito-idp admin-delete-user \
    --user-pool-id $USER_POOL_ID \
    --username $TEST_USERNAME >/dev/null 2>&1

echo "✅ Cleanup complete"
echo ""
echo "🎯 Summary:"
echo "   - Duplicate detection: $([ "$status1" -eq 409 ] && echo "✅ WORKING" || echo "❌ FAILED")"
echo "   - Unique creation: $([ "$status2" -eq 201 ] && echo "✅ WORKING" || echo "❌ FAILED")"  
echo "   - Soft matching: $([ "$status3" -eq 409 ] && echo "✅ WORKING" || echo "❌ FAILED")"