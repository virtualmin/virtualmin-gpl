# Functions for accessing files and running commands as a domain owner

# switch_to_domain_user(&domain)
# Changes the current UID and GID to that of the domain's unix user
sub switch_to_domain_user
{
if (defined(&switch_to_unix_user)) {
	# Use new Webmin function that takes care of platform issues
	&switch_to_unix_user([ $_[0]->{'user'}, undef, $_[0]->{'uid'},
			       $_[0]->{'ugid'} ]);
	}
else {
	# DIY
	($(, $)) = ( $_[0]->{'ugid'},
		     "$_[0]->{'ugid'} ".join(" ", $_[0]->{'ugid'},
					 &other_groups($_[0]->{'user'})) );
	($<, $>) = ( $_[0]->{'uid'}, $_[0]->{'uid'} );
	}
$ENV{'USER'} = $ENV{'LOGNAME'} = $_[0]->{'user'};
$ENV{'HOME'} = $_[0]->{'home'};
}

# run_as_domain_user(&domain, command, background, [never-su])
# Runs some command as the owner of a virtual server, and returns the output
sub run_as_domain_user
{
local ($d, $cmd, $bg, $nosu) = @_;
&foreign_require("proc", "proc-lib.pl");
local @uinfo = getpwnam($_[0]->{'user'});
if (($uinfo[8] =~ /\/(sh|bash|tcsh|csh)$/ ||
     $gconfig{'os_type'} =~ /-linux$/) && !$nosu) {
	# Usable shell .. use su
	local $cmd = &command_as_user($_[0]->{'user'}, 0, $_[1]);
	if ($bg) {
		# No status available
		&system_logged("$cmd &");
		return wantarray ? (undef, 0) : undef;
		}
	else {
		local $out = &backquote_logged($cmd);
		return wantarray ? ($out, $?) : $out;
		}
	}
else {
	# Need to run ourselves
	local $temp = &transname();
	open(TEMP, ">$temp");
	&proc::safe_process_exec_logged($_[1], $_[0]->{'uid'}, $_[0]->{'ugid'}, \*TEMP);
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
	return wantarray ? ($out, $ex) : $out;
	}
}

# make_dir_as_domain_user(&domain, dir, permissions, recursive?)
# Creates a directory, with mkdir run as the domain owner. Returns 1 on success
# or 0 on failure.
sub make_dir_as_domain_user
{
my ($d, $dir, $perms, $recur) = @_;
if (&is_readonly_mode()) {
	print STDERR "Vetoing directory $dir\n";
	return 1;
	}
local $cmd = "mkdir ".($recur ? "-p " : "").quotemeta($dir);
if ($perms) {
	$cmd .= " && chmod ".quotemeta($perms)." ".quotemeta($dir);
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
local $cmd = "rm -rf ".join(" ", map { quotemeta($_) } @files);
local ($out, $ex) = &run_as_domain_user($d, $cmd);
return $ex ? 0 : 1;
}

# symlink_file_as_domain_user(&domain, src, dest)
# Creates a symbolic link, using ln -s run as the domain owner
sub symlink_file_as_domain_user
{
my ($d, $src, $dest) = @_;
return 1 if (&is_readonly_mode());
local $cmd = "ln -s ".quotemeta($src)." ".quotemeta($dest);
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
my $tempfile = &open_tempfile($file);

# Create pipes for sending in data and reading back error
my ($writein, $writeout) = ($fh, "writeout".(++$main::open_tempfile_count));
my ($readin, $readout) = ("readin".(++$main::open_tempfile_count),
			  "readout".(++$main::open_tempfile_count));
pipe($writeout, $writein);
pipe($readout, $readin);

# Fork the process we will use for writing
my $pid = fork();
if (!$pid) {
	# Close file handles
	untie(*STDIN);
	untie(*STDOUT);
	untie(*STDERR);
	close(STDIN);
	close(STDOUT);
	close(STDERR);

	# Open the temp file and start writing
	&switch_to_domain_user($d);
	if ($file =~ /^>\s*(([a-zA-Z]:)?\/.*)$/ && !$notemp) {
		# Writing to a file, via a tempfile
		}
	elsif ($file =~ /^>\s*(([a-zA-Z]:)?\/.*)$/ && $notemp) {
		# Writing directly
		}
	elsif ($file =~ /^>>\s*(([a-zA-Z]:)?\/.*)$/) {
		# Appending to a file
		}
	# XXX open and write what we get from writeout
	# XXX if any error, send back to readin and exit(1)
	# XXX stop if no more input

	exit(0);
	}
$open_tempfile_as_domain_user_pid{$fh} = $pid;
}

# close_tempfile_as_domain_user(&domain, fh)
# Like close_tempfile, but does the final write as the domain owner
sub close_tempfile_as_domain_user
{
my ($d, $fh) = @_;
delete($open_tempfile_as_domain_user_pid{$fh});
}

sub open_readfile_as_domain_user
{
# XXX
}

sub close_readfile_as_domain_user
{
# XXX
}

sub read_file_lines_as_domain_user
{
# XXX
}

sub flush_file_lines_as_domain_user
{
# XXX
}

1;

