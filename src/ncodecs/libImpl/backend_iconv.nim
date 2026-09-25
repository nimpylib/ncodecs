## POSIX backend: iconv

import std/[unicode, oserrors]
from std/posix import errno, E2BIG, EILSEQ, EINVAL
import ./common

when defined(macosx) or defined(openbsd) or defined(haiku):
  {.passL: "-liconv".}

type Iconv = pointer  ## iconv_t
proc iconvOpen(tocode, fromcode: cstring): Iconv {.
  importc: "iconv_open", header: "<iconv.h>".}
proc iconvClose(c: Iconv): cint {.
  importc: "iconv_close", header: "<iconv.h>", discardable.}
proc iconv(c: Iconv, inbuf: ptr cstring, inbytesLeft: ptr csize_t,
    outbuf: ptr cstring, outbytesLeft: ptr csize_t): csize_t {.
  importc: "iconv", header: "<iconv.h>".}

const
  IconvErr = high(csize_t)
  InvalidCd = cast[Iconv](-1)
  InnerEnc = "UTF-8"

type
  Backend* = object
    codec: string
    errors: EncErrors
    decCd, encCd: Iconv
  OutBuf = object
    data: string
    pos: int

proc feed(cd: Iconv, o: var OutBuf, inp: cstring, inLen: int,
    flush = false): tuple[consumed: int, err: cint] =
  ## Feeds `inp[0..<inLen]` (or flushes shift state if `flush`) into `cd`,
  ## growing `o` on demand.
  ## Stops at the first EILSEQ/EINVAL, returning bytes consumed and errno.
  var src = inp
  var left = csize_t inLen
  while true:
    if o.pos >= o.data.len: o.data.setLen(o.data.len * 2 + 16)
    var dst = o.data.ptrAt(o.pos)
    var outLeft = csize_t(o.data.len - o.pos)
    let r =
      if flush: iconv(cd, nil, nil, addr dst, addr outLeft)
      else: iconv(cd, addr src, addr left, addr dst, addr outLeft)
    o.pos = o.data.len - outLeft.int
    if r != IconvErr:
      return (inLen - left.int, 0.cint)
    let e = errno
    if e == E2BIG:
      o.data.setLen(o.data.len * 2 + 16)
    elif e == EILSEQ or e == EINVAL:
      return (inLen - left.int, e)
    else:
      raiseOSError(OSErrorCode e)

proc feed(cd: Iconv, o: var OutBuf, s: string): cint =
  feed(cd, o, cstring s, s.len).err

proc add(o: var OutBuf, s: string) =
  if o.pos + s.len > o.data.len: o.data.setLen(o.pos + s.len + 16)
  copyMem(addr o.data[o.pos], cstring(s), s.len)
  o.pos += s.len

proc convert(b: Backend, s: string, isDecode: bool): string =
  let cd = if isDecode: b.decCd else: b.encCd
  discard iconv(cd, nil, nil, nil, nil)  # reset shift state
  var o = OutBuf(data: newString(s.len + 16))
  var pos = 0
  while pos < s.len:
    let (n, e) = feed(cd, o, s.ptrAt(pos), s.len - pos)
    pos += n
    if e == 0: break
    let truncated = e == EINVAL  # incomplete sequence at end
    let badLen =
      if truncated: s.len - pos
      elif isDecode: 1
      else: max(1, s.runeLenAt(pos))
    onBadInput b.errors:
      let reason =
        if truncated: "unexpected end of data"
        elif isDecode: "invalid start byte"
        else: "character maps to <undefined>"
      if isDecode: raise decodeErrorAt(b.codec, s, pos, badLen, reason)
      else: raise encodeErrorAt(b.codec, s, pos, reason)
    do:
      if isDecode: o.add DecodeReplacement
      # feed via `cd` so stateful encodings keep a consistent shift state
      elif feed(cd, o, EncodeReplacement) != 0:
        raise encodeErrorAt(b.codec, s, pos,
          "replacement character is unencodable")
    pos += badLen
  discard feed(cd, o, nil, 0, flush = true)
  result = move o.data
  result.setLen o.pos

proc openBackend*(encoding: string, errors: EncErrors): Backend =
  result = Backend(codec: encoding, errors: errors,
    decCd: iconvOpen(InnerEnc, cstring encoding),
    encCd: iconvOpen(cstring encoding, InnerEnc))
  if result.decCd == InvalidCd or result.encCd == InvalidCd:
    for cd in [result.decCd, result.encCd]:
      if cd != InvalidCd: iconvClose cd
    raise unknownEncoding(encoding)

proc encodeImpl*(b: Backend, s: string): string = b.convert(s, isDecode = false)
proc decodeImpl*(b: Backend, s: string): string = b.convert(s, isDecode = true)

proc closeImpl*(b: Backend) =
  iconvClose b.encCd
  iconvClose b.decCd
