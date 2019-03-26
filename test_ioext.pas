{   Program TEST_IOEXT
*
*   Program to test the IOEXT library.
}
program test_ioext;
%include 'sys.ins.pas';
%include 'util.ins.pas';
%include 'string.ins.pas';
%include 'file.ins.pas';
%include 'can.ins.pas';
%include 'ioext.ins.pas';

const
  max_msg_parms = 2;                   {max parameters we can pass to a message}

var
  io: ioext_t;                         {IOEXT library use state}
  candevs: can_devs_t;                 {list of CAN devices known to the system}
  canent_p: can_dev_ent_p_t;           {points to CAN devices list entry}
  opbus: ioext_opbus_t;                {state for opening new bus}
  wrlock: sys_sys_threadlock_t;        {lock for writing to standard output}
  prompt:                              {prompt string for entering command}
    %include '(cog)lib/string4.ins.pas';
  buf:                                 {one line command buffer}
    %include '(cog)lib/string8192.ins.pas';
  p: string_index_t;                   {BUF parse index}
  thev: sys_sys_thread_id_t;           {ID of event reading thread}
  uval: ioext_uval_t;                  {complete user value of a I/O line}
  name, name2:                         {command name parameters}
    %include '(cog)lib/string32.ins.pas';
  i1, i2, i3: sys_int_machine_t;       {command parameters}
  quit: boolean;                       {TRUE when trying to exit the program}
  newline: boolean;                    {STDOUT stream is at start of new line}
  b1: boolean;                         {boolean command parameter}
  cmds:                                {command names separated by spaces}
    %include '(cog)lib/string8192.ins.pas';

  opt:                                 {upcased command line option}
    %include '(cog)lib/string_treename.ins.pas';
  parm:                                {command parameter}
    %include '(cog)lib/string_treename.ins.pas';
  pick: sys_int_machine_t;             {number of token picked from list}
  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;
  stat: sys_err_t;                     {completion status}

label
  loop_cmd, done_cmd, err_extra, err_cmparm, leave;
{
********************************************************************************
*
*   Subroutine ADDCMD (NAME)
*
*   Add the command NAME to the commands list.
}
procedure addcmd (                     {add command to commands list}
  in      name: string);               {name of command to add, blank pad or NULL term}
  val_param; internal;

var
  n: string_var32_t;                   {upper case var string copy of command name}

begin
  n.max := size_char(n.str);           {init local var string}

  string_vstring (n, name, size_char(name)); {make var string command name}
  string_upcase (n);                   {upper case for keyword mathing later}
  string_append_token (cmds, n);       {append to end of commands list}
  end;
{
********************************************************************************
*
*   Subroutine LOCKOUT
*
*   Acquire exclusive lock for writing to standard output.
}
procedure lockout;

begin
  sys_thread_lock_enter (wrlock);
  if not newline then writeln;         {start on a new line}
  newline := true;                     {init to STDOUT will be at start of line}
  end;
{
********************************************************************************
*
*   Subroutine UNLOCKOUT
*
*   Release exclusive lock for writing to standard output.
}
procedure unlockout;

begin
  sys_thread_lock_leave (wrlock);
  end;
{
********************************************************************************
*
*   Subroutine THREAD_EVENT (ARG)
*
*   Root routine for the thread that gets events from the IOEXT library.  ARG
*   is not used.
}
procedure thread_event (               {root routine for event getting thread}
  in      arg: sys_int_adr_t);         {unused}
  val_param;

var
  ev: ioext_ev_t;                      {last event received}
  cfgent_p: ioext_cfgent_p_t;          {scratch I/O line configuration list entry}
  tk: string_var32_t;                  {scratch token}

label
  next_ev;

begin
  tk.max := size_char(tk.str);         {init local var string}

