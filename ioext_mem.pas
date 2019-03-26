{   Routines for allocating and deallocating memory related to a specific use of
*   the IOEXT library.  All memory allocated with these routines will be
*   automatically deallocated when the use of the IOEXT library is ended.
}
module ioext_mem;
define ioext_mem_alloc_dyn;
define ioext_mem_alloc_perm;
define ioext_mem_dealloc;
%include 'ioext2.ins.pas';
{
********************************************************************************
*
*   Function IOEXT_MEM_ALLOC_DYN (IO, SZ)
*
*   Allocate memory associated with the use of the IOEXT library IO.  SZ is the
*   size of the memory region to allocate.  The new memory can be individually
*   deallocated later.  In any case, the memory will be automatically
*   deallocated when the use of the IOEXT library is ended.
}
function ioext_mem_alloc_dyn (         {allocate memory, can be separately deallocated}
  in out  io: ioext_t;                 {state for this use of the library}
  in      sz: sys_int_adr_t)           {size of memory to allocate}
  :univ_ptr;                           {pointer to start of new memory}
  val_param;

var
  adr: univ_ptr;

begin
  sys_thread_lock_enter (io.lock);
  util_mem_grab (sz, io.mem_p^, true, adr); {allocate the memory}
  sys_thread_lock_leave (io.lock);
  ioext_mem_alloc_dyn := adr;          {pass back start address of the new memory}
  end;
{
********************************************************************************
*
*   Function IOEXT_MEM_ALLOC_PERM (IO, SZ)
*
*   Allocate memory associated with the use of the IOEXT library IO.  SZ is the
*   size of the memory region to allocate.  The new memory can not be
*   individually deallocated later.  It will only be deallocated automatically
*   when the use of the IOEXT library is ended.
}
function ioext_mem_alloc_perm (        {allocate memory, unable to separately deallocate}
  in out  io: ioext_t;                 {state for this use of the library}
  in      sz: sys_int_adr_t)           {size of memory to allocate}
  :univ_ptr;                           {pointer to start of new memory}
  val_param;

var
  adr: univ_ptr;

begin
  sys_thread_lock_enter (io.lock);
  util_mem_grab (sz, io.mem_p^, false, adr); {allocate the memory}
  sys_thread_lock_leave (io.lock);
  ioext_mem_alloc_perm := adr;         {pass back start address of the new memory}
  end;
{
********************************************************************************
*
*   Subroutine IOEXT_MEM_DEALLOC (IO, ADR)
*
*   Deallocate a memory region allocated with IOEXT_MEM_ALLOC_DYN.
}
procedure ioext_mem_dealloc (          {deallocate dynamically allocated memory}
  in out  io: ioext_t;                 {state for this use of the library}
  in out  adr: univ_ptr);              {start address of memory to deallocate}
  val_param;

begin
  sys_thread_lock_enter (io.lock);
  util_mem_ungrab (adr, io.mem_p^);    {deallocate the memory}
  sys_thread_lock_leave (io.lock);
  end;
