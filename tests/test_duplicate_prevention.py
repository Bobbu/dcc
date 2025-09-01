#!/usr/bin/env python3
"""
Test duplicate prevention in quote creation
"""

import json
import subprocess
import sys
import requests

# Configuration
BASE_URL = "https://dcc.anystupididea.com"
USER_POOL_ID = "us-east-1_ecyuILBAu"
CLIENT_ID = "2idvhvlhgbheglr0hptel5j55"

# Admin credentials
ADMIN_USERNAME = "admin@dcc.com"  
ADMIN_PASSWORD = "AdminPass123!"

# Test quote that we know exists in the database
TEST_QUOTE = "Trying to read our DNA is like trying to understand software code - with only 90% of the code riddled with errors. It's very difficult in that case to understand and predict what that software code acing to do."
TEST_AUTHOR = "Elon Musk"

def get_admin_token():
    """Get access token for admin user"""
    try:
        cmd = [
            'aws', 'cognito-idp', 'admin-initiate-auth',
            '--user-pool-id', USER_POOL_ID,
            '--client-id', CLIENT_ID,
            '--auth-flow', 'ADMIN_NO_SRP_AUTH',
            '--auth-parameters', f'USERNAME={ADMIN_USERNAME},PASSWORD={ADMIN_PASSWORD}'
        ]
        result = subprocess.run(cmd, check=True, capture_output=True, text=True)
        auth_data = json.loads(result.stdout)
        return auth_data['AuthenticationResult']['IdToken']
    except Exception as e:
        print(f"❌ Failed to get admin access token: {e}")
        return None

def test_duplicate_prevention(token):
    """Test that creating a duplicate quote is prevented"""
    print(f"🔍 Testing duplicate prevention...")
    print(f"Quote: \"{TEST_QUOTE[:60]}...\"")
    print(f"Author: {TEST_AUTHOR}")
    print()
    
    headers = {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'application/json'
    }
    
    data = {
        "quote": TEST_QUOTE,
        "author": TEST_AUTHOR,
        "tags": ["test-duplicate"]
    }
    
    try:
        response = requests.post(
            f'{BASE_URL}/admin/quotes',
            headers=headers,
            json=data,
            timeout=10
        )
        
        print(f"📊 Response Status: {response.status_code}")
        print(f"📊 Response Body: {response.text}")
        print()
        
        if response.status_code == 409:
            print("✅ SUCCESS! Duplicate detection is working!")
            print("   Quote creation was properly blocked due to duplicate")
            try:
                result = response.json()
                duplicates = result.get('duplicates', [])
                print(f"   Found {len(duplicates)} matching quote(s)")
                return True
            except:
                pass
        elif response.status_code == 201:
            print("❌ FAILURE! Duplicate was allowed through")
            print("   Quote was created despite being a duplicate")
            return False
        elif response.status_code == 401:
            print("❌ UNAUTHORIZED - JWT token is invalid/expired")
            return False
        elif response.status_code == 403:
            print("❌ FORBIDDEN - User is not admin")
            return False
        else:
            print(f"❌ UNEXPECTED STATUS: {response.status_code}")
            return False
            
    except requests.exceptions.RequestException as e:
        print(f"❌ REQUEST ERROR: {e}")
        return False

def main():
    """Main test runner"""
    print("🚀 Testing Duplicate Prevention")
    print("=" * 40)
    
    # Get admin token
    print("🔐 Getting admin authentication token...")
    token = get_admin_token()
    if not token:
        print("❌ Failed to authenticate as admin")
        return 1
    
    print("✅ Admin authentication successful")
    print()
    
    # Test duplicate prevention
    success = test_duplicate_prevention(token)
    
    if success:
        print("\n🎉 Duplicate prevention is working correctly!")
        return 0
    else:
        print("\n💥 Duplicate prevention failed!")
        return 1

if __name__ == "__main__":
    exit(main())
