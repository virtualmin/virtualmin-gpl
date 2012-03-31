#!/usr/local/bin/perl

=head1 list-available-scripts.pl

List known scripts

This command simply outputs a list of scripts that can potentially installed
into Virtualmin servers. By default it displays a nicely formatted table, but
if the C<--multiline> option is given it will use a more machine-readable format
which shows more information.

By default all scripts available are listed, but you can limit the output
to only those built into Virtualmin with the C<--source core> parameter. Or
show only those you have installed separately with C<--source custom>, or
those from plugins with C<--source plugin>.

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
	$0 = "$pwd/list-available-scripts.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-available-scripts.pl must be run as root";
	}

# Parse command-line args
@types = ( );
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--multiline") {
		$multi = 1;
		}
	elsif ($a eq "--source") {
		$source = shift(@ARGV);
		}
	elsif ($a eq "--type") {
		push(@types, shift(@ARGV));
		}
	elsif ($a eq "--core-only") {
		$coreonly = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Get and filter scripts
@types = &list_scripts($coreonly) if (!@types);
@scripts = map { &get_script($_, $coreonly) } @types;
if ($source) {
	@scripts = grep { $_->{'source'} eq $source } @scripts;
	}

if ($multi) {
	# Show each script on a separate line
	$overall = &get_overall_script_ratings();
	foreach $script (@scripts) {
		print "$script->{'name'}\n";
		print "    Name: $script->{'desc'}\n";
		if ($script->{'category'}) {
			print "    Category: $script->{'category'}\n";
			}
		print "    Available: ",$script->{'avail'} ? "Yes" : "No","\n";
		print "    Versions: ",join(" ", @{$script->{'versions'}}),"\n";
		if ($script->{'release'}) {
			print "    Release: ",$script->{'release'},"\n";
			}
		print "    Available versions: ",
			join(" ", grep { &can_script_version($script, $_) }
				       @{$script->{'versions'}}),"\n";
		print "    Description: $script->{'longdesc'}\n";
		print "    Uses: ",join(" ", @{$script->{'uses'}}),"\n";
		if ($overall->{$script->{'name'}}) {
			print "    Rating: ".$overall->{$script->{'name'}}."\n";
			}
		if ($script->{'site'}) {
			print "    Website: $script->{'site'}\n";
			}
		if ($script->{'author'}) {
			print "    Installer author: $script->{'author'}\n";
			}
		print "    Source: $script->{'source'}\n";
		}
	}
else {
	# Show all on one line
	$fmt = "%-30.30s %-30.30s %-10.10s\n";
	printf $fmt, "Name", "Versions", "Available?";
	printf $fmt, ("-" x 30), ("-" x 30), ("-" x 10);
	foreach $script (@scripts) {
		printf $fmt, $script->{'desc'},
			     join(" ", @{$script->{'versions'}}),
			     $script->{'avail'} ? "Yes" : "No";
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Lists the third-party scripts available for installation.\n";
print "\n";
print "virtualmin list-available-scripts [--multiline]\n";
print "                                  [--source core|custom|plugin|latest]\n";
print "                                  [--type name]*\n";
exit(1);
}

