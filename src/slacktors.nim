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
##    - When sending a deepcopy somehow (mailbox 18)
##      - That one might be a problem of the channel not being empty (?)
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
  import std/strutils
  
  type A = ref object
  type MyObj = ref object
    name: string
      
  proc process(server: ServerActor, x: MyObj)=
    sleep(50)
    echo "Received MyObj message"

  var server: ServerActor = initServerActor(5, "Jabrody", MyObj)
  var tp = ThreadPool.new(num_threads = 2)
  server.runIn(tp)
  var a = A()
  let msg = MyObj(name: "blablabla".repeat(20))
  for x in 0..1:
    msg.sendTo(server)
  
  sleep(2_000)
  server.shutDownServer()
  tp.shutDown()