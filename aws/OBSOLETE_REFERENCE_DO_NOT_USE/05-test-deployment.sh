#!/bin/bash

# Step 5: Integration Testing
# Tests: API endpoints, authentication, image generation, notifications
# Target time: < 30 seconds

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== STEP 5: INTEGRATION TESTING ===${NC}"
echo "Running automated tests to verify deployment"
echo ""

# Get API URL
API_URL=$(aws cloudformation describe-stacks --stack-name dcc-core-api --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' --output text 2>/dev/null)

if [ -z "$API_URL" ] || [ "$API_URL" = "None" ]; then
    echo -e "${RED}✗ Could not get API URL${NC}"
    exit 1
fi

echo -e "${YELLOW}Testing API URL: $API_URL${NC}"

# Test 1: Health check (random quote)
echo -n "Testing quote endpoint... "
QUOTE_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$API_URL/quote" || echo "000")
if [ "$QUOTE_RESPONSE" = "200" ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ (HTTP $QUOTE_RESPONSE)${NC}"
    exit 1
fi

# Test 2: Tags endpoint
echo -n "Testing tags endpoint... "
TAGS_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$API_URL/tags" || echo "000")
if [ "$TAGS_RESPONSE" = "200" ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ (HTTP $TAGS_RESPONSE)${NC}"
    exit 1
fi

# Test 3: CORS (OPTIONS request)
echo -n "Testing CORS support... "
CORS_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X OPTIONS "$API_URL/quote" || echo "000")
if [ "$CORS_RESPONSE" = "200" ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ (HTTP $CORS_RESPONSE)${NC}"
    exit 1
fi

# Test 4: S3 bucket accessibility
echo -n "Testing S3 bucket... "
S3_BUCKET=$(aws cloudformation describe-stacks --stack-name dcc-infrastructure --query 'Stacks[0].Outputs[?OutputKey==`QuoteImagesBucketName`].OutputValue' --output text 2>/dev/null)
if aws s3 ls s3://$S3_BUCKET/ > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    exit 1
fi

# Test 5: DynamoDB table accessibility
echo -n "Testing DynamoDB tables... "
QUOTES_TABLE=$(aws cloudformation describe-stacks --stack-name dcc-infrastructure --query 'Stacks[0].Outputs[?OutputKey==`QuotesTableName`].OutputValue' --output text 2>/dev/null)
if aws dynamodb describe-table --table-name $QUOTES_TABLE > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    exit 1
fi

# Test 6: Authentication endpoints
echo -n "Testing auth endpoints... "
AUTH_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$API_URL/auth/register" -X POST -H "Content-Type: application/json" -d '{}' || echo "000")
if [ "$AUTH_RESPONSE" = "400" ] || [ "$AUTH_RESPONSE" = "422" ]; then
    # 400/422 is expected for empty request - means endpoint is working
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ (HTTP $AUTH_RESPONSE)${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✓ All integration tests passed!${NC}"
echo ""

# Display final system summary
echo -e "${YELLOW}=== DEPLOYMENT SUMMARY ===${NC}"
echo "API URL: $API_URL"
echo "Images Bucket: $S3_BUCKET"
echo "Quotes Table: $QUOTES_TABLE"

# Check if image generation is available
IMAGE_QUEUE=$(aws cloudformation describe-stacks --stack-name dcc-infrastructure --query 'Stacks[0].Outputs[?OutputKey==`ImageGenerationQueueUrl`].OutputValue' --output text 2>/dev/null)
if [ -n "$IMAGE_QUEUE" ] && [ "$IMAGE_QUEUE" != "None" ]; then
    echo "Image Generation: Available"
else
    echo "Image Generation: Not configured"
fi

# Check if push notifications are available
FCM_CHECK=$(aws cloudformation describe-stacks --stack-name dcc-services --query 'Stacks[0].Parameters[?ParameterKey==`FCMServiceAccountJSON`].ParameterValue' --output text 2>/dev/null)
if [ -n "$FCM_CHECK" ] && [ "$FCM_CHECK" != "None" ]; then
    echo "Push Notifications: Enabled"
else
    echo "Push Notifications: Disabled"
fi

echo ""
echo -e "${GREEN}System ready for use!${NC}"