import json
import boto3
from boto3.dynamodb.conditions import Key, Attr
import logging
import os
from decimal import Decimal
from datetime import datetime, timezone
import uuid
import urllib.parse

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
cognito_client = boto3.client('cognito-idp')

table_name = os.environ['TABLE_NAME']
user_pool_id = os.environ['USER_POOL_ID']
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
    """Main Lambda handler for admin operations"""
    try:
        logger.info(f"Admin Event: {json.dumps(event)}")
        
        # Verify admin access
        user_info = get_user_from_token(event)
        if not user_info or not is_admin_user(user_info['username']):
            return {
                'statusCode': 403,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'Access denied. Admin privileges required.'})
            }
        
        # Extract HTTP method and path
        http_method = event['httpMethod']
        path = event['resource']
        path_parameters = event.get('pathParameters') or {}
        query_parameters = event.get('queryStringParameters') or {}
        
        # Parse request body for POST/PUT requests
        body = {}
        if event.get('body'):
            try:
                body = json.loads(event['body'])
            except json.JSONDecodeError:
                return {
                    'statusCode': 400,
                    'headers': CORS_HEADERS,
                    'body': json.dumps({'error': 'Invalid JSON in request body'})
                }
        
        # Route to appropriate handler
        if path == '/admin/quotes' and http_method == 'GET':
            return admin_get_quotes(query_parameters)
        elif path == '/admin/quotes' and http_method == 'POST':
            return admin_create_quote(body, user_info['username'])
        elif path == '/admin/quotes/{id}' and http_method == 'PUT':
            return admin_update_quote(path_parameters.get('id'), body, user_info['username'])
        elif path == '/admin/quotes/{id}' and http_method == 'DELETE':
            return admin_delete_quote(path_parameters.get('id'))
        elif path == '/admin/tags' and http_method == 'GET':
            return admin_get_tags()
        elif path == '/admin/tags' and http_method == 'POST':
            return admin_create_tag(body, user_info['username'])
        elif path == '/admin/tags/{tag}' and http_method == 'PUT':
            return admin_update_tag(path_parameters.get('tag'), body, user_info['username'])
        elif path == '/admin/tags/{tag}' and http_method == 'DELETE':
            return admin_delete_tag(path_parameters.get('tag'))
        elif path == '/admin/tags/unused' and http_method == 'DELETE':
            return admin_cleanup_unused_tags()
        elif path == '/admin/authors' and http_method == 'GET':
            return admin_get_authors(query_parameters)
        elif path == '/admin/export' and http_method == 'GET':
            return admin_export_data(query_parameters)
        elif path == '/admin/search' and http_method == 'GET':
            return admin_search_quotes(query_parameters)
        elif path == '/admin/quotes/author/{author}' and http_method == 'GET':
            return admin_get_quotes_by_author(path_parameters.get('author'), query_parameters)
        elif path == '/admin/quotes/tag/{tag}' and http_method == 'GET':
            return admin_get_quotes_by_tag(path_parameters.get('tag'), query_parameters)
        else:
            return {
                'statusCode': 404,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'Not found'})
            }
            
    except Exception as e:
        logger.error(f"Error in admin lambda_handler: {str(e)}")
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': 'Internal server error'})
        }

def admin_get_quotes(query_params):
    """Get all quotes with pagination and filtering"""
    try:
        # Pagination parameters
        limit = int(query_params.get('limit', '50'))
        limit = min(limit, 1000)  # Cap at 1000 for admin
        
        last_key = query_params.get('last_key')
        exclusive_start_key = None
        if last_key:
            try:
                exclusive_start_key = json.loads(urllib.parse.unquote(last_key))
            except:
                logger.warning(f"Invalid last_key: {last_key}")
        
        # Sorting parameters
        sort_by = query_params.get('sort_by', 'created_at')  # Default to created_at
        sort_order = query_params.get('sort_order', 'desc')  # Default to descending
        scan_forward = sort_order == 'asc'
        
        # Filtering parameters
        tag_filter = query_params.get('tag')
        author_filter = query_params.get('author')
        search_query = query_params.get('search', '').strip()
        
        # Track pagination info
        last_evaluated_key = None
        
        # Build query based on filters
        if tag_filter and tag_filter != 'All':
            # Filter by tag using tag-quote mappings
            quotes = get_quotes_by_tag_admin(tag_filter, limit, exclusive_start_key)
        elif author_filter:
            # Filter by author using AuthorDateIndex
            quotes = get_quotes_by_author_admin(author_filter, limit, exclusive_start_key)
        else:
            # Get all quotes using TypeDateIndex
            # Add filter to ensure we only get actual quotes (PK starts with QUOTE#)
            query_params_dict = {
                'IndexName': 'TypeDateIndex',
                'KeyConditionExpression': Key('type').eq('quote'),
                'FilterExpression': 'begins_with(PK, :quote_prefix)',
                'ExpressionAttributeValues': {
                    ':quote_prefix': 'QUOTE#'
                },
                'Limit': limit,
                'ScanIndexForward': scan_forward  # Control sort order
            }
            
            if exclusive_start_key:
                query_params_dict['ExclusiveStartKey'] = exclusive_start_key
                
            response = table.query(**query_params_dict)
            quotes = response['Items']
            last_evaluated_key = response.get('LastEvaluatedKey')
        
        # Apply search filter if provided
        if search_query:
            search_lower = search_query.lower()
            quotes = [
                quote for quote in quotes
                if (search_lower in quote.get('quote', '').lower() or
                    search_lower in quote.get('author', '').lower())
            ]
        
        # Format quotes for response
        formatted_quotes = []
        for quote in quotes:
            formatted_quote = format_admin_quote_response(quote)
            formatted_quotes.append(formatted_quote)
        
        # Sort by requested field if not using database sorting
        if sort_by in ['quote', 'author']:
            try:
                reverse = sort_order == 'desc'
                formatted_quotes.sort(key=lambda x: x.get(sort_by, '').lower(), reverse=reverse)
            except:
                pass
        
        # Get total count (efficiently using metadata or count query)
        total_count = get_total_quotes_count()
        
        result = {
            'quotes': formatted_quotes,
            'count': len(formatted_quotes),
            'total_count': total_count,
            'has_more': last_evaluated_key is not None
        }
        
        # Add pagination info if available
        if last_evaluated_key:
            result['last_key'] = urllib.parse.quote(json.dumps(last_evaluated_key, cls=DecimalEncoder))
        
        return {
            'statusCode': 200,
            'headers': CORS_HEADERS,
            'body': json.dumps(result, cls=DecimalEncoder)
        }
        
    except Exception as e:
        logger.error(f"Error in admin_get_quotes: {str(e)}")
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': 'Failed to retrieve quotes'})
        }

