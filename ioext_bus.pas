module ioext_bus;
define ioext_open_bus;
%include 'ioext2.ins.pas';
{
********************************************************************************
*
*   Subroutine IOEXT_OPEN_BUS (IO, OPBUS, STAT)
*
*   Add a bus to be controlled by the use of the library that IO is the state
*   for.  The bus is described by OPBUS.  IO must have been previously
*   initialized with IOEXT_START.
*
*   Any number of busses can be controlled by one use of the library.  All the
*   I/O lines available via devices on all the busses will be in a single
*   namespace.  Which bus a device is physically connected to therefore can be
*   ignored by applications, allowing devices to be moved between busses easily.
}
procedure ioext_open_bus (             {open connection to a new bus of IOEXT devices}
  in out  io: ioext_t;                 {state for this use of the library}
  in      opbus: ioext_opbus_t;        {info about the bus to open a connection to}
  out     stat: sys_err_t);            {completion status}
  val_param;

var
  bus_p: ioext_bus_p_t;                {pointer to descriptor for the new bus}
  mem_p: util_mem_context_p_t;         {points to private mem context for the bus}
  stat2: sys_err_t;                    {to avoid corrupting original error in STAT}

label
  abort;

begin
  sys_thread_lock_enter (io.lock);
  util_mem_context_get (io.mem_p^, mem_p); {create private mem context for this bus}
  sys_thread_lock_leave (io.lock);
  util_mem_grab (                      {allocate the bus descriptor}
    sizeof(bus_p^), mem_p^, false, bus_p);

  bus_p^.io_p := addr(io);             {fill in the new bus descriptor}
  bus_p^.mem_p := mem_p;
  sys_thread_lock_create (bus_p^.lock, stat);
  if sys_error(stat) then goto abort;
  bus_p^.next_p := nil;
  bus_p^.prev_p := nil;
  bus_p^.dev_first_p := nil;
  bus_p^.dev_last_p := nil;
  bus_p^.set_p := nil;
  bus_p^.get_p := nil;
  bus_p^.close_p := nil;
  bus_p^.dat_p := nil;
  bus_p^.name.max := size_char(bus_p^.name.str);
  bus_p^.name.len := 0;
  bus_p^.bustype := opbus.bustype;     {set type of this bus}

  case opbus.bustype of                {what type of bus is this ?}

ioext_bus_can_k: begin                 {CAN bus accessed via CAN library}
      ioext_bus_can_open (io, opbus, bus_p^, stat);
      end;

otherwise                              {unexpected bus type}
    sys_stat_set (ioext_subsys_k, ioext_stat_bustype_bad_k, stat);
    sys_stat_parm_int (ord(opbus.bustype), stat);
    sys_stat_parm_str ('IOEXT_OPEN_BUS', stat);
    goto abort;
    end;                               {end of bus type cases}

  if sys_error(stat) then goto abort;  {failed to open connection to bus ?}
{
*   Add the new bus to the list managed by this library use.
}
  sys_thread_lock_enter (io.lock);     {lock library use state}
  bus_p^.prev_p := io.bus_last_p;
  if io.bus_last_p = nil
    then begin                         {this is first bus in list}
      io.bus_first_p := bus_p;
      end
    else begin                         {adding to end of existing list}
      io.bus_last_p^.next_p := bus_p;
      end
    ;
  io.bus_last_p := bus_p;
  sys_thread_lock_leave (io.lock);     {release library use state}

  ioext_event_bus_add (io, bus_p^);    {notify client of the new bus}
  return;                              {normal return point}

abort:                                 {error occurred, STAT already set}
  sys_thread_lock_delete (bus_p^.lock, stat2); {delete thread lock in bus descriptor}
  sys_thread_lock_enter (io.lock);
  util_mem_context_del (mem_p);        {delete bus mem context and bus descriptor}
  sys_thread_lock_leave (io.lock);
  end;
{
********************************************************************************
*
*   Subroutine IOEXT_BUS_DEV_ADD (BUS, DEV)
*
*   Add the device DEV to the bus BUS.  Only the device data fields need to be
*   set in DEV.  The logistics and fields used to link to the rest of the system
*   will be set by this routine.  Specifically, the LOCK, PREV_P, NEXT_P, and
*   BUS_P fields of DEV will be filled in here.
}
procedure ioext_bus_dev_add (          {add device to a bus}
  in out  bus: ioext_bus_t;            {the bus to add a device to}
  in out  dev: ioext_dev_t);           {the device to add}
  val_param;

var
  stat: sys_err_t;                     {completion status}

begin
  sys_thread_lock_create (dev.lock, stat); {fill in dev before linking it to list}
  sys_error_abort (stat, '', '', nil, 0); {should never happen}
  dev.next_p := nil;
  dev.bus_p := addr(bus);              {pointer to bus descriptor}

  sys_thread_lock_enter (bus.lock);    {link new device to list for this bus}
  dev.prev_p := bus.dev_last_p;
  if bus.dev_last_p = nil
    then begin
      bus.dev_first_p := addr(dev);
      end
    else begin
      bus.dev_last_p^.next_p := addr(dev);
      end
    ;
  bus.dev_last_p := addr(dev);
  sys_thread_lock_leave (bus.lock);
  end;
