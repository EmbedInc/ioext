{   Routines for setting output lines to specific states.
}
module ioext_set;
define ioext_setcfg_digout;
define ioext_setcfg_pwm;
define ioext_setcfg_pwmph;
define ioext_set_digout;
define ioext_set_pwm;
define ioext_set_pwmph;
%include 'ioext2.ins.pas';
{
********************************************************************************
*
*   Subroutine IOEXT_SETCFG_DIGOUT (IO, NAME, ONOFF, STAT)
*
*   Configure the I/O line NAME to be a digital output and set its value to
*   ONOFF.
}
procedure ioext_setcfg_digout (        {config as digital output and set value}
  in out  io: ioext_t;                 {state for this use of the library}
  in      name: univ string_var_arg_t; {name of line to set}
  in      onoff: boolean;              {new value to set the line to}
  out     stat: sys_err_t);            {completion status}
  val_param;

var
  io_p: ioext_io_p_t;                  {pointer to I/O line}
  val: ioext_val_t;                    {new value for the line}
  cfg_p: ioext_cfg_p_t;                {pointer to new configuration}
  cfgent_p: ioext_cfgent_p_t;          {pointer to config list entry}

begin
  sys_error_none (stat);               {init to no error encountered}

  io_p := ioext_io_find (io, name);    {find and lock the I/O line}
  if io_p = nil then begin             {no such I/O line}
    sys_stat_set (ioext_subsys_k, ioext_stat_nfound_k, stat);
    sys_stat_parm_vstr (name, stat);
    return;
    end;

  if                                   {already configured as desired ?}
      (io_p^.cfg_p <> nil) and then    {configuration is set ?}
      (io_p^.cfg_p^.ioty = ioext_ioty_digout_k) {is the required configuration ?}
    then begin
      cfg_p := nil;
      end
    else begin                         {need to find appropriate configuration}
      cfgent_p := io_p^.cfg_first_p;
      while cfgent_p <> nil do begin   {scan the list of possible configurations}
        if cfgent_p^.cfg.ioty = ioext_ioty_digout_k {found usable configuration ?}
          then exit;
        cfgent_p := cfgent_p^.next_p;  {advance to next config in list}
        end;
      if cfgent_p = nil then begin     {no usable configuration ?}
        sys_thread_lock_leave (io_p^.lock);
        sys_stat_set (ioext_subsys_k, ioext_stat_nocfg_k, stat);
        sys_stat_parm_vstr (name, stat);
        return;
        end;
      cfg_p := addr(cfgent_p^.cfg);    {get pointer to the new configuration}
      end
    ;

  val.digout := onoff;
  io_p^.dev_p^.bus_p^.set_p^ (io_p^, cfg_p, val, stat); {set line to new value}
  sys_thread_lock_leave (io_p^.lock);
  end;
{
********************************************************************************
*
*   Subroutine IOEXT_SETCFG_PWM (IO, NAME, PER, DUT, STAT)
*
*   Configure the I/O line NAME to be a PWM output and set its value.  PER is
*   the PWM period in number of slices.  This value is silently clipped to the
*   valid range as indicated in the configuration.  DUT is the duty cycle, which
*   is the number of slices the output will be on for per period.  The DUT value
*   is silently clipped to the 0 to PER range.
}
procedure ioext_setcfg_pwm (           {config as PWM and set value}
  in out  io: ioext_t;                 {state for this use of the library}
  in      name: univ string_var_arg_t; {name of line to set}
  in      per: sys_int_machine_t;      {PWM period in numbers of PWM slices}
  in      dut: sys_int_machine_t;      {duty cycle, number of slices on per period}
  out     stat: sys_err_t);            {completion status}
  val_param;

var
  io_p: ioext_io_p_t;                  {pointer to I/O line}
  val: ioext_val_t;                    {new value for the line}
  cfg_p: ioext_cfg_p_t;                {pointer to configuration in use}
  cfgarg_p: ioext_cfg_p_t;             {pointer to new configuration}
  cfgent_p: ioext_cfgent_p_t;          {pointer to config list entry}