def admin_create_quote(body, username):
    """Create a new quote"""
    try:
        # Validate required fields
        if not body.get('quote') or not body.get('author'):
            return {
                'statusCode': 400,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'Quote text and author are required'})
            }
        
        # Generate quote ID
        quote_id = str(uuid.uuid4())
        now = datetime.now(timezone.utc).isoformat()
        
        # Prepare quote data
        quote_data = {
            'PK': f'QUOTE#{quote_id}',
            'SK': f'QUOTE#{quote_id}',
            'type': 'quote',
            'id': quote_id,
            'quote': body['quote'].strip(),
            'author': body['author'].strip(),
            'author_normalized': body['author'].strip().lower(),
            'quote_normalized': body['quote'].strip().lower()[:100],  # First 100 chars for search
            'tags': body.get('tags', []),
            'created_at': now,
            'updated_at': now,
            'created_by': username
        }
        
        # Start transaction to create quote and tag mappings
        transact_items = [
            {
                'Put': {
                    'TableName': table.name,
                    'Item': quote_data
                }
            }
        ]
        
        # Create tag mappings and update tag metadata
        tags = body.get('tags', [])
        for tag in tags:
            if tag:
                # Create tag-quote mapping
                transact_items.append({
                    'Put': {
                        'TableName': table.name,
                        'Item': {
                            'PK': f'TAG#{tag}',
                            'SK': f'QUOTE#{quote_id}',
                            'type': 'tag_quote_mapping',
                            'quote_id': quote_id,
                            'author': body['author'].strip(),
                            'created_at': now
                        }
                    }
                })
                
                # Create/update tag metadata
                ensure_tag_exists(tag, username, now)
        
        # Execute transaction
        dynamodb.meta.client.transact_write_items(TransactItems=transact_items)
        
        # Update author aggregation (async via streams)
        
        # Update the total count
        update_quotes_count(1)  # Increment by 1
        
        formatted_quote = format_admin_quote_response(quote_data)
        
        return {
            'statusCode': 201,
            'headers': CORS_HEADERS,
            'body': json.dumps({
                'message': 'Quote created successfully',
                'quote': formatted_quote
            }, cls=DecimalEncoder)
        }
        
    except Exception as e:
        logger.error(f"Error in admin_create_quote: {str(e)}")
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': 'Failed to create quote'})
        }

def admin_update_quote(quote_id, body, username):
    """Update an existing quote"""
    try:
        if not quote_id:
            return {
                'statusCode': 400,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'Quote ID is required'})
            }
        
        # Get existing quote
        existing_response = table.get_item(
            Key={'PK': f'QUOTE#{quote_id}', 'SK': f'QUOTE#{quote_id}'}
        )
        
        if 'Item' not in existing_response:
            return {
                'statusCode': 404,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'Quote not found'})
            }
        
        existing_quote = existing_response['Item']
        now = datetime.now(timezone.utc).isoformat()
        
        # Prepare updated quote data
        updated_quote = {
            'PK': f'QUOTE#{quote_id}',
            'SK': f'QUOTE#{quote_id}',
            'type': 'quote',
            'id': quote_id,
            'quote': body.get('quote', existing_quote.get('quote', '')).strip(),
            'author': body.get('author', existing_quote.get('author', '')).strip(),
            'author_normalized': body.get('author', existing_quote.get('author', '')).strip().lower(),
            'quote_normalized': body.get('quote', existing_quote.get('quote', '')).strip().lower()[:100],
            'tags': body.get('tags', existing_quote.get('tags', [])),
            'created_at': existing_quote.get('created_at'),
            'updated_at': now,
            'created_by': existing_quote.get('created_by'),
            'updated_by': username
        }
        
        # Handle tag changes
        old_tags = set(existing_quote.get('tags', []))
        new_tags = set(body.get('tags', []))
        
        # First, ensure all new tags exist (outside transaction)
        logger.info(f"Ensuring tags exist for: {new_tags}")
        for tag in new_tags:
            if tag:
                logger.info(f"Ensuring tag exists: {tag}")
                ensure_tag_exists(tag, username, now)
        
        # Calculate which tags to add/remove/keep
        tags_to_remove = old_tags - new_tags
        tags_to_add = new_tags - old_tags
        tags_to_keep = old_tags & new_tags
        
        logger.info(f"Tags to remove: {tags_to_remove}")
        logger.info(f"Tags to add: {tags_to_add}")
        logger.info(f"Tags to keep: {tags_to_keep}")
        
        transact_items = [
            {
                'Put': {
                    'TableName': table.name,
                    'Item': updated_quote
                }
            }
        ]
        
        # Remove old tag mappings (only for tags being removed)
        for tag in tags_to_remove:
            transact_items.append({
                'Delete': {
                    'TableName': table.name,
                    'Key': {
                        'PK': f'TAG#{tag}',
                        'SK': f'QUOTE#{quote_id}'
                    }
                }
            })
        
        # Add new tag mappings (only for tags being added)
        for tag in tags_to_add:
            if tag:
                transact_items.append({
                    'Put': {
                        'TableName': table.name,
                        'Item': {
                            'PK': f'TAG#{tag}',
                            'SK': f'QUOTE#{quote_id}',
                            'type': 'tag_quote_mapping',
                            'quote_id': quote_id,
                            'author': updated_quote['author'],
                            'created_at': now
                        }
                    }
                })
        
        # Execute transaction
        logger.info(f"Executing transaction with {len(transact_items)} items")
        dynamodb.meta.client.transact_write_items(TransactItems=transact_items)
        logger.info("Transaction completed successfully")
        
        formatted_quote = format_admin_quote_response(updated_quote)
        
        return {
            'statusCode': 200,
            'headers': CORS_HEADERS,
            'body': json.dumps({
                'message': 'Quote updated successfully',
                'quote': formatted_quote
            }, cls=DecimalEncoder)
        }
        
    except Exception as e:
        logger.error(f"Error in admin_update_quote: {str(e)}")
        logger.error(f"Error type: {type(e).__name__}")
        logger.error(f"Quote ID: {quote_id}")
        if hasattr(e, 'response'):
            logger.error(f"DynamoDB error response: {e.response}")
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': f'Failed to update quote: {str(e)}'})
        }

