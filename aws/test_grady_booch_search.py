#!/usr/bin/env python3
"""
Test script to search for existing Grady Booch quotes in the database
"""

import boto3
import json
import requests
import os
from datetime import datetime

def authenticate_admin():
    """Authenticate as admin user"""
    cognito_client = boto3.client('cognito-idp', region_name='us-east-1')
    
    try:
        # Create a temporary admin user for testing
        username = f"test_admin_{int(datetime.now().timestamp())}"
        password = "TempAdminPass123!"
        
        # Create user
        try:
            cognito_client.admin_create_user(
                UserPoolId='us-east-1_WCJMgcwll',
                Username=username,
                TemporaryPassword=password,
                MessageAction='SUPPRESS'
            )
            print(f"Created temp admin user: {username}")
        except Exception as e:
            if "UsernameExistsException" not in str(e):
                print(f"Error creating user: {e}")
                return None
        
        # Set permanent password
        try:
            cognito_client.admin_set_user_password(
                UserPoolId='us-east-1_WCJMgcwll',
                Username=username,
                Password=password,
                Permanent=True
            )
        except Exception as e:
            print(f"Error setting password: {e}")
        
        # Add to Admins group
        try:
            cognito_client.admin_add_user_to_group(
                UserPoolId='us-east-1_WCJMgcwll',
                Username=username,
                GroupName='Admins'
            )
            print(f"Added {username} to Admins group")
        except Exception as e:
            print(f"Error adding to group: {e}")
        
        # Authenticate
        try:
            response = cognito_client.admin_initiate_auth(
                UserPoolId='us-east-1_WCJMgcwll',
                ClientId='308apko2vm7tphi0c74ec209cc',
                AuthFlow='USER_PASSWORD_AUTH',
                AuthParameters={
                    'USERNAME': username,
                    'PASSWORD': password
                }
            )
            
            access_token = response['AuthenticationResult']['AccessToken']
            print(f"Successfully authenticated admin user")
            return access_token, username
            
        except Exception as e:
            print(f"Authentication error: {e}")
            return None, None
            
    except Exception as e:
        print(f"Error in admin auth: {e}")
        return None, None

def search_grady_booch_quotes(access_token):
    """Search for existing Grady Booch quotes"""
    headers = {
        'Authorization': f'Bearer {access_token}',
        'x-api-key': 'iJF7oVCPHLaeWfYPhkuy71izWFoXrr8qawS4drL1',
        'Content-Type': 'application/json'
    }
    
    # Search for quotes by Grady Booch
    try:
        response = requests.get(
            'https://dcc.anystupididea.com/admin/quotes',
            headers=headers,
            params={'limit': 1000}  # Get all quotes to search
        )
        
        if response.status_code == 200:
            data = response.json()
            quotes = data.get('quotes', [])
            
            # Filter for Grady Booch quotes
            grady_quotes = [q for q in quotes if 'grady booch' in q.get('author', '').lower()]
            
            print(f"Found {len(grady_quotes)} quotes by Grady Booch:")
            for i, quote in enumerate(grady_quotes, 1):
                print(f"{i}. '{quote['quote'][:60]}...' by {quote['author']}")
                print(f"   ID: {quote['id']}")
                print()
            
            return grady_quotes
            
        else:
            print(f"Error searching quotes: {response.status_code} - {response.text}")
            return []
            
    except Exception as e:
        print(f"Error in search: {e}")
        return []

def test_duplicate_detection(access_token):
    """Test duplicate detection with a sample Grady Booch quote"""
    headers = {
        'Authorization': f'Bearer {access_token}',
        'x-api-key': 'iJF7oVCPHLaeWfYPhkuy71izWFoXrr8qawS4drL1',
        'Content-Type': 'application/json'
    }
    
    test_quote = {
        "quote": "Software is a reflection of the human condition.",
        "author": "Grady Booch"
    }
    
    try:
        response = requests.post(
            'https://dcc.anystupididea.com/admin/check-duplicate',
            headers=headers,
            json=test_quote
        )
        
        if response.status_code == 200:
            result = response.json()
            print(f"Duplicate check result for '{test_quote['quote']}':")
            print(f"Is duplicate: {result.get('is_duplicate')}")
            print(f"Duplicate count: {result.get('duplicate_count')}")
            print(f"Message: {result.get('message')}")
            
            if result.get('duplicates'):
                print("Potential duplicates found:")
                for dup in result['duplicates']:
                    print(f"  - '{dup['quote'][:50]}...' by {dup['author']} (Reason: {dup['match_reason']})")
            
        else:
            print(f"Error in duplicate check: {response.status_code} - {response.text}")
            
    except Exception as e:
        print(f"Error testing duplicate detection: {e}")

def cleanup_user(username):
    """Clean up temporary test user"""
    if not username:
        return
        
    cognito_client = boto3.client('cognito-idp', region_name='us-east-1')
    try:
        cognito_client.admin_delete_user(
            UserPoolId='us-east-1_WCJMgcwll',
            Username=username
        )
        print(f"Cleaned up temp user: {username}")
    except Exception as e:
        print(f"Error cleaning up user {username}: {e}")

if __name__ == "__main__":
    print("=== Testing Grady Booch Quote Search ===\n")
    
    access_token, username = authenticate_admin()
    
    if access_token:
        try:
            # Search for existing Grady Booch quotes
            existing_quotes = search_grady_booch_quotes(access_token)
            
            print(f"\n=== Testing Duplicate Detection ===\n")
            # Test duplicate detection
            test_duplicate_detection(access_token)
            
        finally:
            # Always cleanup
            cleanup_user(username)
    else:
        print("Failed to authenticate admin user")