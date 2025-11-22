#!/usr/bin/env python3
"""
Test the Daily Nuggets Lambda function by invoking it with different UTC hours
to verify the fix is working correctly.
"""

import boto3
import json
from datetime import datetime

lambda_client = boto3.client('lambda', region_name='us-east-1')

def test_hour(hour_utc):
    """Test Daily Nuggets Lambda with a specific UTC hour"""
    print(f"\n🔍 Testing UTC hour {hour_utc:02d}:00...")

    # Create the event that EventBridge would send
    test_event = {
        "source": "aws.scheduler",
        "detail": {
            "hour_utc": hour_utc
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

        if response.get('StatusCode') == 200:
            if 'body' in response_payload:
                body = json.loads(response_payload['body'])
                print(f"✅ Success! {body.get('message', '')}")
                print(f"   Sent: {body.get('sent', 0)} emails")
                print(f"   Failed: {body.get('failed', 0)} emails")
            else:
                print(f"✅ Lambda executed: {response_payload}")
        else:
            print(f"❌ Error: Status {response.get('StatusCode')}")
            print(f"   Response: {response_payload}")

    except Exception as e:
        print(f"❌ Failed to invoke Lambda: {str(e)}")

def main():
    """Test the hours when emails should be sent"""
    print("🚀 TESTING DAILY NUGGETS LAMBDA FUNCTION")
    print("=" * 50)

    # Get current UTC hour
    current_utc_hour = datetime.utcnow().hour
    print(f"Current UTC time: {datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')} UTC")

    # Test the hours when our users should receive emails
    # Based on Eastern Time (UTC-4 during DST):
    # - rob@catalyst.technology: 7 AM ET = 11 UTC
    # - macbobbu@mac.com: 8 AM ET = 12 UTC
    # - robertjosephdaly@gmail.com: 9 AM ET = 13 UTC

    test_hours = [11, 12, 13]

    print("\nTesting delivery hours for Eastern Time users:")
    for hour in test_hours:
        test_hour(hour)

    # Also test current hour to see what happens now
    if current_utc_hour not in test_hours:
        print(f"\nTesting current UTC hour ({current_utc_hour}):")
        test_hour(current_utc_hour)

if __name__ == '__main__':
    main()