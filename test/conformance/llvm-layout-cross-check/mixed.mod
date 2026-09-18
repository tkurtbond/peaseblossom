MODULE mixedRecord;
  (* PLAN.md Phase 8 step 4's own "Decided" note: LLVMTypes.Mod doesn't
     compute byte offsets itself - it emits a literal LLVM array/struct
     type and trusts LLVM's own target-datalayout-driven layout algorithm
     to compute real field offsets, the same algorithm MemoryLayout.Mod's
     Size/Align/FieldOffset already model by hand (natural alignment,
     capped at word size). This fixture is the empirical check that those
     two independently-arrived-at algorithms actually agree, rather than
     an assumption - unlike layout-size-model (which only golden-diffs
     MemoryLayout.Mod against its own prior output), this fixture's
     `expected` values were cross-validated once against clang's own
     real, ABI-verified struct layout via
     `clang -Xclang -fdump-record-layouts -ffreestanding -target
     <triple> -c`, for a C struct with the OC-size-model-equivalent
     fixed-width field types (int8_t/int16_t/int64_t, matching CHAR /
     SHORTINT-under-OC / HUGEINT-and-LONGINT-under-OC here) at both
     i686-unknown-linux-gnu and x86_64-unknown-linux-gnu - see PLAN.md's
     step 4 retrospective for the exact clang invocation and output. This
     fixture itself does not shell out to clang at test time (like
     layout-node-tree/layout-size-model, and unlike llvm-emit-ir/
     llvm-build-run, it has no real toolchain dependency) - the
     algorithm being checked is static, deterministic compiler code, not
     something that can drift per test run, so one-time empirical
     validation is enough; only poc's own -dump-layout runs here.

     Field order/types deliberately mix a 1-byte, two 8-byte, and one
     OC-widened 2-byte field to produce non-trivial padding under the
     OC model (the O2 model doesn't correspond to any fixed-width C
     type set as directly, so this fixture cross-checks the OC columns
     only - see the sizeOC_32/64, alignOC_32/64, offsetOC_32/64 fields
     of poc's own -dump-layout output below). *)

  TYPE
    Mixed = RECORD
      a: CHAR;
      b: HUGEINT;
      c: SHORTINT;
      d: LONGINT
    END;
BEGIN
END mixedRecord.
