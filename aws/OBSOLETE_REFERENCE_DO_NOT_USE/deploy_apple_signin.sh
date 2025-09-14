#!/bin/bash

# Minimal Apple Sign In Deployment Script
# Deploys only the Apple Sign In infrastructure

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting Apple Sign In Deployment...${NC}"

# Check if .env.apple exists
if [ ! -f .env.apple ]; then
    echo -e "${RED}Error: .env.apple file not found!${NC}"
    echo "Please create .env.apple with your Apple credentials:"
    echo "  APPLE_SERVICES_ID=com.yourcompany.yourapp.signin"
    echo "  APPLE_TEAM_ID=YOUR_TEAM_ID"
    echo "  APPLE_KEY_ID=YOUR_KEY_ID"
    echo "  APPLE_PRIVATE_KEY='-----BEGIN PRIVATE KEY-----...'"
    echo "  APP_NAME=YourApp"
    echo "  CALLBACK_URLS=https://yourapp.com/auth/callback,yourapp://auth-success"
    echo "  LOGOUT_URLS=https://yourapp.com/,yourapp://auth-signout"
    exit 1
fi

# Load environment variables
source .env.apple

# Verify required parameters are set
if [ -z "$APPLE_SERVICES_ID" ]; then
    echo -e "${RED}Error: APPLE_SERVICES_ID not set in .env.apple${NC}"
    exit 1
fi

if [ -z "$APPLE_TEAM_ID" ]; then
    echo -e "${RED}Error: APPLE_TEAM_ID not set in .env.apple${NC}"
    exit 1
fi

if [ -z "$APPLE_KEY_ID" ]; then
    echo -e "${RED}Error: APPLE_KEY_ID not set in .env.apple${NC}"
    exit 1
fi

if [ -z "$APPLE_PRIVATE_KEY" ]; then
    echo -e "${RED}Error: APPLE_PRIVATE_KEY not set in .env.apple${NC}"
    exit 1
fi

# Set defaults if not provided
if [ -z "$APP_NAME" ]; then
    APP_NAME="AppleSignInApp"
    echo -e "${YELLOW}Using default APP_NAME: $APP_NAME${NC}"
fi

if [ -z "$CALLBACK_URLS" ]; then
    CALLBACK_URLS="https://yourapp.com/auth/callback,yourapp://auth-success"
    echo -e "${YELLOW}Using default CALLBACK_URLS: $CALLBACK_URLS${NC}"
fi

if [ -z "$LOGOUT_URLS" ]; then
    LOGOUT_URLS="https://yourapp.com/,yourapp://auth-signout"
    echo -e "${YELLOW}Using default LOGOUT_URLS: $LOGOUT_URLS${NC}"
fi

echo -e "${YELLOW}Building SAM application...${NC}"
sam build -t template_sign_in_with_apple.yaml

if [ $? -ne 0 ]; then
    echo -e "${RED}Build failed!${NC}"
    exit 1
fi

echo -e "${YELLOW}Validating template...${NC}"
sam validate -t template_sign_in_with_apple.yaml --lint

echo -e "${YELLOW}Deploying Apple Sign In infrastructure...${NC}"
echo "This may take a few minutes..."

# Deploy with parameters
DEPLOY_OUTPUT=$(sam deploy \
    --template-file template_sign_in_with_apple.yaml \
    --stack-name "${APP_NAME}-apple-signin" \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides \
        AppleServicesId="$APPLE_SERVICES_ID" \
        AppleTeamId="$APPLE_TEAM_ID" \
        AppleKeyId="$APPLE_KEY_ID" \
        ApplePrivateKey="$APPLE_PRIVATE_KEY" \
        AppName="$APP_NAME" \
        CallbackUrls="$CALLBACK_URLS" \
        LogoutUrls="$LOGOUT_URLS" \
    2>&1)

DEPLOY_STATUS=$?

if [ $DEPLOY_STATUS -eq 0 ]; then
    echo -e "${GREEN}✅ Apple Sign In deployment successful!${NC}"
    echo ""
    echo -e "${YELLOW}Key Resources Created:${NC}"
    aws cloudformation describe-stacks --stack-name "${APP_NAME}-apple-signin" \
        --query 'Stacks[0].Outputs[?OutputKey==`UserPoolId`].OutputValue' \
        --output text | xargs -I {} echo "  • User Pool ID: {}"
    aws cloudformation describe-stacks --stack-name "${APP_NAME}-apple-signin" \
        --query 'Stacks[0].Outputs[?OutputKey==`UserPoolClientId`].OutputValue' \
        --output text | xargs -I {} echo "  • User Pool Client ID: {}"
    aws cloudformation describe-stacks --stack-name "${APP_NAME}-apple-signin" \
        --query 'Stacks[0].Outputs[?OutputKey==`CognitoHostedUIUrl`].OutputValue' \
        --output text | xargs -I {} echo "  • Hosted UI URL: {}"
    echo ""
    echo -e "${GREEN}Copy the Amplify configuration from the AmplifyConfiguration output!${NC}"
else
    echo "$DEPLOY_OUTPUT" | grep -v "Uploading to" | grep -v "File with same data"
    echo -e "${RED}Deployment failed!${NC}"
    exit 1
fi