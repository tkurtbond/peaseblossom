# src/driver

`Poc.Mod`: the compiler's main program and CLI parsing
(`poc options {files {options}}`, voc-style flag semantics). Phase 1
added a minimal `-dump-tokens <file>` mode with ad hoc argument handling;
proper flag parsing moves into `src/front/CompilerOptions.Mod` as more
flags accumulate in later phases. Unlike voc, poc must support an
output-directory flag so build artifacts don't default to the cwd (see
`PLAN.md`, "Directory layout").

`Libraries.Mod`: libraries, their manifests and the library path (Phase 12
step 2c). `Version.Mod`: poc's version number, the one place it is kept
(Phase 13 step 1); `poc -version` prints it with the commit from
`BuildInfo.Mod`, which `tools/build-info` generates into `build/gen` and is
not in the source tree.
