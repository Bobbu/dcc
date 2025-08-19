#!/bin/bash

# Full deployment script for DCC API Optimized version
# This deploys the complete optimized infrastructure from scratch

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

set -e

echo -e "${GREEN}🚀 Starting DCC API Optimized Deployment...${NC}"

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

# Set default parameters
STACK_NAME=${STACK_NAME:-dcc-optimized}
ENVIRONMENT=${ENVIRONMENT:-dev}
CUSTOM_DOMAIN=${CUSTOM_DOMAIN:-""}
CERTIFICATE_ARN=${CERTIFICATE_ARN:-""}

echo -e "${BLUE}📋 Deployment Configuration:${NC}"
echo "  Stack Name: $STACK_NAME"
echo "  Environment: $ENVIRONMENT"
echo "  Custom Domain: ${CUSTOM_DOMAIN:-"(none)"}"
echo "  Certificate: ${CERTIFICATE_ARN:-"(none)"}"
echo ""

# Build SAM application with optimized template
echo -e "${YELLOW}🔨 Building SAM application with optimized template...${NC}"
sam build --template template-optimized.yaml

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Build failed!${NC}"
    exit 1
fi

# Deploy using SAM
echo -e "${YELLOW}☁️  Deploying to AWS...${NC}"
if [ -n "$CUSTOM_DOMAIN" ] && [ -n "$CERTIFICATE_ARN" ]; then
    echo "Deploying with custom domain: $CUSTOM_DOMAIN"
    sam deploy \
        --stack-name "$STACK_NAME" \
        --template .aws-sam/build/template.yaml \
        --capabilities CAPABILITY_IAM \
        --parameter-overrides \
            OpenAIApiKey="$OPENAI_API_KEY" \
            Environment="$ENVIRONMENT" \
            CustomDomainName="$CUSTOM_DOMAIN" \
            CertificateArn="$CERTIFICATE_ARN" \
        --resolve-s3
else
    echo "Deploying without custom domain"
    sam deploy \
        --stack-name "$STACK_NAME" \
        --template .aws-sam/build/template.yaml \
        --capabilities CAPABILITY_IAM \
        --parameter-overrides \
            OpenAIApiKey="$OPENAI_API_KEY" \
            Environment="$ENVIRONMENT" \
        --resolve-s3
fi

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Deployment successful!${NC}"
    echo ""
    
    # Get stack outputs
    echo -e "${BLUE}📊 Getting deployment outputs...${NC}"
    API_ENDPOINT=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
        --output text)
    
    API_KEY=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query 'Stacks[0].Outputs[?OutputKey==`ApiKeyValue`].OutputValue' \
        --output text)
    
    USER_POOL_ID=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query 'Stacks[0].Outputs[?OutputKey==`UserPoolId`].OutputValue' \
        --output text)
    
    USER_POOL_CLIENT_ID=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query 'Stacks[0].Outputs[?OutputKey==`UserPoolClientId`].OutputValue' \
        --output text)
    
    CUSTOM_DOMAIN_URL=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query 'Stacks[0].Outputs[?OutputKey==`CustomDomainUrl`].OutputValue' \
        --output text 2>/dev/null)
    
    echo -e "${GREEN}🎉 Optimized DCC API Deployed Successfully!${NC}"
    echo ""
    echo -e "${BLUE}📡 API Endpoints:${NC}"
    if [ -n "$CUSTOM_DOMAIN_URL" ] && [ "$CUSTOM_DOMAIN_URL" != "None" ]; then
        echo "  Custom Domain: $CUSTOM_DOMAIN_URL"
        BASE_URL="$CUSTOM_DOMAIN_URL"
    else
        echo "  API Gateway: $API_ENDPOINT"
        BASE_URL="$API_ENDPOINT"
    fi
    echo ""
    echo -e "${BLUE}🔑 API Configuration:${NC}"
    echo "  API Key: $API_KEY"
    echo "  User Pool ID: $USER_POOL_ID"
    echo "  User Pool Client ID: $USER_POOL_CLIENT_ID"
    echo ""
    echo -e "${BLUE}🧪 Test Your API:${NC}"
    echo "  curl -H \"X-Api-Key: $API_KEY\" \"$BASE_URL/quote\""
    echo "  curl -H \"X-Api-Key: $API_KEY\" \"$BASE_URL/tags\""
    echo ""
    echo -e "${YELLOW}📱 Next Steps:${NC}"
    echo "1. Update your Flutter .env file with the new values:"
    echo "   API_ENDPOINT=$BASE_URL/quote"
    echo "   API_KEY=$API_KEY"
    echo "   API_URL=$BASE_URL"
    echo "   USER_POOL_ID=$USER_POOL_ID"
    echo "   USER_POOL_CLIENT_ID=$USER_POOL_CLIENT_ID"
    echo ""
    echo "2. Run data migration if needed:"
    echo "   python3 run_migration.py"
    echo ""
    echo "3. Create admin user in Cognito and add to 'Admins' group"
    echo ""
    echo -e "${GREEN}🔐 Security Note: Your OpenAI API key is securely stored in AWS Lambda.${NC}"
    
else
    echo -e "${RED}❌ Deployment failed!${NC}"
    exit 1
fi