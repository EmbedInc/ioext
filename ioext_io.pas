{   Routines that manipulate individual I/O lines.
}
module ioext_io;
define ioext_io_find;
define ioext_io_new;
define ioext_io_add;
define ioext_io_get;
%include 'ioext2.ins.pas';
{
********************************************************************************
*
*   Function IOEXT_IO_FIND (IO, NAME)
*
*   Try to find the I/O line indicated by NAME and return the pointer to it.  If
*   the I/O line exists, then the function value will be the pointer to its
*   descriptor, and the lock for that I/O line will be held.  The caller must
*   release that lock when done accessing the descriptor, which should be done
*   quickly.
*
*   If no I/O line of the indicated name exists, then the function returns NIL.
}
function ioext_io_find (               {find I/O line by name and lock it}
  in out  io: ioext_t;                 {state for this use of the library}
  in      name: univ string_var_arg_t) {name of the I/O line}
  :ioext_io_p_t;                       {returned pointer to I/O line, NIL on not found}
  val_param;

var
  name_p: univ_ptr;                    {pointer to name in hash table entry}
  io_pp: ioext_io_pp_t;                {pointer to I/O line pointer in hash entry}
  io_p: ioext_io_p_t;                  {pointer to the I/O line}

begin
  ioext_io_find := nil;                {init to not returning with a I/O line}

  sys_thread_lock_enter (io.lock_hash); {lock hash table for our exclusive use}
  string_hash_ent_lookup (io.hash, name, name_p, io_pp); {do the lookup}
  if io_pp = nil then begin            {nothing with that name found ?}
    sys_thread_lock_leave (io.lock_hash); {release lock on hash table}
    return;
    end;

  io_p := io_pp^;                      {get pointer to the I/O line}
  sys_thread_lock_enter (io_p^.lock);  {lock the I/O line for our use}
  sys_thread_lock_leave (io.lock_hash); {release lock on the hash table}
  ioext_io_find := io_p;               {return pointer to the I/O line}
  end;
{
********************************************************************************
*
*   Function IOEXT_IO_NEW (DEV)
*
*   Create a new descriptor for a I/O line of device DEV.
}
function ioext_io_new (                {create new unlinked I/O line descriptor}
  in out  dev: ioext_dev_t)            {device the I/O line is connected to}
  :ioext_io_p_t;                       {returned pointer to the new descriptor}
  val_param;

var
  iol_p: ioext_io_p_t;                 {pointer to the new descriptor}
  stat: sys_err_t;

begin
  sys_thread_lock_enter (dev.bus_p^.lock);
  util_mem_grab (                      {allocate memory for the new descriptor}
    sizeof(iol_p^), dev.bus_p^.mem_p^, true, iol_p);
  sys_thread_lock_leave (dev.bus_p^.lock);
{
*   Fill in with benign or default values.
}
  sys_thread_lock_create (iol_p^.lock, stat);
  sys_error_abort (stat, '', '', nil, 0); {should never happen}
  iol_p^.dev_p := addr(dev);
  iol_p^.n := 0;
  iol_p^.name.max := size_char(iol_p^.name.str);
  iol_p^.name.len := 0;
  iol_p^.cfg_first_p := nil;
  iol_p^.cfg_last_p := nil;
  iol_p^.cfg_p := nil;
  iol_p^.notified := false;

  ioext_io_new := iol_p;               {pass back pointer to the new descriptor}
  end;
{
********************************************************************************
*
*   Subroutine IOEXT_IO_ADD (IOL, STAT)
*
*   Add the I/O line descriptor IOL to the list of I/O lines of its device.
}
procedure ioext_io_add (               {add I/O line descriptor to its device}
  in out  iol: ioext_io_t;             {the I/O line to add}
  out     stat: sys_err_t);            {completion status}
  val_param;

var
  dev_p: ioext_dev_p_t;                {pointer to the device}
  bus_p: ioext_bus_p_t;                {pointer to the bus}
  io_p: ioext_p_t;                     {pointer to state for this use of the library}
  hpos: string_hash_pos_t;             {handle to position in hash table}
  name_p: univ_ptr;                    {pointer to name stored in hash entry}
  io_pp: ioext_io_pp_t;                {pointer to I/O line pointer in hash entry}
  fnd: boolean;                        {name found in hash table}

begin
  sys_error_none(stat);                {init to no error occurred}

  if (iol.n < 0) or (iol.n > 255) then return; {invalid I/O line number ?}
  dev_p := iol.dev_p;                  {get pointer to the device}
  if dev_p = nil then return;
  bus_p := dev_p^.bus_p;               {get pointer to the bus}
  if bus_p = nil then return;
  io_p := bus_p^.io_p;                 {get pointer to library use state}
  if io_p = nil then return;

  sys_thread_lock_enter (io_p^.lock_hash); {lock I/O names hash table for our use}
  string_hash_pos_lookup (             {find position for this name in hash table}
    io_p^.hash,                        {the hash table}
    iol.name,                          {the name string to find the position of}
    hpos,                              {returned hash table position}
    fnd);                              {returned TRUE iff name already in table}
  if fnd then begin                    {name of new I/O line already in use ?}
    sys_thread_lock_leave (io_p^.lock_hash); {release lock on the hash table}
    sys_stat_set (ioext_subsys_k, ioext_stat_nameused_k, stat); {name already in use}
    sys_stat_parm_vstr (iol.name, stat);
    return;
    end;
  string_hash_ent_add (                {create the new hash table entry}
    hpos,                              {position to create the new entry at}
    name_p,                            {returned pointer to name in hash entry}
    io_pp);                            {returned pointer to hash entry data area}
  io_pp^ := addr(iol);                 {point hash entry to its I/O line}

  sys_thread_lock_enter (iol.dev_p^.lock);
  dev_p^.io[iol.n] := addr(iol);       {set pointer to this I/O line in the device}
  sys_thread_lock_leave (iol.dev_p^.lock);
  sys_thread_lock_leave (io_p^.lock_hash); {release lock on hash table}
  end;
{
********************************************************************************
*
*   Function IOEXT_IO_GET (IO, NAME, UVAL)
*
*   Get the current value of the I/O line indicated by NAME.  The function
*   returns TRUE on success with the new value in UVAL.  If no such I/O line
*   exists, then the function returns FALSE and UVAL is not altered.
}
function ioext_io_get (                {get current value of a I/O line}
  in out  io: ioext_t;                 {state for this use of the library}
  in      name: univ string_var32_t;   {name of the I/O line}
  in out  uval: ioext_uval_t)          {returned value of the I/O line}
  :boolean;                            {TRUE on success, FALSE on name not found}
  val_param;

var
  io_p: ioext_io_p_t;                  {pointer to I/O line descriptor}

begin
  ioext_io_get := false;               {init to I/O line not found}

  io_p := ioext_io_find (io, name);    {lookup name, get pointer to I/O line}
  if io_p = nil then return;           {name not found ?}
  if io_p^.cfg_p = nil
    then begin                         {configuration of this line not set}
      uval.cfg.ioty := ioext_ioty_unk_k;
      end
    else begin                         {line configuration has been set}
      uval.cfg := io_p^.cfg_p^;        {grab the static configuration info}
      uval.val := io_p^.val;           {grab the current value}
      end
    ;
  sys_thread_lock_leave (io_p^.lock);  {release lock on the I/O line}
  ioext_io_get := true;                {indicate returning with the value}
  end;
