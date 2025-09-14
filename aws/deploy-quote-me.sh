#!/bin/bash

# Quote Me API Deployment - Complete System from Zero
# This script builds everything correctly with proper naming

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== QUOTE ME API COMPLETE DEPLOYMENT ===${NC}"
echo "Building from zero with correct naming conventions"
echo ""

# Load environment variables
if [ -f .env.deployment ]; then
    source .env.deployment
    echo -e "${GREEN}✓ Environment variables loaded${NC}"
else
    echo -e "${RED}Error: .env.deployment not found${NC}"
    exit 1
fi

# Check for FCM service account JSON (optional)
FCM_SERVICE_ACCOUNT_FILE="./more_secrets/fcm-service-account.json"
FCM_SERVICE_ACCOUNT_JSON=""

if [ -f "$FCM_SERVICE_ACCOUNT_FILE" ]; then
    echo -e "${GREEN}✓ FCM service account JSON found${NC}"
    FCM_SERVICE_ACCOUNT_JSON=$(cat "$FCM_SERVICE_ACCOUNT_FILE" | jq -c . 2>/dev/null)
else
    echo -e "${YELLOW}ℹ FCM service account not found (push notifications disabled)${NC}"
fi

# Build the application
echo ""
echo -e "${YELLOW}Building SAM application...${NC}"
sam build --template template-quote-me.yaml --cached

if [ $? -ne 0 ]; then
    echo -e "${RED}Build failed!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Build successful${NC}"

# Create S3 bucket for deployments if it doesn't exist
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="quote-me-sam-deployments-${ACCOUNT_ID}"
aws s3 mb s3://$BUCKET_NAME --region us-east-1 2>/dev/null || echo "Deployment bucket already exists"

# Deploy the stack
echo ""
echo -e "${YELLOW}Deploying Quote Me System...${NC}"

STACK_NAME="quote-me-api"
LOG_FILE="deployment.log"

echo "Deployment started at $(date)" > $LOG_FILE

if [ -n "$FCM_SERVICE_ACCOUNT_JSON" ]; then
    sam deploy \
        --template-file .aws-sam/build/template.yaml \
        --stack-name $STACK_NAME \
        --capabilities CAPABILITY_NAMED_IAM \
        --no-confirm-changeset \
        --parameter-overrides \
            OpenAIApiKey="$OPENAI_API_KEY" \
            FCMServiceAccountJSON="$FCM_SERVICE_ACCOUNT_JSON" \
        --s3-bucket $BUCKET_NAME \
        --s3-prefix quote-me-api 2>&1 | tee -a $LOG_FILE
else
    sam deploy \
        --template-file .aws-sam/build/template.yaml \
        --stack-name $STACK_NAME \
        --capabilities CAPABILITY_NAMED_IAM \
        --no-confirm-changeset \
        --parameter-overrides \
            OpenAIApiKey="$OPENAI_API_KEY" \
        --s3-bucket $BUCKET_NAME \
        --s3-prefix quote-me-api 2>&1 | tee -a $LOG_FILE
fi

DEPLOY_STATUS=$?

if [ $DEPLOY_STATUS -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ Deployment successful!${NC}"
    echo ""
    
    # Get stack outputs
    API_URL=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' \
        --output text)
    
    API_KEY_ID=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --query 'Stacks[0].Outputs[?OutputKey==`ApiKeyId`].OutputValue' \
        --output text)
    
    USER_POOL_ID=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --query 'Stacks[0].Outputs[?OutputKey==`UserPoolId`].OutputValue' \
        --output text)
    
    USER_POOL_CLIENT_ID=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --query 'Stacks[0].Outputs[?OutputKey==`UserPoolClientId`].OutputValue' \
        --output text)
    
    QUOTES_TABLE=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --query 'Stacks[0].Outputs[?OutputKey==`QuotesTableName`].OutputValue' \
        --output text)
    
    TAGS_TABLE=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --query 'Stacks[0].Outputs[?OutputKey==`TagsTableName`].OutputValue' \
        --output text)
    
    IMAGES_BUCKET=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --query 'Stacks[0].Outputs[?OutputKey==`QuoteImagesBucketName`].OutputValue' \
        --output text)
    
    # Get API key value
    API_KEY_VALUE=$(aws apigateway get-api-key --api-key $API_KEY_ID --include-value --query value --output text)
    
    # Update .env file in mobile app
    ENV_FILE="../dcc_mobile/.env"
    if [ -f "$ENV_FILE" ]; then
        echo -e "${YELLOW}Updating app configuration...${NC}"
        cp "$ENV_FILE" "$ENV_FILE.bak"
        
        cat > "$ENV_FILE" << EOF
API_ENDPOINT=$API_URL/quote
API_KEY=$API_KEY_VALUE
API_URL=$API_URL
USER_POOL_ID=$USER_POOL_ID
USER_POOL_CLIENT_ID=$USER_POOL_CLIENT_ID
# OpenAI API key removed - now securely stored in AWS Lambda
EOF
        
        echo -e "${GREEN}✓ App configuration updated${NC}"
    fi
    
    # Save deployment configuration
    CONFIG_FILE="deployment-config.txt"
    cat > $CONFIG_FILE << EOF
Quote Me API Configuration
Generated: $(date)
========================

API URL: $API_URL
API Key: $API_KEY_VALUE
User Pool ID: $USER_POOL_ID
User Pool Client ID: $USER_POOL_CLIENT_ID
Quotes Table: $QUOTES_TABLE
Tags Table: $TAGS_TABLE
Images Bucket: $IMAGES_BUCKET

Test Commands:
--------------
# Get a random quote
curl '$API_URL/quote' -H 'x-api-key: $API_KEY_VALUE' | jq

# Get all tags
curl '$API_URL/tags' -H 'x-api-key: $API_KEY_VALUE' | jq

# Get quote by tag
curl '$API_URL/quote?tags=Wisdom' -H 'x-api-key: $API_KEY_VALUE' | jq

EOF
    
    echo ""
    echo -e "${GREEN}=== DEPLOYMENT COMPLETE ===${NC}"
    echo "API URL: $API_URL"
    echo "API Key: $API_KEY_VALUE"
    echo ""
    echo "Configuration saved to: $CONFIG_FILE"
    echo "App .env updated: $ENV_FILE"
    echo ""
    
    # Check if data needs to be restored
    ITEM_COUNT=$(aws dynamodb scan --table-name $QUOTES_TABLE --select COUNT --query Count --output text 2>/dev/null || echo "0")
    
    if [ "$ITEM_COUNT" = "0" ]; then
        echo -e "${YELLOW}⚠ Warning: No data in quotes table${NC}"
        echo "Run restore-data.sh to restore from backup"
    else
        echo -e "${GREEN}✓ Found $ITEM_COUNT quotes in database${NC}"
    fi
    
    # Test the API
    echo ""
    echo -e "${YELLOW}Testing API...${NC}"
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$API_URL/quote" -H "x-api-key: $API_KEY_VALUE")
    
    if [ "$RESPONSE" = "200" ]; then
        echo -e "${GREEN}✓ API is working!${NC}"
        SAMPLE_QUOTE=$(curl -s "$API_URL/quote" -H "x-api-key: $API_KEY_VALUE" | jq -r '.quote' | cut -c1-60)
        echo "Sample quote: \"$SAMPLE_QUOTE...\""
    else
        echo -e "${YELLOW}API returned status $RESPONSE${NC}"
    fi
    
else
    echo -e "${RED}Deployment failed!${NC}"
    echo "Check deployment.log for details"
    exit 1
fi