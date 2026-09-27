
import std/macros
macro tryReplLastArg*(call; args: varargs[untyped]): untyped =
  args.expectLen 1
  let arg = args[0]
  arg.expectKind nnkExprEqExpr
  let v = arg[1]
  let call1 = call.copyNimTree
  call1[^1] = arg
  result = quote do:
    when declared(`v`):
      `call1`
    else:
      `call`

