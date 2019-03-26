{   Public include file for the IOEXT library.
*
*   This library allows applications to control the various inputs and outputs
*   of a set of I/O extender boards connected to this machine or a common bus.
}
const
  ioext_subsys_k = -57;                {ID for this subsystem}
  ioext_stat_bustype_bad_k = 1;        {illegal, unrecognized, or unexpected bus type ID}
  ioext_stat_nameused_k = 2;           {I/O line name already in use}
  ioext_stat_nfound_k = 3;             {no I/O line of that name found}
  ioext_stat_nconfig_k = 4;            {configuration of I/O line not known}
  ioext_stat_badcfg_k = 5;             {I/O line configuration does not support this operation}
  ioext_stat_nocfg_k = 6;              {no usable configuration found}
  ioext_stat_setncfg_k = 7;            {bus SET called with CFG_P NIL and not existing config}
  ioext_stat_pwmref_k = 8;             {I/O line not usable as PWMPH reference line}

type
  ioext_bus_p_t = ^ioext_bus_t;        {pointer to bus that IOEXT devices connected to}
  ioext_dev_p_t = ^ioext_dev_t;        {pointer to one IOEXT device}
  ioext_io_p_t = ^ioext_io_t;          {pointer to one I/O line of a device}
  ioext_io_pp_t = ^ioext_io_p_t;       {pointer to I/O line pointer}
  ioext_p_t = ^ioext_t;                {pointer to library use state}

  ioext_ioty_k_t = (                   {I/O line type ID}
    ioext_ioty_unk_k,                  {I/O line type or value not known}
    ioext_ioty_digout_k,               {digital output}
    ioext_ioty_digin_k,                {digital input}
    ioext_ioty_pwm_k,                  {PWM output}
    ioext_ioty_pwmph_k);               {PWM with phase relative to another PWM output}

  ioext_cfg_p_t = ^ioext_cfg_t;
  ioext_cfg_t = record                 {I/O line configuration}
    ioty: ioext_ioty_k_t;              {I/O line type ID}
    case ioext_ioty_k_t of
ioext_ioty_digout_k: (                 {digital output}
      digout_inv: boolean;             {inverted, low = true, high = false}
      );
ioext_ioty_digin_k: (                  {digital input}
      digin_inv: boolean;              {inverted, low = true, high = false}
      );
ioext_ioty_pwm_k: (                    {PWM digital output}
      pwm_tslice: real;                {slice period, seconds}
      pwm_slmin, pwm_slmax: sys_int_machine_t; {min/max slices in PWM period}
      );
ioext_ioty_pwmph_k: (                  {PWM digital output with phase lock to another line}
      pwmph_tslice: real;              {slice period, seconds}
      pwmph_slmin, pwmph_slmax: sys_int_machine_t; {min/max slices in PWM period}
      );
    end;

  ioext_cfgent_p_t = ^ioext_cfgent_t;
  ioext_cfgent_t = record              {one entry in capabilities list}
    next_p: ioext_cfgent_p_t;          {points to next list entry}
    prev_p: ioext_cfgent_p_t;          {points to previous list entry}
    cfg: ioext_cfg_t;                  {configuration described by this list entry}
    end;

  ioext_val_t = record                 {value of one I/O line}
    case ioext_ioty_k_t of             {what type of I/O line}
ioext_ioty_digout_k: (
      digout: boolean;
      );
ioext_ioty_digin_k: (
      digin: boolean;
      );
ioext_ioty_pwm_k: (
      pwm_per: int32u_t;               {1-N PWM period, units of min PWM slices}
      pwm_duty: int32u_t;              {PWM duty cycle, 0 to PWM_PER}
      );
