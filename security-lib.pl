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
local $cmd = "mkdir ".($recur ? "-p " : "")."quotemeta($dir);
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

sub open_tempfile_as_domain_user
{
}

sub close_tempfile_as_domain_user
{
}

1;

