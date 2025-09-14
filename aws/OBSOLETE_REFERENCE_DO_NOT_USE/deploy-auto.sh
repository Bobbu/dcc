#!/bin/bash

# Auto-deployment script - no interactive prompts, uses environment variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting Automated DCC API Deployment...${NC}"

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
    echo -e "${GREEN}📋 FCM service account JSON found${NC}"
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

echo -e "${YELLOW}Deploying to AWS (automated)...${NC}"

# Always use a consistent log file name
LOG_FILE="deployment.log"
echo "Deployment started at $(date)" > $LOG_FILE

# Deploy with all parameters, no confirmation - use fresh stack name
STACK_NAME="dcc-api-working"

if [ -n "$FCM_SERVICE_ACCOUNT_JSON" ]; then
    sam deploy --stack-name $STACK_NAME --capabilities CAPABILITY_NAMED_IAM --no-confirm-changeset --parameter-overrides \
        OpenAIApiKey="$OPENAI_API_KEY" \
        GoogleClientId="$GOOGLE_CLIENT_ID" \
        GoogleClientSecret="$GOOGLE_CLIENT_SECRET" \
        AppleServicesId="$APPLE_SERVICES_ID" \
        AppleTeamId="$APPLE_TEAM_ID" \
        AppleKeyId="$APPLE_KEY_ID" \
        ApplePrivateKey="$APPLE_PRIVATE_KEY" \
        FCMServiceAccountJSON="$FCM_SERVICE_ACCOUNT_JSON" 2>&1 | tee -a $LOG_FILE
else
    sam deploy --stack-name $STACK_NAME --capabilities CAPABILITY_NAMED_IAM --no-confirm-changeset --parameter-overrides \
        OpenAIApiKey="$OPENAI_API_KEY" \
        GoogleClientId="$GOOGLE_CLIENT_ID" \
        GoogleClientSecret="$GOOGLE_CLIENT_SECRET" \
        AppleServicesId="$APPLE_SERVICES_ID" \
        AppleTeamId="$APPLE_TEAM_ID" \
        AppleKeyId="$APPLE_KEY_ID" \
        ApplePrivateKey="$APPLE_PRIVATE_KEY" 2>&1 | tee -a $LOG_FILE
fi

DEPLOY_STATUS=$?

if [ $DEPLOY_STATUS -eq 0 ]; then
    echo -e "${GREEN}✓ Deployment successful!${NC}"
    echo ""
    echo "Updated Lambda functions with OpenAI client fix."
    if [ -n "$FCM_SERVICE_ACCOUNT_JSON" ]; then
        echo "Push notifications are enabled."
    fi
else
    echo -e "${RED}Deployment failed!${NC}"
    exit 1
fi