ioext_ioty_pwmph_k: (
      pwmph_per: int32u_t;             {1-N PWM period, units of min PWM slices}
      pwmph_duty: int32u_t;            {PWM duty cycle, 0 to PWM_PER}
      pwmph_refn: sys_int_machine_t;   {number of reference line within same device}
      pwmph_ph: int32u_t;              {phase of this line relative to reference}
      );
    end;

  ioext_uval_p_t = ^ioext_uval_t;
  ioext_uval_t = record                {user-visible value of a I/O line}
    cfg: ioext_cfg_t;                  {the line's configuration}
    val: ioext_val_t;                  {the line's value within its configuration}
    end;

  ioext_io_t = record                  {info about one I/O line}
    lock: sys_sys_threadlock_t;        {exclusive lock for accessing this structure}
    dev_p: ioext_dev_p_t;              {points to device controlling the I/O line}
    n: sys_int_machine_t;              {0-255 number of the I/O line within its device}
    name: string_var32_t;              {name of this I/O line}
    cfg_first_p: ioext_cfgent_p_t;     {points to configurations list first entry}
    cfg_last_p: ioext_cfgent_p_t;      {points to configurations list last entry}
    cfg_p: ioext_cfg_p_t;              {points to current configuration}
    val: ioext_val_t;                  {current value of the I/O line}
    notified: boolean;                 {client has been notified of this line's existance}
    end;

  ioext_io_set_p_t = ^procedure (      {points to bus-specific output set routine}
    in out io: ioext_io_t;             {I/O line to set to new state, lock held}
    in    cfg_p: ioext_cfg_p_t;        {new config within I/O line, NIL = use current}
    in    val: ioext_val_t;            {new value to set line to}
    out   stat: sys_err_t);            {completion status}
    val_param;

  ioext_io_get_p_t = ^procedure (      {points to bus-specific input get routine}
    in out io: ioext_io_t;             {I/O line to get the current state of}
    in out val: ioext_val_t;           {returned value of the I/O line}
    out   stat: sys_err_t);            {completion status}
    val_param;

  ioext_dev_t = record                 {info about one IOEXT device in the system}
    bus_p: ioext_bus_p_t;              {points to bus this device connected to}
    prev_p: ioext_dev_p_t;             {points to previous device in list}
    next_p: ioext_dev_p_t;             {points to next device in list}
    lock: sys_sys_threadlock_t;        {exclusive lock for accessing this structure}
    ser: int32u_t;                     {device serial number}
    vend: int16u_t;                    {vendor ID}
    devtype: int8u_t;                  {device type ID within vendor}
    fwver: int8u_t;                    {firmware version number}
    fwseq: int8u_t;                    {firmware sequence number}
    adr: int32u_t;                     {address of this device within its bus}
    nio: sys_int_machine_t;            {number of I/O lines this device has}
    io: array [0..255] of ioext_io_p_t; {pointer to each I/O line, NIL = unimplemented}
    name: string_var32_t;              {name of this device}
    end;

  ioext_bus_close_p_t = ^procedure (   {points to bus-specific routine to close the bus}
    in     bus_p: ioext_bus_p_t);      {points to descriptor of bus to close}
    val_param;

  ioext_bus_k_t = (                    {types of busses IOEXT devices can be attached to}
    ioext_bus_none_k,                  {type not specified}
    ioext_bus_can_k);                  {CAN bus via the CAN library}

  ioext_bus_t = record                 {info about one bus that IOEXT devices attach to}
    io_p: ioext_p_t;                   {points to the library use state}
    mem_p: util_mem_context_p_t;       {points to private mem context for this bus}
    lock: sys_sys_threadlock_t;        {exclusive lock for accessing this structure}
    next_p: ioext_bus_p_t;             {points to next bus in list}
    prev_p: ioext_bus_p_t;             {points to previous bus in list}
    dev_first_p: ioext_dev_p_t;        {points to devices list first entry}
    dev_last_p: ioext_dev_p_t;         {points to devices list last entry}
    set_p: ioext_io_set_p_t;           {points to I/O line set routine}
    get_p: ioext_io_get_p_t;           {points to I/O line get routine}
    close_p: ioext_bus_close_p_t;      {points to bus close routine}
    dat_p: univ_ptr;                   {private bus driver state}
    name: string_var32_t;              {name of bus or controlling device}
    bustype: ioext_bus_k_t;            {bus type}
    end;

  ioext_opbus_t = record               {info for opening connection to a bus}
    bustype: ioext_bus_k_t;            {bus type}
    case ioext_bus_k_t of
ioext_bus_can_k: (                     {CAN bus via the CAN library}
      can_dev_p: can_dev_p_t;          {points to CAN device info}
      );
    end;

  ioext_ev_k_t = (                     {event types}
    ioext_ev_close_k,                  {closing this use of the library}
    ioext_ev_bus_add_k,                {bus added}
    ioext_ev_dev_add_k,                {device added}
    ioext_ev_io_add_k,                 {I/O line added}
    ioext_ev_in_state_k);              {input line new state}

  ioext_ev_t = record                  {info about one asynchronous event}
    evtype: ioext_ev_k_t;              {event type}
    case ioext_ev_k_t of               {data unique to each event type}
ioext_ev_close_k: (
      );
ioext_ev_bus_add_k: (
      bus_add_bus_p: ioext_bus_p_t;    {points to descriptor for new bus}
      );
ioext_ev_dev_add_k: (
      dev_add_dev_p: ioext_dev_p_t;    {points to descriptor for the new device}
      );
ioext_ev_io_add_k: (
      io_add_io_p: ioext_io_p_t;       {points to descriptor for new I/O line}
      );
ioext_ev_in_state_k: (
      in_state_io_p: ioext_io_p_t;     {points to input line that changed state}
      );
    end;

  ioext_event_p_t = ^ioext_event_t;
  ioext_event_t = record               {event queue entry}
    next_p: ioext_event_p_t;           {points to next event in queue}
    ev: ioext_ev_t;                    {the event}
    end;

  ioext_t = record                     {state for one use of this library}
    lock: sys_sys_threadlock_t;        {exclusive lock for accessing this structure}
    mem_p: util_mem_context_p_t;       {points to private memory context}
    bus_first_p: ioext_bus_p_t;        {points to busses list first entry}
    bus_last_p: ioext_bus_p_t;         {points to busses list last entry}
    hash: string_hash_handle_t;        {I/O line names to descriptor pointers hash table}
    lock_hash: sys_sys_threadlock_t;   {thread lock for accessing hash table}
    lock_ev: sys_sys_threadlock_t;     {thread lock for event queue}
    ev_mem_p: util_mem_context_p_t;    {memory context for event queue entries}
    evfirst_p: ioext_event_p_t;        {points to first event in queue}
    evlast_p: ioext_event_p_t;         {points to last event in queue}
    evfree_p: ioext_event_p_t;         {points to list of unused event queue entries}
    evnew: sys_sys_event_id_t;         {signalled when entry added to event queue}
    quit: boolean;                     {closing this use of the library}
    end;
{
*   Public routines.
}
procedure ioext_end (                  {end a use of this library}
  in out  io: ioext_t;                 {library use state, will be returned invalid}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure ioext_event_get (            {get the next sequential event}
  in out  io: ioext_t;                 {state for this use of the library}
  out     ev: ioext_ev_t);             {returned event descriptor}
  val_param; extern;

function ioext_io_get (                {get current value of a I/O line}
  in out  io: ioext_t;                 {state for this use of the library}
  in      name: univ string_var32_t;   {name of the I/O line}
  in out  uval: ioext_uval_t)          {returned value of the I/O line}
  :boolean;                            {TRUE on success, FALSE on name not found}
  val_param; extern;

procedure ioext_list (                 {add I/O line names to existing list}
  in out  io: ioext_t;                 {state for this use of the library}
  in out  list: string_list_t);        {list to add I/O line names to}
  val_param; extern;

procedure ioext_open_bus (             {open connection to a new bus of IOEXT devices}
  in out  io: ioext_t;                 {state for this use of the library}
  in      opbus: ioext_opbus_t;        {info about the bus to open a connection to}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure ioext_set_digout (           {set digital output line to new value}
  in out  io: ioext_t;                 {state for this use of the library}
  in      name: univ string_var_arg_t; {name of line to set}
  in      onoff: boolean;              {new value to set the line to}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure ioext_set_pwm (              {set PWM output to new value}
  in out  io: ioext_t;                 {state for this use of the library}
  in      name: univ string_var_arg_t; {name of line to set}
  in      per: sys_int_machine_t;      {PWM period in numbers of PWM slices}
  in      dut: sys_int_machine_t;      {duty cycle, number of slices on per period}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure ioext_set_pwmph (            {set PWM with rel phase output to new value}
  in out  io: ioext_t;                 {state for this use of the library}
  in      name: univ string_var_arg_t; {name of line to set}
  in      per: sys_int_machine_t;      {PWM period in numbers of PWM slices}
  in      dut: sys_int_machine_t;      {duty cycle, number of slices on per period}
  in      ref: univ string_var_arg_t;  {name of reference line}
  in      phase: sys_int_machine_t;    {phase rel to ref line, units of PWM slices}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure ioext_setcfg_digout (        {config as digital output and set value}
  in out  io: ioext_t;                 {state for this use of the library}
  in      name: univ string_var_arg_t; {name of line to set}
  in      onoff: boolean;              {new value to set the line to}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure ioext_setcfg_pwm (           {config as PWM and set value}
  in out  io: ioext_t;                 {state for this use of the library}
  in      name: univ string_var_arg_t; {name of line to set}
  in      per: sys_int_machine_t;      {PWM period in numbers of PWM slices}
  in      dut: sys_int_machine_t;      {duty cycle, number of slices on per period}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure ioext_setcfg_pwmph (         {config as PWM with rel phase and set value}
  in out  io: ioext_t;                 {state for this use of the library}
  in      name: univ string_var_arg_t; {name of line to set}
  in      per: sys_int_machine_t;      {PWM period in numbers of PWM slices}
  in      dut: sys_int_machine_t;      {duty cycle, number of slices on per period}
  in      ref: univ string_var_arg_t;  {name of reference line}
  in      phase: sys_int_machine_t;    {phase rel to ref line, units of PWM slices}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure ioext_start (                {start a new use of this library}
  in out  mem: util_mem_context_t;     {parent memory context}
  out     io: ioext_t;                 {returned library use state}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;
