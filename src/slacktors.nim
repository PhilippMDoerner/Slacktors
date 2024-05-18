import std/os
import ./slacktors/[mailbox, actor, serverActor]
import chronos
import chronos/threadsync
import chronicles
export mailbox
export actor
import ./slacktors/globalpool

## TODO:
## - Fix memory leaks:
##    - Waiting for signal: waitFor signalReceiver.wait() (serverActorType 4)
##    - When sending a deepcopy somehow (mailbox 18)
## 
## One solution might be to just forego exceptions entirely. To do that, remove all the killer exception stuff and move ServerActor towards being a ptr type

when isMainModule:
  ## SIMPLE ACTOR EXAMPLE
  # let threads = 2

  # type A = ref object
  #   name: string

  # proc run(sources: MailboxTable, targets: MailboxTable) =
  #   echo "Start run"
  #   sleep(1000)
  #   for msg in sources[A].messages:
  #     echo msg.repr

  # var act = newActor(
  #   run, 
  #   proc(e: ref Exception) {.nimcall, gcsafe, raises:[].} = 
  #     echo "Error"
  # )

  # let source = newMailbox[A](5)
  # act.addSource(source)

  # when defined(globalpool):
  #   import ./slacktors/globalpool
  #   openPool(size = threads)
  #   act.run()
  # else:
  #   var tp = ThreadPool.new(num_threads = threads)
  #   act.runIn(tp)

  # source.send(A(name: "test"))
  # source.send(A(name: "test"))
  # source.send(A(name: "test"))
  # echo "Post send"

  # when defined(globalpool):
  #   closePool()
  # else:
  #   tp.syncAll()
  #   tp.shutDown()
    
    
  # SERVER EXAMPLE
  type KillMsg = distinct int
  proc `$`(x: KillMsg): string = $int(x)

  proc process(server: ServerActor, x: KillMsg) = 
    var server = server
    server.shutdownServer()
  proc process[T](server: ServerActor, x: T) = discard
  proc processAsync(server: ServerActor, x: int) {.async.} =
    echo "Intmsg"
    sleep(50)
    echo "Laterecho"
  
  proc process(server: ServerActor, x: int) =
    asyncSpawn server.processAsync(x)

  var server: ServerActor = initServerActor(5, "Jabrody", int, string, float, KillMsg)
  var tp = ThreadPool.new(num_threads = 2)
  server.runIn(tp)

  for x in 0..4:
    sleep(1)
    x.sendTo(server)
    ($x).sendTo(server)
    (x.float).sendTo(server) 

  sleep(3000)
  (0.KillMsg).sendTo(server)
  echo "Do da shutdown ?"
  tp.shutDown()