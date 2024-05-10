import std/importutils
import taskpools
import ./actor

export taskpools

var POOL: Taskpool

proc runProc(actor: Actor) {.gcsafe, nimcall, raises: [].} =
  privateAccess(Actor)
  actor.command(
    actor.sourceMailboxes, 
    actor.targetMailboxes
  )

proc run*(actor: Actor) =
  POOL.spawn actor.runProc()

proc openPool*(size: int) =
  POOL = Taskpool.new(num_threads = size)

proc closePool*() =
  POOL.syncAll()
  POOL.shutDown()