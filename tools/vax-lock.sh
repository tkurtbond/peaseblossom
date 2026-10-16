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
# whose lock is free.
#
# Where flock(1) is (Linux, as on atla, the host that reaches the guest),
# a lock is flock's on a file, /tmp/poc-vax-<uid>-<account>.flock, held by
# an open file descriptor (9), so the kernel frees it when the run ends,
# however it ends; the run's children, expect among them, hold it too
# while they live. Elsewhere a lock is a directory,
# /tmp/poc-vax-<uid>-<account>.lock, made by mkdir and holding the
# owner's process ID. That one is never taken over: a run that finds one
# whose owner has gone stops, naming it, for it to be removed by hand.
# Taking over a lock whose owner had gone raced (2026-10-16): a waiter
# that read the old owner's ID could remove the lock a new owner had just
# made, and two runs then shared an account's directory. Either is in
# /tmp, not TMPDIR, so that every run on the host shares the locks,
# whatever its environment.
#
# The guest's two accounts share UIC group 128, and with it process
# names, lock resources and group logical names; each fixture uses names
# of its own, so only the same fixture run twice at once could collide.

vax_lock_path=
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
  if command -v flock >/dev/null 2>&1; then vax_lock_flock=1; else vax_lock_flock=; fi
  while :; do
    for vax_account in $vax_lock_accounts; do
      if [ -n "$vax_lock_flock" ]; then
        vax_lock_path=/tmp/poc-vax-$(id -u)-$vax_account.flock
        exec 9>>"$vax_lock_path"
        if flock -n 9; then
          vax_locked=1
          VAX_USER=$vax_account
          export VAX_USER
          return
        fi
        exec 9>&-
        continue
      fi
      vax_lock_path=/tmp/poc-vax-$(id -u)-$vax_account.lock
      if mkdir "$vax_lock_path" 2>/dev/null; then
        echo $$ >"$vax_lock_path/pid"
        vax_locked=1
        VAX_USER=$vax_account
        export VAX_USER
        return
      fi
      owner=$(cat "$vax_lock_path/pid" 2>/dev/null || true)
      if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then
        sleep 2
        # still the same owner, gone: left by a run that was killed
        if [ "$(cat "$vax_lock_path/pid" 2>/dev/null || true)" = "$owner" ]; then
          echo "vax-lock: $vax_lock_path was left by process $owner, which has ended: remove it by hand" >&2
          exit 2
        fi
      fi
    done
    sleep 1
  done
}

vax_unlock() {
  if [ -n "$vax_locked" ]; then
    if [ -n "$vax_lock_flock" ]; then
      exec 9>&-
    else
      rm -rf "$vax_lock_path"
    fi
    vax_locked=
  fi
}
