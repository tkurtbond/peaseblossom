# FTP to the VAX/VMS development system, for tools/vax-do.exp,
# tools/vax-assemble.exp and tools/vax-run.exp: "source" it after
# tools/vax-login.tcl, then
#
#   ftp_open $host           log in (the netrc file's login and password)
#   ftp_put <file> <NAME>    copy a file there
#   ftp_get <NAME> <file>    copy one back
#   ftp_delete <NAME>        delete every version of it, if there is one
#   ftp_noop                 keep the session alive
#   ftp_close                log out
#
# ftp_put and ftp_get raise an error, with the server's reply, when the
# copy fails. One session serves a tool's whole run, the copies there,
# the copies back and the deletions, kept alive by ftp_noop while the
# telnet session works: UCX 3.1's INETACP has twice brought the guest
# down (bugcheck SSRVEXCEPT, 2026-10-12 and 2026-10-13) under the stream
# of logins that a session per step made. A session the server ends is
# opened again, once per command.
#
# The server works only in active mode (PORT, the guest connecting back
# to a port opened here), and text goes in ASCII mode (TYPE A), or VMS
# stores it as fixed-length 512-byte records. The bytes are those curl
# --use-ascii sent and kept: each LF of a file goes as CR LF, which UCX
# makes the end of a variable-length record, and each CR LF coming back
# becomes LF.
# The password is never on a command line or printed.

namespace eval ftp {
  variable host ""
  variable control ""
  # seconds to wait for a reply or a connection back, and for a whole copy
  variable timeout 120
  variable copy_timeout 3600
  variable event ""
  variable data ""
}

# wait until ::ftp::event is set, or the timeout passes ("timeout")
proc ftp::wait {{seconds ""}} {
  variable timeout
  if {$seconds eq ""} { set seconds $timeout }
  set timer [after [expr {$seconds * 1000}] {set ::ftp::event timeout}]
  vwait ::ftp::event
  after cancel $timer
  set result $::ftp::event
  set ::ftp::event ""
  return $result
}

# the next line from the server, without its CR LF
proc ftp::line {} {
  variable control
  while 1 {
    if {[gets $control line] >= 0} { return [string trimright $line "\r"] }
    if {[eof $control]} { error "the FTP server closed the session" }
    fileevent $control readable {set ::ftp::event readable}
    set why [wait]
    fileevent $control readable {}
    if {$why eq "timeout"} { error "no answer from the FTP server" }
  }
}

# the server's reply, "<code> <text>", its last line when it has several
proc ftp::reply {} {
  set line [line]
  if {[regexp {^(\d{3})-} $line -> code]} {
    while {![regexp "^$code " $line]} { set line [line] }
  }
  if {![regexp {^\d{3}} $line]} { error "a reply the FTP client cannot read: $line" }
  return $line
}

# send a command, return its reply
proc ftp::command {command} {
  variable control
  puts -nonewline $control "$command\r\n"
  flush $control
  return [reply]
}

proc ftp::expect_reply {reply codes what} {
  if {[string index $reply 0] ni $codes} { error "$what: $reply" }
}

proc ftp_open {host} {
  set ::ftp::host $host
  lassign [netrc $host] login password
  if {$login eq "" || $password eq ""} { error "no login and password for $host in [netrc_file]" }
  # a guest busy with another run can be slow to answer, so three tries
  for {set try 1} {1} {incr try} {
    set control [ftp::connect $host 21]
    if {[string match sock* $control]} break
    if {$try == 3} { error "cannot connect to $host's FTP server: $control" }
    after 2000
  }
  fconfigure $control -translation binary
  set ::ftp::control $control
  ftp::expect_reply [ftp::reply] 2 "the FTP server's greeting"
  set reply [ftp::command "USER $login"]
  if {[string index $reply 0] eq "3"} { set reply [ftp::command "PASS $password"] }
  unset password
  ftp::expect_reply $reply 2 "the FTP login"
  ftp::expect_reply [ftp::command "TYPE A"] 2 "TYPE A"
}

# a nonblocking channel to host's port, or the error, within ten seconds
proc ftp::connect {host port} {
  if {[catch {socket -async $host $port} channel]} { return $channel }
  fconfigure $channel -blocking 0
  fileevent $channel writable {set ::ftp::event writable}
  set why [wait 10]
  fileevent $channel writable {}
  if {$why eq "timeout"} { close $channel; return "no answer" }
  set error [fconfigure $channel -error]
  if {$error ne ""} { close $channel; return $error }
  return $channel
}

