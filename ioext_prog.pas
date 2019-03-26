{   Program IOEXT_PROG [options]
*
*   This is a custom version of PIC_PROG specifically for programming the
*   the firmware into a IOEXT I/O extender device.  This code was cloned from
*   PIC_PROG.PAS on 4 October 2009 and modified independently from there.
}
program ioext_prog;
%include 'sys.ins.pas';
%include 'util.ins.pas';
%include 'string.ins.pas';
%include 'file.ins.pas';
%include 'stuff.ins.pas';
%include 'picprg.ins.pas';

const
  max_msg_args = 4;                    {max arguments we can pass to a message}
  ndatar = 16;                         {number of unit data bytes at end of prog mem}
  crcmask = 16#04C11DB7;               {CRC XOR mask (polynomial)}

  datlast = ndatar - 1;                {last 0-N index of special data bytes}

type
  fwinfo_t = record                    {info about a firmware instance}
    vendid: int32u_t;                  {vendor ID}
    vends: string_var32_t;             {short vendor keyword, upper case}
    vendf: string_var80_t;             {full vendor name}
    fwtype: int32u_t;                  {1-N firmware type ID}
    name: string_var32_t;              {upper case firmware name}
    pic: string_var32_t;               {upper case PIC name, like 18F4580}
    ver: int32u_t;                     {1-N firmware version number}
    seq: int32u_t;                     {1-N firmware sequence number}
    serial: int32u_t;                  {serial number assigned to this device}
    valid: boolean;                    {remaining data is valid}
    end;

  fwdat_p_t = ^fwdat_t;
  fwdat_t =                            {firmware/unit data at end of prog memory}
    array[0 .. datlast] of picprg_dat_t;

