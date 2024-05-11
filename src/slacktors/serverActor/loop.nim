import std/atomics
import ./serverActorType
import chronicles
import taskpools

type KillError* = object of CatchableError ## A custom error. Throwing this will gracefully shut down the server

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
      if not server.hasMessages():
        server.waitForSendSignal()
      
      {.gcsafe}: 
        try:
          server.processMessages()
          
        except KillError as e:
          server.gracefulShutdown()
          break serverLoop
          
        except CatchableError as e:
          error "Message caused exception", error = e[]

proc runServerTask*(actor: ServerActor) {.gcsafe, nimcall, raises: [].} =
  try:
    actor.runServerLoop()
  except Exception as e:
    error("Server crashed with exception: ", error = e[])

proc runIn*(actor: ServerActor, tp: Taskpool) =
  tp.spawn actor.runServerTask()