#!/bin/bash

# Post-deployment script to configure API and restore data
# Run this after deploy-complete.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== POST-DEPLOYMENT CONFIGURATION ===${NC}"
echo ""

# Get stack outputs
API_URL=$(aws cloudformation describe-stacks \
    --stack-name dcc-api-complete \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' \
    --output text)

if [ -z "$API_URL" ] || [ "$API_URL" = "None" ]; then
    echo -e "${RED}Error: Stack not found or not deployed${NC}"
    exit 1
fi

# Get API ID
API_ID=$(aws apigateway get-rest-apis --query 'items[?name==`dcc-api`].id' --output text)

# Setup API key and usage plan
echo -e "${YELLOW}Setting up API key and usage plan...${NC}"

# Check for existing API key
API_KEY_ID=$(aws apigateway get-api-keys --query "items[?stageKeys[?contains(@, '$API_ID')]].id" --output text | head -1)

if [ -z "$API_KEY_ID" ]; then
    # Create API key
    echo "Creating new API key..."
    API_KEY_RESULT=$(aws apigateway create-api-key --name dcc-api-key --enabled --stage-keys restApiId=$API_ID,stageName=prod)
    API_KEY_ID=$(echo "$API_KEY_RESULT" | jq -r '.id')
    API_KEY_VALUE=$(echo "$API_KEY_RESULT" | jq -r '.value')
    
    # Create usage plan
    echo "Creating usage plan..."
    USAGE_PLAN_ID=$(aws apigateway create-usage-plan \
        --name dcc-usage-plan \
        --description "Usage plan for DCC API" \
        --throttle rateLimit=10,burstLimit=20 \
        --quota limit=1000,period=DAY \
        --api-stages apiId=$API_ID,stage=prod \
        --query 'id' --output text)
    
    # Associate API key with usage plan
    aws apigateway create-usage-plan-key \
        --usage-plan-id $USAGE_PLAN_ID \
        --key-id $API_KEY_ID \
        --key-type API_KEY > /dev/null
    
    echo -e "${GREEN}✓ API key and usage plan configured${NC}"
else
    API_KEY_VALUE=$(aws apigateway get-api-key --api-key $API_KEY_ID --include-value --query value --output text)
    echo -e "${GREEN}✓ Using existing API key${NC}"
fi

# Test the API
echo ""
echo -e "${YELLOW}Testing API...${NC}"
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$API_URL/quote" -H "x-api-key: $API_KEY_VALUE")

if [ "$RESPONSE" = "200" ]; then
    echo -e "${GREEN}✓ API is working!${NC}"
else
    echo -e "${YELLOW}⚠ API returned status $RESPONSE (might need data)${NC}"
fi

# Check if data needs to be restored
echo ""
echo -e "${YELLOW}Checking data...${NC}"
QUOTES_TABLE=$(aws cloudformation describe-stacks \
    --stack-name dcc-api-complete \
    --query 'Stacks[0].Outputs[?OutputKey==`QuotesTableName`].OutputValue' \
    --output text)

ITEM_COUNT=$(aws dynamodb scan --table-name $QUOTES_TABLE --select COUNT --query Count --output text 2>/dev/null || echo "0")

if [ "$ITEM_COUNT" = "0" ]; then
    echo "No data found in quotes table."
    
    # Check for CSV backup
    CSV_FILE=$(ls -t quotes_export_*.csv 2>/dev/null | head -1)
    if [ -n "$CSV_FILE" ]; then
        echo "Found backup: $CSV_FILE"
        read -p "Restore data from this backup? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            python3 restore-from-csv.py
        fi
    else
        echo "No backup CSV found. You'll need to restore data manually."
    fi
else
    echo -e "${GREEN}✓ Found $ITEM_COUNT quotes in database${NC}"
fi

# Output final configuration
echo ""
echo -e "${GREEN}=== DEPLOYMENT SUMMARY ===${NC}"
echo "API URL: $API_URL"
echo "API Key: $API_KEY_VALUE"
echo ""
echo "Test with:"
echo "  curl '$API_URL/quote' -H 'x-api-key: $API_KEY_VALUE' | jq"
echo ""

# Save configuration to file
CONFIG_FILE="deployment-config.txt"
cat > $CONFIG_FILE << EOF
DCC API Configuration
Generated: $(date)
=====================

API URL: $API_URL
API Key: $API_KEY_VALUE
API ID: $API_ID

Test command:
curl '$API_URL/quote' -H 'x-api-key: $API_KEY_VALUE' | jq

EOF

echo -e "${GREEN}Configuration saved to $CONFIG_FILE${NC}"