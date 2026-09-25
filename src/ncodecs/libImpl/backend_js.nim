## JS backend: decode with TextDecoder, encode with TextEncoder
## (utf-8 only for encoding)

import std/[tables, jsffi, strutils]
import pkg/jscompat/utils/[catchJsErr, jstypedarraysOps,
                           jsencodings, jstypedarrays]
import ./common

# NOTE: WHATWG's encoding list, which is also what JS's TextDecoder
# supports, overlaps with but is not the same as Python's codecs list.
const jsEncAliases = [
  ("utf-8", "utf-8"), ("utf8", "utf-8"), ("u8", "utf-8"),
  ("utf-16", "utf-16le"), ("utf16", "utf-16le"), ("utf-16le", "utf-16le"),
  ("ascii", "ascii"), ("us-ascii", "ascii"),
  ("latin-1", "iso-8859-1"), ("latin1", "iso-8859-1"),
  ("l1", "iso-8859-1"), ("iso-8859-1", "iso-8859-1"),
  ("iso8859-1", "iso-8859-1"), ("iso-8859-15", "iso-8859-15"),
  ("cp1250", "windows-1250"), ("cp1251", "windows-1251"),
  ("cp1252", "windows-1252"), ("cp1253", "windows-1253"),
  ("cp1254", "windows-1254"), ("cp1255", "windows-1255"),
  ("cp1256", "windows-1256"), ("cp1257", "windows-1257"),
  ("cp1258", "windows-1258"),
  ("windows-1250", "windows-1250"), ("windows-1251", "windows-1251"),
  ("windows-1252", "windows-1252"), ("windows-1253", "windows-1253"),
  ("windows-1254", "windows-1254"), ("windows-1255", "windows-1255"),
  ("windows-1256", "windows-1256"), ("windows-1257", "windows-1257"),
  ("windows-1258", "windows-1258"),
  ("shift-jis", "shift_jis"), ("shiftjis", "shift_jis"),
  ("sjis", "shift_jis"), ("shift_jis", "shift_jis"),
  ("euc-jp", "euc-jp"), ("eucjp", "euc-jp"),
  ("euc-kr", "euc-kr"), ("euckr", "euc-kr"),
  ("koi8-r", "koi8-r"), ("koi8r", "koi8-r"), ("koi8-u", "koi8-u"),
  ("gb2312", "gbk"), ("gbk", "gbk"), ("gb18030", "gb18030"),
  ("big5", "big5"), ("big5hkscs", "big5-hkscs"), ("big5-hkscs", "big5-hkscs"),
  ("mac-roman", "x-mac-roman"), ("macroman", "x-mac-roman"),
  ("iso-2022-jp", "iso-2022-jp"), ("hz-gb-2312", "hz-gb-2312"),
  ("utf-16be", "utf-16be"), ("utf-16-be", "utf-16be"),
].toTable

type Backend* = object
  codec: string
  errors: EncErrors
  isUtf8: bool
  dec: TextDecoder
  enc: TextEncoder

template jsTry(body; onFail: untyped) =
  var failed = false
  jsTryCatchE:
    body
  do:
    failed = true
  if failed: onFail

proc normalizeJsEncoding(encoding: string): string =
  result = encoding.replace('_', '-').toLowerAscii
  jsEncAliases.withValue result, val:
    result = val

proc jsBytesToString(b: TypedArray[uint8, auto]): string =
  for i in 0..<b.len:
    result.add b[i].char

proc openBackend*(encoding: string, errors: EncErrors): Backend =
  let enc = normalizeJsEncoding(encoding)
  result = Backend(codec: encoding, errors: errors, isUtf8: enc == "utf-8")
  jsTry:
    result.dec = newTextDecoder(cstring enc,
      TextDecoderOptions{fatal: errors == EncErrors.strict})
  do: raise unknownEncoding(encoding)
  result.enc = newTextEncoder()

proc encodeImpl*(b: Backend, s: string): string =
  if not b.isUtf8:
    raise newException(ValueError,
      "encoding " & b.codec & " does not support encode on js backend")
  jsBytesToString(b.enc.encode(cstring s))

proc decodeImpl*(b: Backend, s: string): string =
  var res: cstring
  jsTry:
    res = b.dec.decode(toUint8Array(s))
  do: raise invalidDataError(b.codec, decoding = true)
  result = $res
  if b.errors == EncErrors.ignore:
    result = stripDecodeReplacement result

proc closeImpl*(b: Backend) = discard
