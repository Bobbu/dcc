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
    exit 1
fi

# Load environment variables
source .env.deployment

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

# Capture deployment output
DEPLOY_OUTPUT=$(sam deploy --capabilities CAPABILITY_NAMED_IAM --parameter-overrides OpenAIApiKey="$OPENAI_API_KEY" GoogleClientId="$GOOGLE_CLIENT_ID" GoogleClientSecret="$GOOGLE_CLIENT_SECRET" 2>&1)
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
elif [ $DEPLOY_STATUS -eq 0 ]; then
    echo -e "${GREEN}✓ Deployment successful!${NC}"
    echo ""
    echo "Your OpenAI API key is securely stored in AWS Lambda."
    echo "The Flutter app will use the proxy endpoint for tag generation."
    
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