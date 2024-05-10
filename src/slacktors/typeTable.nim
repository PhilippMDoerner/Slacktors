#[
  Implements a table that allows storing various different ptr types via type erasure
]#

import std/[tables, hashes]

type TypeId = distinct pointer
proc `==`*(x, y: TypeId): bool {.borrow.}
proc hash*(x: TypeId): Hash {.borrow.}
proc getTypeId[T](typ: typedesc[T]): TypeId =
  var info {.global.}: int
  return TypeId(info.addr)

type TypeTable* = distinct Table[TypeId, pointer]
proc hasKey*[T](table: TypeTable, key: typedesc[T]): bool =
  let innerKey = key.getTypeId()
  return Table[TypeId, pointer](table).hasKey(innerKey)

proc `[]`*[T](table: TypeTable; typ: typedesc[T]): T =
  let key = typ.getTypeId()
  let valuePtr = Table[TypeId, pointer](table)[key]
  return cast[T](valuePtr)

proc `[]=`*[T: ptr](table: var TypeTable, key: typedesc[T], value: T) =
  let key = T.getTypeId()
  let valuePtr: pointer = value
  Table[TypeId, pointer](table)[key] = valuePtr