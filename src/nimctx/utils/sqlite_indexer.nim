# SQLite-based indexer with FTS for fast symbol and documentation search
# Uses tiny_sqlite for Nim 2.0 compatibility

import std/[os, strutils, json, options]
import tiny_sqlite
export tiny_sqlite.DbValue, tiny_sqlite.DbValueKind

type
  SqliteIndex* = ref object
    db*: DbConn
    dbPath*: string
    nimPath*: string
    hasFts*: bool

proc initDatabase(db: DbConn): bool =
  ## Initialize SQLite database with symbols table and FTS virtual table
  ## Returns true if FTS is available and working
  
  # Main symbols table
  db.exec("""
    CREATE TABLE IF NOT EXISTS symbols (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      kind TEXT,
      module_path TEXT,
      module_name TEXT,
      code TEXT,
      description TEXT,
      line INTEGER,
      col INTEGER,
      package TEXT DEFAULT 'stdlib'
    )
  """)
  
  # Try FTS5 first, then FTS4
  var ftsAvailable = false
  try:
    db.exec("""
      CREATE VIRTUAL TABLE IF NOT EXISTS symbols_fts USING fts5(
        name, description, module_name,
        content='symbols',
        content_rowid='id'
      )
    """)
    ftsAvailable = true
  except:
    try:
      db.exec("""
        CREATE VIRTUAL TABLE IF NOT EXISTS symbols_fts USING fts4(
          name, description, module_name
        )
      """)
      ftsAvailable = true
    except:
      ftsAvailable = false
  
  if ftsAvailable:
    # Triggers to keep FTS index in sync
    db.exec("""
      CREATE TRIGGER IF NOT EXISTS symbols_ai AFTER INSERT ON symbols BEGIN
        INSERT INTO symbols_fts(rowid, name, description, module_name)
        VALUES (new.id, new.name, new.description, new.module_name);
      END
    """)
    
    db.exec("""
      CREATE TRIGGER IF NOT EXISTS symbols_ad AFTER DELETE ON symbols BEGIN
        INSERT INTO symbols_fts(symbols_fts, rowid, name, description, module_name)
        VALUES ('delete', old.id, old.name, old.description, old.module_name);
      END
    """)
  
  # Indexes for fast filtering
  db.exec("CREATE INDEX IF NOT EXISTS idx_symbols_name ON symbols(name)")
  db.exec("CREATE INDEX IF NOT EXISTS idx_symbols_kind ON symbols(kind)")
  db.exec("CREATE INDEX IF NOT EXISTS idx_symbols_module ON symbols(module_name)")
  db.exec("CREATE INDEX IF NOT EXISTS idx_symbols_package ON symbols(package)")
  
  result = ftsAvailable

proc checkFtsAvailable(db: DbConn): bool =
  ## Check if FTS tables exist
  try:
    for row in db.rows("SELECT name FROM sqlite_master WHERE type='table' AND name='symbols_fts'"):
      return row[0].fromDbValue(string) == "symbols_fts"
    return false
  except:
    return false

proc newSqliteIndex*(dbPath, nimPath: string): SqliteIndex =
  ## Create a new SQLite-based index
  result = SqliteIndex(
    dbPath: dbPath,
    nimPath: nimPath,
    hasFts: false
  )
  
  let dbExists = fileExists(dbPath)
  result.db = openDatabase(dbPath)
  
  if not dbExists:
    result.hasFts = initDatabase(result.db)
    if not result.hasFts:
      stderr.writeLine("Warning: SQLite FTS not available. Search will use slower LIKE queries.")
  else:
    result.hasFts = checkFtsAvailable(result.db)

proc close*(index: SqliteIndex) =
  ## Close the database connection
  index.db.close()

proc addSymbol*(index: SqliteIndex, name, kind, modulePath, code, description: string;
               line, col: int; package: string = "stdlib") =
  ## Add a symbol to the index
  let moduleName = extractFilename(modulePath).replace(".nim", "")
  
  index.db.exec("""
    INSERT INTO symbols (name, kind, module_path, module_name, code, description, line, col, package)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  """, name, kind, modulePath, moduleName, code, description, line, col, package)

proc clear*(index: SqliteIndex) =
  ## Clear all symbols (useful for re-indexing)
  index.db.exec("DELETE FROM symbols")
  if index.hasFts:
    try:
      index.db.exec("DELETE FROM symbols_fts")
    except:
      discard

type
  SymbolResult* = object
    id*: int64
    name*: string
    kind*: string
    modulePath*: string
    moduleName*: string
    code*: string
    description*: string
    line*: int
    col*: int
    package*: string

proc toSymbolResult(row: seq[DbValue]): SymbolResult =
  result.id = row[0].fromDbValue(int64)
  result.name = row[1].fromDbValue(string)
  result.kind = if row[2].kind == tiny_sqlite.sqliteNull: "" else: row[2].fromDbValue(string)
  result.modulePath = if row[3].kind == tiny_sqlite.sqliteNull: "" else: row[3].fromDbValue(string)
  result.moduleName = if row[4].kind == tiny_sqlite.sqliteNull: "" else: row[4].fromDbValue(string)
  result.code = if row[5].kind == tiny_sqlite.sqliteNull: "" else: row[5].fromDbValue(string)
  result.description = if row[6].kind == tiny_sqlite.sqliteNull: "" else: row[6].fromDbValue(string)
  result.line = row[7].fromDbValue(int64).int
  result.col = row[8].fromDbValue(int64).int
  result.package = if row[9].kind == tiny_sqlite.sqliteNull: "stdlib" else: row[9].fromDbValue(string)

