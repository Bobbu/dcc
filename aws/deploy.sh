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
    echo "Please create .env.deployment with your OpenAI API key:"
    echo "  OPENAI_API_KEY=your-key-here"
    exit 1
fi

# Load environment variables
source .env.deployment

# Verify OpenAI API key is set
if [ -z "$OPENAI_API_KEY" ]; then
    echo -e "${RED}Error: OPENAI_API_KEY not set in .env.deployment${NC}"
    exit 1
fi

echo -e "${YELLOW}Building SAM application...${NC}"
sam build

if [ $? -ne 0 ]; then
    echo -e "${RED}Build failed!${NC}"
    exit 1
fi

echo -e "${YELLOW}Deploying to AWS...${NC}"
sam deploy --parameter-overrides OpenAIApiKey="$OPENAI_API_KEY"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Deployment successful!${NC}"
    echo ""
    echo "Your OpenAI API key is securely stored in AWS Lambda."
    echo "The Flutter app will use the proxy endpoint for tag generation."
    echo "Don't forget to update the Flutter app with your API Gateway URL."
else
    echo -e "${RED}Deployment failed!${NC}"
    exit 1
fi