#!/usr/local/bin/perl
# Sets the value of a custom field for some server

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*\/)[^\/]+$/) {
		chdir($1);
		}
	chop($pwd = `pwd`);
	$0 = "$pwd/modify-custom.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "modify-custom.pl must be run as root";
	}
use POSIX;

# Parse command-line args
$owner = 1;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = shift(@ARGV);
		}
	elsif ($a eq "--set") {
		$field = shift(@ARGV);
		$value = shift(@ARGV);
		$field && defined($value) || &usage();
		push(@set, [ $field, $value ]);
		}
	else {
		&usage();
		}
	}
$domain && @set || &usage();

# Get the domain
$dom = &get_domain_by("dom", $domain);
$dom || usage("Virtual server $domain does not exist.");
$old = { %$dom };

# Update all fields
@fields = &list_custom_fields();
foreach $f (@set) {
	($field) = grep { $_->{'name'} eq $f->[0] ||
			  $_->{'desc'} eq $f->[0] } @fields;
	$field || &usage("No custom field named $f->[0] exists");
	$dom->{'field_'.$field->{'name'}} = $f->[1];
	}

&save_domain($dom);
print "Custom field values in $domain successfully updated\n";

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Sets the values of one or more custom fields for a virtual server\n";
print "\n";
print "usage: modify-custom.pl   --domain name\n";
print "                          --set field value [--set field value] ...\n";
exit(1);
}