var
  fnam_in:                             {HEX input file name}
    %include '(cog)lib/string_treename.ins.pas';
  srcdir:                              {treename of the applicable SRC directory}
    %include '(cog)lib/string_treename.ins.pas';
  iname_set: boolean;                  {TRUE if the input file name already set}
  pic:                                 {PIC model name}
    %include '(cog)lib/string32.ins.pas';
  pr: picprg_t;                        {PICPRG library state}
  newver: sys_int_machine_t;           {new firmware version}
  fwold, fwnew: fwinfo_t;              {info about existing and new firmare}
  tinfo: picprg_tinfo_t;               {configuration info about the target chip}
  ihn: ihex_in_t;                      {HEX file reading state}
  ii: sys_int_machine_t;               {scratch integer and loop counter}
  r: real;                             {scratch floating point value}
  timer: sys_timer_t;                  {stopwatch timer}
  tdat_p: picprg_tdat_p_t;             {pointer to target data info}
  progflags: picprg_progflags_t;       {set of options flags for programming}
  fwdat: fwdat_t;                      {info data bytes at end of program memory}
  cksum: int32u_t;                     {CRC checksum accumulator}
  quit: boolean;                       {program is being ended deliberately}
  doprog: boolean;                     {perform the program operation}
  change: boolean;                     {allow changing firmware type}
  err: boolean;                        {error announced in subordinate subroutine}
  show: boolean;                       {show current firmware, don't program}
  force: boolean;                      {force programming, even if same version}

  opts:                                {all command line options separate by spaces}
    %include '(cog)lib/string256.ins.pas';
  opt:                                 {upcased command line option}
    %include '(cog)lib/string_treename.ins.pas';
  parm:                                {command line option parameter}
    %include '(cog)lib/string_treename.ins.pas';
  pick: sys_int_machine_t;             {number of token picked from list}
  msg_parm:                            {references arguments passed to a message}
    array[1..max_msg_args] of sys_parm_msg_t;
  stat: sys_err_t;                     {completion status code}

label
  next_opt, done_opt, err_parm, err_conflict, parm_bad, done_opts,
  leave, abort, abort2;
{
********************************************************************************
*
*   Local subroutine CKSUM_INIT
*
*   Initialize the checksum accumulator.
}
procedure cksum_init;
  val_param; internal;

begin
  cksum := crcmask;
  end;
{
********************************************************************************
*
*   Local subroutine CKSUM_ADDBYTE (B)
*
*   Accumulate the byte B into the CRC checksum CKSUM.
}
procedure cksum_addbyte (
  in      b: sys_int_machine_t);       {0-255 byte value to accumulate into CRC}
  val_param; internal;

var
  ii: sys_int_machine_t;
  bits: sys_int_machine_t;
  high1: boolean;

begin
  bits := b & 255;
  for ii := 1 to 8 do begin            {once for each bit to accumulate}
    high1 := (cksum & 16#80000000) <> 0; {TRUE if shifted-out bit will be 1}
    cksum := lshft(cksum, 1) & 16#FFFFFFFF; {shift CRC left one bit}
    if (bits & 16#80) <> 0 then cksum := cksum ! 1; {shift in input bit}
    if high1 then begin                {shifted-out bit was 1 ?}
      cksum := xor(cksum, crcmask);    {apply the XOR mask}
      end;
    bits := lshft(bits, 1) & 255;      {move next input bit into position}
    end;
  end;
{
********************************************************************************
*
*   Local subroutine GET_FWINFO (LASTB, FWINFO, ERR)
*
*   Interpret the unique unit and firmware data stored at the end of program
*   memory.  LASTB is the last byte of the data bytes image.  The interpreted
*   data will be written to FWINFO.  If a hard error is encountered, then it
*   will be written to standard output and ERR set to TRUE.  ERR is set to FALSE
*   on success.
}
procedure get_fwinfo (                 {interpret firmware/unit data at end of mem}
  in var  lastb: picprg_dat_t;         {the last data word of mem image}
  out     fwinfo: fwinfo_t;            {returned info about the firmware and unit}
  out     err: boolean);               {hard error occurred, error announced}
  val_param; internal;

var
  dat_p: fwdat_p_t;                    {pointer to end of program memory image}
  ii: sys_int_conv32_t;                {integer, at least 32 bits}
  msgname: string_var80_t;             {message name}
  tk: string_var32_t;                  {scratch token}
  buf: string_var1024_t;               {message expansion string}
  p: string_index_t;                   {BUF parse index}
  stat: sys_err_t;

label
  error;

begin
  msgname.max := size_char(msgname.str); {init local var strings}
  tk.max := size_char(tk.str);
  buf.max := size_char(buf.str);

  err := false;                        {init to not returning with hard error}

  fwinfo.vends.max := size_char(fwinfo.vends.str); {init all strings to empty}
  fwinfo.vends.len := 0;
  fwinfo.vendf.max := size_char(fwinfo.vendf.str);
  fwinfo.vendf.len := 0;
  fwinfo.name.max := size_char(fwinfo.name.str);
  fwinfo.name.len := 0;
  fwinfo.pic.max := size_char(fwinfo.pic.str);
  fwinfo.pic.len := 0;
  fwinfo.valid := false;               {init to returned data is not valid}
{
*  Extract the raw info.
}
  dat_p := fwdat_p_t(                  {set pointer to start of prog image data area}
    sys_int_adr_t(addr(lastb)) - sizeof(dat_p^[0]) * (ndatar - 1));

  fwinfo.serial := dat_p^[12];         {get serial number}
  ii := dat_p^[13];
  fwinfo.serial := fwinfo.serial ! lshft(ii, 8);
  ii := dat_p^[14];
  fwinfo.serial := fwinfo.serial ! lshft(ii, 16);
  ii := dat_p^[15];
  fwinfo.serial := fwinfo.serial ! lshft(ii, 24);

  fwinfo.vendid := dat_p^[10];         {get vendor ID}
  ii := dat_p^[11];
  fwinfo.vendid := fwinfo.vendid ! lshft(ii, 8);

  fwinfo.fwtype := dat_p^[9];          {get firmware type ID}
  fwinfo.ver := dat_p^[8];             {get firmware version number}
  fwinfo.seq := dat_p^[7];             {get firmware sequence number}

  if dat_p^[6] <> 255 then return;     {verify the reserved words}
  if dat_p^[5] <> 255 then return;
  if dat_p^[4] <> 255 then return;

  if fwinfo.serial <> 16#FFFFFFFF then begin {not blank serial number ?}
    cksum_init;                        {init the checksum accumulator}
    for ii := datlast downto 0 do begin {once for each byte to accumulate into checksum}
      cksum_addbyte (dat_p^[ii]);
      end;
    if cksum <> 0 then return;         {checksum mismatch ?}
    end;

  if (fwinfo.vendid < 1) or (fwinfo.vendid > 65534) then return; {invalid vendor ID ?}
  if (fwinfo.ver < 1) or (fwinfo.ver > 254) then return; {invalid firmware version ?}
  if (fwinfo.seq < 1) or (fwinfo.seq > 254) then return; {invalid firmware sequenc number ?}
{
*   Get expanded info about the vendor.
}
  string_vstring (msgname, 'vendor_'(0), -1); {init fixed part of message name}
  string_f_int (tk, fwinfo.vendid);
  string_append (msgname, tk);         {add vendor ID}
  string_fill (msgname);               {fill trailing unused space with blanks}
  string_f_message (buf, 'ioext', msgname.str, nil, 0); {get expansion of vendor ID message}
  p := 1;                              {init BUF parse index}

  string_token (buf, p, fwinfo.vends, stat); {get short vendor ID keyword}
  if sys_error_check (stat, '', '', nil, 0) then goto error;
  string_upcase (fwinfo.vends);

  string_token (buf, p, fwinfo.vendf, stat); {get full vendor name}
  if sys_error_check (stat, '', '', nil, 0) then goto error;
{
*   Get expanded info about the firmware type from this vendor.
}
  string_vstring (msgname, 'fwtype_'(0), -1); {init fixed part of message name}
  string_f_int (tk, fwinfo.vendid);
  string_append (msgname, tk);         {add vendor ID}
  string_append1 (msgname, '_');
  string_f_int (tk, fwinfo.fwtype);
  string_append (msgname, tk);         {add firmare type ID}
  string_fill (msgname);               {fill trailing unused space with blanks}
  string_f_message (buf, 'ioext', msgname.str, nil, 0); {get expansion of vendor ID message}
  p := 1;                              {init BUF parse index}

  string_token (buf, p, fwinfo.name, stat);
  if sys_error_check (stat, '', '', nil, 0) then goto error;
  string_upcase (fwinfo.name);

  string_token (buf, p, fwinfo.pic, stat);
  if sys_error_check (stat, '', '', nil, 0) then goto error;
  string_upcase (fwinfo.pic);

  fwinfo.valid := true;                {indicate all returned info is valid}
  return;

error:                                 {hard error, message already emitted}
  err := true;                         {indicate returning after hard error}
  end;
{
********************************************************************************
*
*   Local subroutine PUT_FWINFO (LASTB, FWINFO)
*
*   This routine does the reverse of GET_FWINFO.  The firmware/unit data in
*   FWINFO is encoded into the format stored in the last bytes of program memory
*   and written to LASTB.  LASTB is the last data byte of the program memory
*   image.
}
procedure put_fwinfo (                 {set firmware/unit data at end of prog mem}
  out     lastb: picprg_dat_t;         {the last word of program memory image}
  in      fwinfo: fwinfo_t);           {firmware info to encode into prog mem}
  val_param; internal;

var
  dat_p: fwdat_p_t;                    {pointer to end of program memory image}
  ii: sys_int_conv32_t;                {integer, at least 32 bits}

begin
  dat_p := fwdat_p_t(                  {set pointer to start of prog image data area}
    sys_int_adr_t(addr(lastb)) - sizeof(dat_p^[0]) * (ndatar - 1));

  dat_p^[4] := 255;                    {reserved, must be set to 255 for now}
  dat_p^[5] := 255;
  dat_p^[6] := 255;
  dat_p^[7] := fwinfo.seq & 255;       {sequence number}
  dat_p^[8] := fwinfo.ver & 255;       {version number}
  dat_p^[9] := fwinfo.fwtype & 255;    {firmware type ID}
  dat_p^[10] := fwinfo.vendid & 255;   {vendor ID}
  dat_p^[11] := rshft(fwinfo.vendid, 8) & 255;
  dat_p^[12] := fwinfo.serial & 255;   {serial number}
  dat_p^[13] := rshft(fwinfo.serial, 8) & 255;
  dat_p^[14] := rshft(fwinfo.serial, 16) & 255;
  dat_p^[15] := rshft(fwinfo.serial, 24) & 255;

  cksum_init;                          {init checksum accumulator}
  for ii := datlast downto 4 do begin  {add bytes up to checksum into the checksum}
    cksum_addbyte (dat_p^[ii]);
    end;
  for ii := 1 to 4 do begin            {4 more zero bytes}
    cksum_addbyte (0);
    end;
  dat_p^[0] := cksum & 255;            {write the computed checksum}
  dat_p^[1] := rshft(cksum, 8) & 255;
  dat_p^[2] := rshft(cksum, 16) & 255;
  dat_p^[3] := rshft(cksum, 24) & 255;
  end;
{
********************************************************************************
*
*   Subroutine GET_LATEST_HEX (FNAM, ERR)
*
*   Return the pathname of the most recently modified HEX file of the firmware
*   version described in FWOLD.  ERR is returned true iff a hard error was
*   encountered.  In that case a appropriate error message will have been
*   written to standard output.
}
procedure get_latest_hex (
  in out  fnam: string_treename_t;     {returned pathname to lastet HEX file}
  out     err: boolean);               {hard error encountered}
  val_param; internal;

const
  max_msg_args = 1;                    {max arguments we can pass to a message}

var
  conn: file_conn_t;                   {connection to directory to find HEX file in}
  fwname: string_var32_t;              {lower case firmware name}
  ent: string_leafname_t;              {directory entry name}
  finfo: file_info_t;                  {additional info about directory entry}
  latest: string_leafname_t;           {matching dir entry most recently modified}
  ltime: sys_clock_t;                  {time entry LATEST was modified}
  ii: sys_int_machine_t;               {scratch integer and loop counter}
  comp: sys_compare_k_t;               {result of time comparision}
  msg_parm:                            {references arguments passed to a message}
    array[1..max_msg_args] of sys_parm_msg_t;
  stat: sys_err_t;                     {completion status}

label
  next_ent;

begin
  ent.max := size_char(ent.str);       {init local var strings}
  latest.max := size_char(latest.str);
  fwname.max := size_char(fwname.str);
  err := true;                         {init to returning with error}

  if not fwold.valid then begin        {don't know existing firmware type ?}
    sys_message ('ioext', 'fw_notype');
    return;
    end;

  file_open_read_dir (srcdir, conn, stat); {open HEX file directory for reading}
  if sys_error_check (stat, '', '', nil, 0) then return;
  string_copy (fwold.name, fwname);    {make lower case firmware name}
  string_downcase (fwname);
  latest.len := 0;                     {init best match so far to none}

  while true do begin                  {back here each file in the directory}
    file_read_dir (                    {get the next directory entry}
      conn,                            {connection to the directory}
      [file_iflag_dtm_k],              {get date/time of last modification}
      ent,                             {returned directory entry name}
      finfo,                           {returned info about this entry}
      stat);
    if file_eof(stat) then exit;
    if sys_error_check (stat, '', '', nil, 0) then return;
    {
    *   Check this entry for being a HEX file of the existing firmware type.
    *   The entry name must be fwnamexx.HEX, where XX must be zero or more
    *   decimal digits.
    }
    if ent.len < (fwname.len + 4) then next; {too short to be valid HEX file name ?}
    string_downcase (ent);             {make lower case for filename matching}
    for ii := 1 to fwname.len do begin {must start with firmware name}
      if ent.str[ii] <> fwname.str[ii] then goto next_ent;
      end;
    ii := fwname.len + 1;              {index of first char past firmware name}
    while true do begin                {skip over decimal digits}
      if (ent.str[ii] < '0') or (ent.str[ii] > '9') then exit; {not digit ?}
      ii := ii + 1;
      end;
    if ent.len <> (ii + 3) then next;  {remaining string not right size of ".hex" ?}
    if ent.str[ii] <> '.' then next;
    if ent.str[ii + 1] <> 'h' then next;
    if ent.str[ii + 2] <> 'e' then next;
    if ent.str[ii + 3] <> 'x' then next;
    {
    *   This entry is a HEX file of the desired firmware type.
    }
    if latest.len <> 0 then begin      {not first matching file found ?}
      comp := sys_clock_compare (finfo.modified, ltime); {compare new time to best so far}
      if (comp = sys_compare_lt_k) or (comp = sys_compare_eq_k) then next; {not newer ?}
      end;
    string_copy (ent, latest);         {update name of best file found so far}
    ltime := finfo.modified;           {save time this file was last modified}
next_ent:                              {jump here to advance to the next entry}
    end;                               {back to get next directory entry}

  if latest.len = 0 then begin         {no matching HEX file found ?}
    sys_msg_parm_vstr (msg_parm[1], fwold.name);
    sys_message_parms ('ioext', 'hex_none', msg_parm, 1);
    return;
    end;

  string_copy (srcdir, fnam);          {init returned name to directory name}
  string_append1 (fnam, '/');
  string_append (fnam, latest);
  err := false;                        {indicate returning with success}
  end;
{
********************************************************************************
*
*   Start of main routine.
}
begin
  sys_timer_init (timer);              {initialize the stopwatch}
  sys_timer_start (timer);             {start the stopwatch}
  quit := false;                       {init to not deliberately ending program}
  string_treename (string_v('(cog)src/ioext'(0)), srcdir); {make treename of our SRC directory}
  doprog := false;                     {init to not perform program operation}

  string_cmline_init;                  {init for reading the command line}
  string_append_token (opts, string_v('-HEX')); {1}
  string_append_token (opts, string_v('-SIO')); {2}
  string_append_token (opts, string_v('-N')); {3}
  string_append_token (opts, string_v('-V')); {4}
  string_append_token (opts, string_v('-PIC')); {5}
  string_append_token (opts, string_v('-CHANGE')); {6}
  string_append_token (opts, string_v('-SHOW')); {7}
  string_append_token (opts, string_v('-FORCE')); {8}
{
*   Initialize our state before reading the command line options.
}
  picprg_init (pr);                    {select defaults for opening PICPRG library}
  iname_set := false;                  {no input file name specified}
  newver := 0;                         {init to firmware version not specified}
  change := false;                     {init to not allow firmware type change}
  show := false;                       {init to not just show existing firmware}
  force := false;                      {init to not force update of same firmware}
{
*   Back here each new command line option.
}
next_opt:
  string_cmline_token (opt, stat);     {get next command line option name}
  if string_eos(stat) then goto done_opts; {exhausted command line ?}
  sys_error_abort (stat, 'string', 'cmline_opt_err', nil, 0);
  if (opt.len >= 1) and (opt.str[1] <> '-') then begin {implicit pathname token ?}
    if not iname_set then begin        {input file name not set yet ?}
      string_copy (opt, fnam_in);      {set input file name}
      iname_set := true;               {input file name is now set}
      goto next_opt;
      end;
    goto err_conflict;
    end;
  string_upcase (opt);                 {make upper case for matching list}
  string_tkpick (opt, opts, pick);     {pick command line option name from list}
  case pick of                         {do routine for specific option}
{
*   -HEX filename
}
1: begin
  if iname_set then goto err_conflict; {input file name already set ?}
  string_cmline_token (fnam_in, stat); {get the HEX file name}
  iname_set := true;
  end;
{
*   -SIO n
}
2: begin
  string_cmline_token_int (pr.sio, stat); {get serial line number}
  pr.devconn := picprg_devconn_sio_k;  {force use of serial connection}
  end;
{
*   -N progname
}
3: begin
  string_cmline_token (pr.prgname, stat); {get programmer name}
  end;
{
*   -V version
}
4: begin
  if iname_set then goto err_conflict; {input file name already set ?}
  string_cmline_token_int (newver, stat); {get firmware version number}
  if sys_error(stat) then goto err_parm;
  if (newver < 1) or (newver > 254) then goto parm_bad; {invalid version ?}
  iname_set := true;
  end;
{
*   -PIC name
}
5: begin
  string_cmline_token (pic, stat);     {get PIC model name}
  end;
{
*   -CHANGE
}
6: begin
  change := true;
  end;
{
*   -SHOW
}
7: begin
  show := true;
  end;
{
*   -FORCE
}
8: begin
  force := true;
  end;
{
*   Unrecognized command line option.
}
otherwise
    string_cmline_opt_bad;             {unrecognized command line option}
    end;                               {end of command line option case statement}
done_opt:                              {done handling this command line option}

err_parm:                              {jump here on error with parameter}
  string_cmline_parm_check (stat, opt); {check for bad command line option parameter}
  goto next_opt;                       {back for next command line option}

err_conflict:                          {this option conflicts with a previous opt}
  sys_msg_parm_vstr (msg_parm[1], opt);
  sys_message_bomb ('string', 'cmline_opt_conflict', msg_parm, 1);

parm_bad:                              {jump here on got illegal parameter}
  string_cmline_reuse;                 {re-read last command line token next time}
  string_cmline_token (parm, stat);    {re-read the token for the bad parameter}
  sys_msg_parm_vstr (msg_parm[1], parm);
  sys_msg_parm_vstr (msg_parm[2], opt);
  sys_message_bomb ('string', 'cmline_parm_bad', msg_parm, 2);

done_opts:                             {done with all the command line options}
  doprog :=                            {need to perform program operation ?}
    iname_set or (newver <> 0);
  if doprog and show then begin
    sys_message_bomb ('ioext', 'show_bad', nil, 0);
    end;
  doprog := not show;
{
*   All done reading the command line.
}
  picprg_open (pr, stat);              {open the PICPRG programmer library}
  sys_error_abort (stat, 'picprg', 'open', nil, 0);
{
*   Get the programmer firmware info and check the version.
}
  picprg_fw_show1 (pr, pr.fwinfo, stat); {show version and organization to user}
  sys_error_abort (stat, '', '', nil, 0);
  picprg_fw_check (pr, pr.fwinfo, stat); {check firmware version for compatibility}
  sys_error_abort (stat, '', '', nil, 0);
{
*   Configure to the specific target chip.
}
  picprg_config (pr, pic, stat);       {configure the library to the target chip}
  if sys_error_check (stat, '', '', nil, 0) then goto abort;
  picprg_tinfo (pr, tinfo, stat);      {get detailed info about the target chip}
  if sys_error_check (stat, '', '', nil, 0) then goto abort;

  sys_msg_parm_vstr (msg_parm[1], tinfo.name);
  sys_msg_parm_int (msg_parm[2], tinfo.rev);
  sys_message_parms ('picprg', 'target_type', msg_parm, 2); {show target name}

  picprg_tdat_alloc (pr, tdat_p, stat); {allocate and init target data}
  if sys_error_check (stat, '', '', nil, 0) then goto abort;
{
*   Read and validate the firmware info at the end of program memory.
}
  picprg_read (                        {read the info bytes from end of program memory}
    pr,                                {PICPRG library state}
    tinfo.nprog - ndatar,              {starting address of read}
    ndatar,                            {number of words to read}
    tinfo.maskprg,                     {mask of valid bits within data words}
    fwdat,                             {returned data}
    stat);

  get_fwinfo (fwdat[datlast], fwold, err); {extract stored info into FWOLD}
  if err then goto abort;
{
*   Show the existing firmware info.
}
  if fwold.valid
    then begin                         {target contains valid firmware}
      sys_msg_parm_vstr (msg_parm[1], fwold.name);
      sys_msg_parm_int (msg_parm[2], fwold.ver);
      sys_msg_parm_int (msg_parm[3], fwold.seq);
      sys_msg_parm_vstr (msg_parm[4], fwold.vendf);
      if doprog
        then begin
          sys_message_parms ('ioext', 'fw_current', msg_parm, 4);
          end
        else begin
          sys_message_parms ('ioext', 'fw_info', msg_parm, 4);
          end
        ;
      string_f_int32h (parm, fwold.serial);
      sys_msg_parm_vstr (msg_parm[1], parm);
      sys_message_parms ('ioext', 'serial', msg_parm, 1);
      end
    else begin                         {target contents is invalid}
      if doprog
        then begin                     {new firmware will be programmed in}
          end
        else begin                     {only asking what is in target}
          sys_message ('ioext', 'fw_current_invalid');
          end
        ;
      end
    ;

  if not doprog then goto leave;       {nothing more to do ?}
{
*   Make sure FNAM_IN contains the pathname of the HEX file to read.
}
  if newver <> 0 then begin            {HEX file given only by version number ?}
    if not fwold.valid then begin      {unable to get firmware type from target ?}
      sys_message ('ioext', 'fw_notype');
      goto abort;
      end;
    string_copy (srcdir, fnam_in);     {init HEX file name to our SRC directory}
    string_append1 (fnam_in, '/');
    string_append (fnam_in, fwold.name); {add firmware type name}
    ii := 2;                           {init digits in firmware version}
    if newver > 99 then ii := 3;
    string_f_int_max_base (            {make firmware version string}
      parm,                            {output string}
      newver,                          {input integer}
      10,                              {radix}
      ii,                              {fixed field width}
      [ string_fi_leadz_k,             {fill field with leading zeros}
        string_fi_unsig_k],            {the input number is unsigned}
      stat);
    if sys_error_check (stat, '', '', nil, 0) then goto abort;
    string_append (fnam_in, parm);     {add specific version string to file name}
    end;

  if fnam_in.len = 0 then begin        {no file name or version given ?}
    get_latest_hex (fnam_in, err);     {get pathname of most recent HEX file of this type}
    if err then goto abort;
    end;
{
*   Read the HEX file data and save it in the target data structure TDAT_P^.
}
  ihex_in_open_fnam (fnam_in, '.hex .HEX'(0), ihn, stat); {try HEX filename as given}
  if file_not_found(stat) then begin   {no such file, try in SRC directory}
    file_currdir_set (srcdir, stat);   {go to the SRC directory}
    if sys_error_check (stat, '', '', nil, 0) then goto abort;
    ihex_in_open_fnam (fnam_in, '.hex .HEX'(0), ihn, stat); {try again in the SRC directory}
    end;
  if sys_error_check (stat, '', '', nil, 0) then goto abort;
  string_copy (ihn.conn_p^.tnam, fnam_in); {save final HEX file full treename}

  picprg_tdat_hex_read (tdat_p^, ihn, stat); {read HEX file and save target data}
  if sys_error_check (stat, '', '', nil, 0) then goto abort;

  ihex_in_close (ihn, stat);           {close the HEX file}
  if sys_error_check (stat, '', '', nil, 0) then goto abort;

  get_fwinfo (tdat_p^.val_prog_p^[tinfo.nprog-1], fwnew, err); {get info on new firmware}
  if err then goto abort;
  if not fwnew.valid then begin        {HEX file doesn't contain valid firmware ?}
    sys_msg_parm_vstr (msg_parm[1], fnam_in);
    sys_message_parms ('ioext', 'hex_invalid', msg_parm, 1);
    goto abort;
    end;

  sys_msg_parm_vstr (msg_parm[1], fwnew.name); {announce the new firmware version}
  sys_msg_parm_int (msg_parm[2], fwnew.ver);
  sys_msg_parm_int (msg_parm[3], fwnew.seq);
  sys_msg_parm_vstr (msg_parm[4], fwnew.vendf);
  sys_message_parms ('ioext', 'fw_new', msg_parm, 4);

  if                                   {same version, not force overwite ?}
      fwold.valid and                  {existing firmware version is known ?}
      (not force) and                  {not force fimware write ?}
      (fwnew.vendid = fwold.vendid) and {same vendor ?}
      (fwnew.fwtype = fwold.fwtype) and {same firmware type within vendor ?}
      (fwnew.ver = fwold.ver) and      {same version with firmare type ?}
      (fwnew.seq = fwold.seq) and      {same sequence number within version ?}
      (fwold.serial <> 16#FFFFFFFF) and (fwold.serial <> 0) {serial number is valid ?}
      then begin
    sys_message ('ioext', 'fw_same');
    goto leave;
    end;
{
*   Set the unique data to program into the unit at the end of program memory.
*   This data is first collected in FWNEW, then that information is used to
*   update the last locations of the program memory image to write to the
*   target.
}
  if not string_equal (tinfo.name, fwnew.pic) then begin {wrong target PIC ?}
    sys_message ('ioext', 'target_mismatch');
    goto abort;
    end;

  if
      fwold.valid and                  {existing firmware info is known ?}
      (fwnew.fwtype <> fwold.fwtype) and {not the same firmware type ?}
      (not change)                     {firmware change not allowed ?}
      then begin
    sys_message ('ioext', 'fw_mismatch');
    goto abort;
    end;

  if                                   {init new serial number to existing ?}
      fwold.valid and                  {existing serial number is known ?}
      (fwnew.fwtype = fwold.fwtype)    {new firmware is same type as old ?}
      then begin
    fwnew.serial := fwold.serial;
    end;

  if                                   {need to assign new serial number ?}
      (fwnew.serial = 0) or (fwnew.serial = 16#FFFFFFFF) {not a valid serial number}
      then begin
    string_vstring (parm, '(cog)progs/ioext_prog/'(0), -1); {init sequence pathname}
    string_copy (fwnew.vends, opt);
    string_downcase (opt);
    string_append (parm, opt);         {add vendor ID keyword}
    string_append1 (parm, '_');
    string_copy (fwnew.name, opt);
    string_downcase (opt);
    string_append (parm, opt);         {add firmware name}
    fwnew.serial := string_seq_get (   {get new serial number}
      parm,                            {sequence file pathname}
      1,                               {amount to increment sequence number by}
      1,                               {first value if not previously existing}
      [],                              {get number before increment applied}
      stat);
    if sys_error_check (stat, '', '', nil, 0) then goto abort;
    string_f_int32h (opt, fwnew.serial); {make HEX serial number string}
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_parms (                {announce the new serial number}
      'ioext', 'serial_assign', msg_parm, 1);
    end;

  put_fwinfo (                         {set unit info data at end of prog mem}
    tdat_p^.val_prog_p^[tinfo.nprog-1], fwnew);
{
*   Preserve the EEPROM contents if appropriate.  This is done by reading the
*   existing EEPROM data into the data that will be written to the target.  The
*   EEPROM data is only preserved if known to be updating within the same
*   firmware type.
}
  if                                   {need to preserve existing EEPROM data ?}
      fwold.valid and                  {existing firmware type is known ?}
      (fwnew.fwtype = fwold.fwtype) and {updating within same firmware type ?}
      (tinfo.ndat > 0)                 {this target chip has EEPROM ?}
      then begin
    picprg_space_set (pr, picprg_space_data_k, stat); {switch to EEPROM address space}
    if sys_error_check (stat, '', '', nil, 0) then goto abort;
    picprg_read (                      {read from the target chip}
      pr,                              {PICPRG library state}
      0,                               {starting address to read from}
      tinfo.ndat,                      {number of words to read}
      tinfo.maskdat,                   {mask for valid data bits}
      tdat_p^.val_data_p^,             {where to read the data to}
      stat);
    if sys_error_check (stat, '', '', nil, 0) then goto abort;
    picprg_space_set (pr, picprg_space_data_k, stat); {switch back to prog adr space}
    if sys_error_check (stat, '', '', nil, 0) then goto abort;
    end;
{
*   Perform the programming operation.
}
  progflags := [                       {select program/verify options}
    picprg_progflag_stdout_k];         {write progress to standard output}
  picprg_tdat_prog (tdat_p^, progflags, stat); {program the target}
  if sys_error_check (stat, '', '', nil, 0) then goto abort;
{
*   Common point for exiting the program under normal conditions with the PICPRG
*   library open.
}
leave:                                 {clean up and close connection to this target}
  sys_timer_stop (timer);              {stop the stopwatch}
  r := sys_timer_sec (timer);          {get total elapsed seconds}
  sys_msg_parm_real (msg_parm[1], r);
  sys_message_parms ('picprg', 'no_errors', msg_parm, 1);
  quit := true;                        {indicate exiting normally, no error}
{
*   Exit point with the PICPRG library open.  QUIT set indicates that
*   the program is being aborted deliberately and that should not be
*   considered an error.
*
*   If jumping here due to error, then the error message must already have been
*   written.
}
abort:
  picprg_off (pr, stat);               {disengage from the target system}
  sys_error_abort (stat, '', '', nil, 0);
{
*   Programmer has already disengaged from the target to the exent possible.
}
abort2:
  picprg_close (pr, stat);             {close the PICPRG library}
  sys_error_abort (stat, 'picprg', 'close', nil, 0);
  if not quit then begin               {aborting program on error ?}
    sys_bomb;                          {exit the program with error status}
    end;
  end.
