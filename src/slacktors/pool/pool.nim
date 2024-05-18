import std/[atomics, tasks, cpuinfo, typeinfo, isolation]
import threading/channels
import chronicles
import std/times {.all.} # Only needed for `clearThreadVariables`

export isolation, chronicles

proc clearThreadVariables() =
  `=destroy`(times.localInstance)
  `=destroy`(times.utcInstance)
  when defined(gcOrc):
    GC_fullCollect() # from orc.nim. Has no destructor.

proc cleanupThread*() {.gcsafe, raises: [].}=
  ## Internally, this clears up known thread variables
  ## that were likely set to avoid memory leaks.
  ## May become unnecessary if https://github.com/nim-lang/Nim/issues/23165 ever gets fixed
  {.cast(gcsafe).}:
    try:
      clearThreadVariables()
    except Exception as e:
      error "Exception during cleanup: ", error = e[]

type 
  ThreadPoolObj = object
    tasks: ptr Chan[Task]
    workers: seq[Thread[(ThreadPool, WorkerId)]]
    active: Atomic[bool]

  ThreadPool* = ptr ThreadPoolObj

  Worker = Thread[(ThreadPool, WorkerId)]
  
  WorkerId = int
  
proc getTaskCount(pool: ThreadPool): int =
  pool.tasks[].peek()

template spawn*(pool: ThreadPool, call: untyped) =
  pool.tasks[].send(toTask(call))

proc clearTasks(pool: ThreadPool) =
  trace "Start Clearing tasks", taskCount = pool.getTaskCount()
  
  var task: Task
  while pool.tasks[].tryRecv(task):
    try: 
      task.invoke()
    except CatchableError as e:
      error "Exception in task during shutdown: ", error = e[]
    finally:
      `=destroy`(task)
  
  trace "Finished Clearing tasks"

proc destroy(pool: ThreadPool) =
  `=destroy`(pool.tasks[])
  `=destroy`(pool[])
  freeShared(pool.tasks)
  freeShared(pool)

proc shutDown*(pool: ThreadPool) =
  trace "Start shutting down global Threadpool"
  pool.active.store(false)
  
  for index in 0..<pool.workers.len:
    proc doNothing() = discard
    pool.spawn doNothing()
    
  joinThreads(pool.workers)
  
  pool.clearTasks()
  trace "Finished shut down of global Threadpool"
  
  trace "Start destroying ThreadPool"
  pool.destroy()
  trace "Finished destroying ThreadPool"

proc isRunning*(pool: ThreadPool): bool =
  pool.active.load()

proc getTask(pool: ThreadPool): Task =
  pool.tasks[].recv()

proc threadLoop(params: (ThreadPool, WorkerId)) {.thread, nimcall.} =
  let (pool, workerId) = params
  trace "Start Worker Thread", workerId = workerId
  while pool.isRunning():
    try:
      pool.getTask().invoke()
      trace "Task finished", workerId = workerId
      
    except CatchableError as e:
      error "Exception in task: ", workerId = workerId, error = e[]
  
  trace "Finished Worker Thread", workerId = workerId
  cleanupThread()

proc initWorkers(pool: ThreadPool) =
  for index in 0 ..< pool.workers.len:
    createThread(
      pool.workers[index], 
      threadLoop,
      (pool, index)
    )

proc new*(t: typedesc[ThreadPool], numThreads: int = countProcessors()): ThreadPool =
  trace "Creating new ThreadPool", threadCount = numThreads
  result = createShared(ThreadPoolObj)
  result[] = ThreadPoolObj(
    tasks: createShared(Chan[Task]),
    workers: newSeq[Worker](numThreads),
  )
  result[].tasks[] = newChan[Task](100)
  result[].active.store(true)
  result.initWorkers()