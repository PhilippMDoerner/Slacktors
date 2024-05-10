import std/[asyncdispatch, options]
import ./mailboxTable
import ./mailbox
import ./threadCleanup

export mailboxTable

type Actor* = object
  targetMailboxes: MailboxTable
  sourceMailboxes: MailboxTable
  command: proc(sources, targets: MailboxTable) {.nimcall, gcsafe, raises: [].}

proc defaultOnError(e: ref Exception) {.nimcall, gcsafe, raises:[].} = discard

template newActor*(
  runProc: proc(sources: MailboxTable, targets: MailboxTable) {.nimcall, gcsafe.},
  onError: proc(error: ref Exception) {.nimcall, gcsafe, raises: [].} = defaultOnError
): Actor =
  block:
    proc command(sources, targets: MailboxTable) {.nimcall, gcsafe, raises: [].} =
      try:
        runProc(sources, targets)
      except Exception as e:
        onError(e)
      finally:
        threadCleanup.cleanupThread()
        
    Actor(command: command)

proc hasTarget*[T](actor: Actor, targetTyp: typedesc[T]): bool =
  return actor.targetMailboxes.hasMailbox(T)

proc addTarget*[T](actor: var Actor, mailbox: Mailbox[T]) =
  actor.targetMailboxes[T] = mailbox
  
proc getTarget*[T](actor: Actor, typ: typedesc[T]): Option[Mailbox[T]] =
  if actor.hasTarget(T):
    let value = actor.targetMailboxes[T]
    return some(value)
  else:
    return none(Mailbox[T])

proc hasSource[T](actor: Actor, sourceTyp: typedesc[T]): bool =
  return actor.sourceMailboxes.hasMailbox(T)

proc addSource*[T](actor: var Actor, mailbox: Mailbox[T]) =
  actor.sourceMailboxes[T] = mailbox
  
proc getSource*[T](actor: Actor, typ: typedesc[T]): Option[Mailbox[T]] =
  if actor.hasSource(T):
    let value = actor.sourceMailboxes[T]
    return some(value)
  else:
    return none(Mailbox[T])

when not defined(globalpool):
  import taskpools

  proc run*(actor: Actor) {.gcsafe, nimcall, raises: [].} =
    actor.command(
      actor.sourceMailboxes, 
      actor.targetMailboxes
    )

  proc runIn*(actor: Actor, tp: Taskpool) =
    tp.spawn actor.run()

else:
  import pool