proc sanitizeSearchQuery*(query: string): string =
  ## Sanitize a search query to prevent SQL injection
  ## Removes special SQLite FTS characters that could cause issues
  result = query
  # Remove SQLite FTS special characters (but keep basic wildcards for LIKE)
  result = result.replace("\"", "")  # Remove double quotes
  result = result.replace("'", "")   # Remove single quotes
  result = result.replace(";", "")   # Remove semicolons
  result = result.replace("--", "")  # Remove SQL comments
  result = result.replace("/*", "")  # Remove block comment start
  result = result.replace("*/", "")  # Remove block comment end
  result = result.strip()

proc search*(index: SqliteIndex, query: string;
             moduleFilter: Option[string] = none(string),
             kindFilter: Option[string] = none(string),
             packageFilter: Option[string] = none(string),
             maxResults: int = 20): seq[SymbolResult] =
  ## Search for symbols using FTS if available, fallback to LIKE
  
  let safeQuery = sanitizeSearchQuery(query)
  if safeQuery.len == 0:
    return @[]
  
  let queryLower = safeQuery.toLowerAscii()
  
  if index.hasFts and query.len > 0:
    # Use FTS for fast full-text search
    var sqlQuery = """
      SELECT s.id, s.name, s.kind, s.module_path, s.module_name, 
             s.code, s.description, s.line, s.col, s.package
      FROM symbols s
      JOIN symbols_fts fts ON s.id = fts.rowid
      WHERE symbols_fts MATCH ?
    """
    var params: seq[DbValue] = @[query.toDbValue]
    
    if moduleFilter.isSome:
      sqlQuery.add " AND s.module_name = ?"
      params.add moduleFilter.get().toDbValue
    
    if kindFilter.isSome:
      sqlQuery.add " AND s.kind = ?"
      params.add kindFilter.get().toDbValue
    
    if packageFilter.isSome:
      sqlQuery.add " AND s.package = ?"
      params.add packageFilter.get().toDbValue
    
    sqlQuery.add " LIMIT ?"
    params.add maxResults.toDbValue
    
    for row in index.db.rows(sqlQuery, params):
      result.add(toSymbolResult(row))
  else:
    # Fallback to LIKE queries
    var sqlQuery = """
      SELECT id, name, kind, module_path, module_name, 
             code, description, line, col, package
      FROM symbols
      WHERE (LOWER(name) LIKE ? OR LOWER(description) LIKE ?)
    """
    let likePattern = "%" & queryLower & "%"
    var params: seq[DbValue] = @[likePattern.toDbValue, likePattern.toDbValue]
    
    if moduleFilter.isSome:
      sqlQuery.add " AND module_name = ?"
      params.add moduleFilter.get().toDbValue
    
    if kindFilter.isSome:
      sqlQuery.add " AND kind = ?"
      params.add kindFilter.get().toDbValue
    
    if packageFilter.isSome:
      sqlQuery.add " AND package = ?"
      params.add packageFilter.get().toDbValue
    
    sqlQuery.add " LIMIT ?"
    params.add maxResults.toDbValue
    
    for row in index.db.rows(sqlQuery, params):
      result.add(toSymbolResult(row))

proc getSymbol*(index: SqliteIndex, name: string): Option[SymbolResult] =
  ## Get a single symbol by name
  for row in index.db.rows("""
    SELECT id, name, kind, module_path, module_name, 
           code, description, line, col, package
    FROM symbols
    WHERE name = ?
    LIMIT 1
  """, name):
    return some(toSymbolResult(row))
  
  return none(SymbolResult)

proc getModuleSymbols*(index: SqliteIndex, moduleName: string): seq[SymbolResult] =
  ## Get all symbols from a module
  for row in index.db.rows("""
    SELECT id, name, kind, module_path, module_name, 
           code, description, line, col, package
    FROM symbols
    WHERE module_name = ?
  """, moduleName):
    result.add(toSymbolResult(row))

proc getStats*(index: SqliteIndex): JsonNode =
  ## Get index statistics
  var symbolCount = 0
  var moduleCount = 0
  var packageCount = 0
  
  for row in index.db.rows("SELECT COUNT(*) FROM symbols"):
    symbolCount = row[0].fromDbValue(int64).int
  
  for row in index.db.rows("SELECT COUNT(DISTINCT module_name) FROM symbols"):
    moduleCount = row[0].fromDbValue(int64).int
  
  for row in index.db.rows("SELECT COUNT(DISTINCT package) FROM symbols"):
    packageCount = row[0].fromDbValue(int64).int
  
  result = %*{
    "totalSymbols": symbolCount,
    "totalModules": moduleCount,
    "totalPackages": packageCount,
    "ftsAvailable": index.hasFts,
    "dbPath": index.dbPath
  }

proc formatSymbol*(sym: SymbolResult): string =
  ## Format symbol for display
  result = "## " & sym.name & "\n\n"
  result.add("**Kind:** " & sym.kind & "\n\n")
  result.add("**Module:** " & sym.moduleName & " (" & sym.package & ")\n\n")
  result.add("**Signature:**\n```nim\n" & sym.code & "\n```\n\n")
  
  if sym.description.len > 0:
    result.add("**Description:**\n" & sym.description & "\n")

proc listModules*(index: SqliteIndex): seq[string] =
  ## List all module names in the index
  for row in index.db.rows("SELECT DISTINCT module_name FROM symbols"):
    result.add(row[0].fromDbValue(string))

proc listSymbols*(index: SqliteIndex): seq[string] =
  ## List all symbol names in the index
  for row in index.db.rows("SELECT name FROM symbols"):
    result.add(row[0].fromDbValue(string))
