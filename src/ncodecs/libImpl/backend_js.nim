## JS backend: decode with TextDecoder, encode with TextEncoder
## (utf-8 only for encoding)

import std/[tables, jsffi, strutils, unicode]
import pkg/jscompat/utils/[catchJsErr, jstypedarraysOps,
                           jsencodings]
import pkg/py_locale_utf8_encoding/[ascii_utils, encoding_norm]
import ./common

proc setDefaultEncoding*(encoding: string) {.error: "not supported on js backend".}

# NOTE: WHATWG's encoding list, which is also what JS's TextDecoder
# supports, subset of Python's codecs list.
var jsEncAliases = {
  # we must contain normalized `JsKind` encoding name first.
  # ---
  "utf": "utf-8", "utf8": "utf-8", "cp65001": "utf-8",
  # ascii is also set in below
  "8859": "latin1", "latin": "latin1",  # latin1
  "utf-16-le": "utf-16le",
  "utf-16-be": "utf-16be",

  # the following is normal alias
  # ---
  "u8": "utf-8",
  "shiftjis": "shift_jis",
  "eucjp": "euc-jp",
  "euckr": "euc-kr",
  "koi8r": "koi8-r",
  "mac-roman": "x-mac-roman", "macroman": "x-mac-roman",
  "iso2022jp": "iso-2022-jp",
  "utf-16-be": "utf-16be",
}.toTable

for i in ascii_aliases:
  jsEncAliases[i] = "ascii"
  # we handles ascii specially,
  #  unlike js TextDecoder which mixes ascii and latin1

type
  JsKind = enum
    jkWhatwg   ## TextDecoder; encode only if utf-8
    jkUtf8
    jkAscii    ## native: WHATWG maps "ascii" to windows-1252
    jkLatin1   ## native: WHATWG maps "iso-8859-1" to windows-1252
    jkUtf16le  ## TextDecoder for decode, native encode
    jkUtf16be
  Backend* = object
    codec: string
    errors: EncErrors
    kind: JsKind
    dec: TextDecoder
# NOTE: Js's TextEncoder only support utf-8. So it's no need to use it.

const NativeSingleByte = {jkAscii, jkLatin1}

template jsTry(body; onFail: untyped) =
  var failed = false
  jsTryCatchE:
    body
  do:
    failed = true
  if failed: onFail

proc normalizeJsEncoding(encoding: string): string =
  result = Py_normalize_encoding jsLabel encoding
  jsEncAliases.withValue result, val:
    result = val[]

proc toKind(enc: string): JsKind =
  case enc
  of "utf-8": jkUtf8
  of "ascii": jkAscii
  of "latin1": jkLatin1
  of "utf-16le": jkUtf16le
  of "utf-16be": jkUtf16be
  else: jkWhatwg

func maxCode(k: JsKind): int =
  if k == jkAscii: 0x7F else: 0xFF

proc openBackend*(encoding: string, errors: EncErrors): Backend =
  let enc = normalizeJsEncoding(encoding)
  result = Backend(codec: encoding, errors: errors, kind: toKind(enc))
  if result.kind notin NativeSingleByte:
    jsTry:
      result.dec = newTextDecoder(cstring enc,
        TextDecoderOptions{fatal: errors == EncErrors.strict})
    do: raise unknownEncoding(encoding)

proc addUtf16(res: var string, u: int, bigEndian: bool) =
  let (lo, hi) = (char(u and 0xFF), char(u shr 8))
  if bigEndian: res.add hi; res.add lo
  else: res.add lo; res.add hi

proc encodeImpl*(b: Backend, s: string): string =
  case b.kind
  of jkUtf8:
    let pos = validateUtf8 s
    if pos < 0:
      result = newString(s.len)
      for i, c in s: result[i] = c
      return
    raise encodeErrorAt(b.codec, s, pos, "invalid utf8 byte")
  of jkUtf16le, jkUtf16be:
    let be = b.kind == jkUtf16be
    for r in s.runes:
      var c = r.int
      if c > 0xFFFF:
        c -= 0x10000
        result.addUtf16(0xD800 or (c shr 10), be)
        result.addUtf16(0xDC00 or (c and 0x3FF), be)
      else: result.addUtf16(c, be)
  of jkAscii, jkLatin1:
    let hi = b.kind.maxCode
    var pos = 0
    for r in s.runes:
      if r.int <= hi: result.add cast[char](r)
      else:
        onBadInput b.errors:
          raise encodeErrorAt(b.codec, s, pos,
            "ordinal not in range(" & $(hi+1) & ")")
        do: result.add EncodeReplacement
  of jkWhatwg:
    raise newException(ValueError,
      "encoding " & b.codec & " does not support encode on js backend")

proc decodeImpl*(b: Backend, s: string): string =
  if b.kind in NativeSingleByte:
    let hi = b.kind.maxCode
    for i, c in s:
      if c.int <= hi: result.add Rune(c.int)
      else:
        onBadInput b.errors:
          raise decodeErrorAt(b.codec, s, i, 1,
            "ordinal not in range(" & $(hi+1) & ")")
        do: result.add DecodeReplacement
    return
  var res: cstring
  jsTry:
    res = b.dec.decode(toUint8Array(s))
  do: raise invalidDataError(b.codec, decoding = true)
  result = $res
  if b.errors == EncErrors.ignore:
    result = stripDecodeReplacement result

proc closeImpl*(b: Backend) = discard