# end the session, without waiting long for the server
proc ftp::drop {} {
  variable control
  if {$control ne ""} { catch {close $control}; set control "" }
}

proc ftp_close {} {
  catch {ftp::command QUIT}
  ftp::drop
}

# run script (a command and its reply), opening the session again once if
# the server has ended it
proc ftp::retrying {script} {
  if {[catch {uplevel 1 $script} result options]} {
    # the session ended, or a write to it failed
    if {![regexp {closed the session|no answer from|error (writing|flushing)} $result]} {
      return -options $options $result
    }
    drop
    ftp_open $::ftp::host
    return [uplevel 1 $script]
  }
  return $result
}

proc ftp_noop {} {
  ftp::retrying { ftp::command NOOP }
}

# one copy: PORT, then "<verb> <name>", the guest's connection back
# accepted here, the bytes copied by copier (called with the data
# channel), then the end of the copy; a refused data connection is tried
# twice more, each time in a new session, as curl's --retry did: UCX
# answers it with 425, or now and then with "550 Failed to open data
# connection", and once it has refused one, it can go on refusing them in
# that session
proc ftp::transfer {verb name copier} {
  for {set try 1} {1} {incr try} {
    set reply [ftp::retrying [list ftp::transfer_once $verb $name $copier]]
    if {![regexp {^425|^550 Failed to open data connection} $reply] || $try == 3} break
    drop
    after 2000
    ftp_open $::ftp::host
  }
  expect_reply $reply 2 "$verb $name"
}

proc ftp::transfer_once {verb name copier} {
  variable control
  variable data ""
  set address [lindex [fconfigure $control -sockname] 0]
  set server [socket -server ftp::accept -myaddr $address 0]
  set port [lindex [fconfigure $server -sockname] 2]
  try {
    set reply [command "PORT [string map {. ,} $address],[expr {$port >> 8}],[expr {$port & 255}]"]
    if {[string index $reply 0] ne "2"} { return $reply }
    set reply [command "$verb $name"]
    if {[string index $reply 0] ne "1"} { return $reply }
    if {$data eq ""} {
      if {[wait] eq "timeout"} { error "the FTP server did not connect back for $verb $name" }
    }
  } finally {
    close $server
  }
  try {
    fconfigure $data -translation binary
    {*}$copier $data
  } finally {
    close $data
    set data ""
  }
  return [reply]
}

proc ftp::accept {channel address port} {
  set ::ftp::data $channel
  set ::ftp::event accepted
}

# copy from one channel to another, within the timeout
proc ftp::copy {from to} {
  fcopy $from $to -command {apply {{bytes {error ""}} {set ::ftp::event [list done $error]}}}
  set why [wait $::ftp::copy_timeout]
  if {$why eq "timeout"} { error "the copy did not finish" }
  if {[lindex $why 1] ne ""} { error [lindex $why 1] }
}

proc ftp_put {file name} {
  set in [open $file rb]
  set bytes [read $in]
  close $in
  # every line ended by CR LF, as curl --use-ascii sends it: UCX ends a
  # record only at CR LF
  set bytes [string map {"\n" "\r\n"} [string map {"\r\n" "\n"} $bytes]]
  ftp::transfer STOR $name [list ftp::put_bytes $bytes]
}

proc ftp::put_bytes {bytes data} {
  puts -nonewline $data $bytes
  flush $data
}

proc ftp_get {name file} {
  set out [open $file wb]
  try {
    ftp::transfer RETR $name [list ftp::get_bytes $out]
  } finally {
    close $out
  }
  # CR LF to LF, as curl --use-ascii did
  set in [open $file rb]
  set bytes [read $in]
  close $in
  set out [open $file wb]
  puts -nonewline $out [string map {"\r\n" "\n"} $bytes]
  close $out
}

proc ftp::get_bytes {out data} {
  seek $out 0
  chan truncate $out 0
  copy $data $out
}

# every version of name deleted; UCX answers 550 to DELE name;* although it
# deletes them, and a file that is not there is no failure either
proc ftp_delete {name} {
  ftp::retrying [list ftp::command "DELE $name;*"]
}
