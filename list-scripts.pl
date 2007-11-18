#!/usr/local/bin/perl
# Lists all scripts installed into some virtual server

package virtual_server;
$main::no_acl_check++;
$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
if ($0 =~ /^(.*\/)[^\/]+$/) {
	chdir($1);
	}
chop($pwd = `pwd`);
$0 = "$pwd/list-scripts.pl";
require './virtual-server-lib.pl';
$< == 0 || die "list-scripts.pl must be run as root";

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		push(@dnames, shift(@ARGV));
		}
	elsif ($a eq "--user") {
		push(@users, shift(@ARGV));
		}
	elsif ($a eq "--multiline") {
		$multi = 1;
		}
	else {
		&usage();
		}
	}

# Validate args and get domains
@dnames || @users || &usage();
@doms = &get_domains_by_names_users(\@dnames, \@users, \&usage);

foreach my $d (@doms) {
	@scripts = &list_domain_scripts($d);

	if ($multi) {
		# Show each script on a separate line
		foreach $sinfo (@scripts) {
			$script = &get_script($sinfo->{'name'});
			$opts = $sinfo->{'opts'};
			print "$sinfo->{'id'}\n";
			print "    Domain: $d->{'dom'}\n";
			print "    Type: $script->{'name'}\n";
			print "    Description: $script->{'desc'}\n";
			print "    Version: $sinfo->{'version'}\n";
			print "    Installed: ",&make_date($sinfo->{'time'}),"\n";
			print "    Details: $sinfo->{'desc'}\n";
			print "    URL: $sinfo->{'url'}\n";
			if ($opts->{'dir'}) {
				print "    Directory: $opts->{'dir'}\n";
				}
			($dbtype, $dbname) = split(/_/, $opts->{'db'}, 2);
			if ($dbtype) {
				print "    Database: $dbname ($dbtype)\n";
				}
			if ($sinfo->{'user'}) {
				print "    Initial login: $sinfo->{'user'}\n";
				print "    Initial password: $sinfo->{'pass'}\n";
				}
			}
		}
	else {
		# Show all on one line
		if (@doms > 1) {
			print "Scripts in domain $d->{'dom'} :\n"; 
			}
		$fmt = "%-15.15s %-20.20s %-10.10s %-30.30s\n";
		printf $fmt, "ID", "Description", "Version", "URL path";
		printf $fmt, ("-" x 15), ("-" x 20), ("-" x 10), ("-" x 30);
		foreach $sinfo (@scripts) {
			$script = &get_script($sinfo->{'name'});
			$path = $sinfo->{'url'};
			$path =~ s/^http:\/\/([^\/]+)//;
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
print "usage: list-scripts.pl   [--domain domain.name]*\n";
print "                         [--user username]*\n";
print "                         [--multiline]\n";
exit(1);
}

