import json
import boto3
import os
import logging
from datetime import datetime, timezone
from botocore.exceptions import ClientError
import random
from decimal import Decimal
from boto3.dynamodb.conditions import Key, Attr
import requests
import jwt
import time

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS services
dynamodb = boto3.resource('dynamodb')
ses = boto3.client('ses', region_name='us-east-1')
cognito = boto3.client('cognito-idp')

# Get environment variables
QUOTES_TABLE_NAME = os.environ.get('QUOTES_TABLE_NAME', 'dcc-quotes-optimized')
SUBSCRIPTIONS_TABLE_NAME = os.environ.get('SUBSCRIPTIONS_TABLE_NAME', 'dcc-subscriptions')
USER_POOL_ID = os.environ.get('USER_POOL_ID')
SENDER_EMAIL = os.environ.get('SENDER_EMAIL', 'noreply@anystupididea.com')
CORS_ORIGIN = os.environ.get('CORS_ORIGIN', '*')
FCM_SERVICE_ACCOUNT_JSON = os.environ.get('FCM_SERVICE_ACCOUNT_JSON')
FCM_API_URL = 'https://fcm.googleapis.com/v1/projects/{project_id}/messages:send'

# Initialize tables
quotes_table = dynamodb.Table(QUOTES_TABLE_NAME)
subscriptions_table = dynamodb.Table(SUBSCRIPTIONS_TABLE_NAME)

# CORS headers for API responses
CORS_HEADERS = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': CORS_ORIGIN,
    'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
    'Access-Control-Allow-Methods': 'OPTIONS,POST,GET,PUT,DELETE'
}

class DecimalEncoder(json.JSONEncoder):
    """Helper class to convert DynamoDB Decimal types to JSON"""
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super(DecimalEncoder, self).default(obj)

def handler(event, context):
    """Main Lambda handler for Daily Nuggets functionality"""
    logger.info(f"Event: {json.dumps(event)}")
    
    # Check if this is triggered by EventBridge (scheduled event)
    if 'source' in event and event['source'] == 'aws.scheduler':
        return handle_scheduled_delivery(event)
    
    # Otherwise, it's an API Gateway request
    http_method = event.get('httpMethod', '')
    path = event.get('path', '')
    
    try:
        # Admin endpoints - check for admin group
        if path == '/admin/subscriptions' and http_method == 'GET':
            # Check if user is admin
            claims = event.get('requestContext', {}).get('authorizer', {}).get('claims', {})
            groups = claims.get('cognito:groups', '').split(',')
            if 'Admins' not in groups:
                return {
                    'statusCode': 403,
                    'headers': CORS_HEADERS,
                    'body': json.dumps({'error': 'Admin access required'})
                }
            return get_all_subscriptions()
        
        # Handle OPTIONS requests (CORS preflight)
        if http_method == 'OPTIONS':
            return {
                'statusCode': 200,
                'headers': CORS_HEADERS,
                'body': ''
            }
        
        # User endpoints - extract user email from JWT token
        user_email = get_user_email_from_token(event)
        
        if path == '/subscriptions' and http_method == 'GET':
            return get_subscription(user_email)
        elif path == '/subscriptions' and http_method == 'PUT':
            body = json.loads(event.get('body', '{}'))
            return update_subscription(user_email, body)
        elif path == '/subscriptions' and http_method == 'DELETE':
            return delete_subscription(user_email)
        elif path == '/subscriptions/test' and http_method == 'POST':
            # Test endpoint to send a sample email immediately
            return send_test_email(user_email)
        elif path == '/notifications/test' and http_method == 'POST':
            # Test endpoint to send a sample push notification immediately
            return send_test_notification(user_email)
        else:
            return {
                'statusCode': 404,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'Not found'})
            }
            
    except Exception as e:
        logger.error(f"Error handling request: {str(e)}")
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': str(e)})
        }

def get_user_email_from_token(event):
    """Extract user email from JWT token in Authorization header"""
    try:
        # The API Gateway authorizer adds the claims to the request context
        claims = event.get('requestContext', {}).get('authorizer', {}).get('claims', {})
        email = claims.get('email')
        if not email:
            raise ValueError('Email not found in token claims')
        return email
    except Exception as e:
        logger.error(f"Error extracting email from token: {e}")
        raise ValueError('Invalid or expired token')

