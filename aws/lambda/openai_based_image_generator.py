import json
import os
import requests
import logging
from datetime import datetime
import boto3
import uuid
from urllib.parse import urlparse
from openai import OpenAI

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# OpenAI configuration
OPENAI_API_KEY = os.environ.get('OPENAI_API_KEY')
OPENAI_BASE_URL = 'https://api.openai.com/v1'
QUOTE_IMAGES_BUCKET = os.environ.get('QUOTE_IMAGES_BUCKET')

# AWS services
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('dcc-quotes-optimized')
s3_client = boto3.client('s3')

def lambda_handler(event, context):
    """
    AWS Lambda handler that processes image generation jobs from SQS.
    This runs asynchronously with a longer timeout (5 minutes).
    """
    
    for record in event['Records']:
        try:
            # Parse SQS message
            message = json.loads(record['body'])
            job_id = message['job_id']
            quote = message['quote']
            author = message['author']
            tags = message.get('tags', '')
            quote_id = message.get('quote_id')
            
            logger.info(f"Processing image generation job {job_id}")
            
            # Update job status to processing
            update_job_status(job_id, 'processing')
            
            # Generate the sophisticated prompt
            prompt = build_image_prompt(quote, author, tags)
            
            # Call OpenAI DALL-E 3 API to get temporary URL
            temp_image_url = generate_image_with_openai(prompt)
            
            logger.info(f"Successfully generated temporary image for job {job_id}: {temp_image_url}")
            
            # Download image from OpenAI and upload to S3
            permanent_image_url = download_and_store_image(temp_image_url, quote_id or job_id)
            
            logger.info(f"Stored permanent image for job {job_id}: {permanent_image_url}")
            
            # Update quote with permanent S3 image URL if quote_id provided
            if quote_id:
                try:
                    table.update_item(
                        Key={'PK': f'QUOTE#{quote_id}', 'SK': f'QUOTE#{quote_id}'},
                        UpdateExpression='SET image_url = :url, updated_at = :now',
                        ExpressionAttributeValues={
                            ':url': permanent_image_url,
                            ':now': datetime.utcnow().isoformat()
                        }
                    )
                    logger.info(f"Updated quote {quote_id} with permanent image URL")
                except Exception as e:
                    logger.error(f"Failed to update quote with image URL: {str(e)}")
            
            # Update job status to completed
            update_job_status(job_id, 'completed', image_url=permanent_image_url)
            
        except Exception as e:
            logger.error(f"Error processing job {job_id}: {str(e)}")
            update_job_status(job_id, 'failed', error=str(e))
    
    return {
        'statusCode': 200,
        'body': json.dumps('Batch processed successfully')
    }

def download_and_store_image(temp_url, identifier):
    """
    Download image from OpenAI temporary URL and store permanently in S3.
    Returns the permanent S3 URL.
    """
    try:
        if not QUOTE_IMAGES_BUCKET:
            raise ValueError('QUOTE_IMAGES_BUCKET environment variable not set')
        
        # Generate a unique filename
        file_extension = 'png'  # DALL-E generates PNG images
        filename = f"{identifier}-{uuid.uuid4().hex[:8]}.{file_extension}"
        
        logger.info(f"Downloading image from OpenAI: {temp_url[:100]}...")
        
        # Download the image from OpenAI
        response = requests.get(temp_url, timeout=60)
        response.raise_for_status()
        
        # Upload to S3
        logger.info(f"Uploading image to S3: {filename}")
        s3_client.put_object(
            Bucket=QUOTE_IMAGES_BUCKET,
            Key=filename,
            Body=response.content,
            ContentType='image/png',
            CacheControl='max-age=31536000',  # 1 year cache
        )
        
        # Generate the permanent S3 URL
        permanent_url = f"https://{QUOTE_IMAGES_BUCKET}.s3.amazonaws.com/{filename}"
        
        logger.info(f"Successfully stored image at: {permanent_url}")
        return permanent_url
        
    except Exception as e:
        logger.error(f"Failed to download and store image: {str(e)}")
        # Return the temporary URL as fallback
        logger.warning("Falling back to temporary OpenAI URL")
        return temp_url

