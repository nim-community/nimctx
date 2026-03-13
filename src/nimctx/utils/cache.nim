# Cache utilities for nimctx

import std/[tables, times, os, json, strutils, options]

type
  CacheEntry*[T] = object
    data*: T
    createdAt*: Time
    ttl*: Duration  # Time-to-live, zero means no expiration
  
  MemoryCache*[T] = ref object
    entries*: Table[string, CacheEntry[T]]
    maxSize*: int
    defaultTtl*: Duration

proc newMemoryCache*[T](maxSize: int = 1000, defaultTtl: Duration = initDuration(minutes = 5)): MemoryCache[T] =
  ## Create a new memory cache
  result = MemoryCache[T](
    entries: initTable[string, CacheEntry[T]](),
    maxSize: maxSize,
    defaultTtl: defaultTtl
  )

proc isExpired[T](entry: CacheEntry[T]): bool =
  ## Check if cache entry is expired
  if entry.ttl == initDuration(0):
    return false
  let elapsed = getTime() - entry.createdAt
  return elapsed > entry.ttl

proc get*[T](cache: MemoryCache[T], key: string): Option[T] =
  ## Get value from cache
  if not cache.entries.hasKey(key):
    return none(T)
  
  let entry = cache.entries[key]
  if isExpired(entry):
    cache.entries.del(key)
    return none(T)
  
  return some(entry.data)

proc set*[T](cache: MemoryCache[T], key: string, value: T, ttl: Duration = initDuration(0)) =
  ## Set value in cache
  # Clean up if at capacity (simple LRU - remove oldest)
  if cache.entries.len >= cache.maxSize:
    var oldestKey = ""
    var oldestTime = getTime()
    for k, v in cache.entries:
      if v.createdAt < oldestTime:
        oldestTime = v.createdAt
        oldestKey = k
    if oldestKey.len > 0:
      cache.entries.del(oldestKey)
  
  let actualTtl = if ttl == initDuration(0): cache.defaultTtl else: ttl
  cache.entries[key] = CacheEntry[T](
    data: value,
    createdAt: getTime(),
    ttl: actualTtl
  )

proc del*[T](cache: MemoryCache[T], key: string) =
  ## Delete key from cache
  cache.entries.del(key)

proc clear*[T](cache: MemoryCache[T]) =
  ## Clear all cache entries
  cache.entries.clear()

proc getCacheKey*(parts: varargs[string]): string =
  ## Generate a cache key from parts
  result = parts.join(":")

# File cache for persistent storage
proc saveToFile*[T](cache: MemoryCache[T], path: string) =
  ## Save cache to file (as JSON)
  var jsonArr = newJArray()
  for key, entry in cache.entries:
    if not isExpired(entry):
      let entryJson = %*{
        "key": key,
        "data": $entry.data,  # This requires T to be serializable
        "createdAt": $entry.createdAt.toUnix(),
        "ttl": entry.ttl.inSeconds
      }
      jsonArr.add(entryJson)
  
  writeFile(path, $jsonArr)

proc loadFromFile*[T](cache: MemoryCache[T], path: string) =
  ## Load cache from file
  if not fileExists(path):
    return
  
  try:
    let content = readFile(path)
    let jsonArr = parseJson(content)
    # Note: This is a simplified version - actual implementation would
    # need proper deserialization based on type T
  except:
    discard
