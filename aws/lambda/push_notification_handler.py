"""
Lambda function for sending push notifications via Firebase Cloud Messaging.
Handles both individual and batch notifications for Daily Nuggets.
"""

import json
import os
import boto3
import logging
from typing import Dict, List, Optional
import requests
from datetime import datetime, timedelta
from decimal import Decimal
import jwt
import time

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Environment variables
FCM_SERVICE_ACCOUNT_JSON = os.environ.get('FCM_SERVICE_ACCOUNT_JSON')
FCM_API_URL = 'https://fcm.googleapis.com/v1/projects/{project_id}/messages:send'
FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging'
QUOTES_TABLE = os.environ.get('QUOTES_TABLE_NAME')
USER_PROFILES_TABLE = os.environ.get('USER_PROFILES_TABLE_NAME')
ANALYTICS_TABLE = os.environ.get('ANALYTICS_TABLE_NAME', 'dcc-notification-analytics')

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')

class DecimalEncoder(json.JSONEncoder):
    """Helper class to convert DynamoDB Decimal types to JSON."""
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super(DecimalEncoder, self).default(obj)

def get_access_token():
    """Get OAuth2 access token for FCM v1 API using service account."""
    
    if not FCM_SERVICE_ACCOUNT_JSON:
        raise ValueError("FCM_SERVICE_ACCOUNT_JSON not configured")
    
    try:
        # Parse service account JSON
        service_account = json.loads(FCM_SERVICE_ACCOUNT_JSON)
        
        # Create JWT
        now = int(time.time())
        payload = {
            'iss': service_account['client_email'],
            'scope': FCM_SCOPE,
            'aud': 'https://oauth2.googleapis.com/token',
            'iat': now,
            'exp': now + 3600  # 1 hour expiry
        }
        
        # Sign JWT with private key
        token = jwt.encode(payload, service_account['private_key'], algorithm='RS256')
        
        # Exchange JWT for access token
        response = requests.post(
            'https://oauth2.googleapis.com/token',
            data={
                'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                'assertion': token
            },
            headers={'Content-Type': 'application/x-www-form-urlencoded'}
        )
        
        if response.status_code != 200:
            raise Exception(f"Failed to get access token: {response.text}")
        
        access_token = response.json()['access_token']
        logger.info("Successfully obtained FCM access token")
        return access_token
        
    except Exception as e:
        logger.error(f"Failed to get FCM access token: {str(e)}")
        raise

