# '.' this file from tools/vax-assemble and tools/vax-run. Their runs share
# POC's home directory on the VAX development system, and the fixtures run
# several at once (test/run-tests.sh), so each run holds this host's lock
# while it uses the guest:
#
#   vax_lock      waits for the lock and takes it
#   vax_unlock    gives it up (in the run's EXIT trap)
#
# The lock is a directory in /tmp, not TMPDIR, so that every run on the
# host shares it, whatever its environment; it holds the owner's process
# ID, and a lock whose owner has gone is taken over.

vax_lock_dir=/tmp/poc-vax-$(id -u).lock
vax_locked=

vax_lock() {
  while ! mkdir "$vax_lock_dir" 2>/dev/null; do
    owner=$(cat "$vax_lock_dir/pid" 2>/dev/null || true)
    if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then
      rm -rf "$vax_lock_dir"
      continue
    fi
    sleep 1
  done
  echo $$ >"$vax_lock_dir/pid"
  vax_locked=1
}

vax_unlock() {
  if [ -n "$vax_locked" ]; then
    rm -rf "$vax_lock_dir"
    vax_locked=
  fi
}
