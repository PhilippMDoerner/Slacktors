import std/atomics
import ./serverActorType
import chronicles
import taskpools

var IS_RUNNING*: Atomic[bool] ## \
## Global switch that controls whether threadServers keep running or shut down.
## Change this value to false to trigger shut down of all threads running
## ThreadButler default event-loops.
IS_RUNNING.store(true)

proc isRunning*(): bool = IS_RUNNING.load()
proc shutdownAllServers*() = IS_RUNNING.store(false)

proc shutdownServer*() =
  ## Triggers the graceful shut down of the thread-server this proc is called on.
  raise newException(KillError, "Shutdown")

proc runServerLoop(server: ServerActor) {.gcsafe.} =
  block serverLoop: 
    while isRunning():
      {.gcsafe}: 
        try:
          if not server.hasMessages():
            server.waitForSendSignal()
          
          server.processMessages()
          
        except KillError as e:
          server.gracefulShutdown()
          break serverLoop
          
        except CatchableError as e:
          error "Message caused exception", server = server, error = e[]

proc runServerTask*(actor: ServerActor) {.gcsafe, nimcall, raises: [].} =
  try:
    actor.runServerLoop()
  except Exception as e:
    error("Server crashed with exception: ", server = actor, error = e[])
  notice("Server finished", server = actor)

proc runIn*(actor: ServerActor, tp: Taskpool) =
  tp.spawn actor.runServerTask()