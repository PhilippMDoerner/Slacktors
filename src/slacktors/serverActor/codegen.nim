import ./serverActorType
import chronos
import chronos/threadsync
import std/[importutils, genasts, sequtils, strutils, strformat, atomics, macros]

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
  ##     except CatchableError as e:
  ##       error "Message caused exception", msg = msg, error = e.repr
  ##   --- Repeat for each type - end ---
  ## ```
  ## Requires each msg type to have a defined proc: proc process(x: <TYPE>) 
  result = newProc(procType = nnkLambda)
  let raisesPragma = nnkPragma.newTree(
    nnkExprColonExpr.newTree(
      ident("raises"),
      nnkBracket.newTree()
    )
  )
  result.pragma = raisesPragma
  echo result.repr
  
  let server = ident("server")
  let serverParam = newIdentDefs(
    server, ident("ServerActor")
  )
  result.params.add(serverParam)
  
  for typ in types:
    let processMailboxNode = genAst(server = server, typ = typ):
      try:
        for msg in server.sources[typ].messages:
          trace "Bulk recv: Thread <= Mailbox", server = server, msgTyp = $typ, msg = msg.repr
          try:
            server.process(msg)
                
          except CatchableError as e:
            error("Message caused exception", server = server, msgType = $typeOf(msg), msg = msg.repr, error = e[])
      
      except CatchableError as e:
        error("Failed to access mailbox", server = server, mailboxType = $typ, error = e[])
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

proc generateDestructorProc(types: NimNode): NimNode =
  ## Generates a proc for destroying all receiving mailboxes in a given ServerActor
  ## ```
  ## proc destroy(server: ServerActor) {.nimcall, raises: [].}=
  ##   --- Repeat for each type - start ---
  ##   destroyMailbox(server.sources[`typ]`)
  ##   --- Repeat for each type - end ---
  ## ```
  result = newProc(procType = nnkLambda)
  let raisesPragma = nnkPragma.newTree(
    nnkExprColonExpr.newTree(
      ident("raises"),
      nnkBracket.newTree()
    )
  )
  result.pragma = raisesPragma

  let server = ident("server")
  let serverParam = newIdentDefs(
    server, ident("ServerActor")
  )
  result.params.add(serverParam)
  for typ in types:
    let destroyMailboxNode = quote do:
      try:
        destroyMailbox(`server`.sources[`typ`])
      except CatchableError as e:
        error "Failed to destroy mailbox", server = `server`, mailboxType = $`typ`, error = e[]
    result.body.add(destroyMailboxNode)

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
  let destructorProcNode = generateDestructorProc(types)

  return quote do:
    block:
      privateAccess(ServerActor)
      let processProc = `processProcNode`
      let mailboxes = `boxesBlockNode`
      let hasMessagesProc = `hasMessagesProcNode`
      let destructorProc = `destructorProcNode`
      let server = createShared(ServerActorObj)
      server[] = ServerActorObj(
        name: `serverName`,
        sources: mailboxes,
        processProc: processProc,
        hasMessagesProc: hasMessagesProc,
        destructorProc: destructorProc,
        signalReceiver: new(ThreadSignalPtr)[]
      )
      server.isRunning.store(true)
      server
      
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
  