begin
  sys_error_none (stat);               {init to no error encountered}

  io_p := ioext_io_find (io, name);    {find and lock the I/O line}
  if io_p = nil then begin             {no such I/O line}
    sys_stat_set (ioext_subsys_k, ioext_stat_nfound_k, stat);
    sys_stat_parm_vstr (name, stat);
    return;
    end;

  if                                   {already configured as desired ?}
      (io_p^.cfg_p <> nil) and then    {configuration is set ?}
      (io_p^.cfg_p^.ioty = ioext_ioty_pwm_k) {is the required configuration ?}
    then begin
      cfg_p := io_p^.cfg_p;
      cfgarg_p := nil;
      end
    else begin                         {need to find appropriate configuration}
      cfgent_p := io_p^.cfg_first_p;
      while cfgent_p <> nil do begin   {scan the list of possible configurations}
        if cfgent_p^.cfg.ioty = ioext_ioty_pwm_k {found usable configuration ?}
          then exit;
        cfgent_p := cfgent_p^.next_p;  {advance to next config in list}
        end;
      if cfgent_p = nil then begin     {no usable configuration ?}
        sys_thread_lock_leave (io_p^.lock);
        sys_stat_set (ioext_subsys_k, ioext_stat_nocfg_k, stat);
        sys_stat_parm_vstr (name, stat);
        return;
        end;
      cfg_p := addr(cfgent_p^.cfg);    {get pointer to the new configuration}
      cfgarg_p := cfg_p;
      end
    ;

  val.pwm_per := max(cfg_p^.pwm_slmin, min(cfg_p^.pwm_slmax, per)); {PWM period}
  val.pwm_duty := max(0, min(val.pwm_per, dut)); {duty cycle}
  io_p^.dev_p^.bus_p^.set_p^ (io_p^, cfgarg_p, val, stat); {set line to new value}
  sys_thread_lock_leave (io_p^.lock);
  end;
{
********************************************************************************
*
*   Subroutine IOEXT_SETCFG_PWMPH (IO, NAME, PER, DUT, REF, PHASE, STAT)
*
*   Configure the I/O line NAME to be a PWM output with relative phase, and set
*   its value.  PER is the PWM period in number of slices.  This value is
*   silently clipped to the valid range as indicated in the configuration.  DUT
*   is the duty cycle, which is the number of slices the output will be on for
*   per period.  The DUT value is silently clipped to the 0 to PER range.  REF
*   is the name of the reference line.  This must be a PWM or PWMPH output on
*   the same device.  PHASE is the relative phase of this line with respect to
*   the reference line.  It is the number of PWM slices this line will lag the
*   reference line.  This makes little sense unless the two lines are set to the
*   same period.
}
procedure ioext_setcfg_pwmph (         {config as PWM with rel phase and set value}
  in out  io: ioext_t;                 {state for this use of the library}
  in      name: univ string_var_arg_t; {name of line to set}
  in      per: sys_int_machine_t;      {PWM period in numbers of PWM slices}
  in      dut: sys_int_machine_t;      {duty cycle, number of slices on per period}
  in      ref: univ string_var_arg_t;  {name of reference line}
  in      phase: sys_int_machine_t;    {phase rel to ref line, units of PWM slices}
  out     stat: sys_err_t);            {completion status}
  val_param;

var
  ref_p: ioext_io_p_t;                 {pointer to phase reference line}
  refn: sys_int_machine_t;             {number of reference line within same device}
  io_p: ioext_io_p_t;                  {pointer to I/O line}
  val: ioext_val_t;                    {new value for the line}
  cfg_p: ioext_cfg_p_t;                {pointer to new configuration}
  cfgarg_p: ioext_cfg_p_t;             {pointer to new configuration}
  cfgent_p: ioext_cfgent_p_t;          {pointer to config list entry}
  dev_p: ioext_dev_p_t;                {device of reference line}
  iotyr: ioext_ioty_k_t;               {config type of the reference line}

label
  bad_ref;

begin
  sys_error_none (stat);               {init to no error encountered}

  ref_p := ioext_io_find (io, ref);    {find and lock the phase reference line}
  if ref_p = nil then begin
    sys_stat_set (ioext_subsys_k, ioext_stat_nfound_k, stat);
    sys_stat_parm_vstr (ref, stat);
    return;
    end;
  dev_p := ref_p^.dev_p;               {get reference line device}
  if dev_p = nil then begin
    sys_thread_lock_leave (ref_p^.lock);
    goto bad_ref;
    end;
  iotyr := ioext_ioty_unk_k;           {init to ref line type not known}
  if (ref_p^.cfg_p <> nil) then begin
    iotyr := ref_p^.cfg_p^.ioty;
    end;
  refn := ref_p^.n;                    {save number of ref line within its device}
  sys_thread_lock_leave (ref_p^.lock); {release lock on the reference line}

  case iotyr of                        {how is reference line configured}
