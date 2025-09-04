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
    
    http_method = event.get('httpMethod')
    
    if http_method == 'GET':
        return get_users_list()
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