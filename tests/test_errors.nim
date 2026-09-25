import std/unittest
import ncodecs

test "decode":
  check initNCodecInfo("latin1").decode("\xe9").data == "é"
  expect UnicodeDecodeError: discard initNCodecInfo("utf-8").decode("a\xffb")
  expect UnicodeDecodeError: discard initNCodecInfo("utf-8").decode("a\xe4")
  check initNCodecInfo("utf-8", "ignore").decode("a\xffb").data == "ab"
  check initNCodecInfo("utf-8", "replace").decode("a\xffb\xe4").data == "a\uFFFDb\uFFFD"
  check initNCodecInfo("ascii", "replace").decode("a\x80").data == "a\uFFFD"

test "encode":
  check initNCodecInfo("latin1").encode("é").data == "\xe9"
  expect UnicodeEncodeError:
    discard initNCodecInfo("ascii").encode("aé")
  check initNCodecInfo("ascii", "ignore").encode("aéb").data == "ab"
  check initNCodecInfo("ascii", "replace").encode("aé中b").data == "a??b"
  check initNCodecInfo("UTF-16LE", "replace").encode("a").data == "a\0"
  when not defined(js):  # JS has no TextEncoder for non-utf-8
    check initNCodecInfo("iso-2022-jp", "replace").encode("日é本").data ==
      initNCodecInfo("iso-2022-jp").encode("日?本").data

test "lookup":
  expect LookupError: discard initNCodecInfo("nope")
  expect LookupError: discard initNCodecInfo("utf-8", "namereplace")
