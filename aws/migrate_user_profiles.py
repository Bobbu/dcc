#!/usr/bin/env python3
"""
Migration script to add push notification fields to existing user profiles.
Run this once to update the DynamoDB schema for push notification support.
"""

import boto3
import json
from decimal import Decimal
from datetime import datetime

# Initialize DynamoDB
dynamodb = boto3.resource('dynamodb', region_name='us-east-1')

def migrate_user_profiles():
    """Add push notification fields to existing user profiles."""
    
    # Use the subscriptions table since that's where user profile data is stored
    table_name = 'dcc-subscriptions'
    
    print(f"Migrating table: {table_name}")
    table = dynamodb.Table(table_name)
    
    # Scan all existing profiles
    response = table.scan()
    items = response['Items']
    
    # Handle pagination
    while 'LastEvaluatedKey' in response:
        response = table.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
        items.extend(response['Items'])
    
    print(f"Found {len(items)} subscription profiles to migrate")
    
    # Update each profile with new fields if they don't exist
    migrated_count = 0
    for item in items:
        email = item['email']
        
        # Check if already migrated
        if 'notificationPreferences' in item:
            print(f"User {email} already migrated, skipping...")
            continue
        
        # Prepare update expression
        update_expression = "SET "
        expression_values = {}
        expression_names = {}
        
        # Add FCM tokens structure (empty initially)
        if 'fcmTokens' not in item:
            update_expression += "#fcm = :fcm, "
            expression_names['#fcm'] = 'fcmTokens'
            expression_values[':fcm'] = {
                'ios': None,
                'android': None,
                'web': None
            }
        
        # Add notification preferences with defaults
        if 'notificationPreferences' not in item:
            update_expression += "#prefs = :prefs, "
            expression_names['#prefs'] = 'notificationPreferences'
            
            # Keep email enabled if user has existing subscription
            enable_email = item.get('is_subscribed', False)
            
            expression_values[':prefs'] = {
                'enableEmail': enable_email,
                'enablePush': False,  # Opt-in for push
                'preferredTime': '08:00',  # Default 8 AM
                'timezone': item.get('timezone', 'America/New_York')  # Use existing or default
            }
        
        # Add notification stats
        if 'notificationStats' not in item:
            update_expression += "#stats = :stats"
            expression_names['#stats'] = 'notificationStats'
            expression_values[':stats'] = {
                'lastPushSent': None,
                'lastOpened': None,
                'openCount': Decimal(0),
                'emailOpenCount': Decimal(0),
                'pushOpenCount': Decimal(0)
            }
        
        # Remove trailing comma and space
        update_expression = update_expression.rstrip(', ')
        
        try:
            # Update the item
            table.update_item(
                Key={'email': email},
                UpdateExpression=update_expression,
                ExpressionAttributeNames=expression_names,
                ExpressionAttributeValues=expression_values
            )
            migrated_count += 1
            print(f"✓ Migrated user {email}")
        except Exception as e:
            print(f"✗ Failed to migrate user {email}: {str(e)}")
    
    print(f"\nMigration complete! Migrated {migrated_count} profiles")
    
    # Create a sample migrated profile for testing
    print("\nSample migrated profile structure:")
    if items:
        sample = table.get_item(Key={'email': items[0]['email']})['Item']
        print(json.dumps(
            {
                'email': sample.get('email'),
                'fcmTokens': sample.get('fcmTokens'),
                'notificationPreferences': sample.get('notificationPreferences'),
                'notificationStats': sample.get('notificationStats')
            },
            indent=2,
            default=str
        ))

if __name__ == "__main__":
    migrate_user_profiles()