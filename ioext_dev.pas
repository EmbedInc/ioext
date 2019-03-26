{   Routines that manipulate devices.
}
module ioext_dev;
define ioext_dev_new;
define ioext_dev_add;
%include 'ioext2.ins.pas';
{
********************************************************************************
*
*   Function IOEXT_DEV_NEW (BUS)
*
*   Create a new device descriptor for a device on the indicated bus.  Fields
*   will be initialized to default or benign values to the extent possible.  The
*   descriptor will not be linked onto the list of devices for the bus.
}
function ioext_dev_new (               {create new unlinked device descriptor}
  in out  bus: ioext_bus_t)            {bus the device is connected to}
  :ioext_dev_p_t;                      {returned pointer to the new descriptor}
  val_param;

var
  dev_p: ioext_dev_p_t;                {pointer to the new descriptor}
  ii: sys_int_machine_t;
  stat: sys_err_t;

begin
  sys_thread_lock_enter (bus.lock);
  util_mem_grab (                      {allocate memory for the device descriptor}
    sizeof(dev_p^), bus.mem_p^, true, dev_p);
  sys_thread_lock_leave (bus.lock);

  dev_p^.bus_p := addr(bus);
  dev_p^.prev_p := nil;
  dev_p^.next_p := nil;
  sys_thread_lock_create (dev_p^.lock, stat); {fill in default or benign field values}
  sys_error_abort (stat, '', '', nil, 0); {should never happen}
  dev_p^.ser := 0;
  dev_p^.vend := 0;
  dev_p^.devtype := 0;
  dev_p^.fwver := 0;
  dev_p^.fwseq := 0;
  dev_p^.adr := 0;
  dev_p^.nio := 0;
  for ii := 0 to 255 do begin
    dev_p^.io[ii] := nil;
    end;
  dev_p^.name.max := size_char(dev_p^.name.str);
  dev_p^.name.len := 0;

  ioext_dev_new := dev_p;              {pass back pointer to the new descriptor}
  end;
{
********************************************************************************
*
*   Subroutine IOEXT_DEV_ADD (DEV, STAT)
*
*   Add the fully filled in device descriptor DEV to the list of devices on its
*   bus.  The new device will be added to the end of the list.
}
procedure ioext_dev_add (              {add device to its bus}
  in out  dev: ioext_dev_t;            {the device to add}
  out     stat: sys_err_t);            {completion status}
  val_param;

begin
  dev.next_p := nil;

  sys_thread_lock_enter (dev.bus_p^.lock);
  dev.prev_p := dev.bus_p^.dev_last_p;
  if dev.bus_p^.dev_last_p = nil
    then begin                         {devices list is currently empty}
      dev.bus_p^.dev_first_p := addr(dev);
      end
    else begin                         {adding to end of existing list}
      dev.bus_p^.dev_last_p^.next_p := addr(dev);
      end
    ;
  dev.bus_p^.dev_last_p := addr(dev);
  sys_thread_lock_leave (dev.bus_p^.lock);
  end;
