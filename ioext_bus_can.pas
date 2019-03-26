{   Routines to handle a CAN bus accessed via the CAN library.
}
module ioext_bus_can;
define ioext_bus_can_open;
%include 'ioext2.ins.pas';

type
  dd_p_t = ^dd_t;
  dd_t = record                        {private state for this driver}
    lock: sys_sys_threadlock_t;        {exclusive lock for accessing multi-thread state}
    cl: can_t;                         {CAN library use state for this connection}
    adr: array [1..255] of ioext_dev_p_t; {pointers to devices at each address}
    nextadr: sys_int_machine_t;        {1-255 next bus address to assign}
    ndev: sys_int_machine_t;           {0-255 number of devices on this bus}
    thid_in: sys_sys_thread_id_t;      {ID of CAN frames receiving thread}
    err: sys_err_t;                    {first error encountered by a background thread}
    quit: boolean;                     {trying to close}
    end;

procedure ioext_bus_can_close (        {close the connection to this bus}
  in out  bus: ioext_bus_t);           {descriptor of bus to close}
  val_param; forward;

procedure ioext_bus_can_set (          {set I/O line to new state, lock held}
  in out  io: ioext_io_t;              {the I/O line to set}
  in      cfg_p: ioext_cfg_p_t;        {new config within I/O line, NIL = use current}
  in      val: ioext_val_t;            {the value to set it to}
  out     stat: sys_err_t);            {completion status}
  val_param; forward;

procedure ioext_bus_can_get (          {get current state of I/O line}
  in out  io: ioext_io_t;              {I/O line to get the current state of}
  in out  val: ioext_val_t;            {returned value of the I/O line}
  out     stat: sys_err_t);            {completion status}
  val_param; forward;

procedure ioext_bus_can_in (           {root routine for CAN receiving thread}
  in      arg: sys_int_adr_t);         {address of bus descriptor}
  val_param; forward;
{
********************************************************************************
*
*   Subroutine IOEXT_BUS_CAN_OPEN (IO, OPBUS, BUS, STAT)
*
*   Open a connection to a CAN bus that is accessed via the CAN library.  IO is
*   the IOEXT library use state.  OPBUS is the information from the application
*   about the bus to open.
*
*   BUS is the bus descriptor for the new bus connection.  It has already been
*   filled in to the extent possible.  This routine will open the connection
*   and fill in the remaining fields in BUS.  BUS is not currently linked into
*   the system.  That is the caller's responsibility if this routine returns
*   without error.
*
*   It is assumed that the caller will delete the memory context for this bus
*   (pointed to by BUS.MEM_P) if this routine returns with error.  This routine
*   therefore does not need to deallocate any memory allocated under the bus
*   memory context on error, since it will automatically be deleted when the bus
*   memory context is deleted.
}
procedure ioext_bus_can_open (         {open connection to CAN bus via CAN library}
  in out  io: ioext_t;                 {state for this use of the library}
  in      opbus: ioext_opbus_t;        {info about the bus to open a connection to}
  in out  bus: ioext_bus_t;            {descriptor for the new bus}
  out     stat: sys_err_t);            {completion status}
  val_param;

var
  dd_p: dd_p_t;                        {pointer to private driver state}
  ii: sys_int_machine_t;               {scratch integer and loop counter}
  stat2: sys_err_t;                    {to avoid corrupting first error in STAT}

label
  abort1, abort2;

begin
  util_mem_grab (                      {allocate private driver state}
    sizeof(dd_p^), bus.mem_p^, false, dd_p);
  bus.dat_p := dd_p;                   {save pointer to private data in bus descriptor}
  bus.set_p := univ_ptr(addr(ioext_bus_can_set)); {set pointers to the external driver routines}
  bus.get_p := univ_ptr(addr(ioext_bus_can_get));
  bus.close_p := univ_ptr(addr(ioext_bus_can_close));
  with dd_p^:dd do begin               {define DD abbreviation for driver data}

  sys_thread_lock_create (dd.lock, stat); {create private multi-thread lock}
  if sys_error(stat) then return;

  can_init (dd.cl);                    {init the CAN library state}
  dd.cl.dev := opbus.can_dev_p^;       {indicate device to use}
  can_open (dd.cl, stat);              {open connection to this CAN device}
  if sys_error(stat) then goto abort1;
  string_copy (dd.cl.dev.name, bus.name); {set bus name from controlling device name}

  for ii := 1 to 255 do begin
    dd.adr[ii] := nil;                 {init to all bus addresses unassigned}
    end;
  dd.nextadr := 1;                     {init next address to assign}
  dd.ndev := 0;                        {init to no devices known on the bus}
  sys_error_none (dd.err);             {init to no error in background thread}
  dd.quit := false;                    {init to not trying to shut down}

  sys_thread_create (                  {create input frames receiving thread}
    addr(ioext_bus_can_in),            {address of root thread routine}
    sys_int_adr_t(addr(bus)),          {pass pointer to bus descriptor}
    dd.thid_in,                        {returned ID of the new thread}
    stat);
  if sys_error(stat) then goto abort2;
  return;                              {normal return point}
{
*   Error has occured with CAN library open.  STAT indicates the error.
}
abort2:
  can_close (dd.cl, stat2);            {close the connection to the bus}