def get_all_subscriptions():
    """Get all subscriptions for admin view"""
    try:
        response = subscriptions_table.scan()
        subscribers = response.get('Items', [])
        
        # Handle pagination if needed
        while 'LastEvaluatedKey' in response:
            response = subscriptions_table.scan(
                ExclusiveStartKey=response['LastEvaluatedKey']
            )
            subscribers.extend(response.get('Items', []))
        
        # Sort by created_at descending (newest first)
        subscribers.sort(key=lambda x: x.get('created_at', ''), reverse=True)
        
        logger.info(f"Retrieved {len(subscribers)} total subscribers")
        
        return {
            'statusCode': 200,
            'headers': CORS_HEADERS,
            'body': json.dumps({
                'subscribers': subscribers,
                'total': len(subscribers),
                'active': len([s for s in subscribers if s.get('is_subscribed', False)])
            }, cls=DecimalEncoder)
        }
        
    except Exception as e:
        logger.error(f"Error getting all subscriptions: {str(e)}")
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': 'Failed to get subscriptions'})
        }

def get_subscription(email):
    """Get user's subscription preferences"""
    try:
        response = subscriptions_table.get_item(
            Key={'email': email}
        )
        
        if 'Item' in response:
            return {
                'statusCode': 200,
                'headers': CORS_HEADERS,
                'body': json.dumps(response['Item'], cls=DecimalEncoder)
            }
        else:
            return {
                'statusCode': 404,
                'headers': CORS_HEADERS,
                'body': json.dumps({'message': 'No subscription found'})
            }
            
    except Exception as e:
        logger.error(f"Error getting subscription: {str(e)}")
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': 'Failed to get subscription'})
        }

def update_subscription(email, body):
    """Create or update user's subscription preferences"""
    try:
        # Validate input
        is_subscribed = body.get('is_subscribed', False)
        delivery_method = body.get('delivery_method', 'email')
        timezone_str = body.get('timezone', 'America/New_York')
        notification_preferences = body.get('notification_preferences', {})
        
        # Prepare item for DynamoDB
        item = {
            'email': email,
            'is_subscribed': is_subscribed,
            'delivery_method': delivery_method,
            'timezone': timezone_str,
            'created_at': datetime.now(timezone.utc).isoformat(),
            'updated_at': datetime.now(timezone.utc).isoformat()
        }
        
        # Add notification preferences if provided
        if notification_preferences:
            item['notificationPreferences'] = notification_preferences
            logger.info(f"📱 Storing notification preferences: {json.dumps(notification_preferences, cls=DecimalEncoder)}")
        else:
            logger.info("📱 No notification preferences provided - FCM token will not be stored")
        
        # Check if subscription exists to preserve created_at
        existing = subscriptions_table.get_item(Key={'email': email})
        if 'Item' in existing:
            item['created_at'] = existing['Item'].get('created_at', item['created_at'])
        
        # Save to DynamoDB
        subscriptions_table.put_item(Item=item)
        
        logger.info(f"Subscription updated for {email}: subscribed={is_subscribed}, timezone={timezone_str}")
        
        return {
            'statusCode': 200,
            'headers': CORS_HEADERS,
            'body': json.dumps({
                'message': 'Subscription updated successfully',
                'subscription': item
            }, cls=DecimalEncoder)
        }
        
    except Exception as e:
        logger.error(f"Error updating subscription: {str(e)}")
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': 'Failed to update subscription'})
        }

def delete_subscription(email):
    """Delete user's subscription"""
    try:
        subscriptions_table.delete_item(
            Key={'email': email}
        )
        
        logger.info(f"Subscription deleted for {email}")
        
        return {
            'statusCode': 200,
            'headers': CORS_HEADERS,
            'body': json.dumps({'message': 'Subscription deleted successfully'})
        }
        
    except Exception as e:
        logger.error(f"Error deleting subscription: {str(e)}")
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': 'Failed to delete subscription'})
        }

