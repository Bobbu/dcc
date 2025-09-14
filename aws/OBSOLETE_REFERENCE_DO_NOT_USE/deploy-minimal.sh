#!/bin/bash

# Minimal deployment script for Quote Me API
# Uses new "quote-me" naming to avoid conflicts

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Starting Quote Me Minimal API Deployment...${NC}"

# Load environment variables
if [ -f .env.deployment ]; then
    source .env.deployment
    echo -e "${GREEN}✓ Environment variables loaded${NC}"
else
    echo -e "${RED}Error: .env.deployment not found${NC}"
    exit 1
fi

# Build the application
echo -e "${YELLOW}Building SAM application...${NC}"
sam build --template template-minimal.yaml --cached

if [ $? -ne 0 ]; then
    echo -e "${RED}Build failed!${NC}"
    exit 1
fi

echo -e "${YELLOW}Deploying Quote Me API...${NC}"

# Deploy with minimal parameters
sam deploy \
    --template-file .aws-sam/build/template.yaml \
    --stack-name quote-me-api \
    --capabilities CAPABILITY_NAMED_IAM \
    --no-confirm-changeset \
    --parameter-overrides \
        OpenAIApiKey="$OPENAI_API_KEY" \
    --s3-bucket quote-me-sam-deployments-$(aws sts get-caller-identity --query Account --output text) \
    --s3-prefix quote-me-api

DEPLOY_STATUS=$?

if [ $DEPLOY_STATUS -eq 0 ]; then
    echo -e "${GREEN}✓ Deployment successful!${NC}"
    echo ""
    
    # Get outputs
    API_URL=$(aws cloudformation describe-stacks \
        --stack-name quote-me-api \
        --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' \
        --output text)
    
    echo "API URL: $API_URL"
    echo ""
    
    # Get API key
    API_ID=$(aws apigateway get-rest-apis --query 'items[?name==`quote-me-api`].id' --output text)
    if [ -n "$API_ID" ]; then
        API_KEY_ID=$(aws apigateway get-api-keys --query "items[?stageKeys[?contains(@, '$API_ID')]].id" --output text | head -1)
        if [ -n "$API_KEY_ID" ]; then
            API_KEY_VALUE=$(aws apigateway get-api-key --api-key $API_KEY_ID --include-value --query value --output text)
            echo "API Key: $API_KEY_VALUE"
        fi
    fi
else
    echo -e "${RED}Deployment failed!${NC}"
    exit 1
fi