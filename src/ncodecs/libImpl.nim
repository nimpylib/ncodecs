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
  EncoderCvt = proc (s: string): string {.PraEncoderCvt.}
  EncoderClose = proc () {.raises: [].}
  NCodecInfo* = object
    name*: string
    errors*: EncErrors
    encode*, decode*: EncoderCvt
    close: EncoderClose

proc close*(self: NCodecInfo) = discard ## no need to call this. \
  ## remaining just for compatitable.
defdestroy NCodecInfo:
  if self.close.isNil: return
  self.close()

template cvt(b: Backend, impl: untyped): EncoderCvt =
  ## wraps a backend conversion as a closure; `inLen` is evaluated on `s`
  proc (s {.inject.}: string): string {.PraEncoderCvt.} =
    impl(b, s)

func initNCodecInfo*(encoding: string, errors = DefEncErrors): NCodecInfo =
  var b: Backend
  {.cast(noSideEffect).}:
    checkErrors errors
    b = openBackend(encoding, errors)
  NCodecInfo(
    name: encoding,
    errors: errors,
    encode: cvt(b, encodeImpl),
    decode: cvt(b, decodeImpl),
    close: proc () = closeImpl(b),
  )

func initNCodecInfo*(encoding: string, errors: string): NCodecInfo =
  initNCodecInfo(encoding, parseEnum[EncErrors](errors))
