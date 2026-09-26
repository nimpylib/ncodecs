
template imp(name) {.dirty.} =
  import name as lib

import ./common
when defined(windows):
  imp backend_windows
else:
  imp backend_iconv
export lib except openBackend

const Js = defined(js)
when not Js:
  # js calls normalize itself as it needs that
  import pkg/py_locale_utf8_encoding/encoding_norm

proc openBackend*(encoding: string, errors: EncErrors): Backend =
  when not Js:
    # jslabel is available on all platform
    #  just meaning `-` is used instead of `_`
    let encoding = Py_normalize_encoding jslabel encoding
  return lib.openBackend(encoding, errors)

