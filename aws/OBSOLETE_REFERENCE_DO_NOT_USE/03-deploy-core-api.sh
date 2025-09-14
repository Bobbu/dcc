#!/bin/bash

# Step 3: Core API Deployment  
# Deploys: Basic Lambda functions, API Gateway, core endpoints
# Target time: < 90 seconds

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

STACK_NAME="dcc-core-api"

echo -e "${BLUE}=== STEP 3: CORE API DEPLOYMENT ===${NC}"
echo "Deploying core API: Lambda functions, API Gateway, CRUD endpoints"
echo ""

# Load environment variables
source .env.deployment

# Build SAM application
echo -e "${YELLOW}Building SAM application...${NC}"
sam build --cached

if [ $? -ne 0 ]; then
    echo -e "${RED}Build failed!${NC}"
    exit 1
fi

# Deploy core API stack
aws cloudformation deploy \
    --template-file templates/03-core-api.yaml \
    --stack-name $STACK_NAME \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides \
        OpenAIApiKey="$OPENAI_API_KEY" \
    --no-fail-on-empty-changeset

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Core API deployment successful!${NC}"
    
    # Get and display outputs
    echo ""
    echo -e "${YELLOW}Core API Resources:${NC}"
    aws cloudformation describe-stacks --stack-name $STACK_NAME \
        --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
        --output table
    
    echo ""
    echo -e "${GREEN}Step 3 Complete. Ready for Step 4 (Extended Services).${NC}"
else
    echo -e "${RED}Core API deployment failed!${NC}"
    exit 1
fi