#!/bin/bash

# Lambda-only deployment script using SAM sync for faster iterations

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting Lambda-Only Deployment (SAM Sync)...${NC}"
echo -e "${YELLOW}💡 This only updates Lambda functions and doesn't create new resources${NC}"

# Load environment variables
source .env.deployment

echo -e "${YELLOW}Building and syncing with SAM...${NC}"

# Use SAM sync for faster Lambda-only deployments
sam sync --stack-name dcc-demo-sam-app --watch-exclude "*.git/*" --watch-exclude "node_modules/*"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Lambda-only deployment successful!${NC}"
    echo ""
    echo "Lambda functions have been updated."
    echo "For infrastructure changes, use ./deploy.sh"
else
    echo -e "${RED}Lambda-only deployment failed!${NC}"
    echo "Try ./deploy.sh for a full deployment"
    exit 1
fi