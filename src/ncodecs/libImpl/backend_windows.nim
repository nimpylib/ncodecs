## Windows backend: MultiByteToWideChar / WideCharToMultiByte

import std/[unicode, oserrors]
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

proc multiByteToWideChar(codePage: int32, dwFlags: int32,
    lpMultiByteStr: cstring, cbMultiByte: cint,
    lpWideCharStr: cstring, cchWideChar: cint): cint {.
  stdcall, importc: "MultiByteToWideChar", dynlib: "kernel32".}
proc wideCharToMultiByte(codePage: int32, dwFlags: int32,
    lpWideCharStr: cstring, cchWideChar: cint,
    lpMultiByteStr: cstring, cbMultiByte: cint,
    lpDefaultChar: cstring, lpUsedDefaultChar: ptr int32): cint {.
  stdcall, importc: "WideCharToMultiByte", dynlib: "kernel32".}
proc getLastError(): int32 {.stdcall, importc: "GetLastError",
  dynlib: "kernel32".}

type
  Backend* = object
    codec: string
    errors: EncErrors
    cp: int32
  WinRes = tuple[ok: bool, data: string]

proc noDefaultCharCP(cp: int32): bool =
  ## code pages for which `lpDefaultChar`/`lpUsedDefaultChar` must be nil
  cp == CP_UTF8 or cp == 65000 or cp in 50220'i32..50229'i32 or
    cp in 57002'i32..57011'i32 or cp == 52936 or cp == 54936 or cp == 42

template twoPass(res: var string, sizeOf: untyped, call: untyped) =
  ## Windows APIs are called twice: first to query size (`dst`=nil, n=0),
  ## then to fill. `call` sees injected `dst` and `n`.
  block:
    var dst {.inject.}: cstring = nil
    var n {.inject.} = cint 0
    n = call
    if n == 0: raiseOSError(osLastError())
    res = newString(sizeOf)
    dst = cstring res
    if call == 0: raiseOSError(osLastError())

proc toWide(cp: int32, s: string, strict: bool): WinRes =
  ## returns ok=false on invalid input when `strict`
  if s.len == 0: return (true, "")
  if cp == CP_UTF16LE: return (true, s)
  var flags = if strict: MB_ERR_INVALID_CHARS else: 0'i32
  let probe = multiByteToWideChar(cp, flags, cstring s, cint s.len, nil, 0)
  if probe == 0:
    case getLastError()
    of ERROR_NO_UNICODE_TRANSLATION: return (false, "")
    of ERROR_INVALID_FLAGS: flags = 0  # some code pages reject the flag
    else: raiseOSError(osLastError())
  result.ok = true
  twoPass result.data, n * 2:
    multiByteToWideChar(cp, flags, cstring s, cint s.len, dst, n)

proc fromWide(cp: int32, w: string, errors: EncErrors): WinRes =
  ## returns ok=false if some char is unrepresentable and errors==strict
  if w.len == 0: return (true, "")
  if cp == CP_UTF16LE: return (true, w)
  var usedDef: int32 = 0
  let useDef = not noDefaultCharCP(cp)
  let flags = if useDef and errors != EncErrors.replace: WC_NO_BEST_FIT_CHARS
              else: 0'i32
  let defCh: cstring = if useDef: cstring(EncodeReplacement) else: nil
  let pUsed = if useDef: addr usedDef else: nil
  twoPass result.data, n:
    wideCharToMultiByte(cp, flags, cstring w, cint(w.len div 2),
      dst, n, defCh, pUsed)
  result.ok = usedDef == 0 or errors == EncErrors.replace

proc openBackend*(encoding: string, errors: EncErrors): Backend =
  let cp = cast[int32](nameToCodePage(encoding))
  if cp < 0 or cp in UnsupportedCPs:
    raise unknownEncoding(encoding)
  Backend(codec: encoding, errors: errors, cp: cp)

proc decodeImpl*(b: Backend, s: string): string =
  let (ok, w) = toWide(b.cp, s, b.errors == EncErrors.strict)
  if not ok: raise invalidDataError(b.codec, decoding = true)
  result = fromWide(CP_UTF8, w, EncErrors.replace).data
  if b.errors == EncErrors.ignore:
    # Windows API cannot tell where the bad bytes are
    result = stripDecodeReplacement result

proc encodeImpl*(b: Backend, s: string): string =
  let (ok, w) = toWide(CP_UTF8, s, b.errors == EncErrors.strict)
  if not ok: raise invalidDataError(b.codec, decoding = false)
  if b.errors == EncErrors.replace or noDefaultCharCP(b.cp):
    return fromWide(b.cp, w, EncErrors.replace).data
  var allOk: bool
  (allOk, result) = fromWide(b.cp, w, b.errors)
  if allOk: return
  # slow path: locate offending chars rune by rune
  result.setLen 0
  var pos = 0
  for r in s.runes:
    let rs = $r
    let (ok1, w1) = toWide(CP_UTF8, rs, false)
    let (ok2, d) = if ok1: fromWide(b.cp, w1, EncErrors.strict)
                   else: (false, "")
    if ok2: result.add d
    else:
      onBadInput b.errors:
        raise encodeErrorAt(b.codec, s, pos)
      do: result.add EncodeReplacement
    pos += rs.len

proc closeImpl*(b: Backend) = discard
