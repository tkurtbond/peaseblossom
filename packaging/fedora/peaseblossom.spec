# Fedora RPM for poc, the Peaseblossom Oberon-2 compiler (PLAN.md, Phase 13
# step 8). Built from the release tarball (make dist), which carries poc's
# own LLVM IR as seed/, so clang alone builds poc: voc is not needed.
#
#   make dist
#   rpmbuild -ba --define "_sourcedir $PWD/build/dist" packaging/fedora/peaseblossom.spec
#
# The runtime library, poc-rtl, is installed where poc looks for it,
# beside its own directory: %%{_prefix}/lib/poc/<triple>/<O2|OC>[-g]/, as
# gcc keeps its target files under %%{_prefix}/lib/gcc (not %%{_libdir}).
#
# The subpackage peaseblossom-vax has what poc -target vax-dec-vms needs
# besides (make install-vax): the libraries POCRTL, VMSDEF and VMSLIB in
# %%{_prefix}/lib/poc/vax-dec-vms/, the kits of poc for VAX/VMS, and the
# VAX/VMS Guide. It is all text, so noarch, and needs poc of its own
# version, which refuses a library another version wrote.

# poc-rtl's -g copies keep their debugging information; poc itself has
# none to split off, and is stripped in %%install.
%global debug_package %{nil}
%global __brp_strip %{nil}
%global _preserve_static_debuginfo 1
# libpoc-rtl.so is for programs poc builds, which find it by their run-time
# path, not for the system's library search
%global __provides_exclude_from ^%{_prefix}/lib/poc/.*$

Name:           peaseblossom
Version:        0.9.0
Release:        1%{?dist}
Summary:        Oberon-2 compiler (poc) using LLVM

License:        BSD-3-Clause
URL:            https://github.com/tkurtbond/peaseblossom
Source0:        %{url}/releases/download/v%{version}/%{name}-%{version}.tar.gz

# the seed has been checked on x86_64 only (seed/64 is for every 64-bit
# target, but poc has not been run on aarch64 Linux)
ExclusiveArch:  x86_64

BuildRequires:  clang
BuildRequires:  make
BuildRequires:  gawk
BuildRequires:  diffutils
# check.sh renders poc(1)
BuildRequires:  man-db
BuildRequires:  util-linux
# poc compiles and links every program with clang
Requires:       clang

%description
poc, the Peaseblossom Oberon Compiler, compiles Oberon-2 (the report by
H. Moessenboeck and N. Wirth) through LLVM: each module to LLVM IR, which
clang compiles and links. It comes with its runtime library, poc-rtl
(Oakwood's and Vishap Oberon's library modules), for both of its size
models, -O2 and -OC, and the User's Guide and Reference Guide.

%package        vax
Summary:        VAX/VMS target for poc: runtime libraries, VMS kits and guide
BuildArch:      noarch
Requires:       %{name} = %{version}-%{release}

%description    vax
What poc -target vax-dec-vms needs besides poc itself, which has the VAX
back end built in: the VAX runtime library POCRTL and the libraries of
VMS's own interfaces, VMSDEF (generated from STARLET) and VMSLIB, under
both size models, so that poc finds them as it finds poc-rtl; the two
kits that install poc on a VAX/VMS 5.5-2 system, which a program built
against these libraries needs there; and the Peaseblossom VAX/VMS Guide.

%prep
%autosetup

%build
# poc runs clang itself with its own options (doc/developer/llvm-toolchain.md), so
# the distribution's CFLAGS and LDFLAGS do not reach it. The tarball has
# the VAX kits and the VAX/VMS Guide as text already: installable-vax
# builds only the libraries.
make installable installable-vax

%install
make install DESTDIR=%{buildroot} PREFIX=%{_prefix} BINDIR=%{_bindir} \
  LIBDIR=%{_prefix}/lib MANDIR=%{_mandir} DOCDIR=%{_pkgdocdir}
# LICENSE goes in %%{_licensedir} (%%license below), not with the docs too
rm %{buildroot}%{_pkgdocdir}/LICENSE
%{__strip} %{buildroot}%{_bindir}/poc
make install-vax DESTDIR=%{buildroot} PREFIX=%{_prefix} BINDIR=%{_bindir} \
  LIBDIR=%{_prefix}/lib DATADIR=%{_datadir} \
  VAXKITDIR=%{_datadir}/%{name}/vax VAXDOCDIR=%{_docdir}/%{name}-vax

%check
# what a user does with the installed poc: programs at both size models,
# -g, shared poc-rtl, a library of one's own, poc(1)
test/install/check.sh %{buildroot}%{_bindir}/poc %{_builddir}/check-install
# programs for the VAX built with it and the VAX libraries alone
test/install/check-vax.sh %{buildroot}%{_bindir}/poc %{_builddir}/check-install-vax \
  tools/bootstrap/vax-kit/check %{buildroot}%{_datadir}/%{name}/vax %{buildroot}%{_docdir}/%{name}-vax

%files
%license LICENSE
%{_bindir}/poc
%{_prefix}/lib/poc/
%exclude %{_prefix}/lib/poc/vax-dec-vms/
%{_mandir}/man1/poc.1*
%{_pkgdocdir}/

