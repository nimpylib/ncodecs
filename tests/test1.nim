
import std/unittest

import ncodecs
test "name normalization":
  let enc = initNCodecInfo("utf-8")
  check enc.name == "utf-8"

