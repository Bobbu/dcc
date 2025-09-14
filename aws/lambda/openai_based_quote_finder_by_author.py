import json
import os
import logging
import requests
from typing import List, Dict, Any

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for fetching candidate quotes from OpenAI for a specific author.
    Admin authentication required.
    """
    logger.info(f"Received event: {json.dumps(event)}")
    
    headers = {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "Content-Type,Authorization,X-Api-Key",
        "Access-Control-Allow-Methods": "GET,OPTIONS"
    }
    
    try:
        # Check for admin authentication (handled by API Gateway authorizer)
        if 'requestContext' not in event or 'authorizer' not in event['requestContext']:
            logger.error("No authorization context found")
            return {
                'statusCode': 401,
                'headers': headers,
                'body': json.dumps({'error': 'Unauthorized'})
            }
        
        # Get author and optional limit from query parameters
        query_params = event.get('queryStringParameters', {}) or {}
        author = query_params.get('author', '').strip()
        limit = int(query_params.get('limit', '5'))  # Default to 5 if not specified
        
        if not author:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': 'Author parameter is required'})
            }
            
        # Validate limit parameter
        if limit < 1 or limit > 20:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': 'Limit must be between 1 and 20'})
            }
        
        logger.info(f"Fetching candidate quotes for author: {author}")
        
        # Get OpenAI API key from environment
        openai_api_key = os.environ.get('OPENAI_API_KEY')
        if not openai_api_key:
            logger.error("OpenAI API key not configured")
            return {
                'statusCode': 500,
                'headers': headers,
                'body': json.dumps({'error': 'OpenAI service not configured'})
            }
        
        # Build the prompt for OpenAI
        system_prompt = f"""You are a knowledgeable assistant that finds authentic, verified quotes from famous authors.
When providing quotes, you must:
1. Only provide quotes that are actually attributable to the specified author
2. Include the source/reference where the quote can be found (book, speech, interview, etc.)
3. Provide context about when and where the quote was said/written
4. Format your response as a JSON array with exactly {limit} quotes"""

        user_prompt = f"""Find me {limit} authentic quotes by {author}.
For each quote, provide:
- The exact quote text
- The source (book title, speech name, interview, etc.)
- The year (if known)
- Brief context about when/where it was said
- A confidence level (high/medium/low) based on how well-documented the attribution is

Return the response as a JSON array with this structure:
[
  {{
    "quote": "The actual quote text",
    "source": "Where the quote is from",
    "year": "Year if known, or null",
    "context": "Brief context about the quote",
    "confidence": "high/medium/low"
  }}
]"""

        # Call OpenAI API using requests (similar to candidate_tags_handler.py)
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
                        'content': system_prompt
                    },
                    {
                        'role': 'user',
                        'content': user_prompt
                    }
                ],
                'max_tokens': 2000,
                'temperature': 0.3
            },
            timeout=30
        )
        
        if response.status_code == 200:
            openai_data = response.json()
            content = openai_data['choices'][0]['message']['content']
            logger.info(f"OpenAI response: {content[:500]}...")  # Log first 500 chars
            
            # Parse the response
            candidate_quotes = parse_quotes_from_response(content, limit)
            
            # Add author to each quote for convenience
            for quote in candidate_quotes:
                quote['author'] = author
            
            logger.info(f"Successfully retrieved {len(candidate_quotes)} candidate quotes")
            
            return {
                'statusCode': 200,
                'headers': headers,
                'body': json.dumps({
                    'author': author,
                    'quotes': candidate_quotes,
                    'count': len(candidate_quotes)
                })
            }
            
        elif response.status_code == 429:
            # Rate limit hit
            logger.warning("OpenAI rate limit hit")
            return {
                'statusCode': 429,
                'headers': headers,
                'body': json.dumps({'error': 'Rate limit exceeded. Please wait a moment and try again.'})
            }
        else:
            logger.error(f"OpenAI API error: {response.status_code} - {response.text}")
            return {
                'statusCode': response.status_code,
                'headers': headers,
                'body': json.dumps({'error': f'OpenAI API error: {response.status_code}'})
            }
            
    except requests.exceptions.Timeout:
        logger.error("OpenAI API timeout")
        return {
            'statusCode': 504,
            'headers': headers,
            'body': json.dumps({'error': 'Request timeout'})
        }
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({'error': 'Internal server error'})
        }


def parse_quotes_from_response(content: str, limit: int = 5) -> List[Dict[str, Any]]:
    """Parse quotes from OpenAI's response, handling various formats."""
    try:
        # Clean up the response - remove markdown formatting if present
        clean_content = content.strip()
        clean_content = clean_content.replace('```json', '').replace('```', '').strip()
        
        # Try to parse as JSON
        parsed_response = json.loads(clean_content)
        
        # Handle different response formats
        if isinstance(parsed_response, dict) and 'quotes' in parsed_response:
            candidate_quotes = parsed_response['quotes']
        elif isinstance(parsed_response, dict) and len(parsed_response) == 1:
            # Handle case where there's a single key with array value
            candidate_quotes = list(parsed_response.values())[0]
        elif isinstance(parsed_response, list):
            candidate_quotes = parsed_response
        else:
            # Fallback: assume the whole response is what we want
            candidate_quotes = [parsed_response] if isinstance(parsed_response, dict) else []
        
        # Ensure we have a list and limit to the specified number of quotes
        if not isinstance(candidate_quotes, list):
            candidate_quotes = []
        else:
            candidate_quotes = candidate_quotes[:limit]
        
        return candidate_quotes
        
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse OpenAI response as JSON: {e}")
        logger.error(f"Response content: {content}")
        return []
    except Exception as e:
        logger.error(f"Error parsing quotes from response: {e}")
        return []