%files vax
%license LICENSE
%{_prefix}/lib/poc/vax-dec-vms/
%{_datadir}/%{name}/
%{_docdir}/%{name}-vax/

%changelog
* Sat Oct 24 2026 T. Kurt Bond <tkurtbond@gmail.com> - 0.9.0-1
- Update to 0.9.0: poc needs far less memory, most of all for VAX/VMS:
  identifiers and literals are held once and sized to fit, the VAX back
  end encodes each procedure and checks each module as it writes it,
  and the VAX runtime's collector grows its heap to 1.5 times the live
  data; poc compiling itself on VAX/VMS peaks at 15.5 MB of virtual
  memory instead of 103.7 MB and takes about half the CPU time.

* Wed Oct 21 2026 T. Kurt Bond <tkurtbond@gmail.com> - 0.8.0-1
- Update to 0.8.0: for VAX/VMS, poc writes each module's object file
  itself (-vax-objects, -emit-vax-object), with traceback records and,
  with -g, records for the VMS debugger; poc on VMS builds from objects
  and needs MACRO only for the runtime's PocRtl.mar, and poc on Unix
  builds from MACRO-32 unless given -vax-objects (-vax-macro32 keeps
  the old way); -emit-macro32, -emit-vax-object and -emit-vax-image may
  be given together; and poc's own source type-checks under -O2 again
  (make check-o2).

* Sat Oct 17 2026 T. Kurt Bond <tkurtbond@gmail.com> - 0.7.0-1
- Update to 0.7.0: a back end for VAX/VMS 5.5-2 (poc -target
  vax-dec-vms), which writes MACRO-32 and a DCL procedure that assembles
  and links it, with the runtime library POCRTL and VMS's interfaces,
  VMSDEF (generated from STARLET) and VMSLIB, as object libraries and
  shareable images, ["VMS"] external procedures, and two kits that
  install poc itself on VAX/VMS; the new subpackage peaseblossom-vax,
  which installs those libraries, the kits and the VAX/VMS Guide (make
  install-vax); options after the file name are applied;
  SYSTEM.VAL(SYSTEM.ADDRESS, E) is an external procedure's address; the
  runtime module Directories; and a note when a missing module is the
  VAX runtime's, not installed.

* Wed Oct 14 2026 T. Kurt Bond <tkurtbond@gmail.com> - 0.6.0-1
- Update to 0.6.0: the unsigned integer types SYSTEM.CARD8, CARD16,
  CARD32, CARD64 and SYSTEM.CARD, with Card and CardHex in Out, Err and
  OutStr and Card in In and InStr; every FOR loop ends before a step
  past its final value, so a loop up to MAX of its type ends; make
  doc-all; and three fixes (REAL constant expressions folded in double
  precision, traps after an index or in an argument designator reported
  at the wrong place, and -strict applied to an imported module's
  procedure locals).

* Fri Oct 09 2026 T. Kurt Bond <tkurtbond@gmail.com> - 0.5.0-1
- Update to 0.5.0: SYSTEM.ADDRESS and an integer type of its width
  are assignable to each other; a build reuses an object that is up to
  date, judged by content; -lto on 32-bit x86 NetBSD when poc runs
  there; a missing import's notes name a library that has the module
  for another target; wider HTML documents; and two fixes (a module
  compiled alone had no root table for the collector, and
  -trap-location put a failed WITH of several guards at its last
  guard). Packages for OpenBSD amd64, NetBSD i386 and FreeBSD arm64 as
  well.

* Tue Oct 06 2026 T. Kurt Bond <tkurtbond@gmail.com> - 0.4.1-1
- Update to 0.4.1: a fix (ORD of a SET did not compile under -OC).

* Tue Oct 06 2026 T. Kurt Bond <tkurtbond@gmail.com> - 0.4.0-1
- Update to 0.4.0: a library records its -link arguments for the
  programs that link it; a module's part may be C++ (<Module>.cpp,
  linked by clang++); -help lists every command and option; the guides
  and poc(1) as HTML and PDF; and two fixes (a mistyped option was lost
  in the usage text, an ELSIF's position in the debug information).

* Mon Oct 05 2026 T. Kurt Bond <tkurtbond@gmail.com> - 0.3.1-1
- Update to 0.3.1: a fix (poc -install-library over a copy an older poc
  wrote said "rebuild it", and could leave old modules' files behind).

* Mon Oct 05 2026 T. Kurt Bond <tkurtbond@gmail.com> - 0.3.0-1
- Update to 0.3.0: read-only parameters (x-), which take constants and
  any expression; the runtime modules OutStr and InStr, Out and In on
  strings; and a fix (an imported read-only variable was accepted as a
  VAR argument).

* Sun Oct 04 2026 T. Kurt Bond <tkurtbond@gmail.com> - 0.2.0-1
- Update to 0.2.0: record and array literals, structured constants, and
  four fixes (exported external procedures, -check's word size, -strict
  on compiled imports, string literals of any length).

* Sat Oct 03 2026 T. Kurt Bond <tkurtbond@gmail.com> - 0.1.0-1
- First package.
