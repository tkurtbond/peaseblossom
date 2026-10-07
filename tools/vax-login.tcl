# The VAX/VMS development system's login, by telnet, for tools/vax-assemble.exp
# and tools/vax-run.exp: "source" it, then "vax_login $host", which leaves the
# session at the prompt "VAXASM> " ($prompt, a regular expression), or exits 2
# with a message. The password is read from ~/.netrc here, never on a command
# line, and nothing is shown while it is sent (log_user 0).
# doc/developer/DEVELOPER.md, section 4.

# login and password of "machine $host" in ~/.netrc
proc netrc {host} {
  set f [open [file join $::env(HOME) .netrc] r]
  set tokens [regexp -all -inline {\S+} [read $f]]
  close $f
  set login ""; set password ""; set here 0
  for {set i 0} {$i < [llength $tokens]} {incr i} {
    set t [lindex $tokens $i]
    if {$t eq "machine"} {
      incr i; set here [expr {[lindex $tokens $i] eq $host}]
    } elseif {$t eq "default"} {
      set here 0
    } elseif {$here && $t eq "login"} {
      incr i; set login [lindex $tokens $i]
    } elseif {$here && $t eq "password"} {
      incr i; set password [lindex $tokens $i]
    }
  }
  return [list $login $password]
}

# the message, after the name of the tool's script, on the standard error
proc fail {message} {
  puts stderr "[file rootname [file tail $::argv0]]: $message"
  exit 2
}

proc vax_login {host} {
  global spawn_id expect_out prompt
  lassign [netrc $host] login password
  if {$login eq "" || $password eq ""} { fail "no login and password for $host in ~/.netrc" }

  spawn -noecho telnet $host
  expect {
    -re {Username: ?$} {}
    timeout { fail "no Username: prompt from $host" }
    eof { fail "telnet to $host closed" }
  }
  send "$login\r"
  expect {
    -re {Password: ?$} {}
    timeout { fail "no Password: prompt from $host" }
  }
  send "$password\r"
  unset password
  # VAX_ASSEMBLE_LOG names a file for the session from here on, the password
  # already sent, for finding out why a prompt was not recognised
  if {[info exists ::env(VAX_ASSEMBLE_LOG)]} { log_file -a -noappend $::env(VAX_ASSEMBLE_LOG) }
  # The DCL prompt: "$ " at the start of a line
  set prompt {\n\$ $}
  set answered 0
  expect {
    -re $prompt {}
    -re "\033(Z|\\\[0?c)" {
      # the login's SET TERMINAL/INQUIRE asks what the terminal is: a VT100
      # with advanced video, answered once, or the login warns of an unknown
      # terminal type
      if {!$answered} { send "\033\[?1;2c"; set answered 1 }
      exp_continue
    }
    -re {User authorization failure} { fail "login to $host refused" }
    timeout { fail "no DCL prompt after logging in to $host" }
  }
  # From here on a prompt of our own, which no output can be mistaken for;
  # DCL's "$ " can follow a bare carriage return
  send "SET PROMPT=\"VAXASM> \"\r"
  set prompt {VAXASM> $}
  expect {
    -re $prompt {}
    timeout { fail "SET PROMPT was not answered" }
  }
}
