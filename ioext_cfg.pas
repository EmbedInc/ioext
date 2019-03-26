{   Routines that manipulate I/O line configurations.
}
module ioext_cfg;
define ioext_cfg_newent;
define ioext_cfg_addent;
%include 'ioext2.ins.pas';
{
********************************************************************************
*
*   Function IOEXT_CFG_NEWENT (IOL)
*
*   Create a new configurations list entry for the I/O line IOL.  The new list
*   entry will be initialized to the extent possible, but will not be linked to
*   the I/O line.
}
function ioext_cfg_newent (            {create new unlinked configuration list entry}
  in out  iol: ioext_io_t)             {I/O line the configuration is for}
  :ioext_cfgent_p_t;                   {returned pointer to new config list entry}
  val_param;

var
  cfgent_p: ioext_cfgent_p_t;          {pointer to new descriptor}

begin
  sys_thread_lock_enter (iol.dev_p^.bus_p^.lock);
  util_mem_grab (                      {allocate memory for the new descriptor}
    sizeof(cfgent_p^), iol.dev_p^.bus_p^.mem_p^, true, cfgent_p);
  sys_thread_lock_leave (iol.dev_p^.bus_p^.lock);

  cfgent_p^.next_p := nil;             {fill in the new descriptor}
  cfgent_p^.prev_p := nil;
  cfgent_p^.cfg.ioty := ioext_ioty_unk_k;

  ioext_cfg_newent := cfgent_p;        {pass back pointer to the new descriptor}
  end;
{
********************************************************************************
*
*   Subroutine IOEXT_CFG_ADDENT (IOL, CFGENT)
*
*   Add the configuration list entry CFGENT to the I/O line IOL.
}
procedure ioext_cfg_addent (           {add fully filled in configuration to I/O line}
  in out  iol: ioext_io_t;             {I/O line to add the configuration to}
  in out  cfgent: ioext_cfgent_t);     {the configuration to add}
  val_param;

begin
  cfgent.next_p := nil;                {will be at end of list}

  sys_thread_lock_enter (iol.lock);
  cfgent.prev_p := iol.cfg_last_p;
  if iol.cfg_last_p = nil
    then begin                         {the list is currently empty}
      iol.cfg_first_p := addr(cfgent);
      end
    else begin                         {adding to end of existing list}
      iol.cfg_last_p^.next_p := addr(cfgent);
      end
    ;
  iol.cfg_last_p := addr(cfgent);
  sys_thread_lock_leave (iol.lock);
  end;
