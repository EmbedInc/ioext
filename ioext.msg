/*   Messages unique to the IOEXT library.
/*
msg err1
  lan english -def
    Unexpected bus type of %p1i encountered in routine %p2s.
msg err2
  lan english -def
    The new I/O line "%p1s" can not be added to the system because its name is
    already in use.
msg err3
  lan english -def
    No I/O line with name "%p1s" is known.
msg err4
  lan english -def
    The configuration of I/O line "%p1s" is not known.
msg err5
  lan english -def
    The configuration of I/O line "%p1s" does not support this operation.
msg err6
  lan english -def
    The I/O line "%p1s" can not be configured as desired.
msg err7
  lan english -def
    INTERNAL ERROR:  The bus SET routine was called with the CFG_P argument NIL
    but without a previous configuration defined for the I/O line.
msg err7
  lan english -def
    I/O line "%p1s" is not usable as the PWM reference for I/O line "%p2s".
/*
/*   Messages not related to error codes.
/*
msg bus_can_nopen
  lan english -def
    Unable to open CAN bus via device %p1s.
msg bus_can_opened
  lan english -def
    Opened CAN bus using device %p1s.
msg bus_open_none
  lan english -def
    No available IOEXT compatible bus opened.
msg err_can_recv
  lan english -def
    Error on attempt to get next received CAN frame.
msg fw_current
  lan english -def
    Old firmware is %p1s ver %p2i seq %p3i by %p4s.
msg fw_current_invalid
  lan english -def
    The target does not contain valid firmware.
msg fw_info
  lan english -def
    Firmware is %p1s ver %p2i seq %p3i by %p4s.
msg fw_mismatch
  lan english -def
    Firmware mismatch.
msg fw_new
  lan english -def
    New firmware is %p1s ver %p2i seq %p3i by %p4s.
msg fw_notype
  lan english -def
    The target does not contain valid existing firmware.  Unable to determine
    the firmware type.
msg fw_same
  lan english -def
    Target already contains the desired firmare, programming skipped.
msg hex_invalid
  lan english -def
    The HEX file "%p1s" does not contain valid firmware.
msg hex_none
  lan english -def
    No HEX file for firmware type %p1s was found.
msg serial
  lan english -def
    Serial number %p1s
msg serial_assign
  lan english -def
    Assigning serial number %p1s
msg show_bad
  lan english -def
    Input file name or version is not allowed with -SHOW.
msg target_mismatch
  lan english -def
    Invalid firmware for this unit.
/*
/*   Expansions of vendor and firmware IDs.
/*
msg vendor_1
  lan english -def
    Embed "Embed Inc"
msg fwtype_1_1
  lan english -def
    io1c 18F4580