def admin_delete_quote(quote_id):
    """Delete a quote and its associated mappings"""
    try:
        if not quote_id:
            return {
                'statusCode': 400,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'Quote ID is required'})
            }
        
        # Get existing quote to find its tags
        existing_response = table.get_item(
            Key={'PK': f'QUOTE#{quote_id}', 'SK': f'QUOTE#{quote_id}'}
        )
        
        if 'Item' not in existing_response:
            return {
                'statusCode': 404,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'Quote not found'})
            }
        
        existing_quote = existing_response['Item']
        tags = existing_quote.get('tags', [])
        
        # Prepare transaction to delete quote and all mappings
        transact_items = [
            {
                'Delete': {
                    'TableName': table.name,
                    'Key': {
                        'PK': f'QUOTE#{quote_id}',
                        'SK': f'QUOTE#{quote_id}'
                    }
                }
            }
        ]
        
        # Delete tag mappings
        for tag in tags:
            transact_items.append({
                'Delete': {
                    'TableName': table.name,
                    'Key': {
                        'PK': f'TAG#{tag}',
                        'SK': f'QUOTE#{quote_id}'
                    }
                }
            })
        
        # Execute transaction
        dynamodb.meta.client.transact_write_items(TransactItems=transact_items)
        
        # Update the total count
        update_quotes_count(-1)  # Decrement by 1
        
        return {
            'statusCode': 200,
            'headers': CORS_HEADERS,
            'body': json.dumps({'message': 'Quote deleted successfully'})
        }
        
    except Exception as e:
        logger.error(f"Error in admin_delete_quote: {str(e)}")
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': 'Failed to delete quote'})
        }

def admin_get_tags():
    """Get all tags with full metadata including quote counts"""
    try:
        response = table.query(
            IndexName='TypeDateIndex',
            KeyConditionExpression=Key('type').eq('tag'),
            ScanIndexForward=False
        )
        
        # Build tag metadata using stored quote counts (no queries needed!)
        tags = []
        for item in response['Items']:
            tag_name = item.get('name', '')
            if tag_name:
                tag_data = {
                    'name': tag_name,
                    'quote_count': item.get('quote_count', 0),  # Use stored count!
                    'created_at': item.get('created_at'),
                    'updated_at': item.get('updated_at'),
                    'created_by': item.get('created_by'),
                    'last_used': item.get('last_used')
                }
                tags.append(tag_data)
        
        # Sort tags alphabetically by name
        tags.sort(key=lambda x: x['name'].lower())
        
        return {
            'statusCode': 200,
            'headers': CORS_HEADERS,
            'body': json.dumps({
                'tags': tags,
                'count': len(tags)
            }, cls=DecimalEncoder)
        }
        
    except Exception as e:
        logger.error(f"Error in admin_get_tags: {str(e)}")
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': 'Failed to retrieve tags'})
        }

def admin_get_authors(query_params):
    """Get all authors with statistics"""
    try:
        limit = int(query_params.get('limit', '50'))
        limit = min(limit, 100)
        
        response = table.query(
            IndexName='TypeDateIndex',
            KeyConditionExpression=Key('type').eq('author'),
            Limit=limit,
            ScanIndexForward=False
        )
        
        authors = []
        for item in response['Items']:
            author_data = {
                'name': item.get('name', ''),
                'quote_count': item.get('quote_count', 0),
                'tags_used': item.get('tags_used', []),
                'first_quote_date': item.get('first_quote_date'),
                'last_quote_date': item.get('last_quote_date')
            }
            authors.append(author_data)
        
        return {
            'statusCode': 200,
            'headers': CORS_HEADERS,
            'body': json.dumps({
                'authors': authors,
                'count': len(authors)
            }, cls=DecimalEncoder)
        }
        
    except Exception as e:
        logger.error(f"Error in admin_get_authors: {str(e)}")
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': 'Failed to retrieve authors'})
        }

# Helper functions

