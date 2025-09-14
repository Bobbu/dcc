#!/bin/bash

# Validation script for DCC API - separate from deployment for speed

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting DCC API Validation...${NC}"

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

echo -e "${YELLOW}Validating environment variables...${NC}"

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

echo -e "${YELLOW}Validating SAM template...${NC}"
sam validate --lint

LINT_STATUS=$?
if [ $LINT_STATUS -ne 0 ]; then
    echo -e "${YELLOW}Warning: Template has linting warnings (non-fatal)${NC}"
    echo "Running basic validation without lint..."
    sam validate
    if [ $? -ne 0 ]; then
        echo -e "${RED}Template validation failed!${NC}"
        exit 1
    fi
fi

echo -e "${YELLOW}Checking AWS credentials...${NC}"
aws sts get-caller-identity > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: AWS credentials not configured or invalid${NC}"
    echo "Please run: aws configure"
    exit 1
fi

echo -e "${YELLOW}Checking FCM service account JSON...${NC}"
FCM_SERVICE_ACCOUNT_FILE="./more_secrets/fcm-service-account.json"
if [ -f "$FCM_SERVICE_ACCOUNT_FILE" ]; then
    echo -e "${GREEN}📋 FCM service account JSON found${NC}"
    FCM_SERVICE_ACCOUNT_JSON=$(cat "$FCM_SERVICE_ACCOUNT_FILE" | jq -c .)
    if [ -z "$FCM_SERVICE_ACCOUNT_JSON" ]; then
        echo -e "${YELLOW}Warning: FCM service account JSON is invalid${NC}"
    else
        echo -e "${GREEN}📋 FCM service account JSON is valid${NC}"
    fi
else
    echo -e "${YELLOW}📋 No FCM service account JSON found (push notifications will be disabled)${NC}"
fi

echo -e "${YELLOW}Running additional CloudFormation validation...${NC}"
sam validate --template template.yaml

if [ $? -ne 0 ]; then
    echo -e "${RED}CloudFormation template validation failed!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ All validations passed!${NC}"
echo ""
echo "The deployment is ready to proceed. Run ./deploy.sh to deploy."