next_ev:                               {back here to get each new event}
  ioext_event_get (io, ev);            {get the next event into EV}
  case ev.evtype of                    {what kind of event is it ?}
{
*   This use of the IOEXT library is being closed.
}
ioext_ev_close_k: begin
  sys_thread_exit;
  end;
{
*   A new bus was added.
}
ioext_ev_bus_add_k: begin
  with ev.bus_add_bus_p^:bus do begin  {set up BUS abbreviation}
  lockout;
  write ('Added ');
  case bus.bustype of
ioext_bus_can_k: write ('CAN bus');
otherwise
    write ('bus type ', ord(bus.bustype));
    end;
  writeln (' "', bus.name.str:bus.name.len, '"');
  unlockout;
  end;                                 {end of BUS abbreviation}
  end;
{
*   A new device was added.
}
ioext_ev_dev_add_k: begin
  with ev.dev_add_dev_p^:dev do begin  {set up DEV abbreviation}
  lockout;
  writeln ('Added device ', dev.name.str:dev.name.len, ' to bus ',
    dev.bus_p^.name.str:dev.bus_p^.name.len, ' at address ', dev.adr, ':');
  string_f_int32h (tk, dev.ser);
  writeln ('  Vendor ID     ', dev.vend);
  writeln ('  Device type   ', dev.devtype);
  writeln ('  Serial number ', tk.str:tk.len);
  writeln ('  Firmware vers ', dev.fwver);
  writeln ('  Firmware seq  ', dev.fwseq);
  unlockout;
  end;                                 {end of DEV abbreviation}
  end;
{
*   A new I/O line was added.
}
ioext_ev_io_add_k: begin
  with ev.io_add_io_p^:iol do begin    {set up IOL abbreviation}
  lockout;
  writeln ('Added I/O line ', iol.n, ' "', iol.name.str:iol.name.len, '" to device ',
    iol.dev_p^.name.str:iol.dev_p^.name.len, ', configurations:');
  cfgent_p := iol.cfg_first_p;
  while cfgent_p <> nil do begin       {back here each new configuration}
    case cfgent_p^.cfg.ioty of         {what type of I/O line is this ?}
ioext_ioty_digout_k: begin             {digital output}
        writeln ('  Digital output');
        end;
ioext_ioty_digin_k: begin              {digital input}
        writeln ('  Digital input');
        end;
ioext_ioty_pwm_k: begin                {PWM output}
        writeln ('  PWM output');
        end;
ioext_ioty_pwmph_k: begin              {PWM with relative phase control}
        writeln ('  PWM output with relative phase');
        end;
otherwise
      writeln ('  Unknown configuration type ', ord(cfgent_p^.cfg.ioty));
      end;
    cfgent_p := cfgent_p^.next_p;      {advance to next configuration in list}
    end;                               {back to handle this new configuration}
  unlockout;
  end;                                 {done with IOL abbreviation}
  end;
{
*   A input line changed state.
}
ioext_ev_in_state_k: begin
  with ev.in_state_io_p^:iol do begin  {set up IOL abbreviation}
  lockout;
  write ('Line ', iol.name.str:iol.name.len, ' = ');
  case iol.cfg_p^.ioty of
ioext_ioty_digin_k: begin
      write ('digital in, ');
      if iol.val.digin
        then write ('ON')
        else write ('OFF');
      end;
otherwise
    write ('Unexpected type ', ord(iol.cfg_p^.ioty));
    end;
  writeln;
  unlockout;
  end;                                 {done with IOL abbreviation}
  end;
{
*   Unexpected event type.
}
otherwise
    lockout;
    writeln ('Received event of unexpected type ', ord(ev.evtype));
    unlockout;
    end;

  goto next_ev;
  end;
{
********************************************************************************
*
*   Function NOT_EOS
*
*   Returns TRUE if the input buffer BUF was is not exhausted.  This is
*   used to check for additional tokens at the end of a command.
}
function not_eos                       {check for more tokens left}
  :boolean;                            {TRUE if more tokens left in BUF}