def get_user_from_token(event):
    """Extract user information from JWT token"""
    try:
        claims = event.get('requestContext', {}).get('authorizer', {}).get('claims', {})
        if not claims:
            return None
        
        return {
            'username': claims.get('cognito:username'),
            'email': claims.get('email'),
            'groups': claims.get('cognito:groups', '').split(',') if claims.get('cognito:groups') else []
        }
    except Exception as e:
        logger.error(f"Error extracting user from token: {str(e)}")
        return None

def is_admin_user(username):
    """Check if user is in the Admins group"""
    try:
        response = cognito_client.list_users_in_group(
            UserPoolId=user_pool_id,
            GroupName='Admins'
        )
        
        admin_users = [user['Username'] for user in response['Users']]
        return username in admin_users
        
    except Exception as e:
        logger.error(f"Error checking admin status: {str(e)}")
        return False

def ensure_tag_exists(tag_name, username, timestamp):
    """Ensure a tag exists in the database"""
    try:
        table.put_item(
            Item={
                'PK': f'TAG#{tag_name}',
                'SK': f'TAG#{tag_name}',
                'type': 'tag',
                'name': tag_name,
                'name_normalized': tag_name.lower(),
                'created_at': timestamp,
                'updated_at': timestamp,
                'created_by': username,
                'quote_count': 0,
                'last_used': timestamp
            },
            ConditionExpression='attribute_not_exists(PK)'  # Only create if doesn't exist
        )
    except dynamodb.meta.client.exceptions.ConditionalCheckFailedException:
        # Tag already exists, that's fine
        pass
    except Exception as e:
        logger.error(f"Error ensuring tag exists: {str(e)}")

def get_quotes_by_tag_admin(tag_name, limit, exclusive_start_key):
    """Get quotes by tag for admin interface"""
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
        quotes = batch_get_quotes_admin(quote_ids[:limit])  # Respect limit
        return quotes
        
    except Exception as e:
        logger.error(f"Error in get_quotes_by_tag_admin: {str(e)}")
        return []

def get_quotes_by_author_admin(author_name, limit, exclusive_start_key):
    """Get quotes by author for admin interface"""
    try:
        author_normalized = author_name.lower()
        
        query_params = {
            'IndexName': 'AuthorDateIndex',
            'KeyConditionExpression': Key('author_normalized').eq(author_normalized),
            'Limit': limit,
            'ScanIndexForward': False  # Newest first
        }
        
        if exclusive_start_key:
            query_params['ExclusiveStartKey'] = exclusive_start_key
            
        response = table.query(**query_params)
        return response['Items']
        
    except Exception as e:
        logger.error(f"Error in get_quotes_by_author_admin: {str(e)}")
        return []

def batch_get_quotes_admin(quote_ids):
    """Batch get multiple quotes by ID for admin interface"""
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
        logger.error(f"Error in batch_get_quotes_admin: {str(e)}")
        return []

def get_total_quotes_count():
    """Get total count of quotes efficiently"""
    try:
        # First, try to get from metadata record
        metadata_response = table.get_item(
            Key={'PK': 'METADATA#QUOTES', 'SK': 'STATS'}
        )
        
        if 'Item' in metadata_response and 'total_count' in metadata_response['Item']:
            return int(metadata_response['Item']['total_count'])
        
        # Fallback: Count actual quotes (where PK starts with QUOTE#)
        # We need to filter to only count actual quote items, not tag mappings or other items
        count = 0
        last_evaluated_key = None
        
        while True:
            query_params = {
                'IndexName': 'TypeDateIndex',
                'KeyConditionExpression': Key('type').eq('quote'),
                'FilterExpression': 'begins_with(PK, :quote_prefix)',
                'ExpressionAttributeValues': {
                    ':quote_prefix': 'QUOTE#'
                },
                'Select': 'COUNT'
            }
            
            if last_evaluated_key:
                query_params['ExclusiveStartKey'] = last_evaluated_key
            
            response = table.query(**query_params)
            count += response['Count']
            
            last_evaluated_key = response.get('LastEvaluatedKey')
            if not last_evaluated_key:
                break
        
        logger.info(f"Counted {count} actual quotes in database")
        
        # Store the count in metadata for next time
        table.put_item(
            Item={
                'PK': 'METADATA#QUOTES',
                'SK': 'STATS',
                'type': 'metadata',
                'total_count': count,
                'last_updated': datetime.now(timezone.utc).isoformat()
            }
        )
        
        return count
        
    except Exception as e:
        logger.error(f"Error getting total quotes count: {str(e)}")
        return -1  # Return -1 to indicate error

def update_quotes_count(delta):
    """Update the total quotes count by delta (positive or negative)"""
    try:
        # Use atomic counter update
        response = table.update_item(
            Key={'PK': 'METADATA#QUOTES', 'SK': 'STATS'},
            UpdateExpression='ADD total_count :delta SET last_updated = :now, #type = :type',
            ExpressionAttributeValues={
                ':delta': delta,
                ':now': datetime.now(timezone.utc).isoformat(),
                ':type': 'metadata'
            },
            ExpressionAttributeNames={
                '#type': 'type'
            },
            ReturnValues='UPDATED_NEW'
        )
        return response.get('Attributes', {}).get('total_count', -1)
    except Exception as e:
        logger.error(f"Error updating quotes count: {str(e)}")
        return -1

def format_admin_quote_response(item):
    """Format a quote item for admin API response"""
    try:
        quote_id = item.get('id') or item.get('PK', '').replace('QUOTE#', '')
        
        return {
            'id': quote_id,
            'quote': item.get('quote', ''),
            'author': item.get('author', ''),
            'tags': item.get('tags', []),
            'created_at': item.get('created_at'),
            'updated_at': item.get('updated_at'),
            'created_by': item.get('created_by'),
            'updated_by': item.get('updated_by')
        }
        
    except Exception as e:
        logger.error(f"Error formatting admin quote response: {str(e)}")
        return {
            'id': '',
            'quote': 'Error loading quote',
            'author': 'Unknown',
            'tags': [],
            'created_at': None,
            'updated_at': None
        }

