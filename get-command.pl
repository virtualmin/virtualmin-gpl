#!/usr/local/bin/perl

=head1 get-command.pl

Show information about some command.

This command outputs information about another API command, such as its
supported command-line parameters. It is designed for use by developers
writing their own API on top of the Virtualmin remote API.

=cut

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*)\/[^\/]+$/) {
		chdir($pwd = $1);
		}
	else {
		chop($pwd = `pwd`);
		}
	$0 = "$pwd/get-command.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "get-command.pl must be run as root";
	}

# Parse command-line args
my $short = 1;
&parse_common_cli_flags(\@ARGV);
while(@ARGV > 0) {
	my $a = shift(@ARGV);
	if ($a eq "--command") {
		$cmd = shift(@ARGV);
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Find the command
$cmd || &usage("Missing --command parameter");
$cmd =~ s/\.pl$//;
# Do not spawn a terminal-only command to fetch its help over HTTP.
&is_api_account_command($cmd) && &is_remote_api_request() &&
	&usage("API account management is available only to root on the command line");
!&master_admin() && $cmd !~ /^[a-z0-9_\-]+$/i &&
	&usage("API command $cmd was not found");
&require_remote_api_command();
!&master_admin() && !&can_remote_as_user($cmd) &&
	&usage("API command $cmd was not found");
if (my $msg = &api_command_unavailable_message($cmd)) {
	print "$msg\n";
	exit(1);
	}
$cmd .= ".pl" if ($cmd !~ /\.pl$/);
if (&is_api_access_user()) {
	# Use the authorized provider, including commands stored only under pro/.
	my $entry = &get_api_access_command($cmd);
	$cmdpath = $entry->{'path'};
	}
else {
	# Keep the existing lookup order for ordinary accounts.
	foreach $dir ($module_root_directory,
		      map { &module_root_directory($_) } @plugins) {
		if (-r "$dir/$cmd") {
			# Keep the first readable script for ordinary callers.
			$cmdpath = "$dir/$cmd";
			$cmddir = $dir;
			last;
			}
		}
	}
$cmdpath || &usage("API command $cmd was not found");

# Extract description
$src = &read_file_contents($cmdpath);
if ($src =~ /=head1\s+(.*)\n\n(.*)\n/) {
	$desc = $2;
	}

# Run with --help to get command line flags
if (&is_api_access_user()) {
	# Retain the caller's policy, including the selected command provider.
	my $entry = &prepare_api_access_command($cmd, [ '--help' ]);
	pipe(my $read, my $write) || &usage("Cannot open command pipe: $!");
	my $pid = &execute_webmin_script($entry->{'path'},
		$entry->{'provider'}, [ '--help' ], $write);
	# Collect help from the authorized child for the metadata parser below.
	$out = join('', <$read>);
	close($read);
	waitpid($pid, 0);
	}
else {
# Preserve standalone help execution for ordinary administrator and owner calls.
&clean_environment();
$ENV{'WEBMIN_CONFIG'} = $config_directory;
$out = &backquote_command(quotemeta($cmdpath)." --help 2>&1 </dev/null");
&reset_environment();
}
@helpargs = ( );
foreach my $l (split(/\r?\n/, $out)) {
	$l =~ s/^(virtualmin|cloudmin)\s+(\S+)//;	# strip command
	last if (@helpargs && $l !~ /\S/);		# end of help
	next if ($l !~ /--/ || $l =~ /--help/);
	push(@helpargs, $l);
	}

# Parse flags string
$args = join(" ", @helpargs);
while($args =~ /\S/) {
	$args =~ s/^\s*\|\s*//;
	if ($args =~ /^\s*\[([^\]]+)\](\*|\+|)(.*)$/) {
		# One or more optional args
		$opt = 1;
		$flags = $1;
		$repeat = $2;
		$args = $3;
		}
	elsif ($args =~ /^\s*\<((?:[^<>]|<[^<>]*>)+)\>(\*|\+|)(.*)$/) {
		# One or more required args, which may hold <value> placeholders
		$opt = 0;
		$flags = $1;
		$repeat = $2;
		$args = $3;
		}
	elsif ($args =~ /^\s*(\-\-\S+\s+"[^"]+")(.*)$/ ||
	       $args =~ /^\s*(\-\-\S+\s+<(?!\s*--)[^<>]+>)(.*)$/) {
		# One arg with a quoted or bracketed parameter, not a group
		$opt = 0;
		$flags = $1;
		$repeat = "";
		$args = $2;
		}
	elsif ($args =~ /^\s*(\-\-\S+\s+[^\[\<\-\s]\S+)(.*)$/) {
		# One arg with non-quoted parameter
		$opt = 0;
		$flags = $1;
		$repeat = "";
		$args = $2;
		}
	elsif ($args =~ /^\s*(\-\-\S+)(.*)$/) {
		# Binary arg
		$opt = 0;
		$flags = $1;
		$repeat = "";
		$args = $2;
		}
	else {
		&usage("Cannot parse args $args");
		}

	# Split list of flags
	while($flags =~ /\S/) {
		$flags =~ s/^\s*\|\s*//;
		if ($flags =~ /^\s*\-\-(\S+)\s+<(?!\s*--)([^<>]+)>(.*)$/ ||
		    $flags =~ /^\s*\-\-(\S+)\s+"([^"]+)"(.*)$/ ||
		    $flags =~ /^\s*\-\-(\S+)\s+([^\[\<\-\s]\S+)(.*)$/) {
			push(@rv, { 'name' => $1,
				    'binary' => 0,
				    'value' => $2,
				    'opt' => $opt,
				    'repeat' => $repeat });
			$flags = $3;
			}
		elsif ($flags =~ /^\s*\-\-(\S+)(.*)$/) {
			push(@rv, { 'name' => $1,
				    'binary' => 1,
				    'opt' => $opt,
				    'repeat' => $repeat });
			$flags = $2;
			}
		else {
			&usage("Cannot parse flag $flags");
			}
		}
	}

# Show params
print "Description: $desc\n" if ($desc);
foreach $a (@rv) {
	print $a->{'name'},"\n";
	print "    Binary: ",($a->{'binary'} ? "Yes" : "No"),"\n";
	print "    Value: $a->{'value'}\n" if (!$a->{'binary'});
	print "    Optional: ",($a->{'opt'} ? "Yes" : "No"),"\n";
	print "    Repeats: ",($a->{'repeat'} eq '+' ? "1 or more times" :
			       $a->{'repeat'} eq '*' ? "0 or more times" :
						       "No"),"\n";
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Show information about some command.\n";
print "\n";
print "virtualmin get-command --command name\n";
exit(1);
}

