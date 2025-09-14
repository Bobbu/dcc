#!/bin/bash

# Step 1: Deploy ONLY S3 bucket and policy
# This should take seconds, not minutes

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

STACK_NAME="dcc-s3-images"

echo -e "${GREEN}=== S3 Bucket Deployment ===${NC}"
echo "Deploying S3 bucket and public access policy ONLY"
echo ""

# Check if stack exists
aws cloudformation describe-stacks --stack-name $STACK_NAME > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${YELLOW}Stack $STACK_NAME already exists. Updating...${NC}"
    OPERATION="update"
else
    echo -e "${GREEN}Creating new stack $STACK_NAME${NC}"
    OPERATION="create"
fi

# Deploy the S3-only template
echo -e "${YELLOW}Deploying S3 resources...${NC}"
aws cloudformation deploy \
    --template-file s3-only-template.yaml \
    --stack-name $STACK_NAME \
    --capabilities CAPABILITY_IAM \
    --no-fail-on-empty-changeset

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ S3 deployment successful!${NC}"
    echo ""
    
    # Get outputs
    BUCKET_NAME=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' --output text)
    BUCKET_URL=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query 'Stacks[0].Outputs[?OutputKey==`BucketURL`].OutputValue' --output text)
    
    echo "Bucket Name: $BUCKET_NAME"
    echo "Bucket URL: $BUCKET_URL"
    echo ""
    
    # Test public access
    echo -e "${YELLOW}Testing public access...${NC}"
    
    # Create a test file
    echo "Test image placeholder" > /tmp/test-image.txt
    
    # Upload test file
    aws s3 cp /tmp/test-image.txt s3://$BUCKET_NAME/test-image.txt
    
    # Try to access it publicly
    curl -s -o /dev/null -w "%{http_code}" $BUCKET_URL/test-image.txt > /tmp/status_code
    STATUS=$(cat /tmp/status_code)
    
    if [ "$STATUS" = "200" ]; then
        echo -e "${GREEN}✓ Public access working! (HTTP $STATUS)${NC}"
    else
        echo -e "${RED}✗ Public access not working (HTTP $STATUS)${NC}"
        echo "This might be normal if the policy needs time to propagate."
    fi
    
    # Clean up test file
    aws s3 rm s3://$BUCKET_NAME/test-image.txt
    rm /tmp/test-image.txt /tmp/status_code
    
    echo ""
    echo -e "${GREEN}S3 infrastructure ready for image storage!${NC}"
    echo ""
    echo "Next step: Run ./deploy-lambdas.sh to deploy Lambda functions"
else
    echo -e "${RED}S3 deployment failed!${NC}"
    exit 1
fi