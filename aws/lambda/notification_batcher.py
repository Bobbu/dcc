"""
Lambda function for batching and sending Daily Nuggets notifications.
This function is triggered by EventBridge rules for timezone-specific scheduling.
"""

import json
import os
import boto3
import logging
from typing import Dict, List
from decimal import Decimal
from datetime import datetime, timedelta, timezone as dt_timezone
import random

try:
    import pytz
except ImportError:
    # Fallback if pytz is not available
    pytz = None

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Environment variables
QUOTES_TABLE = os.environ.get('QUOTES_TABLE_NAME')
USER_PROFILES_TABLE = os.environ.get('USER_PROFILES_TABLE_NAME')
PUSH_NOTIFICATION_FUNCTION = os.environ.get('PUSH_NOTIFICATION_FUNCTION_NAME')

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
lambda_client = boto3.client('lambda')

class DecimalEncoder(json.JSONEncoder):
    """Helper class to convert DynamoDB Decimal types to JSON."""
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super(DecimalEncoder, self).default(obj)

def lambda_handler(event, context):
    """
    Main handler for notification batching.
    
    Event structure (from EventBridge):
    {
        "source": "aws.events",
        "detail": {
            "hour_utc": 8  # UTC hour (0-23)
        }
    }
    """
    
    try:
        # Extract parameters from event
        detail = event.get('detail', {})
        hour_utc = detail.get('hour_utc', 8)
        
        logger.info(f"Processing Daily Nuggets batch for UTC hour: {hour_utc}")
        
        # Find users to notify across all timezones for this UTC hour
        eligible_users = get_eligible_users_for_utc_hour(hour_utc)
        
        if not eligible_users:
            logger.info("No eligible users found for this batch")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'No eligible users found',
                    'hour_utc': hour_utc
                })
            }
        
        # Select random quote for this batch
        daily_quote = select_daily_quote()
        
        # Separate users by notification preference
        email_users = []
        push_users = []
        both_users = []
        
        for user in eligible_users:
            prefs = user.get('notificationPreferences', {})
            enable_email = prefs.get('enableEmail', False)
            enable_push = prefs.get('enablePush', False)
            
            if enable_email and enable_push:
                both_users.append(user)
            elif enable_email:
                email_users.append(user)
            elif enable_push:
                push_users.append(user)
        
        # Results tracking
        results = {
            'hour_utc': hour_utc,
            'totalUsers': len(eligible_users),
            'quote': daily_quote,
            'emailOnly': len(email_users),
            'pushOnly': len(push_users),
            'both': len(both_users),
            'emailResults': None,
            'pushResults': None
        }
        
        # Send email notifications (existing Daily Nuggets function)
        email_recipients = email_users + both_users
        if email_recipients:
            email_result = send_email_batch(email_recipients, daily_quote, hour_utc)
            results['emailResults'] = email_result
        
        # Send push notifications
        push_recipients = push_users + both_users
        if push_recipients:
            push_result = send_push_batch(push_recipients, daily_quote)
            results['pushResults'] = push_result
        
        logger.info(f"Batch complete - Email: {len(email_recipients)}, Push: {len(push_recipients)}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(results, cls=DecimalEncoder)
        }
        
    except Exception as e:
        logger.error(f"Error in notification batcher: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def get_eligible_users_for_utc_hour(hour_utc: int) -> List[Dict]:
    """Find users eligible for notifications at this UTC hour across all timezones."""
    
    # Use the subscriptions table as it contains user preferences
    subscriptions_table = dynamodb.Table(USER_PROFILES_TABLE)
    
    try:
        # Scan for all users with notification preferences
        response = subscriptions_table.scan()
        users = response['Items']
        
        # Handle pagination
        while 'LastEvaluatedKey' in response:
            response = subscriptions_table.scan(
                ExclusiveStartKey=response['LastEvaluatedKey']
            )
            users.extend(response['Items'])
        
        eligible_users = []
        for user in users:
            prefs = user.get('notificationPreferences', {})
            
            # Skip users with no notifications enabled
            if not (prefs.get('enableEmail', False) or prefs.get('enablePush', False)):
                continue
                
            # Get user's timezone and preferred hour
            user_timezone = prefs.get('timezone', 'America/New_York')
            preferred_time = prefs.get('preferredTime', '08:00')
            
            # Extract hour from preferred_time (format: "HH:MM")
            try:
                preferred_hour = int(preferred_time.split(':')[0])
            except (ValueError, IndexError):
                preferred_hour = 8  # Default to 8 AM
            
            # Calculate if this UTC hour matches the user's local preferred hour
            if user_should_receive_at_utc_hour(user_timezone, preferred_hour, hour_utc):
                eligible_users.append(user)
        
        logger.info(f"Found {len(eligible_users)} eligible users for UTC hour {hour_utc}")
        return eligible_users
        
    except Exception as e:
        logger.error(f"Failed to get eligible users: {str(e)}")
        return []

def user_should_receive_at_utc_hour(user_timezone: str, preferred_hour: int, utc_hour: int) -> bool:
    """Calculate if a user should receive notification at this UTC hour."""
    
    try:
        if pytz:
            # Use pytz if available
            user_tz = pytz.timezone(user_timezone)
            utc_dt = datetime.now(dt_timezone.utc).replace(hour=utc_hour, minute=0, second=0, microsecond=0)
            local_dt = utc_dt.astimezone(user_tz)
            return local_dt.hour == preferred_hour
        else:
            # Simple timezone offset mapping fallback
            timezone_offsets = {
                'America/New_York': -5,  # EST
                'America/Chicago': -6,   # CST
                'America/Denver': -7,    # MST
                'America/Los_Angeles': -8,  # PST
                'Europe/London': 0,      # GMT
                'UTC': 0
            }
            
            offset = timezone_offsets.get(user_timezone, 0)
            # During DST, US timezones are 1 hour ahead
            # Simple check: April-October
            month = datetime.now().month
            if user_timezone.startswith('America/') and 4 <= month <= 10:
                offset += 1
            
            local_hour = (utc_hour + offset) % 24
            return local_hour == preferred_hour
        
    except Exception as e:
        logger.warning(f"Error calculating timezone for {user_timezone}: {str(e)}")
        # Fallback: assume UTC if timezone calculation fails
        return utc_hour == preferred_hour

def select_daily_quote() -> Dict:
    """Select a random quote for today's Daily Nuggets."""
    
    quotes_table = dynamodb.Table(QUOTES_TABLE)
    
    try:
        # Use the same logic as existing daily nuggets
        # This could be enhanced to ensure different quotes on different days
        response = quotes_table.scan(
            Limit=50,  # Get a sample to choose from
            Select='ALL_ATTRIBUTES'
        )
        
        quotes = response['Items']
        
        if not quotes:
            raise ValueError("No quotes available in database")
        
        # Select random quote
        daily_quote = random.choice(quotes)
        
        logger.info(f"Selected daily quote: {daily_quote['id']} by {daily_quote.get('author', 'Unknown')}")
        return daily_quote
        
    except Exception as e:
        logger.error(f"Failed to select daily quote: {str(e)}")
        raise

def send_email_batch(users: List[Dict], quote: Dict, hour_utc: int) -> Dict:
    """Send email notifications via existing Daily Nuggets function."""
    
    try:
        # Extract email addresses
        emails = []
        for user in users:
            if user.get('email'):
                emails.append(user['email'])
        
        if not emails:
            return {'sent': 0, 'error': 'No email addresses found'}
        
        # Send emails directly using SES
        sent_count = 0
        errors = []
        
        # Import SES here to avoid issues if not available
        import boto3
        ses_client = boto3.client('ses', region_name='us-east-1')
        
        for email in emails:
            try:
                # Create email content with same format as original Daily Nuggets
                from datetime import datetime
                subject = f"🌟 Your Daily Nugget - {datetime.now().strftime('%B %d, %Y')}"
                
                # Create professional HTML body matching original format
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
                            <div class="quote">"{quote.get('quote', '')}"</div>
                            <div class="author">— {quote.get('author', 'Unknown')}</div>
                            {format_tags_html(quote.get('tags', []))}
                        </div>
                        <div class="footer">
                            <p>You're receiving this because you subscribed to Daily Nuggets.</p>
                            <p><a href="https://quote-me.anystupididea.com/profile" class="unsubscribe">Manage your subscription</a> in the Quote Me app.</p>
                        </div>
                    </div>
                </body>
                </html>
                """
                
                # Create text body
                text_body = f"""
🌟 Your Daily Nugget - {datetime.now().strftime('%B %d, %Y')}

"{quote.get('quote', '')}"

— {quote.get('author', 'Unknown')}

{format_tags_text(quote.get('tags', []))}

You're receiving this because you subscribed to Daily Nuggets.
Manage your subscription in the Quote Me app.
                """
                
                # Send email via SES with proper sender name
                response = ses_client.send_email(
                    Source='Quote Me Daily <noreply@anystupididea.com>',
                    Destination={'ToAddresses': [email]},
                    Message={
                        'Subject': {'Data': subject},
                        'Body': {
                            'Text': {'Data': text_body},
                            'Html': {'Data': html_body}
                        }
                    }
                )
                
                sent_count += 1
                logger.info(f"Successfully sent email to {email} (MessageId: {response['MessageId']})")
                
            except Exception as e:
                error_msg = f"Error sending to {email}: {str(e)}"
                logger.error(error_msg)
                errors.append(error_msg)
        
        result = {
            'sent': sent_count,
            'total': len(emails),
            'message': f'Email batch sent to {sent_count}/{len(emails)} users'
        }
        
        if errors:
            result['errors'] = errors
        
        logger.info(f"Email batch complete: {sent_count}/{len(emails)} sent")
        return result
        
    except Exception as e:
        logger.error(f"Failed to send email batch: {str(e)}")
        return {'sent': 0, 'error': str(e)}

def send_push_batch(users: List[Dict], quote: Dict) -> Dict:
    """Send push notifications via push notification function."""
    
    try:
        # Extract user IDs for users with push notifications enabled
        user_ids = []
        for user in users:
            prefs = user.get('notificationPreferences', {})
            if prefs.get('enablePush', False):
                user_ids.append(user['userId'])
        
        if not user_ids:
            return {'sent': 0, 'error': 'No users with push notifications enabled'}
        
        # Call push notification function
        payload = {
            'action': 'send_batch',
            'userIds': user_ids,
            'quoteId': quote['id'],
            'testMode': False
        }
        
        response = lambda_client.invoke(
            FunctionName=PUSH_NOTIFICATION_FUNCTION,
            InvocationType='Event',  # Async
            Payload=json.dumps(payload, cls=DecimalEncoder)
        )
        
        logger.info(f"Push notification batch sent to {len(user_ids)} users")
        
        return {
            'sent': len(user_ids),
            'message': f'Push batch sent to {len(user_ids)} users',
            'invokeResponse': response['StatusCode']
        }
        
    except Exception as e:
        logger.error(f"Failed to send push batch: {str(e)}")
        return {'sent': 0, 'error': str(e)}

def update_user_delivery_stats(users: List[Dict], delivery_type: str):
    """Update user statistics for delivery tracking."""
    
    try:
        user_table = dynamodb.Table(USER_PROFILES_TABLE)
        current_time = datetime.utcnow().isoformat()
        
        # Batch update user stats
        # Note: DynamoDB batch operations have limits
        for user in users:
            try:
                user_table.update_item(
                    Key={'userId': user['userId']},
                    UpdateExpression=f"SET notificationStats.last{delivery_type.title()}Sent = :now",
                    ExpressionAttributeValues={
                        ':now': current_time
                    }
                )
            except Exception as e:
                logger.warning(f"Failed to update stats for user {user['userId']}: {str(e)}")
        
    except Exception as e:
        logger.error(f"Failed to update user delivery stats: {str(e)}")

def format_tags_html(tags):
    """Format tags for HTML email"""
    if not tags:
        return ""
    
    tags_html = '<div class="tags">'
    for tag in tags[:5]:  # Limit to 5 tags
        tags_html += f'<span class="tag">{tag}</span>'
    tags_html += '</div>'
    return tags_html

def format_tags_text(tags):
    """Format tags for text email"""
    if not tags:
        return ""
    
    return f"Tags: {', '.join(tags[:5])}"  # Limit to 5 tags