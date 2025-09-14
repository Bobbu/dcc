import json
import boto3
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# DynamoDB configuration
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('dcc-quotes-optimized')

def lambda_handler(event, context):
    """
    AWS Lambda handler to check the status of an image generation job.
    """
    
    # Handle CORS preflight
    if event.get('httpMethod') == 'OPTIONS':
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Api-Key'
            },
            'body': ''
        }
    
    try:
        # Get job_id from path parameters
        job_id = event.get('pathParameters', {}).get('jobId')
        
        if not job_id:
            raise ValueError('Job ID is required')
        
        logger.info(f"Checking status for job {job_id}")
        
        # Get job status from DynamoDB
        response = table.get_item(Key={'PK': f'JOB#{job_id}', 'SK': 'METADATA'})
        
        if 'Item' not in response:
            return {
                'statusCode': 404,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': 'Job not found',
                    'jobId': job_id
                })
            }
        
        job = response['Item']
        
        # Build response
        result = {
            'jobId': job_id,
            'status': job.get('status', 'unknown'),
            'createdAt': job.get('created_at'),
            'updatedAt': job.get('updated_at')
        }
        
        # Include additional fields based on status
        if job.get('status') == 'completed':
            result['imageUrl'] = job.get('image_url')
            result['quote'] = job.get('quote')
            result['author'] = job.get('author')
        elif job.get('status') == 'failed':
            result['error'] = job.get('error_message', 'Unknown error')
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,Authorization,X-Api-Key',
                'Access-Control-Allow-Methods': 'GET,OPTIONS'
            },
            'body': json.dumps(result)
        }
        
    except Exception as e:
        logger.error(f"Error checking job status: {str(e)}")
        
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Failed to check job status',
                'message': str(e)
            })
        }