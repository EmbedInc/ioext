@echo off
rem
rem   BUILD_LIB [-dbg]
rem
rem   Build the IOEXT library.
rem
setlocal
call build_pasinit

call src_insall %srcdir% %libname%

call src_pas %srcdir% %libname%_bus %1
call src_pas %srcdir% %libname%_bus_can %1
call src_pas %srcdir% %libname%_cfg %1
call src_pas %srcdir% %libname%_dev %1
call src_pas %srcdir% %libname%_event %1
call src_pas %srcdir% %libname%_io %1
call src_pas %srcdir% %libname%_mem %1
call src_pas %srcdir% %libname%_set %1
call src_pas %srcdir% %libname%_start %1

call src_lib %srcdir% %libname%
call src_msg %srcdir% %libname%