abort1:
  sys_thread_lock_delete (dd.lock, stat2); {delete the private thread interlock}
  end;                                 {done with DD abbreviation}
  end;
{
********************************************************************************
*
*   Subroutine IOEXT_BUS_CAN_CLOSE (BUS)
*
*   Disconnect from the bus and deallocate private resources associated with it.
*   This routine does not need to deallocate any memory allocated under the bus
*   context because that context will be deleted by the caller after this
*   routine returns.
}
procedure ioext_bus_can_close (        {close the connection to this bus}
  in out  bus: ioext_bus_t);           {descriptor of bus to close}
  val_param;

var
  dd_p: dd_p_t;                        {pointer to private driver state}
  evin: sys_sys_event_id_t;            {signalled on input thread exit}
  stat: sys_err_t;                     {completion status}

begin
  dd_p := bus.dat_p;                   {get pointer to private driver state}
  with dd_p^:dd do begin               {define DD abbreviation for driver data}

  sys_thread_event_get (dd.thid_in, evin, stat); {get event signalled on input thread exit}
  sys_error_abort (stat, '', '', nil, 0);
  dd.quit := true;                     {indicate trying to shut down}

  can_close (dd.cl, stat);             {close connection to the bus}
  sys_error_abort (stat, '', '', nil, 0);

  sys_event_wait (evin, stat);         {wait for input receiving thread to exit}
  sys_error_abort (stat, '', '', nil, 0);

  sys_thread_lock_delete (dd.lock, stat); {delete the private thread interlock}
  sys_error_abort (stat, '', '', nil, 0);
  end;                                 {done with DD abbreviation}
  end;                                 {end of subroutine IOEXT_BUS_CAN_CLOSE}
{
********************************************************************************
*
*   Subroutine IOEXT_BUS_CAN_IN (ARG)
*
*   Root routine for the CAN frames receiving thread.  ARG is the address of the
*   bus descriptor.
}
procedure ioext_bus_can_in (           {root routine for CAN receiving thread}
  in      arg: sys_int_adr_t);         {address of bus descriptor}
  val_param;

var
  bus_p: ioext_bus_p_t;                {points to the bus descriptor}
  dd_p: dd_p_t;                        {points to our private driver data}
  canr: can_frame_t;                   {received CAN frame}
  canf: can_frame_t;                   {scratch CAN frame descriptor}
  i1, i2, i3, i4: sys_int_conv32_t;    {parameters interpreted from CAN frame data}
  sline: sys_int_machine_t;            {starting I/O line number of group being processed}
  line: sys_int_machine_t;             {0-255 I/O line number}
  bit: sys_int_machine_t;              {bit number within byte or word}
  dind: sys_int_machine_t;             {data bytes index}
  b1: boolean;                         {boolean parameter}
  ch: boolean;                         {state changed}
  tk: string_var32_t;                  {scratch token}
  dev_p: ioext_dev_p_t;                {scratch pointer to device descriptor}
  io_p: ioext_io_p_t;                  {scratch pointer to I/O line descriptor}
  cfgent_p: ioext_cfgent_p_t;          {I/O line configuration list entry pointer}
  ext_opc: sys_int_machine_t;          {extended command opcode}
  ext_ack: boolean;                    {ACK to previous frame, not new}
  ext_rsp: boolean;                    {in response to deliberate request, not asynch}
  ext_reqack: boolean;                 {ACK requested}
  ext_first: boolean;                  {first frame of message}
  ext_last: boolean;                   {last frame of message}
  ext_seq: sys_int_machine_t;          {0-15 SEQ field value}
  ext_adr: sys_int_machine_t;          {1-255 node address}
  stat: sys_err_t;                     {completion status}

