#!/bin/bash

# Test script for candidate quotes endpoint
# Creates temporary admin user, tests the endpoint, then cleans up

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 Testing Candidate Quotes Endpoint${NC}"
echo "=================================="

# Get CloudFormation outputs
echo -e "${YELLOW}📋 Getting CloudFormation stack outputs...${NC}"
USER_POOL_ID=$(aws cloudformation describe-stacks --stack-name dcc-demo-sam-app --query "Stacks[0].Outputs[?OutputKey=='UserPoolId'].OutputValue" --output text)
CLIENT_ID=$(aws cloudformation describe-stacks --stack-name dcc-demo-sam-app --query "Stacks[0].Outputs[?OutputKey=='UserPoolClientId'].OutputValue" --output text)
CUSTOM_DOMAIN_URL=$(aws cloudformation describe-stacks --stack-name dcc-demo-sam-app --query "Stacks[0].Outputs[?OutputKey=='CustomDomainUrl'].OutputValue" --output text)

if [ -z "$USER_POOL_ID" ] || [ -z "$CLIENT_ID" ] || [ -z "$CUSTOM_DOMAIN_URL" ]; then
    echo -e "${RED}❌ Failed to get CloudFormation outputs${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Stack outputs retrieved${NC}"
echo "   User Pool ID: $USER_POOL_ID"
echo "   Client ID: $CLIENT_ID"
echo "   API URL: $CUSTOM_DOMAIN_URL"

# Generate unique test user email
TIMESTAMP=$(date +%s)
TEST_EMAIL="test-quotes-$TIMESTAMP@example.com"
TEST_PASSWORD="TempPass123!"

echo ""
echo -e "${YELLOW}👤 Creating temporary test user...${NC}"

# Create test user
aws cognito-idp admin-create-user \
    --user-pool-id "$USER_POOL_ID" \
    --username "$TEST_EMAIL" \
    --user-attributes Name=email,Value="$TEST_EMAIL" Name=email_verified,Value=true \
    --temporary-password "$TEST_PASSWORD" \
    --message-action SUPPRESS > /dev/null

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to create test user${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Test user created: $TEST_EMAIL${NC}"

# Set permanent password
echo -e "${YELLOW}🔐 Setting permanent password...${NC}"
aws cognito-idp admin-set-user-password \
    --user-pool-id "$USER_POOL_ID" \
    --username "$TEST_EMAIL" \
    --password "$TEST_PASSWORD" \
    --permanent > /dev/null

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to set permanent password${NC}"
    # Cleanup
    aws cognito-idp admin-delete-user --user-pool-id "$USER_POOL_ID" --username "$TEST_EMAIL" > /dev/null
    exit 1
fi

# Add user to Admins group
echo -e "${YELLOW}👥 Adding user to Admins group...${NC}"
aws cognito-idp admin-add-user-to-group \
    --user-pool-id "$USER_POOL_ID" \
    --username "$TEST_EMAIL" \
    --group-name "Admins" > /dev/null

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to add user to Admins group${NC}"
    # Cleanup
    aws cognito-idp admin-delete-user --user-pool-id "$USER_POOL_ID" --username "$TEST_EMAIL" > /dev/null
    exit 1
fi

echo -e "${GREEN}✅ User added to Admins group${NC}"

# Authenticate and get JWT token
echo -e "${YELLOW}🔑 Authenticating user...${NC}"
AUTH_RESPONSE=$(aws cognito-idp initiate-auth \
    --client-id "$CLIENT_ID" \
    --auth-flow USER_PASSWORD_AUTH \
    --auth-parameters USERNAME="$TEST_EMAIL",PASSWORD="$TEST_PASSWORD" 2>/dev/null)

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Authentication failed${NC}"
    # Cleanup
    aws cognito-idp admin-delete-user --user-pool-id "$USER_POOL_ID" --username "$TEST_EMAIL" > /dev/null
    exit 1
fi

ID_TOKEN=$(echo "$AUTH_RESPONSE" | jq -r '.AuthenticationResult.IdToken')

if [ -z "$ID_TOKEN" ] || [ "$ID_TOKEN" = "null" ]; then
    echo -e "${RED}❌ Failed to get ID token${NC}"
    # Cleanup
    aws cognito-idp admin-delete-user --user-pool-id "$USER_POOL_ID" --username "$TEST_EMAIL" > /dev/null
    exit 1
fi

echo -e "${GREEN}✅ Authentication successful${NC}"

# Test the candidate quotes endpoint
echo ""
echo -e "${BLUE}🧪 Testing candidate quotes endpoint...${NC}"
echo -e "${YELLOW}📝 Fetching quotes for 'Albert Einstein'...${NC}"

ENDPOINT_URL="$CUSTOM_DOMAIN_URL/admin/candidate-quotes"
RESPONSE=$(curl -s -w "%{http_code}" \
    -H "Authorization: Bearer $ID_TOKEN" \
    -H "Content-Type: application/json" \
    "$ENDPOINT_URL?author=Albert%20Einstein")

# Extract HTTP status code (last 3 characters)
HTTP_CODE="${RESPONSE: -3}"
# Extract response body (all but last 3 characters)
RESPONSE_BODY="${RESPONSE%???}"

echo -e "${YELLOW}📡 HTTP Status: $HTTP_CODE${NC}"

if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✅ API call successful!${NC}"
    echo ""
    echo -e "${BLUE}📖 Response:${NC}"
    echo "$RESPONSE_BODY" | jq '.'
    
    # Extract and display quote count
    QUOTE_COUNT=$(echo "$RESPONSE_BODY" | jq -r '.count // 0')
    echo ""
    echo -e "${GREEN}✅ Successfully retrieved $QUOTE_COUNT candidate quotes${NC}"
    
    # Display first quote as sample
    if [ "$QUOTE_COUNT" -gt 0 ]; then
        echo ""
        echo -e "${BLUE}📝 Sample quote:${NC}"
        FIRST_QUOTE=$(echo "$RESPONSE_BODY" | jq -r '.quotes[0].quote // "No quote found"')
        FIRST_SOURCE=$(echo "$RESPONSE_BODY" | jq -r '.quotes[0].source // "No source"')
        FIRST_CONFIDENCE=$(echo "$RESPONSE_BODY" | jq -r '.quotes[0].confidence // "unknown"')
        echo -e "   Quote: \"$FIRST_QUOTE\""
        echo -e "   Source: $FIRST_SOURCE"
        echo -e "   Confidence: $FIRST_CONFIDENCE"
    fi
else
    echo -e "${RED}❌ API call failed${NC}"
    echo -e "${RED}Response: $RESPONSE_BODY${NC}"
    
    # Try to parse error message
    ERROR_MSG=$(echo "$RESPONSE_BODY" | jq -r '.error // .message // "Unknown error"' 2>/dev/null || echo "Unknown error")
    echo -e "${RED}Error: $ERROR_MSG${NC}"
fi

# Cleanup: Delete the test user
echo ""
echo -e "${YELLOW}🧹 Cleaning up test user...${NC}"
aws cognito-idp admin-delete-user \
    --user-pool-id "$USER_POOL_ID" \
    --username "$TEST_EMAIL" > /dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Test user deleted${NC}"
else
    echo -e "${YELLOW}⚠️  Warning: Failed to delete test user $TEST_EMAIL${NC}"
fi

echo ""
if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}🎉 Candidate quotes endpoint test PASSED!${NC}"
    exit 0
else
    echo -e "${RED}💥 Candidate quotes endpoint test FAILED!${NC}"
    exit 1
fi