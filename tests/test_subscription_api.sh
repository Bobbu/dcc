#!/bin/bash

# Test script to check subscription API endpoints
set -e

USER_POOL_ID="us-east-1_ecyuILBAu"
CLIENT_ID="2idvhvlhgbheglr0hptel5j55"
BASE_URL="https://dcc.anystupididea.com"

echo "🧪 Testing Daily Nuggets Subscription API"
echo "========================================"

# Test with admin user
echo "1️⃣ Testing with admin@dcc.com..."
echo ""

ADMIN_TOKEN=$(aws cognito-idp admin-initiate-auth \
    --user-pool-id $USER_POOL_ID \
    --client-id $CLIENT_ID \
    --auth-flow ADMIN_NO_SRP_AUTH \
    --auth-parameters USERNAME=admin@dcc.com,PASSWORD=AdminPass123! \
    --query 'AuthenticationResult.IdToken' \
    --output text 2>/dev/null)

if [ ! -z "$ADMIN_TOKEN" ] && [ "$ADMIN_TOKEN" != "None" ]; then
    echo "✅ Admin authentication successful"
    
    echo "📡 Getting admin subscription..."
    response=$(curl -s -w "\n%{http_code}" -X GET \
        "$BASE_URL/subscriptions" \
        -H "Authorization: Bearer $ADMIN_TOKEN" \
        -H "Content-Type: application/json")
    
    status=$(echo "$response" | tail -n 1)
    body=$(echo "$response" | sed '$d')
    
    echo "Status: $status"
    echo "Response: $body"
    
    if [ "$status" -eq 404 ]; then
        echo "❌ No subscription found for admin@dcc.com (as expected)"
        echo ""
        echo "📝 Creating subscription for admin..."
        create_response=$(curl -s -w "\n%{http_code}" -X PUT \
            "$BASE_URL/subscriptions" \
            -H "Authorization: Bearer $ADMIN_TOKEN" \
            -H "Content-Type: application/json" \
            -d '{"is_subscribed": true, "delivery_method": "email", "timezone": "America/New_York"}')
        
        create_status=$(echo "$create_response" | tail -n 1)
        create_body=$(echo "$create_response" | sed '$d')
        
        echo "Create Status: $create_status"
        echo "Create Response: $create_body"
    fi
    
else
    echo "❌ Admin authentication failed"
fi

echo ""
echo "2️⃣ Testing with rob@catalyst.technology (if possible)..."
echo "This would require the password for that account."