label
  loop, have_dev, recv_ext,
  digin_dcfg, digin_nextl, next_digich,
  done_canr, abort;

begin
  tk.max := size_char(tk.str);         {init local var string}

  bus_p := univ_ptr(arg);              {get pointer to the bus descriptor}
  dd_p := bus_p^.dat_p;                {get pointer to private driver data}
  with dd_p^:dd do begin               {define DD abbreviation for driver data}
{
*   Reset all the nodes on this bus.  This causes all node addresses to be
*   be unassigned, which causes each device to request a node address.
}
  canf.id := ioext_opcs_busreset_k;    {ID for resetting all bus nodes}
  canf.ndat := 0;                      {no data bytes}
  canf.flags := [];                    {standard data frame}
  can_send (dd.cl, canf, stat);        {send the CAN frame}
  if sys_error(stat) then goto abort;
{
*   Flush all pending received CAN frames.  Some can frames may have been
*   received before the RESET command was sent and processed by all the nodes.
*   To ignore them, we wait long enough so that all such frames would have been
*   received, then get and ignore all frames until there is no received frame
*   immediately available.  This could flush a frame sent after the RESET was
*   received, but such frames should only be requests for address, which are
*   repeated at regular intervals.
}
  sys_wait (0.100);                    {wait for any frames prior to RESET to be received}
  while can_recv(dd.cl, 0.0, canf, stat) {get all immediately available received frames}
    do begin end;
  if sys_error(stat) then goto abort;

