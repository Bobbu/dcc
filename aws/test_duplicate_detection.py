#!/usr/bin/env python3

"""
Test script to debug the duplicate detection algorithm
"""

import re

def normalize_text(text):
    """Normalizes text for softer comparison by removing extra whitespace,
    punctuation variations, and common differences"""
    if not text:
        return ""
    
    text = (text.strip()
            .lower()
            # Remove extra whitespace
            .replace('\n', ' ')
            .replace('\t', ' ')
            # Normalize punctuation
            .replace('"', '"').replace('"', '"')  # Smart quotes
            .replace(''', "'").replace(''', "'")  # Smart apostrophes  
            .replace('—', '-').replace('–', '-')  # Em/en dashes
            .replace('…', '...')  # Ellipsis
            # Remove trailing periods from authors
            .rstrip('.'))
    # Clean up multiple spaces
    text = re.sub(r'\s+', ' ', text)
    return text

def calculate_similarity(text1, text2):
    """Calculates similarity ratio between two strings using a simple
    character-based approach suitable for quotes and author names"""
    if not text1 and not text2:
        return 1.0
    if not text1 or not text2:
        return 0.0
    
    # For very similar lengths, use character-by-character comparison
    if abs(len(text1) - len(text2)) <= 3:
        matches = 0
        max_length = max(len(text1), len(text2))
        
        for i in range(max_length):
            if i < len(text1) and i < len(text2) and text1[i] == text2[i]:
                matches += 1
        return matches / max_length if max_length > 0 else 0.0
    
    # For different lengths, use word-based comparison
    words1 = text1.split(' ')
    words2 = text2.split(' ')
    
    common_words = 0
    for word1 in words1:
        if word1 in words2 and len(word1) > 2:
            common_words += 1
    
    total_words = len(words1) + len(words2)
    return (2.0 * common_words) / total_words if total_words > 0 else 0.0

def are_similar_quotes(quote1_text, quote1_author, quote2_text, quote2_author):
    """Checks if two quotes are similar enough to be considered duplicates"""
    normalized_quote1 = normalize_text(quote1_text)
    normalized_quote2 = normalize_text(quote2_text)
    normalized_author1 = normalize_text(quote1_author)
    normalized_author2 = normalize_text(quote2_author)
    
    print(f"Comparing quotes:")
    print(f"  Quote 1: '{normalized_quote1}'")
    print(f"  Quote 2: '{normalized_quote2}'")
    print(f"  Author 1: '{normalized_author1}'")
    print(f"  Author 2: '{normalized_author2}'")
    
    # Exact match after normalization
    if normalized_quote1 == normalized_quote2 and normalized_author1 == normalized_author2:
        return True, "exact_match"
    
    # Similar quote text with exact author match
    quote_similarity = calculate_similarity(normalized_quote1, normalized_quote2)
    print(f"  Quote similarity: {quote_similarity:.3f}")
    if quote_similarity >= 0.90 and normalized_author1 == normalized_author2:
        return True, f"similar_quote_same_author_{quote_similarity:.2f}"
    
    # Exact quote with similar author (handles attribution variations)
    author_similarity = calculate_similarity(normalized_author1, normalized_author2)
    print(f"  Author similarity: {author_similarity:.3f}")
    if normalized_quote1 == normalized_quote2 and author_similarity >= 0.85:
        return True, f"same_quote_similar_author_{author_similarity:.2f}"
    
    # Both quote and author are very similar (for cases with minor differences)
    if quote_similarity >= 0.95 and author_similarity >= 0.90:
        return True, f"both_similar_q{quote_similarity:.2f}_a{author_similarity:.2f}"
    
    return False, None

def test_grady_booch_quotes():
    """Test with some Grady Booch quotes that were flagged as duplicates"""
    
    # Test quotes from the user's log
    test_quotes = [
        ("Software is a reflection of the human condition.", "Grady Booch"),
        ("The essence of software engineering is to manage complexity.", "Grady Booch"),
        ("A complex system that works is invariably found to have evolved from a simple system that worked.", "Grady Booch"),
    ]
    
    # Test against some example existing quotes (not by Grady Booch)
    existing_quotes = [
        ("The only way to do great work is to love what you do.", "Steve Jobs"),
        ("Innovation distinguishes between a leader and a follower.", "Steve Jobs"),
        ("Life is what happens to you while you're busy making other plans.", "John Lennon"),
        ("The future belongs to those who believe in the beauty of their dreams.", "Eleanor Roosevelt"),
        ("Success is not final, failure is not fatal: it is the courage to continue that counts.", "Winston Churchill")
    ]
    
    print("=== Testing Grady Booch quotes against existing database ===\n")
    
    for i, (test_quote, test_author) in enumerate(test_quotes):
        print(f"Testing quote {i+1}: '{test_quote}' by {test_author}")
        print("-" * 80)
        
        found_duplicates = False
        for existing_quote, existing_author in existing_quotes:
            is_similar, reason = are_similar_quotes(test_quote, test_author, existing_quote, existing_author)
            if is_similar:
                print(f"  ❌ DUPLICATE DETECTED: {reason}")
                print(f"     vs '{existing_quote}' by {existing_author}")
                found_duplicates = True
            else:
                print(f"  ✅ Not similar to '{existing_quote[:30]}...' by {existing_author}")
        
        if not found_duplicates:
            print(f"  ✅ No duplicates found for this quote")
        
        print()

if __name__ == "__main__":
    test_grady_booch_quotes()