def admin_create_tag(body, username):
    """Create a new tag"""
    try:
        # Support both 'tag' and 'name' fields for compatibility
        tag_name = body.get('tag', body.get('name', '')).strip()
        if not tag_name:
            return {
                'statusCode': 400,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'Tag name is required'})
            }
        
        now = datetime.now(timezone.utc).isoformat()
        
        # Check if tag already exists
        existing = table.get_item(
            Key={'PK': f'TAG#{tag_name}', 'SK': f'TAG#{tag_name}'}
        )
        
        if 'Item' in existing:
            return {
                'statusCode': 409,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'Tag already exists'})
            }
        
        # Create tag
        tag_item = {
            'PK': f'TAG#{tag_name}',
            'SK': f'TAG#{tag_name}',
            'type': 'tag',
            'name': tag_name,
            'name_normalized': tag_name.lower(),
            'created_at': now,
            'updated_at': now,
            'created_by': username,
            'quote_count': 0,
            'last_used': now
        }
        
        table.put_item(Item=tag_item)
        
        return {
            'statusCode': 201,
            'headers': CORS_HEADERS,
            'body': json.dumps({
                'message': 'Tag created successfully',
                'tag': {
                    'name': tag_name,
                    'quote_count': 0,
                    'created_at': now
                }
            })
        }
        
    except Exception as e:
        logger.error(f"Error in admin_create_tag: {str(e)}")
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': 'Failed to create tag'})
        }

def admin_update_tag(old_tag_name, body, username):
    """Update/rename a tag and all associated quotes"""
    try:
        # Support both 'tag' and 'name' fields for compatibility
        new_tag_name = body.get('tag', body.get('name', '')).strip()
        if not new_tag_name or not old_tag_name:
            return {
                'statusCode': 400,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'Both old and new tag names are required'})
            }
        
        # URL decode the old tag name
        old_tag_name = urllib.parse.unquote(old_tag_name)
        
        if old_tag_name == new_tag_name:
            return {
                'statusCode': 400,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'New tag name must be different'})
            }
        
        # Check if new tag already exists
        existing_tag = table.get_item(
            Key={'PK': f'TAG#{new_tag_name}', 'SK': f'TAG#{new_tag_name}'}
        )
        
        if 'Item' in existing_tag:
            return {
                'statusCode': 409,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'New tag name already exists'})
            }
        
        now = datetime.now(timezone.utc).isoformat()
        quotes_updated = 0
        
        # Get all quotes that use this tag via tag-quote mappings
        mappings_response = table.query(
            IndexName='TagQuoteIndex',
            KeyConditionExpression=Key('PK').eq(f'TAG#{old_tag_name}')
        )
        
        # Update each quote that uses this tag
        for mapping in mappings_response['Items']:
            if mapping.get('type') == 'tag_quote_mapping':
                quote_id = mapping.get('quote_id')
                if quote_id:
                    # Get the quote details
                    quote_response = table.get_item(
                        Key={'PK': f'QUOTE#{quote_id}', 'SK': f'QUOTE#{quote_id}'}
                    )
                    
                    if 'Item' in quote_response:
                        quote = quote_response['Item']
                        tags = quote.get('tags', [])
                        
                        # Replace old tag with new tag in the tags list
                        if old_tag_name in tags:
                            new_tags = [new_tag_name if tag == old_tag_name else tag for tag in tags]
                            
                            # Update the quote with new tags
                            table.update_item(
                                Key={'PK': f'QUOTE#{quote_id}', 'SK': f'QUOTE#{quote_id}'},
                                UpdateExpression='SET tags = :tags, updated_at = :updated_at, updated_by = :updated_by',
                                ExpressionAttributeValues={
                                    ':tags': new_tags,
                                    ':updated_at': now,
                                    ':updated_by': username
                                }
                            )
                            quotes_updated += 1
        
        # Create new tag metadata
        new_tag_item = {
            'PK': f'TAG#{new_tag_name}',
            'SK': f'TAG#{new_tag_name}',
            'type': 'tag',
            'name': new_tag_name,
            'name_normalized': new_tag_name.lower(),
            'created_at': now,
            'updated_at': now,
            'created_by': username,
            'quote_count': quotes_updated,
            'last_used': now
        }
        
        # Use transaction to create new tag and delete old tag
        transact_items = [
            {
                'Put': {
                    'TableName': table.name,
                    'Item': new_tag_item
                }
            },
            {
                'Delete': {
                    'TableName': table.name,
                    'Key': {'PK': f'TAG#{old_tag_name}', 'SK': f'TAG#{old_tag_name}'}
                }
            }
        ]
        
        # Update all tag-quote mappings to use new tag name
        for mapping in mappings_response['Items']:
            if mapping.get('type') == 'tag_quote_mapping':
                quote_id = mapping.get('quote_id')
                if quote_id:
                    # Delete old mapping
                    transact_items.append({
                        'Delete': {
                            'TableName': table.name,
                            'Key': {'PK': f'TAG#{old_tag_name}', 'SK': f'QUOTE#{quote_id}'}
                        }
                    })
                    
                    # Create new mapping
                    transact_items.append({
                        'Put': {
                            'TableName': table.name,
                            'Item': {
                                'PK': f'TAG#{new_tag_name}',
                                'SK': f'QUOTE#{quote_id}',
                                'type': 'tag_quote_mapping',
                                'quote_id': quote_id,
                                'author': mapping.get('author', ''),
                                'created_at': now
                            }
                        }
                    })
        
        # Execute transaction (may need to batch for large numbers of items)
        if len(transact_items) <= 100:  # DynamoDB transaction limit
            dynamodb.meta.client.transact_write_items(TransactItems=transact_items)
        else:
            # Handle large transactions by batching
            for i in range(0, len(transact_items), 100):
                batch = transact_items[i:i+100]
                dynamodb.meta.client.transact_write_items(TransactItems=batch)
        
        return {
            'statusCode': 200,
            'headers': CORS_HEADERS,
            'body': json.dumps({
                'message': 'Tag updated successfully',
                'quotes_updated': quotes_updated,
                'old_tag': old_tag_name,
                'new_tag': new_tag_name
            })
        }
        
    except Exception as e:
        logger.error(f"Error in admin_update_tag: {str(e)}")
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': 'Failed to update tag'})
        }

