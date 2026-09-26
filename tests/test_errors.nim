import std/unittest
import ncodecs

test "decode":
  check initNCodecInfo("latin1").decode("\xe9") == "é"
  expect UnicodeDecodeError: discard initNCodecInfo("utf-8").decode("a\xffb")
  expect UnicodeDecodeError: discard initNCodecInfo("utf-8").decode("a\xe4")
  check initNCodecInfo("utf-8", "ignore").decode("a\xffb") == "ab"
  check initNCodecInfo("utf-8", "replace").decode("a\xffb\xe4") == "a\uFFFDb\uFFFD"
  check initNCodecInfo("ascii", "replace").decode("a\x80") == "a\uFFFD"

test "encode":
  check initNCodecInfo("latin1").encode("é") == "\xe9"
  expect UnicodeEncodeError:
    discard initNCodecInfo("ascii").encode("aé")
  check initNCodecInfo("ascii", "ignore").encode("aéb") == "ab"
  check initNCodecInfo("ascii", "replace").encode("aé中b") == "a??b"
  check initNCodecInfo("UTF-16LE", "replace").encode("a") == "a\0"
  when not defined(js):  # JS has no TextEncoder for non-utf-8
    check initNCodecInfo("iso-2022-jp", "replace").encode("日é本") ==
      initNCodecInfo("iso-2022-jp").encode("日?本")

test "lookup":
  expect LookupError: discard initNCodecInfo("nope")
  expect LookupError: discard initNCodecInfo("utf-8", "namereplace")
