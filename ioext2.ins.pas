{   Private include file for the IOEXT library.
}
%include 'sys.ins.pas';
%include 'util.ins.pas';
%include 'string.ins.pas';
%include 'file.ins.pas';
%include 'can.ins.pas';
%include 'ioext.ins.pas';
{
********************************************************************************
*
*   CAN bus opcodes used by the IOEXT system.
*
*   The opcodes are broken into two independent namespaces, one for standard CAN
*   frames (11 bit ID), and the other for extended CAN frames (29 bit ID).  The
*   opcode is the high bits of the ID in both cases.  Since these are the first
*   bits used in arbitrating CAN collisions, each opcode gives its message a
*   fixed priority relative to all other opcodes.  Standard frames have priority
*   over extended frames, and 0 has priority over 1.  The priority of opcodes
*   therefore starts with opcode 0 for standard frames as the highest priority,
*   to the last standard frame opcode, then to opcode 0 for extended frames,
*   then to the last extended frame opcode.  This is also the order the opcodes
*   are listed here.
}
const
{
*   Standard frame opcodes.  All 11 bits of the frame ID are used for the
*   opcode, so opcodes range from 0 to 2047.
}
  ioext_opcs_busreset_k = 0;           {reset bus state, unassign all addresses}
  ioext_opcs_nodeadr_k = 2046;         {assign node address to specific unit}
  ioext_opcs_reqadr_k = 2047;          {unit requests node address assignment}
{
*   Extended frame opcodes.  The upper 10 bits of the 29 bit frame ID are the
*   opcode, so opcodes range from 0 to 1023.
}
  ioext_opce_digout_k = 0;             {set digital outputs to fixed values}
  ioext_opce_digin_k = 1;              {report state of digital inputs}
  ioext_opce_digich_k = 32;            {report changed digital inputs}
  ioext_opce_pwmset_k = 129;           {set PWM parameters of a line}
  ioext_opce_pwmsetph_k = 130;         {set PWM parameters with relative phase of a line}
  ioext_opce_fwinfo_k = 960;           {report firmware information}
{
********************************************************************************
}
procedure ioext_bus_can_open (         {open connection to CAN bus via CAN library}
  in out  io: ioext_t;                 {state for this use of the library}
  in      opbus: ioext_opbus_t;        {info about the bus to open a connection to}
  in out  bus: ioext_bus_t;            {descriptor for the new bus}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure ioext_bus_dev_add (          {add device to a bus}
  in out  bus: ioext_bus_t;            {the bus to add a device to}
  in out  dev: ioext_dev_t);           {the device to add}
  val_param; extern;

procedure ioext_cfg_addent (           {add fully filled in configuration to I/O line}
  in out  iol: ioext_io_t;             {I/O line to add the configuration to}
  in out  cfgent: ioext_cfgent_t);     {the configuration to add}
  val_param; extern;

function ioext_cfg_newent (            {create new unlinked configuration list entry}
  in out  iol: ioext_io_t)             {I/O line the configuration is for}
  :ioext_cfgent_p_t;                   {returned pointer to new config list entry}
  val_param; extern;

procedure ioext_dev_add (              {add device to its bus}
  in out  dev: ioext_dev_t;            {the device to add}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

function ioext_dev_new (               {create new unlinked device descriptor}
  in out  bus: ioext_bus_t)            {bus the device is connected to}
  :ioext_dev_p_t;                      {returned pointer to the new descriptor}
  val_param; extern;

procedure ioext_event_bus_add (        {create event for new bus added}
  in out  io: ioext_t;                 {state for this use of the library}
  in      bus: ioext_bus_t);           {bus that was added}
  extern;

procedure ioext_event_dev_add (        {create event for new device added}
  in out  io: ioext_t;                 {state for this use of the library}
  in      dev: ioext_dev_t);           {device that was added}
  extern;

procedure ioext_event_enqueue (        {add entry to end of event queue}
  in out  io: ioext_t;                 {state for this use of the library}
  in out  event: ioext_event_t);       {the entry to add to end of queue}
  val_param; extern;

procedure ioext_event_in_state (       {create event for input line state changed}
  in out  io: ioext_t;                 {state for this use of the library}
  in      ioline: ioext_io_t);         {the I/O line that changed state}
  extern;

procedure ioext_event_io_add (         {create event for new I/O line added}
  in out  io: ioext_t;                 {state for this use of the library}
  in out  ioline: ioext_io_t);         {the I/O line that was added}
  extern;

function ioext_event_newent (          {get unused event queue entry}
  in out  io: ioext_t)                 {state for this use of the library}
  :ioext_event_p_t;                    {returned pointing to new event queue entry}
  val_param; extern;

procedure ioext_io_add (               {add I/O line descriptor to its device}
  in out  iol: ioext_io_t;             {the I/O line to add}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

function ioext_io_find (               {find I/O line by name and lock it}
  in out  io: ioext_t;                 {state for this use of the library}
  in      name: univ string_var_arg_t) {name of the I/O line}
  :ioext_io_p_t;                       {returned pointer to I/O line, NIL on not found}
  val_param; extern;

function ioext_io_new (                {create new unlinked I/O line descriptor}
  in out  dev: ioext_dev_t)            {device the I/O line is connected to}
  :ioext_io_p_t;                       {returned pointer to the new descriptor}
  val_param; extern;

function ioext_mem_alloc_dyn (         {allocate memory, can be separately deallocated}
  in out  io: ioext_t;                 {state for this use of the library}
  in      sz: sys_int_adr_t)           {size of memory to allocate}
  :univ_ptr;                           {pointer to start of new memory}
  val_param; extern;

function ioext_mem_alloc_perm (        {allocate memory, unable to separately deallocate}
  in out  io: ioext_t;                 {state for this use of the library}
  in      sz: sys_int_adr_t)           {size of memory to allocate}
  :univ_ptr;                           {pointer to start of new memory}
  val_param; extern;

procedure ioext_mem_dealloc (          {deallocate dynamically allocated memory}
  in out  io: ioext_t;                 {state for this use of the library}
  in out  adr: univ_ptr);              {start address of memory to deallocate}
  val_param; extern;
