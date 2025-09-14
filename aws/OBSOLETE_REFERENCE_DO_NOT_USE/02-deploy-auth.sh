#!/bin/bash

# Step 2: Authentication Deployment
# Deploys: Cognito User Pools, IAM roles, Identity providers
# Target time: < 60 seconds

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

STACK_NAME="dcc-auth"

echo -e "${BLUE}=== STEP 2: AUTHENTICATION DEPLOYMENT ===${NC}"
echo "Deploying authentication: Cognito, IAM roles, OAuth providers"
echo ""

# Check required environment variables
if [ ! -f .env.deployment ]; then
    echo -e "${RED}Error: .env.deployment file not found!${NC}"
    echo "Run ./validate.sh first to check configuration"
    exit 1
fi

source .env.deployment

# Validate required auth parameters
if [ -z "$GOOGLE_CLIENT_ID" ] || [ -z "$GOOGLE_CLIENT_SECRET" ]; then
    echo -e "${RED}Error: Google OAuth credentials not set${NC}"
    exit 1
fi

if [ -z "$APPLE_TEAM_ID" ] || [ -z "$APPLE_KEY_ID" ] || [ -z "$APPLE_PRIVATE_KEY" ]; then
    echo -e "${RED}Error: Apple Sign In credentials not set${NC}"
    exit 1
fi

# Deploy authentication stack
aws cloudformation deploy \
    --template-file templates/02-auth.yaml \
    --stack-name $STACK_NAME \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides \
        GoogleClientId="$GOOGLE_CLIENT_ID" \
        GoogleClientSecret="$GOOGLE_CLIENT_SECRET" \
        AppleServicesId="${APPLE_SERVICES_ID:-com.anystupididea.quoteme.signin}" \
        AppleTeamId="$APPLE_TEAM_ID" \
        AppleKeyId="$APPLE_KEY_ID" \
        ApplePrivateKey="$APPLE_PRIVATE_KEY" \
    --no-fail-on-empty-changeset

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Authentication deployment successful!${NC}"
    
    # Get and display outputs
    echo ""
    echo -e "${YELLOW}Authentication Resources:${NC}"
    aws cloudformation describe-stacks --stack-name $STACK_NAME \
        --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
        --output table
    
    echo ""
    echo -e "${GREEN}Step 2 Complete. Ready for Step 3 (Core API).${NC}"
else
    echo -e "${RED}Authentication deployment failed!${NC}"
    exit 1
fi