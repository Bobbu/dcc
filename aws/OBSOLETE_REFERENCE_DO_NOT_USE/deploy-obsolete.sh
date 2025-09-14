#!/bin/bash

# Deployment script for DCC API with secure environment variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting DCC API Deployment...${NC}"
echo -e "${YELLOW}💡 Run ./validate.sh first to check configuration${NC}"

# Load environment variables (assume validation already done)
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
sam build --cached 2>&1 | grep -v "File with same data already exists" | grep -v "skipping upload"

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo -e "${RED}Build failed!${NC}"
    exit 1
fi

echo -e "${YELLOW}Deploying to AWS...${NC}"

# Ask user preference: wait or background
echo ""
read -p "Wait for deployment to complete? (y/N): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Deploying and waiting for completion..."
    # Deploy and wait (original behavior)
    if [ -n "$FCM_SERVICE_ACCOUNT_JSON" ]; then
        DEPLOY_OUTPUT=$(sam deploy --capabilities CAPABILITY_NAMED_IAM --parameter-overrides \
            OpenAIApiKey="$OPENAI_API_KEY" \
            GoogleClientId="$GOOGLE_CLIENT_ID" \
            GoogleClientSecret="$GOOGLE_CLIENT_SECRET" \
            AppleServicesId="$APPLE_SERVICES_ID" \
            AppleTeamId="$APPLE_TEAM_ID" \
            AppleKeyId="$APPLE_KEY_ID" \
            ApplePrivateKey="$APPLE_PRIVATE_KEY" \
            FCMServiceAccountJSON="$FCM_SERVICE_ACCOUNT_JSON" 2>&1)
    else
        DEPLOY_OUTPUT=$(sam deploy --capabilities CAPABILITY_NAMED_IAM --parameter-overrides \
            OpenAIApiKey="$OPENAI_API_KEY" \
            GoogleClientId="$GOOGLE_CLIENT_ID" \
            GoogleClientSecret="$GOOGLE_CLIENT_SECRET" \
            AppleServicesId="$APPLE_SERVICES_ID" \
            AppleTeamId="$APPLE_TEAM_ID" \
            AppleKeyId="$APPLE_KEY_ID" \
            ApplePrivateKey="$APPLE_PRIVATE_KEY" 2>&1)
    fi
    DEPLOY_STATUS=$?
else
    echo "Starting deployment in background..."
    echo "Deployment log will be saved to deployment.log"
    
    # Deploy in background
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
    echo -e "${GREEN}✓ Deployment started in background with PID: $DEPLOY_PID${NC}"
    echo ""
    echo "Monitor progress with:"
    echo "  ./check_deploy_status.sh"
    echo "  tail -f deployment.log"
    echo ""
    echo "Kill deployment if needed: kill $DEPLOY_PID"
    
    # Exit successfully since deployment started
    exit 0
fi

DEPLOY_STATUS=$?

# Check if it's just "no changes"
if echo "$DEPLOY_OUTPUT" | grep -q "No changes to deploy"; then
    echo -e "${GREEN}✓ Stack is already up to date - no changes needed${NC}"
    echo ""
    echo -e "${GREEN}All infrastructure is deployed and ready:${NC}"
    echo "  • API endpoints are active"
    echo "  • DynamoDB tables are configured"
    echo "  • Lambda functions are deployed"
    echo "  • Daily Nuggets feature is operational"
    if [ -n "$FCM_SERVICE_ACCOUNT_JSON" ]; then
        echo "  • Push notifications are enabled"
    fi
elif [ $DEPLOY_STATUS -eq 0 ]; then
    echo -e "${GREEN}✓ Deployment successful!${NC}"
    echo ""
    echo "Your OpenAI API key is securely stored in AWS Lambda."
    echo "The Flutter app will use the proxy endpoint for tag generation."
    
    if [ -n "$FCM_SERVICE_ACCOUNT_JSON" ]; then
        echo ""
        echo -e "${GREEN}🔥 Push Notifications are now enabled!${NC}"
        echo ""
        echo "📋 Push notification endpoints available:"
        echo "   • POST /subscriptions/test - Test user push notification"
        echo "   • POST /notifications/test - Test push notification API"
    fi
    
    # Show key outputs
    echo ""
    echo -e "${YELLOW}Key Resources:${NC}"
    aws cloudformation describe-stacks --stack-name dcc-demo-sam-app \
        --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' \
        --output text | xargs -I {} echo "  • API URL: {}"
else
    # Only show actual errors, not upload progress
    echo "$DEPLOY_OUTPUT" | grep -v "Uploading to" | grep -v "File with same data"
    echo -e "${RED}Deployment failed!${NC}"
    echo "Please check the error messages above."
    exit 1
fi