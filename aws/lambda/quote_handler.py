import json
import random
import boto3
from boto3.dynamodb.conditions import Key, Attr
import logging
import os
from decimal import Decimal
from datetime import datetime
import urllib.parse

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize DynamoDB
dynamodb = boto3.resource('dynamodb')
table_name = os.environ['QUOTES_TABLE_NAME']
table = dynamodb.Table(table_name)

# CORS headers
CORS_HEADERS = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'
}

class DecimalEncoder(json.JSONEncoder):
    """Helper class to convert DynamoDB Decimal types to int/float"""
    def default(self, obj):
        if isinstance(obj, Decimal):
            return int(obj) if obj % 1 == 0 else float(obj)
        return super(DecimalEncoder, self).default(obj)

def lambda_handler(event, context):
    """Main Lambda handler for optimized quote operations"""
    try:
        logger.info(f"Event: {json.dumps(event)}")
        
        # Extract HTTP method and path
        http_method = event['httpMethod']
        path = event['resource']
        path_parameters = event.get('pathParameters') or {}
        query_parameters = event.get('queryStringParameters') or {}
        
        # Route to appropriate handler
        if path == '/quote' and http_method == 'GET':
            return get_random_quote(query_parameters)
        elif path == '/quote/{id}' and http_method == 'GET':
            return get_quote_by_id(path_parameters.get('id'))
        elif path == '/tags' and http_method == 'GET':
            return get_all_tags()
        elif path == '/quotes/author/{author}' and http_method == 'GET':
            return get_quotes_by_author(path_parameters.get('author'), query_parameters)
        elif path == '/quotes/tag/{tag}' and http_method == 'GET':
            return get_quotes_by_tag(path_parameters.get('tag'), query_parameters)
        elif path == '/search' and http_method == 'GET':
            return search_quotes(query_parameters)
        else:
            return {
                'statusCode': 404,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'Not found'})
            }
            
    except Exception as e:
        logger.error(f"Error in lambda_handler: {str(e)}")
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': 'Internal server error'})
        }

def get_random_quote(query_params):
    """Get a random quote, optionally filtered by tags"""
    try:
        tags = query_params.get('tags', '').split(',') if query_params.get('tags') else []
        tags = [tag.strip() for tag in tags if tag.strip()]
        
        if tags:
            # Get quotes filtered by tags
            quotes = []
            for tag in tags:
                tag_quotes = get_quotes_for_tag(tag, limit=100)
                quotes.extend(tag_quotes)
            
            # Remove duplicates by quote ID
            unique_quotes = {}
            for quote in quotes:
                quote_id = quote.get('id') or quote.get('PK', '').replace('QUOTE#', '')
                unique_quotes[quote_id] = quote
            
            quotes = list(unique_quotes.values())
        else:
            # Get all quotes
            quotes = get_all_quotes_from_index(limit=1000)
        
        if not quotes:
            return {
                'statusCode': 404,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'No quotes found'})
            }
        
        # Select random quote
        selected_quote = random.choice(quotes)
        
        # Format response
        formatted_quote = format_quote_response(selected_quote)
        
        return {
            'statusCode': 200,
            'headers': CORS_HEADERS,
            'body': json.dumps(formatted_quote, cls=DecimalEncoder)
        }
        
    except Exception as e:
        logger.error(f"Error in get_random_quote: {str(e)}")
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': 'Failed to retrieve quote'})
        }

def get_quote_by_id(quote_id):
    """Get a specific quote by ID"""
    try:
        if not quote_id:
            return {
                'statusCode': 400,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'Quote ID is required'})
            }
        
        # Query the quote directly using simple key structure
        response = table.get_item(
            Key={'id': quote_id}
        )
        
        if 'Item' not in response:
            return {
                'statusCode': 404,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'Requested quote was not found.'})
            }
        
        formatted_quote = format_quote_response(response['Item'])
        
        return {
            'statusCode': 200,
            'headers': CORS_HEADERS,
            'body': json.dumps(formatted_quote, cls=DecimalEncoder)
        }
        
    except Exception as e:
        logger.error(f"Error in get_quote_by_id: {str(e)}")
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': 'Failed to retrieve quote'})
        }

