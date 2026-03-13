# Tests for cache utilities

import std/[unittest, times, options, tables]
import nimctx/utils/cache

suite "memory cache":
  test "can create cache":
    let cache = newMemoryCache[string](maxSize = 100)
    check cache != nil
    check cache.maxSize == 100
  
  test "can set and get":
    let cache = newMemoryCache[string]()
    cache.set("key1", "value1")
    let val = cache.get("key1")
    check val.isSome
    check val.get() == "value1"
  
  test "returns none for missing key":
    let cache = newMemoryCache[string]()
    let val = cache.get("missing")
    check val.isNone
  
  test "can delete":
    let cache = newMemoryCache[string]()
    cache.set("key1", "value1")
    cache.del("key1")
    let val = cache.get("key1")
    check val.isNone
  
  test "can clear":
    let cache = newMemoryCache[string]()
    cache.set("key1", "value1")
    cache.set("key2", "value2")
    cache.clear()
    check cache.get("key1").isNone
    check cache.get("key2").isNone
  
  test "respects max size":
    let cache = newMemoryCache[string](maxSize = 2)
    cache.set("key1", "value1")
    cache.set("key2", "value2")
    cache.set("key3", "value3")  # Should trigger cleanup
    # At least one of the old keys should be evicted
    check (cache.get("key1").isNone or cache.get("key2").isNone)
    check cache.get("key3").isSome

  test "generates cache key":
    let key1 = getCacheKey("part1", "part2", "part3")
    check key1 == "part1:part2:part3"
    
    let key2 = getCacheKey("single")
    check key2 == "single"
