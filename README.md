pexec
=====

parallel execution command, on host or across a cluster, run commands, copy, etc

pexec builds a machine list from command-line arguments on which cmd is
to be run.  If the string %host% is part of cmd, names from the machine
list are substituted in its stead.  Output of cmd on each machine is
printed to the execution host's STDOUT.
