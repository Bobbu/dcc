import json
import boto3
import os
import uuid
from datetime import datetime
from boto3.dynamodb.conditions import Key, Attr

# Initialize DynamoDB
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ.get('QUOTES_TABLE', 'dcc-quotes'))

def get_user_claims(event):
    """Extract user claims from Cognito JWT token"""
    claims = event.get('requestContext', {}).get('authorizer', {}).get('claims', {})
    
    # Check if user is in admin group
    groups = claims.get('cognito:groups', '')
    is_admin = 'Admins' in groups if groups else False
    
    return {
        'username': claims.get('cognito:username', 'unknown'),
        'email': claims.get('email', ''),
        'is_admin': is_admin,
        'groups': groups
    }

def create_response(status_code, body, headers=None):
    """Create standardized API response"""
    default_headers = {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token",
        "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS"
    }
    
    if headers:
        default_headers.update(headers)
    
    return {
        "statusCode": status_code,
        "headers": default_headers,
        "body": json.dumps(body) if isinstance(body, (dict, list)) else body
    }

def update_tags_metadata(new_tags):
    """Update the tags metadata record with new tags"""
    try:
        metadata_id = "TAGS_METADATA"
        timestamp = datetime.utcnow().isoformat() + 'Z'
        
        # Get current tags metadata
        try:
            response = table.get_item(Key={'id': metadata_id})
            current_tags = set(response.get('Item', {}).get('tags', []))
        except:
            current_tags = set()
        
        # Merge in new tags
        if new_tags:
            current_tags.update(new_tags)
        
        # Update metadata record
        table.put_item(Item={
            'id': metadata_id,
            'tags': sorted(list(current_tags)),  # Keep sorted for consistency
            'updated_at': timestamp
        })
        
        print(f"✅ Updated tags metadata: {sorted(list(current_tags))}")
        
    except Exception as e:
        print(f"❌ Error updating tags metadata: {e}")
        # Don't fail the main operation if metadata update fails

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

def validate_quote_data(data):
    """Validate quote data structure"""
    required_fields = ['quote', 'author']
    optional_fields = ['tags']
    
    errors = []
    
    # Check required fields
    for field in required_fields:
        if field not in data or not data[field] or not data[field].strip():
            errors.append(f"'{field}' is required and cannot be empty")
    
    # Validate tags if provided
    if 'tags' in data:
        if not isinstance(data['tags'], list):
            errors.append("'tags' must be an array")
        elif not all(isinstance(tag, str) and tag.strip() for tag in data['tags']):
            errors.append("All tags must be non-empty strings")
    
    return errors

def handle_create_quote(event, user_claims):
    """Handle POST /admin/quotes"""
    if not user_claims['is_admin']:
        return create_response(403, {"error": "Forbidden", "message": "Admin access required"})
    
    try:
        # Parse request body
        body = json.loads(event.get('body', '{}'))
        
        # Validate input
        validation_errors = validate_quote_data(body)
        if validation_errors:
            return create_response(400, {
                "error": "Validation failed",
                "details": validation_errors
            })
        
        # Create new quote
        quote_id = str(uuid.uuid4())
        timestamp = datetime.utcnow().isoformat() + 'Z'
        
        quote_item = {
            'id': quote_id,
            'quote': body['quote'].strip(),
            'author': body['author'].strip(),
            'tags': body.get('tags', []),
            'created_at': timestamp,
            'updated_at': timestamp,
            'created_by': user_claims['username']
        }
        
        # Save to DynamoDB
        table.put_item(Item=quote_item)
        
        # Update tags metadata
        update_tags_metadata(quote_item['tags'])
        
        return create_response(201, {
            "message": "Quote created successfully",
            "quote": quote_item
        })
        
    except json.JSONDecodeError:
        return create_response(400, {"error": "Invalid JSON in request body"})
    except Exception as e:
        print(f"Error creating quote: {e}")
        return create_response(500, {"error": "Internal server error"})

def handle_update_quote(event, user_claims):
    """Handle PUT /admin/quotes/{id}"""
    if not user_claims['is_admin']:
        return create_response(403, {"error": "Forbidden", "message": "Admin access required"})
    
    try:
        # Get quote ID from path
        quote_id = event.get('pathParameters', {}).get('id')
        if not quote_id:
            return create_response(400, {"error": "Quote ID is required"})
        
        # Parse request body
        body = json.loads(event.get('body', '{}'))
        
        # Validate input
        validation_errors = validate_quote_data(body)
        if validation_errors:
            return create_response(400, {
                "error": "Validation failed",
                "details": validation_errors
            })
        
        # Check if quote exists
        try:
            response = table.get_item(Key={'id': quote_id})
            if 'Item' not in response:
                return create_response(404, {"error": "Quote not found"})
        except Exception as e:
            print(f"Error checking quote existence: {e}")
            return create_response(500, {"error": "Internal server error"})
        
        # Update quote
        timestamp = datetime.utcnow().isoformat() + 'Z'
        
        updated_item = {
            'id': quote_id,
            'quote': body['quote'].strip(),
            'author': body['author'].strip(),
            'tags': body.get('tags', []),
            'updated_at': timestamp,
            'updated_by': user_claims['username']
        }
        
        # Preserve creation metadata
        existing_quote = response['Item']
        updated_item['created_at'] = existing_quote.get('created_at', timestamp)
        updated_item['created_by'] = existing_quote.get('created_by', 'unknown')
        
        # Save updated item
        table.put_item(Item=updated_item)
        
        # Update tags metadata
        update_tags_metadata(updated_item['tags'])
        
        return create_response(200, {
            "message": "Quote updated successfully",
            "quote": updated_item
        })
        
    except json.JSONDecodeError:
        return create_response(400, {"error": "Invalid JSON in request body"})
    except Exception as e:
        print(f"Error updating quote: {e}")
        return create_response(500, {"error": "Internal server error"})

