
import std/strformat
import std/parseopt
import std/syncio as nio
from std/terminal import isatty
import pkg/handy_sugars/assumes
import ./libImpl
import ./cli/[version, utils, helps]

proc closeIfNotTty(f: nio.File) =
  if not f.isatty: f.close
proc main*(from_code, to_code: string, errors = DefEncErrors;
           inputs: openArray[nio.File] = [nio.stdin], output: nio.File = nio.stdout
  ) =
  setDefaultEncoding from_code
  let enc = initNCodecInfo(to_code, errors)

  for input in inputs:
    while not input.endOfFile:
      let s = input.readLine
      output.writeLine enc.encode(s)
    input.closeIfNotTty
  enc.close()

proc exitWith(msg: string) {.noReturn.} =
  nio.stdout.write msg
  quit()

proc badOption(k: string) {.noReturn.} =
  let app = getAppName()
  quit appMsg fmt"""invalid option -- '{k}'
Try `{app} --help' or `{app} --usage' for more information
"""

proc main* =
  var
    inputs: seq[nio.File]
    errors = EncErrors.strict
    output = nio.stdout
    from_code, to_code = "utf-8"
  for (kind, k, v) in getopt(
    shortNoVal = {'?', 'h', 'c',    's',      'V',       'l'},
    longNoVal = @["help", "usage","slient", "version", "list"],
  ):
    case kind
    of cmdEnd: unreachable
    of cmdArgument: inputs.add open k
    of cmdLongOption, cmdShortOption:
      case k
      of "help", "?", "h": exitWith getHelp()
      of "usage": exitWith getUsage()
      of "c": errors = ignore
      of "s": discard #TODO:warn
      of "o", "output": output = open(v, fmWrite)
      of "f", "from-code": from_code = v
      of "t", "to-code": to_code = v
      #of "l", "list": TODO
      of "V", "version": exitWith getVersion()
      else: badOption k
  if inputs.len == 0:
    inputs.add nio.stdin
  try:
    main from_code, to_code, errors, inputs, output
  except CatchableError as e:
    quit appMsg e.msg
  output.closeIfNotTty

