## Windows backend: MultiByteToWideChar / WideCharToMultiByte

import std/[unicode, oserrors, widestrs]
import std/encodings  # nameToCodePage
import ./common

const
  CP_UTF8 = 65001'i32
  CP_UTF16LE = 1200'i32
  UnsupportedCPs = [1201'i32, 12000, 12001]
  MB_ERR_INVALID_CHARS = 0x8'i32
  WC_NO_BEST_FIT_CHARS = 0x400'i32
  ERROR_INVALID_FLAGS = 1004'i32
  ERROR_NO_UNICODE_TRANSLATION = 1113'i32

var DefCP = CP_UTF8

proc nameToCodePageNum(encoding: string): int32 =
  let cp = cast[int32](nameToCodePage(encoding))
  if cp < 0 or cp in UnsupportedCPs:
    raise unknownEncoding(encoding)
  return cp

proc setDefaultEncoding*(encoding: string) =
  DefCP = nameToCodePageNum encoding

proc multiByteToWideChar(codePage: int32, dwFlags: int32,
    lpMultiByteStr: cstring|(ptr char), cbMultiByte: cint,
    lpWideCharStr: WideCString, cchWideChar: cint): cint {.
  stdcall, importc: "MultiByteToWideChar", dynlib: "kernel32".}
proc wideCharToMultiByte(codePage: int32, dwFlags: int32,
    lpWideCharStr: WideCString, cchWideChar: cint,
    lpMultiByteStr: cstring, cbMultiByte: cint,
    lpDefaultChar: cstring, lpUsedDefaultChar: ptr int32): cint {.
  stdcall, importc: "WideCharToMultiByte", dynlib: "kernel32".}
proc getLastError(): int32 {.stdcall, importc: "GetLastError",
  dynlib: "kernel32".}

type
  Backend* = ref object
    codec: string
    errors: EncErrors
    cp: int32
  Wide = WideCStringObj
    ## UTF-16 buffer (not relying on NUL terminator)

proc noDefaultCharCP(cp: int32): bool =
  ## code pages for which `lpDefaultChar`/`lpUsedDefaultChar` must be nil
  cp == CP_UTF8 or cp == 65000 or cp in 50220'i32..50229'i32 or
    cp in 57002'i32..57011'i32 or cp == 52936 or cp == 54936 or cp == 42

template data(w: Wide): WideCString =
  ## works whether `WideCStringObj` is an object (nimv2) or a ref
  w

template twoPass(DstT: typedesc, call: untyped, alloc: untyped) =
  ## Windows APIs are called twice: first to query size (`dst`=nil, n=0),
  ## then to fill into the buffer returned by `alloc` (which sees `n`).
  ## `call` sees injected `dst` and `n`.
  block:
    var dst {.inject.}: DstT = nil
    var n {.inject.} = cint 0
    n = call
    if n == 0: raiseOSError(osLastError())
    dst = alloc
    if call == 0: raiseOSError(osLastError())

using s: openArray[char]
proc toWide(cp: int32, s; strict: bool, w: var Wide): bool =
  ## returns false on invalid input when `strict`
  if s.len == 0: return true
  if cp == CP_UTF16LE:
    w = newWideCString(s.len div 2)
    if w.len > 0: copyMem(addr w.data[0], addr s[0], w.len * 2)
    return true
  var flags = if strict: MB_ERR_INVALID_CHARS else: 0'i32
  let probe = multiByteToWideChar(cp, flags, addr s[0], cint s.len, nil, 0)
  if probe == 0:
    case getLastError()
    of ERROR_NO_UNICODE_TRANSLATION: return false
    of ERROR_INVALID_FLAGS: flags = 0  # some code pages reject the flag
    else: raiseOSError(osLastError())
  twoPass WideCString,
      multiByteToWideChar(cp, flags, addr s[0], cint s.len, dst, n):
    w = newWideCString(n)
    w
  true

proc fromWide(cp: int32, w: Wide, errors: EncErrors, res: var string): bool =
  ## returns false if some char is unrepresentable and errors==strict
  res.setLen 0
  if w.len == 0: return true
  if cp == CP_UTF16LE:
    res = newString(w.len * 2)
    copyMem(addr res[0], addr w.data[0], res.len)
    return true
  var usedDef: int32 = 0
  let useDef = not noDefaultCharCP(cp)
  let flags = if useDef and errors != EncErrors.replace: WC_NO_BEST_FIT_CHARS
              else: 0'i32
  let defCh: cstring = if useDef: cstring(EncodeReplacement) else: nil
  let pUsed = if useDef: addr usedDef else: nil
  twoPass cstring,
      wideCharToMultiByte(cp, flags, w.data, cint w.len, dst, n, defCh, pUsed):
    res = newString(n)
    cstring res
  usedDef == 0 or errors == EncErrors.replace

proc openBackend*(encoding: string, errors: EncErrors): Backend =
  Backend(codec: encoding, errors: errors, cp: nameToCodePageNum(encoding))

proc decodeImpl*(b: Backend, s): string =
  var w: Wide
  if not toWide(b.cp, s, b.errors == EncErrors.strict, w):
    raise invalidDataError(b.codec, decoding = true)
  discard fromWide(DefCP, w, EncErrors.replace, result)
  if b.errors == EncErrors.ignore:
    # Windows API cannot tell where the bad bytes are
    result = stripDecodeReplacement result

proc encodeImpl*(b: Backend, s): string =
  var w: Wide
  if not toWide(DefCP, s, b.errors == EncErrors.strict, w):
    raise invalidDataError(b.codec, decoding = false)
  if b.errors == EncErrors.replace or noDefaultCharCP(b.cp):
    discard fromWide(b.cp, w, EncErrors.replace, result)
    return
  if fromWide(b.cp, w, b.errors, result): return
  # slow path: locate offending chars rune by rune
  result.setLen 0
  var pos = 0
  var d: string
  for r in s.runes:
    let rs = $r
    if toWide(DefCP, rs, false, w) and fromWide(b.cp, w, EncErrors.strict, d):
      result.add d
    else:
      onBadInput b.errors:
        raise encodeErrorAt(b.codec, s, pos)
      do: result.add EncodeReplacement
    pos += rs.len

proc closeImpl*(b: Backend) = discard

