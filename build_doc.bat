@echo off
rem
rem   BUILD_DOC
rem
rem   "Build" all the generic documentation from this source directory.  That
rem   generally means just copying it into the Embed DOC directory.
rem
setlocal
call build_vars
copya ioext_prot.txt (cog)doc/ioext_prot.txt