ioext_ioty_pwm_k,
ioext_ioty_pwmph_k: ;
otherwise
bad_ref:
    sys_stat_set (ioext_subsys_k, ioext_stat_pwmref_k, stat);
    sys_stat_parm_vstr (ref, stat);
    sys_stat_parm_vstr (name, stat);
    return;
    end;                               {end of ref line type cases}

  io_p := ioext_io_find (io, name);    {find and lock the I/O line}
  if io_p = nil then begin             {no such I/O line}
    sys_stat_set (ioext_subsys_k, ioext_stat_nfound_k, stat);
    sys_stat_parm_vstr (name, stat);
    return;
    end;
  if io_p^.dev_p <> dev_p then begin   {not on same device as reference line ?}
    sys_thread_lock_leave (io_p^.lock);
    goto bad_ref;
    end;

  if                                   {already configured as desired ?}
      (io_p^.cfg_p <> nil) and then    {configuration is set ?}
      (io_p^.cfg_p^.ioty = ioext_ioty_pwmph_k) {is the required configuration ?}
    then begin
      cfg_p := io_p^.cfg_p;
      cfgarg_p := nil;
      end
    else begin                         {need to find appropriate configuration}
      cfgent_p := io_p^.cfg_first_p;
      while cfgent_p <> nil do begin   {scan the list of possible configurations}
        if cfgent_p^.cfg.ioty = ioext_ioty_pwmph_k {found usable configuration ?}
          then exit;
        cfgent_p := cfgent_p^.next_p;  {advance to next config in list}
        end;
      if cfgent_p = nil then begin     {no usable configuration ?}
        sys_thread_lock_leave (io_p^.lock);
        sys_stat_set (ioext_subsys_k, ioext_stat_nocfg_k, stat);
        sys_stat_parm_vstr (name, stat);
        return;
        end;
      cfg_p := addr(cfgent_p^.cfg);    {get pointer to the new configuration}
      cfgarg_p := cfg_p;
      end
    ;

  val.pwmph_per := max(cfg_p^.pwm_slmin, min(cfg_p^.pwm_slmax, per)); {PWM period}
  val.pwmph_duty := max(0, min(val.pwm_per, dut)); {duty cycle}
  val.pwmph_refn := refn;              {number of the reference line}
  val.pwmph_ph := phase;               {phase relative to the reference line}
  io_p^.dev_p^.bus_p^.set_p^ (io_p^, cfgarg_p, val, stat); {set line to new value}
  sys_thread_lock_leave (io_p^.lock);
  end;
{
********************************************************************************
*
*   Subroutine IOEXT_SET_DIGOUT (IO, NAME, ONOFF, STAT)
*
*   Set the digital output line NAME to the value ONOFF.
}
procedure ioext_set_digout (           {set digital output line to new value}
  in out  io: ioext_t;                 {state for this use of the library}
  in      name: univ string_var_arg_t; {name of line to set}
  in      onoff: boolean;              {new value to set the line to}
  out     stat: sys_err_t);            {completion status}
  val_param;

var
  io_p: ioext_io_p_t;                  {pointer to I/O line}
  cfg_p: ioext_cfg_p_t;                {pointer to the configuration of this line}
  val: ioext_val_t;                    {new value for the line}

begin
  sys_error_none (stat);               {init to no error encountered}

  io_p := ioext_io_find (io, name);    {find and lock the I/O line}
  if io_p = nil then begin             {no such I/O line}
    sys_stat_set (ioext_subsys_k, ioext_stat_nfound_k, stat);
    sys_stat_parm_vstr (name, stat);
    return;
    end;

  cfg_p := io_p^.cfg_p;                {get pointer to line configuration}
  if cfg_p = nil then begin            {configuration of this line not set ?}
    sys_thread_lock_leave (io_p^.lock);
    sys_stat_set (ioext_subsys_k, ioext_stat_nconfig_k, stat);
    sys_stat_parm_vstr (name, stat);
    return;
    end;

  case cfg_p^.ioty of                  {what is configuration of this line ?}
ioext_ioty_digout_k: begin             {digital output}
      val.digout := onoff;
      end;
ioext_ioty_pwm_k: begin                {normal PWM output}
      val.pwm_per := io_p^.val.pwm_per; {preserve PWM period}
      if onoff
        then val.pwm_duty := val.pwm_per {max duty cycle for ON}
        else val.pwm_duty := 0;        {0 duty cycle for OFF}
      end;
