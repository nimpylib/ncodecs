## Nim's codecs.
##  not the same as Python's codecs

from std/strutils import parseEnum
import pkg/nimpatch/destroyPatch
import ./libImpl/common
export EncErrors, DefEncErrors, DefErrors, LookupError,
  UnicodeError, UnicodeDecodeError, UnicodeEncodeError

when defined(js): import ./libImpl/backend_js
else: import ./libImpl/backend_native
export setDefaultEncoding
export encoding_norm

{.pragma: PraEncoderCvt, raises: [ValueError, LookupError, OSError].}
type
  NCodecInfo* = object
    b: Backend
    name: string
    errors: EncErrors

proc close*(self: NCodecInfo) = discard ## no need to call this. \
  ## remaining just for compatitable.
defdestroy NCodecInfo:
  if self.b.isNil: return
  self.b.closeImpl

using
  self: NCodecInfo
  s: openArray[char]|string
# `|string` as we want to support types convertible to string
#   like PyStr
proc encode*(self; s): string = self.b.encodeImpl s
proc decode*(self; s): string = self.b.decodeImpl s
# getters
proc name*(self): string = self.name
proc errors*(self): EncErrors = self.errors


func initNCodecInfo*(encoding: string, errors = DefEncErrors): NCodecInfo =
  var b: Backend
  {.cast(noSideEffect).}:
    checkErrors errors
    b = openBackend(encoding, errors)
  NCodecInfo(
    b: b,
    name: encoding,
    errors: errors,
  )

func initNCodecInfo*(encoding: string, errors: string): NCodecInfo =
  initNCodecInfo(encoding, parseEnum[EncErrors](errors))