def handle_scheduled_delivery(event):
    """Handle scheduled EventBridge trigger to send daily emails"""
    try:
        # Get timezone from event detail (passed from EventBridge rule)
        target_timezone = event.get('detail', {}).get('timezone', 'America/New_York')
        logger.info(f"Processing daily delivery for timezone: {target_timezone}")
        
        # Query all active subscriptions for this timezone
        response = subscriptions_table.scan(
            FilterExpression=Attr('is_subscribed').eq(True) & 
                           Attr('timezone').eq(target_timezone) &
                           Attr('delivery_method').eq('email')
        )
        
        subscribers = response.get('Items', [])
        logger.info(f"Found {len(subscribers)} subscribers for {target_timezone}")
        
        # Get today's quote
        quote_data = get_daily_quote()
        
        if not quote_data:
            logger.error("No quote available for today")
            return {
                'statusCode': 500,
                'body': json.dumps({'error': 'No quote available'})
            }
        
        # Send email to each subscriber
        success_count = 0
        error_count = 0
        
        for subscriber in subscribers:
            try:
                send_daily_email(subscriber['email'], quote_data)
                success_count += 1
            except Exception as e:
                logger.error(f"Failed to send email to {subscriber['email']}: {str(e)}")
                error_count += 1
        
        logger.info(f"Daily delivery complete: {success_count} sent, {error_count} failed")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Daily delivery complete for {target_timezone}',
                'sent': success_count,
                'failed': error_count
            })
        }
        
    except Exception as e:
        logger.error(f"Error in scheduled delivery: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def get_daily_quote():
    """Get a random quote for daily delivery (same as optimized quote handler)"""
    try:
        # Get all quotes using the TypeDateIndex (same as quote_handler_optimized.py)
        response = quotes_table.query(
            IndexName='TypeDateIndex',
            KeyConditionExpression=Key('type').eq('quote'),
            Limit=1000,
            ScanIndexForward=False  # Newest first
        )
        
        items = response.get('Items', [])
        if not items:
            logger.error("No quotes found in database")
            return None
        
        # Select a random quote (same as optimized quote handler)
        random_quote = random.choice(items)
        
        return {
            'id': random_quote.get('id', ''),
            'quote': random_quote.get('quote', ''),
            'author': random_quote.get('author', ''),
            'tags': random_quote.get('tags', [])
        }
        
    except Exception as e:
        logger.error(f"Error getting daily quote: {str(e)}")
        return None

def send_daily_email(recipient_email, quote_data):
    """Send the daily nugget email to a subscriber"""
    try:
        # Format the email
        subject = f"🌟 Your Daily Nugget - {datetime.now().strftime('%B %d, %Y')}"
        
        # HTML email template
        html_body = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <style>
                body {{ font-family: 'Georgia', serif; background-color: #f5f5f5; margin: 0; padding: 0; }}
                .container {{ max-width: 600px; margin: 40px auto; background: white; border-radius: 10px; overflow: hidden; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }}
                .header {{ background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; }}
                .content {{ padding: 40px; }}
                .quote {{ font-size: 24px; line-height: 1.6; color: #2d3748; font-style: italic; margin: 20px 0; }}
                .author {{ font-size: 18px; color: #4a5568; text-align: right; margin: 20px 0; }}
                .tags {{ margin: 30px 0; }}
                .tag {{ display: inline-block; background: #edf2f7; color: #4a5568; padding: 5px 15px; border-radius: 20px; margin: 5px; font-size: 14px; }}
                .footer {{ background: #f7fafc; padding: 20px; text-align: center; color: #718096; font-size: 14px; }}
                .unsubscribe {{ color: #4299e1; text-decoration: none; }}
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <h1 style="margin: 0; font-size: 28px;">✨ Daily Nugget</h1>
                    <p style="margin: 10px 0 0 0; opacity: 0.9;">Your daily dose of inspiration</p>
                </div>
                <div class="content">
                    <div class="quote">"{quote_data['quote']}"</div>
                    <div class="author">— {quote_data['author']}</div>
                    {format_tags_html(quote_data.get('tags', []))}
                </div>
                <div class="footer">
                    <p>You're receiving this because you subscribed to Daily Nuggets.</p>
                    <p><a href="quoteme:///profile" class="unsubscribe">Manage your subscription</a> in the Quote Me app.</p>
                    <p style="font-size: 12px; margin-top: 10px;">
                        <a href="https://quote-me.anystupididea.com/profile" style="color: #718096;">Or manage in your browser</a>
                    </p>
                </div>
            </div>
        </body>
        </html>
        """
        
        # Plain text fallback
        text_body = f"""
        Daily Nugget - {datetime.now().strftime('%B %d, %Y')}
        
        "{quote_data['quote']}"
        
        — {quote_data['author']}
        
        Tags: {', '.join(quote_data.get('tags', []))}
        
        ---
        You're receiving this because you subscribed to Daily Nuggets.
        Manage your subscription in the Quote Me app.
        """
        
        # Send email via SES
        response = ses.send_email(
            Source=f'Quote Me Daily <{SENDER_EMAIL}>',
            Destination={'ToAddresses': [recipient_email]},
            Message={
                'Subject': {'Data': subject},
                'Body': {
                    'Text': {'Data': text_body},
                    'Html': {'Data': html_body}
                }
            }
        )
        
        logger.info(f"Email sent to {recipient_email}: MessageId={response['MessageId']}")
        return True
        
    except ClientError as e:
        logger.error(f"SES error sending to {recipient_email}: {e.response['Error']['Message']}")
        raise
    except Exception as e:
        logger.error(f"Error sending email to {recipient_email}: {str(e)}")
        raise

def format_tags_html(tags):
    """Format tags for HTML email"""
    if not tags:
        return ""
    
    tags_html = '<div class="tags">'
    for tag in tags[:5]:  # Limit to 5 tags
        tags_html += f'<span class="tag">{tag}</span>'
    tags_html += '</div>'
    return tags_html

def send_test_email(email):
    """Send a test email immediately (for testing purposes)"""
    try:
        quote_data = get_daily_quote()
        if not quote_data:
            return {
                'statusCode': 404,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'No quotes available'})
            }
        
        send_daily_email(email, quote_data)
        
        return {
            'statusCode': 200,
            'headers': CORS_HEADERS,
            'body': json.dumps({
                'message': 'Test email sent successfully',
                'quote': quote_data
            }, cls=DecimalEncoder)
        }
        
    except Exception as e:
        logger.error(f"Error sending test email: {str(e)}")
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': f'Failed to send test email: {str(e)}'})
        }

def get_fcm_access_token():
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
            'sub': service_account['client_email'],
            'aud': 'https://oauth2.googleapis.com/token',
            'iat': now,
            'exp': now + 3600,  # 1 hour
            'scope': 'https://www.googleapis.com/auth/firebase.messaging'
        }
        
        # Sign with private key
        token = jwt.encode(payload, service_account['private_key'], algorithm='RS256')
        
        # Exchange JWT for access token
        response = requests.post('https://oauth2.googleapis.com/token', data={
            'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            'assertion': token
        })
        
        if response.status_code != 200:
            raise Exception(f"Failed to get access token: {response.text}")
            
        return response.json()['access_token']
        
    except Exception as e:
        logger.error(f"Error getting FCM access token: {str(e)}")
        raise

def send_test_notification(email):
    """Send a test push notification immediately (for testing purposes)"""
    try:
        # Get user's subscription to find FCM token
        response = subscriptions_table.get_item(Key={'email': email})
        
        if 'Item' not in response:
            return {
                'statusCode': 404,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'No subscription found'})
            }
        
        subscription = response['Item']
        logger.info(f"🔍 Full subscription data: {json.dumps(subscription, cls=DecimalEncoder)}")
        
        notification_prefs = subscription.get('notificationPreferences', {})
        logger.info(f"🔍 Notification preferences: {json.dumps(notification_prefs, cls=DecimalEncoder)}")
        
        fcm_tokens = notification_prefs.get('fcmTokens', {})
        logger.info(f"🔍 FCM tokens found: {json.dumps(fcm_tokens, cls=DecimalEncoder)}")
        
        if not fcm_tokens:
            return {
                'statusCode': 404,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'No FCM token found. Please enable push notifications first.'})
            }
        
        # Get a random quote
        quote_data = get_daily_quote()
        if not quote_data:
            return {
                'statusCode': 404,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'No quotes available'})
            }
        
        # Get FCM access token
        access_token = get_fcm_access_token()
        
        # Send to all platform tokens
        notifications_sent = 0
        errors = []
        
        for platform, token in fcm_tokens.items():
            if not token:
                continue
                
            try:
                # Prepare FCM message
                service_account = json.loads(FCM_SERVICE_ACCOUNT_JSON)
                project_id = service_account['project_id']
                
                fcm_message = {
                    'message': {
                        'token': token,
                        'notification': {
                            'title': 'Test Daily Nugget',
                            'body': quote_data['quote'][:100] + '...' if len(quote_data['quote']) > 100 else quote_data['quote']
                        },
                        'data': {
                            'quoteId': str(quote_data.get('id', '')),
                            'author': quote_data.get('author', ''),
                            'fullQuote': quote_data['quote'],
                            'type': 'test_notification'
                        },
                        'android': {
                            'notification': {
                                'click_action': 'FLUTTER_NOTIFICATION_CLICK',
                                'channel_id': 'daily_nuggets'
                            }
                        },
                        'apns': {
                            'payload': {
                                'aps': {
                                    'category': 'DAILY_NUGGET'
                                }
                            }
                        }
                    }
                }
                
                # Send notification
                response = requests.post(
                    FCM_API_URL.format(project_id=project_id),
                    headers={
                        'Authorization': f'Bearer {access_token}',
                        'Content-Type': 'application/json'
                    },
                    json=fcm_message
                )
                
                if response.status_code == 200:
                    notifications_sent += 1
                    logger.info(f"Test notification sent successfully to {platform}")
                else:
                    error_msg = f"FCM error for {platform}: {response.text}"
                    errors.append(error_msg)
                    logger.error(error_msg)
                    
            except Exception as e:
                error_msg = f"Error sending to {platform}: {str(e)}"
                errors.append(error_msg)
                logger.error(error_msg)
        
        if notifications_sent > 0:
            return {
                'statusCode': 200,
                'headers': CORS_HEADERS,
                'body': json.dumps({
                    'message': f'Test notification sent to {notifications_sent} device(s)',
                    'quote': quote_data,
                    'errors': errors if errors else None
                }, cls=DecimalEncoder)
            }
        else:
            return {
                'statusCode': 500,
                'headers': CORS_HEADERS,
                'body': json.dumps({
                    'error': 'Failed to send test notification',
                    'details': errors
                })
            }
        
    except Exception as e:
        logger.error(f"Error sending test notification: {str(e)}")
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': f'Failed to send test notification: {str(e)}'})
        }