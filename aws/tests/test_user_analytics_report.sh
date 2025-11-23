#!/bin/bash

# Test script to manually trigger the user analytics report
# This is useful for testing without waiting for the weekly schedule

set -e

echo "🧪 Testing User Analytics Report Function"
echo "=========================================="

# Get the function name from CloudFormation outputs
FUNCTION_NAME="quote-me-user-analytics-report"

echo ""
echo "📋 Function: $FUNCTION_NAME"
echo ""

# Invoke the Lambda function
echo "🚀 Invoking Lambda function..."
aws lambda invoke \
    --function-name "$FUNCTION_NAME" \
    --payload '{"source":"manual-test"}' \
    --cli-binary-format raw-in-base64-out \
    response.json

echo ""
echo "📊 Response:"
cat response.json | python3 -m json.tool

echo ""
echo ""
echo "✅ Test completed!"
echo ""
echo "📧 Check admin email inbox for the weekly report"
echo "📦 Check DynamoDB table 'quote-me-analytics-reports' for snapshot"

# Clean up
rm response.json