loop:                                  {back here to get each new CAN frame}
  if dd.quit then return;              {trying to shut down driver ?}
  discard( can_recv (dd.cl, sys_timeout_none_k, canr, stat) ); {get next CAN input frame}
  if dd.quit then return;              {trying to shut down driver ?}
  if sys_error_check (stat, 'ioext', 'err_can_recv', nil, 0) then begin
    dd.quit := true;
    return;
    end;
  if can_frflag_ext_k in canr.flags then goto recv_ext; {extended frame ?}
{
*   Standard frame.
}
  case canr.id of                      {which frame is it ?}
{
******************************
*
*   REQADR sernum vendor fwtype
}
ioext_opcs_reqadr_k: begin             {node is requesting address assignment}
  if can_frflag_rtr_k in canr.flags then goto done_canr; {ignore remote request frame of this ID}
  if canr.ndat <> 7 then goto done_canr; {invalid number of data bytes ?}
  i1 := lshft(canr.dat[0], 8) ! canr.dat[1]; {get device vendor ID}
  i2 := canr.dat[2];                   {get device type ID}
  i3 :=                                {get device serial number}
    lshft(canr.dat[3], 24) !
    lshft(canr.dat[4], 16) !
    lshft(canr.dat[5], 8) !
    canr.dat[6];
{
*   Look for this device already in the list.
}
  for i4 := 1 to 255 do begin          {once for each possible bus address}
    if dd.adr[i4] = nil then next;     {this address unassigned ?}
    if dd.adr[i4]^.vend <> i1 then next; {vendor ID doesn't match ?}
    if dd.adr[i4]^.devtype <> i2 then next; {device type ID doesn't match ?}
    if dd.adr[i4]^.ser <> i3 then next; {serial number doesn't match ?}
    goto have_dev;                     {I4 is bus address of existing device}
    end;
{
*   This device is not already in the list.  Assign the first unused bus address
*   starting at NEXTADR.
}
  i4 := dd.nextadr;
  while true do begin                  {scan until find unused address}
    if dd.adr[i4] = nil then exit;     {found unused bus address ?}
    i4 := i4 + 1;                      {advance to next address}
    if i4 > 255 then i4 := 1;
    if i4 = dd.nextadr then goto done_canr; {no available adr, done with this frame ?}
    end;
{
*   I4 is the address to assign to this node.  This address is currently unused.
*   Create a new device descriptor and link it onto the list for this bus.
}
  dd.nextadr := i4 + 1;                {update first address to try next time}
  if dd.nextadr > 255 then dd.nextadr := 1;
  dd.ndev := dd.ndev + 1;              {count one more device assigned on this bus}

  dev_p := ioext_dev_new (bus_p^);     {create new unlinked device descriptor}
  dev_p^.vend := i1;                   {vendor ID}
  dev_p^.devtype := i2;                {device type}
  dev_p^.ser := i3;                    {device serial number}
  dev_p^.fwver := 0;                   {firmware version, init unknown}
  dev_p^.fwseq := 0;                   {firmware sequence number, init unknown}
  dev_p^.adr := i4;                    {assigned node address}
  string_f_int32h (dev_p^.name, dev_p^.ser); {init device name to serial number for now}

  dd.adr[dev_p^.adr] := dev_p;         {this address now in use by the new device}
  ioext_dev_add (dev_p^, stat);        {add the device to this bus}
  if sys_error(stat) then goto abort;
{
*   *** TEMPORARY KLUDGE ALERT ***
*   For now, explicitly create all the I/O lines on this device.  Eventually
*   this information will be queried from the device in a standard manner, but
*   that has not been implemented yet.  To be able to create and test other
*   parts of the system, we assume that all devices are IO1 or IO2 boards and
*   fill in the list of I/O lines accordingly.
}
  for i1 := 0 to 23 do begin           {once for each I/O line}
    io_p := ioext_io_new (dev_p^);     {create new I/O line descriptor for this device}
    io_p^.n := i1;                     {set 0-N number of this I/O line}
    string_copy (dev_p^.name, io_p^.name); {start name with device name followed by colon}
    string_append1 (io_p^.name, ':');
    if i1 <= 15
      then begin                       {digital output line (0-15)}
        string_appends (io_p^.name, 'DOUT'(0));
        string_f_int (tk, i1);
        string_append (io_p^.name, tk);

        cfgent_p := ioext_cfg_newent (io_p^); {create new configuration descriptor}
        cfgent_p^.cfg.ioty := ioext_ioty_digout_k; {digital output line}
        cfgent_p^.cfg.digout_inv := false; {init to positive logic}
        ioext_cfg_addent (io_p^, cfgent_p^); {add configuration to this I/O line}

        cfgent_p := ioext_cfg_newent (io_p^); {create new configuration descriptor}
        cfgent_p^.cfg.ioty := ioext_ioty_pwm_k; {PWM output line}
        cfgent_p^.cfg.pwm_tslice := 25.0e-6; {PWM slice period}
        cfgent_p^.cfg.pwm_slmin := 1;  {min slices in PWM period}
        cfgent_p^.cfg.pwm_slmax := 255; {max slices in PWM period}
        ioext_cfg_addent (io_p^, cfgent_p^); {add configuration to this I/O line}

        cfgent_p := ioext_cfg_newent (io_p^); {create new configuration descriptor}
        cfgent_p^.cfg.ioty := ioext_ioty_pwmph_k; {PWM output with relative phase}
        cfgent_p^.cfg.pwmph_tslice := 25.0e-6; {PWM slice period}
        cfgent_p^.cfg.pwmph_slmin := 1; {min slices in PWM period}
        cfgent_p^.cfg.pwmph_slmax := 255; {max slices in PWM period}
        ioext_cfg_addent (io_p^, cfgent_p^); {add configuration to this I/O line}
        end
      else begin                       {digital input line (16-23)}
        string_appends (io_p^.name, 'DIN'(0));
        string_f_int (tk, i1 - 16);
        string_append (io_p^.name, tk);

        cfgent_p := ioext_cfg_newent (io_p^); {create new configuration descriptor}
        cfgent_p^.cfg.ioty := ioext_ioty_digin_k; {digital input line}
        cfgent_p^.cfg.digin_inv := true; {init to negative logic, for mechanical switches}
        ioext_cfg_addent (io_p^, cfgent_p^); {add configuration to this I/O line}
        end
      ;
    ioext_io_add (io_p^, stat);
    if sys_error(stat) then goto abort;
    end;
{
*   Done artificially creating list of I/O lines.
*   *** END OF TEMPORARY KLUDGE ***
}

{
*   I4 is the address to assign this existing device.
}
have_dev:
  dev_p := dd.adr[i4];                 {get pointer to the device}

  canf.flags := [];                    {standard data frame}
  canf.id := ioext_opcs_nodeadr_k;     {ID for assigning node address}
  canf.ndat := 8;                      {number of data bytes}
  canf.dat[0] := rshft(dev_p^.vend, 8) & 255; {16 bit vendor ID, high to low byte order}
  canf.dat[1] := dev_p^.vend & 255;
  canf.dat[2] := dev_p^.devtype;       {device type ID}
  canf.dat[3] := rshft(dev_p^.ser, 24) & 255; {serial number, high to low byte order}
  canf.dat[4] := rshft(dev_p^.ser, 16) & 255;
  canf.dat[5] := rshft(dev_p^.ser, 8) & 255;
  canf.dat[6] := dev_p^.ser & 255;
  canf.dat[7] := dev_p^.adr & 255;     {address to assign}

  can_send (dd.cl, canf, stat);        {send the NODEADR command}
  if sys_error(stat) then goto abort;
{
*   Inquire the device's firmware info and current state of its digital input
*   lines.  DEV_P is pointing to the device descriptor.
}
  canf.flags := [can_frflag_ext_k, can_frflag_rtr_k]; {extended remote request frame}
  canf.id :=                           {frame ID}
    lshft(ioext_opce_digin_k, 19) !    {DIGIN opcode}
    lshft(1, 16) !                     {command, not ACK}
    lshft(0, 8) !                      {SEQ}
    dev_p^.adr;                        {assigned bus address}
  canf.ndat := 0;
  can_send (dd.cl, canf, stat);        {send the DIGIN request}
  if sys_error(stat) then goto abort;

  canf.flags := [can_frflag_ext_k, can_frflag_rtr_k]; {extended remote request frame}
  canf.id :=                           {frame ID}
    lshft(ioext_opce_fwinfo_k, 19) !   {FWINFO opcode}
    lshft(1, 16) !                     {command, not ACK}
    lshft(0, 8) !                      {SEQ}
    dev_p^.adr;                        {assigned bus address}
  canf.ndat := 0;
  can_send (dd.cl, canf, stat);        {send the FWINFO request}
  if sys_error(stat) then goto abort;
  end;                                 {end of REQADR standard frame}

    end;                               {end of recognized standard ID opcodes}
  goto done_canr;                      {done with this received CAN frame}
{
*   Extended frame.
}
recv_ext:
{
*   Extract the various fields from the extended CAN frame ID.
}
  ext_opc := rshft(canr.id, 19);       {opcode}
  ext_ack := (canr.id & 16#10000) = 0; {ACK to previous frame}
  ext_rsp := (canr.id & 16#8000) = 0;  {response to request, not asynchronous}
  ext_reqack := (canr.id & 16#4000) <> 0; {ACK requested to this frame}
  ext_first := (canr.id & 16#2000) = 0; {first frame of message}
  ext_last := (canr.id & 16#1000) = 0; {last frame of message}
  ext_seq := rshft(canr.id, 8) & 15;   {SEQ field}
  ext_adr := canr.id & 255;            {bus node address}

  dev_p := dd.adr[ext_adr];            {get pointer to device at this address}
  if dev_p = nil then goto done_canr;  {this address not assigned ?}
  case ext_opc of
{
******************************
*
*   DIGIN mask bits ... mask bits
}
ioext_opce_digin_k: begin
  if ext_ack then goto done_canr;      {ACK to previous frame ?}
  if not (ext_first and ext_last) then goto done_canr; {not only frame in message ?}
  if canr.ndat = 0 then goto done_canr; {no data, nothing to do ?}
  if odd(canr.ndat) then goto done_canr; {invalid number of data bytes ?}
  if ext_seq > 7 then goto done_canr;  {invalid set of line numbers ?}

  line := ext_seq * 32;                {make starting I/O line number}
  dind := 0;                           {init to first MASK/BITS data byte pair}
  sys_thread_lock_enter (dev_p^.lock); {temp lock the device for our use}
  while dind < canr.ndat do begin      {back here each new data bytes pair}
    i1 := canr.dat[dind];              {get MASK byte}
    dind := dind + 1;
    i2 := canr.dat[dind];              {get BITS byte}
    dind := dind + 1;
    for i3 := 0 to 7 do begin          {once for each I/O line of this byte pair}
      if not odd(i1) then goto digin_nextl; {no data for this line ?}
      io_p := dev_p^.io[line];         {get pointer to this I/O line}
      if io_p = nil then goto digin_nextl; {this I/O line doesn't exist ?}
      ch := false;                     {init to no changes made to this I/O line}
      sys_thread_lock_enter (io_p^.lock); {lock I/O line for our use}
      if                               {already configured as digital input ?}
          (io_p^.cfg_p <> nil) and then
          (io_p^.cfg_p^.ioty = ioext_ioty_digin_k)
        then goto digin_dcfg;
      cfgent_p := io_p^.cfg_first_p;   {init to first configuration in the list}
      while cfgent_p <> nil do begin   {scan thru the possible configurations}
        if cfgent_p^.cfg.ioty = ioext_ioty_digin_k then begin {found right config ?}
          io_p^.cfg_p := addr(cfgent_p^.cfg); {set to this configuration}
          ch := true;                  {indicate line state changed}
          goto digin_dcfg;             {configuration all set}
          end;
        cfgent_p := cfgent_p^.next_p;  {advance to the next configuration}
        end;                           {back to check this next configuration}
      sys_thread_lock_leave (io_p^.lock); {done messing with this I/O line}
      goto digin_nextl;                {no suitable configuration, skip this line}
digin_dcfg:                            {line configuration is all set}
      b1 := odd(i2);                   {get unflipped value of this line}
      if cfgent_p^.cfg.digin_inv then b1 := not b1; {this line inverted ?}
      if io_p^.val.digin <> b1 then begin {value is being changed ?}
        ch := true;
        io_p^.val.digin := b1;         {set the line to its new value}
        end;
      sys_thread_lock_leave (io_p^.lock); {done messing with this I/O line}
      if ch then begin                 {need to report changed value ?}
        ioext_event_in_state (bus_p^.io_p^, io_p^); {send event for changed I/O line state}
        end;
digin_nextl:                           {done with this I/O line, advance to next}
      i1 := rshft(i1, 1);              {move next MASK bit into place}
      i2 := rshft(i2, 1);              {move next BITS bit into place}
      line := line + 1;                {make number of next I/O line}
      end;                             {back for next I/O line in this byte pair}
    end;                               {back for next data byte pair}
  sys_thread_lock_leave (dev_p^.lock); {release lock on the device}
  end;                                 {end of DIGIN command}
{
******************************
*
*   DIGICH mask bits change [mask bits change]
}
ioext_opce_digich_k: begin
  if ext_ack then goto done_canr;      {ACK to previous frame ?}
  if not (ext_first and ext_last) then goto done_canr; {not only frame in message ?}
  if (canr.ndat mod 3) <> 0 then goto done_canr; {invalid number of data bytes ?}

  dind := 0;                           {init data bytes index of next group}
  while (dind + 2) <= canr.ndat do begin {back here each new group of data bytes}
    sline := (ext_seq * 16) + (dind div 3) * 8; {make starting I/O line number for this group}
    i1 := canr.dat[dind];              {get MASK byte into I1}
    dind := dind + 1;
    i2 := canr.dat[dind];              {get BITS byte into I2}
    dind := dind + 1;
    i3 := canr.dat[dind];              {get CHANGE byte into I3}
    dind := dind + 1;
    for bit := 0 to 7 do begin         {once for each bit in the group bytes}
      line := sline + bit;             {make number of this I/O line}
      if (rshft(i1, bit) & 1) = 0 then next; {this line is not a input line}
      b1 := (rshft(i2, bit) & 1) = 1;  {get new value of this line}
      ch := (rshft(i3, bit) & 1) = 1;  {device detected change in this line ?}
      io_p := dev_p^.io[line];         {get pointer to this I/O line}
      if io_p = nil then next;         {no such I/O line ?}
      sys_thread_lock_enter (io_p^.lock); {get exclusive access to this I/O line}
      if io_p^.cfg_p = nil then goto next_digich; {configuration of this line not set yet ?}

      case io_p^.cfg_p^.ioty of        {what kind of I/O line is this ?}
ioext_ioty_digin_k: begin              {digital input line}
          if io_p^.cfg_p^.digin_inv then begin {sense of this I/O line is inverted ?}
            b1 := not b1;
            end;
          ch := ch or (io_p^.val.digin <> b1); {changed from last known value ?}
          io_p^.val.digin := b1;       {set the line to the new value}
          end;
otherwise
        goto next_digich;              {I/O line type not supported for DIGICH}
        end;

      if ch then begin                 {line changed state ?}
        ioext_event_in_state (bus_p^.io_p^, io_p^); {send event for changed I/O line state}
        end;
next_digich:                           {done with this I/O line, lock being held}
      sys_thread_lock_leave (io_p^.lock); {release lock on the I/O line}
      end;                             {back to do next I/O line in this data bytes group}
    end;                               {back for next data bytes group}
  end;                                 {end of DIGICH command}
{
******************************
*
*   FWINFO fwver fwseq
}
ioext_opce_fwinfo_k: begin
  if ext_ack then goto done_canr;
  if not (ext_first and ext_last) then goto done_canr;
  if ext_seq <> 0 then goto done_canr;
  if canr.ndat <> 4 then goto done_canr;

  i1 := lshft(canr.dat[0], 8) ! canr.dat[1]; {get firmware version}
  i2 := lshft(canr.dat[2], 8) ! canr.dat[3]; {get firmware sequence number}
  ch := (i1 <> dev_p^.fwver) or (i2 <> dev_p^.fwseq); {something getting changed ?}
  dev_p^.fwver := i1;                  {set the device to the new values}
  dev_p^.fwseq := i2;
  if ch then begin                     {different firmware versions ?}
    ioext_event_dev_add (bus_p^.io_p^, dev_p^); {notify client of new device}
    end;
  for i1 := 0 to 255 do begin          {once for each possible I/O line of this device}
    io_p := dev_p^.io[i1];             {get pointer to this I/O line}
    if io_p = nil then next;           {this I/O line not defined ?}
    if not io_p^.notified then begin   {client not previously notified about this line ?}
      ioext_event_io_add (bus_p^.io_p^, io_p^); {notify client of new I/O line}
      if io_p^.cfg_p = nil then next;  {no configuration set yet ?}
      case io_p^.cfg_p^.ioty of        {check for input lines with known state}
ioext_ioty_digin_k: begin              {digital input}
          ioext_event_in_state (bus_p^.io_p^, io_p^); {notify of initial value}
          end;
        end;
      end;
    end;
  end;                                 {end of FWINFO command}

    end;                               {end of extended frame opcode cases}

done_canr:                             {done processing the current received CAN frame}
  if sys_error(stat) then goto abort;
  goto loop;                           {back to get next CAN frame}
{
*   A hard error was encountered.  STAT indicates the error.
}
abort:
  sys_thread_lock_enter (dd.lock);
  if not sys_error(dd.err) then dd.err := stat; {save first error}
  sys_thread_lock_leave (dd.lock);
  dd.quit := true;                     {indicate trying to shut down}
  end;                                 {done with DD abbreviation}
  end;                                 {end of subroutine IOEXT_BUS_CAN_CLOSE}
{
********************************************************************************
*
*   Subroutine IOEXT_BUS_CAN_SET (IO, CFG_P, VAL, STAT)
*
*   Set the I/O line IO to the configuration pointed to by CFG_P and value VAL.
*   CFG_P must be pointing to one of the configurations defined for the I/O
*   line, or it may be NIL to indicate to use the current configuration.
*
*   The I/O line must be on a device connected to a bus type supported by this
*   module.  This routine is generally called indirectly via the SET_P pointer
*   in the bus descriptor.
*
*   The lock on the I/O line must be held when this routine is called.  The lock
*   will not be released.
}
procedure ioext_bus_can_set (          {set I/O line to new state, lock held}
  in out  io: ioext_io_t;              {the I/O line to set}
  in      cfg_p: ioext_cfg_p_t;        {new config within I/O line, NIL = use current}
  in      val: ioext_val_t;            {the value to set it to}
  out     stat: sys_err_t);            {completion status}
  val_param;

var
  dd_p: dd_p_t;                        {pointer to private driver data}
  canf: can_frame_t;                   {scratch CAN frame descriptor}
  seq: sys_int_machine_t;              {0-15 CAN frame sequence field}
  ii: sys_int_machine_t;               {scratch integer}
  bit: sys_int_machine_t;              {bit number}

begin
  sys_error_none(stat);                {init to no error encountered}

  if cfg_p <> nil then io.cfg_p := cfg_p; {set to new configuration}
  if io.cfg_p = nil then begin
    sys_stat_set (ioext_subsys_k, ioext_stat_setncfg_k, stat);
    return;
    end;

  dd_p := io.dev_p^.bus_p^.dat_p;      {get pointer to private driver data}
  case io.cfg_p^.ioty of               {what configuration is it ?}

ioext_ioty_digout_k: begin             {digital output line}
  io.val.digout := val.digout;         {save new value}

  seq := io.n div 32;                  {indicate which group of 32 lines}
  canf.flags := [can_frflag_ext_k];    {extended frame}
  canf.id :=                           {frame ID}
    lshft(ioext_opce_digout_k, 19) !   {opcode}
    lshft(1, 16) !                     {command, not ACK}
    lshft(seq, 8) !                    {SEQ}
    io.dev_p^.adr;                     {assigned bus address}
  for ii := 0 to 7 do begin            {init all data bytes to 0}
    canf.dat[ii] := 0;
    end;
  ii := ((io.n - seq * 32) div 8) * 2; {offset of MASK byte}
  bit := io.n mod 8;                   {make 0-7 bit number within data bytes}
  canf.dat[ii] := lshft(1, bit);       {set the mask bit for the selected line}
  ii := ii + 1;                        {make index for the BITS byte}
  if val.digout <> io.cfg_p^.digout_inv then begin {set line to 1 ?}
    canf.dat[ii] := lshft(1, bit);
    end;
  canf.ndat := ii + 1;                 {truncate data bytes after BITS byte}
  can_send (dd_p^.cl, canf, stat);     {send the command}
  end;

ioext_ioty_pwm_k: begin                {PWM output}
  io.val.pwm_per := val.pwm_per;       {save new values}
  io.val.pwm_duty := val.pwm_duty;

  canf.flags := [can_frflag_ext_k];    {extended frame}
  canf.id :=                           {frame ID}
    lshft(ioext_opce_pwmset_k, 19) !   {opcode}
    lshft(1, 16) !                     {command, not ACK}
    lshft(0, 8) !                      {SEQ}
    io.dev_p^.adr;                     {assigned bus address}
  canf.dat[0] := io.n;                 {I/O line number}
  canf.dat[1] := rshft(io.val.pwm_per, 8) & 255;
  canf.dat[2] := io.val.pwm_per & 255;
  canf.dat[3] := rshft(io.val.pwm_duty, 8) & 255;
  canf.dat[4] := io.val.pwm_duty & 255;
  canf.ndat := 5;                      {number of data bytes}
  can_send (dd_p^.cl, canf, stat);     {send the command}
  end;

ioext_ioty_pwmph_k: begin              {PWM output with relative phase}
  io.val.pwmph_per := val.pwmph_per;   {save new values}
  io.val.pwmph_duty := val.pwmph_duty;
  io.val.pwmph_refn := val.pwmph_refn;
  io.val.pwmph_ph := val.pwmph_ph;

  canf.flags := [can_frflag_ext_k];    {extended frame}
  canf.id :=                           {frame ID}
    lshft(ioext_opce_pwmsetph_k, 19) ! {opcode}
    lshft(1, 16) !                     {command, not ACK}
    lshft(0, 8) !                      {SEQ}
    io.dev_p^.adr;                     {assigned bus address}
  canf.dat[0] := io.n;                 {I/O line number}
  canf.dat[1] := rshft(io.val.pwmph_per, 8) & 255; {period}
  canf.dat[2] := io.val.pwmph_per & 255;
  canf.dat[3] := rshft(io.val.pwmph_duty, 8) & 255; {duty cycle}
  canf.dat[4] := io.val.pwmph_duty & 255;
  canf.dat[5] := io.val.pwmph_refn & 255; {reference line number}
  canf.dat[6] := rshft(io.val.pwmph_ph, 8) & 255; {phase}
  canf.dat[7] := io.val.pwmph_ph & 255;
  canf.ndat := 8;                      {number of data bytes}
  can_send (dd_p^.cl, canf, stat);     {send the command}
  end;

otherwise
    writeln ('Configuration ID ', ord(io.cfg_p^.ioty), ' not implemented in IOEXT_BUS_CAN_SET');
    sys_bomb;
    end;
  end;
{
********************************************************************************
*
*   Subroutine IOEXT_BUS_CAN_GET (IO, VAL, STAT)
*
*   Get the current value of the I/O line IO into VAL.  This routine must only
*   be called for a I/O line connected to the type of bus supported by this
*   module.
}
procedure ioext_bus_can_get (          {get current state of I/O line}
  in out  io: ioext_io_t;              {I/O line to get the current state of}
  in out  val: ioext_val_t;            {returned value of the I/O line}
  out     stat: sys_err_t);            {completion status}
  val_param;

begin
  writeln ('IOEXT_BUS_CAN_GET not implemented yet.');
  sys_bomb;
  end;
