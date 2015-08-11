# Functions for accessing files and running commands as a domain owner

# has_domain_user(&domain)
# Returns 1 if some domain has a Unix user
sub has_domain_user
{
my ($d) = @_;
if ($d->{'parent'}) {
        $d = &get_domain($d->{'parent'});
        }
return 0 if (!$d->{'unix'});
my @uinfo = getpwnam($d->{'user'});
return scalar(@uinfo) ? 1 : 0;
}

# switch_to_domain_user(&domain)
# Changes the current UID and GID to that of the domain's unix user
sub switch_to_domain_user
{
my ($d) = @_;
if ($d->{'parent'}) {
	$d = &get_domain($d->{'parent'});
	}
return 0 if (!$d->{'unix'});	# Doesn't have a user
if (defined(&switch_to_unix_user)) {
	# Use new Webmin function that takes care of platform issues
	&switch_to_unix_user([ $d->{'user'}, undef, $d->{'uid'},
			       $d->{'ugid'} ]);
	}
else {
	# DIY
	($(, $)) = ( $d->{'ugid'},
		     "$d->{'ugid'} ".join(" ", $d->{'ugid'},
					 &other_groups($d->{'user'})) );
	($<, $>) = ( $d->{'uid'}, $d->{'uid'} );
	}
$ENV{'USER'} = $ENV{'LOGNAME'} = $d->{'user'};
$ENV{'HOME'} = $d->{'home'};
}

# run_as_domain_user(&domain, command, background, [never-su])
# Runs some command as the owner of a virtual server, and returns the output
sub run_as_domain_user
{
local ($d, $cmd, $bg, $nosu) = @_;
if ($d->{'parent'}) {
	$d = &get_domain($d->{'parent'});
	}

# Set a reasonable environment for the command
local %OLDENV = %ENV;
$ENV{'HOME'} = $uinfo[7];
$ENV{'USER'} = $uinfo[0];
$ENV{'LOGNAME'} = $uinfo[0];

&foreign_require("proc", "proc-lib.pl");
local @uinfo = getpwnam($d->{'user'});
local @rv;
if (($uinfo[8] =~ /\/(sh|bash|tcsh|csh)$/ ||
     $gconfig{'os_type'} =~ /-linux$/) && !$nosu) {
	# Usable shell .. use su
	local $cmd = &command_as_user($d->{'user'}, 0, $cmd);
	if ($bg) {
		# No status available
		&system_logged("$cmd &");
		@rv = ( undef, 0 );
		}
	else {
		local $out = &backquote_logged($cmd);
		@rv = ( $out, $? );
		}
	}
else {
	# Need to run ourselves
	local $temp = &transname();
	open(TEMP, ">$temp");
	&proc::safe_process_exec_logged($cmd, $d->{'uid'}, $d->{'ugid'},\*TEMP);
	local $ex = $?;
	local $out;
	close(TEMP);
	local $_;
	open(TEMP, $temp);
	while(<TEMP>) {
		$out .= $_;
		}
	close(TEMP);
	unlink($temp);
	@rv = ( $out, $ex );
	}

# Clean up the environment
$ENV{'HOME'} = $OLDENV{'HOME'};
$ENV{'USER'} = $OLDENV{'USER'};
$ENV{'LOGNAME'} = $OLDENV{'LOGNAME'};
return wantarray ? @rv : $rv[0];
}

# make_dir_as_domain_user(&domain, dir, permissions, recursive?)
# Creates a directory, with mkdir run as the domain owner. Returns 1 on success
# or 0 on failure.
sub make_dir_as_domain_user
{
my ($d, $dir, $perms, $recur) = @_;
return 1 if (&is_readonly_mode());
local $cmd = "mkdir ".($recur ? "-p " : "").quotemeta($dir)." 2>&1";;
if ($perms) {
	$cmd .= " && chmod ".sprintf("%o", $perms & 07777)." ".
			     quotemeta($dir)." 2>&1";;
	}
local ($out, $ex) = &run_as_domain_user($d, $cmd);
return $ex ? 0 : 1;
}

# unlink_file_as_domain_user(&domain, file, ...)
# Deletes some files or directories, as the domain owner
sub unlink_file_as_domain_user
{
my ($d, @files) = @_;
return 1 if (&is_readonly_mode());
local $cmd = "rm -rf ".join(" ", map { quotemeta($_) } @files)." 2>&1";
local ($out, $ex) = &run_as_domain_user($d, $cmd);
return $ex ? 0 : 1;
}