def get_all_tags():
    """Get all available tags from the database"""
    try:
        # Query all tag items using GSI with pagination
        tags = ['All']  # Always include 'All' option

        # Initial query
        response = table.query(
            IndexName='TypeDateIndex',
            KeyConditionExpression=Key('type').eq('tag'),
            ProjectionExpression='#name',
            ExpressionAttributeNames={'#name': 'name'}
        )

        for item in response['Items']:
            if 'name' in item:
                tags.append(item['name'])

        # Continue querying while there are more pages
        while 'LastEvaluatedKey' in response:
            response = table.query(
                IndexName='TypeDateIndex',
                KeyConditionExpression=Key('type').eq('tag'),
                ProjectionExpression='#name',
                ExpressionAttributeNames={'#name': 'name'},
                ExclusiveStartKey=response['LastEvaluatedKey']
            )

            for item in response['Items']:
                if 'name' in item:
                    tags.append(item['name'])

        # Remove duplicates and sort
        tags = sorted(list(set(tags)))

        logger.info(f"Retrieved {len(tags)} total tags from database")

        return {
            'statusCode': 200,
            'headers': CORS_HEADERS,
            'body': json.dumps({
                'tags': tags,
                'count': len(tags)
            })
        }
        
    except Exception as e:
        logger.error(f"Error in get_all_tags: {str(e)}")
        # Fallback to basic tags
        fallback_tags = ['All', 'Motivation', 'Success', 'Leadership', 'Life', 'Wisdom']
        return {
            'statusCode': 200,
            'headers': CORS_HEADERS,
            'body': json.dumps({
                'tags': fallback_tags,
                'count': len(fallback_tags)
            })
        }

def get_quotes_by_author(author, query_params):
    """Get quotes by a specific author with pagination"""
    try:
        if not author:
            return {
                'statusCode': 400,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'Author name is required'})
            }
        
        # URL decode the author name
        author = urllib.parse.unquote(author)
        author_normalized = author.lower()
        
        # Pagination parameters
        limit = int(query_params.get('limit', '50'))
        limit = min(limit, 1000)  # Cap at 1000
        
        last_key = query_params.get('last_key')
        exclusive_start_key = None
        if last_key:
            try:
                exclusive_start_key = json.loads(urllib.parse.unquote(last_key))
            except:
                logger.warning(f"Invalid last_key: {last_key}")
        
        # Query using AuthorDateIndex
        query_params = {
            'IndexName': 'AuthorDateIndex',
            'KeyConditionExpression': Key('author_normalized').eq(author_normalized),
            'Limit': limit,
            'ScanIndexForward': False  # Newest first
        }
        
        if exclusive_start_key:
            query_params['ExclusiveStartKey'] = exclusive_start_key
            
        response = table.query(**query_params)
        
        quotes = [format_quote_response(item) for item in response['Items']]
        
        result = {
            'quotes': quotes,
            'count': len(quotes),
            'author': author
        }
        
        # Add pagination info
        if 'LastEvaluatedKey' in response:
            result['last_key'] = urllib.parse.quote(json.dumps(response['LastEvaluatedKey'], cls=DecimalEncoder))
        
        return {
            'statusCode': 200,
            'headers': CORS_HEADERS,
            'body': json.dumps(result, cls=DecimalEncoder)
        }
        
    except Exception as e:
        logger.error(f"Error in get_quotes_by_author: {str(e)}")
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': 'Failed to retrieve quotes'})
        }

def get_quotes_by_tag(tag, query_params):
    """Get quotes by a specific tag with pagination"""
    try:
        if not tag:
            return {
                'statusCode': 400,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'Tag name is required'})
            }
        
        # URL decode the tag name
        tag = urllib.parse.unquote(tag)
        
        # Pagination parameters
        limit = int(query_params.get('limit', '50'))
        limit = min(limit, 1000)  # Cap at 1000
        
        last_key = query_params.get('last_key')
        exclusive_start_key = None
        if last_key:
            try:
                exclusive_start_key = json.loads(urllib.parse.unquote(last_key))
            except:
                logger.warning(f"Invalid last_key: {last_key}")
        
        # Get quotes for this tag using the mapping table
        quotes = get_quotes_for_tag(tag, limit, exclusive_start_key)
        
        result = {
            'quotes': quotes,
            'count': len(quotes),
            'tag': tag
        }
        
        return {
            'statusCode': 200,
            'headers': CORS_HEADERS,
            'body': json.dumps(result, cls=DecimalEncoder)
        }
        
    except Exception as e:
        logger.error(f"Error in get_quotes_by_tag: {str(e)}")
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': 'Failed to retrieve quotes'})
        }