def lambda_handler(event, context):
    """
    Main handler for push notification requests.
    
    Event structure:
    {
        "action": "send_individual" | "send_batch",
        "userId": "user-id" (for individual),
        "userIds": ["user-id-1", "user-id-2"] (for batch),
        "quoteId": "quote-id" (optional, will select random if not provided),
        "testMode": true/false (optional, for testing)
    }
    """
    
    if not FCM_SERVER_KEY:
        logger.error("FCM_SERVER_KEY not configured")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Push notifications not configured'})
        }
    
    action = event.get('action', 'send_individual')
    
    try:
        if action == 'send_individual':
            result = send_individual_notification(event)
        elif action == 'send_batch':
            result = send_batch_notifications(event)
        else:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': f'Unknown action: {action}'})
            }
        
        return {
            'statusCode': 200,
            'body': json.dumps(result, cls=DecimalEncoder)
        }
        
    except Exception as e:
        logger.error(f"Error in push notification handler: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def send_individual_notification(event: Dict) -> Dict:
    """Send a push notification to a single user."""
    
    user_id = event.get('userId')
    if not user_id:
        raise ValueError("userId is required for individual notification")
    
    # Get user profile
    user_table = dynamodb.Table(USER_PROFILES_TABLE)
    user_response = user_table.get_item(Key={'userId': user_id})
    
    if 'Item' not in user_response:
        raise ValueError(f"User {user_id} not found")
    
    user = user_response['Item']
    
    # Check if push notifications are enabled
    prefs = user.get('notificationPreferences', {})
    if not prefs.get('enablePush', False):
        logger.info(f"Push notifications disabled for user {user_id}")
        return {'message': 'Push notifications disabled for user', 'sent': False}
    
    # Get FCM tokens
    fcm_tokens = user.get('fcmTokens', {})
    active_tokens = [
        token for token in [
            fcm_tokens.get('ios'),
            fcm_tokens.get('android'),
            fcm_tokens.get('web')
        ] if token
    ]
    
    if not active_tokens:
        logger.info(f"No FCM tokens found for user {user_id}")
        return {'message': 'No FCM tokens found', 'sent': False}
    
    # Get quote
    quote = get_quote_for_notification(event.get('quoteId'))
    
    # Send notification to all user's devices
    results = []
    for token in active_tokens:
        result = send_fcm_notification(token, quote, user_id)
        results.append(result)
    
    # Track analytics
    track_notification_event(user_id, quote['id'], 'push_sent', {
        'devices': len(active_tokens),
        'test_mode': event.get('testMode', False)
    })
    
    # Update user stats
    update_user_notification_stats(user_id, 'push')
    
    return {
        'message': 'Notification sent',
        'sent': True,
        'devices': len(active_tokens),
        'quote': quote,
        'results': results
    }

def send_batch_notifications(event: Dict) -> Dict:
    """Send push notifications to multiple users."""
    
    user_ids = event.get('userIds', [])
    if not user_ids:
        raise ValueError("userIds array is required for batch notification")
    
    # Get quote for this batch
    quote = get_quote_for_notification(event.get('quoteId'))
    
    success_count = 0
    failure_count = 0
    results = []
    
    for user_id in user_ids:
        try:
            result = send_individual_notification({
                'userId': user_id,
                'quoteId': quote['id'],
                'testMode': event.get('testMode', False)
            })
            
            if result.get('sent'):
                success_count += 1
            else:
                failure_count += 1
            
            results.append({
                'userId': user_id,
                'success': result.get('sent', False),
                'message': result.get('message')
            })
            
        except Exception as e:
            logger.error(f"Failed to send to user {user_id}: {str(e)}")
            failure_count += 1
            results.append({
                'userId': user_id,
                'success': False,
                'error': str(e)
            })
    
    return {
        'message': f'Batch complete: {success_count} sent, {failure_count} failed',
        'success_count': success_count,
        'failure_count': failure_count,
        'quote': quote,
        'results': results
    }

def send_fcm_notification(token: str, quote: Dict, user_id: str) -> Dict:
    """Send notification via FCM v1 API."""
    
    try:
        # Get service account details for project ID
        service_account = json.loads(FCM_SERVICE_ACCOUNT_JSON)
        project_id = service_account['project_id']
        
        # Get access token
        access_token = get_access_token()
        
        # Truncate quote text for notification body (keeping full text in data)
        body_text = quote['text']
        if len(body_text) > 100:
            body_text = body_text[:97] + '...'
        
        # FCM v1 API payload structure
        payload = {
            'message': {
                'token': token,
                'notification': {
                    'title': 'Daily Nugget',
                    'body': f'"{body_text}" - {quote["author"]}'
                },
                'data': {
                    'quoteId': str(quote['id']),
                    'fullQuote': quote['text'],
                    'author': quote['author'],
                    'tags': json.dumps(quote.get('tags', [])),
                    'clickAction': 'FLUTTER_NOTIFICATION_CLICK',
                    'deepLink': f'/quote/{quote["id"]}',
                    'userId': user_id,
                    'notificationType': 'daily_nugget'
                },
                'android': {
                    'priority': 'high',
                    'notification': {
                        'channel_id': 'daily_nuggets',
                        'color': '#1A237E',  # Indigo theme color
                        'icon': 'ic_notification',
                        'sound': 'default'
                    }
                },
                'apns': {
                    'payload': {
                        'aps': {
                            'category': 'DAILY_NUGGET',
                            'mutable-content': 1,
                            'content-available': 1,
                            'badge': 1,
                            'sound': 'default'
                        }
                    }
                },
                'webpush': {
                    'headers': {
                        'TTL': '86400'  # 24 hours
                    },
                    'notification': {
                        'icon': '/icons/icon-192x192.png',
                        'badge': '/icons/badge-72x72.png',
                        'actions': [
                            {
                                'action': 'favorite',
                                'title': 'Favorite',
                                'icon': '/icons/heart.png'
                            },
                            {
                                'action': 'share', 
                                'title': 'Share',
                                'icon': '/icons/share.png'
                            }
                        ]
                    }
                }
            }
        }
        
        headers = {
            'Authorization': f'Bearer {access_token}',
            'Content-Type': 'application/json'
        }
        
        api_url = FCM_API_URL.format(project_id=project_id)
        response = requests.post(api_url, json=payload, headers=headers)
        
        if response.status_code == 200:
            response_data = response.json()
            logger.info(f"Successfully sent notification to token ending in ...{token[-6:]}")
            return {'success': True, 'messageId': response_data.get('name', 'unknown')}
        else:
            response_data = response.json() if response.content else {}
            logger.error(f"FCM v1 API error: {response.status_code} - {response_data}")
            
            # Handle invalid token errors
            if response.status_code == 404 or 'not-found' in response_data.get('error', {}).get('status', ''):
                remove_invalid_token(user_id, token)
            
            return {'success': False, 'error': response_data}
            
    except Exception as e:
        logger.error(f"Failed to send FCM notification: {str(e)}")
        return {'success': False, 'error': str(e)}

def get_quote_for_notification(quote_id: Optional[str] = None) -> Dict:
    """Get a quote for the notification, either specified or random."""
    
    quotes_table = dynamodb.Table(QUOTES_TABLE)
    
    if quote_id:
        # Get specific quote
        response = quotes_table.get_item(Key={'id': quote_id})
        if 'Item' not in response:
            raise ValueError(f"Quote {quote_id} not found")
        return response['Item']
    else:
        # Get random quote (similar to existing daily nuggets logic)
        response = quotes_table.scan(
            Limit=1,
            Select='ALL_ATTRIBUTES'
        )
        
        if response['Items']:
            return response['Items'][0]
        else:
            raise ValueError("No quotes available")

def track_notification_event(user_id: str, quote_id: str, event_type: str, metadata: Dict = None):
    """Track notification analytics."""
    
    try:
        analytics_table = dynamodb.Table(ANALYTICS_TABLE)
        
        event_id = f"{user_id}#{datetime.utcnow().isoformat()}#{event_type}"
        
        item = {
            'eventId': event_id,
            'userId': user_id,
            'quoteId': quote_id,
            'eventType': event_type,
            'timestamp': datetime.utcnow().isoformat(),
            'metadata': metadata or {}
        }
        
        analytics_table.put_item(Item=item)
        
    except Exception as e:
        logger.error(f"Failed to track analytics: {str(e)}")

def update_user_notification_stats(user_id: str, notification_type: str):
    """Update user's notification statistics."""
    
    try:
        user_table = dynamodb.Table(USER_PROFILES_TABLE)
        
        user_table.update_item(
            Key={'userId': user_id},
            UpdateExpression="SET notificationStats.lastPushSent = :now",
            ExpressionAttributeValues={
                ':now': datetime.utcnow().isoformat()
            }
        )
        
    except Exception as e:
        logger.error(f"Failed to update user stats: {str(e)}")

def remove_invalid_token(user_id: str, token: str):
    """Remove an invalid FCM token from user profile."""
    
    try:
        user_table = dynamodb.Table(USER_PROFILES_TABLE)
        
        # Determine which platform the token belongs to
        user_response = user_table.get_item(Key={'userId': user_id})
        if 'Item' not in user_response:
            return
        
        fcm_tokens = user_response['Item'].get('fcmTokens', {})
        
        # Find and remove the invalid token
        for platform in ['ios', 'android', 'web']:
            if fcm_tokens.get(platform) == token:
                user_table.update_item(
                    Key={'userId': user_id},
                    UpdateExpression=f"REMOVE fcmTokens.{platform}"
                )
                logger.info(f"Removed invalid {platform} token for user {user_id}")
                break
                
    except Exception as e:
        logger.error(f"Failed to remove invalid token: {str(e)}")