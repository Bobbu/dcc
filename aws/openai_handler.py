import json
import os
import boto3
import logging
import requests
from typing import List, Dict, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda function to proxy OpenAI requests for tag generation.
    This keeps the OpenAI API key secure on the server side.
    """
    logger.info(f"Received event: {json.dumps(event)}")
    
    # Parse the request body
    try:
        body = json.loads(event['body'])
        quote = body['quote']
        author = body['author']
        existing_tags = body.get('existingTags', [])
    except (json.JSONDecodeError, KeyError) as e:
        logger.error(f"Invalid request body: {e}")
        return {
            'statusCode': 400,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,X-Api-Key,Authorization',
                'Access-Control-Allow-Methods': 'OPTIONS,POST'
            },
            'body': json.dumps({'error': 'Invalid request. Must include quote, author, and optionally existingTags.'})
        }
    
    # Get OpenAI API key from environment
    openai_api_key = os.environ.get('OPENAI_API_KEY')
    if not openai_api_key:
        logger.error("OpenAI API key not configured")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,X-Api-Key,Authorization',
                'Access-Control-Allow-Methods': 'OPTIONS,POST'
            },
            'body': json.dumps({'error': 'OpenAI service not configured'})
        }
    
    # Build the prompt for tag generation
    prompt = build_tag_generation_prompt(quote, author, existing_tags)
    
    try:
        # Call OpenAI API
        response = requests.post(
            'https://api.openai.com/v1/chat/completions',
            headers={
                'Content-Type': 'application/json',
                'Authorization': f'Bearer {openai_api_key}'
            },
            json={
                'model': 'gpt-4o-mini',
                'messages': [
                    {
                        'role': 'system',
                        'content': 'You are a thoughtful tag selector. You analyze quotes deeply to understand their core meaning, then select the most relevant tags from a provided list. You ONLY choose from existing tags and NEVER create new ones. Always return a JSON array of 3-5 selected tags.'
                    },
                    {
                        'role': 'user',
                        'content': prompt
                    }
                ],
                'max_tokens': 100,
                'temperature': 0.2
            },
            timeout=30
        )
        
        if response.status_code == 200:
            openai_data = response.json()
            content = openai_data['choices'][0]['message']['content']
            
            # Parse the tags from the response
            tags = parse_tags_from_response(content)
            
            logger.info(f"Successfully generated tags for quote: {tags}")
            
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Headers': 'Content-Type,X-Api-Key,Authorization',
                    'Access-Control-Allow-Methods': 'OPTIONS,POST'
                },
                'body': json.dumps({
                    'tags': tags,
                    'usage': openai_data.get('usage', {})
                })
            }
        elif response.status_code == 429:
            # Rate limit hit
            logger.warning("OpenAI rate limit hit")
            return {
                'statusCode': 429,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Headers': 'Content-Type,X-Api-Key,Authorization',
                    'Access-Control-Allow-Methods': 'OPTIONS,POST'
                },
                'body': json.dumps({'error': 'Rate limit exceeded. Please wait a moment and try again.'})
            }
        else:
            logger.error(f"OpenAI API error: {response.status_code} - {response.text}")
            return {
                'statusCode': response.status_code,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Headers': 'Content-Type,X-Api-Key,Authorization',
                    'Access-Control-Allow-Methods': 'OPTIONS,POST'
                },
                'body': json.dumps({'error': f'OpenAI API error: {response.status_code}'})
            }
            
    except requests.exceptions.Timeout:
        logger.error("OpenAI API timeout")
        return {
            'statusCode': 504,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,X-Api-Key,Authorization',
                'Access-Control-Allow-Methods': 'OPTIONS,POST'
            },
            'body': json.dumps({'error': 'Request timeout'})
        }
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,X-Api-Key,Authorization',
                'Access-Control-Allow-Methods': 'OPTIONS,POST'
            },
            'body': json.dumps({'error': 'Internal server error'})
        }

def build_tag_generation_prompt(quote: str, author: str, existing_tags: List[str]) -> str:
    """Build the prompt for OpenAI tag generation."""
    existing_tags_text = ', '.join(existing_tags) if existing_tags else 'No existing tags provided.'
    
    return f'''Analyze this quote and select exactly 3-5 tags that best capture its core meaning. Choose ONLY from the existing tags provided.

Quote: "{quote}"
Author: {author}

Available tags to choose from: {existing_tags_text}

Instructions:
1. Think deeply about what this quote is really about (not just surface keywords)
2. Select 3-5 tags from the list above that best match the quote's meaning
3. Avoid tags that don't strongly relate to the quote's core message
4. Return only a JSON array of selected tags

Example response: ["Thinking", "Wisdom", "Reflection"]'''

def parse_tags_from_response(content: str) -> List[str]:
    """Parse tags from OpenAI's response, handling various formats."""
    try:
        # Clean up the response - remove markdown formatting if present
        clean_content = content.strip()
        clean_content = clean_content.replace('```json', '').replace('```', '').strip()
        
        # Find JSON array pattern
        import re
        json_match = re.search(r'\[(.*?)\]', clean_content, re.DOTALL)
        if json_match:
            clean_content = json_match.group(0)
        
        # Parse the JSON array
        tags = json.loads(clean_content)
        
        # Ensure we have a list of strings
        if isinstance(tags, list):
            return [str(tag).strip() for tag in tags if tag]
        else:
            logger.error(f"Unexpected response format: {content}")
            return []
            
    except (json.JSONDecodeError, Exception) as e:
        logger.error(f"Error parsing tags from response: {e}, Content: {content}")
        # Try to extract tags as fallback
        return extract_tags_fallback(content)

def extract_tags_fallback(content: str) -> List[str]:
    """Fallback method to extract tags if JSON parsing fails."""
    import re
    # Look for quoted strings
    matches = re.findall(r'"([^"]+)"', content)
    if matches:
        return matches[:5]  # Return up to 5 tags
    return []