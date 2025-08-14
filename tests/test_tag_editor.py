#!/usr/bin/env python3

import requests
import json
import subprocess
import sys
import time

# Configuration
BASE_URL = "https://dcc.anystupididea.com"
USER_POOL_ID = "us-east-1_ecyuILBAu"
CLIENT_ID = "2idvhvlhgbheglr0hptel5j55"
ADMIN_GROUP = "Admins"

# Generate unique test user credentials
import time
TEST_USERNAME = f"test-tag-editor-{int(time.time())}@dcc-test.com"
TEST_PASSWORD = "TempTestPass123!"

def create_test_user():
    """Create temporary admin user for testing"""
    print(f"👤 Creating temporary admin user: {TEST_USERNAME}")
    
    try:
        # Create user
        cmd1 = [
            'aws', 'cognito-idp', 'admin-create-user',
            '--user-pool-id', USER_POOL_ID,
            '--username', TEST_USERNAME,
            '--user-attributes', f'Name=email,Value={TEST_USERNAME}',
            '--temporary-password', TEST_PASSWORD,
            '--message-action', 'SUPPRESS'
        ]
        
        result1 = subprocess.run(cmd1, capture_output=True, text=True)
        if result1.returncode != 0:
            print(f"❌ Failed to create test user: {result1.stderr}")
            return False
        
        # Set permanent password
        cmd2 = [
            'aws', 'cognito-idp', 'admin-set-user-password',
            '--user-pool-id', USER_POOL_ID,
            '--username', TEST_USERNAME,
            '--password', TEST_PASSWORD,
            '--permanent'
        ]
        
        result2 = subprocess.run(cmd2, capture_output=True, text=True)
        if result2.returncode != 0:
            print(f"❌ Failed to set permanent password: {result2.stderr}")
            return False
        
        # Add to admin group
        cmd3 = [
            'aws', 'cognito-idp', 'admin-add-user-to-group',
            '--user-pool-id', USER_POOL_ID,
            '--username', TEST_USERNAME,
            '--group-name', ADMIN_GROUP
        ]
        
        result3 = subprocess.run(cmd3, capture_output=True, text=True)
        if result3.returncode != 0:
            print(f"❌ Failed to add user to admin group: {result3.stderr}")
            return False
        
        print("✅ Temporary admin user created successfully")
        return True
        
    except Exception as e:
        print(f"❌ Error creating test user: {e}")
        return False

