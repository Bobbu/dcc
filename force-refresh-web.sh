#!/bin/bash

# Simple script to force refresh the web app by invalidating CloudFront cache
# Run this after making changes to immediately bust the cache

set -e

STACK_NAME="${1:-quote-me-web-app}"
REGION="${2:-us-east-1}"

echo "🔄 Force refreshing web app cache..."
echo "Stack: $STACK_NAME"
echo "Region: $REGION"

# Get CloudFront distribution ID
DISTRIBUTION_ID=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    --query "Stacks[0].Outputs[?OutputKey=='CloudFrontDistributionId'].OutputValue" \
    --output text 2>/dev/null)

if [ -z "$DISTRIBUTION_ID" ]; then
    echo "❌ Could not retrieve CloudFront distribution ID"
    echo "Make sure the stack '$STACK_NAME' exists and has been deployed"
    exit 1
fi

echo "CloudFront Distribution: $DISTRIBUTION_ID"

# Create aggressive cache invalidation
echo "Creating cache invalidation..."
INVALIDATION_ID=$(aws cloudfront create-invalidation \
    --distribution-id $DISTRIBUTION_ID \
    --paths "/*" \
    --region $REGION \
    --query "Invalidation.Id" \
    --output text)

echo "✅ Cache invalidation created: $INVALIDATION_ID"
echo ""
echo "⏰ The cache invalidation will take 1-5 minutes to propagate."
echo "💡 For immediate testing:"
echo "   • Hard refresh: Ctrl+Shift+R (Win/Linux) or Cmd+Shift+R (Mac)"
echo "   • Use incognito/private browsing mode"
echo "   • Open DevTools → Network → Check 'Disable cache'"
echo ""
echo "📊 Monitor invalidation status:"
echo "   aws cloudfront get-invalidation --distribution-id $DISTRIBUTION_ID --id $INVALIDATION_ID"