# unlink_logged_as_domain_user(&domain, file, ...)
# Like unlink_file_as_domain_user, but locks the file to log the change
sub unlink_logged_as_domain_user
{
my ($d, @files) = @_;
my %locked;
foreach my $f (@file) {
	if (!&test_lock($f)) {
		&lock_file($f);
		$locked{$f} = 1;
		}
	}
my $rv = &unlink_file_as_domain_user($d, @files);
foreach my $f (@files) {
	if ($locked{$f}) {
		&unlock_file($f);
		}
	}
return $rv;
}

# symlink_file_as_domain_user(&domain, src, dest)
# Creates a symbolic link, using ln -s run as the domain owner
sub symlink_file_as_domain_user
{
my ($d, $src, $dest) = @_;
return 1 if (&is_readonly_mode());
local $cmd = "ln -s ".quotemeta($src)." ".quotemeta($dest)." 2>&1";
local ($out, $ex) = &run_as_domain_user($d, $cmd);
return $ex ? 0 : 1;
}

# symlink_logged_as_domain_user(&domain, src, dest)
sub symlink_logged_as_domain_user
{
my ($d, $src, $dest) = @_;
&lock_file($dest);
my $rv = &symlink_file_as_domain_user($d, $src, $dest);
&unlock_file($dest);
return $rv;
}

# link_file_as_domain_user(&domain, src, dest)
# Creates a hard link, using ln run as the domain owner
sub link_file_as_domain_user
{
my ($d, $src, $dest) = @_;
return 1 if (&is_readonly_mode());
local $cmd = "ln ".quotemeta($src)." ".quotemeta($dest)." 2>&1";
local ($out, $ex) = &run_as_domain_user($d, $cmd);
return $ex ? 0 : 1;
}

# open_tempfile_as_domain_user(&domain, handle, file, [no-error],
# 			       [no-tempfile], [safe?])
# Like the Webmin open_tempfile function, but in a sub-process that runs as
# the domain owner.
sub open_tempfile_as_domain_user
{
my ($d, $fh, $file, $noerror, $notemp, $safe) = @_;
$fh = (caller(0))[0]."::".$fh;
my $realfile = $file;
$realfile =~ s/^[> ]*//;
while(-l $realfile) {
	# Open the link target instead
	$realfile = &resolve_links($realfile);
	}
if (-d $realfile) {
	if ($noerror) { return 0; }
	else { &error("Cannot write to directory $realfile"); }
	}

if (&is_readonly_mode() && $file =~ />/ && !$safe) {
	# Read-only mode .. veto all writes
	return open($fh, ">$null_file");
	}

# Get the temp file now, before forking
my $tempfile;
if ($file =~ /^>\s*(([a-zA-Z]:)?\/.*)$/ && !$notemp) {
	$tempfile = &open_tempfile($realfile);
	}

# Create pipes for sending in data and reading back error
my ($writein, $writeout) = ($fh, "writeout".(++$main::open_tempfile_count));
my ($readin, $readout) = ("readin".(++$main::open_tempfile_count),
			  "readout".(++$main::open_tempfile_count));
pipe($writeout, $writein);
pipe($readout, $readin);

# Fork the process we will use for writing
my $pid = fork();
if ($pid < 0) {
	if ($noerror) { return 0; }
	else { &error("Failed to fork sub-process for writing : $!"); }
	}
if (!$pid) {
	# Close file handles
	untie(*STDIN);
	untie(*STDOUT);
	untie(*STDERR);
	close(STDIN);
	close(STDOUT);
	close(STDERR);
	close($writein);
	close($readout);
	my $oldsel = select($readin); $| = 1; select($oldsel);

	# Open the temp file and start writing
	&switch_to_domain_user($d);
	if ($file =~ /^>\s*(([a-zA-Z]:)?\/.*)$/ && !$notemp) {
		# Writing to a file, via a tempfile
		my $ex = open(FILE, ">$tempfile");
		if (!$ex) {
			print $readin "Failed to open $tempfile : $!\n";
			exit(1);
			}
		}
	elsif ($file =~ /^>\s*(([a-zA-Z]:)?\/.*)$/ && $notemp) {
		# Writing directly
		my $ex = open(FILE, ">$realfile");
		if (!$ex) {
			print $readin "Failed to open $realfile : $!\n";
			exit(1);
			}
		}
	elsif ($file =~ /^>>\s*(([a-zA-Z]:)?\/.*)$/) {
		# Appending to a file
		my $ex = open(FILE, ">>$realfile");
		if (!$ex) {
			print $readin "Failed to open $realfile : $!\n";
			exit(1);
			}
		}
	else {
		print $readin "Unknown file mode $file\n";
		exit(1);
		}
	print $readin "OK\n";	# Signal OK
	$SIG{'PIPE'} = 'ignore';	# Write errors detected by print
	while(<$writeout>) {
		my $rv = (print FILE $_);
		if (!$rv) {
			print $readin "Write to $realfile failed : $!\n";
			exit(2);
			}
		}
	my $ex = close(FILE);
	if ($ex) {
		exit(0);
		}
	else {
		print $readin "Close of $realfile failed : $!\n";
		exit(3);
		}
	}
close($writeout);
close($readin);

# Check if the file was opened OK
my $oldsel = select($readout); $| = 1; select($oldsel);
my $err = <$readout>;
chop($err);
if ($err ne 'OK') {
	waitpid($pid, 0);
	if ($noerror) { return 0; }
	else { &error($err || "Unknown error in sub-process"); }
	}

$main::open_temphandles{$fh} = $realfile;
$main::open_tempfile_as_domain_user_pid{$fh} = $pid;
$main::open_tempfile_readout{$fh} = $readout;
$main::open_tempfile_noerror{$fh} = $noerror;
return 1;
}

