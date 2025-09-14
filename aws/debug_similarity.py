#!/usr/bin/env python3

"""
Debug the similarity calculation with real database quotes
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
    
    print(f"  Comparing lengths: {len(text1)} vs {len(text2)} (diff: {abs(len(text1) - len(text2))})")
    
    # For very similar lengths, use character-by-character comparison
    if abs(len(text1) - len(text2)) <= 3:
        print("  Using character-by-character comparison")
        matches = 0
        max_length = max(len(text1), len(text2))
        
        for i in range(max_length):
            if i < len(text1) and i < len(text2) and text1[i] == text2[i]:
                matches += 1
        
        similarity = matches / max_length if max_length > 0 else 0.0
        print(f"  Character matches: {matches}/{max_length} = {similarity:.3f}")
        return similarity
    
    # For different lengths, use word-based comparison
    print("  Using word-based comparison")
    words1 = text1.split(' ')
    words2 = text2.split(' ')
    
    print(f"  Words1 ({len(words1)}): {words1}")
    print(f"  Words2 ({len(words2)}): {words2}")
    
    common_words = 0
    common_word_list = []
    for word1 in words1:
        if word1 in words2 and len(word1) > 2:
            common_words += 1
            common_word_list.append(word1)
    
    total_words = len(words1) + len(words2)
    similarity = (2.0 * common_words) / total_words if total_words > 0 else 0.0
    
    print(f"  Common words (>2 chars): {common_word_list}")
    print(f"  Common word count: {common_words}")
    print(f"  Total words: {total_words}")
    print(f"  Word similarity: (2 * {common_words}) / {total_words} = {similarity:.3f}")
    
    return similarity

def test_suspicious_similarities():
    """Test some combinations that might produce false positives"""
    
    test_cases = [
        # Test common short phrases that might match
        ("The only way to do great work is to love what you do.", "Steve Jobs",
         "Software is a reflection of the human condition.", "Grady Booch"),
        
        # Test similar sentence structures
        ("Innovation distinguishes between a leader and a follower.", "Steve Jobs",
         "The essence of software engineering is to manage complexity.", "Grady Booch"),
        
        # Test with very common words
        ("Success is not final, failure is not fatal: it is the courage to continue that counts.", "Winston Churchill",
         "A complex system that works is invariably found to have evolved from a simple system that worked.", "Grady Booch"),
    ]
    
    for i, (quote1, author1, quote2, author2) in enumerate(test_cases, 1):
        print(f"\n=== Test Case {i} ===")
        print(f"Quote 1: '{quote1}' by {author1}")
        print(f"Quote 2: '{quote2}' by {author2}")
        
        norm_quote1 = normalize_text(quote1)
        norm_quote2 = normalize_text(quote2)
        norm_author1 = normalize_text(author1)
        norm_author2 = normalize_text(author2)
        
        print(f"\nNormalized:")
        print(f"Quote 1: '{norm_quote1}'")
        print(f"Quote 2: '{norm_quote2}'")
        print(f"Author 1: '{norm_author1}'")
        print(f"Author 2: '{norm_author2}'")
        
        print(f"\nQuote similarity calculation:")
        quote_similarity = calculate_similarity(norm_quote1, norm_quote2)
        
        print(f"\nAuthor similarity calculation:")
        author_similarity = calculate_similarity(norm_author1, norm_author2)
        
        print(f"\nResults:")
        print(f"Quote similarity: {quote_similarity:.3f}")
        print(f"Author similarity: {author_similarity:.3f}")
        
        # Check if this would be flagged as duplicate
        is_duplicate = False
        reason = None
        
        if norm_quote1 == norm_quote2 and norm_author1 == norm_author2:
            is_duplicate = True
            reason = "exact_match"
        elif quote_similarity >= 0.90 and norm_author1 == norm_author2:
            is_duplicate = True
            reason = f"similar_quote_same_author_{quote_similarity:.2f}"
        elif norm_quote1 == norm_quote2 and author_similarity >= 0.85:
            is_duplicate = True
            reason = f"same_quote_similar_author_{author_similarity:.2f}"
        elif quote_similarity >= 0.95 and author_similarity >= 0.90:
            is_duplicate = True
            reason = f"both_similar_q{quote_similarity:.2f}_a{author_similarity:.2f}"
        
        if is_duplicate:
            print(f"❌ WOULD BE FLAGGED AS DUPLICATE: {reason}")
        else:
            print(f"✅ Not flagged as duplicate")
        
        print("-" * 80)

if __name__ == "__main__":
    test_suspicious_similarities()