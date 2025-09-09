#!/bin/bash

# Deployment script for DCC API with secure environment variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting DCC API Deployment...${NC}"

# Check if .env.deployment exists
if [ ! -f .env.deployment ]; then
    echo -e "${RED}Error: .env.deployment file not found!${NC}"
    echo "Please create .env.deployment with your API keys:"
    echo "  OPENAI_API_KEY=your-openai-key-here"
    echo "  GOOGLE_CLIENT_ID=your-google-client-id"
    echo "  GOOGLE_CLIENT_SECRET=your-google-client-secret"
    echo "  APPLE_SERVICES_ID=com.anystupididea.quoteme.signin"
    echo "  APPLE_TEAM_ID=your-apple-team-id"
    echo "  APPLE_KEY_ID=your-apple-key-id"
    echo "  APPLE_PRIVATE_KEY='-----BEGIN PRIVATE KEY-----...'"
    exit 1
fi

# Load environment variables
source .env.deployment

# Check for FCM service account JSON (optional)
FCM_SERVICE_ACCOUNT_FILE="./more_secrets/fcm-service-account.json"
FCM_SERVICE_ACCOUNT_JSON=""

if [ -f "$FCM_SERVICE_ACCOUNT_FILE" ]; then
    echo -e "${GREEN}📋 FCM service account JSON found, enabling push notifications...${NC}"
    FCM_SERVICE_ACCOUNT_JSON=$(cat "$FCM_SERVICE_ACCOUNT_FILE" | jq -c .)
    if [ -z "$FCM_SERVICE_ACCOUNT_JSON" ]; then
        echo -e "${YELLOW}Warning: Failed to read FCM service account JSON, push notifications will be disabled${NC}"
        FCM_SERVICE_ACCOUNT_JSON=""
    fi
else
    echo -e "${YELLOW}📋 No FCM service account JSON found, push notifications will be disabled${NC}"
    echo -e "${YELLOW}    To enable push notifications, place your Firebase service account JSON at:${NC}"
    echo -e "${YELLOW}    ${FCM_SERVICE_ACCOUNT_FILE}${NC}"
fi

# Verify required API keys are set
if [ -z "$OPENAI_API_KEY" ]; then
    echo -e "${RED}Error: OPENAI_API_KEY not set in .env.deployment${NC}"
    exit 1
fi

if [ -z "$GOOGLE_CLIENT_ID" ]; then
    echo -e "${RED}Error: GOOGLE_CLIENT_ID not set in .env.deployment${NC}"
    exit 1
fi

if [ -z "$GOOGLE_CLIENT_SECRET" ]; then
    echo -e "${RED}Error: GOOGLE_CLIENT_SECRET not set in .env.deployment${NC}"
    exit 1
fi

# Apple Sign In parameters (optional - will use defaults if not provided)
if [ -z "$APPLE_SERVICES_ID" ]; then
    APPLE_SERVICES_ID="com.anystupididea.quoteme.signin"
    echo -e "${YELLOW}Using default APPLE_SERVICES_ID: $APPLE_SERVICES_ID${NC}"
fi

if [ -z "$APPLE_TEAM_ID" ]; then
    echo -e "${RED}Error: APPLE_TEAM_ID not set in .env.deployment${NC}"
    echo "Get your Team ID from Apple Developer → Account → Membership"
    exit 1
fi

if [ -z "$APPLE_KEY_ID" ]; then
    echo -e "${RED}Error: APPLE_KEY_ID not set in .env.deployment${NC}"
    echo "Create a Sign in with Apple key in Apple Developer → Certificates, Identifiers & Profiles → Keys"
    exit 1
fi

if [ -z "$APPLE_PRIVATE_KEY" ]; then
    echo -e "${RED}Error: APPLE_PRIVATE_KEY not set in .env.deployment${NC}"
    echo "Set APPLE_PRIVATE_KEY to the contents of your .p8 file (including BEGIN/END lines)"
    exit 1
fi

echo -e "${YELLOW}Building SAM application...${NC}"
sam build --cached 2>&1 | grep -v "File with same data already exists" | grep -v "skipping upload"

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo -e "${RED}Build failed!${NC}"
    exit 1
fi

echo -e "${YELLOW}Validating template...${NC}"
sam validate --lint

echo -e "${YELLOW}Deploying to AWS...${NC}"
echo "This may take a few minutes..."

# Capture deployment output (Apple provider creation may take several minutes)
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