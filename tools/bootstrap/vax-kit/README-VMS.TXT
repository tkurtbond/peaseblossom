Peaseblossom for VAX/VMS: the STARLET kit
=========================================

This kit adds two libraries to poc @VERSION@@COMMIT@ for VAX/VMS 5.5-2,
under both size models, with their sources:

  VMSDEF  VMS's interfaces as Oberon modules: the system services
          (STARLET), the run-time library routines (LIB_ROUTINES,
          STR_ROUTINES, ...), and the constants, condition values and
          records of SYS$LIBRARY:STARLETSD.TLB's other modules (SSDEF,
          RMSDEF, IODEF, ...), generated from STARLETSD.TLB. Their
          sources are in [.SRC.RTL.VMS].
  VMSLIB  Conditions, EventFlags, ExitHandlers, LogicalNames, Symbols
          and Timers, built on VMSDEF: condition values, their messages
          and condition handlers, event flags, exit handlers, logical
          names, DCL symbols, and timers that call an AST routine. An
          AST routine is an AsynchronousTraps.Routine, from POCRTL.
          Their sources are in [.SRC.RTL.VMSLIB].

Installing
----------

1. Install poc from POC-@VERSIONNAME@.COM first (its README.TXT). This
   kit must come from the same release: it refuses a poc of any other
   version, as poc refuses a library another poc wrote.

2. Copy POC-VMS-@VERSIONNAME@.COM to VMS in ASCII (text) mode, and run
   it in the top of poc's installation, where BUILD.COM is:

       $ SET DEFAULT dev:[dir]
       $ @POC-VMS-@VERSIONNAME@

3. Build the two libraries, and set them up:

       $ @BUILD
       $ @SETUP

   @BUILD builds only what is not built yet, here VMSDEF and VMSLIB
   under both size models ("@BUILD O2" or "@BUILD OC" for one); each
   step's time is added to BUILD.LOG. @SETUP then defines their logical
   names along with POCRTL's.

Using them
----------

A module imports VMSDEF's and VMSLIB's modules as any other:

    MODULE Abort;
      IMPORT Out, Conditions, SSDEF;
      VAR text: ARRAY 256 OF CHAR;
    BEGIN
      Conditions.Message(SSDEF.SS$_ABORT, text);
      Out.String(text); Out.Ln
    END Abort.

prints "%SYSTEM-F-ABORT, abort". poc finds the libraries in [.LIB.POC]
beside its [.BIN], and links a program with each library it uses, from
its object library or, with -shared-libraries, its shareable image.

The comments in [.SRC.RTL.VMSLIB]'s modules describe VMSLIB; VMSDEF's
modules are STARLET's own definitions, which the VMS manuals describe.