def admin_delete_tag(tag_name):
    """Delete a tag and remove it from all quotes that use it"""
    try:
        if not tag_name:
            return {
                'statusCode': 400,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'Tag name is required'})
            }
        
        # URL decode the tag name
        tag_name = urllib.parse.unquote(tag_name)
        
        now = datetime.now(timezone.utc).isoformat()
        quotes_updated = 0
        
        # First get all quote mappings for this tag
        mappings_response = table.query(
            IndexName='TagQuoteIndex',
            KeyConditionExpression=Key('PK').eq(f'TAG#{tag_name}')
        )
        
        # Update each quote to remove this tag from its tags array
        for mapping in mappings_response['Items']:
            if mapping.get('type') == 'tag_quote_mapping':
                quote_id = mapping.get('quote_id')
                if quote_id:
                    # Get the quote details
                    quote_response = table.get_item(
                        Key={'PK': f'QUOTE#{quote_id}', 'SK': f'QUOTE#{quote_id}'}
                    )
                    
                    if 'Item' in quote_response:
                        quote = quote_response['Item']
                        tags = quote.get('tags', [])
                        
                        # Remove the tag from the tags list
                        if tag_name in tags:
                            new_tags = [tag for tag in tags if tag != tag_name]
                            
                            # Update the quote with new tags
                            table.update_item(
                                Key={'PK': f'QUOTE#{quote_id}', 'SK': f'QUOTE#{quote_id}'},
                                UpdateExpression='SET tags = :tags, updated_at = :updated_at',
                                ExpressionAttributeValues={
                                    ':tags': new_tags,
                                    ':updated_at': now
                                }
                            )
                            quotes_updated += 1
        
        # Delete tag and all mappings in transaction
        transact_items = [
            {
                'Delete': {
                    'TableName': table.name,
                    'Key': {'PK': f'TAG#{tag_name}', 'SK': f'TAG#{tag_name}'}
                }
            }
        ]
        
        # Add mapping deletions
        for item in mappings_response['Items']:
            if item.get('type') == 'tag_quote_mapping':
                transact_items.append({
                    'Delete': {
                        'TableName': table.name,
                        'Key': {'PK': item['PK'], 'SK': item['SK']}
                    }
                })
        
        # Execute transaction (may need to batch for large numbers of items)
        if len(transact_items) <= 100:  # DynamoDB transaction limit
            dynamodb.meta.client.transact_write_items(TransactItems=transact_items)
        else:
            # Handle large transactions by batching
            for i in range(0, len(transact_items), 100):
                batch = transact_items[i:i+100]
                dynamodb.meta.client.transact_write_items(TransactItems=batch)
        
        return {
            'statusCode': 200,
            'headers': CORS_HEADERS,
            'body': json.dumps({
                'message': 'Tag deleted successfully',
                'quotes_updated': quotes_updated,
                'mappings_deleted': len(mappings_response['Items'])
            })
        }
        
    except Exception as e:
        logger.error(f"Error in admin_delete_tag: {str(e)}")
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': 'Failed to delete tag'})
        }

def admin_cleanup_unused_tags():
    """Remove tags that have no associated quotes"""
    try:
        # Get all tags
        tags_response = table.query(
            IndexName='TypeDateIndex',
            KeyConditionExpression=Key('type').eq('tag')
        )
        
        unused_tags = []
        for tag in tags_response['Items']:
            tag_name = tag.get('name')
            if tag_name and tag.get('quote_count', 0) == 0:
                unused_tags.append(tag_name)
        
        # Delete unused tags
        deleted_count = 0
        for tag_name in unused_tags:
            try:
                table.delete_item(
                    Key={'PK': f'TAG#{tag_name}', 'SK': f'TAG#{tag_name}'}
                )
                deleted_count += 1
            except Exception as e:
                logger.warning(f"Failed to delete unused tag {tag_name}: {str(e)}")
        
        return {
            'statusCode': 200,
            'headers': CORS_HEADERS,
            'body': json.dumps({
                'message': f'Cleaned up {deleted_count} unused tags',
                'deleted_tags': unused_tags[:deleted_count]
            })
        }
        
    except Exception as e:
        logger.error(f"Error in admin_cleanup_unused_tags: {str(e)}")
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': 'Failed to cleanup unused tags'})
        }

