#!/usr/bin/env python3
"""
Update existing subscriptions with delivery hour preferences based on user's settings.
This fixes the issue where EventBridge was sending emails to all subscribers regardless
of their preferred delivery time.
"""

import boto3
import json
from datetime import datetime

dynamodb = boto3.resource('dynamodb', region_name='us-east-1')
table = dynamodb.Table('quote-me-subscriptions')

# Map of user emails to their preferred delivery hours
# Based on your testing, these are the delivery times you set:
user_preferences = {
    'rob@catalyst.technology': 7,        # 7:00 AM
    'macbobbu@mac.com': 8,                # 8:00 AM
    'robertjosephdaly@gmail.com': 9       # 9:00 AM
}

def update_subscriptions():
    """Update existing subscriptions with delivery hour preferences"""

    # Scan all subscriptions
    response = table.scan()
    subscriptions = response.get('Items', [])

    updated_count = 0

    for subscription in subscriptions:
        email = subscription.get('email')
        notification_prefs = subscription.get('notificationPreferences', {})

        # Determine delivery hour
        if email in user_preferences:
            delivery_hour = user_preferences[email]
            print(f"Setting {email} to custom delivery hour: {delivery_hour}:00")
        else:
            delivery_hour = 8  # Default to 8 AM
            print(f"Setting {email} to default delivery hour: {delivery_hour}:00")

        # Update notification preferences with delivery hour
        if 'deliveryHour' not in notification_prefs:
            notification_prefs['deliveryHour'] = delivery_hour

            # Update the item in DynamoDB
            try:
                table.update_item(
                    Key={'email': email},
                    UpdateExpression='SET notificationPreferences = :prefs, updated_at = :now',
                    ExpressionAttributeValues={
                        ':prefs': notification_prefs,
                        ':now': datetime.utcnow().isoformat()
                    }
                )
                updated_count += 1
                print(f"✅ Updated {email} with delivery hour {delivery_hour}")
            except Exception as e:
                print(f"❌ Error updating {email}: {str(e)}")
        else:
            print(f"⏭️  Skipping {email} - already has delivery hour: {notification_prefs['deliveryHour']}")

    print(f"\n🎉 Update complete! Updated {updated_count} subscriptions")

    # Verify the updates
    print("\n📋 Current subscription status:")
    response = table.scan()
    for item in response.get('Items', []):
        prefs = item.get('notificationPreferences', {})
        delivery_hour = prefs.get('deliveryHour', 'Not set')
        timezone = item.get('timezone', 'Not set')
        print(f"  {item['email']}: {timezone} at {delivery_hour}:00")

if __name__ == '__main__':
    update_subscriptions()