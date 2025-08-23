import json
import boto3
import os
import uuid
from datetime import datetime
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')
table_name = os.environ.get('TABLE_NAME', 'dcc-proposed-quotes')
table = dynamodb.Table(table_name)
# Main quotes table for approved quotes
quotes_table_name = 'dcc-quotes-optimized'
quotes_table = dynamodb.Table(quotes_table_name)

def decimal_default(obj):
    """Helper to convert Decimal to float for JSON serialization"""
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError

def lambda_handler(event, context):
    """
    Handle proposed quote operations:
    - POST: Create a new proposed quote
    - GET: Retrieve proposed quotes (admin only)
    """
    
    # Extract HTTP method and path
    http_method = event.get('httpMethod', '')
    path = event.get('path', '')
    
    # Parse the JWT claims from the authorizer
    claims = event.get('requestContext', {}).get('authorizer', {}).get('claims', {})
    user_email = claims.get('email', 'unknown')
    user_name = claims.get('name', user_email)
    cognito_groups = claims.get('cognito:groups', '')
    is_admin = 'Admins' in cognito_groups if cognito_groups else False
    
    # Handle CORS preflight
    if http_method == 'OPTIONS':
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
                'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
                'Access-Control-Allow-Credentials': 'true'
            },
            'body': ''
        }
    
    try:
        if http_method == 'POST' and path == '/propose-quote':
            # Create a new proposed quote
            body = json.loads(event.get('body', '{}'))
            
            # Validate required fields
            quote_text = body.get('quote', '').strip()
            author = body.get('author', '').strip()
            
            if not quote_text:
                return {
                    'statusCode': 400,
                    'headers': {
                        'Access-Control-Allow-Origin': '*',
                        'Content-Type': 'application/json'
                    },
                    'body': json.dumps({'error': 'Quote text is required'})
                }
            
            if not author:
                return {
                    'statusCode': 400,
                    'headers': {
                        'Access-Control-Allow-Origin': '*',
                        'Content-Type': 'application/json'
                    },
                    'body': json.dumps({'error': 'Author is required'})
                }
            
            # Create the proposed quote item
            quote_id = str(uuid.uuid4())
            timestamp = datetime.utcnow().isoformat() + 'Z'
            
            item = {
                'id': quote_id,
                'quote': quote_text,
                'author': author,
                'proposer_email': user_email,
                'proposer_name': user_name,
                'status': 'pending',  # pending, approved, rejected
                'created_date': timestamp,
                'updated_date': timestamp
            }
            
            # Optional fields
            if 'tags' in body and body['tags']:
                item['tags'] = body['tags']
            
            if 'notes' in body and body['notes']:
                item['notes'] = body['notes'].strip()
            
            # Save to DynamoDB
            table.put_item(Item=item)
            
            return {
                'statusCode': 201,
                'headers': {
                    'Access-Control-Allow-Origin': '*',
                    'Content-Type': 'application/json'
                },
                'body': json.dumps({
                    'message': 'Quote proposed successfully',
                    'id': quote_id,
                    'status': 'pending'
                })
            }
        
        elif http_method == 'PUT' and path.startswith('/proposed-quotes/'):
            # Admin approve/reject proposed quote
            if not is_admin:
                return {
                    'statusCode': 403,
                    'headers': {
                        'Access-Control-Allow-Origin': '*',
                        'Content-Type': 'application/json'
                    },
                    'body': json.dumps({'error': 'Admin access required'})
                }
            
            # Extract quote ID from path
            quote_id = path.split('/')[-1]
            body = json.loads(event.get('body', '{}'))
            action = body.get('action')  # 'approve' or 'reject'
            feedback = body.get('feedback', '')
            
            if action not in ['approve', 'reject']:
                return {
                    'statusCode': 400,
                    'headers': {
                        'Access-Control-Allow-Origin': '*',
                        'Content-Type': 'application/json'
                    },
                    'body': json.dumps({'error': 'Action must be approve or reject'})
                }
            
            try:
                # Get the proposed quote
                response = table.get_item(Key={'id': quote_id})
                if 'Item' not in response:
                    return {
                        'statusCode': 404,
                        'headers': {
                            'Access-Control-Allow-Origin': '*',
                            'Content-Type': 'application/json'
                        },
                        'body': json.dumps({'error': 'Proposed quote not found'})
                    }
                
                proposed_quote = response['Item']
                timestamp = datetime.utcnow().isoformat() + 'Z'
                
                # Update proposed quote status
                update_expression = 'SET #status = :status, updated_date = :updated_date, reviewed_by = :reviewed_by'
                expression_values = {
                    ':status': action + 'd',  # 'approved' or 'rejected'
                    ':updated_date': timestamp,
                    ':reviewed_by': user_email
                }
                expression_names = {'#status': 'status'}
                
                if feedback:
                    update_expression += ', admin_feedback = :feedback'
                    expression_values[':feedback'] = feedback
                
                # Update the proposed quote
                table.update_item(
                    Key={'id': quote_id},
                    UpdateExpression=update_expression,
                    ExpressionAttributeValues=expression_values,
                    ExpressionAttributeNames=expression_names
                )
                
                # If approved, add to main quotes table
                if action == 'approve':
                    # Create new quote in main table
                    new_quote_id = str(uuid.uuid4())
                    
                    quote_item = {
                        'PK': f'QUOTE#{new_quote_id}',
                        'SK': f'QUOTE#{new_quote_id}',
                        'id': new_quote_id,
                        'type': 'quote',
                        'quote': proposed_quote['quote'],
                        'author': proposed_quote['author'],
                        'quote_normalized': proposed_quote['quote'].lower(),
                        'author_normalized': proposed_quote['author'].lower(),
                        'created_at': timestamp,
                        'updated_at': timestamp,
                        'created_by': user_email,  # Admin who approved it
                        'proposed_by': proposed_quote['proposer_email'],
                        'approved_by': user_email,
                        'original_proposal_id': quote_id
                    }
                    
                    # Add tags if they exist
                    if 'tags' in proposed_quote and proposed_quote['tags']:
                        quote_item['tags'] = proposed_quote['tags']
                        
                        # Also create tag entries for each tag (following existing pattern)
                        for tag in proposed_quote['tags']:
                            quotes_table.put_item(Item={
                                'PK': f'TAG#{tag}',
                                'SK': f'QUOTE#{new_quote_id}',
                                'id': f'tag#{tag}#{new_quote_id}',
                                'type': 'tag_mapping',
                                'tag': tag,
                                'quote_id': new_quote_id,
                                'created_at': timestamp
                            })
                    
                    # Save to main quotes table
                    quotes_table.put_item(Item=quote_item)
                
                return {
                    'statusCode': 200,
                    'headers': {
                        'Access-Control-Allow-Origin': '*',
                        'Content-Type': 'application/json'
                    },
                    'body': json.dumps({
                        'message': f'Quote {action}d successfully',
                        'status': action + 'd',
                        'new_quote_id': new_quote_id if action == 'approve' else None
                    })
                }
                
            except Exception as e:
                print(f"Error updating proposed quote: {str(e)}")
                return {
                    'statusCode': 500,
                    'headers': {
                        'Access-Control-Allow-Origin': '*',
                        'Content-Type': 'application/json'
                    },
                    'body': json.dumps({'error': f'Failed to {action} quote: {str(e)}'})
                }
        
        elif http_method == 'DELETE' and path.startswith('/proposed-quotes/'):
            # Admin delete proposed quote
            if not is_admin:
                return {
                    'statusCode': 403,
                    'headers': {
                        'Access-Control-Allow-Origin': '*',
                        'Content-Type': 'application/json'
                    },
                    'body': json.dumps({'error': 'Admin access required'})
                }
            
            # Extract quote ID from path
            quote_id = path.split('/')[-1]
            
            try:
                # Delete the proposed quote
                response = table.delete_item(
                    Key={'id': quote_id},
                    ReturnValues='ALL_OLD'
                )
                
                if 'Attributes' not in response:
                    return {
                        'statusCode': 404,
                        'headers': {
                            'Access-Control-Allow-Origin': '*',
                            'Content-Type': 'application/json'
                        },
                        'body': json.dumps({'error': 'Proposed quote not found'})
                    }
                
                return {
                    'statusCode': 200,
                    'headers': {
                        'Access-Control-Allow-Origin': '*',
                        'Content-Type': 'application/json'
                    },
                    'body': json.dumps({
                        'message': 'Quote deleted successfully',
                        'deleted_id': quote_id
                    })
                }
                
            except Exception as e:
                print(f"Error deleting proposed quote: {str(e)}")
                return {
                    'statusCode': 500,
                    'headers': {
                        'Access-Control-Allow-Origin': '*',
                        'Content-Type': 'application/json'
                    },
                    'body': json.dumps({'error': f'Failed to delete quote: {str(e)}'})
                }
        
        elif http_method == 'GET' and path == '/proposed-quotes':
            # Get proposed quotes
            # Regular users see only their own quotes
            # Admins see all quotes
            
            if is_admin:
                # Admin: get all proposed quotes (pending, approved, rejected)
                quotes = []
                
                # Get pending quotes first
                response = table.query(
                    IndexName='StatusDateIndex',
                    KeyConditionExpression='#status = :status',
                    ExpressionAttributeNames={
                        '#status': 'status'
                    },
                    ExpressionAttributeValues={
                        ':status': 'pending'
                    },
                    ScanIndexForward=False  # Most recent first
                )
                quotes.extend(response['Items'])
                
                # Get approved quotes
                response = table.query(
                    IndexName='StatusDateIndex',
                    KeyConditionExpression='#status = :status',
                    ExpressionAttributeNames={
                        '#status': 'status'
                    },
                    ExpressionAttributeValues={
                        ':status': 'approved'
                    },
                    ScanIndexForward=False,  # Most recent first
                    Limit=50  # Limit recent approved quotes
                )
                quotes.extend(response['Items'])
                
                # Get rejected quotes
                response = table.query(
                    IndexName='StatusDateIndex',
                    KeyConditionExpression='#status = :status',
                    ExpressionAttributeNames={
                        '#status': 'status'
                    },
                    ExpressionAttributeValues={
                        ':status': 'rejected'
                    },
                    ScanIndexForward=False,  # Most recent first
                    Limit=50  # Limit recent rejected quotes
                )
                quotes.extend(response['Items'])
                
                # Sort all quotes by updated_date descending
                quotes.sort(key=lambda x: x.get('updated_date', x.get('created_date', '')), reverse=True)
                
            else:
                # Regular user: get only their quotes
                response = table.query(
                    IndexName='ProposerEmailIndex',
                    KeyConditionExpression='proposer_email = :email',
                    ExpressionAttributeValues={
                        ':email': user_email
                    },
                    ScanIndexForward=False  # Most recent first
                )
                quotes = response['Items']
            
            return {
                'statusCode': 200,
                'headers': {
                    'Access-Control-Allow-Origin': '*',
                    'Content-Type': 'application/json'
                },
                'body': json.dumps({
                    'quotes': quotes,
                    'count': len(quotes),
                    'is_admin': is_admin
                }, default=decimal_default)
            }
        
        else:
            return {
                'statusCode': 404,
                'headers': {
                    'Access-Control-Allow-Origin': '*',
                    'Content-Type': 'application/json'
                },
                'body': json.dumps({'error': 'Not found'})
            }
    
    except json.JSONDecodeError:
        return {
            'statusCode': 400,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Content-Type': 'application/json'
            },
            'body': json.dumps({'error': 'Invalid JSON in request body'})
        }
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Content-Type': 'application/json'
            },
            'body': json.dumps({'error': 'Internal server error', 'details': str(e)})
        }