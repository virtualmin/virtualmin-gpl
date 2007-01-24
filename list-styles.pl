#!/usr/local/bin/perl
# Lists all configuration templates

$no_acl_check++;
$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
if ($0 =~ /^(.*\/)[^\/]+$/) {
	chdir($1);
	}
chop($pwd = `pwd`);
$0 = "$pwd/list-styles.pl";
require './virtual-server-lib.pl';
$< == 0 || die "list-styles.pl must be run as root";

@styles = &list_content_styles();
$fmt = "%-15.15s %-60.60s\n";
printf $fmt, "Name", "Description";
printf $fmt, ("-" x 15), ("-" x 60);
foreach $s (@styles) {
	printf $fmt, $s->{'name'}, $s->{'desc'};
	}


