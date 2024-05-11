import ./serverActorType
import chronos
import chronos/threadsync
import std/[importutils, sequtils, strutils, strformat, macros]

export importutils

proc generateInternalProcessMessages(types: NimNode): NimNode =
  ## Generates a proc `processMessages` for processing all messages in a given 
  ## MailboxTable instance.
  ## ```
  ## proc(server: ServerActor, mailboxes: MailboxTable) =
  ##   --- Repeat for each type - start ---
  ##   for msg in mailboxes[typ].messages:
  ##     try:
  ##       server.process(msg)
  ##     except KillError as e:
  ##       raise e
  ##     except CatchableError as e:
  ##       error "Message caused exception", msg = msg, error = e.repr
  ##   --- Repeat for each type - end ---
  ## ```
  ## Requires each msg type to have a defined proc: proc process(x: <TYPE>) 
  result = newProc(procType = nnkLambda)
  let server = ident("server")
  let serverParam = newIdentDefs(
    server, ident("ServerActor")
  )
  result.params.add(serverParam)
  
  for typ in types:
    let processMailboxNode = quote do:
      for msg in `server`.sources[`typ`].messages:
        debug "Bulk recv: Thread <= Mailbox", server = `server`.name, msgTyp = $`typ`, msg = msg
        try:
          `server`.process(msg)
        except KillError as e:
          raise e ## Reraise Exception so it can break the server loop
        
        except CatchableError as e:
          error "Message caused exception", msgType = $typeOf(msg), msg = msg, error = e.repr
    
    result.body.add(processMailboxNode)

proc generateInternalHasMessages(types: NimNode): NimNode =
  ## Generates a proc for checking if any mailbox in a given ServerActor currently has messages
  ## ```
  ## proc(mailboxes: MailboxTable): bool =
  ##   --- Repeat for each type - start ---
  ##   if mailboxes[typ].hasMessages():
  ##     return true
  ##   --- Repeat for each type - end ---
  ##   return false
  ## ```
  result = newProc(params = @[ident("bool")], procType = nnkLambda)
  let mailboxes = ident("mailboxes")
  let mailboxesParam = newIdentDefs(
    mailboxes, ident("MailboxTable")
  )
  result.params.add(mailboxesParam)

  for typ in types:
    let checkMailboxNode = quote do:
      if `mailboxes`[`typ`].hasMessages():
        return true
    result.body.add(checkMailboxNode)
  
  let finalReturnNode = quote do: 
    return false
  result.body.add finalReturnNode

proc generateMailboxes(types: NimNode, size: NimNode): NimNode =
  ## Generates a block statement that creates a MailboxTable instance
  ## that contains a mailbox per type in `types`.
  ## ```
  ## block:
  ##   var mailboxes: MailboxTable
  ##   --- Repeat for each type - start ---
  ##   mailboxes[`typ`] = newMailbox[`typ`](`size`)
  ##   --- Repeat for each type - end ---
  ##   mailboxes
  ## ```
  let mailboxesIdent = ident("mailboxes")
  let mailboxTable = newStmtList()
  let instantiation = quote do: 
    var `mailboxesIdent`: MailboxTable
  mailboxTable.add instantiation
  for typ in types:
    let mailboxNode = quote do: 
      `mailboxesIdent`[`typ`] = newMailbox[`typ`](`size`)
    mailboxTable.add(mailboxNode)
  
  mailboxTable.add(mailboxesIdent)
  return newBlockStmt(mailboxTable)

proc validateTypes(types: NimNode) =
  case types.kind
  of nnkBracket:
    for typ in types:
      let isTypeDesc = typ.kind == nnkSym
      if not isTypeDesc:
        error(fmt"""
          "{typ.repr}" is not a type description, but was found among the input-message types:
          {types.repr}.
          It may have been pushed in there due to calling "initServerActor" with parameters that do not have the type you expect. 
        """.strip())
  else:
    error(fmt"""
      The types passed in to initServerActor were not all of type `typedesc`: 
      {types.repr}
    """.strip())
  
  
proc createServerActor(
  mailboxSize: NimNode, 
  serverName: NimNode, 
  types: NimNode
): NimNode =
  validateTypes(types)

  let boxesBlockNode = generateMailboxes(types, mailboxSize)
  let processProcNode = generateInternalProcessMessages(types)
  let hasMessagesProcNode = generateInternalHasMessages(types)
  return quote do:
    block:
      privateAccess(ServerActor)
      let processProc = `processProcNode`
      let mailboxes = `boxesBlockNode`
      let hasMessagesProc = `hasMessagesProcNode`
      ServerActor(
        name: `serverName`,
        sources: mailboxes,
        processProc: processProc,
        hasMessagesProc: hasMessagesProc,
        signalReceiver: new(ThreadSignalPtr)[]
      )

const DEFAULT_SERVER_NAME = "unspecified"
const DEFAULT_MAILBOX_SIZE = 5
macro initServerActor*(
  mailboxSize: int,
  serverName: string,
  types: varargs[typed]
): ServerActor =
  let actorNode = createServerActor(mailboxSize, serverName, types)
  when defined(slacktorDebug):
    echo actorNode.repr
  return actorNode

macro initServerActor*(
  mailboxSize: int,
  types: varargs[typed]
): ServerActor = createServerActor(
  mailboxSize, 
  newStrLitNode(DEFAULT_SERVER_NAME), 
  types
)

macro initServerActor*(
  serverName: string,
  types: varargs[typed]
): ServerActor = createServerActor(
  newIntLitNode(DEFAULT_MAILBOX_SIZE), 
  serverName, 
  types
)

macro initServerActor*(
  types: varargs[typed]
): ServerActor = createServerActor(
  newIntLitNode(DEFAULT_MAILBOX_SIZE), 
  newStrLitNode(DEFAULT_SERVER_NAME), 
  types
)
  