var
  psave: string_index_t;               {saved copy of BUF parse index}
  tk: string_var4_t;                   {token parsed from BUF}
  stat: sys_err_t;                     {completion status code}

begin
  tk.max := size_char(tk.str);         {init local var string}

  not_eos := false;                    {init to BUF has been exhausted}
  psave := p;                          {save current BUF parse index}
  string_token (buf, p, tk, stat);     {try to get another token}
  if sys_error(stat) then return;      {assume normal end of line encountered ?}
  not_eos := true;                     {indicate a token was found}
  p := psave;                          {reset parse index to get this token again}
  end;
{
********************************************************************************
*
*   Start of main routine.
}
begin
  ioext_start (util_top_mem_context, io, stat); {start use of the IOEXT library}
  sys_error_abort (stat, '', '', nil, 0);
{
*   Open all suitable CAN busses.
}
  can_devlist_get (util_top_mem_context, candevs); {get list of CAN devices}
  opbus.bustype := ioext_bus_can_k;    {type of bus to open}
  canent_p := candevs.list_p;          {init pointer to first device in list}
  while canent_p <> nil do begin       {once for each device in list}
    opbus.can_dev_p := addr(canent_p^.dev); {indicate device to open}
    ioext_open_bus (io, opbus, stat);  {open this bus}
    if sys_error(stat)
      then begin                       {didn't open the bus}
        sys_msg_parm_vstr (msg_parm[1], canent_p^.dev.name);
        sys_message_parms ('ioext', 'bus_can_nopen', msg_parm, 1);
        end
      else begin                       {bus successfully opened}
        sys_msg_parm_vstr (msg_parm[1], canent_p^.dev.name);
        sys_message_parms ('ioext', 'bus_can_opened', msg_parm, 1);
        end
      ;
    canent_p := canent_p^.next_p;      {advance to next device in list}
    end;
  can_devlist_del (candevs);           {deallocate CAN devices list}
{
*   Abort if no busses opened.
}
  if io.bus_first_p = nil then begin   {no busses open ?}
    sys_message_bomb ('ioext', 'bus_open_none', nil, 0);
    end;
{
*   Start up the system.
}
  sys_thread_lock_create (wrlock, stat); {create interlock for writing to STDOUT}
  sys_error_abort (stat, '', '', nil, 0);

  sys_thread_create (                  {start the event processing thread}
    addr(thread_event),                {root thread routine address}
    0,                                 {argument passed to thread routine, unused}
    thev,                              {returned ID of the new thread}
    stat);
  sys_error_abort (stat, '', '', nil, 0);

  quit := false;                       {init to not trying to exit the program}
  newline := true;                     {STDOUT is currently at start of new line}
  string_vstring (prompt, ': '(0), -1); {set command prompt string}

  addcmd ('?');                        {1}
  addcmd ('HELP');                     {2}
  addcmd ('Q');                        {3}
  addcmd ('GET');                      {4}
  addcmd ('CFG');                      {5}
  addcmd ('SET');                      {6}
{
***************************************
*
*   Process user commands.
}
loop_cmd:                              {back here each new input line}
  sys_wait (0.100);
  lockout;
  string_prompt (prompt);              {prompt the user for a command}
  newline := false;                    {indicate STDOUT not at start of new line}
  unlockout;

  string_readin (buf);                 {get command from the user}
  newline := true;                     {STDOUT now at start of line}
  if buf.len <= 0 then goto loop_cmd;  {ignore blank lines}
  p := 1;                              {init BUF parse index}
  string_token (buf, p, opt, stat);    {get command name token into OPT}
  if string_eos(stat) then goto loop_cmd; {ignore line if no command found}
  if sys_error(stat) then goto err_cmparm;
  string_upcase (opt);
  string_tkpick (opt, cmds, pick);     {pick command name from list}
  case pick of
{
***************************************
*
*   HELP
}
1, 2: begin
  if not_eos then goto err_extra;
  lockout;
  writeln;
  writeln ('? or HELP   - Show this list of commands');
  writeln ('Q           - Quit the program');
  writeln ('GET name    - Get current state of I/O line');
  writeln ('CFG name config value - configure I/O line and set value');
  writeln ('    Config and value options:');
  writeln ('  DIGOUT onoff');
  writeln ('  PWM period duty');
  writeln ('  PWMPH period duty refname phase');
  writeln ('SET name config value - set output line value, keep config');
  writeln ('    Config and value options:');
  writeln ('  DIGOUT onoff');
  writeln ('  PWM period duty');
  writeln ('  PWMPH period duty refname phase');
  unlockout;
  end;
{
***************************************
*
*   Q
}
3: begin
  if not_eos then goto err_extra;
  goto leave;
  end;
{
***************************************
*
*   GET name
}
4: begin
  string_token (buf, p, parm, stat);
  if sys_error(stat) then goto err_cmparm;
  if not_eos then goto err_extra;

  if not ioext_io_get (io, parm, uval) then begin
    lockout;
    writeln ('No such I/O line.');
    unlockout;
    goto done_cmd;
    end;

  lockout;
  case uval.cfg.ioty of                {what type of I/O line is it ?}

ioext_ioty_unk_k: begin
  writeln ('Line not configured.');
  end;

ioext_ioty_digout_k: begin
  write ('Digital output: ');
  if uval.val.digout
    then write ('ON')
    else write ('OFF');
  writeln;
  end;

ioext_ioty_digin_k: begin
  write ('Digital input: ');
  if uval.val.digin
    then write ('ON')
    else write ('OFF');
  writeln;
  end;

ioext_ioty_pwm_k: begin
  string_f_fp_fixed (parm, 1.0 / (uval.cfg.pwm_tslice * uval.val.pwm_per), 1); {Hz}
  write ('PWM output: ', parm.str:parm.len, ' Hz');
  string_f_fp_fixed (parm, uval.val.pwm_duty/uval.val.pwm_per, 4); {duty cycle}
  writeln (', duty cycle ', uval.val.pwm_duty, '/', uval.val.pwm_per,
    ' = ', parm.str:parm.len);
  end;

ioext_ioty_pwmph_k: begin
  string_f_fp_fixed (parm, 1.0 / (uval.cfg.pwmph_tslice * uval.val.pwmph_per), 1);
  write ('PWM output: ', parm.str:parm.len, ' Hz');
  string_f_fp_fixed (parm, uval.val.pwmph_duty/uval.val.pwmph_per, 4); {duty cycle}
  writeln (', duty cycle ', uval.val.pwmph_duty, '/', uval.val.pwmph_per,
    ' = ', parm.str:parm.len,
    ', ref ', uval.val.pwmph_refn, ', phase ', uval.val.pwmph_ph);
  end;

otherwise
    writeln ('Unexpected I/O line type ID of ', ord(uval.cfg.ioty), ' encountered.');
    end;                               {end of line type cases}
  unlockout;
  end;
{
***************************************
*
*   CFG name config value
}
5: begin
  string_token (buf, p, name, stat);   {get I/O line name into NAME}
  if sys_error(stat) then goto err_cmparm;
  string_token (buf, p, parm, stat);   {get config name into PARM}
  if sys_error(stat) then goto err_cmparm;
  string_upcase (parm);
  string_tkpick80 (parm,
    'DIGOUT PWM PWMPH',
    pick);
  case pick of

1: begin                               {DIGOUT onoff}
  string_token (buf, p, parm, stat);   {get onoff}
  if sys_error(stat) then goto err_cmparm;
  string_t_bool (parm, [string_tftype_onoff_k], b1, stat);
  if sys_error(stat) then goto err_cmparm;
  if not_eos then goto err_extra;
  ioext_setcfg_digout (io, name, b1, stat);
  end;

2: begin                               {PWM per duty}
  string_token_int (buf, p, i1, stat); {period}
  if sys_error(stat) then goto err_cmparm;
  string_token_int (buf, p, i2, stat); {duty cycle}
  if sys_error(stat) then goto err_cmparm;
  if not_eos then goto err_extra;
  ioext_setcfg_pwm (io, name, i1, i2, stat);
  end;

3: begin                               {PWMPH per duty ref phase}
  string_token_int (buf, p, i1, stat); {period}
  if sys_error(stat) then goto err_cmparm;
  string_token_int (buf, p, i2, stat); {duty cycle}
  if sys_error(stat) then goto err_cmparm;
  string_token (buf, p, name2, stat);  {reference line name}
  if sys_error(stat) then goto err_cmparm;
  string_token_int (buf, p, i3, stat); {phase}
  if sys_error(stat) then goto err_cmparm;
  if not_eos then goto err_extra;
  ioext_setcfg_pwmph (io, name, i1, i2, name2, i3, stat);
  end;

otherwise
    lockout;
    writeln ('Invalid configuration type name.');
    unlockout;
    p := buf.len + 1;
    end;
  end;
{
***************************************
*
*   SET name config value
}
6: begin
  string_token (buf, p, name, stat);   {get I/O line name into NAME}
  if sys_error(stat) then goto err_cmparm;
  string_token (buf, p, parm, stat);   {get config name into PARM}
  if sys_error(stat) then goto err_cmparm;
  string_upcase (parm);
  string_tkpick80 (parm,
    'DIGOUT PWM PWMPH',
    pick);
  case pick of

1: begin                               {DIGOUT onoff}
  string_token (buf, p, parm, stat);   {get onoff}
  if sys_error(stat) then goto err_cmparm;
  string_t_bool (parm, [string_tftype_onoff_k], b1, stat);
  if sys_error(stat) then goto err_cmparm;
  if not_eos then goto err_extra;
  ioext_set_digout (io, name, b1, stat);
  end;

2: begin                               {PWM per duty}
  string_token_int (buf, p, i1, stat); {period}
  if sys_error(stat) then goto err_cmparm;
  string_token_int (buf, p, i2, stat); {duty cycle}
  if sys_error(stat) then goto err_cmparm;
  if not_eos then goto err_extra;
  ioext_set_pwm (io, name, i1, i2, stat);
  end;

3: begin                               {PWMPH per duty ref phase}
  string_token_int (buf, p, i1, stat); {period}
  if sys_error(stat) then goto err_cmparm;
  string_token_int (buf, p, i2, stat); {duty cycle}
  if sys_error(stat) then goto err_cmparm;
  string_token (buf, p, name2, stat);  {reference line name}
  if sys_error(stat) then goto err_cmparm;
  string_token_int (buf, p, i3, stat); {phase}
  if sys_error(stat) then goto err_cmparm;
  if not_eos then goto err_extra;
  ioext_set_pwmph (io, name, i1, i2, name2, i3, stat);
  end;

otherwise
    lockout;
    writeln ('Can not set value of this type of I/O line.');
    unlockout;
    p := buf.len + 1;
    end;                               {end of line type cases}
  end;
{
***************************************
*
*   Unrecognized command.
}
otherwise
    lockout;
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_parms ('string', 'err_command_bad', msg_parm, 1);
    unlockout;
    goto loop_cmd;
    end;

done_cmd:                              {done processing the current command}
  if sys_error(stat) then goto err_cmparm; {handle error, if any}

  if not_eos then begin                {extraneous token after command ?}
err_extra:
    lockout;
    writeln ('Too many parameters for this command.');
    unlockout;
    end;
  goto loop_cmd;                       {back to process next command input line}

err_cmparm:                            {parameter error, STAT set accordingly}
  lockout;
  sys_error_print (stat, '', '', nil, 0);
  unlockout;
  goto loop_cmd;

leave:
  quit := true;                        {tell all threads to shut down}
  ioext_end (io, stat);                {end this use of the IOEXT library}
  sys_error_abort (stat, '', '', nil, 0);
  end.
