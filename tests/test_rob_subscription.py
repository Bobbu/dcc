#!/usr/bin/env python3

"""
Test subscription for rob@catalyst.technology
"""

import boto3
import json
from decimal import Decimal

# DynamoDB client
dynamodb = boto3.resource('dynamodb', region_name='us-east-1')
subscriptions_table = dynamodb.Table('dcc-subscriptions')

def decimal_default(obj):
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError

def check_rob_subscription():
    """Check Rob's subscription status"""
    email = "rob@catalyst.technology"
    print(f"🔍 Checking subscription for: {email}")
    print("=" * 50)
    
    try:
        response = subscriptions_table.get_item(
            Key={'email': email}
        )
        
        if 'Item' in response:
            item = response['Item']
            print("✅ Subscription found:")
            print(f"  Email: {item.get('email')}")
            print(f"  Subscribed: {item.get('is_subscribed')}")
            print(f"  Delivery Method: {item.get('delivery_method')}")
            print(f"  Timezone: {item.get('timezone')}")
            print(f"  Created: {item.get('created_at')}")
            print(f"  Updated: {item.get('updated_at')}")
            
            # Verify data types
            print(f"\n🔍 Data type analysis:")
            print(f"  is_subscribed type: {type(item.get('is_subscribed'))}")
            print(f"  is_subscribed value: {repr(item.get('is_subscribed'))}")
            
            return item
        else:
            print("❌ No subscription found")
            return None
            
    except Exception as e:
        print(f"❌ Error: {e}")
        return None

if __name__ == "__main__":
    print("🧪 Rob's Subscription Test")
    print("=" * 30)
    check_rob_subscription()
    
    print("\n📋 Next steps:")
    print("1. If is_subscribed is True in DB, but False in web app:")
    print("   - Check Flutter web app JWT token extraction")
    print("   - Check if subscription API call is failing")
    print("   - Check browser dev tools for network errors")
    print("2. If is_subscribed is False in DB:")
    print("   - The subscription was never saved properly")