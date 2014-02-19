pexec
=====

parallel command-execution OR file-copy acting on a number of hosts

pexec builds a machine list from command-line arguments on which an
arbitrary cmd is to be run.  Called in its most general form, pexec
achieves parallelism by overseeing a fixed number of fork(2)'d and
execvp(3)'d cmd processes marshalled by the host initiating the
operation (the execution host).  If the string "%host%" is part of cmd,
names from the machine list are substituted in its stead.

Alternatively specifying one of the remote file copy operations, pexec
fixes cmd appropriately and distributes src to the machine list's dest
in a tree-like fashion: on success (proper exit status), the
destination machine is placed on a work queue to potentially source a
future copy operation itself.  Any source machine and the "root" of the
tree will always be returned to the work queue upon completion of their
subtasks (but see --parallel below for alternate behavior).  Note here
that the string "%host%" is a mandatory part of the dest description.

The output of cmd on each machine is printed to the execution host's
STDOUT by default (but see --output below for alternate behavior).
pexec will catch the following signals for special processing: INT
(^C), QUIT (^\), TERM and TSTP (^Z).  pexec will elevate INT and TERM
signals it receives to KILL any children it has spawned, then terminate
itself immediately.  Signalling QUIT (usu. ^\) will KILL any children
that have already been spawned by pexec, however execution of the
parent proceeds if there are any hosts remaining in the machine list
that have not had the opportunity to exec something!  Issuing TSTP (^Z)
will print to STDERR the list of outstanding processes pexec has
spawned (or plans to) that await completion, then continue.
