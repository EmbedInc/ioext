module ioext_start;
define ioext_start;
define ioext_end;
%include 'ioext2.ins.pas';
{
********************************************************************************
*
*   Subroutine IOEXT_START (MEM, IO, STAT)
*
*   Start a new use of the IOEXT library.  MEM is the parent memory context.  A
*   subordinate memory context to MEM will be created, and all dynamically
*   allocated memory associated with this new use of the library will be from
*   the subordinate context.  IO will be returned the new library use state.
}
procedure ioext_start (                {start a new use of this library}
  in out  mem: util_mem_context_t;     {parent memory context}
  out     io: ioext_t;                 {returned library use state}
  out     stat: sys_err_t);            {completion status}
  val_param;

var
  stat2: sys_err_t;

label
  abort1;

begin
  sys_thread_lock_create (io.lock, stat); {create single thread interlock}
  if sys_error(stat) then return;

  util_mem_context_get (mem, io.mem_p); {create private memory context}
  io.bus_first_p := nil;               {init to no busses open}
  io.bus_last_p := nil;
  string_hash_create (                 {init hash table of I/O line names}
    io.hash,                           {hash table to initialize}
    128,                               {number of hash buckets}
    32,                                {max length of any entry name}
    sizeof(ioext_io_p_t),              {data size for each table entry}
    [],                                {create subordinate mem context, may del entries}
    io.mem_p^);                        {parent memory context}
  sys_thread_lock_create (io.lock_hash, stat);

  sys_thread_lock_create (io.lock_ev, stat);
  if sys_error(stat) then goto abort1;
  util_mem_context_get (io.mem_p^, io.ev_mem_p); {create mem context for event queue}
  io.evfirst_p := nil;
  io.evlast_p := nil;
  io.evfree_p := nil;
  sys_event_create_bool (io.evnew);

  io.quit := false;                    {init to not shutting down}
  return;                              {normal return point}

abort1:
  sys_thread_lock_delete (io.lock, stat2);
  end;
{
********************************************************************************
*
*   Subroutine IOEXT_END (IO, STAT)
*
*   End the use of the IOEXT library for which the state is IO.
}
procedure ioext_end (                  {end a use of this library}
  in out  io: ioext_t;                 {library use state, will be returned invalid}
  out     stat: sys_err_t);            {completion status}
  val_param;

var
  bus_p: ioext_bus_p_t;                {pointer to current bus}
  dev_p: ioext_dev_p_t;                {pointer to current device}
  io_p: ioext_io_p_t;                  {pointer to current I/O line}
  ii: sys_int_machine_t;

begin
{
*   Close the connections to all the busses and stop all other threads.
}
  bus_p := io.bus_first_p;             {init to first bus}
  while bus_p <> nil do begin          {back here each new bus}
    bus_p^.close_p^ (bus_p);           {close connection to this bus}
    bus_p := bus_p^.next_p;            {advance to next bus in list}
    end;                               {back to close next bus}
{
*   Deallocate system resources other than dynamic memory of busses, I/O
*   devices, and I/O lines.  Dynamic memory will be deallocated automaticlly
*   when the top memory context is deleted.
}
  bus_p := io.bus_first_p;             {init to first bus}
  while bus_p <> nil do begin          {back here each new bus}
    dev_p := bus_p^.dev_first_p;
    while dev_p <> nil do begin        {once for each device on this bus}
      for ii := 0 to 255 do begin      {once for each I/O line of this device}
        io_p := dev_p^.io[ii];
        if io_p = nil then next;
        sys_thread_lock_delete (io_p^.lock, stat); {delete I/O line thread lock}
        if sys_error(stat) then return;
        end;
      sys_thread_lock_delete (dev_p^.lock, stat); {delete device thread lock}
      if sys_error(stat) then return;
      dev_p := dev_p^.next_p;
      end;
    sys_thread_lock_delete (bus_p^.lock, stat); {delete bus thread lock}
    if sys_error(stat) then return;
    bus_p := bus_p^.next_p;            {advance to next bus in list}
    end;                               {back to close next bus}
{
*   Deallocate system resources of the library use state.
}
  string_hash_delete (io.hash);        {delete I/O line names hash table}
  sys_thread_lock_delete (io.lock, stat); {delete top thread lock}
  if sys_error(stat) then return;
  util_mem_context_del (io.mem_p);     {deallocate all dynamic memory}
  end;
