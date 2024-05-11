import std/[atomics, macros]
import chronos
import chronos/threadsync
import ../mailboxTable
import chronicles

type ShutdownError* = object of CatchableError ## A custom error. Indicates an issue that happened during shutdown.

type ServerActor* = object
  name*: string
  sources: MailboxTable
  targets: MailboxTable
  processProc: proc(server: ServerActor) {.nimcall.} # Processing is done by capturing "process(value: T)" overloads
  hasMessagesProc: proc(mailboxes: MailboxTable): bool {.nimcall, gcsafe.}
  signalReceiver: ThreadSignalPtr ## For internal usage only. Signaller to wake up thread from low power state.

proc sendWakeupSignalTo*(server: ServerActor) =
  let response = server.signalReceiver.fireSync()
  let hasSentSignal = response.isOk()
  if not hasSentSignal:
    notice "Failed to wake up threadServer: ", name = server.name


proc waitForSendSignal*(server: ServerActor) = 
  ## Causes the server to work through its remaining async-work
  ## and go into a low powered state afterwards. Receiving a signal
  ## will wake the server up again.
  notice "Going to sleep", serverName = server.name
  waitFor server.signalReceiver.wait()
  notice "Waking up", serverName = server.name

proc processMessages*(actor: ServerActor) = 
  actor.processProc(actor)

proc hasMessages*(actor: ServerActor): bool = 
  return actor.hasMessagesProc(actor.sources)

proc gracefulShutdown*(server: ServerActor) =
  notice "Regular shut down of server started", serverName = server.name
  server.processMessages() # Process remaining messages
  let closeResult = server.signalReceiver.close()
  if closeResult.isErr():
    raise newException(ShutdownError, closeResult.error)
  notice "Regular shut down of server ended", serverName = server.name