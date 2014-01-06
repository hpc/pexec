#!/usr/bin/perl -w
# Copyright (C) 2011 Daryl W. Grunau
#
# Unless otherwise indicated, this information has been authored by an employee
# or employees of the Los Alamos National Security, LLC (LANS), operator of the
# Los Alamos National Laboratory under Contract No.  DE-AC52-06NA25396 with the
# U.S. Department of Energy.  The U.S. Government has rights to use, reproduce,
# and distribute this information. The public may copy and use this information
# without charge, provided that this Notice and any statement of authorship are
# reproduced on all copies. Neither the Government nor LANS makes any warranty,
# express or implied, or assumes any liability or responsibility for the use of
# this information.
#
# This program has been approved for release from LANS by LA-CC Number 10-066,
# being part of the HPC Operational Suite.

$| = 1;
($prog = $0) =~ s!.*/!!;

$PMAX = 32;

use Fcntl qw(:DEFAULT :flock);

use Pod::Usage;
use Getopt::Long;
&Getopt::Long::config(
   'require_order',			# don't mix non-options with options
   'auto_abbrev',			# allow unique option abbreviation
   'bundling',				# allow bundling of options
);

use Sys::Hostname;
local $ThisMachine = hostname;
$ThisMachine =~ s/\..*//;

local $prompt = $ENV{'prompt'} || '# ';

unshift (@ARGV, split(/\s+/, $ENV{'PEXEC'})) if (exists $ENV{'PEXEC'});

local $opt_a;				# all
local $opt_debug;			# debug
local $opt_fanout=256;			# remote-copy fan-out
local $opt_h;				# help
local $opt_l;				# login
local @opt_m;				# machines
local $opt_man;				# man page
local $opt_output='-';			# output file (default: STDOUT)
local $opt_P;				# parallel
local $opt_p;				# prefix
local $opt_rand;			# randomize host list
local $opt_rcp;				# rcp to remote
local $opt_opts;			# remote copy program options
local $opt_ping;			# ping remote before exec'ing cmd
local $opt_ping_host;			# ping remote:port/proto
local $opt_ping_timeout='5';		# ping timeout (default: 5 sec)
local $opt_rsh;				# rsh remote
local $opt_rsync;			# rsync to remote
local $opt_rsync_rsh;			# rsync remote transport shell
local @opt_s;				# skip
local $opt_scp;				# scp to remote
local $opt_ssh;				# ssh remote
local $opt_success='0';			# successful exit statuses
local $opt_t=300;			# timeout
local $opt_v;				# verbose
local $opt_V;				# verify

pod2usage(2) unless &GetOptions(
   'a|all'		=> \$opt_a,
   'd|debug'		=> \$opt_debug,
   'exit-success=s'	=> \$opt_success,
   'fan-out=i'		=> \$opt_fanout,
   'h|help'		=> \$opt_h,
   'l|login=s'		=> \$opt_l,
   'm|machines=s'	=> \@opt_m,
   'man'		=> \$opt_man,
   'o|output=s'		=> \$opt_output,
   'P|parallel:i'	=> \$opt_P,
   'p|prefix'		=> \$opt_p,
   'ping'		=> \$opt_ping,
   'ping-host=s'	=> \$opt_ping_host,
   'ping-timeout=i'	=> \$opt_ping_timeout,
   'random'		=> \$opt_rand,
   'rcp'		=> \$opt_rcp,
   'rcp-opts=s'		=> \$opt_opts,
   'rsh'		=> \$opt_rsh,
   'rsync'		=> \$opt_rsync,
   'rsync-opts=s'	=> \$opt_opts,
   'rsync-rsh=s'	=> \$opt_rsync_rsh,
   's|skip=s'		=> \@opt_s,
   'scp'		=> \$opt_scp,
   'scp-opts=s'		=> \$opt_opts,
   'ssh'		=> \$opt_ssh,
   't|timeout=i'	=> \$opt_t,
   'v|verbose'		=> \$opt_v,
   'V|verify'		=> \$opt_V,
);

pod2usage(1) if (defined($opt_h));
if ($opt_man) {				# print the man page
   $ENV{'LANG'} = 'C';
   if ($< && $>) {			# no root privs
      pod2usage(-verbose => 2);
   } else {
      my $id = getpwnam("nobody") || getpwnam("nouser") || -2;
      eval {
	 $> = $id;			# drop euid first
	 $< = $id;			# drop ruid
      };
      if (!$@ && $< && $>) {		# success!
	 pod2usage(-verbose => 2)
      } else {				# failure!
	 pod2usage(1);
      }
   }
}

pod2usage(qq|\n$prog: option '-l' cannot be used with without '--rsh' or '--ssh'\n|)
   if (defined($opt_l) && !(defined($opt_rsh) || defined($opt_ssh)));
pod2usage(qq|\n$prog: option '--rsh' cannot be used with option '--ssh'\n|) if
   (defined($opt_rsh) && defined($opt_ssh));
pod2usage(qq|\n$prog: option '--rsync-rsh' can only be used with option '--rsync'\n|) if
   (defined($opt_rsync_rsh) && ! defined($opt_rsync));
pod2usage(qq|\n$prog: option '--fan-out' must be non-negative\n|)
   unless ($opt_fanout >= 0);
pod2usage(qq|\n$prog: option '--ping-timeout' must be positive\n|)
   unless ($opt_ping_timeout > 0);
$opt_ping = 1 if (defined($opt_ping_host));

local $ping_port = undef;
local $ping_proto = undef;
if (defined($opt_ping)) {
   if (defined($opt_ping_host)) {

      pod2usage("\n$prog: --ping-host: malformed: $opt_ping_host\n")
	 unless ($opt_ping_host =~ /\%host\%/);

      if ($opt_ping_host =~ 
	 /^(.*):([^\/]+)\/(tcp|udp|icmp|syn)$/) {	# %host%:port/proto
	 $opt_ping_host = $1;
	 $ping_port = $2;
	 $ping_proto = $3;
	 if ($ping_port !~ /^\d+$/) {			# service name
	    $ping_port = getservbyname($ping_port, 'tcp') ||
	       pod2usage(qq|\n$prog: --ping-host: no such service: $ping_port\n|);
	 }
      } elsif ($opt_ping_host =~ /^(.*):([^\/]+)$/) {	# %host%:port
	 $opt_ping_host = $1;
	 $ping_port = $2;
	 if ($ping_port !~ /^\d+$/) {			# service name
	    $ping_port = getservbyname($ping_port, 'tcp') ||
	       pod2usage(qq|\n$prog: --ping-host: no such service: $ping_port\n|);
	 }
	 $ping_proto = 'syn';
      } elsif ($opt_ping_host =~ /:/) {
	 pod2usage("\n$prog: --ping-host: malformed: $opt_ping_host\n")
      }

   } else {
      $opt_ping_host = '%host%';
   }
}

