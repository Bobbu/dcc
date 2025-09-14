#!/bin/bash

# Step 1: Core Infrastructure Deployment
# Deploys: S3 buckets, DynamoDB tables, SQS queues
# Target time: < 30 seconds

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

STACK_NAME="dcc-infrastructure"

echo -e "${BLUE}=== STEP 1: INFRASTRUCTURE DEPLOYMENT ===${NC}"
echo "Deploying core infrastructure: S3, DynamoDB, SQS"
echo ""

# Deploy infrastructure stack
aws cloudformation deploy \
    --template-file templates/01-infrastructure.yaml \
    --stack-name $STACK_NAME \
    --capabilities CAPABILITY_IAM \
    --no-fail-on-empty-changeset

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Infrastructure deployment successful!${NC}"
    
    # Get and display outputs
    echo ""
    echo -e "${YELLOW}Infrastructure Resources:${NC}"
    aws cloudformation describe-stacks --stack-name $STACK_NAME \
        --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
        --output table
    
    echo ""
    echo -e "${GREEN}Step 1 Complete. Ready for Step 2 (Authentication).${NC}"
else
    echo -e "${RED}Infrastructure deployment failed!${NC}"
    exit 1
fi