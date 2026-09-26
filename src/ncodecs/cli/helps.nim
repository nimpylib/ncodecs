
import std/strformat
import ./utils

const
  repoUrl{.strdefine.} = ""

proc getFooter: string =
  if repoUrl.len > 0:
    let issueUrl = repoUrl & "/issues/"
    return '\n' & fmt"""
For bug reporting instructions, please see:
<{issueUrl}>
"""

proc getHelp*: string =
  let app = getAppName()
  fmt"""
Usage: {app} [OPTION...] [FILE...]
Convert encoding of given files from one encoding to another.

 Input/Output format specification:
  -f, --from-code=NAME       encoding of original text
  -t, --to-code=NAME         encoding for output

 Information:
  -l, --list                 list all known coded character sets

 Output control:
  -c                         omit invalid characters from output
  -o, --output=FILE          output file
  -s, --silent               suppress warnings
      --verbose              print progress information

  -?, --help                 Give this help list
      --usage                Give a short usage message
  -V, --version              Print program version

Mandatory or optional arguments to long options are also mandatory or optional
for any corresponding short options.
{getFooter()}"""

proc getUsage*: string =
  let app = getAppName()
  fmt"""
Usage: {app} [-lcs?V] [-f NAME] [-t NAME] [-o FILE] [--from-code=NAME]
            [--to-code=NAME] [--list] [--output=FILE] [--silent] [--verbose]
            [--help] [--usage] [--version] [FILE...]
"""

