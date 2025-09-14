import json
import os
import boto3
import requests
from datetime import datetime

def create_response(status_code, body):
    """Create a properly formatted HTTP response"""
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, X-Api-Key, Authorization'
        },
        'body': json.dumps(body) if isinstance(body, (dict, list)) else str(body)
    }

def lambda_handler(event, context):
    """Main Lambda handler for OpenAI operations"""
    print(f"🤖 OpenAI Handler received event: {json.dumps(event)}")
    
    try:
        # Parse the request
        method = event.get('httpMethod', '')
        path = event.get('path', '')
        
        # Check authentication
        auth_header = event.get('headers', {}).get('Authorization', '')
        if not auth_header or not auth_header.startswith('Bearer '):
            return create_response(401, {"error": "Authentication required"})
        
        # For now, we'll assume the token is valid (Cognito authorizer handles this)
        # In a production system, you might want additional validation
        
        if method == 'POST' and path == '/admin/generate-tags':
            return handle_generate_tags(event)
        else:
            return create_response(404, {"error": "Not found"})
            
    except Exception as e:
        print(f"❌ OpenAI Handler error: {e}")
        import traceback
        traceback.print_exc()
        return create_response(500, {"error": "Internal server error"})

def handle_generate_tags(event):
    """Handle POST /admin/generate-tags"""
    try:
        # Parse the request body
        body = json.loads(event.get('body', '{}'))
        quote_text = body.get('quote', '').strip()
        author = body.get('author', '').strip()
        existing_tags = body.get('existingTags', [])
        
        print(f"🏷️ Generating tags for quote by {author}: {quote_text[:100]}...")
        
        if not quote_text:
            return create_response(400, {"error": "Quote text is required"})
        
        # Prepare the prompt for OpenAI
        existing_tags_str = ', '.join(existing_tags[:20]) if existing_tags else "None"
        
        prompt = f"""
You are an expert at categorizing inspirational and motivational quotes with relevant, professional tags.

Quote: "{quote_text}"
Author: {author}

Existing tags in the system: {existing_tags_str}

Instructions:
1. Generate 1-5 highly relevant tags for this quote
2. Focus on themes, emotions, concepts, and topics
3. Choose only from the existing tags. Do not make any new ones.

Return only a JSON array of tag strings, nothing else.
Example: ["Wisdom", "Personal Growth", "Humor"]
"""

        # Get OpenAI API key
        api_key = os.environ.get('OPENAI_API_KEY')
        if not api_key:
            return create_response(500, {"error": "OpenAI API key not configured"})
        
        # Call OpenAI API using requests (more reliable in Lambda)
        try:
            response = requests.post(
                'https://api.openai.com/v1/chat/completions',
                headers={
                    'Content-Type': 'application/json',
                    'Authorization': f'Bearer {api_key}'
                },
                json={
                    'model': 'gpt-4o-mini',
                    'messages': [
                        {
                            'role': 'system',
                            'content': 'You are a professional quote categorization assistant. Always return valid JSON arrays of strings.'
                        },
                        {
                            'role': 'user',
                            'content': prompt
                        }
                    ],
                    'max_tokens': 200,
                    'temperature': 0.3
                },
                timeout=30
            )
            
            # Check response status
            if response.status_code == 200:
                data = response.json()
                content = data['choices'][0]['message']['content'].strip()
                print(f"🤖 OpenAI raw response: {content}")
                
                # Try to parse as JSON
                try:
                    tags = json.loads(content)
                    if not isinstance(tags, list):
                        raise ValueError("Response is not a list")
                    
                    # Clean and validate tags
                    clean_tags = []
                    for tag in tags:
                        if isinstance(tag, str) and tag.strip():
                            clean_tag = tag.strip()
                            if len(clean_tag) <= 50:  # Reasonable tag length limit
                                clean_tags.append(clean_tag)
                    
                    # Limit to 5 tags max
                    final_tags = clean_tags[:5]
                    
                    print(f"✅ Generated {len(final_tags)} tags: {final_tags}")
                    
                    return create_response(200, {
                        "tags": final_tags,
                        "quote": quote_text,
                        "author": author
                    })
                    
                except json.JSONDecodeError:
                    print(f"❌ Failed to parse OpenAI response as JSON: {content}")
                    # Fallback: extract likely tags from response
                    import re
                    tag_pattern = r'"([^"]+)"'
                    extracted_tags = re.findall(tag_pattern, content)
                    if extracted_tags:
                        fallback_tags = [tag for tag in extracted_tags if len(tag) <= 50][:5]
                        print(f"🔄 Fallback extraction found {len(fallback_tags)} tags: {fallback_tags}")
                        return create_response(200, {
                            "tags": fallback_tags,
                            "quote": quote_text,
                            "author": author
                        })
                    else:
                        return create_response(500, {"error": "Failed to parse tag recommendations"})
            else:
                print(f"❌ OpenAI API returned status {response.status_code}: {response.text}")
                return create_response(500, {"error": f"OpenAI API error: {response.status_code}"})
                
        except requests.exceptions.Timeout:
            print(f"❌ OpenAI API timeout")
            return create_response(500, {"error": "OpenAI API timeout"})
        except Exception as openai_error:
            print(f"❌ OpenAI API error: {openai_error}")
            return create_response(500, {"error": f"OpenAI API error: {str(openai_error)}"})
        
    except Exception as e:
        print(f"❌ Error in handle_generate_tags: {e}")
        import traceback
        traceback.print_exc()
        return create_response(500, {"error": "Internal server error"})