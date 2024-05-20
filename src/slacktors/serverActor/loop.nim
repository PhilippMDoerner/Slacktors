import std/atomics
import ./serverActorType
import ../threadCleanup
import ../pool/pool
import chronos
import chronicles

var IS_RUNNING*: Atomic[bool] ## \
## Global switch that controls whether threadServers keep running or shut down.
## Change this value to false to trigger shut down of all threads running
## ThreadButler default event-loops.
IS_RUNNING.store(true)

proc isGlobalRunning*(): bool = IS_RUNNING.load()
proc shutdownAllServers*() =  IS_RUNNING.store(false)

proc runServerLoop(server: ServerActor) {.gcsafe.} =
  var server = server
  block serverLoop: 
    while isGlobalRunning() and server.isRunning():
      {.gcsafe}: 
        try:
          if not server.hasMessages():
            server.waitForSendSignal()
          
          server.processMessages()
          
        except CatchableError as e:
          error "Message caused exception", server = server, error = e[]
  
proc runServerTask*(actor: ServerActor) {.gcsafe, nimcall, raises: [].} =
  let serverName = $actor
  block:
    try:
      actor.runServerLoop()
    except Exception as e:
      error("Server crashed with exception: ", server = serverName, error = e[])
    finally:
      try:
        {.gcsafe.}: actor.gracefulShutdown()
      except ShutdownError as e:
        error("Failed to gracefully shut down server: ", server = serverName, error = e[])
  threadCleanup.cleanupThread()
proc runIn*(actor: ServerActor, tp: ThreadPool) =
  tp.spawn actor.runServerTask()