my @rcp_opts   = ('-rp');		# default rcp options
my @rsync_opts = ('-aq');		# default rsync options
my @scp_opts   = ('-Brpq');		# default scp options

local $opt_rcpy = undef;
local @opt_rcpy_opts = split(/\s+/, $opt_opts) if (defined($opt_opts));
if (defined($opt_rcp)) {
   pod2usage(qq|\n$prog: option '--rcp' cannot be used with option '--scp'\n|)
      if (defined($opt_scp));
   pod2usage(qq|\n$prog: option '--rcp' cannot be used with option '--rsync'\n|)
      if (defined($opt_rsync));
   $opt_rcpy = 'rcp';
   @opt_rcpy_opts = @rcp_opts unless(@opt_rcpy_opts);
   $ping_port = getservbyname('shell', 'tcp') unless (defined($ping_port));
   $ping_proto = 'syn' unless (defined($ping_proto));
} elsif (defined($opt_scp)) {
   pod2usage(qq|\n$prog: option '--scp' cannot be used with option '--rsync'\n|)
      if (defined($opt_rsync));
   $opt_rcpy = 'scp';
   @opt_rcpy_opts = @scp_opts unless(@opt_rcpy_opts);
   $ping_port = getservbyname('ssh', 'tcp') unless (defined($ping_port));
   $ping_proto = 'syn' unless (defined($ping_proto));
} elsif (defined($opt_rsync)) {
   $opt_rcpy = 'rsync';
   @opt_rcpy_opts = @rsync_opts unless(@opt_rcpy_opts);
   pod2usage(qq|\n$prog: option '--rsync-opts' may not contain '-e' or '--rsh'\n|)
      if (grep(/(-e|--rsh)\s+\S+/, @opt_rcpy_opts));
   $opt_rsync_rsh = 'ssh -qx' unless (defined($opt_rsync_rsh));
   push(@opt_rcpy_opts, '-e', $opt_rsync_rsh);
   $ping_port = getservbyname('rsync', 'tcp') unless (defined($ping_port));
   $ping_proto = 'syn' unless (defined($ping_proto));
}

if (defined($opt_rcpy)) {
   pod2usage(qq|\n$prog: option '--$opt_rcpy' cannot be used with option '--ssh'\n|)
      if (defined($opt_ssh));
   pod2usage(qq|\n$prog: option '--$opt_rcpy' cannot be used with option '--rsh'\n|)
      if (defined($opt_rsh));
}

# redefine success
local %EXIT_success = ();
if (defined($opt_success)) {
   foreach my $status (split(',', $opt_success)) {
      pod2usage(qq|\n$prog: --exit-success: '$status' must be numeric\n|)
	 unless ($status =~ /^\d+$/);
      $EXIT_success{$status}++;
   }
} else {
   $EXIT_success{'0'}++;
}

unless (@ARGV) {
   pod2usage("\n$prog: no cmd specified\n");
}

