# rpmbuild --with xcat
%if %{?_with_xcat:1} %{!?_with_xcat:0}
%define with_xcat	1
%define _xcatroot	/opt/xcat
%else
%define with_xcat	0
%endif

# rpmbuild --with xcatroot=<prefix>
%if %{?_with_xcatroot:1} %{!?_with_xcatroot:0}
%define with_xcat	1
%define	_xcatroot	%(%{__perl} -e '$_ = "%{_with_xcatroot}"; if (s/^.*--with-xcatroot=(\\S+)$/$1/) { print;}')
%endif

Summary: Execute a command on a set of hosts
Name: pexec
Version: 1.4
Release: 13%{?dist}
Group: Applications/System
Source: %{name}-%{version}.tgz
Patch0: pexec-xcat.patch
BuildRoot: %{_tmppath}/%{name}-%{version}-root
License: Modified BSD
Requires: perl
BuildArch: noarch
Packager: dwg@lanl.gov
Conflicts: xcat-pexec xCAT-pexec pexec-bproc pexec-warewulf
Obsoletes: pexec-slurm
Prefix: %{_bindir}
Prefix: %{_mandir}

%description
pexec builds a machine list from command-line arguments on which cmd is
to be run.  If the string %host% is part of cmd, names from the machine
list are substituted in its stead.  Output of cmd on each machine is
printed to the execution host's STDOUT.

%if %{with_xcat}
%package -n xCAT-pexec
Summary: Execute a command on a set of hosts
Group: Applications/System
Requires: %{_xcatroot}/bin/nodels
Provides: pexec-xCAT = %{version}-%{release}
Conflicts: pexec >= 1.3 pexec-bproc pexec-slurm pexec-warewulf
Obsoletes: pexec < 1.3 xcat-pexec

%description -n xCAT-pexec
pexec builds a machine list from command-line arguments on which cmd is
to be run.  If the string %host% is part of cmd, names from the machine
list are substituted in its stead.  Output of cmd on each machine is
printed to the execution host's STDOUT.
%endif

%prep

%setup -q

%if %{with_xcat}
%{__perl} -pi -e "s,'/opt/xcat','%{_xcatroot}',g" %PATCH0
%patch0 -p0 -b .patch0
%endif

%install
umask 022
%{__rm} -rf $RPM_BUILD_ROOT

%if %{with_xcat}

%{__mkdir_p} $RPM_BUILD_ROOT%{_xcatroot}/bin
%{__install} -m 0755 %{name}.pl $RPM_BUILD_ROOT%{_xcatroot}/bin/%{name}

%{__mkdir_p} $RPM_BUILD_ROOT%{_xcatroot}/man/man1
pod2man %{name}.pl $RPM_BUILD_ROOT%{_xcatroot}/man/man1/pexec.1

%else

%{__mkdir_p} $RPM_BUILD_ROOT%{_bindir}
%{__install} -m 0755 %{name}.pl $RPM_BUILD_ROOT%{_bindir}/%{name}

%{__mkdir_p} $RPM_BUILD_ROOT%{_mandir}/man1
pod2man %{name}.pl $RPM_BUILD_ROOT%{_mandir}/man1/%{name}.1

%endif

%clean
%{__rm} -rf $RPM_BUILD_ROOT


%if %{with_xcat}

%files -n xCAT-pexec
%defattr(-,root,root,0755)
%doc COPYING
%attr(0755,root,root) %{_xcatroot}/bin/%{name}
%attr(0644,root,root) %{_xcatroot}/man/man1/%{name}.1

%else

%files
%defattr(-,root,root,0755)
%doc COPYING
%attr(0755,root,root) %{_bindir}/%{name}
%attr(0644,root,root) %{_mandir}/man1/%{name}.1.gz
%endif


%changelog
* Tue Feb 11 2014 Daryl W. Grunau <dwg@lanl.gov> 1.4-13
- Exit EINTR if interrupted; ETIMEDOUT if timed out.
- BUGFIX: verbose output missing on tree-root processes.
- ParseRange() function to better handle host ranges.

* Fri Jan 10 2014 Daryl W. Grunau <dwg@lanl.gov> 1.4-12
- BUGFIX: host range needs to support multiple NRs, comma-separated when
  handling p[NR]s cases, for prefix 'p', node range 'NR' and suffix 's'.

* Fri Jan 10 2014 Daryl W. Grunau <dwg@lanl.gov> 1.4-11
- BUGFIX: host range suffix is not permitted to contain yet another range when
  handling p[NR]s cases, for prefix 'p', node range 'NR' and suffix 's'.

* Thu Jan 09 2014 Daryl W. Grunau <dwg@lanl.gov> 1.4-10
- 'local' becomes 'our' where appropriate (and lose perl 5.003 compatibility).
- Documentation fixes.

* Thu Jan 09 2014 Daryl W. Grunau <dwg@lanl.gov> 1.4-9
- BUGFIX: handle cases where -m (or -s) was specified with no argument(s).
- BUGFIX: host range suffix should match greedily when handling p[NR]s
  cases, for prefix 'p', node range 'NR' and suffix 's'.
- Merge subroutines spawn and tspawn.
- Native slurm support; obsolete pexec-slurm.  Document this.

* Mon Mar 26 2012 Daryl W. Grunau <dwg@lanl.gov> 1.4-8
- Move 'unique array element' guarantee into IntersectNetgroups() from
  CacheNetgroups().
- Use Slurm.pm ':constant' macros to identify node states, rather than matching
  strings when built --with slurm.  Add -m allrespond=allup, allnorespond=allnotup,
  alldrained in this case too; document these.

* Wed Sep 14 2011 Daryl W. Grunau <dwg@lanl.gov> 1.4-7
- Squash a GetMachines() bug introduced in 1.4-6.