# close_tempfile_as_domain_user(&domain, fh)
# Like close_tempfile, but does the final write as the domain owner
sub close_tempfile_as_domain_user
{
my ($d, $fh) = @_;
$fh = (caller(0))[0]."::".$fh;
my $pid = $main::open_tempfile_as_domain_user_pid{$fh};
my $readout = $main::open_tempfile_readout{$fh};
my $realfile = $main::open_temphandles{$fh};
my $tempfile = $main::open_tempfiles{$realfile};
my ($rv, $err);
if ($pid) {
	# Writing was done in a sub-process .. wait for it to exit
	close($fh);
	waitpid($pid, 0);
	my $ex = $?;
	$err = <$readout>;
	close($readout);

	# Rename over temp file if needed
	if ($tempfile && !$ex) {
		my @st = stat($realfile);
		&rename_as_domain_user($d, $tempfile, $realfile);
		if (@st) {
			&set_permissions_as_domain_user($d, $st[2], $realfile);
			}
		}
	$rv = !$ex;
	}
else {
	# Just close the file
	$rv = close($fh);
	}
delete($main::open_tempfile_as_domain_user_pid{$fh});
delete($main::open_tempfile_readout{$fh});
delete($main::open_temphandles{$fh});
return $rv;
}

# open_readfile_as_domain_user(&domain, handle, file)
# Open a file for reading, using a sub-process run as the domain owner
sub open_readfile_as_domain_user
{
my ($d, $fh, $file) = @_;
my ($readin, $readout) = ("readin".(++$main::open_tempfile_count), $fh);
pipe($readout, $readin);
my $pid = fork();
if ($pid < 0) {
	return 0;
	}
if (!$pid) {
	# Close file handles
	untie(*STDIN);
	untie(*STDOUT);
	untie(*STDERR);
	close(STDIN);
	close(STDOUT);
	close(STDERR);
	close($readout);
	my $oldsel = select($readin); $| = 1; select($oldsel);

	# Open the file and start reading
	&switch_to_domain_user($d);
	my $ok = open(FILE, $file);
	if (!$ok) {
		print $readin "Failed to open $file : $!\n";
		exit(1);
		}
	print $readin "OK\n";   # Signal OK
	while(<FILE>) {
		print $readin $_;
		}
	close(FILE);
	exit(0);
	}
close($readin);
my $oldsel = select($readout); $| = 1; select($oldsel);
my $err = <$readout>;
chop($err);
if ($err ne 'OK') {
	waitpid($pid, 0);
	return 0;
        }

$main::open_readfile_as_domain_user_pid{$fh} = $pid;
return 1;
}

