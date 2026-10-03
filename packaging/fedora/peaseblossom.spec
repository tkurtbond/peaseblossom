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

# poc-rtl's -g copies keep their debugging information; poc itself has
# none to split off, and is stripped in %%install.
%global debug_package %{nil}
%global __brp_strip %{nil}
%global _preserve_static_debuginfo 1
# libpoc-rtl.so is for programs poc builds, which find it by their run-time
# path, not for the system's library search
%global __provides_exclude_from ^%{_prefix}/lib/poc/.*$

Name:           peaseblossom
Version:        0.1.0
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

%prep
%autosetup

%build
# poc runs clang itself with its own options (doc/llvm-toolchain.md), so
# the distribution's CFLAGS and LDFLAGS do not reach it
make installable

%install
make install DESTDIR=%{buildroot} PREFIX=%{_prefix} BINDIR=%{_bindir} \
  LIBDIR=%{_prefix}/lib MANDIR=%{_mandir} DOCDIR=%{_pkgdocdir}
%{__strip} %{buildroot}%{_bindir}/poc

%check
# what a user does with the installed poc: programs at both size models,
# -g, shared poc-rtl, a library of one's own, poc(1)
test/install/check.sh %{buildroot}%{_bindir}/poc %{_builddir}/check-install

%files
%license LICENSE
%{_bindir}/poc
%{_prefix}/lib/poc/
%{_mandir}/man1/poc.1*
%{_pkgdocdir}/

%changelog
* Sat Oct 03 2026 T. Kurt Bond <tkurtbond@gmail.com> - 0.1.0-1
- First package.