* Fri Sep 09 2011 Daryl W. Grunau <dwg@lanl.gov> 1.4-6
- DNS verify hosts after fork, if requested.
- Support the intersection of netgroups a@b on the machine list; document this.
- Fix up the node_state matching for 'allup' and 'alldown' --with slurm.

* Tue Aug 09 2011 Daryl W. Grunau <dwg@lanl.gov> 1.4-5
- Modified BSD license.

* Wed Jun 08 2011 Daryl W. Grunau <dwg@lanl.gov> 1.4-4
- Slurm patches fixes for v2.3 api.

* Fri Apr 02 2010 Daryl W. Grunau <dwg@lanl.gov> 1.4-3
- Switch to Modified BSD license.

* Tue Mar 30 2010 Daryl W. Grunau <dwg@lanl.gov> 1.4-2
- Translate p[1-10,13]s to p1s-p10s,p13s for prefix 'p' and suffix 's' when
  processing the machine list for -m.
- Permit 'PrefixDigit(s)Suffix' for node ranges (previously only
 'PrefixDigit(s)' was supported).
- Document these machine list changes.

* Tue Mar 09 2010 Daryl W. Grunau <dwg@lanl.gov> 1.4-1
- LA-CC.  LANS contract number.

* Fri Oct 30 2009 Daryl W. Grunau <dwg@lanl.gov> 1.3-8
- Require perl(Slurm) instead of slurm-tools --with slurm.

* Thu Oct 08 2009 Daryl W. Grunau <dwg@lanl.gov> 1.3-7
- Change default ping-timeout to 5s from 3s.
- Revert 'our' to 'local' everywhere for perl 5.003 compatibility.
- Remote copy commands are mutually exclusive with remote shell commands.
- Don't strip host/server names if they appear to be IP addresses in '-p' output.
- Support ^/path/to/file syntax (a la xCAT) natively for -m and -s options.
- Define --with target=panfs; brute-force a BSD pkg built by root only.

* Sun Dec 21 2008 Daryl W. Grunau <dwg@lanl.gov> 1.3-6
- Define --with target = slurm.

* Thu Nov 13 2008 Daryl W. Grunau <dwg@lanl.gov> 1.3-5
- Fix POD error: "Around line 1155: You forgot a '=back' before '=head1'"
- Specifying --debug should not check file src file readability on
  remote copy commands.

* Fri Oct 24 2008 Daryl W. Grunau <dwg@lanl.gov> 1.3-4
- xcat patch: v1.3 'nr' is an alias to nodels; make this change so xcat2
  will work.  Fix "Useless localization of scalar assignment at pexec.pl line 74"
  by switching to 'our'.  xcat -> xCAT & obsolete xcat-pexec.

* Tue Sep 02 2008 Daryl W. Grunau <dwg@lanl.gov> 1.3-3
- Reqire warewulf-tools instead of hardcoded path.

* Tue May 06 2008 Daryl W. Grunau <dwg@lanl.gov> 1.3-2
- Splitting out bproc, warewulf & xcat took too much out w.r.t. $ping_host.
  Replaced with default $ping_host='%host%'.

* Tue Apr 08 2008 Daryl W. Grunau <dwg@lanl.gov> 1.3-1
- Define --with targets = bproc, warewulf & xcat.  Only build RPMS
  based upon these; specifying nothing gets you a pexec w/o this
  addn'l functionality.  Specifying --with xcatroot=<path> influences
  the install directory for the xcat build (and implies --with xcat).

* Thu Jun 28 2007 Daryl W. Grunau <dwg@lanl.gov> 1.2-1
- Bugfix: rcpy commands did not take into account that src file could
  contain no '/'!
- Bugfix: rcpy commands must specify absolute path for dst.
- Cleanup lockfiles better by catching SIGINT & SIGTERM, passing to process
  group and exiting gracefully (deleting the lockfile).
- On Ctrl-Z, if more than PMAX procs are waiting to run just show the
  number, not every last entry.
- On Ctrl-Z, SIGCONT my process group in case I've got subprocs (e.g. a
  pipe chain) that really do honor SIGTSTP.
- New switch: --output, enabling output to a file (or multiple files)
- New switches: --ping, --ping-host, --ping-timeout to predicate cmd exec
  on successful ping.
- Doc/example changes to reflect new switches.
- Create two packages for xcat & non-xcat versions.  Maintain diffs with a
  patch.

* Tue Dec 12 2006 Daryl W. Grunau <dwg@lanl.gov> 1.1-1
- Recognize host ranges that were previously not permitted, e.g. a valid
  range contains an even number of "things" when split by '-'.  This
  permits cluster names that contain dashes to be valid in range
  specifications.
- Permit a range to count downwards as well as upwards.

* Tue Sep 19 2006 Daryl W. Grunau <dwg@lanl.gov> 1.0-1
- Tree-spawn remote copying algorithm (and deprecate -M).
- New options: --bpcp, --rcp, --rsync, --scp, --fan-out, --exit-success.
- Deprecate -r; use --rsh.  Deprecate -b; use --bpsh.
- Exit with logical OR of all exit statuses.
- Include bpcp.patch in the doc directory.

* Tue Jul 25 2006 Daryl W. Grunau <dwg@lanl.gov> 0.3-1PLSD
- Add --random option to randomize host list.

* Mon Jul 18 2005 Daryl W. Grunau <dwg@lanl.gov> 0.2-1PLSD
- select during ReapChildren in wrong location, preventing the reaping
  of children in a timely fashion.

* Fri Jun 24 2005 Daryl W. Grunau <dwg@lanl.gov> 0.1-1PLSD
- First cut.
