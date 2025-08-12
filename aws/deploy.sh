#!/bin/bash

echo "Deploying DCC API to AWS..."

# Build and deploy the SAM application
sam build
# No need for guided once we have our samconfig.toml
sam deploy --guided
# sam deploy

echo "Deployment complete!"
echo "Don't forget to update the Flutter app with your API Gateway URL."