# close_readfile_as_domain_user(&domain, handle)
# Close a file opened by open_readfile_as_domain_user
sub close_readfile_as_domain_user
{
my ($d, $fh) = @_;
my $pid = $main::open_readfile_as_domain_user_pid{$fh};
if ($pid) {
	close($fh);
	kill('KILL', $pid);
	waitpid($pid, 0);
	}
delete($main::open_readfile_as_domain_user_pid{$fh});
return 1;
}

# read_file_lines_as_domain_user(&domain, file, [readonly])
# Like Webmin's read_file_lines function, but opens the file as a domain owner
sub read_file_lines_as_domain_user
{
my ($d, $file, $ro) = @_;
if (!$file) {
	my ($package, $filename, $line) = caller;
	&error("Missing file to read at ${package}::${filename} line $line\n");
	}
if (!$main::file_cache{$file}) {
        my (@lines, $eol);
	local $_;
        &open_readfile_as_domain_user($d, READFILE, $file);
        while(<READFILE>) {
		if (!$eol) {
			$eol = /\r\n$/ ? "\r\n" : "\n";
			}
                tr/\r\n//d;
                push(@lines, $_);
                }
        &close_readfile_as_domain_user($d, READFILE);
        $main::file_cache{$file} = \@lines;
	$main::file_cache_noflush{$file} = $ro;
	$main::file_cache_eol{$file} = $eol || "\n";
        }
else {
	# Make read-write if currently readonly
	if (!$ro) {
		$main::file_cache_noflush{$file} = 0;
		}
	}
return $main::file_cache{$file};
}

# flush_file_lines_as_domain_user(&domain, file, eol)
# Write out a file read into memory by read_file_lines_as_domain_user
sub flush_file_lines_as_domain_user
{
my ($d, $file, $eol) = @_;
my ($package, $filename, $line) = caller;
if (!$file) {
	&error("Missing file to flush at ${package}::${filename} line $line");
	}
if (!$main::file_cache{$file}) {
	&error("File $file was not opened by read_file_lines_as_domain_user ".
	       "at ${package}::${filename} line $line");
	}
$eol ||= $main::file_cache_eol{$file} || "\n";
if (!$main::file_cache_noflush{$file}) {
	&open_tempfile_as_domain_user($d, FLUSHFILE, ">$file");
	foreach my $line (@{$main::file_cache{$file}}) {
		(print FLUSHFILE $line,$eol) ||
			&error(&text("efilewrite", $file, $!));
		}
	&close_tempfile_as_domain_user($d, FLUSHFILE);
	}
delete($main::file_cache{$file});
delete($main::file_cache_noflush{$file});
}

# rename_as_domain_user(&domain, oldfile, newfile)
# Rename a file, using mv run as the domain owner
sub rename_as_domain_user
{
my ($d, $oldfile, $newfile) = @_;
return 1 if (&is_readonly_mode());
my $cmd = "mv -f ".quotemeta($oldfile)." ".quotemeta($newfile)." 2>&1";
my ($out, $ex) = &run_as_domain_user($d, $cmd);
return $ex ? 0 : 1;
}

# set_permissions_as_domain_user(&domain, perms, file, ...)
# Set permissions on some file, using chmod run as the domain owner
sub set_permissions_as_domain_user
{
my ($d, $perms, @files) = @_;
return 1 if (&is_readonly_mode());
my $cmd = "chmod ".sprintf("%o", $perms & 07777)." ".
	  join(" ", map { quotemeta($_) } @files)." 2>&1";
my ($out, $ex) = &run_as_domain_user($d, $cmd);
return $ex ? 0 : 1;
}

# execute_as_domain_user(&domain, &code)
# Run some code reference in a sub-process, as the domain's user. If the
# function fails (due to calling error), this process will exit too.
sub execute_as_domain_user
{
my ($d, $code) = @_;
my $pid = fork();
if (!$pid) {
	&switch_to_domain_user($d);
	&$code();
	exit(0);
	}
elsif ($pid < 0) {
	&error("Fork for execute_as_domain_user failed : $!");
	}
else {
	waitpid($pid, 0);
	if ($?) {
		exit($? / 256);
		}
	}
}

