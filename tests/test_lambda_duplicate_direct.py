#!/usr/bin/env python3
"""
Direct test of duplicate detection Lambda function logic
"""
import sys
import os
import json

# Add the lambda directory to path so we can import the admin_handler
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'aws', 'lambda'))

# Import the functions from admin_handler
from admin_handler import normalize_text, calculate_similarity, are_similar_quotes

def test_normalization():
    """Test text normalization function"""
    print("🔤 Testing text normalization...")
    
    test_cases = [
        ("Hello   World!", "hello world!"),
        ("Einstein.", "einstein"),
        ('"Smart quotes"', '"smart quotes"'),
        ("Text—with–dashes", "text-with-dashes"),
        ("Multiple\n\twhitespace", "multiple whitespace"),
    ]
    
    for input_text, expected in test_cases:
        result = normalize_text(input_text)
        status = "✅" if result == expected else "❌"
        print(f"  {status} '{input_text}' → '{result}' (expected: '{expected}')")
    
    return True

def test_similarity():
    """Test similarity calculation"""
    print("\n📊 Testing similarity calculation...")
    
    test_cases = [
        ("hello world", "hello world", 1.0),
        ("hello world", "hello world!", "high"),  # Should be high similarity
        ("albert einstein", "einstein", "medium"),  # Should be medium similarity
        ("to be or not to be", "to be, or not to be", "medium"),  # Punctuation difference
        ("completely different", "totally unrelated", "low"),  # Should be low
    ]
    
    for text1, text2, expected in test_cases:
        result = calculate_similarity(text1, text2)
        
        if expected == "high":
            status = "✅" if result >= 0.8 else "❌"
        elif expected == "medium":
            status = "✅" if 0.3 <= result < 0.8 else "❌"
        elif expected == "low":
            status = "✅" if result < 0.3 else "❌"
        else:
            status = "✅" if abs(result - expected) < 0.01 else "❌"
        
        print(f"  {status} '{text1}' vs '{text2}' = {result:.3f} ({expected})")
    
    return True

def test_duplicate_detection():
    """Test the main duplicate detection logic"""
    print("\n🔍 Testing duplicate detection logic...")
    
    test_cases = [
        # Should be duplicates
        ("The only way to do great work is to love what you do", "Steve Jobs",
         "The only way to do great work is to love what you do.", "Steve Jobs", True, "punctuation"),
        
        ("Life is what happens", "John Lennon",
         "Life is what happens", "John Lennon.", True, "author punctuation"),
         
        ("Be yourself; everyone else is taken", "Oscar Wilde",
         "Be yourself, everyone else is taken", "Oscar Wilde", True, "minor quote change"),
        
        # Should NOT be duplicates
        ("The best time to plant a tree", "Chinese Proverb",
         "A journey of a thousand miles", "Lao Tzu", False, "different quotes"),
         
        ("Same quote", "Author One",
         "Same quote", "Completely Different Author", False, "same quote, different author"),
    ]
    
    for quote1, author1, quote2, author2, should_match, description in test_cases:
        is_similar, reason = are_similar_quotes(quote1, author1, quote2, author2)
        
        status = "✅" if is_similar == should_match else "❌"
        print(f"  {status} {description}")
        print(f"      Quote 1: '{quote1}' by {author1}")
        print(f"      Quote 2: '{quote2}' by {author2}")
        print(f"      Result: {is_similar} ({reason if reason else 'no match'})")
        print()
    
    return True

def main():
    """Run all tests"""
    print("🧪 Testing Duplicate Detection Lambda Functions")
    print("=" * 50)
    
    try:
        test_normalization()
        test_similarity() 
        test_duplicate_detection()
        
        print("✅ All Lambda function tests completed!")
        return 0
        
    except Exception as e:
        print(f"❌ Test failed with error: {e}")
        import traceback
        traceback.print_exc()
        return 1

if __name__ == "__main__":
    exit(main())