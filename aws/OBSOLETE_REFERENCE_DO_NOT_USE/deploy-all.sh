#!/bin/bash

# Master Deployment Script
# Orchestrates complete DCC system deployment in 5 steps
# Target total time: < 5 minutes

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

DEPLOYMENT_START=$(date +%s)

echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║                    DCC DEPLOYMENT SYSTEM                    ║${NC}"
echo -e "${BOLD}${BLUE}║                Complete Infrastructure Setup                 ║${NC}"
echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Function to log step timing
log_step() {
    local step_num=$1
    local step_name=$2
    local start_time=$3
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo -e "${GREEN}✓ Step $step_num ($step_name) completed in ${duration}s${NC}"
    echo ""
}

# Function to handle errors
handle_error() {
    local step_num=$1
    local step_name=$2
    echo -e "${RED}✗ Step $step_num ($step_name) failed!${NC}"
    echo -e "${YELLOW}Deployment stopped. Fix the error and re-run deploy-all.sh${NC}"
    exit 1
}

echo -e "${YELLOW}Starting complete DCC deployment...${NC}"
echo ""

# Pre-flight checks
echo -e "${BLUE}Running pre-flight checks...${NC}"
if [ ! -f .env.deployment ]; then
    echo -e "${RED}Error: .env.deployment not found. Run ./validate.sh first.${NC}"
    exit 1
fi

if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI not installed${NC}"
    exit 1
fi

if ! command -v sam &> /dev/null; then
    echo -e "${RED}Error: SAM CLI not installed${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Pre-flight checks passed${NC}"
echo ""

# Step 1: Infrastructure
echo -e "${BLUE}STEP 1/5: Infrastructure (S3, DynamoDB, SQS)${NC}"
STEP_START=$(date +%s)
if ./01-deploy-infrastructure.sh; then
    log_step 1 "Infrastructure" $STEP_START
else
    handle_error 1 "Infrastructure"
fi

# Step 2: Authentication
echo -e "${BLUE}STEP 2/5: Authentication (Cognito, IAM, OAuth)${NC}"
STEP_START=$(date +%s)
if ./02-deploy-auth.sh; then
    log_step 2 "Authentication" $STEP_START
else
    handle_error 2 "Authentication"
fi

# Step 3: Core API
echo -e "${BLUE}STEP 3/5: Core API (Lambda, API Gateway)${NC}"
STEP_START=$(date +%s)
if ./03-deploy-core-api.sh; then
    log_step 3 "Core API" $STEP_START
else
    handle_error 3 "Core API"
fi

# Step 4: Extended Services
echo -e "${BLUE}STEP 4/5: Extended Services (Image Gen, Notifications)${NC}"
STEP_START=$(date +%s)
if ./04-deploy-services.sh; then
    log_step 4 "Extended Services" $STEP_START
else
    handle_error 4 "Extended Services"
fi

# Step 5: Integration Tests
echo -e "${BLUE}STEP 5/5: Integration Tests${NC}"
STEP_START=$(date +%s)
if ./05-test-deployment.sh; then
    log_step 5 "Integration Tests" $STEP_START
else
    handle_error 5 "Integration Tests"
fi

# Calculate total time
DEPLOYMENT_END=$(date +%s)
TOTAL_TIME=$((DEPLOYMENT_END - DEPLOYMENT_START))

echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║                   DEPLOYMENT SUCCESSFUL!                    ║${NC}"
echo -e "${BOLD}${GREEN}║                                                              ║${NC}"
echo -e "${BOLD}${GREEN}║   Total deployment time: ${TOTAL_TIME} seconds                        ║${NC}"
echo -e "${BOLD}${GREEN}║   All systems operational and tested                        ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Display final system information
echo -e "${YELLOW}System Information:${NC}"
API_URL=$(aws cloudformation describe-stacks --stack-name dcc-core-api --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' --output text 2>/dev/null || echo "Not deployed")
echo "API URL: $API_URL"

S3_BUCKET=$(aws cloudformation describe-stacks --stack-name dcc-infrastructure --query 'Stacks[0].Outputs[?OutputKey==`QuoteImagesBucketName`].OutputValue' --output text 2>/dev/null || echo "Not deployed")
echo "Images Bucket: $S3_BUCKET"

echo ""
echo -e "${GREEN}Ready for testing! Try: curl $API_URL/quote${NC}"