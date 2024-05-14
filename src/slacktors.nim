import std/os
import taskpools
import ./slacktors/[mailbox, actor, serverActor]
import chronos
import chronos/threadsync
import chronicles
export mailbox
export actor

when isMainModule:
  ## SIMPLE ACTOR EXAMPLE
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
    
    
  # SERVER EXAMPLE
  type KillMsg = distinct int
  proc `$`(x: KillMsg): string = $int(x)

  proc process(server: ServerActor, x: KillMsg) = shutdownServer()
  proc process[T](server: ServerActor, x: T) = discard
  proc processAsync(server: ServerActor, x: int) {.async.} =
    notice "Intmsg"
    sleep(50)
    notice "Laterecho"
  proc process(server: ServerActor, x: int) =
    asyncCheck server.processAsync(x)

  var server: ServerActor = initServerActor(5, "Jabrody", int, string, float, KillMsg)
  var tp = Taskpool.new(num_threads = 2)
  server.runIn(tp)
  server.runIn(tp)

  for x in 0..4:
    sleep(1)
    x.sendTo(server)
    ($x).sendTo(server)
    (x.float).sendTo(server) 

  sleep(3000)
  (0.KillMsg).sendTo(server)

  tp.syncAll()
  tp.shutDown()