# write_as_domain_user(&domain, &code)
# Runs some code with the effective UID and GID set to that of the domain user,
# so that file IO is locked down. Sets it back afterwards.
sub write_as_domain_user
{
my ($d, $code) = @_;
if ($d->{'parent'}) {
	$d = &get_domain($d->{'parent'});
	}
if ($d->{'unix'}) {
	my $gid = $d->{'ugid'} || $d->{'gid'};
	$) = $gid." ".join(" ", $gid, &other_groups($d->{'user'}));
	$> = $d->{'uid'};
	}
my @rv;
eval {
	local $main::error_must_die = 1;
	@rv = &$code();
	};
my $err = $@;
if ($d->{'unix'}) {
	$) = 0;
	$> = 0;
	}
if ($err) {
	$err =~ s/\s+at\s+(\/\S+)\s+line\s+(\d+)\.?//;
	&error($err);
	}
return wantarray ? @rv : $rv[0];
}

# write_as_mailbox_user(&user, &code)
# Runs some code with the effective UID and GID set to that of a mailbox user,
# so that file IO is locked down. Sets it back afterwards.
sub write_as_mailbox_user
{
my ($user, $code) = @_;
$) = $user->{'gid'}." ".join(" ", $user->{'gid'},
				  &other_groups($user->{'user'}));
$> = $user->{'uid'};
my @rv;
eval {
	local $main::error_must_die = 1;
	@rv = &$code();
	};
my $err = $@;
$) = 0;
$> = 0;
if ($err) {
	$err =~ s/\s+at\s+(\/\S+)\s+line\s+(\d+)\.?//;
	&error($err);
	}
return wantarray ? @rv : $rv[0];
}

# copy_source_dest_as_domain_user(&domain, source, dest)
# Copy a file or directory, with commands run as a domain owner
sub copy_source_dest_as_domain_user
{
my ($d, $src, $dst) = @_;
return (1, undef) if (&is_readonly_mode());
my $ok = 1;
my $err;
if (-d $src) {
	# A directory .. need to copy with tar command
	my @st = stat($src);
	&unlink_file_as_domain_user($d, $dst);
	&make_dir_as_domain_user($d, $dst, $st[2]);
	my ($out, $ex) = &run_as_domain_user($d,
		"(cd ".quotemeta($src)." && ".
		&make_tar_command("cf", "-", ".").
		" | (cd ".quotemeta($dst)." && ".
		&make_tar_command("xf", "-").")) 2>&1");
	if ($ex) {
		$ok = 0;
		$err = $out;
		}
	}
else {
	# Can just copy with cp
	my ($out, $ex) = &run_as_domain_user($d,
		"cp -p ".quotemeta($src)." ".quotemeta($dst)." 2>&1");
	if ($ex && $out !~ /failed to preserve ownership/i) {
		$ok = 0;
		$err = $out;
		}
	}
return wantarray ? ($ok, $err) : $ok;
}

# copy_write_as_domain_user(&domain, source, dest)
# Copy a file, with only the writing done as the domain user
sub copy_write_as_domain_user
{
my ($d, $src, $dst) = @_;
return (1, undef) if (&is_readonly_mode());
my ($ok, $err);
$ok = 1;
if (!open(SOURCEFILE, $src)) {
	$ok = 0;
	$err = $!;
	}
else {
	if (!&open_tempfile_as_domain_user($d, DESTFILE, ">$dst", 1, 1)) {
		$ok = 0;
		$err = $!;
		}
	else {
		eval {
			local $main::error_must_die = 1;
			while(<SOURCEFILE>) {
				&print_tempfile(DESTFILE, $_);
				}
			};
		if ($@) {
			$ok = 0;
			$err = $@;
			}
		close(SOURCEFILE);
		&close_tempfile_as_domain_user($d, DESTFILE);
		}
	}
return wantarray ? ($ok, $err) : $ok;
}

# safe_domain_file(&domain, file)
# Returns 1 if some file is safe for a given domain to manage.
# Currently just prevents symlinks
sub safe_domain_file
{
my ($d, $file) = @_;
my $realfile = &resolve_links($file);
return $realfile eq $file || &same_file($realfile, $file);
}

# read_file_contents_as_domain_user(&domain, file)
# Returns the full contents of some file, read as the domain owner
sub read_file_contents_as_domain_user
{
my ($d, $file) = @_;
&open_readfile_as_domain_user($d, FILE, $file) || return undef;
local $/ = undef;
my $rv = <FILE>;
&close_readfile_as_domain_user($d, FILE);
return $rv;
}

1;

