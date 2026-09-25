# Package

version       = "0.1.0"
author        = "litlighilit"
description   = "like Lib/codecs of Python but only Nim side api"
license       = "MIT"
srcDir        = "src"
installExt    = @["nim"]
bin           = @["ncodecs"]
binDir        = "bin"

# Dependencies

requires "nim > 2.0.8"

var pylibPre = "https://github.com/nimpylib"
let envVal = getEnv("NIMPYLIB_PKGS_BARE_PREFIX")
if envVal != "": pylibPre = ""
#if pylibPre == Def: pylibPre = ""
elif pylibPre[^1] != '/':
  pylibPre.add '/'
template pylib(x, ver) =
  requires if pylibPre == "": x & ver
           else: pylibPre & x

pylib "pyerrors", " ^= 0.1.0"
pylib "jscompat", " ^= 0.1.9"