def update_job_status(job_id, status, image_url=None, error=None):
    """Update job status in DynamoDB."""
    try:
        update_expr = 'SET #status = :status, updated_at = :now'
        expr_values = {
            ':status': status,
            ':now': datetime.utcnow().isoformat()
        }
        
        if image_url:
            update_expr += ', image_url = :url'
            expr_values[':url'] = image_url
        
        if error:
            update_expr += ', error_message = :error'
            expr_values[':error'] = error
        
        table.update_item(
            Key={'PK': f'JOB#{job_id}', 'SK': 'METADATA'},
            UpdateExpression=update_expr,
            ExpressionAttributeNames={'#status': 'status'},
            ExpressionAttributeValues=expr_values
        )
        logger.info(f"Updated job {job_id} status to {status}")
    except Exception as e:
        logger.error(f"Failed to update job status: {str(e)}")

def build_image_prompt(quote, author, tags=None):
    """
    Builds a sophisticated prompt for consistent, professional quote imagery.
    """
    
    # Base style guidelines for consistency
    base_style = f"""Create a sophisticated, inspirational image that visually represents the essence of this quote.

Style Guidelines:
- Professional, high-quality digital art aesthetic
- Warm, inviting color palette with subtle gradients (soft blues, golds, warm grays)
- Soft, diffused lighting that creates depth and atmosphere
- Clean, minimalist composition with balanced visual elements
- Slightly abstract or symbolic rather than literal interpretation
- Suitable for displaying alongside inspirational text overlay
- Elegant, timeless feel that complements written wisdom
- Avoid text, words, or letters in the image

Visual Elements:
- Symbolic representations of the quote's core message
- Natural elements like soft light rays, flowing water, or serene landscapes
- Geometric patterns or flowing lines suggesting growth, progress, or wisdom
- Subtle textures that add depth without overwhelming
- Color psychology matching the quote's emotional tone
- Composition leaves space for text overlay

Quote: "{quote}"
Author: {author}"""

    # Add thematic context based on tags
    if tags and tags.strip():
        tag_list = [tag.strip() for tag in tags.split(',') if tag.strip()]
        if tag_list:
            base_style += f"\nThematic Context: {', '.join(tag_list)}"
    
    # Add author-specific context for well-known figures
    author_context = get_author_context(author)
    if author_context:
        base_style += f"\nAuthor Context: {author_context}"
    
    return base_style

def get_author_context(author):
    """
    Provides visual context based on well-known authors.
    """
    author_lower = author.lower()
    
    # Historical/philosophical figures
    if any(name in author_lower for name in ['einstein', 'newton', 'galileo']):
        return "Scientific, intellectual atmosphere with subtle cosmic or mathematical elements"
    elif any(name in author_lower for name in ['shakespeare', 'wilde', 'twain']):
        return "Literary, classical atmosphere with elegant, timeless elements"
    elif any(name in author_lower for name in ['gandhi', 'mandela', 'king']):
        return "Peaceful, dignified atmosphere with elements of hope and unity"
    elif any(name in author_lower for name in ['jobs', 'gates', 'bezos']):
        return "Modern, innovative atmosphere with clean, technological elegance"
    elif any(name in author_lower for name in ['buddha', 'confucius', 'lao']):
        return "Serene, meditative atmosphere with natural, zen-like elements"
    elif any(name in author_lower for name in ['da vinci', 'leonardo']):
        return "Renaissance artistry with elements of innovation, flight, and creative genius"
    
    return None

def generate_image_with_openai(prompt):
    """
    Calls OpenAI API to generate an image - uses official OpenAI client like the working example.
    """
    
    if not OPENAI_API_KEY:
        raise ValueError('OpenAI API key not configured')
    
    # Initialize OpenAI client exactly like the working example
    client = OpenAI(api_key=OPENAI_API_KEY)
    
    logger.info(f"Calling OpenAI API with prompt: {prompt[:100]}...")
    
    try:
        # Match the working example exactly
        result = client.images.generate(
            model="gpt-image-1",
            prompt=prompt,
            size="1024x1024"
        )
        
        # Get the image URL exactly like the working example
        image_url = result.data[0].url
        
        logger.info(f"OpenAI API successful, image URL: {image_url}")
        return image_url
        
    except Exception as e:
        logger.error(f"OpenAI API request failed: {str(e)}")
        raise Exception(f"OpenAI API request failed: {str(e)}")