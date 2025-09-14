#!/bin/bash

# Async deployment script - starts deployment and lets you monitor separately

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting Async DCC API Deployment...${NC}"

# Load environment variables
source .env.deployment

# Check for FCM service account JSON (optional)
FCM_SERVICE_ACCOUNT_FILE="./more_secrets/fcm-service-account.json"
FCM_SERVICE_ACCOUNT_JSON=""

if [ -f "$FCM_SERVICE_ACCOUNT_FILE" ]; then
    echo -e "${GREEN}📋 FCM service account JSON found, enabling push notifications...${NC}"
    FCM_SERVICE_ACCOUNT_JSON=$(cat "$FCM_SERVICE_ACCOUNT_FILE" | jq -c . 2>/dev/null)
fi

# Set defaults for Apple Sign In if not provided
if [ -z "$APPLE_SERVICES_ID" ]; then
    APPLE_SERVICES_ID="com.anystupididea.quoteme.signin"
fi

echo -e "${YELLOW}Building SAM application...${NC}"
sam build --cached

if [ $? -ne 0 ]; then
    echo -e "${RED}Build failed!${NC}"
    exit 1
fi

echo -e "${YELLOW}Starting deployment in background...${NC}"
echo "Deployment log will be saved to deployment.log"

# Start deployment in background and save output to log
{
    if [ -n "$FCM_SERVICE_ACCOUNT_JSON" ]; then
        sam deploy --capabilities CAPABILITY_NAMED_IAM --parameter-overrides \
            OpenAIApiKey="$OPENAI_API_KEY" \
            GoogleClientId="$GOOGLE_CLIENT_ID" \
            GoogleClientSecret="$GOOGLE_CLIENT_SECRET" \
            AppleServicesId="$APPLE_SERVICES_ID" \
            AppleTeamId="$APPLE_TEAM_ID" \
            AppleKeyId="$APPLE_KEY_ID" \
            ApplePrivateKey="$APPLE_PRIVATE_KEY" \
            FCMServiceAccountJSON="$FCM_SERVICE_ACCOUNT_JSON"
    else
        sam deploy --capabilities CAPABILITY_NAMED_IAM --parameter-overrides \
            OpenAIApiKey="$OPENAI_API_KEY" \
            GoogleClientId="$GOOGLE_CLIENT_ID" \
            GoogleClientSecret="$GOOGLE_CLIENT_SECRET" \
            AppleServicesId="$APPLE_SERVICES_ID" \
            AppleTeamId="$APPLE_TEAM_ID" \
            AppleKeyId="$APPLE_KEY_ID" \
            ApplePrivateKey="$APPLE_PRIVATE_KEY"
    fi
} > deployment.log 2>&1 &

DEPLOY_PID=$!
echo -e "${GREEN}✓ Deployment started with PID: $DEPLOY_PID${NC}"
echo ""
echo "Monitor progress with:"
echo "  tail -f deployment.log"
echo ""
echo "Check status with:"
echo "  aws cloudformation describe-stacks --stack-name dcc-demo-sam-app --query 'Stacks[0].StackStatus'"
echo ""
echo "Kill deployment if needed with:"
echo "  kill $DEPLOY_PID"

# Optionally wait for completion
read -p "Wait for deployment to complete? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Waiting for deployment to complete..."
    wait $DEPLOY_PID
    DEPLOY_STATUS=$?
    
    if [ $DEPLOY_STATUS -eq 0 ]; then
        echo -e "${GREEN}✓ Deployment completed successfully!${NC}"
    else
        echo -e "${RED}✗ Deployment failed!${NC}"
        echo "Check deployment.log for details"
    fi
else
    echo "Deployment continues in background. Check deployment.log for progress."
fi