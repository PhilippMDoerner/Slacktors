import threading/channels
import std/[options, isolation]
import chronicles

type Mailbox*[T] = ptr Chan[T]

proc newMailbox*[T](capacity: int): Mailbox[T] =
  let mailbox = createShared(Chan[T])
  mailbox[] = newChan[T](capacity)
  return mailbox
  
proc destroyMailbox*[T](mailbox: Mailbox[T]) =
  freeShared(mailbox)

proc send*[T](mailbox: Mailbox[T], value: T) = 
  mailbox[].send(
    unsafeIsolate(deepCopy(value))
  )

proc trySend*[T](mailbox: Mailbox[T], value: T): bool =
  return mailbox[].trySend(
    unsafeIsolate(deepCopy(value))
  )

proc recv*[T](mailbox: Mailbox[T]): T = mailbox[].recv()

proc tryRecv*[T](mailbox: Mailbox[T]): Option[T] =
  var msg: T
  let hasMsg = mailbox[].tryRecv(msg)
  if hasMsg:
    return some(msg)
  else:
    return none(T)

proc peek*[T](mailbox: Mailbox[T]): int = mailbox[].peek()

proc hasMessages*[T](mailbox: Mailbox[T]): bool = 
  let counter = mailbox.peek()
  notice "Mailbox was scanned for messages", mailboxType = $T, msgCount = counter
  mailbox.peek() > 0

iterator messages*[T](mailbox: Mailbox[T]): T =
  var msg: T
  while mailbox[].tryRecv(msg):
    yield msg