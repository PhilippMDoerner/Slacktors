import std/[atomics, macros, strformat]
import chronos
import chronos/threadsync
import ../mailboxTable
import chronicles

type ShutdownError* = object of CatchableError ## Indicates an issue that happened during shutdown.
type SendingError* = object of ValueError ## Thrown when a message was attempted to be sent to a recipient that cannot possibly receive it.

type 
  ServerActorObj* = object
    name: string
    sources: MailboxTable
    targets: MailboxTable
    processProc: proc(server: ServerActor) {.nimcall, raises: [].} # Processing is done by capturing "process(value: T)" overloads
    hasMessagesProc: proc(mailboxes: MailboxTable): bool {.nimcall, gcsafe.}
    signalReceiver: ThreadSignalPtr ## For internal usage only. Signaller to wake up thread from low power state.
    destructorProc: proc(server: ServerActor) {.nimcall, raises: [].}
    isRunning: Atomic[bool]

  ServerActor* = ptr ServerActorObj

proc `$`*(server: ServerActor): string = server.name

proc sendWakeupSignalTo*(server: ServerActor) =
  let response = server.signalReceiver.fireSync()
  let hasSentSignal = response.isOk()
  if not hasSentSignal:
    notice "Failed to wake up server: ", targetServer = server.name

proc isRunning*(server: var ServerActor): bool = server.isRunning.load()

proc shutdownServer*(server: var ServerActor) =
  ## Triggers the graceful shut down of the thread-server this proc is called on.
  trace "Starting shutdown of server", server = server.name
  server.isRunning.store(false)
  server.sendWakeupSignalTo()

proc waitForSendSignal*(server: ServerActor) = 
  ## Causes the server to work through its remaining async-work
  ## and go into a low powered state afterwards. Receiving a signal
  ## will wake the server up again.
  debug "Going to sleep", server = server.name
  waitFor server.signalReceiver.wait()
  debug "Waking up", server = server.name

proc processMessages*(actor: ServerActor) = 
  actor.processProc(actor)

proc hasMessages*(actor: ServerActor): bool = 
  return actor.hasMessagesProc(actor.sources)

proc gracefulShutdown*(server: ServerActor) =
  let serverName = $server
  notice "Regular shut down of server started", server = serverName
  server.processMessages() # Process remaining messages
  let closeResult = server.signalReceiver.close()
  if closeResult.isErr():
    raise newException(ShutdownError, closeResult.error)
  
  server.destructorProc(server)
  freeShared(server)
  notice "Regular shut down of server ended", server = serverName

proc sendTo*[T](value: T, server: ServerActor) =
  debug "trySend  : Thread => Mailbox", server = server.name, msgTyp = $T
  try:
    server.sources[T].send(value)
    server.sendWakeupSignalTo()
  
  except KeyError as e:
    raise newException(SendingError, fmt"The server '{server.name}' does not have a mailbox for type '{$T}'. ", parentException = e)
  
  except CatchableError as e:
    raise newException(SendingError, "Failed to send message to server " & server.name, parentException = e)

proc trySendTo*[T](value: T, server: ServerActor): bool =
  debug "trySend  : Thread => Mailbox", server = server.name, msgTyp = $T
  try:
    let success = server.sources[T].trySend(value)
    server.sendWakeupSignalTo()
    return success
  except KeyError as e:
    raise newException(SendingError, fmt"The server '{server.name}' does not have a mailbox for type '{$T}'. ", parentException = e)
  
  except CatchableError as e:
    raise newException(SendingError, "Failed to send message to server " & server.name, parentException = e)