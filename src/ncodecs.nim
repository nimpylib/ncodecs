
import ./ncodecs/libImpl
export libImpl

when isMainModule:
  import ./ncodecs/cli
  main()

