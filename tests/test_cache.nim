# Tests for cache utilities

import std/[unittest, os, times, options, tables]
import nimctx/utils/cache

suite "memory cache":
  test "can create memory cache":
    let cache = newMemoryCache[string](maxSize = 100, defaultTtl = initDuration(minutes = 5))
    check cache != nil
    check cache.maxSize == 100
    check len(cache.entries) == 0

  test "can set and get value":
    let cache = newMemoryCache[string](maxSize = 10)
    cache.set("key1", "value1")
    
    let result = cache.get("key1")
    check result.isSome
    check result.get() == "value1"

  test "get returns none for non-existent key":
    let cache = newMemoryCache[int](maxSize = 10)
    let result = cache.get("nonexistent")
    check result.isNone

  test "get returns none for expired entry":
    let cache = newMemoryCache[string](maxSize = 10, defaultTtl = initDuration(milliseconds = 50))
    cache.set("key1", "value1")
    
    # Should exist immediately
    check cache.get("key1").isSome
    
    # Wait for expiration
    sleep(100)
    
    # Should be expired now
    let result = cache.get("key1")
    check result.isNone

  test "can delete key":
    let cache = newMemoryCache[string](maxSize = 10)
    cache.set("key1", "value1")
    check cache.get("key1").isSome
    
    cache.del("key1")
    check cache.get("key1").isNone

  test "clear removes all entries":
    let cache = newMemoryCache[string](maxSize = 10)
    cache.set("key1", "value1")
    cache.set("key2", "value2")
    check cache.entries.len == 2
    
    cache.clear()
    check len(cache.entries) == 0
    check cache.get("key1").isNone
    check cache.get("key2").isNone

  test "respects max size with LRU eviction":
    let cache = newMemoryCache[string](maxSize = 2)
    cache.set("key1", "value1")
    cache.set("key2", "value2")
    check cache.entries.len == 2
    
    # Adding third item should evict oldest
    cache.set("key3", "value3")
    check cache.entries.len == 2
    
    # key1 should be evicted (LRU)
    check cache.get("key1").isNone
    check cache.get("key2").isSome
    check cache.get("key3").isSome

  test "access updates LRU order":
    let cache = newMemoryCache[string](maxSize = 2)
    cache.set("key1", "value1")
    cache.set("key2", "value2")
    
    # Access key1 to make it more recent
    discard cache.get("key1")
    
    # Add new item - should evict key2 (now older)
    cache.set("key3", "value3")
    
    check cache.get("key1").isSome  # Should still exist
    check cache.get("key2").isNone  # Should be evicted
    check cache.get("key3").isSome  # New item

  test "custom TTL overrides default":
    let cache = newMemoryCache[string](maxSize = 10, defaultTtl = initDuration(minutes = 10))
    cache.set("key1", "value1", ttl = initDuration(milliseconds = 50))
    
    check cache.get("key1").isSome
    sleep(100)
    check cache.get("key1").isNone

  test "zero TTL means no expiration":
    let cache = newMemoryCache[string](maxSize = 10, defaultTtl = initDuration(0))
    cache.set("key1", "value1")
    
    # Should still exist after short wait
    sleep(50)
    check cache.get("key1").isSome

  test "getCacheKey generates correct keys":
    check getCacheKey("a", "b", "c") == "a:b:c"
    check getCacheKey("single") == "single"
    check getCacheKey("") == ""
