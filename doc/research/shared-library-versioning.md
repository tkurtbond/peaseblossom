# Shared Library Versioning on Linux, OpenBSD, NetBSD, and FreeBSD

Shared library versioning across **Linux**, **FreeBSD**, **OpenBSD**, and **NetBSD** relies on the **ELF (Executable and Linkable Format)** standard, but they diverge significantly in file naming conventions, versioning philosophy, and how the dynamic linker handles compatibility.

---

### 1. Linux (GNU/ELF)
Linux uses the GNU C Library (`glibc`) and the GNU dynamic linker (`ld.so`). It relies heavily on **SONAMEs** and **GNU Symbol Versioning** via linker scripts.

* **Naming Convention:** `libfoo.so.<major>.<minor>.<patch>` (e.g., `libssl.so.1.1.1`).
* **The SONAME Mechanism:** The actual file on disk has full version numbers, but the library embeds a **SONAME** (Shared Object Name), typically just the major version (e.g., `libssl.so.1.1`). When a binary links against the library, the linker records this SONAME as a dependency rather than the exact filename.
* **Symbol Versioning:** Linux goes a step further than BSDs by supporting *symbol-level* versioning. A single library file (`libfoo.so.1`) can export multiple versions of the *same* symbol (e.g., `foo@GLIBC_2.2.5` and `foo@GLIBC_2.4`), allowing fine-grained backwards compatibility without bumping the major SONAME for internal additions.

---

### 2. FreeBSD
FreeBSD uses an ELF toolchain similar to Linux, but its philosophy regarding system integration and package management shapes a cleaner file-naming approach.

* **Naming Convention:** `libfoo.so.<major>` (e.g., `libz.so.6`). 
* **Versioning Philosophy:** Unlike Linux, FreeBSD traditionally restricts the filename suffix to *just* the major version number. The minor and patch numbers are typically omitted from the actual shared library filename on disk because any breaking change to the ABI requires a major version bump anyway.
* **Control:** FreeBSD handles library bumps strictly within its Ports collection and base system. When a library major version changes, dependent ports must have their `PORTREVISION` bumped to trigger rebuilds.

---

### 3. OpenBSD
OpenBSD enforces strict and rigid rules regarding shared library versioning to maintain absolute security and stability across upgrades.

* **Naming Convention:** `libfoo.so.<major>.<minor>` (e.g., `libcrypto.so.45.0`).
* **The Major.Minor Meaning:** 
  * **Major number:** Bumped whenever there is a **backward-incompatible API/ABI break** (e.g., removing a function or changing a signature).
  * **Minor number:** Bumped whenever there is a **backward-compatible change** (e.g., adding a new function).
* **Runtime Rules:** OpenBSD’s dynamic linker (`ld.so`) requires a library with the *exact same major number* and an *equal or higher minor number* to satisfy dependencies. This design makes checking library compatibility deterministic and lightweight compared to Linux's symbol versioning scripts.

---

### 4. NetBSD
NetBSD uses a versioning scheme very similar to OpenBSD, rooted in its historical BSD design, and pairs it with the cross-platform `pkgsrc` package system.

* **Naming Convention:** `libfoo.so.<major>.<minor>` (e.g., `libcurses.so.8.2`).
* **Versioning Philosophy:** Like OpenBSD, the major version increments on breaking changes, and the minor version increments when new functions or backwards-compatible features are added.
* **Major-Minor Tracking:** NetBSD tracks these versions via internal system mechanisms (like shlib_version files in the source tree) ensuring that binaries compiled against older minor revisions continue to run seamlessly as long as the major version matches and the minor version is satisfied.

---

### Summary Comparison Table

| Feature / OS | Linux (GNU) | FreeBSD | OpenBSD | NetBSD |
| :--- | :--- | :--- | :--- | :--- |
| **Typical Filename** | `libfoo.so.X.Y.Z` | `libfoo.so.X` | `libfoo.so.X.Y` | `libfoo.so.X.Y` |
| **SONAME Used?** | Yes | Yes | Yes | Yes |
| **Symbol Versioning** | Yes (via linker scripts) | No | No | No |
| **Minor Version in Filename** | Yes | Usually omitted | Yes | Yes |