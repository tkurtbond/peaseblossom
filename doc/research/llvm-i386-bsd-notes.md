# LLVM, i386/i686, and BSD Compiler Notes

## Does LLVM run on i386-class machines?

Short answer: not really, though it depends on what you mean by "run on."

**As a build/host target for the LLVM toolchain itself:** Practically no.

- Modern LLVM/Clang requires a C++17 (increasingly C++20-ish) toolchain and a fairly large amount of RAM and disk to even build itself, let alone run — many gigabytes for a full build, and non-trivial memory to compile moderately complex C++ files. Genuine 80386-class machines (1985-era, tens of megabytes of RAM at most) can't realistically host it.
- Most Linux distributions that still ship 32-bit x86 builds target **i686** as the minimum baseline (Pentium Pro/Pentium II era, mid-1990s), not the original i386. That's because glibc and GCC/LLVM runtime code rely on instructions like `CMPXCHG` for atomic operations that a true 80386 doesn't have (that arrived with the 486) or that aren't reliably available until i586/i686. So even "32-bit x86" software today generally won't run on a literal 386.
- LLVM itself dropped explicit support for pre-i686 32-bit hosts a long time ago in its build system requirements.

**As a code-generation target (cross-compiling):** Yes — LLVM's backend can still generate machine code for the i386 instruction set (`-target i386` or GCC/Clang's `-march=i386`), the same way it can target other legacy architectures. So you can use a modern 64-bit machine running LLVM/Clang to *produce* binaries meant to run on old 32-bit x86 chips (down to true 386, if you disable newer instruction requirements), even though LLVM can't practically run *on* such a machine itself.

**Conclusion:** LLVM can target i386, but it doesn't run natively on i386-class hardware as a host system.

---

## Are Pentium II's i686?

Yes — the Pentium II is an i686-class chip. The i686 designation covers Intel's P6 microarchitecture family: Pentium Pro (the first P6 chip), Pentium II, Pentium III, and later Pentium M/Core-based chips that kept the same baseline instruction set additions.

What actually makes something "i686" rather than "i586" (plain Pentium) or "i486" comes down to a handful of instruction-set and architectural features introduced with the P6 core:

- **CMOV** (conditional move instructions) — usually the single most-cited dividing line, since a lot of software's "i686 minimum" requirement boils down to needing `CMOV`.
- A more capable **out-of-order, superscalar execution** design (not an ISA feature per se, but part of what "P6-class" means architecturally).
- Reliable support for things like `CMPXCHG8B` (technically introduced earlier, on some late 486/early Pentium chips, but consistently present from here on).
- The Pentium II specifically added **MMX** on top of the P6 core (which the original Pentium Pro lacked), plus a larger L2 cache setup — but MMX isn't what defines "i686"; the P6 core/CMOV lineage is.

So a Pentium II is well above the minimum bar that "i686" Linux distributions (and correspondingly, distributions expecting a CMOV-capable, modern-enough atomic-ops-capable CPU) target — meaning it's far more plausible as a host for a modern LLVM/Clang build than a true 80386 or even early 80486 would be, though practical limits from RAM, disk space, and 32-bit-only address space would become the bottleneck long before instruction-set compatibility.

---

## Does OpenBSD provide an i686 build?

Yes, but it's important to be precise about naming: OpenBSD calls the port **"i386"**, but it isn't targeting the original 80386 chip — the actual minimum requirement is Pentium-class or later. OpenBSD/i386 works across a broad range of standard PCs and clones, with a wide variety of processors and I/O bus architectures, and "all CPUs compatible with the Intel Pentium or later, with Intel-compatible hardware floating point support should work."

So functionally, OpenBSD's "i386" port is really an i586-and-up port — which comfortably includes i686-class chips like a Pentium II. There's no separate "i686" build; i686 hardware just runs the same i386-named port, since it exceeds the minimum requirement.

Relevant caveats:

- Due to the increased usage of OpenBSD/amd64, as well as the age and practicality of most i386 hardware, only easy and critical security fixes are backported to i386 — so it's a maintained but de-prioritized architecture.
- Minimum install: 32MB of RAM and at least 250MB of disk space (base set); at least 600MB for the entire system; more RAM recommended to run X or compile the system. A Pentium II box (typically 32–256MB RAM by the late '90s) sits right at or above that bar.
- Building LLVM/Clang *on* that hardware would still be rough in practice — cross-compiling from a faster machine and deploying the resulting i386-target binary would be far more practical.

---

## OpenBSD i386 supplies Clang as the system C compiler

Correct. Clang became the default base-system compiler on i386 (and amd64) in July 2017, replacing the ancient GCC 4.2.1 that OpenBSD had been stuck on since 2010 due to GCC's switch to GPLv3. GCC 4 was kept around initially, but Clang took over as the default for both architectures at that point.

This ties back to the i686 discussion: the base-system Clang on i386 registers `x86 - 32-bit X86: Pentium-Pro and above` as its target — confirming the "i386" port floor is really Pentium Pro-class (i686), not a literal 80386.

One nuance: the base-system Clang only builds LLVM's X86 backend (plus AMDGPU where needed) — it's not the full multi-target LLVM you'd get from the ports tree's standalone `clang-13`-style packages, which register many more backends (AArch64, etc.). So "Clang is the system C compiler" is accurate, but it's a leaner build than the general-purpose LLVM toolchain most people think of.

---

## Is there a 32-bit build of Clang for NetBSD 32-bit (i386)?

Yes, but with a different story than OpenBSD's: NetBSD never switched its *default* base compiler to Clang, the way OpenBSD and FreeBSD did. NetBSD "picked a different path and remained with GCC and binutils regardless of the license change to GPLv3" — as of NetBSD 9.1, all supported platforms have recent versions of GCC (7.5.0) and binutils in the base system, and NetBSD is more or less tied to GCC since it supports more architectures than the other BSDs, some of which will likely never be supported in LLVM.

That said, Clang **is** available and buildable for i386, just opt-in rather than default:

- Since NetBSD 6, the base system has included Clang, and it works on ARM, PowerPC, x86, and possibly SPARC64, though it isn't built by default.
- To enable it, set `MKGCC=no`, `MKLLVM=yes`, `HAVE_LLVM=yes`, `PKGSRC_COMPILER=clang`, `CLANGBASE=/usr` in `mk.conf` and rebuild — applies to both the base system and pkgsrc packages.
- Daily images are built from NetBSD-current for selected platforms (including i386) with the MKLLVM and HAVE_LLVM build options enabled, and contain LLVM and Clang — so pre-built i386 Clang-enabled snapshots do exist, just not as the release default.

There's also pkgsrc's standalone `clang` package for adding the compiler without replacing the base `cc`.

**Bottom line:** no separate "official 32-bit Clang release" the way you might expect from a project like Rust, but a fully functional 32-bit (i386) Clang build path exists in NetBSD's own build system, and prebuilt snapshot images with it enabled are already produced. Known caveat: early testing found a libm issue where `expf(3)` gave wrong results on i386 — worth checking current status if libm precision matters.

---

### Sources referenced
- https://www.openbsd.org/i386.html
- https://www.phoronix.com/news/OpenBSD-Default-Clang
- https://www.cambus.net/the-state-of-toolchains-in-openbsd/
- https://www.cambus.net/differences-between-base-and-openbsd-llvm-in-openbsd/
- https://wiki.netbsd.org/tutorials/clang/
- https://www.cambus.net/the-state-of-toolchains-in-netbsd/
- https://sonnenberger.org/2012/01/19/status-netbsd-and-llvm/
