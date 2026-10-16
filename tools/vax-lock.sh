# '.' this file from tools/vax-assemble, tools/vax-do and tools/vax-run,
# after setting host. The guest has more than one account for poc's runs
# (the user, 2026-10-16: POC and POC2), each a line "machine <host> login
# <name> password ..." of $VAX_NETRC, and a run there uses its account's
# home directory throughout; the fixtures run several at once
# (test/run-tests.sh), so each run holds a lock of this host's for its
# account while it uses the guest:
#
#   vax_lock      waits for the lock of an account and takes it, and
#                 exports VAX_USER, that account's login, for the expect
#                 script (tools/vax-login.tcl)
#   vax_unlock    gives it up (in the run's EXIT trap)
#
# With VAX_USER set, a run uses that account alone (tools/bootstrap/
# vax-stages, which installs POC.EXE in the account's [.BIN], sets it to
# poc); otherwise it takes the first of $VAX_NETRC's accounts for the host
# whose lock is free. Each lock is a directory in /tmp, not TMPDIR, so that
# every run on the host shares it, whatever its environment; it holds the
# owner's process ID, and a lock whose owner has gone is taken over. The
# guest's two accounts share UIC group 128, and with it process names,
# lock resources and group logical names; each fixture uses names of its
# own, so only the same fixture run twice at once could collide.

vax_lock_dir=
vax_locked=

# the accounts' logins for host, in $VAX_NETRC's order (its passwords are
# not printed); VAX_USER alone, if it is set
vax_accounts() {
  if [ -n "${VAX_USER:-}" ]; then
    echo "$VAX_USER"
    return
  fi
  [ -r "$VAX_NETRC" ] || return 0
  awk -v host="$host" '
    { for (i = 1; i <= NF; i++) {
        if ($i == "machine") { here = ($(i + 1) == host); i++ }
        else if ($i == "default") here = 0
        else if ($i == "login") { if (here) print $(i + 1); i++ }
        else if ($i == "password" || $i == "account" || $i == "macdef") i++
      } }' "$VAX_NETRC"
}

vax_lock() {
  vax_lock_accounts=$(vax_accounts | tr 'A-Z' 'a-z' | awk '!seen[$0]++')
  # with no account, the expect script reports that there is none
  [ -n "$vax_lock_accounts" ] || vax_lock_accounts=none
  while :; do
    for vax_account in $vax_lock_accounts; do
      vax_lock_dir=/tmp/poc-vax-$(id -u)-$vax_account.lock
      if mkdir "$vax_lock_dir" 2>/dev/null; then
        echo $$ >"$vax_lock_dir/pid"
        vax_locked=1
        VAX_USER=$vax_account
        export VAX_USER
        return
      fi
      owner=$(cat "$vax_lock_dir/pid" 2>/dev/null || true)
      if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then
        rm -rf "$vax_lock_dir"
      fi
    done
    sleep 1
  done
}

vax_unlock() {
  if [ -n "$vax_locked" ]; then
    rm -rf "$vax_lock_dir"
    vax_locked=
  fi
}
