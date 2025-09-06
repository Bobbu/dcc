import json
import boto3
import os
from datetime import datetime
from typing import Dict, Any, List, Optional
from botocore.exceptions import ClientError

cognito = boto3.client('cognito-idp')
dynamodb = boto3.resource('dynamodb')

USER_POOL_ID = os.environ['USER_POOL_ID']
SUBSCRIPTION_TABLE = os.environ.get('SUBSCRIPTION_TABLE', 'dcc-daily-nuggets-subscriptions')

def handler(event: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handler for user management endpoints.
    """
    print(f"Event: {json.dumps(event)}")
    
    http_method = event.get('httpMethod')
    
    # Handle OPTIONS requests for CORS preflight without authentication
    if http_method == 'OPTIONS':
        return {
            'statusCode': 200,
            'headers': get_cors_headers(),
            'body': json.dumps({'message': 'CORS preflight successful'})
        }
    
    # Get user info from API Gateway Cognito authorizer context
    request_context = event.get('requestContext', {})
    authorizer = request_context.get('authorizer', {})
    claims = authorizer.get('claims', {})
    
    if not claims:
        return {
            'statusCode': 401,
            'headers': get_cors_headers(),
            'body': json.dumps({'error': 'Authorization required'})
        }
    
    # Check if user is admin by looking at groups
    cognito_groups = claims.get('cognito:groups', '')
    groups = cognito_groups.split(',') if cognito_groups else []
    
    if 'Admins' not in groups:
        return {
            'statusCode': 403,
            'headers': get_cors_headers(),
            'body': json.dumps({'error': 'Admin access required'})
        }
    
    # Extract path parameters
    path_params = event.get('pathParameters', {})
    
    if http_method == 'GET':
        return get_users_list()
    elif http_method == 'PUT':
        # Handle admin group assignment/unassignment
        user_id = path_params.get('userId')
        if not user_id:
            return {
                'statusCode': 400,
                'headers': get_cors_headers(),
                'body': json.dumps({'error': 'User ID required'})
            }
        return update_user_admin_status(user_id, event.get('body'), claims)
    elif http_method == 'DELETE':
        # Handle user deletion
        user_id = path_params.get('userId')
        if not user_id:
            return {
                'statusCode': 400,
                'headers': get_cors_headers(),
                'body': json.dumps({'error': 'User ID required'})
            }
        return delete_user(user_id, claims)
    else:
        return {
            'statusCode': 405,
            'headers': get_cors_headers(),
            'body': json.dumps({'error': 'Method not allowed'})
        }

def get_users_list() -> Dict[str, Any]:
    """
    Get list of all users with their attributes.
    """
    try:
        users = []
        pagination_token = None
        
        # Get subscription data from DynamoDB
        subscription_table = dynamodb.Table(SUBSCRIPTION_TABLE)
        subscriptions = {}
        try:
            scan_response = subscription_table.scan()
            for item in scan_response.get('Items', []):
                user_id = item.get('user_id')
                if user_id:
                    subscriptions[user_id] = {
                        'subscribed': item.get('subscribed', False),
                        'timezone': item.get('timezone'),
                        'preferred_time': item.get('preferred_time'),
                        'created_at': item.get('created_at'),
                        'updated_at': item.get('updated_at')
                    }
        except ClientError as e:
            print(f"Error fetching subscriptions: {e}")
        
        # Paginate through all users
        while True:
            if pagination_token:
                response = cognito.list_users(
                    UserPoolId=USER_POOL_ID,
                    PaginationToken=pagination_token,
                    Limit=60
                )
            else:
                response = cognito.list_users(
                    UserPoolId=USER_POOL_ID,
                    Limit=60
                )
            
            for user in response.get('Users', []):
                user_data = parse_user_data(user, subscriptions)
                users.append(user_data)
            
            pagination_token = response.get('PaginationToken')
            if not pagination_token:
                break
        
        # Sort users by creation date (most recent first)
        users.sort(key=lambda x: x.get('created_at', ''), reverse=True)
        
        return {
            'statusCode': 200,
            'headers': get_cors_headers(),
            'body': json.dumps({
                'users': users,
                'total': len(users)
            })
        }
    except ClientError as e:
        print(f"Error listing users: {e}")
        return {
            'statusCode': 500,
            'headers': get_cors_headers(),
            'body': json.dumps({'error': 'Failed to list users'})
        }

def parse_user_data(user: Dict[str, Any], subscriptions: Dict[str, Any]) -> Dict[str, Any]:
    """
    Parse Cognito user data into a clean format.
    """
    attributes = {attr['Name']: attr['Value'] for attr in user.get('Attributes', [])}
    user_id = attributes.get('sub')
    
    # Get subscription data for this user
    subscription_data = subscriptions.get(user_id, {})
    
    # Parse dates
    created_at = user.get('UserCreateDate')
    if created_at:
        created_at = created_at.isoformat()
    
    last_modified = user.get('UserLastModifiedDate')
    if last_modified:
        last_modified = last_modified.isoformat()
    
    # Get user groups
    try:
        groups_response = cognito.admin_list_groups_for_user(
            UserPoolId=USER_POOL_ID,
            Username=user['Username']
        )
        groups = [group['GroupName'] for group in groups_response.get('Groups', [])]
    except ClientError:
        groups = []
    
    return {
        'user_id': user_id,
        'username': user.get('Username'),
        'email': attributes.get('email'),
        'email_verified': attributes.get('email_verified') == 'true',
        'display_name': attributes.get('name') or attributes.get('preferred_username'),
        'status': user.get('UserStatus'),
        'enabled': user.get('Enabled', True),
        'created_at': created_at,
        'last_modified': last_modified,
        'groups': groups,
        'is_admin': 'Admins' in groups,
        'daily_nuggets_subscribed': subscription_data.get('subscribed', False),
        'timezone': subscription_data.get('timezone'),
        'preferred_time': subscription_data.get('preferred_time'),
        'subscription_created_at': subscription_data.get('created_at'),
        'subscription_updated_at': subscription_data.get('updated_at')
    }

def update_user_admin_status(user_id: str, body: str, claims: Dict[str, Any]) -> Dict[str, Any]:
    """
    Add or remove a user from the Admins group.
    """
    try:
        # Parse request body
        if not body:
            return {
                'statusCode': 400,
                'headers': get_cors_headers(),
                'body': json.dumps({'error': 'Request body required'})
            }
        
        request_data = json.loads(body)
        action = request_data.get('action')  # 'add' or 'remove'
        
        if action not in ['add', 'remove']:
            return {
                'statusCode': 400,
                'headers': get_cors_headers(),
                'body': json.dumps({'error': 'Invalid action. Must be "add" or "remove"'})
            }
        
        # Get the current user's ID (the one making the request)
        current_user_id = claims.get('sub')
        
        # Prevent users from removing themselves from admin group
        if action == 'remove' and user_id == current_user_id:
            return {
                'statusCode': 403,
                'headers': get_cors_headers(),
                'body': json.dumps({'error': 'You cannot remove yourself from the Admins group'})
            }
        
        # Find the username for the given user_id
        try:
            # List users and find the one with matching sub
            users_response = cognito.list_users(
                UserPoolId=USER_POOL_ID,
                Filter=f'sub = "{user_id}"',
                Limit=1
            )
            
            if not users_response.get('Users'):
                return {
                    'statusCode': 404,
                    'headers': get_cors_headers(),
                    'body': json.dumps({'error': 'User not found'})
                }
            
            username = users_response['Users'][0]['Username']
            
        except ClientError as e:
            print(f"Error finding user: {e}")
            return {
                'statusCode': 500,
                'headers': get_cors_headers(),
                'body': json.dumps({'error': 'Failed to find user'})
            }
        
        # Perform the action
        try:
            if action == 'add':
                cognito.admin_add_user_to_group(
                    UserPoolId=USER_POOL_ID,
                    Username=username,
                    GroupName='Admins'
                )
                message = f'User {username} added to Admins group'
            else:  # action == 'remove'
                cognito.admin_remove_user_from_group(
                    UserPoolId=USER_POOL_ID,
                    Username=username,
                    GroupName='Admins'
                )
                message = f'User {username} removed from Admins group'
            
            return {
                'statusCode': 200,
                'headers': get_cors_headers(),
                'body': json.dumps({
                    'success': True,
                    'message': message,
                    'user_id': user_id,
                    'action': action
                })
            }
            
        except ClientError as e:
            print(f"Error updating user group: {e}")
            error_message = str(e)
            if 'UserNotFoundException' in error_message:
                return {
                    'statusCode': 404,
                    'headers': get_cors_headers(),
                    'body': json.dumps({'error': 'User not found'})
                }
            return {
                'statusCode': 500,
                'headers': get_cors_headers(),
                'body': json.dumps({'error': f'Failed to update user group: {error_message}'})
            }
            
    except json.JSONDecodeError:
        return {
            'statusCode': 400,
            'headers': get_cors_headers(),
            'body': json.dumps({'error': 'Invalid JSON in request body'})
        }
    except Exception as e:
        print(f"Unexpected error: {e}")
        return {
            'statusCode': 500,
            'headers': get_cors_headers(),
            'body': json.dumps({'error': 'Internal server error'})
        }

def delete_user(user_id: str, claims: Dict[str, Any]) -> Dict[str, Any]:
    """
    Delete a user from Cognito and clean up related data.
    """
    try:
        # Get the current user's ID (the one making the request)
        current_user_id = claims.get('sub')
        
        # Prevent users from deleting themselves
        if user_id == current_user_id:
            return {
                'statusCode': 403,
                'headers': get_cors_headers(),
                'body': json.dumps({'error': 'You cannot delete yourself'})
            }
        
        # Find the username for the given user_id
        try:
            # List users and find the one with matching sub
            users_response = cognito.list_users(
                UserPoolId=USER_POOL_ID,
                Filter=f'sub = "{user_id}"',
                Limit=1
            )
            
            if not users_response.get('Users'):
                return {
                    'statusCode': 404,
                    'headers': get_cors_headers(),
                    'body': json.dumps({'error': 'User not found'})
                }
            
            username = users_response['Users'][0]['Username']
            user_email = None
            
            # Get email from user attributes
            for attr in users_response['Users'][0].get('Attributes', []):
                if attr['Name'] == 'email':
                    user_email = attr['Value']
                    break
            
        except ClientError as e:
            print(f"Error finding user: {e}")
            return {
                'statusCode': 500,
                'headers': get_cors_headers(),
                'body': json.dumps({'error': 'Failed to find user'})
            }
        
        # Delete the user from Cognito
        try:
            cognito.admin_delete_user(
                UserPoolId=USER_POOL_ID,
                Username=username
            )
            
            # Clean up user data from DynamoDB (subscription data)
            subscription_table = dynamodb.Table(SUBSCRIPTION_TABLE)
            try:
                subscription_table.delete_item(
                    Key={'user_id': user_id},
                    ConditionExpression='attribute_exists(user_id)'
                )
                print(f"Deleted subscription data for user {user_id}")
            except ClientError as e:
                # It's okay if subscription data doesn't exist
                if e.response['Error']['Code'] != 'ConditionalCheckFailedException':
                    print(f"Warning: Could not delete subscription data for user {user_id}: {e}")
            
            return {
                'statusCode': 200,
                'headers': get_cors_headers(),
                'body': json.dumps({
                    'success': True,
                    'message': f'User {user_email or username} has been deleted',
                    'user_id': user_id
                })
            }
            
        except ClientError as e:
            print(f"Error deleting user: {e}")
            error_message = str(e)
            if 'UserNotFoundException' in error_message:
                return {
                    'statusCode': 404,
                    'headers': get_cors_headers(),
                    'body': json.dumps({'error': 'User not found'})
                }
            return {
                'statusCode': 500,
                'headers': get_cors_headers(),
                'body': json.dumps({'error': f'Failed to delete user: {error_message}'})
            }
            
    except Exception as e:
        print(f"Unexpected error: {e}")
        return {
            'statusCode': 500,
            'headers': get_cors_headers(),
            'body': json.dumps({'error': 'Internal server error'})
        }

def get_cors_headers() -> Dict[str, str]:
    """
    Get CORS headers for API responses.
    """
    return {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Api-Key,Authorization',
        'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
    }