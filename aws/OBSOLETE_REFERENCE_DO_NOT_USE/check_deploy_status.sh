#!/bin/bash

# Deployment status monitoring script for DCC API

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

STACK_NAME="dcc-demo-sam-app"

# Function to get status with emoji
get_status_display() {
    local status=$1
    case $status in
        "CREATE_COMPLETE"|"UPDATE_COMPLETE")
            echo -e "${GREEN}✅ $status${NC}"
            ;;
        "CREATE_IN_PROGRESS"|"UPDATE_IN_PROGRESS")
            echo -e "${YELLOW}🔄 $status${NC}"
            ;;
        "CREATE_FAILED"|"UPDATE_FAILED"|"UPDATE_ROLLBACK_COMPLETE"|"UPDATE_ROLLBACK_FAILED")
            echo -e "${RED}❌ $status${NC}"
            ;;
        "UPDATE_ROLLBACK_IN_PROGRESS"|"DELETE_IN_PROGRESS")
            echo -e "${YELLOW}🔙 $status${NC}"
            ;;
        *)
            echo -e "${BLUE}ℹ️  $status${NC}"
            ;;
    esac
}

echo -e "${BLUE}DCC API Deployment Status Monitor${NC}"
echo "=================================="

# Check if stack exists
aws cloudformation describe-stacks --stack-name $STACK_NAME > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Stack '$STACK_NAME' not found${NC}"
    echo "Have you run ./deploy.sh yet?"
    exit 1
fi

# Get current status
RESULT=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[0].{Status:StackStatus,Updated:LastUpdatedTime,Created:CreationTime}" --output json)
STATUS=$(echo $RESULT | jq -r '.Status')
UPDATED=$(echo $RESULT | jq -r '.Updated // .Created' | cut -d'T' -f1,2 | tr 'T' ' ')

echo -e "Stack: ${BLUE}$STACK_NAME${NC}"
echo -e "Status: $(get_status_display $STATUS)"
echo -e "Last Updated: ${BLUE}$UPDATED UTC${NC}"
echo ""

# Show appropriate next steps based on status
case $STATUS in
    "UPDATE_IN_PROGRESS"|"CREATE_IN_PROGRESS")
        echo -e "${YELLOW}🔄 Deployment in progress...${NC}"
        echo ""
        echo "Monitor in real-time with:"
        echo "  watch -n 10 './check_deploy_status.sh'"
        echo ""
        echo "Or see detailed events:"
        echo "  aws cloudformation describe-stack-events --stack-name $STACK_NAME --query 'StackEvents[0:10].[LogicalResourceId,ResourceStatus,Timestamp]' --output table"
        ;;
    "UPDATE_COMPLETE"|"CREATE_COMPLETE")
        echo -e "${GREEN}✅ Deployment successful!${NC}"
        echo ""
        echo "API endpoints:"
        API_URL=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='ApiUrl'].OutputValue" --output text)
        echo -e "  ${GREEN}$API_URL${NC}"
        echo ""
        echo "Test your deployment:"
        echo "  curl $API_URL/quote"
        ;;
    "UPDATE_ROLLBACK_COMPLETE"|"UPDATE_ROLLBACK_FAILED"|"CREATE_FAILED")
        echo -e "${RED}❌ Deployment failed${NC}"
        echo ""
        echo "Check recent events for errors:"
        echo "  aws cloudformation describe-stack-events --stack-name $STACK_NAME --query 'StackEvents[?ResourceStatusReason!=null][0:5].[LogicalResourceId,ResourceStatus,ResourceStatusReason]' --output table"
        echo ""
        echo "Try deploying again:"
        echo "  ./validate.sh && ./deploy.sh"
        ;;
    "UPDATE_ROLLBACK_IN_PROGRESS")
        echo -e "${YELLOW}🔙 Rolling back failed deployment...${NC}"
        echo ""
        echo "Wait for rollback to complete, then check logs:"
        echo "  ./check_deploy_status.sh"
        ;;
    *)
        echo -e "${BLUE}ℹ️  Status: $STATUS${NC}"
        ;;
esac

# Always use deployment.log - ONE consistent log file
if [ -f "deployment.log" ]; then
    echo ""
    echo -e "${BLUE}Recent deployment log:${NC}"
    echo "----------------------"
    tail -5 deployment.log
    echo ""
    echo "Full log: tail -f deployment.log"
fi