def admin_export_data(query_params):
    """Export all quotes, authors, and tags for backup purposes"""
    try:
        logger.info("Starting data export for backup")
        
        # Get export format (default: json)
        export_format = query_params.get('format', 'json').lower()
        include_metadata = query_params.get('metadata', 'true').lower() == 'true'
        
        # Get all quotes using TypeDateIndex for efficient scanning
        all_quotes = []
        last_evaluated_key = None
        
        while True:
            scan_params = {
                'IndexName': 'TypeDateIndex',
                'FilterExpression': Attr('type').eq('quote'),
                'ProjectionExpression': 'id, quote, author, tags, created_at, updated_at, created_by'
            }
            
            if last_evaluated_key:
                scan_params['ExclusiveStartKey'] = last_evaluated_key
            
            response = table.scan(**scan_params)
            
            for item in response.get('Items', []):
                quote_data = {
                    'id': item.get('id', ''),
                    'quote': item.get('quote', ''),
                    'author': item.get('author', ''),
                    'tags': item.get('tags', []),
                    'created_at': item.get('created_at', ''),
                    'updated_at': item.get('updated_at', '')
                }
                
                if include_metadata and item.get('created_by'):
                    quote_data['created_by'] = item.get('created_by')
                    
                all_quotes.append(quote_data)
            
            last_evaluated_key = response.get('LastEvaluatedKey')
            if not last_evaluated_key:
                break
        
        # Extract unique authors and tags
        all_authors = sorted(list(set(quote['author'] for quote in all_quotes if quote['author'])))
        all_tags = sorted(list(set(tag for quote in all_quotes for tag in quote['tags'] if tag)))
        
        # Build export data
        export_data = {
            'export_metadata': {
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'total_quotes': len(all_quotes),
                'total_authors': len(all_authors),
                'total_tags': len(all_tags),
                'format': export_format,
                'version': '2.0'
            },
            'quotes': all_quotes,
            'authors': all_authors,
            'tags': all_tags
        }
        
        # Handle different export formats
        if export_format == 'csv':
            # For CSV, we'll return a structured format that can be easily processed
            return {
                'statusCode': 200,
                'headers': {
                    **CORS_HEADERS,
                    'Content-Type': 'application/json',
                    'Content-Disposition': 'attachment; filename="quotes_export.json"'
                },
                'body': json.dumps({
                    'message': 'CSV export format available - use format=json for full structured export',
                    'csv_instructions': 'Process the quotes array to generate CSV format as needed',
                    'data': export_data
                }, cls=DecimalEncoder, indent=2)
            }
        else:
            # Default JSON format
            return {
                'statusCode': 200,
                'headers': {
                    **CORS_HEADERS,
                    'Content-Type': 'application/json',
                    'Content-Disposition': 'attachment; filename="quotes_backup.json"'
                },
                'body': json.dumps(export_data, cls=DecimalEncoder, indent=2)
            }
            
    except Exception as e:
        logger.error(f"Error in admin_export_data: {str(e)}")
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': 'Failed to export data'})
        }

def admin_search_quotes(query_params):
    """Search quotes by text in quote content, author, or tags"""
    try:
        search_query = query_params.get('q', '').strip()
        if not search_query:
            return {
                'statusCode': 400,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'Search query (q) parameter is required'})
            }
        
        logger.info(f"Admin searching quotes for: '{search_query}'")
        
        # Pagination parameters
        limit = int(query_params.get('limit', '100'))
        limit = min(limit, 1000)  # Cap at 1000 for performance
        
        # Sort parameters
        sort_by = query_params.get('sort_by', 'relevance')  # relevance, created_at, updated_at, quote, author
        sort_order = query_params.get('sort_order', 'desc')  # asc or desc
        
        logger.info(f"Search sorting: sort_by={sort_by}, sort_order={sort_order}")
        
        last_key = query_params.get('last_key')
        exclusive_start_key = None
        if last_key:
            try:
                exclusive_start_key = json.loads(urllib.parse.unquote(last_key))
            except:
                logger.warning(f"Invalid last_key: {last_key}")
        
        # Convert search query to lowercase for case-insensitive search
        search_lower = search_query.lower()
        
        # Query all quotes using TypeDateIndex, then filter in Python for better control
        query_params = {
            'IndexName': 'TypeDateIndex',
            'KeyConditionExpression': Key('type').eq('quote'),
            'Limit': limit * 5,  # Query more to account for filtering
            'ScanIndexForward': False  # Newest first
        }
        
        if exclusive_start_key:
            query_params['ExclusiveStartKey'] = exclusive_start_key
        
        response = table.query(**query_params)
        
        # Additional case-insensitive filtering in Python for better matches
        matched_quotes = []
        for item in response.get('Items', []):
            quote_text = item.get('quote', '').lower()
            author_name = item.get('author', '').lower()
            tags = [tag.lower() for tag in item.get('tags', [])]
            
            # Check if search query matches quote, author, or any tag
            if (search_lower in quote_text or 
                search_lower in author_name or 
                any(search_lower in tag for tag in tags)):
                
                # Extract ID from PK if id field doesn't exist
                quote_id = item.get('id', '')
                if not quote_id and item.get('PK'):
                    quote_id = item.get('PK', '').replace('QUOTE#', '')
                
                quote_data = {
                    'id': quote_id,
                    'quote': item.get('quote', ''),
                    'author': item.get('author', ''),
                    'tags': item.get('tags', []),
                    'created_at': item.get('created_at', ''),
                    'updated_at': item.get('updated_at', '')
                }
                
                if item.get('created_by'):
                    quote_data['created_by'] = item.get('created_by')
                
                matched_quotes.append(quote_data)
                
                # Stop if we have enough results
                if len(matched_quotes) >= limit:
                    break
        
        # Sort by specified field
        logger.info(f"Sorting {len(matched_quotes)} results by {sort_by} ({sort_order})")
        if sort_by == 'relevance':
            # Sort by relevance (exact matches first, then partial matches)
            def relevance_score(quote):
                score = 0
                quote_lower = quote['quote'].lower()
                author_lower = quote['author'].lower()
                
                # Exact matches get higher scores
                if search_lower == quote_lower or search_lower == author_lower:
                    score += 100
                elif search_lower in quote_lower or search_lower in author_lower:
                    score += 50
                
                # Tag matches
                for tag in quote.get('tags', []):
                    if search_lower == tag.lower():
                        score += 30
                    elif search_lower in tag.lower():
                        score += 15
                
                return score
            
            matched_quotes.sort(key=relevance_score, reverse=True)
        else:
            # Sort by other fields
            reverse_order = (sort_order == 'desc')
            
            if sort_by == 'quote':
                matched_quotes.sort(key=lambda x: x.get('quote', '').lower(), reverse=reverse_order)
            elif sort_by == 'author':
                matched_quotes.sort(key=lambda x: x.get('author', '').lower(), reverse=reverse_order)
            elif sort_by == 'created_at':
                matched_quotes.sort(key=lambda x: x.get('created_at', ''), reverse=reverse_order)
            elif sort_by == 'updated_at':
                # Debug: log first few updated_at values before sorting
                if matched_quotes:
                    sample_dates = [q.get('updated_at', 'MISSING') for q in matched_quotes[:5]]
                    logger.info(f"Sample updated_at values before sort: {sample_dates}")
                matched_quotes.sort(key=lambda x: x.get('updated_at', ''), reverse=reverse_order)
                # Debug: log first few updated_at values after sorting
                if matched_quotes:
                    sample_dates = [q.get('updated_at', 'MISSING') for q in matched_quotes[:5]]
                    logger.info(f"Sample updated_at values after sort (reverse={reverse_order}): {sample_dates}")
            else:
                # Default to created_at if invalid sort field
                matched_quotes.sort(key=lambda x: x.get('created_at', ''), reverse=reverse_order)
        
        # Prepare pagination info
        next_key = None
        if response.get('LastEvaluatedKey') and len(matched_quotes) >= limit:
            next_key = urllib.parse.quote(json.dumps(response['LastEvaluatedKey']))
        
        result = {
            'quotes': matched_quotes[:limit],  # Ensure we don't exceed limit
            'total_found': len(matched_quotes),
            'search_query': search_query,
            'has_more': next_key is not None
        }
        
        if next_key:
            result['last_evaluated_key'] = next_key
        
        logger.info(f"✅ Found {len(matched_quotes)} quotes matching '{search_query}'")
        
        return {
            'statusCode': 200,
            'headers': CORS_HEADERS,
            'body': json.dumps(result, cls=DecimalEncoder)
        }
        
    except Exception as e:
        logger.error(f"Error in admin_search_quotes: {str(e)}")
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': 'Failed to search quotes'})
        }