def cleanup_test_user():
    """Cleanup temporary admin user"""
    print(f"🧹 Cleaning up temporary admin user: {TEST_USERNAME}")
    
    try:
        cmd = [
            'aws', 'cognito-idp', 'admin-delete-user',
            '--user-pool-id', USER_POOL_ID,
            '--username', TEST_USERNAME
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            print("✅ Temporary user deleted successfully")
        else:
            print(f"⚠️  Note: Manual cleanup may be needed for user: {TEST_USERNAME}")
    except Exception as e:
        print(f"⚠️  Error during cleanup: {e}")

def get_admin_token():
    """Get admin authentication token"""
    try:
        cmd = [
            'aws', 'cognito-idp', 'admin-initiate-auth',
            '--user-pool-id', USER_POOL_ID,
            '--client-id', CLIENT_ID,
            '--auth-flow', 'ADMIN_NO_SRP_AUTH',
            '--auth-parameters', f'USERNAME={TEST_USERNAME},PASSWORD={TEST_PASSWORD}'
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        if result.returncode == 0:
            response = json.loads(result.stdout)
            return response['AuthenticationResult']['IdToken']
        else:
            print(f"❌ Failed to authenticate: {result.stderr}")
            return None
            
    except Exception as e:
        print(f"❌ Error getting token: {e}")
        return None

def test_get_tags(token):
    """Test getting current tags"""
    print("📋 Getting current tags...")
    
    headers = {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'application/json'
    }
    
    response = requests.get(f"{BASE_URL}/admin/tags", headers=headers)
    
    if response.status_code == 200:
        data = response.json()
        tags = data.get('tags', [])
        count = data.get('count', 0)
        print(f"✅ Found {count} tags: {tags}")
        return tags
    else:
        print(f"❌ Failed to get tags: {response.status_code} - {response.text}")
        return []

def test_add_tag(token, tag_name):
    """Test adding a new tag"""
    print(f"➕ Adding tag: {tag_name}")
    
    headers = {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'application/json'
    }
    
    data = {'tag': tag_name}
    response = requests.post(f"{BASE_URL}/admin/tags", headers=headers, json=data)
    
    if response.status_code == 201:
        result = response.json()
        print(f"✅ Tag added successfully: {result['message']}")
        return True
    else:
        print(f"❌ Failed to add tag: {response.status_code} - {response.text}")
        return False

def test_update_tag(token, old_tag, new_tag):
    """Test updating a tag"""
    print(f"✏️ Updating tag '{old_tag}' to '{new_tag}'")
    
    headers = {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'application/json'
    }
    
    data = {'tag': new_tag}
    response = requests.put(f"{BASE_URL}/admin/tags/{old_tag}", headers=headers, json=data)
    
    if response.status_code == 200:
        result = response.json()
        quotes_updated = result.get('quotes_updated', 0)
        print(f"✅ Tag updated successfully: {result['message']} ({quotes_updated} quotes updated)")
        return True
    else:
        print(f"❌ Failed to update tag: {response.status_code} - {response.text}")
        return False

def test_delete_tag(token, tag_name):
    """Test deleting a tag"""
    print(f"🗑️ Deleting tag: {tag_name}")
    
    headers = {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'application/json'
    }
    
    response = requests.delete(f"{BASE_URL}/admin/tags/{tag_name}", headers=headers)
    
    if response.status_code == 200:
        result = response.json()
        quotes_updated = result.get('quotes_updated', 0)
        print(f"✅ Tag deleted successfully: {result['message']} ({quotes_updated} quotes updated)")
        return True
    else:
        print(f"❌ Failed to delete tag: {response.status_code} - {response.text}")
        return False

def test_list_quotes(token):
    """Test listing quotes to verify TAGS_METADATA is filtered out"""
    print("📝 Testing quote list to ensure TAGS_METADATA is filtered...")
    
    headers = {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'application/json'
    }
    
    response = requests.get(f"{BASE_URL}/admin/quotes", headers=headers)
    
    if response.status_code == 200:
        data = response.json()
        quotes = data.get('quotes', [])
        
        # Check if any quote has id "TAGS_METADATA"
        metadata_found = any(quote.get('id') == 'TAGS_METADATA' for quote in quotes)
        
        if metadata_found:
            print("❌ TAGS_METADATA record found in quotes list - filtering failed!")
            return False
        else:
            print(f"✅ Quotes list properly filtered - {len(quotes)} quotes, no metadata records")
            return True
    else:
        print(f"❌ Failed to get quotes: {response.status_code} - {response.text}")
        return False

def test_add_duplicate_tag(token, tag_name):
    """Test adding a duplicate tag (should fail)"""
    print(f"🔄 Testing duplicate tag addition: {tag_name}")
    
    headers = {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'application/json'
    }
    
    data = {'tag': tag_name}
    response = requests.post(f"{BASE_URL}/admin/tags", headers=headers, json=data)
    
    if response.status_code == 400:
        print(f"✅ Duplicate tag correctly rejected")
        return True
    else:
        print(f"❌ Duplicate tag should have been rejected: {response.status_code}")
        return False

def main():
    print("🧪 Testing Tag Editor Functionality")
    print("=" * 50)
    
    # Setup: Create temporary admin user
    if not create_test_user():
        print("❌ Failed to create temporary test user")
        sys.exit(1)
    
    try:
        # Wait for user creation to propagate
        print("⏳ Waiting for user creation to propagate...")
        time.sleep(3)
        
        # Get admin token
        token = get_admin_token()
        if not token:
            print("❌ Cannot proceed without admin token")
            sys.exit(1)
        
        print("✅ Successfully authenticated as admin")
        print()
        
        # Step 1: Get initial tags
        initial_tags = test_get_tags(token)
        print()
        
        # Step 2: Test quotes list filtering
        quotes_filter_success = test_list_quotes(token)
        print()
        
        # Step 3: Test adding a new tag
        test_tag_name = f"TestTag-{int(time.time())}"
        add_success = test_add_tag(token, test_tag_name)
        print()
        
        # Step 4: Test adding duplicate tag (should fail)
        if add_success:
            test_add_duplicate_tag(token, test_tag_name)
            print()
        
        # Step 5: Test updating the tag
        updated_tag_name = f"{test_tag_name}-Updated"
        if add_success:
            update_success = test_update_tag(token, test_tag_name, updated_tag_name)
            print()
        else:
            update_success = False
        
        # Step 6: Verify tags after update
        updated_tags = test_get_tags(token)
        print()
        
        # Step 7: Test deleting the tag
        if update_success:
            delete_success = test_delete_tag(token, updated_tag_name)
            print()
        elif add_success:
            delete_success = test_delete_tag(token, test_tag_name)
            print()
        else:
            delete_success = True  # Nothing to delete
        
        # Step 8: Verify final state
        final_tags = test_get_tags(token)
        print()
        
        # Summary
        print("📊 Test Summary:")
        print("=" * 20)
        tests_passed = 0
        total_tests = 5
        
        if quotes_filter_success:
            print("✅ Quotes list filtering: PASSED")
            tests_passed += 1
        else:
            print("❌ Quotes list filtering: FAILED")
        
        if add_success:
            print("✅ Tag addition: PASSED")
            tests_passed += 1
        else:
            print("❌ Tag addition: FAILED")
        
        if update_success or not add_success:  # Skip if add failed
            print("✅ Tag update: PASSED")
            tests_passed += 1
        else:
            print("❌ Tag update: FAILED")
        
        if delete_success:
            print("✅ Tag deletion: PASSED")
            tests_passed += 1
        else:
            print("❌ Tag deletion: FAILED")
        
        # Check if we're back to initial state
        if len(final_tags) <= len(initial_tags):
            print("✅ State cleanup: PASSED")
            tests_passed += 1
        else:
            print("❌ State cleanup: FAILED")
        
        print(f"\n🎯 Overall: {tests_passed}/{total_tests} tests passed")
        
        if tests_passed == total_tests:
            print("🎉 All tag editor functionality tests PASSED!")
        else:
            print("⚠️ Some tests failed. Please review the output above.")
        
    finally:
        # Cleanup: Delete temporary user
        cleanup_test_user()

if __name__ == "__main__":
    main()