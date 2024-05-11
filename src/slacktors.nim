import std/os
import taskpools
import ./slacktors/[mailbox, actor, serverActor]
export mailbox
export actor

when isMainModule:
  ## Dummy Example Code
  let threads = 2

  type A = ref object
    name: string

  proc run(sources: MailboxTable, targets: MailboxTable) =
    echo "Start run"
    sleep(1000)
    for msg in sources[A].messages:
      echo msg.repr

  var act = newActor(
    run, 
    proc(e: ref Exception) {.nimcall, gcsafe, raises:[].} = 
      echo "Error"
  )

  let source = newMailbox[A](5)
  act.addSource(source)

  when defined(globalpool):
    import ./slacktors/pool
    openPool(size = threads)
    act.run()
  else:
    var tp = Taskpool.new(num_threads = threads)
    act.runIn(tp)

  source.send(A(name: "test"))
  source.send(A(name: "test"))
  source.send(A(name: "test"))
  echo "Post send"

  when defined(globalpool):
    closePool()
  else:
    tp.syncAll()
    tp.shutDown()