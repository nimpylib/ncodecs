
from std/os import getAppFilename, splitFile

var cache: string
proc getAppName*: string =
  if cache.len > 0:
    return cache
  result = getAppFilename().splitFile.name
  cache = result

proc appMsg*(msg: string): string =
  getAppName() & ": " & msg
  
