#!/usr/local/bin/perl
# Lists mail aliases in some domain

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*\/)[^\/]+$/) {
		chdir($1);
		}
	chop($pwd = `pwd`);
	$0 = "$pwd/list-aliases.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-aliases.pl must be run as root";
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
	elsif ($a eq "--all-domains") {
		$all = 1;
		}
	elsif ($a eq "--multiline") {
		$multi = 1;
		}
	elsif ($a eq "--plugins") {
		$plugins = 1;
		}
	else {
		&usage();
		}
	}

# Validate args and get domains
@dnames || @users || $all || &usage();
if ($all) {
	@doms = &list_domains();
	}
else {
	@doms = &get_domains_by_names_users(\@dnames, \@users, \&usage);
	}

foreach $d (@doms) {
	@aliases = &list_domain_aliases($d, !$plugins);
	if ($multi) {
		# Show each destination on a separate line
		foreach $a (@aliases) {
			print $a->{'from'},
			      ($a->{'cmt'} ? " # $a->{'cmt'}" : ""),"\n";
			foreach $t (@{$a->{'to'}}) {
				print "    $t\n";
				}
			}
		}
	else {
		# Show all on one line
		if (@doms > 1) {
			print "Aliases in domain $d->{'dom'} :\n"; 
			}
		$fmt = "%-20s %-59s\n";
		printf $fmt, "Alias", "Destination";
		printf $fmt, ("-" x 20), ("-" x 59);
		foreach $a (@aliases) {
			printf $fmt, &nice_from($a->{'from'}),
				     join(", ", @{$a->{'to'}});
			}
		if (@doms > 1) {
			print "\n";
			}
		}
	}

sub nice_from
{
local $f = $_[0];
$f =~ s/\@$domain$//;
return $f eq "%1" ? "*" : $f;
}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Lists the mail aliases in one or more virtual servers.\n";
print "\n";
print "usage: list-aliases.pl   [--all-domains] | [--domain domain.name] |\n";
print "                         [--user username]*\n";
print "                         [--multiline]\n";
print "                         [--plugins]\n";
exit(1);
}

