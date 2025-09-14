#!/bin/bash

# Complete DCC API Deployment - Scorched Earth Rebuild
# This deploys everything including custom domain mapping

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== DCC API COMPLETE DEPLOYMENT (SCORCHED EARTH) ===${NC}"
echo "This will deploy the complete system with custom domain mapping"
echo ""

# Load environment variables
if [ -f .env.deployment ]; then
    source .env.deployment
    echo -e "${GREEN}✓ Environment variables loaded${NC}"
else
    echo -e "${RED}Error: .env.deployment not found${NC}"
    exit 1
fi

# Check for FCM service account JSON (optional)
FCM_SERVICE_ACCOUNT_FILE="./more_secrets/fcm-service-account.json"
FCM_SERVICE_ACCOUNT_JSON=""

if [ -f "$FCM_SERVICE_ACCOUNT_FILE" ]; then
    echo -e "${GREEN}📋 FCM service account JSON found${NC}"
    FCM_SERVICE_ACCOUNT_JSON=$(cat "$FCM_SERVICE_ACCOUNT_FILE" | jq -c . 2>/dev/null)
fi

# Build the application
echo -e "${YELLOW}Building SAM application...${NC}"
sam build --template template-complete.yaml --cached

if [ $? -ne 0 ]; then
    echo -e "${RED}Build failed!${NC}"
    exit 1
fi

echo -e "${YELLOW}Deploying Complete DCC System...${NC}"

# Create S3 bucket if it doesn't exist
BUCKET_NAME="dcc-sam-deployments-$(aws sts get-caller-identity --query Account --output text)"
aws s3 mb s3://$BUCKET_NAME --region us-east-1 2>/dev/null || echo "Bucket already exists"

# Deploy with all parameters
STACK_NAME="dcc-api-complete"

echo "Deployment started at $(date)" > deployment.log

if [ -n "$FCM_SERVICE_ACCOUNT_JSON" ]; then
    sam deploy \
        --template-file .aws-sam/build/template.yaml \
        --stack-name $STACK_NAME \
        --capabilities CAPABILITY_NAMED_IAM \
        --no-confirm-changeset \
        --parameter-overrides \
            OpenAIApiKey="$OPENAI_API_KEY" \
            FCMServiceAccountJSON="$FCM_SERVICE_ACCOUNT_JSON" \
        --s3-bucket $BUCKET_NAME \
        --s3-prefix dcc-api-complete 2>&1 | tee -a deployment.log
else
    sam deploy \
        --template-file .aws-sam/build/template.yaml \
        --stack-name $STACK_NAME \
        --capabilities CAPABILITY_NAMED_IAM \
        --no-confirm-changeset \
        --parameter-overrides \
            OpenAIApiKey="$OPENAI_API_KEY" \
        --s3-bucket $BUCKET_NAME \
        --s3-prefix dcc-api-complete 2>&1 | tee -a deployment.log
fi

DEPLOY_STATUS=$?

if [ $DEPLOY_STATUS -eq 0 ]; then
    echo -e "${GREEN}✓ Deployment successful!${NC}"
    echo ""
    
    # Get outputs
    API_URL=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' \
        --output text)
    
    USER_POOL_ID=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --query 'Stacks[0].Outputs[?OutputKey==`UserPoolId`].OutputValue' \
        --output text)
    
    USER_POOL_CLIENT_ID=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --query 'Stacks[0].Outputs[?OutputKey==`UserPoolClientId`].OutputValue' \
        --output text)
    
    echo "API URL: $API_URL"
    echo "User Pool ID: $USER_POOL_ID"
    echo "User Pool Client ID: $USER_POOL_CLIENT_ID"
    echo ""
    
    # Get API key (create if needed)
    API_ID=$(aws apigateway get-rest-apis --query 'items[?name==`dcc-api`].id' --output text)
    if [ -n "$API_ID" ]; then
        echo "Setting up API key and usage plan..."
        
        # Try to find existing API key
        API_KEY_ID=$(aws apigateway get-api-keys --query "items[?stageKeys[?contains(@, '$API_ID')]].id" --output text | head -1)
        
        if [ -z "$API_KEY_ID" ]; then
            # Create API key if it doesn't exist
            echo "Creating new API key..."
            API_KEY_RESULT=$(aws apigateway create-api-key --name dcc-api-key --enabled --stage-keys restApiId=$API_ID,stageName=prod)
            API_KEY_ID=$(echo "$API_KEY_RESULT" | jq -r '.id')
            API_KEY_VALUE=$(echo "$API_KEY_RESULT" | jq -r '.value')
            
            # Create usage plan
            echo "Creating usage plan..."
            USAGE_PLAN_ID=$(aws apigateway create-usage-plan \
                --name dcc-usage-plan \
                --description "Usage plan for DCC API" \
                --throttle rateLimit=10,burstLimit=20 \
                --quota limit=1000,period=DAY \
                --api-stages apiId=$API_ID,stage=prod \
                --query 'id' --output text)
            
            # Associate API key with usage plan
            aws apigateway create-usage-plan-key \
                --usage-plan-id $USAGE_PLAN_ID \
                --key-id $API_KEY_ID \
                --key-type API_KEY > /dev/null
            
            echo "✓ API key and usage plan configured"
        else
            API_KEY_VALUE=$(aws apigateway get-api-key --api-key $API_KEY_ID --include-value --query value --output text)
            echo "✓ Using existing API key"
        fi
        
        echo "API Key: $API_KEY_VALUE"
        
        # Update .env file in mobile app
        ENV_FILE="../dcc_mobile/.env"
        if [ -f "$ENV_FILE" ]; then
            echo ""
            echo "Updating $ENV_FILE with new values..."
            sed -i.bak "s|API_ENDPOINT=.*|API_ENDPOINT=$API_URL/quote|" "$ENV_FILE"
            sed -i.bak "s|API_KEY=.*|API_KEY=$API_KEY_VALUE|" "$ENV_FILE"
            sed -i.bak "s|API_URL=.*|API_URL=$API_URL|" "$ENV_FILE"
            sed -i.bak "s|USER_POOL_ID=.*|USER_POOL_ID=$USER_POOL_ID|" "$ENV_FILE"
            sed -i.bak "s|USER_POOL_CLIENT_ID=.*|USER_POOL_CLIENT_ID=$USER_POOL_CLIENT_ID|" "$ENV_FILE"
            echo "✓ App configuration updated"
        fi
    fi
    
    echo ""
    echo -e "${GREEN}Complete system deployed successfully!${NC}"
    echo "Custom domain: https://dcc.anystupididea.com"
    if [ -n "$FCM_SERVICE_ACCOUNT_JSON" ]; then
        echo "Push notifications: Enabled"
    fi
else
    echo -e "${RED}Deployment failed!${NC}"
    exit 1
fi