local $strand = '';			# internally-generated random string
local @ARGTree = ();			# ARGV for the tree
if (defined($opt_rcpy)) {
   pod2usage("\n$prog: --$opt_rcpy: too few arguments\n")
      unless (scalar @ARGV >= 2);

   my @RLP = ($opt_rcpy, @opt_rcpy_opts);

   my @Chars = ('a'..'z','A'..'Z','0'..'9','_');
   foreach (1 .. 32) {
      $strand .= $Chars[rand @Chars];
   }

   my $dst_host = $dst_path = $dst_file = undef;
   my $dst = $ARGV[-1];			# dest is always the last arg
   my $dst_d = 0;			# assume dest isn't a dirname

   pod2usage("\n$prog: --$opt_rcpy: invalid dest description: $dst\n")
      unless ($dst =~ /\%host\%:/);

   pod2usage("\n$prog: --$opt_rcpy: destination directory must be absolute\n")
      unless ($dst =~ /\%host\%:\//);

   pod2usage("\n$prog: --$opt_rcpy: internal error: $dst\n")
      if ($dst =~ /\%$strand\%/);

   if ($dst =~ /^(\S+):(.*)\/(\S+)$/) {	# ^dst_host:dst_path/dst_file$
      $dst_host = $1;
      $dst_path = $2;
      $dst_file = $3;
   } elsif ($dst =~ /^(\S+):\/$/) { 	# ^dst_host:/$
      $dst_host = $1;
      $dst_path = '/';
      $dst_file = '.';
   }

   (my $server = $dst_host) =~ s/\%host\%/\%$strand\%/ig;

   if (scalar @ARGV > 2) {		# multiple src must go to a directory
      $dst_d = 1;
   } elsif ($dst_file eq '.') {		# a trailing "/."
      $dst_d = 1;
   } elsif ($dst_file =~ /\/$/) {	# a trailing "/"
      $dst_path .= "/$dst_file" ;
      $dst_file = '.';
      $dst_d = 1;
   } elsif (-d "$dst_path/$dst_file"	# a hint from local disk -
      && $dst_file ne '.') {		# this could be problematic
      $dst_d = 1;			# if the remote disk doesn't
   }					# mimick the execution host's

   grep($_ =~ s/\/+/\//g,@ARGV);	# strip duplicate slashes

   for (my $i = 0; $i < $#ARGV; $i++) {
      my $src = $ARGV[$i];
      -r $src || die "$prog: $src: $!\n" unless (defined($opt_debug));

      my $src_path = $src_file = undef;

      if ($src =~ /^(.*)\/(\S+)$/) {	# ^src_path/src_file$
	 $src_path = $1;
	 $src_file = $2;
      } else {
	 $src_path = '.';
	 $src_file = $src;
      }

      if (defined($opt_rsync)) {
	 if ($src_file =~ /\/$/ && -d "$src_path/$src_file") {	# src/
	    chop $src_file;		# trim trailing "/"
	    opendir(SRC, "$src_path/$src_file")
	       || die "$prog: $src_path/$src_file: $!\n";
	    foreach my $file (grep { $_ !~ /^\.{1,2}$/ } readdir(SRC)) {
	       push(@ARGTree, "$dst_path/$dst_file/$file");
	    }
	    closedir(SRC);
	 } else {
	    push(@ARGTree, $dst_d
	       ? "$dst_path/$dst_file/$src_file"
	       : "$dst_path/$dst_file"
	    );
	 }
      } elsif (defined($opt_scp)) {
	 push(@ARGTree, $dst_d
	    ? "$dst_path/$dst_file/$src_file"
	    : "$dst_path/$dst_file"
	 );
      } else {
	 push(@ARGTree, $dst_d
	    ? "$server:$dst_path/$dst_file/$src_file"
	    : "$server:$dst_path/$dst_file"
	 );
      }
   }
   push (@ARGTree, $ARGV[-1]);

   if (defined($opt_rsync)) {		# remote copy by rsync-rsh
      unshift (@ARGTree, split(/\s+/, "$opt_rsync_rsh $server"), @RLP);
   } elsif (defined($opt_scp)) {	# remote copy by ssh
      unshift (@ARGTree, split(/\s+/, "ssh -qnx $server"), @RLP);
   } else {
      unshift (@ARGTree,@RLP);		# 3rd party copy
   }

   grep($_ =~ s/\/+/\//g,@ARGTree);	# strip duplicate slashes

   unshift (@ARGV,@RLP);

   $opt_output = '-';			# rcpy always sends output to STDOUT
}

if (defined($opt_rsh)) {
   my @RLP = (defined($opt_l) ?
      ('rsh','-n',"$opt_l\@%host%") :
      ('rsh','-n','%host%')
     );
   unshift (@ARGV,@RLP);
   $ping_port = getservbyname('shell', 'tcp') unless (defined($ping_port));
   $ping_proto = 'syn' unless (defined($ping_proto));
}

if (defined($opt_ssh)) {
   my @RLP = (defined($opt_l) ?
      ('ssh','-nx',"$opt_l\@%host%") :
      ('ssh','-nx','%host%')
     );
   unshift (@ARGV,@RLP);
   $ping_port = getservbyname('ssh', 'tcp') unless (defined($ping_port));
   $ping_proto = 'syn' unless (defined($ping_proto));
}

if (defined($opt_P)) {
   if (defined($opt_rcpy)) {
      $opt_P = 1 unless $opt_P;		# default rcpy arity = 1
   } else {
      $opt_P = $PMAX unless $opt_P;
   }
} else {
   $opt_P = 1;
}

if (defined($opt_ping)) {
   $ping_port = getservbyname('echo', 'tcp') unless (defined($ping_port));
   $ping_proto = 'icmp' unless (defined($ping_proto));
}

unless (@opt_m) {
   pod2usage("\n$prog: no machine group specified\n");
}

local %NETGROUP = ();
&CacheNetgroups(\%NETGROUP);
local @MachineList = &GetMachines(\%NETGROUP,\@opt_m);
local @MachineSkip = &GetMachines(\%NETGROUP,\@opt_s) if (@opt_s);
unless (defined($opt_a)) {
   push(@MachineSkip,$ThisMachine);
   push(@MachineSkip,
      map { join('.', unpack('C4', $_)) }
	 (gethostbyname($ThisMachine))[4]);
}

foreach $skip (@MachineSkip) {
   @MachineList = grep(! /^\Q$skip\E$/,@MachineList);
}

unless (@MachineList) {
   print STDERR "$prog: empty machine group!\n" if ($opt_v);
   exit 0;
}

use POSIX qw(tmpnam);
do { $tty = tmpnam() }
   until sysopen(TTY, $tty, O_RDWR|O_EXCL|O_CREAT); 

print STDERR "Timeout: $opt_t seconds.\n" if ($opt_v && $opt_t);

# Exec the command
local @WorkQ = ();
local %RUNpids = %RC = ();
local $SIG{'QUIT'} = 'IGNORE';
local $SIG{'INT'} = local $SIG{'TERM'} = \&IT_signal_handler;
local $SIG{'TSTP'} = \&tstp_signal_handler; local $SIGTSTP = 0;
local $SIG{'__DIE__'} = \&__DIE__signal_handler;

H: while (@MachineList) {
   my $running = 0;
   foreach (values %RUNpids) { $running++ unless defined $_->{'sender'}; }
   if ($running < abs($opt_P)) {
      my $machine = ($opt_rand
	 ? splice(@MachineList,int(rand(scalar @MachineList)),1)
	 : shift(@MachineList)
      );
      if ( my $pid = &spawn($machine) ) {
	 $RUNpids{$pid} = {
	    'sender'	=> undef,	# a root process
	    'machine'	=> $machine,
	 };
      }
      next H;
   }

   while (@WorkQ) {
      last unless (@MachineList);
      last unless ( scalar keys %RUNpids < $opt_fanout );
      my $sender = shift(@WorkQ);
      my $machine = ($opt_rand
	 ? splice(@MachineList,int(rand(scalar @MachineList)),1)
	 : shift(@MachineList)
      );
      if ( my $pid = &tspawn($sender,$machine) ) {
	 $RUNpids{$pid} = {
	    'sender'	=> $sender,	# a tree process
	    'machine'	=> $machine,
	 };
      }
   }

   my $WQ = &ReapChildren(\%RUNpids,\%RC);

   if (defined($opt_rcpy) && scalar(@{ $WQ })) { 
      push (@WorkQ, @{ $WQ });
      $opt_P = 0 unless ($opt_P > 0);
   }

   &handle_sigTSTP if ($SIGTSTP);
}

while ( %RUNpids ) {
   &ReapChildren(\%RUNpids,\%RC);
   &handle_sigTSTP if ($SIGTSTP);
}

if (-e $tty) {
   unlink($tty) || die "$prog: unable to unlink $tty: $!\n";
}

my $status = 0;
foreach my $failed (keys %RC) {
   $status |= $RC{$failed};		# OR the non-successful exit statuses
}

exit $status;

sub tspawn ($$) {
   my ($sender,$machine) = @_;

   my $pid;
   my @Cmd = (scalar @ARGTree ? @ARGTree : @ARGV);

   grep($_ =~ s/\%$strand\%/$sender/ig,@Cmd);
   grep($_ =~ s/\%host\%/$machine/ig,@Cmd);
   (my $ping_host = $opt_ping_host) =~ s/\%host\%/$machine/ig if (defined($opt_ping));
   my $cmd = join(' ',@Cmd);

   if ( $pid = fork ) {				# parent
      return $pid;
   } elsif ( defined $pid ) {			# child
      local $SIG{'TSTP'} = 'IGNORE';
      local $SIG{'__DIE__'} = 'DEFAULT';
      local $SIG{'INT'} = local $SIG{'TERM'} = local $SIG{'QUIT'} = sub {
	 if (defined($cpid)) {
	    kill 9,$cpid;
	    close(CMD);
	 }
	 die " '$cmd': killed.\n";
      };
      local $SIG{'ALRM'} = sub {
	 if (defined($cpid)) {
	    kill 9,$cpid;
	    close(CMD);
	 }
	 die " '$cmd': command timed out ($opt_t sec)\n";
      };

      my $rc = 0;

      alarm($opt_t);
      unless (defined($cpid = 
	 open(CMD, "-|"))) {
	    die " '$cmd': failed.\n";
      }

      unless ($cpid) {				# grandchild
	 open(STDERR, ">&STDOUT");		# dup STDOUT
	 if (defined($opt_debug)) {
	    print "'host' '$machine' && "
	       if (defined($opt_V));
	    print "'ping' '$ping_host:$ping_port/$ping_proto' && "
	       if (defined($opt_ping));
	    print join(" ", map { qq|'$_'| } @Cmd) . "\n";
	    sleep 1;
	    exit 0;
	 } else {

	    if (defined($opt_V)) {
	       unless (gethostbyname($machine)) {	# qualify host
		  print STDOUT "bad hostname\n";
		  exit -1;
	       }
	    }

	    if (defined($opt_ping)) {
	       use Net::Ping;
	       use POSIX ":errno_h";

	       my $p = Net::Ping->new($ping_proto, $opt_ping_timeout);
	       $p->{port_num} = $ping_port;
	       if ($p->ping($ping_host)) {
		  if ($ping_proto eq 'syn') {
		     unless ($p->ack($ping_host)) {	# SYN ack failed
			print STDOUT "noping\n";
			exit EHOSTUNREACH;
		     }
		  }
	       } else {					# ping failed
		  print STDOUT "noping\n";
		  exit EHOSTUNREACH;
	       }
	       $p->close();
	    }

	    { exec { $Cmd[0] } @Cmd };
	    print STDOUT "$!\n";
	    exit -1;
	 }
      }

      my @Output = <CMD>;
      unless (close CMD) {
	 $rc = $?>>8;
      }
      alarm(0);

      $| = 1;
      if (@Output) {
	 my $host = $machine;
	 $host =~ s/\..*//
	    unless ($host =~ /^(\d{1,3}\.){3,3}\d{1,3}$/);
	 my $server = $sender;
	 $server =~ s/\..*//
	    unless ($server =~ /^(\d{1,3}\.){3,3}\d{1,3}$/);
	 @Output = map { "$server->$host: $_" } @Output if ($opt_p);
	 if ($opt_v) {
	    unshift(@Output, "$prompt$cmd\n");
	    push(@Output, "\n");
	 }
	 sysopen(TTY, $tty, O_RDONLY) ||
	    die "$prog: unable to open '$tty': $!\n";
	 die "$prog: flock failure: $!\n" unless flock(TTY, LOCK_EX);
	 print STDOUT (@Output);
	 close STDOUT;
	 flock(TTY, LOCK_UN);
	 close(TTY);
      } elsif ($opt_v) {			# no output produced by cmd
	 sysopen(TTY, $tty, O_RDONLY) ||
	    die "$prog: unable to open '$tty': $!\n";
	 die "$prog: flock failure: $!\n" unless flock(TTY, LOCK_EX);
	 print STDOUT "$prompt$cmd\n";
	 close STDOUT;
	 flock(TTY, LOCK_UN);
	 close(TTY);
      }
      exit $rc;
   } else {					# fork error
      warn "fork: $!\n";
      return 0;
   }
}

sub spawn ($) {
   my $machine = $_[0];

   my $pid;
   my @Cmd = @ARGV;
   grep($_ =~ s/\%host\%/$machine/ig,@Cmd);
   (my $outfile = $opt_output) =~ s/\%host\%/$machine/ig;
   (my $ping_host = $opt_ping_host) =~ s/\%host\%/$machine/ig if (defined($opt_ping));
   my $cmd = join(' ',@Cmd);

   if ( $pid = fork ) {				# parent
      return $pid;
   } elsif ( defined $pid ) {			# child
      local $SIG{'TSTP'} = 'IGNORE';
      local $SIG{'__DIE__'} = 'DEFAULT';
      local $SIG{'INT'} = local $SIG{'TERM'} = local $SIG{'QUIT'} = sub {
	 if (defined($cpid)) {
	    kill 9,$cpid;
	    close(CMD);
	 }
	 die " '$cmd': killed.\n";
      };
      local $SIG{'ALRM'} = sub {
	 if (defined($cpid)) {
	    kill 9,$cpid;
	    close(CMD);
	 }
	 die " '$cmd': command timed out ($opt_t sec)\n";
      };

      my $rc = 0;

      alarm($opt_t);
      unless (defined($cpid = 
	 open(CMD, "-|"))) {
	    die " '$cmd': failed.\n";
      }

      unless ($cpid) {				# grandchild
	 open(STDERR, ">&STDOUT");		# dup STDOUT
	 if (defined($opt_debug)) {
	    print "'host' '$machine' && "
	       if (defined($opt_V));
	    print "'ping' '$ping_host:$ping_port/$ping_proto' && "
	       if (defined($opt_ping));
	    print join(" ", map { qq|'$_'| } @Cmd) . "\n";
	    sleep 1;
	    exit 0;
	 } else {

	    if (defined($opt_V)) {
	       unless (gethostbyname($machine)) {	# qualify host
		  print STDOUT "bad hostname\n";
		  exit -1; 
	       }
	    }

	    if (defined($opt_ping)) {
	       use Net::Ping;
	       use POSIX ":errno_h";

	       my $p = Net::Ping->new($ping_proto, $opt_ping_timeout);
	       $p->{port_num} = $ping_port;
	       if ($p->ping($ping_host)) {
		  if ($ping_proto eq 'syn') {
		     unless ($p->ack($ping_host)) {	# SYN ack failed
			print STDOUT "noping\n";
			exit EHOSTUNREACH;
		     }
		  }
	       } else {					# ping failed
		  print STDOUT "noping\n";
		  exit EHOSTUNREACH;
	       }
	       $p->close();
	    }

	    { exec { $Cmd[0] } @Cmd };
	    print STDOUT "$!\n";
	    exit -1;
	 }
      }

      my @Output = <CMD>;
      unless (close CMD) {
	 $rc = $?>>8;
      }
      alarm(0);

      $| = 1;
      if (@Output) {
	 my $host = $machine;
	 $host =~ s/\..*//
	    unless ($host =~ /^(\d{1,3}\.){3,3}\d{1,3}$/);
	 if ($opt_p) {				# prefix
	    @Output = defined $opt_rcpy
	       ? map { "$ThisMachine->$host: $_" } @Output
	       : map { "$host: $_" } @Output;
	 }
	 sysopen(TTY, $tty, O_RDONLY) ||
	    die "$prog: unable to open '$tty': $!\n";
	 die "$prog: flock failure: $!\n" unless flock(TTY, LOCK_EX);
	 open (OUTPUT, ">>$outfile") || die "$prog: unable to open '$outfile': $!\n";
	 print STDOUT "$prompt$cmd\n" if ($opt_v);
	 print OUTPUT (@Output);
	 print STDOUT "\n" if ($opt_v);
	 close OUTPUT;
	 flock(TTY, LOCK_UN);
	 close(TTY);
      } elsif ($opt_v) {			# no output produced by cmd
	 sysopen(TTY, $tty, O_RDONLY) ||
	    die "$prog: unable to open '$tty': $!\n";
	 die "$prog: flock failure: $!\n" unless flock(TTY, LOCK_EX);
	 print STDOUT "$prompt$cmd\n";
	 close STDOUT;
	 flock(TTY, LOCK_UN);
	 close(TTY);
      }
      exit $rc;
   } else {					# fork error
      warn "fork: $!\n";
      return 0;
   }
}

sub ReapChildren ($$) {
   my ($RUN_ref,$RC_ref) = @_;
   use POSIX ":sys_wait_h";
   my @RunQ = ();

   foreach my $pid (keys %$RUN_ref) {
      if ( waitpid($pid,&WNOHANG) > 0 ) {
	 my $rc = $?>>8;
	 if (exists($EXIT_success{$rc})) {	# success!
	    push(@RunQ, $RUN_ref->{$pid}{'machine'});
	 } else {				# failure!
	    $$RC_ref{$RUN_ref->{$pid}{'machine'}} = $rc;
	 }
	 if (defined($RUN_ref->{$pid}{'sender'})) {
	    push(@RunQ, $RUN_ref->{$pid}{'sender'});
	 }
	 delete $RUN_ref->{$pid};
      }
   }
   select(undef, undef, undef, 0.1);
   return \@RunQ;
}

sub CacheNetgroups ($) {
   my $href = $_[0];

   my %TMP = ();

   open(CFG,'/etc/netgroup') || return 0;
   while (defined(my $ngrent = <CFG>)) {
      next if ($ngrent =~ /^#/);		# strip out comments
      next if ($ngrent =~ /(\(|\))/);		# strip lines containing ( or )
      chomp $ngrent;
      my ($key, $value) = split(/\s+/, $ngrent, 2);
      $TMP{$key} = $value if (defined $value);
   }
   close CFG;

   foreach my $key (sort keys %TMP) {
      @{ $href->{$key}} = &ExpandNetgroup(\%TMP, $TMP{$key});
   }
}

sub IntersectNetgroups ($$) {
   my ($aref1, $aref2) = @_;
   my @Intersect = ();
   my %UNION = ();
   my %SEEN;

   %SEEN = ();
   foreach my $member (@{ $aref1 }) {
      next if ($SEEN{$member}++);		# weed out A1 duplicates
      $UNION{$member}++;
   }

   %SEEN = ();
   foreach my $member (@{ $aref2 }) {
      next if ($SEEN{$member}++);		# weed out A2 duplicates
      $UNION{$member}++;
   }

   foreach my $member (keys %UNION) {
      push (@Intersect, $member)
	 if ($UNION{$member} > 1);		# member is in BOTH Arrays
   }

   return @Intersect;
}

sub ExpandNetgroup ($$) {
   my ($href, $values) = @_;

   return map { exists $href->{$_}
      ? &ExpandNetgroup($href, $href->{$_})	# netgroup indirection
      : $_ 
   } split /\s+/, $values;
}

sub GetMachines ($$) {
   my ($href,$aref) = @_;

   my @Machines = ();

   foreach my $machines (@{ $aref }) {
      $machines =~ s/\s+//go;				# kill whitespace

      while ($machines =~ /([^,\[]+)\[([\d,-]+)\]([^,]?)/) {
	 my $match  = $&;				# translate
	 my $prefix = $1;				#   p[1-10,13]s
	 my $suffix = $3;				# to
	(my $string = $2) =~ s/(\d+)/$prefix$1$suffix/g;#   p1s-p10s,p13s
	 $machines =~ s/\Q$match\E/$string/;		# for prefix 'p' and
      }							# suffix 's'

M:    foreach my $name (split(',',$machines)) {
	 my @Dash = split('-', $name);
	 if ($name =~ /^\@([^\@]+)$/) {			# a lone netgroup
	    push(@Machines,@{ $href->{$1} })
	       if (defined($href->{$1}));
	    next M;
	 } elsif ($name =~ /\@/) {			# intersection of netgroups
	    my @Isect = ();
	    my $Universal_Set = 1;
	    foreach my $ng (split('@', $name)) {
	       if (defined($href->{$ng})) {
		  @Isect = ($Universal_Set
		     ? @{ $href->{$ng} }
		     : IntersectNetgroups(\@Isect, \@{ $href->{$ng} })
		  );
		  $Universal_Set = 0;
	       } else {
		  next M;
	       }
	    }
	    push(@Machines,@Isect) if scalar(@Isect);
	    next M;
	 } elsif ($name =~ /^\^(.*)$/) {		# a file containing
	    unless (open(FILE, $1)) {			# hosts in the first
	       push(@Machines,$name);			# column, optionally
	       next M;					# delimited by a
	    }						# space or colon
	    my @NR = ();
	    while (defined(my $host = <FILE>)) {
	       next if ($host =~ /^(#|\^)/);
	       next if ($host =~ /^\s*$/);
	       $host =~ s/[\s:].*//g;
	       push (@NR,$host);
	    }
	    close FILE;
	    push(@Machines, &GetMachines($href,\@NR)) if (scalar(@NR));
	    next M;
	 } elsif (! (scalar(@Dash) % 2)) {		# a valid range
	    my $chunkL = my $chunkR = "";		# contains an even
	    while (scalar(@Dash)) {			# number of "things"
	       $chunkL .= shift(@Dash) . '-';		# split by '-'
	       $chunkR = pop(@Dash) . "-$chunkR";
	    }
	    chop($chunkL); chop($chunkR);
	    my $prefixL = $prefixR = undef;
	    my $numberL = $numberR = undef;
	    my $suffixL = $suffixR = undef;
	    if ($chunkL =~ /^(\D*)(\d+)((\D+[-\w]*)*)$/) {
	       $prefixL = $1;
	       $numberL = $2;
	       $suffixL = $3;
	    } else {
	       push(@Machines,$name);
	       next M;
	    }
	    if ($chunkR =~ /^(\D*)(\d+)((\D+[-\w]*)*)$/) {
	       $prefixR = $1;
	       $numberR = $2;
	       $suffixR = $3;
	    } else {
	       push(@Machines,$name);
	       next M;
	    }
	    if ($prefixL ne $prefixR) {			# cluster mismatch
	       push(@Machines,$name);
	       next M;
	    } elsif ($suffixL ne $suffixR) {		# cluster mismatch
	       push(@Machines,$name);
	       next M;
	    } else {
	       if ($numberL <= $numberR) {
		  my $fmt = ($numberL =~ /^0/
		     ? "$prefixL%0".length($numberL)."d$suffixL"	# a leading zero
		     : "$prefixL%d$suffixL"
		  );
		  for (my $i=$numberL; $i <= $numberR; $i++) {
		     push(@Machines,sprintf("$fmt",$i));
		  }
	       } else {
		  my $fmt = ($numberR =~ /^0/
		     ? "$prefixR%0".length($numberR)."d$suffixR"	# a leading zero
		     : "$prefixR%d$suffixR"
		  );
		  for (my $i=$numberL; $i >= $numberR; $i--) {
		     push(@Machines,sprintf("$fmt",$i));
		  }
	       }
	    }
	 } else {					# a single host
	    push(@Machines,$name) unless ($name =~ /^$/);
	 }
      }
   }

   # weed out duplicates
   my %SEEN = (); my @Unique = ();
   foreach my $machine (@Machines) {
      next if ($SEEN{$machine}++);
      push (@Unique, $machine);
   }
   return @Unique;
}

sub tstp_signal_handler {
   my $nal = $_[0];
   ${ "SIG$nal" } = 1;
   kill 'CONT' => -$$;
   return 0;
}

sub handle_sigTSTP {
   my %_RUNpids = %RUNpids;
   my @_MachineList = @MachineList;
   my ($pid, $src, $dst);

   $SIGTSTP = 0;

   format STDERR =
^>>>>>>>>>>>>>>> -> ^<<<<<<<<<<<<<<<  pid=^<<<<<<<<<<<<<<<<
$src,               $dst,                 $pid
.

# processes running
   print STDERR "\n                    Outstanding Processes:\n";
   foreach $pid (sort {$a <=> $b } keys %_RUNpids) {
      $dst = $_RUNpids{$pid}{'machine'};
      $src  = (defined $_RUNpids{$pid}{'sender'}
	 ? $_RUNpids{$pid}{'sender'}
	 : $ThisMachine
      );
      write STDERR;
   }

# processes waiting to run
   my $num = scalar @_MachineList;
   if ($num > $PMAX) {
      print STDERR "\n                    ($num more waiting to run)\n";
   } else {
      foreach $dst (@_MachineList) {
	 $pid = '(waiting to run)';
	 $src = '';
	 write STDERR;
      }
   }

   print STDERR "\n";

}

sub IT_signal_handler {
   my $nal = $_[0];

   local $SIG{$nal} = 'IGNORE';
   kill $nal => -$$;
   unlink($tty) if (-e $tty);
   exit -1;
}

sub __DIE__signal_handler {
   my $error = $_[0];

   unlink($tty) if (-e $tty);
   die $error;
}

# Documentation

=head1 NAME

B<pexec> - execute a command on a set of hosts

=head1 SYNOPSIS

B<pexec> [B<-h>] [B<--man>]

B<pexec> I<args> S<[B<-l> I<user>]> S<[B<-o> I<outfile>]> S<[B<--rsh>]>
S<[B<--ssh>]> B<cmd>

B<pexec> I<args> S<B<--rcp>>   S<[B<--rcp-opts> I<opts>]>  B<src> S<[B<src ...>]>
[I<user@>]%host%:B<dest>

B<pexec> I<args> S<B<--scp>>   S<[B<--scp-opts> I<opts>]>  B<src> S<[B<src ...>]>
[I<user@>]%host%:B<dest>

B<pexec> I<args> S<B<--rsync>> S<[B<--rsync-opts> I<opts>]>
S<[B<--rsync-rsh> I<rshell>]> B<src> S<[B<src ...>]> [I<user@>]%host%:B<dest>

where I<args> are one or more of:

=over

S<B<-m> I<host>[I<,host>]> S<[B<-s> I<host>[I<,host>]]> S<[B<-P> [I<#>]]>
[B<-dpVv>] [B<--all>] S<[B<--exit-success> I<rc>[I<,rc>]]>
[B<--random>] S<[B<-t> I<tmo>]>

[B<--ping>] S<[B<--ping-host> I<format>[I<:port>[I</proto>]]]> S<[B<--ping-timeout> I<tmo>]>

=back

=head1 DESCRIPTION

B<pexec> builds a machine list from command-line arguments on which an
arbitrary B<cmd> is to be run.  Called in its most general form, B<pexec>
achieves parallelism by overseeing a fixed number of fork(2)'d and
execvp(3)'d B<cmd> processes marshalled by the host initiating the
operation (the execution host).  If the string "I<%host%>" is part of
B<cmd>, names from the machine list are substituted in its stead.

Alternatively specifying one of the remote file copy operations, B<pexec>
fixes B<cmd> appropriately and distributes B<src> to the machine list's
B<dest> in a tree-like fashion: on success (proper exit status), the
destination machine is placed on a work queue to potentially source a
future copy operation itself.  Any source machine and the "root" of the
tree will always be returned to the work queue upon completion of their
subtasks (but see B<--parallel> below for alternate behavior).  Note here
that the string "I<%host%>" is a mandatory part of the B<dest> description.

The output of B<cmd> on each machine is printed to the execution host's
STDOUT by default (but see B<--output> below for alternate behavior).  B<pexec>
will catch the following signals for special processing: INT (B<^C>), QUIT
(B<^\>), TERM and TSTP (B<^Z>).  B<pexec> will elevate INT and TERM signals
it receives to KILL any children it has spawned, then terminate itself
immediately.  Signalling QUIT (usu. B<^\>) will KILL any children that have
already been spawned by B<pexec>, however execution of the parent
I<proceeds> if there are any hosts remaining in the machine list that have
not had the opportunity to exec something!  Issuing TSTP (B<^Z>) will print
to STDERR the list of outstanding processes B<pexec> has spawned (or plans
to) that await completion, then continue.

=head1 OPTIONS

=over 4

=item B<-h,--help>

Show command usage and exit.

=item B<--man>

Print the pexec(1) manpage and exit.

=item B<-a,--all>

Permit B<cmd> to be run on the execution host if it is specified in the
machine list (skipped by default).

=item B<-d,--debug>

Don't really execute anything, just print to STDOUT the B<cmd> that would
be executed (via execvp(3)) throughout the execution cycle.  The printed
command and its arguments are individually enclosed by single quotes.

=item B<--exit-success> I<rc>[I<,rc>]

Define the successful exit statuses for B<cmd> as comma-separated integer
values.  Note that fan-out for the remote file copy operations is only
accomplished by proper exit status of B<cmd> as it is run by the hosts
which comprise the machine list.  Requesting B<pexec> to run a remote copy
operation via B<--rcp>, B<--rsync> or B<--scp> which succeeds
yet exits with an I<rc> outside this list will result in I<serial>
operation!  On the other hand, cascading failure may ensue if you include a
return code here which really does indicate failure of B<cmd>.  Default
behavior if this option is omitted is to only consider exit status I<0>
indicative of success.

=item B<--fan-out> I<#>

If a remote file copy operation is requested, permit fan-out of B<cmd> to
be sourced by at most I<#> >= 0 hosts from the machine list simultaneously.
If B<--fan-out> is not specified, the default is 256-way parallelism.
Entirely serial operation is accomplished by setting B<--fan-out=0> in which
case no fan-out is performed whatsoever; the source for every remote copy
to all hosts in the machine list will be the execution host itself.

=item B<-l,--login> I<user>

Authenticate as I<user> on the remote machine (only valid with "B<--rsh>" or
"B<--ssh>").

=item B<-m,--machines> I<host>[I<,host>]

Include I<host> in the machine list.  Valid names are: hosts, netgroups,
ranges, or a path to files containing these entities (newline separated).
Each I<host> specification may be inter-mixed however always comma
separated.  Netgroup names are invoked by using the "@" symbol, which acts
as an intersection operator.  A single netgroup can be designated with a
leading or trailing "@" (e.g. "@compute"), which can be thought of as the
(implied) Universal Set intersected with the netgroup specified.  Multiple
"@"-separated names result in a machine list of hosts that the given
netgroups have in common (e.g. "compute@CU1").  A host range is specified
by a hyphen "-" between host names of the form "B<pDs>" for prefix B<p>,
digit(s) B<D>, and optional suffix B<s> (e.g.  "rr01a-rr16a").  The LHS
prefix of the statement must match the RHS prefix; likewise for any given
suffix.  If the LHS digits are less than the RHS digits, the resulting
machine list will be ascending in order, otherwise the list will descend
numerically.  You may alternatively specify a host range by "factoring out"
the prefix and suffix and merely enclose the digits in square brackets
(e.g. "rr[01-16]a") in which case B<pexec> will translate what you mean
before the machine list is processed.  Note that in either case, B<pexec>
will preserve any zero-padding that the I<smallest number> of the given
range posesses (e.g.  the shown example will produce rr01a, rr02a, ...
rr16a).  File paths are given with a leading "^" (e.g.  "^/tmp/bootme").
Multiple instances of B<-m> may be issued.

=item B<-o,--output> I<outfile>

Send the output produced by B<cmd> to I<outfile>.  If the string
"I<%host%>" is part of I<outfile>, names from the machine list are
substituted in its stead.  This option is ignored for the remote file copy
operations.

=item B<-P,--parallel> [I<#>]

Permit parallel execution of B<cmd> by the execution host on I<#> hosts
from the machine list simultaneously.  Generally, if I<#> is not specified,
the default is 32-way parallelism; if B<-P> is omitted altogether, B<cmd> is
executed serially on each machine in the list.

In the case of B<--rcp>, B<--rsync> or B<--scp>, however, if
I<#> is omitted the default is to set B<P=1> and accomplish parallelism by
B<cmd> fan-out (see B<--fan-out> above to limit the width).  Specifying larger
values than I<1> might be desirable to take advantage of additional capabilities
the execution host may possess over others in the machine list (e.g. faster
disk, larger network pipe, etc).  A negative value of I<#> permits the
execution host to initially source B<abs>(I<#>) parallel remote copy
operations but is then omitted from the work queue for future execution.

=item B<--ping>

Ping each host in the machine list before executing I<cmd>.  Successful
acknowledgment within the grace period permits I<cmd> to proceed; otherwise
the child prints "noping" on its STDOUT and exits EHOSTUNREACH.  An
intelligent effort is made to set appropriate default port/protocol values
to provide the best-possible assurance I<cmd> will succeed to the host
should the ping be successful.  For example, the B<pexec> options involving
ssh(1)/scp(1) will set default ping attributes to I<22/syn>; likewise for
rsh(1)/rcp(1) and rsync(1).  These may be overridden by the B<--ping-host>
option below.  In the event B<pexec> is unable to decipher which service
you're intending, default ping attributes are set to the standard:
I<echo/icmp>.  Be forewarned, however, that I<icmp> ping (to any port)
requires root privilege.

=item B<--ping-host> I<format>[I<:port>[I</proto>]]]

Define the remote host I<format> to ping, and optionally a service
I<port>/I<proto>.  The host I<format>, at minimum, must contain the string
"I<%host%>" but may be used to describe additional characteristics of the
remote host for ping purposes (see the B<EXAMPLES> section below).  The
I<port> specification is optional and may either be a number or a service
name, in which case it will be converted to a port number.  Omitting the
I<port> lends its value to the default process outlined in the B<--ping>
description above.  The I<proto> specification is also optional but must be
one of "I<tcp>", "I<udp>", "I<icmp>" or "I<syn>".  Be forewarned that an
I<icmp> ping (to any port) requires root privilege.  If the I<proto>
argument is not specified and the I<port> is defined, default behavior is
to use "I<syn>" for the protocol.  If B<--ping> is selected yet option
B<--ping-host> is omitted altogether, I<format> defaults to "I<%host%>"
leaving the I<port>/I<proto> values to the default process outlined in the
B<--ping> description above.

=item B<--ping-timeout> I<tmo>

Timeout for ping acknowledgement.  Values for I<tmo> must be greater than "0"
(default: 5 sec).

=item B<-p,--prefix>

Generally, prefix every line of output produced by B<cmd> by S<"I<host>: ">, the
machine on/for which it was run.  Remote file copy specifications get
prefixed by S<"I<server>-E<gt>I<host>: ">.

=item B<--random>

Randomize the machine list instead of honoring the order provided on the
command line.

=item B<--rcp> B<src> [B<src ...>] [I<user@>]%host%:B<dest>

Distribute locally-resident B<src> (file or directory) to remote B<host:dest>
using rcp(1) for every host in the machine list.  Specifying more than one
B<src> mandates that B<host:dest> be a directory name on the remote
machine.  Password-less rsh(1) authentication for I<user> must succeed
between any given pair of hosts in the machine list!  Your current I<user>
name is assumed if none is specified.

=item B<--rcp-opts> I<opts>

If B<--rcp> is specified, pass the following I<opts> directly to rcp(1).
If this option is omitted, I<opts> defaults to "I<-rp>" (recursive; preserve
mode, ownership and timestamps).

=item B<--rsh>

Remote B<cmd> execution via rsh(1) (equivalent to S<"rsh -n I<%host%>">).

=item B<--rsync> B<src> [B<src ...>] [I<user@>]%host%:B<dest>

Distribute locally-resident B<src> (file or directory) to remote B<host:dest>
using rsync(1) for every host in the machine list.  Specifying more than
one B<src> mandates that B<host:dest> be a directory name on the remote
machine.  Password-less ssh(1) authentication for I<user> must succeed
between any given pair of hosts in the machine list (see B<--rsync-rsh>
below for an alternate remote-shell and/or authentication method)!  Your
current I<user> name is assumed if none is specified.

=item B<--rsync-opts> I<opts>

If B<--rsync> is specified, pass the following I<opts> directly to rsync(1).
If this option is omitted, I<opts> defaults to "I<-aq>" (archive; quiet).
Do not specify a remote transport shell with this option (see B<--rsync-rsh>
below)!

=item B<--rsync-rsh> I<rshell>

If B<--rsync> is specified, use I<rshell> as the remote transport shell for
rsync(1).  You can also use B<--rsync-rsh> to authenticate as a different
I<user> on the remote machine (see the B<EXAMPLES> section below).  If this
option is omitted, I<rshell> defaults to "I<ssh -qx>".

=item B<--scp> B<src> [B<src ...>] [I<user@>]%host%:B<dest>

Distribute locally-resident B<src> (file or directory) to remote B<host:dest>
using scp(1) for every host in the machine list.  Specifying more than one
B<src> mandates that B<host:dest> be a directory name on the remote machine.
Password-less ssh(1) authentication for I<user> must succeed between any
given pair of hosts in the machine list!  Your current I<user> name is
assumed if none is specified.

=item B<--scp-opts> I<opts>

If B<--scp> is specified, pass the following I<opts> directly to scp(1).
If this option is omitted, I<opts> defaults to "I<-Brpq>" (batch mode;
recursive; preserve mode, ownership and timestamps; quiet).

=item B<--ssh>

Remote B<cmd> execution via ssh(1) (equivalent to S<"ssh -nx I<%host%>">).

=item B<-s,--skip> I<host>[I<,host>]

Skip I<host> from the machine list.  See B<--machines> above for valid
I<host> specifications.

=item B<-t,--timeout> I<tmo>

Timeout for execution of B<cmd>.  A value of "0" disables the timeout
(default: 300 sec).

=item B<-V,--verify>

Verify hostnames in the machine list with gethostbyname(3) before executing
B<cmd>.  A successful DNS lookup permits I<cmd> to proceed; otherwise the
child prints "bad hostname" on its STDOUT and exits.

=item B<-v,--verbose>

Print, on STDOUT, the B<cmd> issued to each I<host>, followed by its
output, if any.

=back

=head1 EXAMPLES

1)  % pexec -P 128 -m rp1-rp128 -t 5 --ssh uptime

Remotely execute (by ssh(1)) C<uptime>, in 128-way parallel, on rp1, rp2,
..., rp128, killing processes that do not run to completion in 5 seconds.
If B<-v> were specified, each host's output would be separated by the
execution line issued to that particular host.  If B<-p> were specified,
each host's output would be prefixed by its hostname from the machine list.

2)  % pexec -vPt 30 -m @every-host -o %host%.pub ssh-keyscan %host%

Retrieve, in 32-way (default) parallel, remote hosts' public rsa1 keys,
storing the result in %host%.pub, which is set individually for each
machine defined by netgroup @every-host.  Kill processes that have not
completed in 30 seconds.

3)  % pexec -vPt 10 -m @FC -s mailhost,@servers,^/tmp/lucky --rsh "/sbin/init 0"

Remotely halt (by rsh(1)), in 32-way (default) parallel, all hosts defined
by the netgroup "FC", skipping "mailhost", all hosts defined by the
netgroup "servers" and hosts listed in the file I</tmp/lucky>.  Kill
processes that have not completed in 10 seconds.  Here, the file
I</tmp/lucky> may look like:

    % cat /tmp/lucky
    # comment lines ignored
    ^/tmp/lucky     # file indirection ignored
    fe1             # whitespace to EOL chopped
    fe2:            # colon & whitespace to EOL chopped
    fe3-fe8         # ranges are expanded
    FEs@SU2         # netgroups are expanded

4a)  % pexec -t 60 -m n0-n1023 -P 6 --rsync --rsync-rsh "rsh -l root"
/net/scratch/data %host%:/tmp/.

4b)  % pexec -t 60 -m n0-n1023 -P 6 --rsync --rsync-rsh rsh
/net/scratch/data root@%host%:/tmp/.

4c)  % pexec -t 60 -m n0-n1023 -P 6 rsync -aq -e rsh /net/scratch/data
root@%host%:/tmp/.

Remote archive copy, by rsync(1), C</net/scratch/data> to C</tmp/data> of
n0, n1, ..., n1023.  Authentication between hosts will be accomplished by
rsh(1) access for the root user.  At any given time, there may be up to six
rsync(1) instances sourced from the execution host itself.  Examples 4a)
and 4b) permit up to 256 individual rsync(1) processes sourced by the
"leaves" of the execution tree whereas the general-case example 4c) permits
none.  Kill processes that do not run to completion in 60 seconds.

5)  % pexec -pP -m @compute --ping --ping-host %host%-man0:echo/icmp
rpower %host% cycle

