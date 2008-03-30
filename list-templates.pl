#!/usr/local/bin/perl
# Lists all configuration templates

$no_acl_check++;
$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
if ($0 =~ /^(.*\/)[^\/]+$/) {
	chdir($1);
	}
chop($pwd = `pwd`);
$0 = "$pwd/list-templates.pl";
require './virtual-server-lib.pl';
$< == 0 || die "list-templates.pl must be run as root";

# Parse command-line args
$owner = 1;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--name-only") {
		$nameonly = 1;
		}
	else {
		&usage();
		}
	}

@tmpls = &list_templates();
if ($nameonly) {
	# Just template IDs
	foreach $tmpl (@tmpls) {
		print $tmpl->{'name'},"\n";
		}
	}
else {
	# More details
	$fmt = "%-10.10s %-60.60s\n";
	printf $fmt, "ID", "Description";
	printf $fmt, ("-" x 10), ("-" x 60);
	foreach $tmpl (@tmpls) {
		printf $fmt, $tmpl->{'id'}, $tmpl->{'name'};
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Lists the available templates for new virtual servers.\n";
print "\n";
print "usage: list-templates.pl [--name-only]\n";
exit(1);
}

