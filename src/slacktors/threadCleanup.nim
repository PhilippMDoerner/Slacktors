import chronos

proc destroyThreadVariables() =
  when defined(gcOrc):
    GC_fullCollect() # from orc.nim. Has no destructor.

  `=destroy`(getThreadDispatcher())

proc cleanupThread*() {.gcsafe, raises: [].}=
  ## Internally, this clears up known thread variables
  ## that were likely set to avoid memory leaks.
  ## May become unnecessary if https://github.com/nim-lang/Nim/issues/23165 ever gets fixed
  {.cast(gcsafe).}:
    try:
      destroyThreadVariables()
    except Exception as e:
      echo "Exception during cleanup: " & e.msg