Remote power cycle nodes defined by the compute netgroup predicated by the
successful echo/icmp ping to the host's man0 interface (e.g. a BMC device).

=head1 DIAGNOSTICS

B<pexec> exits with 0 on success.  On B<cmd> failure, the exit value will
be determined by the logical OR of all of the I<improper> statuses returned
by B<cmd> running on the machine list.  See B<--exit-success> for a
mechanism to influence what B<pexec> believes to be success/failure of
B<cmd>.

=head1 ENVIRONMENT

=over 6

=item B<PEXEC>

Take B<pexec> options from this environment variable, which is parsed
before the command line (and thereby overridden).

=back

=head1 FILES

F</etc/netgroup>

=head1 CAVEATS

1. When distributing a I<single> B<src> to B<host:dest>, it is infeasible for
B<pexec> to ascertain whether the destination is a I<file> or a
I<directory> name on the remote host; an important fact to know for the
"leaves" of the tree to source B<cmd> on other hosts in the machine list.
If B<host:dest> I<should be> a directory name, include a trailing slash
("/" or "/.") in its discription.  Omitting this, B<pexec> will attempt to
answer the question by investigating the execution host's filesystem
itself, however it is not at all required to look like the filesystems of
the machine list.  Failing all of the above, B<pexec> will treat B<dest> as
a I<file>name on the remote host.

