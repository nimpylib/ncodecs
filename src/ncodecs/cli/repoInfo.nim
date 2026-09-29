
import std/strutils
import std/uri
const
  repoUrl*{.strdefine.} = ""

proc getRepoOwner*(default = ""): string =
  if repoUrl == "": return default
  let parts = parseUri repoUrl
  result = parts.path.strip(chars = {'/'})
  let pathParts = result.split('/')
  assert pathParts.len == 2
  result = pathParts[0]

