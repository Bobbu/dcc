#!/bin/bash

# Step 4: Extended Services Deployment
# Deploys: Image generation, notifications, exports, daily nuggets
# Target time: < 60 seconds

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

STACK_NAME="dcc-services"

echo -e "${BLUE}=== STEP 4: EXTENDED SERVICES DEPLOYMENT ===${NC}"
echo "Deploying extended services: Image generation, notifications, exports"
echo ""

# Load environment variables
source .env.deployment

# Check for FCM service account JSON (optional)
FCM_SERVICE_ACCOUNT_FILE="./more_secrets/fcm-service-account.json"
FCM_SERVICE_ACCOUNT_JSON=""

if [ -f "$FCM_SERVICE_ACCOUNT_FILE" ]; then
    echo -e "${GREEN}📋 FCM service account JSON found, enabling push notifications...${NC}"
    FCM_SERVICE_ACCOUNT_JSON=$(cat "$FCM_SERVICE_ACCOUNT_FILE" | jq -c . 2>/dev/null)
fi

# Deploy services stack
if [ -n "$FCM_SERVICE_ACCOUNT_JSON" ]; then
    aws cloudformation deploy \
        --template-file templates/04-services.yaml \
        --stack-name $STACK_NAME \
        --capabilities CAPABILITY_NAMED_IAM \
        --parameter-overrides \
            OpenAIApiKey="$OPENAI_API_KEY" \
            FCMServiceAccountJSON="$FCM_SERVICE_ACCOUNT_JSON" \
        --no-fail-on-empty-changeset
else
    aws cloudformation deploy \
        --template-file templates/04-services.yaml \
        --stack-name $STACK_NAME \
        --capabilities CAPABILITY_NAMED_IAM \
        --parameter-overrides \
            OpenAIApiKey="$OPENAI_API_KEY" \
        --no-fail-on-empty-changeset
fi

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Extended services deployment successful!${NC}"
    
    # Get and display outputs
    echo ""
    echo -e "${YELLOW}Extended Services Resources:${NC}"
    aws cloudformation describe-stacks --stack-name $STACK_NAME \
        --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
        --output table
    
    echo ""
    if [ -n "$FCM_SERVICE_ACCOUNT_JSON" ]; then
        echo -e "${GREEN}🔥 Push notifications enabled!${NC}"
    fi
    echo -e "${GREEN}Step 4 Complete. Ready for Step 5 (Integration Tests).${NC}"
else
    echo -e "${RED}Extended services deployment failed!${NC}"
    exit 1
fi