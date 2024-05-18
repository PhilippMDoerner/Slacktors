import std/importutils
import ./pool/pool
import ./actor

export pool

var POOL: ThreadPool

proc runProc(actor: Actor) {.gcsafe, nimcall, raises: [].} =
  privateAccess(Actor)
  actor.command(
    actor.sourceMailboxes, 
    actor.targetMailboxes
  )

proc run*(actor: Actor) =
  POOL.spawn actor.runProc()

proc openPool*(size: int) =
  POOL = ThreadPool.new(numThreads = size)

proc closePool*() =
  POOL.shutDown()
