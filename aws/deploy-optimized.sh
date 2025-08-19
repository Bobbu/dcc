#!/bin/bash

# Deploy optimized Lambda functions using existing infrastructure
# This updates the current functions to use the optimized table and handlers

set -e

echo "🚀 Deploying Optimized Lambda Functions..."

# Source environment variables
source .env.deployment

# Update quote handler to use optimized version
echo "📦 Updating quote handler..."
cd lambda
zip -r ../quote-handler-optimized.zip quote_handler_optimized.py
cd ..
aws lambda update-function-code \
  --function-name dcc-quote-handler \
  --zip-file fileb://quote-handler-optimized.zip

# Wait for code update to complete before updating configuration
echo "⏳ Waiting for quote handler code update to complete..."
aws lambda wait function-updated --function-name dcc-quote-handler

aws lambda update-function-configuration \
  --function-name dcc-quote-handler \
  --handler quote_handler_optimized.lambda_handler \
  --environment Variables="{TABLE_NAME=dcc-quotes-optimized,ENVIRONMENT=dev}"

# Update admin handler to use optimized version
echo "📦 Updating admin handler..."
cd lambda
zip -r ../admin-handler-optimized.zip admin_handler_optimized.py
cd ..
aws lambda update-function-code \
  --function-name dcc-admin-handler \
  --zip-file fileb://admin-handler-optimized.zip

# Wait for admin handler code update to complete before updating configuration
echo "⏳ Waiting for admin handler code update to complete..."
aws lambda wait function-updated --function-name dcc-admin-handler

aws lambda update-function-configuration \
  --function-name dcc-admin-handler \
  --handler admin_handler_optimized.lambda_handler \
  --environment Variables="{TABLE_NAME=dcc-quotes-optimized,USER_POOL_ID=us-east-1_ecyuILBAu,ENVIRONMENT=dev}"

echo "🎯 Updating Lambda permissions for optimized table..."

# Update IAM policies to access the optimized table
echo "🔍 Getting Lambda function roles..."
QUOTE_FUNCTION_ROLE=$(aws lambda get-function-configuration --function-name dcc-quote-handler --query 'Role' --output text | cut -d'/' -f2)
ADMIN_FUNCTION_ROLE=$(aws lambda get-function-configuration --function-name dcc-admin-handler --query 'Role' --output text | cut -d'/' -f2)

echo "Quote function role: $QUOTE_FUNCTION_ROLE"
echo "Admin function role: $ADMIN_FUNCTION_ROLE"

# Create policy document for optimized table access
cat > optimized-table-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:UpdateItem",
                "dynamodb:DeleteItem",
                "dynamodb:Query",
                "dynamodb:Scan",
                "dynamodb:BatchGetItem",
                "dynamodb:BatchWriteItem",
                "dynamodb:TransactWriteItems"
            ],
            "Resource": [
                "arn:aws:dynamodb:us-east-1:*:table/dcc-quotes-optimized",
                "arn:aws:dynamodb:us-east-1:*:table/dcc-quotes-optimized/index/*"
            ]
        }
    ]
}
EOF

# Create and attach the DynamoDB policy
aws iam put-role-policy \
  --role-name $QUOTE_FUNCTION_ROLE \
  --policy-name OptimizedTableAccess \
  --policy-document file://optimized-table-policy.json

aws iam put-role-policy \
  --role-name $ADMIN_FUNCTION_ROLE \
  --policy-name OptimizedTableAccess \
  --policy-document file://optimized-table-policy.json

# Create Cognito policy for admin handler
echo "🔐 Adding Cognito permissions for admin handler..."
cat > cognito-admin-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "cognito-idp:AdminGetUser",
                "cognito-idp:ListUsersInGroup"
            ],
            "Resource": "arn:aws:cognito-idp:us-east-1:*:userpool/us-east-1_ecyuILBAu"
        }
    ]
}
EOF

aws iam put-role-policy \
  --role-name $ADMIN_FUNCTION_ROLE \
  --policy-name CognitoAdminAccess \
  --policy-document file://cognito-admin-policy.json

# Clean up
rm -f quote-handler-optimized.zip admin-handler-optimized.zip optimized-table-policy.json cognito-admin-policy.json

echo "✅ Optimized Lambda functions deployed successfully!"
echo ""
echo "🔗 Updated Functions:"
echo "  • dcc-quote-handler → quote_handler_optimized.py"
echo "  • dcc-admin-handler → admin_handler_optimized.py"
echo ""
echo "📊 New Table: dcc-quotes-optimized"
echo "🎯 Environment: dev"
echo ""
echo "Next step: Test the optimized API endpoints!"