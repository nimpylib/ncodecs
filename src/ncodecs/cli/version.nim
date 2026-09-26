
import std/compilesettings
import std/strutils
import std/paths
import std/strformat
import ./utils

when defined(nimPreviewSlimSystem):
  import std/assertions
  import std/syncio

proc getNimbleMeta: tuple[version, author: string]{.compileTime.} =
  let
    proj = Path querySetting(projectFull)
    projName = Path querySetting(projectName)
  let nimbleFile = $(proj.parentDir /../ projName).addFileExt"nimble"
  proc lstripSp(s: string): string =
    s.strip(trailing=false, chars={' '})
  template tryGetVal(key) =
    let k = astToStr(key)
    if line.startsWith k:
      var res = line[k.len..^1]
      res = res.lstripSp
      if res[0] == '=':
        res = res[1..^1]
        res = res.lstripSp
        result.key = res[1..^2]
        continue

  for line in nimbleFile.readFile.splitLines: # use this as this proc is static
    tryGetVal version
    tryGetVal author

  for k, v in result.fieldPairs:
    if v.len == 0:
      doAssert false, "failed to fetch " & k & " from nimble file"

const info = getNimbleMeta()
proc getVersion*: string =
  let app = getAppName()
  const year = CompileDate.split('-', 1)[0]
  const Inc = info.author
  fmt"""
{app} {info.version}
Copyright (C) {year} {Inc}.
This is free software; see the source for copying conditions.  There is NO
warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
Written by {info.author}.
"""  

