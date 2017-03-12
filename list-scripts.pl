#!/usr/local/bin/perl

=head1 list-scripts.pl

Display script installed into some virtual server

The virtual servers to display scripts for can be specified with the 
C<--domain> parameter, which must be followed by a domain name and can appear
multiple times. Alternately you can use C<--all-domains> to select all of them,
or C<--user> to show scripts for virtual servers owned by a specific 
Virtualmin administrator.

The program displays a table of all scripts
currently installed, including their install IDs and version numbers. To get
more details in a program-friendly format, use the C<--multiline> parameter.
To just get a list of script names, use C<--name-only>.

To limit the output to just scripts of some type, use the C<--type> flag
followed by a script code name, like C<phpmyadmin>.

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
	$0 = "$pwd/list-scripts.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-scripts.pl must be run as root";
	}

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		push(@dnames, shift(@ARGV));
		}
	elsif ($a eq "--user") {
		push(@users, shift(@ARGV));
		}
	elsif ($a eq "--type") {
		$scripttype = shift(@ARGV);
		}
	elsif ($a eq "--all-domains") {
		$all = 1;
		}
	elsif ($a eq "--multiline") {
		$multi = 1;
		}
	elsif ($a eq "--name-only") {
		$nameonly = 1;
		}
	elsif ($a eq "--id-only") {
		$idonly = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Validate args and get domains
@dnames || @users || $all || &usage("No domains or users specified");
if ($all) {
	@doms = &list_domains();
	}
else {
	@doms = &get_domains_by_names_users(\@dnames, \@users, \&usage);
	}
@doms = grep { &can_domain_have_scripts($_) } @doms;
@doms || &usage("None of the selected virtual servers can have scripts");

foreach my $d (@doms) {
	&detect_real_script_versions($d);
	@scripts = &list_domain_scripts($d);
	if ($scripttype) {
		@scripts = grep { $_->{'name'} eq $scripttype } @scripts;
		}

	if ($multi) {
		# Show each script on a separate line
		foreach $sinfo (@scripts) {
			$script = &get_script($sinfo->{'name'});
			$opts = $sinfo->{'opts'};
			print "$sinfo->{'id'}\n";
			print "    Domain: $d->{'dom'}\n";
			print "    Type: $script->{'name'}\n";
			print "    Manually deleted: ",
			      ($script->{'deleted'} ? "Yes" : "No"),"\n";
			print "    Description: $script->{'desc'}\n";
			print "    Version: $sinfo->{'version'}\n";
			print "    Installed: ",&make_date($sinfo->{'time'}),"\n";
			if ($sinfo->{'desc'}) {
				print "    Details: $sinfo->{'desc'}\n";
				}
			if ($sinfo->{'url'}) {
				print "    URL: $sinfo->{'url'}\n";
				}
			print "    State: ",$sinfo->{'partial'} || "OK","\n";
			if ($opts->{'dir'}) {
				print "    Directory: $opts->{'dir'}\n";
				}
			($dbtype, $dbname) = split(/_/, $opts->{'db'}, 2);
			if ($dbtype) {
				print "    Database: $dbname ($dbtype)\n";
				print "    Delete database on uninstall: ",
				      ($opts->{'newdb'} ? "Yes" : "No"),"\n";
				}
			if ($sinfo->{'user'}) {
				print "    Initial login: $sinfo->{'user'}\n";
				print "    Initial password: $sinfo->{'pass'}\n";
				}
			if ($script->{'site'}) {
				print "    Website: $script->{'site'}\n";
				}
			}
		}
	elsif ($nameonly) {
		# Just show script type codes
		foreach $sinfo (@scripts) {
			print $sinfo->{'name'},"\n";
			}
		}
	elsif ($idonly) {
		# Just show script install IDs
		foreach $sinfo (@scripts) {
			print $sinfo->{'id'},"\n";
			}
		}
	else {
		# Show all on one line
		if (@doms > 1) {
			print "Scripts in domain $d->{'dom'} :\n"; 
			}
		$fmt = "%-20.20s %-20.20s %-10.10s %-25.25s\n";
		printf $fmt, "ID", "Description", "Version", "URL path";
		printf $fmt, ("-" x 20), ("-" x 20), ("-" x 10), ("-" x 25);
		foreach $sinfo (@scripts) {
			$script = &get_script($sinfo->{'name'});
			$path = $sinfo->{'url'};
			$path =~ s/^(http|https):\/\/([^\/]+)//;
			$path ||= $sinfo->{'path'};
			printf $fmt, $sinfo->{'id'},
				     $script->{'desc'},
				     $sinfo->{'version'},
				     $path;
			}
		if (@doms > 1) {
			print "\n";
			}
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Lists the scripts installed on one or more virtual servers.\n";
print "\n";
print "virtualmin list-scripts --all-domains | --domain name | --user username\n";
print "                       [--multiline | --name-only]\n";
print "                       [--type script]\n";
exit(1);
}