def admin_get_quotes_by_author(author, query_params):
    """Get quotes by a specific author with pagination - admin version"""
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
        limit = min(limit, 100)  # Cap at 100
        
        last_key = query_params.get('last_key')
        exclusive_start_key = None
        if last_key:
            try:
                exclusive_start_key = json.loads(urllib.parse.unquote(last_key))
            except:
                logger.warning(f"Invalid last_key: {last_key}")
        
        # Query using AuthorDateIndex
        query_params_db = {
            'IndexName': 'AuthorDateIndex',
            'KeyConditionExpression': Key('author_normalized').eq(author_normalized),
            'Limit': limit,
            'ScanIndexForward': False  # Newest first
        }
        
        if exclusive_start_key:
            query_params_db['ExclusiveStartKey'] = exclusive_start_key
            
        response = table.query(**query_params_db)
        
        quotes = [format_quote_for_admin(item) for item in response['Items']]
        
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
        logger.error(f"Error in admin_get_quotes_by_author: {str(e)}")
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': 'Failed to retrieve quotes by author'})
        }

def admin_get_quotes_by_tag(tag, query_params):
    """Get quotes by a specific tag with pagination - admin version"""
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
        limit = min(limit, 100)  # Cap at 100
        
        last_key = query_params.get('last_key')
        exclusive_start_key = None
        if last_key:
            try:
                exclusive_start_key = json.loads(urllib.parse.unquote(last_key))
            except:
                logger.warning(f"Invalid last_key: {last_key}")
        
        # Query using TagQuoteIndex
        query_params_db = {
            'IndexName': 'TagQuoteIndex',
            'KeyConditionExpression': Key('PK').eq(f'TAG#{tag}'),
            'Limit': limit,
            'ScanIndexForward': False  # Newest first
        }
        
        if exclusive_start_key:
            query_params_db['ExclusiveStartKey'] = exclusive_start_key
        
        response = table.query(**query_params_db)
        
        # Get the actual quote details for each tag mapping
        quotes = []
        for item in response['Items']:
            if item.get('PK', '').startswith('QUOTE#'):
                quote_details = get_quote_details(item['PK'])
                if quote_details:
                    quotes.append(format_quote_for_admin(quote_details))
        
        result = {
            'quotes': quotes,
            'count': len(quotes),
            'tag': tag
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
        logger.error(f"Error in admin_get_quotes_by_tag: {str(e)}")
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': 'Failed to retrieve quotes by tag'})
        }

def get_quote_details(quote_pk):
    """Get full quote details from primary key"""
    try:
        response = table.get_item(Key={'PK': quote_pk, 'SK': quote_pk})
        return response.get('Item')
    except Exception as e:
        logger.error(f"Error getting quote details: {str(e)}")
        return None

def get_tag_quote_count(tag_name):
    """Get the number of quotes that use this tag"""
    try:
        # Query the TagQuoteIndex to count only tag_quote_mapping items for this tag
        response = table.query(
            IndexName='TagQuoteIndex',
            KeyConditionExpression=Key('PK').eq(f'TAG#{tag_name}'),
            FilterExpression=Attr('type').eq('tag_quote_mapping'),
            Select='COUNT'
        )
        
        return response.get('Count', 0)
        
    except Exception as e:
        logger.error(f"Error getting tag quote count for {tag_name}: {str(e)}")
        return 0