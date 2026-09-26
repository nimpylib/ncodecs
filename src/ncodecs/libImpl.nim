## Nim's codecs.
##  not the same as Python's codecs

import std/unicode
from std/strutils import parseEnum
import ./libImpl/common
export EncErrors, DefEncErrors, DefErrors, LookupError,
  UnicodeError, UnicodeDecodeError, UnicodeEncodeError

when defined(js): import ./libImpl/backend_js
else: import ./libImpl/backend_native

{.pragma: PraEncoderCvt, raises: [ValueError, LookupError, OSError].}
type
  CvtRes = tuple[data: string, len: int]
  EncoderCvt = proc (s: string): CvtRes {.PraEncoderCvt.}
  EncoderClose = proc () {.raises: [].}
  NCodecInfo* = object
    name*: string
    errors*: EncErrors
    encode*, decode*: EncoderCvt
    close*: EncoderClose

template cvt(b: Backend, impl: untyped, inLen: untyped): EncoderCvt =
  ## wraps a backend conversion as a closure; `inLen` is evaluated on `s`
  proc (s {.inject.}: string): CvtRes {.PraEncoderCvt.} =
    (impl(b, s), inLen)

func initNCodecInfo*(encoding: string, errors = DefEncErrors): NCodecInfo =
  var b: Backend
  {.cast(noSideEffect).}:
    checkErrors errors
    b = openBackend(encoding, errors)
  NCodecInfo(
    name: encoding,
    errors: errors,
    encode: cvt(b, encodeImpl, s.runeLen),
    decode: cvt(b, decodeImpl, s.len),
    close: proc () = closeImpl(b),
  )

func initNCodecInfo*(encoding: string, errors: string): NCodecInfo =
  initNCodecInfo(encoding, parseEnum[EncErrors](errors))