ioext_ioty_pwmph_k: begin              {PWM output with relative phase to another line}
      val.pwmph_per := io_p^.val.pwmph_per; {preserve PWM period}
      if onoff
        then val.pwmph_duty := val.pwmph_per {max duty cycle for ON}
        else val.pwmph_duty := 0;      {0 duty cycle for OFF}
      val.pwmph_refn := io_p^.val.pwmph_refn; {preserve reference line}
      val.pwmph_ph := io_p^.val.pwmph_ph; {preserve phase from ref line}
      end;
otherwise                              {incompatible configuration}
    sys_thread_lock_leave (io_p^.lock);
    sys_stat_set (ioext_subsys_k, ioext_stat_badcfg_k, stat);
    sys_stat_parm_vstr (name, stat);
    return;
    end;

  io_p^.dev_p^.bus_p^.set_p^ (io_p^, nil, val, stat); {set line to new value}
  sys_thread_lock_leave (io_p^.lock);
  end;
{
********************************************************************************
*
*   Subroutine IOEXT_SET_PWM (IO, NAME, PER, DUT, STAT)
*
*   Set the PWM output line NAME to a new value.  PER is the PWM period in
*   number of slices.  This value is silently clipped to the valid range as
*   indicated in the configuration.  DUT is the duty cycle, which is the number
*   of slices the output will be on for per period.  The DUT value is silently
*   clipped to the 0 to PER range.
}
procedure ioext_set_pwm (              {set PWM output to new value}
  in out  io: ioext_t;                 {state for this use of the library}
  in      name: univ string_var_arg_t; {name of line to set}
  in      per: sys_int_machine_t;      {PWM period in numbers of PWM slices}
  in      dut: sys_int_machine_t;      {duty cycle, number of slices on per period}
  out     stat: sys_err_t);            {completion status}
  val_param;

var
  io_p: ioext_io_p_t;                  {pointer to I/O line}
  cfg_p: ioext_cfg_p_t;                {pointer to the configuration of this line}
  val: ioext_val_t;                    {new value for the line}

begin
  sys_error_none (stat);               {init to no error encountered}

  io_p := ioext_io_find (io, name);    {find and lock the I/O line}
  if io_p = nil then begin             {no such I/O line}
    sys_stat_set (ioext_subsys_k, ioext_stat_nfound_k, stat);
    sys_stat_parm_vstr (name, stat);
    return;
    end;

  cfg_p := io_p^.cfg_p;                {get pointer to line configuration}
  if cfg_p = nil then begin            {configuration of this line not set ?}
    sys_thread_lock_leave (io_p^.lock);
    sys_stat_set (ioext_subsys_k, ioext_stat_nconfig_k, stat);
    sys_stat_parm_vstr (name, stat);
    return;
    end;

  case cfg_p^.ioty of                  {what is configuration of this line ?}
ioext_ioty_pwm_k: begin                {normal PWM output}
      val.pwm_per := max(cfg_p^.pwm_slmin, min(cfg_p^.pwm_slmax, per)); {PWM period}
      val.pwm_duty := max(0, min(val.pwm_per, dut)); {duty cycle}
      end;
ioext_ioty_pwmph_k: begin              {PWM output with relative phase to another line}
      val.pwmph_per := max(cfg_p^.pwmph_slmin, min(cfg_p^.pwmph_slmax, per)); {PWM period}
      val.pwmph_duty := max(0, min(val.pwmph_per, dut)); {duty cycle}
      val.pwmph_refn := io_p^.val.pwmph_refn; {preserve reference line}
      val.pwmph_ph := io_p^.val.pwmph_ph; {preserve phase from ref line}
      end;
otherwise                              {incompatible configuration}
    sys_thread_lock_leave (io_p^.lock);
    sys_stat_set (ioext_subsys_k, ioext_stat_badcfg_k, stat);
    sys_stat_parm_vstr (name, stat);
    return;
    end;

  io_p^.dev_p^.bus_p^.set_p^ (io_p^, cfg_p, val, stat); {set line to new value}
  sys_thread_lock_leave (io_p^.lock);
  end;
{
********************************************************************************
*
*   Subroutine IOEXT_SET_PWMPH (IO, NAME, PER, DUT, REF, PHASE, STAT)
*
*   Set the PWM with relative phase output line NAME to be a new value.  PER is
*   the PWM period in number of slices.  This value is silently clipped to the
*   valid range as indicated in the configuration.  DUT is the duty cycle, which
*   is the number of slices the output will be on for per period.  The DUT value
*   is silently clipped to the 0 to PER range.  REF is the name of the reference
*   line.  This must be a PWM or PWMPH output on the same device.  PHASE is the
*   relative phase of this line with respect to the reference line.  It is the
*   number of PWM slices this line will lag the reference line.  This makes
*   little sense unless the two lines are set to the same period.
}
procedure ioext_set_pwmph (            {set PWM with rel phase output to new value}
  in out  io: ioext_t;                 {state for this use of the library}
  in      name: univ string_var_arg_t; {name of line to set}
  in      per: sys_int_machine_t;      {PWM period in numbers of PWM slices}
  in      dut: sys_int_machine_t;      {duty cycle, number of slices on per period}
  in      ref: univ string_var_arg_t;  {name of reference line}
  in      phase: sys_int_machine_t;    {phase rel to ref line, units of PWM slices}
  out     stat: sys_err_t);            {completion status}
  val_param;

