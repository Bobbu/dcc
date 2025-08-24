import json
import boto3
from botocore.exceptions import ClientError
from datetime import datetime
import os
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
favorites_table = dynamodb.Table(os.environ['FAVORITES_TABLE_NAME'])
quotes_table = dynamodb.Table(os.environ['QUOTES_TABLE_NAME'])

def cors_response(status_code, body):
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,x-api-key',
        },
        'body': json.dumps(body)
    }

def get_user_id_from_context(context):
    """Extract user ID from JWT token claims"""
    try:
        logger.info(f"Request context: {json.dumps(context, default=str)}")
        claims = context.get('authorizer', {}).get('claims', {})
        logger.info(f"JWT claims: {json.dumps(claims, default=str)}")
        
        # Try sub first (standard JWT claim), then fallback to cognito:username
        user_id = claims.get('sub') or claims.get('cognito:username')
        if not user_id:
            logger.error(f"No user ID found in JWT claims. Available keys: {list(claims.keys())}")
            return None
        logger.info(f"Using user_id: {user_id}")
        return user_id
    except Exception as e:
        logger.error(f"Error extracting user ID: {str(e)}")
        return None

def get_quote_by_id(quote_id):
    """Fetch quote details from quotes table"""
    try:
        logger.info(f"Looking up quote with ID: {quote_id} in table: {os.environ.get('QUOTES_TABLE_NAME')}")
        # Use the correct composite key structure: PK and SK both = QUOTE#{quote_id}
        response = quotes_table.get_item(Key={'PK': f'QUOTE#{quote_id}', 'SK': f'QUOTE#{quote_id}'})
        logger.info(f"Quote lookup response: {response}")
        item = response.get('Item')
        if item:
            logger.info(f"Found quote: {item.get('quote', '')[:50]}...")
        else:
            logger.error(f"Quote not found in database: {quote_id}")
        return item
    except Exception as e:
        logger.error(f"Error fetching quote {quote_id}: {str(e)}")
        return None

def lambda_handler(event, context):
    try:
        method = event['httpMethod']
        path = event['path']
        
        # Extract user ID from JWT context
        user_id = get_user_id_from_context(event.get('requestContext', {}))
        if not user_id:
            return cors_response(401, {'error': 'Unauthorized - Invalid user token'})
        
        if method == 'GET' and path == '/favorites':
            return get_favorites(user_id)
        elif method == 'POST' and '/favorites/' in path:
            quote_id = path.split('/')[-1]
            return add_favorite(user_id, quote_id)
        elif method == 'DELETE' and '/favorites/' in path:
            quote_id = path.split('/')[-1]
            return remove_favorite(user_id, quote_id)
        elif method == 'GET' and '/favorites/' in path and path.endswith('/check'):
            quote_id = path.split('/')[-2]  # Extract quote_id before '/check'
            return check_favorite(user_id, quote_id)
        else:
            return cors_response(404, {'error': 'Not found'})
            
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return cors_response(500, {'error': 'Internal server error'})

def get_favorites(user_id):
    """Get all favorites for a user"""
    try:
        response = favorites_table.query(
            KeyConditionExpression=boto3.dynamodb.conditions.Key('user_id').eq(user_id),
            ScanIndexForward=False  # Sort by created_at descending (most recent first)
        )
        
        favorites = []
        for item in response['Items']:
            # Include the favorite metadata along with quote data
            favorite = {
                'quote_id': item['quote_id'],
                'created_at': item['created_at'],
                'quote': item.get('quote_snapshot', {})
            }
            favorites.append(favorite)
        
        return cors_response(200, {
            'favorites': favorites,
            'count': len(favorites)
        })
        
    except Exception as e:
        logger.error(f"Error getting favorites for user {user_id}: {str(e)}")
        return cors_response(500, {'error': 'Failed to get favorites'})

def add_favorite(user_id, quote_id):
    """Add a quote to user's favorites"""
    try:
        # First, fetch the quote to include a snapshot
        quote = get_quote_by_id(quote_id)
        if not quote:
            return cors_response(404, {'error': 'Quote not found'})
        
        # Check if already favorited
        try:
            existing = favorites_table.get_item(
                Key={'user_id': user_id, 'quote_id': quote_id}
            )
            if 'Item' in existing:
                return cors_response(200, {'message': 'Already favorited', 'is_favorite': True})
        except Exception:
            pass  # Continue if check fails
        
        # Add to favorites with quote snapshot
        now = datetime.utcnow().isoformat()
        favorites_table.put_item(
            Item={
                'user_id': user_id,
                'quote_id': quote_id,
                'created_at': now,
                'quote_snapshot': {
                    'quote': quote.get('quote', ''),
                    'author': quote.get('author', ''),
                    'tags': quote.get('tags', [])
                }
            }
        )
        
        logger.info(f"Added favorite: user={user_id}, quote={quote_id}")
        return cors_response(201, {'message': 'Added to favorites', 'is_favorite': True})
        
    except Exception as e:
        logger.error(f"Error adding favorite: user={user_id}, quote={quote_id}, error={str(e)}")
        return cors_response(500, {'error': 'Failed to add favorite'})

def remove_favorite(user_id, quote_id):
    """Remove a quote from user's favorites"""
    try:
        favorites_table.delete_item(
            Key={'user_id': user_id, 'quote_id': quote_id}
        )
        
        logger.info(f"Removed favorite: user={user_id}, quote={quote_id}")
        return cors_response(200, {'message': 'Removed from favorites', 'is_favorite': False})
        
    except Exception as e:
        logger.error(f"Error removing favorite: user={user_id}, quote={quote_id}, error={str(e)}")
        return cors_response(500, {'error': 'Failed to remove favorite'})

def check_favorite(user_id, quote_id):
    """Check if a quote is favorited by user"""
    try:
        response = favorites_table.get_item(
            Key={'user_id': user_id, 'quote_id': quote_id}
        )
        
        is_favorite = 'Item' in response
        return cors_response(200, {'is_favorite': is_favorite, 'quote_id': quote_id})
        
    except Exception as e:
        logger.error(f"Error checking favorite: user={user_id}, quote={quote_id}, error={str(e)}")
        return cors_response(500, {'error': 'Failed to check favorite status'})