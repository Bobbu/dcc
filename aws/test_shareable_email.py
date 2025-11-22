#!/usr/bin/env python3
"""
Test the new shareable Daily Nuggets email by sending a test email
"""

import boto3
import json

lambda_client = boto3.client('lambda', region_name='us-east-1')

def send_test_email():
    """Send a test Daily Nuggets email to rob@catalyst.technology"""

    print("🚀 Sending test Daily Nuggets email with sharing features...")

    # Create a test event that simulates an API request
    test_event = {
        "httpMethod": "POST",
        "path": "/subscriptions/test",
        "requestContext": {
            "authorizer": {
                "claims": {
                    "email": "rob@catalyst.technology",
                    "cognito:groups": "Admins"
                }
            }
        }
    }

    try:
        # Invoke the Lambda function
        response = lambda_client.invoke(
            FunctionName='quote-me-daily-nuggets-handler',
            InvocationType='RequestResponse',
            Payload=json.dumps(test_event)
        )

        # Parse the response
        response_payload = json.loads(response['Payload'].read())

        if response.get('StatusCode') == 200 and response_payload.get('statusCode') == 200:
            body = json.loads(response_payload['body'])
            print(f"✅ {body.get('message', 'Email sent successfully!')}")
            if 'quote' in body:
                quote = body['quote']
                print(f"\n📧 Email sent with quote:")
                print(f"   \"{quote['quote'][:100]}...\"")
                print(f"   — {quote['author']}")
                print(f"\n🔗 The email includes:")
                print(f"   • Social sharing buttons (Twitter, Facebook, LinkedIn, Email)")
                print(f"   • View in Browser link: https://quote-me.anystupididea.com/quote/{quote['id']}")
                print(f"   • Open in App link: quoteme:///quote/{quote['id']}")
        else:
            print(f"❌ Error: {response_payload}")
    except Exception as e:
        print(f"❌ Failed to send test email: {str(e)}")

if __name__ == '__main__':
    send_test_email()