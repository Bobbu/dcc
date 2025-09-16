import json
import os
import boto3
import logging
from datetime import datetime
import uuid

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# AWS services
sqs = boto3.client('sqs')
dynamodb = boto3.resource('dynamodb')
quotes_table_name = os.environ.get('QUOTES_TABLE_NAME', 'quote-me-quotes')
table = dynamodb.Table(quotes_table_name)

# SQS Queue URL (will be set from environment variable)
QUEUE_URL = os.environ.get('IMAGE_GENERATION_QUEUE_URL')

def lambda_handler(event, context):
    """
    AWS Lambda handler to queue image generation requests.
    Returns immediately with a job ID for status tracking.
    """
    
    # Handle CORS preflight
    if event.get('httpMethod') == 'OPTIONS':
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'POST, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Api-Key'
            },
            'body': ''
        }
    
    try:
        # Parse request body
        if not event.get('body'):
            raise ValueError('Request body is required')
        
        body = json.loads(event['body'])
        quote = body.get('quote', '').strip()
        author = body.get('author', '').strip()
        tags = body.get('tags', '').strip()
        quote_id = body.get('quote_id')
        
        if not quote:
            raise ValueError('Quote is required')
        
        if not author:
            raise ValueError('Author is required')
        
        # Generate a unique job ID
        job_id = str(uuid.uuid4())
        
        logger.info(f"Queuing image generation job {job_id} for quote by {author}")
        
        # Create job record in DynamoDB for tracking
        job_item = {
            'id': f'JOB_{job_id}',  # Use simple id field for primary key
            'job_id': job_id,
            'status': 'queued',
            'quote': quote,
            'author': author,
            'tags': tags,
            'quote_id': quote_id,
            'created_at': datetime.utcnow().isoformat(),
            'type': 'image_generation_job'
        }
        
        # Store job status in the quotes table
        table.put_item(Item=job_item)
        
        # Send message to SQS queue
        message = {
            'job_id': job_id,
            'quote': quote,
            'author': author,
            'tags': tags,
            'quote_id': quote_id
        }
        
        sqs.send_message(
            QueueUrl=QUEUE_URL,
            MessageBody=json.dumps(message),
            MessageAttributes={
                'job_id': {
                    'StringValue': job_id,
                    'DataType': 'String'
                }
            }
        )
        
        logger.info(f"Job {job_id} queued successfully")
        
        return {
            'statusCode': 202,  # Accepted
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,Authorization,X-Api-Key',
                'Access-Control-Allow-Methods': 'POST,OPTIONS'
            },
            'body': json.dumps({
                'jobId': job_id,
                'status': 'queued',
                'message': 'Image generation job queued successfully'
            })
        }
        
    except Exception as e:
        logger.error(f"Error queuing image generation: {str(e)}")
        
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Failed to queue image generation',
                'message': str(e)
            })
        }