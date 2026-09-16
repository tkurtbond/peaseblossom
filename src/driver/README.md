# src/driver

`Poc.Mod`: the compiler's main program and CLI parsing
(`poc options {files {options}}`, voc-style flag semantics). Phase 1
added a minimal `-dump-tokens <file>` mode with ad hoc argument handling;
proper flag parsing moves into `src/front/CompilerOptions.Mod` as more
flags accumulate in later phases. Unlike voc, poc must support an
output-directory flag so build artifacts don't default to the cwd (see
`PLAN.md`, "Directory layout").
