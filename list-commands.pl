#!/usr/local/bin/perl

=head1 list-commands.pl

Lists API scripts available

This command lists all API commands available, categorized by type and
with a brief summary of each. It is used to produce the output from the
Virtualmin C<--help> command. By default the output is in a human-readable format,
but you can switch to a more parsable format with the C<--multiline> flag.

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
	$0 = "$pwd/list-features.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-commands.pl must be run as root";
	}

# Parse command-line args
my $short = 1;
&parse_common_cli_flags(\@ARGV);
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--short") {
		$short = 1;
		}
	elsif ($a eq "--long") {
		$short = 0;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Work out the max command length, for formatting
my $maxlen = 0;
foreach my $c (&list_api_categories()) {
	my ($cname, @cglobs) = @$c;
	foreach my $cmd (map { glob($_) } @cglobs) {
		my $scmd = $cmd;
		$scmd =~ s/\.pl$// if ($short);
		$maxlen = length($scmd) if (length($scmd) > $maxlen);
		}
	}

# Go through the categories
my @skips = &list_api_skip_scripts();
my %cdescs = &list_api_category_descs();
my %done;
my $fmt = "\%-${maxlen}.${maxlen}s \%s\n";
foreach my $c (&list_api_categories()) {
	my ($cname, @cglobs) = @$c;
	@cglobs = map { my $g = $_; ($g, "pro/$g", map { "$root_directory/$_/$g" } @plugins) } @cglobs;
	my @cmds = map { glob($_) } @cglobs;

	# Print a line for each command
	my $donehead = 0;
	foreach my $cmd (@cmds) {
		next if (-l $cmd);
		next if (&indexof($cmd, @skips) >= 0);
		my $spellcmd = $cmd;
		$spellcmd =~ s/licence/license/g;
		next if ($done{$spellcmd}++);
		my $src = &read_file_contents($cmd);
		next if ($src !~ /=head1\s+(.*)\n\n(.*)\n/);
		my $desc = $2;
		my $scmd = $cmd;
		$scmd =~ s/^.*\///;
		$scmd =~ s/\.pl$// if ($short);
		if ($multiline) {
			# Show a block for the command
			print $scmd,"\n";
			print "    Description: $desc\n";
			print "    Category: $cname\n";
			}
		elsif ($nameonly) {
			# Just command name
			print $scmd,"\n";
			}
		else {
			# Just one line, maybe wrapped
			my $wrap;
			while (length($desc) + $maxlen > 79) {
				# Line is too long - wrap it by taking off
				# a word
				$desc =~ s/\s(\S+)$//;
				$wrap = $1." ".$wrap;
				}
			$desc =~ s/\.\s*$//;
			$wrap =~ s/\.\s*$//;
			if (!$donehead) {
				# Category header
				print $cname,"\n";
				print ("-" x length($cname));
				print "\n";
				$donehead = 1;
				}
			printf $fmt, $scmd, $desc;
			printf $fmt, "", $wrap if ($wrap);
			}
		}
	if ($donehead && !$multiline && !$nameonly) {
		print "\n";
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Lists available command-line API scripts.\n";
print "\n";
print "virtualmin list-commands [--short]\n";
print "                         [--multiline | --name-only]\n";
exit(1);
}