def search_quotes(query_params):
    """Search quotes by text content"""
    try:
        search_text = query_params.get('q', '').strip()
        if not search_text:
            return {
                'statusCode': 400,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'Search query (q) is required'})
            }
        
        search_text_lower = search_text.lower()
        limit = int(query_params.get('limit', '50'))
        limit = min(limit, 1000)  # Cap at 1000
        
        # For now, use scan with filter (can be optimized with OpenSearch later)
        response = table.scan(
            FilterExpression=Attr('type').eq('quote') & (
                Attr('quote').contains(search_text) |
                Attr('author').contains(search_text)
            ),
            Limit=limit * 2  # Get more items since we're filtering
        )
        
        # Further filter and format results
        quotes = []
        for item in response['Items']:
            if (search_text_lower in item.get('quote', '').lower() or 
                search_text_lower in item.get('author', '').lower()):
                quotes.append(format_quote_response(item))
                if len(quotes) >= limit:
                    break
        
        result = {
            'quotes': quotes,
            'count': len(quotes),
            'query': search_text
        }
        
        return {
            'statusCode': 200,
            'headers': CORS_HEADERS,
            'body': json.dumps(result, cls=DecimalEncoder)
        }
        
    except Exception as e:
        logger.error(f"Error in search_quotes: {str(e)}")
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': 'Search failed'})
        }

def get_quotes_for_tag(tag_name, limit=50, exclusive_start_key=None):
    """Helper function to get quotes for a specific tag"""
    try:
        # First, get the quote IDs from the tag-quote mapping
        query_params = {
            'IndexName': 'TagQuoteIndex',
            'KeyConditionExpression': Key('PK').eq(f'TAG#{tag_name}'),
            'Limit': limit,
            'ScanIndexForward': False  # Newest first
        }
        
        if exclusive_start_key:
            query_params['ExclusiveStartKey'] = exclusive_start_key
            
        response = table.query(**query_params)
        
        # Get the full quote details in batch
        quote_ids = []
        for item in response['Items']:
            if item.get('type') == 'tag_quote_mapping' and 'quote_id' in item:
                quote_ids.append(item['quote_id'])
        
        if not quote_ids:
            return []
            
        # Batch get the full quote details
        quotes = batch_get_quotes(quote_ids[:limit])  # Respect limit
        return quotes
        
    except Exception as e:
        logger.error(f"Error in get_quotes_for_tag: {str(e)}")
        return []

def batch_get_quotes(quote_ids):
    """Batch get multiple quotes by ID"""
    try:
        if not quote_ids:
            return []
            
        # DynamoDB batch_get_item can handle up to 100 items
        batch_size = 100
        all_quotes = []
        
        for i in range(0, len(quote_ids), batch_size):
            batch_ids = quote_ids[i:i + batch_size]
            
            request_items = {
                table.name: {
                    'Keys': [
                        {'PK': f'QUOTE#{quote_id}', 'SK': f'QUOTE#{quote_id}'}
                        for quote_id in batch_ids
                    ]
                }
            }
            
            response = dynamodb.batch_get_item(RequestItems=request_items)
            
            if table.name in response['Responses']:
                all_quotes.extend(response['Responses'][table.name])
        
        return all_quotes
        
    except Exception as e:
        logger.error(f"Error in batch_get_quotes: {str(e)}")
        return []

def get_all_quotes_from_index(limit=1000):
    """Get all quotes using scan"""
    try:
        response = table.scan(
            Limit=limit
        )
        
        return response['Items']
        
    except Exception as e:
        logger.error(f"Error in get_all_quotes_from_index: {str(e)}")
        return []

def format_quote_response(item):
    """Format a quote item for API response"""
    try:
        # Handle both old and new data structures
        quote_id = item.get('id') or item.get('PK', '').replace('QUOTE#', '')
        
        return {
            'id': quote_id,
            'quote': item.get('quote', ''),
            'author': item.get('author', ''),
            'tags': item.get('tags', []),
            'image_url': item.get('image_url'),  # Include image URL if available
            'created_at': item.get('created_at'),
            'updated_at': item.get('updated_at')
        }
        
    except Exception as e:
        logger.error(f"Error formatting quote response: {str(e)}")
        return {
            'id': '',
            'quote': 'Error loading quote',
            'author': 'Unknown',
            'tags': [],
            'created_at': None,
            'updated_at': None
        }