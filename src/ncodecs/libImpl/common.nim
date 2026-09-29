## Types and helpers shared by all backends.
##
## Every backend module must provide:
##
## - `type Backend`
## - `proc openBackend(encoding: string, errors: EncErrors): Backend`
##   (raises `LookupError` for unknown encodings)
## - `proc encodeImpl(b: Backend, s: string): string`  (UTF-8 -> encoding)
## - `proc decodeImpl(b: Backend, s: string): string`  (encoding -> UTF-8)
## - `proc closeImpl(b: Backend)`

import std/[unicode, strutils]
import pkg/pyerrors/[lkuperr, unicode_err]
import pkg/py_locale_utf8_encoding/encoding_norm
import pkg/py_locale_utf8_encoding/internal/pycore_fileutils
export EncErrors, toPyErrorHandler, encoding_norm
export LookupError, unicode_err

const
  DefEncErrors* = EncErrors.strict
  DefErrors* = $DefEncErrors
  SupportedEncErrors* = {EncErrors.strict, EncErrors.ignore, EncErrors.replace}
  DecodeReplacement* = "\uFFFD"  ## used on decoding (UTF-8 bytes)
  EncodeReplacement* = "?"       ## used on encoding

proc checkErrors*(errors: EncErrors) =
  if errors notin SupportedEncErrors:
    raise newException(LookupError,
      "error handler '" & $errors & "' is not supported yet")

proc unknownEncoding*(encoding: string): ref LookupError =
  newException(LookupError, "unknown encoding: " & encoding)

using s: openArray[char]
proc encodeErrorAt*(codec: string, s; pos: int,
    reason = "character maps to <undefined>"): ref UnicodeEncodeError =
  ## `pos` is a byte offset of UTF-8 `s`; reported position is in runes.
  let runePos = s.toOpenArray(0, pos-1).runeLen  # 0..-1 is empty
  var ch = ""
  if pos < s.len:
    let r = s.runeAt(pos).int32
    ch = "'\\u" & toHex(r, if r > 0xFFFF: 8 else: 4).toLowerAscii & "' "
  newException(UnicodeEncodeError,
    "'" & codec & "' codec can't encode character " & ch &
    "in position " & $runePos & ": " & reason)

proc decodeErrorAt*(codec: string, s; pos, badLen: int,
    reason = "invalid start byte"): ref UnicodeDecodeError =
  newUnicodeDecodeError(codec, s[pos], pos, pos + max(1, badLen), reason)

proc invalidDataError*(codec: string, decoding: bool): ref UnicodeError =
  ## for backends that cannot locate the offending position
  let prefix = "'" & codec & "' codec can't "
  if decoding:
    result = newException(UnicodeDecodeError, prefix & "decode bytes: invalid data")
  else:
    result = newException(UnicodeEncodeError, prefix & "encode: invalid utf-8 input")

template onBadInput*(errors: EncErrors, onStrict, onReplace: untyped) =
  ## Dispatches an invalid-input event on the error handler:
  ## `onStrict` must raise; `ignore` does nothing.
  case errors
  of EncErrors.strict: onStrict
  of EncErrors.ignore: discard
  of EncErrors.replace: onReplace
  else: doAssert false, "unreachable: checked by checkErrors"

proc stripDecodeReplacement*(s: string): string =
  ## Approximates `ignore` for backends that can only replace.
  ## NOTE: also removes U+FFFD that genuinely exist in input.
  s.replace(DecodeReplacement, "")

template ptrAt*(s: cstring, i: int): cstring =
  cast[cstring](cast[int](s) + i)
template ptrAt*(s: string, i: int): cstring =
  ptrAt(cstring(s), i)
template ptrAt*(s: openArray[char], i: int): cstring =
  cast[cstring](addr s[i])

