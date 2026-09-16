# tools/bootstrap

Stage 0/1/2 build scripts (see `PLAN.md`, "Bootstrap terminology"):

- **Stage 0**: `voc` compiles poc's own source into a working `poc`
  binary. Load-bearing until Stage 1 exists.
- **Stage 1**: the Stage-0-built `poc` compiles poc's own source again.
- **Stage 2**: Stage-1's `poc` compiles poc's own source a third time, to
  check Stage 1 vs. Stage 2 output for the self-hosting fixed point.

Nothing here yet — a `stage0` script will appear once there's real poc
source for `voc` to compile (starting Phase 1).
