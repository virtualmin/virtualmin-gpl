#!/usr/local/bin/perl
# Lists simple mail aliases for some domain

package virtual_server;
$main::no_acl_check++;
$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
if ($0 =~ /^(.*\/)[^\/]+$/) {
	chdir($1);
	}
chop($pwd = `pwd`);
$0 = "$pwd/list-simple-aliases.pl";
require './virtual-server-lib.pl';
$< == 0 || die "list-simple-aliases.pl must be run as root";

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = shift(@ARGV);
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

$domain || &usage();
$d = &get_domain_by("dom", $domain);
$d || usage("Virtual server $domain does not exist");
@aliases = &list_domain_aliases($d, !$plugins);
if ($multi) {
	# Show each destination on a separate line
	foreach $a (@aliases) {
		$simple = &get_simple_alias($d, $a);
		next if (!$simple);
		print $a->{'from'},"\n";
		print "    Comment: $a->{'cmt'}\n" if ($a->{'cmt'});
		foreach $f (@{$simple->{'forward'}}) {
			print "    Forward: $f\n";
			}
		if ($simple->{'bounce'}) {
			print "    Bounce: Yes\n";
			}
		if ($simple->{'local'}) {
			print "    Local user: $simple->{'local'}\n";
			}
		if ($simple->{'auto'}) {
			$msg = $simple->{'autotext'};
			$msg =~ s/\n/\\n/g;
			print "    Autoreply message: $msg\n";
			}
		if ($simple->{'period'}) {
			print "    Autoreply period: $simple->{'period'}\n";
			}
		if ($simple->{'from'}) {
			print "    Autoreply from: $simple->{'from'}\n";
			}
		}
	}
else {
	# Show all on one line
	$fmt = "%-20s %-59s\n";
	printf $fmt, "Alias", "Destination";
	printf $fmt, ("-" x 20), ("-" x 59);
	foreach $a (@aliases) {
		$simple = &get_simple_alias($d, $a);
		next if (!$simple);
		@to = @{$simple->{'forward'}};
		push(@to, "Bounce") if ($simple->{'bounce'});
		push(@to, $simple->{'local'}) if ($simple->{'local'});
		push(@to, "Autoreply") if ($simple->{'auto'});
		printf $fmt, &nice_from($a->{'from'}),
			     join(", ", @to);
		}
	}

sub nice_from
{
local $f = $_[0];
$f =~ s/\@$domain$//;
return $f eq "%1" || !$f ? "*" : $f;
}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Lists the simple mail aliases in some virtual server.\n";
print "\n";
print "usage: list-simple-aliases.pl   --domain domain.name\n";
print "                                [--multiline]\n";
print "                                [--plugins]\n";
exit(1);
}

