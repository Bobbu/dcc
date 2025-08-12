import json
import random

# Collection of inspirational quotes with their authors
QUOTES = [
    {
        "quote": "The only way to do great work is to love what you do.",
        "author": "Steve Jobs"
    },
    {
        "quote": "Innovation distinguishes between a leader and a follower.",
        "author": "Steve Jobs"
    },
    {
        "quote": "Life is what happens to you while you're busy making other plans.",
        "author": "John Lennon"
    },
    {
        "quote": "The future belongs to those who believe in the beauty of their dreams.",
        "author": "Eleanor Roosevelt"
    },
    {
        "quote": "It is during our darkest moments that we must focus to see the light.",
        "author": "Aristotle"
    },
    {
        "quote": "The only impossible journey is the one you never begin.",
        "author": "Tony Robbins"
    },
    {
        "quote": "Success is not final, failure is not fatal: it is the courage to continue that counts.",
        "author": "Winston Churchill"
    },
    {
        "quote": "The way to get started is to quit talking and begin doing.",
        "author": "Walt Disney"
    },
    {
        "quote": "Don't let yesterday take up too much of today.",
        "author": "Will Rogers"
    },
    {
        "quote": "You learn more from failure than from success. Don't let it stop you. Failure builds character.",
        "author": "Unknown"
    },
    {
        "quote": "If you are working on something that you really care about, you don't have to be pushed. The vision pulls you.",
        "author": "Steve Jobs"
    },
    {
        "quote": "Experience is a hard teacher because she gives the test first, the lesson afterward.",
        "author": "Vernon Law"
    },
    {
        "quote": "To live a creative life, we must lose our fear of being wrong.",
        "author": "Joseph Chilton Pearce"
    },
    {
        "quote": "If you want to lift yourself up, lift up someone else.",
        "author": "Booker T. Washington"
    },
    {
        "quote": "I have not failed. I've just found 10,000 ways that won't work.",
        "author": "Thomas A. Edison"
    }
]

def lambda_handler(event, context):
    """
    AWS Lambda handler for the quote endpoint.
    Returns a random quote with its author.
    """
    try:
        # Select a random quote
        selected_quote = random.choice(QUOTES)
        
        # Prepare the response
        response_body = {
            "quote": selected_quote["quote"],
            "author": selected_quote["author"]
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