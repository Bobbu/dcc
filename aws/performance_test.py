#!/usr/bin/env python3
"""
Performance comparison testing for DynamoDB optimization
Tests old table vs optimized table for various query patterns
"""

import boto3
import time
import json
import statistics
import sys
from concurrent.futures import ThreadPoolExecutor
import random

# Initialize DynamoDB
dynamodb = boto3.resource('dynamodb')
old_table = dynamodb.Table('dcc-quotes')
new_table = dynamodb.Table('dcc-quotes-optimized')

def time_operation(func, *args, **kwargs):
    """Time a function call and return result and duration"""
    start_time = time.time()
    result = func(*args, **kwargs)
    end_time = time.time()
    return result, (end_time - start_time) * 1000  # Return ms

def test_old_tag_query(tag_name):
    """Test tag query using old table (scan-based with string array contains)"""
    try:
        # The old table stores tags as a DynamoDB List of Strings
        # We need to scan and filter programmatically since DynamoDB contains() 
        # doesn't work reliably with List types in FilterExpression
        response = old_table.scan(Limit=50)  # Get more items to find matches
        
        matches = []
        for item in response['Items']:
            tags = item.get('tags', [])
            # Convert DynamoDB format to Python list if needed
            if isinstance(tags, list):
                tag_strings = [tag if isinstance(tag, str) else str(tag) for tag in tags]
            else:
                tag_strings = []
            
            if tag_name in tag_strings:
                matches.append(item)
                if len(matches) >= 10:  # Limit to 10 matches
                    break
        
        return len(matches)
    except Exception as e:
        print(f"Error in old tag query: {e}")
        return 0

def test_new_tag_query(tag_name):
    """Test tag query using optimized table (GSI-based)"""
    try:
        response = new_table.query(
            IndexName='TagQuoteIndex',
            KeyConditionExpression=boto3.dynamodb.conditions.Key('PK').eq(f'TAG#{tag_name}'),
            Limit=10
        )
        return len(response['Items'])
    except Exception as e:
        print(f"Error in new tag query: {e}")
        return 0

def test_old_author_query(author_name):
    """Test author query using old table (scan-based)"""
    try:
        response = old_table.scan(
            FilterExpression=boto3.dynamodb.conditions.Attr('author').eq(author_name),
            Limit=10
        )
        return len(response['Items'])
    except Exception as e:
        print(f"Error in old author query: {e}")
        return 0

def test_new_author_query(author_name):
    """Test author query using optimized table (GSI-based)"""
    try:
        response = new_table.query(
            IndexName='AuthorDateIndex',
            KeyConditionExpression=boto3.dynamodb.conditions.Key('author_normalized').eq(author_name.lower()),
            Limit=10
        )
        return len(response['Items'])
    except Exception as e:
        print(f"Error in new author query: {e}")
        return 0

def test_old_random_quote():
    """Test getting random quote from old table"""
    try:
        response = old_table.scan(Limit=100)
        if response['Items']:
            return random.choice(response['Items'])
        return None
    except Exception as e:
        print(f"Error in old random query: {e}")
        return None

def test_new_random_quote():
    """Test getting random quote from optimized table"""
    try:
        response = new_table.query(
            IndexName='TypeDateIndex',
            KeyConditionExpression=boto3.dynamodb.conditions.Key('type').eq('quote'),
            Limit=100
        )
        if response['Items']:
            return random.choice(response['Items'])
        return None
    except Exception as e:
        print(f"Error in new random query: {e}")
        return None

def run_performance_test(test_name, old_func, new_func, test_args, iterations=10):
    """Run performance comparison between old and new implementations"""
    print(f"\n🧪 Testing: {test_name}")
    print(f"Arguments: {test_args}")
    print(f"Iterations: {iterations}")
    print("-" * 60)
    
    old_times = []
    new_times = []
    
    # Test old implementation
    print("Testing OLD implementation...")
    for i in range(iterations):
        try:
            result, duration = time_operation(old_func, *test_args)
            old_times.append(duration)
            print(f"  Run {i+1}: {duration:.2f}ms (found {result} items)")
        except Exception as e:
            print(f"  Run {i+1}: ERROR - {e}")
    
    print("\nTesting NEW implementation...")
    for i in range(iterations):
        try:
            result, duration = time_operation(new_func, *test_args)
            new_times.append(duration)
            print(f"  Run {i+1}: {duration:.2f}ms (found {result} items)")
        except Exception as e:
            print(f"  Run {i+1}: ERROR - {e}")
    
    # Calculate statistics
    if old_times and new_times:
        old_avg = statistics.mean(old_times)
        new_avg = statistics.mean(new_times)
        improvement = ((old_avg - new_avg) / old_avg) * 100
        speedup = old_avg / new_avg
        
        print(f"\n📊 RESULTS for {test_name}:")
        print(f"  OLD Average: {old_avg:.2f}ms")
        print(f"  NEW Average: {new_avg:.2f}ms")
        print(f"  Improvement: {improvement:.1f}% faster")
        print(f"  Speed-up: {speedup:.1f}x")
        
        return {
            'test_name': test_name,
            'old_avg': old_avg,
            'new_avg': new_avg,
            'improvement_percent': improvement,
            'speedup': speedup
        }
    else:
        print(f"❌ Test failed - insufficient data")
        return None

def main():
    """Run comprehensive performance tests"""
    print("🚀 DynamoDB Optimization Performance Testing")
    print("=" * 60)
    
    results = []
    
    # Test 1: Tag-based queries (most impactful optimization)
    # Using tags verified to exist in old table
    popular_tags = ['Life', 'Humor', 'Success', 'Travel', 'Philosophy']
    
    for tag in popular_tags[:3]:  # Test top 3 popular tags
        result = run_performance_test(
            f"Tag Query: {tag}",
            test_old_tag_query,
            test_new_tag_query,
            [tag],
            iterations=5
        )
        if result:
            results.append(result)
    
    # Test 2: Author-based queries
    # Using authors verified to exist in old table
    popular_authors = ['Anthony Bourdain', 'Albert Einstein', 'Winston Churchill']
    
    for author in popular_authors[:2]:  # Test top 2 popular authors
        result = run_performance_test(
            f"Author Query: {author}",
            test_old_author_query,
            test_new_author_query,
            [author],
            iterations=5
        )
        if result:
            results.append(result)
    
    # Test 3: Random quote retrieval
    result = run_performance_test(
        "Random Quote Retrieval",
        test_old_random_quote,
        test_new_random_quote,
        [],
        iterations=5
    )
    if result:
        results.append(result)
    
    # Summary Report
    print("\n" + "=" * 60)
    print("📈 PERFORMANCE OPTIMIZATION SUMMARY")
    print("=" * 60)
    
    if results:
        total_improvement = statistics.mean([r['improvement_percent'] for r in results])
        avg_speedup = statistics.mean([r['speedup'] for r in results])
        
        for result in results:
            print(f"✅ {result['test_name']}: {result['improvement_percent']:.1f}% faster ({result['speedup']:.1f}x)")
        
        print(f"\n🎯 OVERALL PERFORMANCE GAINS:")
        print(f"   Average Improvement: {total_improvement:.1f}% faster")
        print(f"   Average Speed-up: {avg_speedup:.1f}x")
        
        if total_improvement > 50:
            print(f"\n🏆 EXCELLENT! Major performance improvement achieved!")
        elif total_improvement > 20:
            print(f"\n✅ GOOD! Significant performance improvement achieved!")
        else:
            print(f"\n📈 Modest performance improvement achieved.")
    else:
        print("❌ No successful test results to analyze")

if __name__ == '__main__':
    main()