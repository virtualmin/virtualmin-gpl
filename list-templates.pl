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

@tmpls = &list_templates();
$fmt = "%-10.10s %-60.60s\n";
printf $fmt, "ID", "Description";
printf $fmt, ("-" x 10), ("-" x 60);
foreach $tmpl (@tmpls) {
	printf $fmt, $tmpl->{'id'}, $tmpl->{'name'};
	}


