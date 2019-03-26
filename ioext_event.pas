{   Routines for manipulating events and the event queue.
}
module ioext_event;
define ioext_event_newent;
define ioext_event_enqueue;
define ioext_event_get;
define ioext_event_bus_add;
define ioext_event_dev_add;
define ioext_event_io_add;
define ioext_event_in_state;
%include 'ioext2.ins.pas';
{
********************************************************************************
*
*   Function IOEXT_EVENT_NEWENT (IO)
*
*   Return pointer to unused event queue entry.  The entry will not be linked
*   into the queue.
}
function ioext_event_newent (          {get unused event queue entry}
  in out  io: ioext_t)                 {state for this use of the library}
  :ioext_event_p_t;                    {returned pointing to new event queue entry}
  val_param;

var
  event_p: ioext_event_p_t;

begin
  sys_thread_lock_enter (io.lock_ev);
  if io.evfree_p = nil
    then begin                         {the free list is empty}
      util_mem_grab (                  {allocate new memory for the queue entry}
        sizeof(event_p^), io.ev_mem_p^, false, event_p);
      end
    else begin                         {a free entry is available}
      event_p := io.evfree_p;
      io.evfree_p := event_p^.next_p;
      end
    ;
  sys_thread_lock_leave (io.lock_ev);

  event_p^.next_p := nil;
  ioext_event_newent := event_p;
  end;
{
********************************************************************************
*
*   Subroutine IOEXT_EVENT_ENQUEUE (IO, EVENT)
*
*   Add the event queue entry EVENT to the end of the queue.
}
procedure ioext_event_enqueue (        {add entry to end of event queue}
  in out  io: ioext_t;                 {state for this use of the library}
  in out  event: ioext_event_t);       {the entry to add to end of queue}
  val_param;

begin
  event.next_p := nil;                 {will be at end of queue}

  sys_thread_lock_enter (io.lock_ev);
  if io.evlast_p = nil
    then begin                         {the queue is empty}
      io.evfirst_p := addr(event);
      end
    else begin                         {adding to end of existing list}
      io.evlast_p^.next_p := addr(event);
      end
    ;
  io.evlast_p := addr(event);
  sys_thread_lock_leave (io.lock_ev);

  sys_event_notify_bool (io.evnew);    {signal new event in event queue}
  end;
{
********************************************************************************
*
*   Subroutine IOEXT_EVENT_GET (IO, EV)
*
*   Get the next sequential event associated with the IO use of the IOEXT
*   library.  This routine waits indefinitely until a event is available.
}
procedure ioext_event_get (            {get the next sequential event}
  in out  io: ioext_t;                 {state for this use of the library}
  out     ev: ioext_ev_t);             {returned event descriptor}
  val_param;

var
  event_p: ioext_event_p_t;
  stat: sys_err_t;

begin
  while true do begin                  {back here until find a new event}

    sys_thread_lock_enter (io.lock_ev);
    if io.evfirst_p <> nil then begin  {a event is available ?}
      event_p := io.evfirst_p;         {get pointer to the event queue entry}
      io.evfirst_p := event_p^.next_p; {update queue head to next entry}
      if io.evfirst_p = nil then io.evlast_p := nil; {queue is now empty ?}
      event_p^.next_p := io.evfree_p;  {add removed entry to head of free list}
      io.evfree_p := event_p;
      ev := event_p^.ev;               {pass back the event data}
      sys_thread_lock_leave (io.lock_ev);
      return;
      end;
    if io.quit then begin              {closing this use of the library ?}
      sys_thread_lock_leave (io.lock_ev);
      ev.evtype := ioext_ev_close_k;   {return event that library is being closed}
      return;
      end;
    sys_thread_lock_leave (io.lock_ev);

    sys_event_wait (io.evnew, stat);   {wait for entry to be added to the queue}
    if sys_error(stat) then begin      {error waiting on event ?}
      ev.evtype := ioext_ev_close_k;   {return event that library is being closed}
      return;
      end;
    end;                               {back to check queue again}
  end;
{
********************************************************************************
*
*   Subroutine IOEXT_EVENT_BUS_ADD
*
*   Create event indicating a new bus has been added.
}
procedure ioext_event_bus_add (        {create event for new bus added}
  in out  io: ioext_t;                 {state for this use of the library}
  in      bus: ioext_bus_t);           {bus that was added}

var
  event_p: ioext_event_p_t;            {points to the new event}

begin
  event_p := ioext_event_newent (io);  {get unused event descriptor}
  event_p^.ev.evtype := ioext_ev_bus_add_k; {fill in the new event descriptor}
  event_p^.ev.bus_add_bus_p := addr(bus);
  ioext_event_enqueue (io, event_p^);  {add the event to the end of the queue}
  end;
{
********************************************************************************
*
*   Subroutine IOEXT_EVENT_DEV_ADD
*
*   Create event indicating a new device has been added.
}
procedure ioext_event_dev_add (        {create event for new device added}
  in out  io: ioext_t;                 {state for this use of the library}
  in      dev: ioext_dev_t);           {device that was added}

var
  event_p: ioext_event_p_t;            {points to the new event}

begin
  event_p := ioext_event_newent (io);  {get unused event descriptor}
  event_p^.ev.evtype := ioext_ev_dev_add_k; {fill in the new event descriptor}
  event_p^.ev.dev_add_dev_p := addr(dev);
  ioext_event_enqueue (io, event_p^);  {add the event to the end of the queue}
  end;
{
********************************************************************************
*
*   Subroutine IOEXT_EVENT_IO_ADD
*
*   Create event indicating a I/O line has been added.
}
procedure ioext_event_io_add (         {create event for new I/O line added}
  in out  io: ioext_t;                 {state for this use of the library}
  in out  ioline: ioext_io_t);         {the I/O line that was added}

var
  event_p: ioext_event_p_t;            {points to the new event}

begin
  event_p := ioext_event_newent (io);  {get unused event descriptor}
  event_p^.ev.evtype := ioext_ev_io_add_k; {fill in the new event descriptor}
  event_p^.ev.io_add_io_p := addr(ioline);
  ioline.notified := true;             {remember event created for this line}
  ioext_event_enqueue (io, event_p^);  {add the event to the end of the queue}
  end;
{
********************************************************************************
*
*   Subroutine IOEXT_EVENT_IN_STATE
*
*   Create event indicating a input line changed state.
}
procedure ioext_event_in_state (       {create event for input line state changed}
  in out  io: ioext_t;                 {state for this use of the library}
  in      ioline: ioext_io_t);         {the I/O line that changed state}

var
  event_p: ioext_event_p_t;            {points to the new event}

begin
  if not ioline.notified then return;  {don't notify of changes before line existance}

  event_p := ioext_event_newent (io);  {get unused event descriptor}
  event_p^.ev.evtype := ioext_ev_in_state_k; {fill in the new event descriptor}
  event_p^.ev.in_state_io_p := addr(ioline);
  ioext_event_enqueue (io, event_p^);  {add the event to the end of the queue}
  end;
