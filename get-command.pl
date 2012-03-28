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
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--command") {
		$cmd = shift(@ARGV);
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage();
		}
	}

# Find the command
$cmd || &usage("Missing --command parameter");
$cmd .= ".pl" if ($cmd !~ /\.pl$/);
foreach $dir ($module_root_directory,
	      map { &module_root_directory($_) } @plugins) {
	if (-r "$dir/$cmd") {
		$cmdpath = "$dir/$cmd";
		$cmddir = $dir;
		last;
		}
	}
$cmdpath || &usage("API command $cmd was not found");

# Extract description
$src = &read_file_contents($cmdpath);
if ($src =~ /=head1\s+(.*)\n\n(.*)\n/) {
	$desc = $2;
	}

# Run with --help to get command line flags
&clean_environment();
$ENV{'WEBMIN_CONFIG'} = $config_directory;
$out = &backquote_command("$cmdpath --help 2>&1 </dev/null");
&reset_environment();
foreach my $l (split(/\r?\n/, $out)) {
	$l =~ s/^(virtualmin|cloudmin)\s+(\S+)//;	# strip command
	last if (@args && $l !~ /\S/);			# end of help
	next if ($l !~ /--/ || $l =~ /--help/);
	push(@args, $l);
	}

# Parse flags string
$args = join(" ", @args);
while($args =~ /\S/) {
	$args =~ s/^\s*\|\s*//;
	if ($args =~ /^\s*\[([^\]]+)\](\*|\+|)(.*)$/) {
		# One or more optional args
		$opt = 1;
		$flags = $1;
		$repeat = $2;
		$args = $3;
		}
	elsif ($args =~ /^\s*\<([^\>]+)\>(\*|\+|)(.*)$/) {
		# One or more required args
		$opt = 0;
		$flags = $1;
		$repeat = $2;
		$args = $3;
		}
	elsif ($args =~ /^\s*(\-\-\S+\s+"[^"]+")(.*)$/) {
		# One arg with quoted parameter
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
		if ($flags =~ /^\s*\-\-(\S+)\s+"([^"]+)"(.*)$/ ||
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

