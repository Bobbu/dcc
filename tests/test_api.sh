#!/bin/bash
#
# Essentially, using this form:
# $ curl -H "x-api-key: $API_KEY" $API_ENDPOINT
#
# Test script for DCC Quote API
# Load environment variables
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
else
    echo "❌ Error: .env file not found. Please copy .env.sample to .env and configure your API settings."
    exit 1
fi

echo "Testing DCC Quote API..."
echo "Endpoint: $API_ENDPOINT"
echo "API Key: ${API_KEY:0:8}..."
echo ""

# Test 1: Basic GET request
echo "=== Test 1: Basic GET Request ==="
response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -H "x-api-key: $API_KEY" "$API_ENDPOINT")
http_status=$(echo "$response" | tail -n 1 | cut -d: -f2)
body=$(echo "$response" | head -n -1)

echo "HTTP Status: $http_status"
echo "Response Body:"
echo "$body" | jq . 2>/dev/null || echo "$body"
echo ""

if [ "$http_status" -eq 200 ]; then
    echo "✅ Test 1 PASSED: API returned 200 OK"
else
    echo "❌ Test 1 FAILED: Expected 200, got $http_status"
fi
echo ""

# Test 2: Multiple requests to verify randomness
echo "=== Test 2: Multiple Requests (checking for variety) ==="
quotes=()
for i in {1..3}; do
    echo "Request $i:"
    response=$(curl -s -H "x-api-key: $API_KEY" "$API_ENDPOINT")
    quote=$(echo "$response" | jq -r '.quote' 2>/dev/null || echo "Failed to parse")
    author=$(echo "$response" | jq -r '.author' 2>/dev/null || echo "Failed to parse")
    echo "  Quote: \"$quote\""
    echo "  Author: $author"
    quotes+=("$quote")
    echo ""
done

# Check if we got different quotes (basic randomness check)
unique_quotes=$(printf '%s\n' "${quotes[@]}" | sort -u | wc -l)
total_quotes=${#quotes[@]}

if [ "$unique_quotes" -gt 1 ]; then
    echo "✅ Test 2 PASSED: Got $unique_quotes different quotes out of $total_quotes requests"
else
    echo "ℹ️  Test 2 INFO: All quotes were the same (may be random chance)"
fi
echo ""

# Test 3: Response structure validation
echo "=== Test 3: Response Structure Validation ==="
response=$(curl -s -H "x-api-key: $API_KEY" "$API_ENDPOINT")

# Check if response contains required fields
if echo "$response" | jq -e '.quote and .author' >/dev/null 2>&1; then
    echo "✅ Test 3 PASSED: Response contains required 'quote' and 'author' fields"
    
    quote_length=$(echo "$response" | jq -r '.quote' | wc -c)
    author_length=$(echo "$response" | jq -r '.author' | wc -c)
    
    echo "  Quote length: $quote_length characters"
    echo "  Author length: $author_length characters"
else
    echo "❌ Test 3 FAILED: Response missing required fields"
    echo "  Response: $response"
fi
echo ""

# Test 4: Rate limiting test
echo "=== Test 4: Rate Limiting Test ==="
echo "Making 8 rapid requests to test rate limits (1/sec sustained, 5/sec burst)..."

rate_limit_errors=0
successful_requests=0

for i in {1..8}; do
    echo -n "Request $i: "
    response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -H "x-api-key: $API_KEY" "$API_ENDPOINT")
    http_status=$(echo "$response" | tail -n 1 | cut -d: -f2)
    body=$(echo "$response" | head -n -1)
    
    if [ "$http_status" -eq 200 ]; then
        quote=$(echo "$body" | jq -r '.quote' 2>/dev/null | cut -c1-50)
        echo "✅ Success - \"$quote...\""
        successful_requests=$((successful_requests + 1))
    elif [ "$http_status" -eq 429 ]; then
        echo "🚫 Rate Limited (HTTP 429)"
        rate_limit_errors=$((rate_limit_errors + 1))
    else
        echo "❌ Error (HTTP $http_status)"
    fi
    
    # Small delay between requests
    sleep 0.1
done

echo ""
echo "Results:"
echo "  Successful requests: $successful_requests"
echo "  Rate limited requests: $rate_limit_errors"

if [ "$rate_limit_errors" -gt 0 ]; then
    echo "✅ Test 4 PASSED: Rate limiting is working - blocked $rate_limit_errors requests"
else
    echo "ℹ️  Test 4 INFO: No rate limiting observed (may need more rapid requests)"
fi
echo ""

echo "=== API Testing Complete ==="