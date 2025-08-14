import json
import random
import boto3
import os
from boto3.dynamodb.conditions import Key, Attr

# Initialize DynamoDB
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ.get('QUOTES_TABLE', 'dcc-quotes'))

def get_quotes_by_tags(tags):
    """
    Get quotes that contain any of the specified tags.
    Uses DynamoDB scan with filter expression.
    """
    try:
        if not tags or 'All' in tags:
            # Get all quotes
            response = table.scan()
        else:
            # Create filter expression for any tag match
            filter_expressions = []
            for tag in tags:
                filter_expressions.append(Attr('tags').contains(tag))
            
            # Combine with OR logic
            filter_expression = filter_expressions[0]
            for expr in filter_expressions[1:]:
                filter_expression = filter_expression | expr
                
            response = table.scan(FilterExpression=filter_expression)
        
        return response.get('Items', [])
        
    except Exception as e:
        print(f"Error querying DynamoDB: {e}")
        return []

def parse_tags_from_query(event):
    """
    Parse tags from query string parameters.
    Supports: ?tags=Motivation,Business or ?tags=All
    """
    query_params = event.get('queryStringParameters') or {}
    tags_param = query_params.get('tags', 'All')
    
    if tags_param == 'All':
        return ['All']
    
    # Split by comma and clean up
    tags = [tag.strip() for tag in tags_param.split(',') if tag.strip()]
    return tags if tags else ['All']

def get_tags_metadata():
    """Get all available tags from metadata record"""
    try:
        response = table.get_item(Key={'id': 'TAGS_METADATA'})
        if 'Item' in response:
            return response['Item']['tags']
        return []
    except Exception as e:
        print(f"Error getting tags metadata: {e}")
        return []

def handle_tags_request():
    """Handle GET /tags request"""
    try:
        tags = get_tags_metadata()
        
        # Ensure 'All' is first in the list
        if 'All' not in tags:
            tags = ['All'] + tags
        elif tags.index('All') != 0:
            tags.remove('All')
            tags = ['All'] + tags
        
        response_body = {
            "tags": tags,
            "count": len(tags)
        }
        
        return {
            "statusCode": 200,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Headers": "Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token",
                "Access-Control-Allow-Methods": "GET,OPTIONS"
            },
            "body": json.dumps(response_body)
        }
        
    except Exception as e:
        print(f"Error handling tags request: {e}")
        
        error_response = {
            "error": "Internal server error",
            "message": "Failed to retrieve tags"
        }
        
        return {
            "statusCode": 500,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*"
            },
            "body": json.dumps(error_response)
        }

def lambda_handler(event, context):
    """
    AWS Lambda handler for the quote endpoint and tags endpoint.
    
    Routes:
    - GET /quote: Returns a random quote with its author, filtered by tags if specified.
    - GET /tags: Returns all available tags.
    
    Query parameters for /quote:
    - tags: Comma-separated list of tags (e.g., "Motivation,Business") or "All"
    """
    try:
        # Route based on path
        path = event.get('path', '/quote')
        
        if path == '/tags':
            return handle_tags_request()
        
        # Default to quote handling
        # Parse tags from query parameters
        requested_tags = parse_tags_from_query(event)
        
        # Get quotes matching the tags
        quotes = get_quotes_by_tags(requested_tags)
        
        if not quotes:
            # Fallback to all quotes if no matches found
            quotes = get_quotes_by_tags(['All'])
        
        if not quotes:
            raise Exception("No quotes found in database")
        
        # Select a random quote
        selected_quote = random.choice(quotes)
        
        # Prepare the response
        response_body = {
            "quote": selected_quote["quote"],
            "author": selected_quote["author"],
            "tags": selected_quote.get("tags", []),
            "id": selected_quote["id"]
        }
        
        return {
            "statusCode": 200,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Headers": "Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token",
                "Access-Control-Allow-Methods": "GET,OPTIONS"
            },
            "body": json.dumps(response_body)
        }
        
    except Exception as e:
        # Handle any unexpected errors
        print(f"Lambda error: {e}")
        
        error_response = {
            "error": "Internal server error",
            "message": "Failed to retrieve quote"
        }
        
        return {
            "statusCode": 500,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*"
            },
            "body": json.dumps(error_response)
        }