var
  ref_p: ioext_io_p_t;                 {pointer to phase reference line}
  refn: sys_int_machine_t;             {number of reference line within same device}
  io_p: ioext_io_p_t;                  {pointer to I/O line}
  val: ioext_val_t;                    {new value for the line}
  cfg_p: ioext_cfg_p_t;                {pointer to new configuration}
  dev_p: ioext_dev_p_t;                {device of reference line}
  iotyr: ioext_ioty_k_t;               {config type of the reference line}

label
  bad_ref;

begin
  sys_error_none (stat);               {init to no error encountered}

  ref_p := ioext_io_find (io, ref);    {find and lock the phase reference line}
  if ref_p = nil then begin
    sys_stat_set (ioext_subsys_k, ioext_stat_nfound_k, stat);
    sys_stat_parm_vstr (ref, stat);
    return;
    end;
  dev_p := ref_p^.dev_p;               {get reference line device}
  if dev_p = nil then begin
    sys_thread_lock_leave (ref_p^.lock);
    goto bad_ref;
    end;
  iotyr := ioext_ioty_unk_k;           {init to ref line type not known}
  if (ref_p^.cfg_p <> nil) then begin
    iotyr := ref_p^.cfg_p^.ioty;
    end;
  refn := ref_p^.n;                    {save number of ref line within its device}
  sys_thread_lock_leave (ref_p^.lock); {release lock on the reference line}

  case iotyr of                        {how is reference line configured}
ioext_ioty_pwm_k,
ioext_ioty_pwmph_k: ;
otherwise
bad_ref:
    sys_stat_set (ioext_subsys_k, ioext_stat_pwmref_k, stat);
    sys_stat_parm_vstr (ref, stat);
    sys_stat_parm_vstr (name, stat);
    return;
    end;                               {end of ref line type cases}

  io_p := ioext_io_find (io, name);    {find and lock the I/O line}
  if io_p = nil then begin             {no such I/O line}
    sys_stat_set (ioext_subsys_k, ioext_stat_nfound_k, stat);
    sys_stat_parm_vstr (name, stat);
    return;
    end;
  if io_p^.dev_p <> dev_p then begin   {not on same device as reference line ?}
    sys_thread_lock_leave (io_p^.lock);
    goto bad_ref;
    end;

  cfg_p := io_p^.cfg_p;                {get pointer to line configuration}
  if cfg_p = nil then begin            {configuration of this line not set ?}
    sys_thread_lock_leave (io_p^.lock);
    sys_stat_set (ioext_subsys_k, ioext_stat_nconfig_k, stat);
    sys_stat_parm_vstr (name, stat);
    return;
    end;

  case cfg_p^.ioty of                  {what is configuration of this line ?}
ioext_ioty_pwmph_k: begin              {PWM output with relative phase to another line}
      val.pwmph_per := max(cfg_p^.pwmph_slmin, min(cfg_p^.pwmph_slmax, per)); {PWM period}
      val.pwmph_duty := max(0, min(val.pwmph_per, dut)); {duty cycle}
      val.pwmph_refn := refn;          {number of the reference line}
      val.pwmph_ph := phase;           {phase relative to the reference line}
      end;
otherwise                              {incompatible configuration}
    sys_thread_lock_leave (io_p^.lock);
    sys_stat_set (ioext_subsys_k, ioext_stat_badcfg_k, stat);
    sys_stat_parm_vstr (name, stat);
    return;
    end;

  io_p^.dev_p^.bus_p^.set_p^ (io_p^, cfg_p, val, stat); {set line to new value}
  sys_thread_lock_leave (io_p^.lock);
  end;
