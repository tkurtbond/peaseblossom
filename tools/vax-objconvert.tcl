# poc's objects on the VAX/VMS development system, for tools/vax-do.exp,
# tools/vax-run.exp and tools/vax-assemble.exp (PLAN.md Phase 18 step 4c;
# doc/developer/vax-object-language.md, sections 15.3 and 15.9, proposals
# 7 to 9): "source" it after tools/vax-login.tcl and tools/vax-ftp.tcl,
# then
#
#   objconvert_put <file> <NAME>   copy poc's object <file> there, in
#                                  binary mode, as <NAME>.CNT
#   objconvert_ready <dir> <key>   (logged in) [.BIN]OBJCONVERT.EXE built
#                                  from <dir>'s MACRO-32 unless
#                                  [.BIN]OBJCONVERT.KEY holds <key>
#                                  (tools/vax-objconvert writes both)
#   objconvert <NAME>              (logged in, ready) <NAME>.CNT converted
#                                  to <NAME>.OBJ
#   objconvert_each <NAME>...      (logged in) the converter ready, from
#                                  $VAX_OBJCONVERT_DIR and
#                                  $VAX_OBJCONVERT_KEY, which the tool's
#                                  shell script sets, and each <NAME>.CNT
#                                  converted, or the tool's "fail"
#
# The first three raise an error, with what the guest said, when they
# fail. A file sent by FTP in binary mode becomes fixed 512-byte records,
# padded with zeros, which OBJCONVERT reads as the counted records poc
# writes on Linux and the BSDs, and writes as an object, a
# variable-length record each. The converter is built in [.OBJCONVERT],
# apart from a run's own files, with the runtime that comes with it, not
# POC$RTL's.

namespace eval objconvert {
  # seconds the converter's build may take
  variable build_timeout 1800
  # the procedure that builds it, run in [.OBJCONVERT] with the key as P1
  variable build_procedure {$ ! tools/vax-objconvert.tcl: OBJCONVERT built here, from poc's
$ ! MACRO-32 for it and its runtime, into [-.BIN], with its key, P1,
$ ! in [-.BIN]OBJCONVERT.KEY; then this directory's files deleted
$ SET NOON
$ SET DEFAULT [.OBJCONVERT]
$ MACRO/OBJECT POCRTL.MAR
$ S = $STATUS
$ IF .NOT. S THEN GOTO DONE
$ DEFINE/NOLOG POC$RTL 'F$ENVIRONMENT("DEFAULT")'
$ @OBJECTCONVERT
$ S = $STATUS
$ DEASSIGN POC$RTL
$ IF .NOT. S THEN GOTO DONE
$ IF F$SEARCH("[-]BIN.DIR") .EQS. "" THEN CREATE/DIRECTORY [-.BIN]
$ COPY/NOLOG OBJECTCONVERT.EXE [-.BIN]OBJCONVERT.EXE
$ S = $STATUS
$ IF .NOT. S THEN GOTO DONE
$ PURGE/NOLOG [-.BIN]OBJCONVERT.EXE
$ OPEN/WRITE KEY [-.BIN]OBJCONVERT.KEY
$ WRITE KEY "OBJCONVERT-KEY ", P1
$ CLOSE KEY
$ PURGE/NOLOG [-.BIN]OBJCONVERT.KEY
$DONE:
$ SET DEFAULT [-]
$ DELETE/NOLOG [.OBJCONVERT]*.*;*
$ WRITE SYS$OUTPUT "OBJCONVERT-BUILT ", S
$ EXIT 1
}
}

proc objconvert_put {file name} {
  ftp_put_binary $file $name.CNT
}

# send a DCL command, wait for the prompt, and return what it printed,
# without the command's echo
proc objconvert::command {command {seconds 120}} {
  global prompt expect_out
  send "$command\r"
  expect {
    -timeout $seconds
    -re $prompt {}
    timeout { error "no prompt after $command" }
    eof { error "the telnet session ended in $command" }
  }
  set out $expect_out(buffer)
  regsub {^[^\n]*\n} $out "" out
  regsub {\r?\n?VAXASM> $} $out "" out
  regsub -all {\r} $out "" out
  return [string trim $out]
}

# $STATUS of the last command, as hexadecimal
proc objconvert::status {} {
  set out [command "WRITE SYS\$OUTPUT \"OBJCONVERT-STATUS \", \$STATUS"]
  if {![regexp {OBJCONVERT-STATUS %X([0-9A-F]{8})} $out -> hex]} { error "no status: $out" }
  return $hex
}

proc objconvert_ready {dir key} {
  set out [objconvert::command {TYPE [.BIN]OBJCONVERT.KEY}]
  if {![regexp {OBJCONVERT-KEY (\d+)} $out -> have] || $have ne $key} {
    objconvert::command {CREATE/DIRECTORY [.OBJCONVERT]}
    set procedure [file join [file dirname $dir] objconvert-build.com]
    set f [open $procedure w]
    puts -nonewline $f $objconvert::build_procedure
    close $f
    try {
      ftp_put $procedure {[.OBJCONVERT]BUILD.COM}
    } finally {
      file delete $procedure
    }
    foreach file [glob -directory $dir *] {
      ftp_put $file "\[.OBJCONVERT\][string toupper [file tail $file]]"
    }
    # a minute at a time, the FTP session kept alive in between
    send "@\[.OBJCONVERT\]BUILD $key\r"
    set deadline [expr {[clock seconds] + $objconvert::build_timeout}]
    set out ""
    while 1 {
      expect {
        -timeout 60
        -re {OBJCONVERT-BUILT %X([0-9A-F]{8})} {
          append out $expect_out(buffer)
          set hex $expect_out(1,string)
          break
        }
        -re {[^\n]*\n} { append out $expect_out(buffer); exp_continue }
        timeout {}
        eof { error "the telnet session ended while OBJCONVERT was built" }
      }
      if {[clock seconds] >= $deadline} { error "OBJCONVERT was not built within $objconvert::build_timeout seconds" }
      catch ftp_noop
    }
    expect -re $::prompt
    if {!([scan $hex %x] & 1)} { error "OBJCONVERT was not built (%X$hex):\n[string map {\r {}} $out]" }
  }
  objconvert::command {OBJCONVERT := $'F$PARSE("[.BIN]OBJCONVERT.EXE")'}
}

proc objconvert {name} {
  set out [objconvert::command "OBJCONVERT $name.CNT $name.OBJ"]
  if {$out ne ""} { error $out }
}

proc objconvert_each {names} {
  if {[llength $names] == 0} return
  if {[catch {objconvert_ready $::env(VAX_OBJCONVERT_DIR) $::env(VAX_OBJCONVERT_KEY)} message]} {
    fail "the object converter: $message"
  }
  foreach name $names {
    if {[catch {objconvert $name} message]} { fail "cannot convert $name.CNT: $message" }
  }
}
