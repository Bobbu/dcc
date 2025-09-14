#!/bin/bash

# Deploy Federated Authentication Add-on
# This adds Google and Apple Sign In to an existing Cognito User Pool

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== FEDERATED AUTHENTICATION DEPLOYMENT ===${NC}"
echo "This will add Google and Apple Sign In to the existing Cognito User Pool"
echo ""

# Check if main stack exists
USER_POOL_ID=$(aws cloudformation describe-stacks \
    --stack-name dcc-api-complete \
    --query 'Stacks[0].Outputs[?OutputKey==`UserPoolId`].OutputValue' \
    --output text 2>/dev/null)

if [ -z "$USER_POOL_ID" ] || [ "$USER_POOL_ID" = "None" ]; then
    echo -e "${RED}Error: Main API stack not found or UserPool not created${NC}"
    echo "Please deploy the main API first using ./deploy-complete.sh"
    exit 1
fi

echo -e "${GREEN}✓ Found User Pool: $USER_POOL_ID${NC}"

# Load environment variables
if [ -f .env.deployment ]; then
    source .env.deployment
    echo -e "${GREEN}✓ Environment variables loaded${NC}"
else
    echo -e "${RED}Error: .env.deployment not found${NC}"
    exit 1
fi

# Validate required variables
if [ -z "$GOOGLE_CLIENT_ID" ] || [ -z "$GOOGLE_CLIENT_SECRET" ]; then
    echo -e "${YELLOW}Warning: Google OAuth credentials not found${NC}"
fi

if [ -z "$APPLE_TEAM_ID" ] || [ -z "$APPLE_KEY_ID" ] || [ -z "$APPLE_PRIVATE_KEY" ]; then
    echo -e "${YELLOW}Warning: Apple Sign In credentials not found${NC}"
fi

echo -e "${YELLOW}Deploying Federated Authentication...${NC}"

sam deploy \
    --template-file template-federated-auth.yaml \
    --stack-name dcc-federated-auth \
    --capabilities CAPABILITY_IAM \
    --no-confirm-changeset \
    --parameter-overrides \
        UserPoolId="$USER_POOL_ID" \
        GoogleClientId="$GOOGLE_CLIENT_ID" \
        GoogleClientSecret="$GOOGLE_CLIENT_SECRET" \
        AppleServicesId="${APPLE_SERVICES_ID:-com.anystupididea.quoteme.signin}" \
        AppleTeamId="$APPLE_TEAM_ID" \
        AppleKeyId="$APPLE_KEY_ID" \
        ApplePrivateKey="$APPLE_PRIVATE_KEY"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Federated authentication deployed successfully!${NC}"
    echo ""
    echo "Google and Apple Sign In have been added to your Cognito User Pool"
else
    echo -e "${RED}Deployment failed!${NC}"
    exit 1
fi