def handle_delete_quote(event, user_claims):
    """Handle DELETE /admin/quotes/{id}"""
    if not user_claims['is_admin']:
        return create_response(403, {"error": "Forbidden", "message": "Admin access required"})
    
    try:
        # Get quote ID from path
        quote_id = event.get('pathParameters', {}).get('id')
        if not quote_id:
            return create_response(400, {"error": "Quote ID is required"})
        
        # Check if quote exists
        try:
            response = table.get_item(Key={'id': quote_id})
            if 'Item' not in response:
                return create_response(404, {"error": "Quote not found"})
        except Exception as e:
            print(f"Error checking quote existence: {e}")
            return create_response(500, {"error": "Internal server error"})
        
        # Delete quote
        table.delete_item(Key={'id': quote_id})
        
        return create_response(200, {
            "message": "Quote deleted successfully",
            "deleted_quote_id": quote_id
        })
        
    except Exception as e:
        print(f"Error deleting quote: {e}")
        return create_response(500, {"error": "Internal server error"})

def handle_list_quotes(event, user_claims):
    """Handle GET /admin/quotes"""
    if not user_claims['is_admin']:
        return create_response(403, {"error": "Forbidden", "message": "Admin access required"})
    
    try:
        # Get all quotes for admin view
        response = table.scan()
        quotes = response.get('Items', [])
        
        # Sort by creation date (newest first)
        quotes.sort(key=lambda x: x.get('created_at', ''), reverse=True)
        
        return create_response(200, {
            "quotes": quotes,
            "count": len(quotes)
        })
        
    except Exception as e:
        print(f"Error listing quotes: {e}")
        return create_response(500, {"error": "Internal server error"})

def handle_get_tags(event, user_claims):
    """Handle GET /admin/tags"""
    if not user_claims['is_admin']:
        return create_response(403, {"error": "Forbidden", "message": "Admin access required"})
    
    try:
        tags = get_tags_metadata()
        return create_response(200, {
            "tags": tags,
            "count": len(tags)
        })
        
    except Exception as e:
        print(f"Error getting tags: {e}")
        return create_response(500, {"error": "Internal server error"})

def get_used_tags():
    """Get all tags that are actually used in quotes"""
    try:
        # Scan all quotes to find used tags
        response = table.scan()
        quotes = response.get('Items', [])
        
        used_tags = set()
        for quote in quotes:
            # Skip metadata records
            if quote.get('id') == 'TAGS_METADATA':
                continue
            # Add all tags from this quote
            quote_tags = quote.get('tags', [])
            if isinstance(quote_tags, list):
                used_tags.update(quote_tags)
        
        return sorted(list(used_tags))
        
    except Exception as e:
        print(f"Error getting used tags: {e}")
        return []

def handle_cleanup_unused_tags(event, user_claims):
    """Handle DELETE /admin/tags/unused"""
    if not user_claims['is_admin']:
        return create_response(403, {"error": "Forbidden", "message": "Admin access required"})
    
    try:
        # Get current tags metadata
        current_tags = set(get_tags_metadata())
        
        # Get actually used tags
        used_tags = set(get_used_tags())
        
        # Find unused tags
        unused_tags = current_tags - used_tags
        
        if not unused_tags:
            return create_response(200, {
                "message": "No unused tags found",
                "removed_tags": [],
                "remaining_tags": sorted(list(used_tags)),
                "count_removed": 0,
                "count_remaining": len(used_tags)
            })
        
        # Update metadata to only include used tags
        metadata_id = "TAGS_METADATA"
        timestamp = datetime.utcnow().isoformat() + 'Z'
        
        table.put_item(Item={
            'id': metadata_id,
            'tags': sorted(list(used_tags)),
            'updated_at': timestamp
        })
        
        print(f"✅ Cleaned up unused tags: {sorted(list(unused_tags))}")
        print(f"✅ Remaining tags: {sorted(list(used_tags))}")
        
        return create_response(200, {
            "message": f"Successfully removed {len(unused_tags)} unused tags",
            "removed_tags": sorted(list(unused_tags)),
            "remaining_tags": sorted(list(used_tags)),
            "count_removed": len(unused_tags),
            "count_remaining": len(used_tags)
        })
        
    except Exception as e:
        print(f"Error cleaning up unused tags: {e}")
        return create_response(500, {"error": "Internal server error"})

def lambda_handler(event, context):
    """
    AWS Lambda handler for admin quote management.
    Handles CRUD operations for quotes with Cognito authentication.
    """
    try:
        # Extract user claims from Cognito
        user_claims = get_user_claims(event)
        print(f"Admin request from user: {user_claims['username']}, is_admin: {user_claims['is_admin']}")
        
        # Route based on HTTP method and path
        method = event.get('httpMethod', '')
        path = event.get('path', '')
        
        if method == 'POST' and path == '/admin/quotes':
            return handle_create_quote(event, user_claims)
        elif method == 'PUT' and path.startswith('/admin/quotes/'):
            return handle_update_quote(event, user_claims)
        elif method == 'DELETE' and path.startswith('/admin/quotes/'):
            return handle_delete_quote(event, user_claims)
        elif method == 'GET' and path == '/admin/quotes':
            return handle_list_quotes(event, user_claims)
        elif method == 'GET' and path == '/admin/tags':
            return handle_get_tags(event, user_claims)
        elif method == 'DELETE' and path == '/admin/tags/unused':
            return handle_cleanup_unused_tags(event, user_claims)
        else:
            return create_response(404, {"error": "Not found"})
            
    except Exception as e:
        print(f"Lambda error: {e}")
        return create_response(500, {"error": "Internal server error"})