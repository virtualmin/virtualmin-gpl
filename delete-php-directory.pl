#!/usr/local/bin/perl
# Remove any custom version of PHP for some directory

package virtual_server;
$main::no_acl_check++;
$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
if ($0 =~ /^(.*\/)[^\/]+$/) {
	chdir($1);
	}
chop($pwd = `pwd`);
$0 = "$pwd/delete-php-directory.pl";
require './virtual-server-lib.pl';
$< == 0 || die "delete-php-directory.pl must be run as root";

# Parse command-line args
$owner = 1;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = shift(@ARGV);
		}
	elsif ($a eq "--dir") {
		$dir = shift(@ARGV);
		}
	else {
		&usage();
		}
	}

# Validate inputs
$domain && $dir || &usage();
$d = &get_domain_by("dom", $domain);
$d || usage("Virtual server $domain does not exist");
$mode = &get_domain_php_mode($d);
if ($dir !~ /^\//) {
	$dir = &public_html_dir($d)."/".$dir;
	}
if ($dir eq &public_html_dir($d)) {
	usage("The PHP version cannot be removed for public_html");
	}

# Make the change
&set_all_null_print();
&delete_domain_php_directory($d, $dir);
&run_post_actions();

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Removes any custom PHP version used in some web directory.\n";
print "\n";
print "usage: delete-php-directory.pl   --domain domain.name\n";
print "                                 --dir directory|url-path\n";
exit(1);
}