2. Emperical data shows that rcp(1) and 'rsh(1) B<cmd>' do not exit with
non-zero status on failure of their execution.  The most robust of the
remote copy operations in this regard are rsync(1) and scp(1).

3. If you time out on a remote operation, the local process that transported you
will terminate but any successful remote execution may proceed!

=head1 REMOTE FILE COPY RESTRICTIONS

1. It is assumed that password-less authentication as required by B<cmd> will
succeed between any pair of hosts in the machine list for I<user>.  It is
also vacuously required that the execution host have the same privilege to
any host in the machine list, however the converse need not be true for
B<pexec> to succeed.

2. Filesystem uniformity must exist between all hosts in the machine list
with regard to B<dest>:  if B<dest> is a directory name on the filesystems
of some machines and not on others, B<pexec> will certainly fail.

3. B<pexec> does not check the validity any of the options specified by
B<--rcp-opts>, B<--scp-opts>, B<--rsync-opts> or
B<--rsync-rsh>; use with caution.

=head1 SEE ALSO

gethostbyname(3), netgroup(5), rsh(1), rcp(1),
rsync(1), ssh(1), scp(1)

=head1 AUTHOR

Daryl W. Grunau <dwg@lanl.gov>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 Daryl W. Grunau

Unless otherwise indicated, this information has been authored by an employee
or employees of the Los Alamos National Security, LLC (LANS), operator of the
Los Alamos National Laboratory under Contract No.  DE-AC52-06NA25396 with the
U.S. Department of Energy.  The U.S. Government has rights to use, reproduce,
and distribute this information. The public may copy and use this information
without charge, provided that this Notice and any statement of authorship are
reproduced on all copies. Neither the Government nor LANS makes any warranty,
express or implied, or assumes any liability or responsibility for the use of
this information.

This program has been approved for release from LANS by LA-CC Number 10-066,
being part of the HPC Operational Suite.

=cut
