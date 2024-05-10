import ./typeTable
import ./mailbox

export typeTable

type MailboxTable* = distinct TypeTable

proc hasMailbox*[T](table: MailboxTable, typ: typedesc[T]): bool =
  return TypeTable(table).hasKey(Mailbox[T])

proc `[]`*[T](table: MailboxTable, typ: typedesc[T]): Mailbox[T] =
  return TypeTable(table)[Mailbox[T]]

proc `[]=`*[T](table: var MailboxTable, typ: typedesc[T], mailbox: Mailbox[T]) =
  TypeTable(table)[Mailbox[T]] = mailbox