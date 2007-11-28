#!/usr/local/bin/perl
# Set the version of PHP to run in some directory

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*\/)[^\/]+$/) {
		chdir($1);
		}
	chop($pwd = `pwd`);
	$0 = "$pwd/set-php-directory.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "set-php-directory.pl must be run as root";
	}

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
	elsif ($a eq "--version") {
		$version = shift(@ARGV);
		}
	else {
		&usage();
		}
	}

# Validate inputs
$domain && $dir && $version || &usage();
$d = &get_domain_by("dom", $domain);
$d || usage("Virtual server $domain does not exist");
$mode = &get_domain_php_mode($d);
$mode eq "mod_php" &&
    usage("The PHP version cannot be set for virtual servers using mod_php");
@avail = map { $_->[0] } &list_available_php_versions($d);
&indexof($version, @avail) >= 0 ||
    usage("Only the following PHP version are available : ".join(" ", @avail));
if ($dir eq ".") {
	$dir = &public_html_dir($d);
	}
elsif ($dir !~ /^\//) {
	$dir = &public_html_dir($d)."/".$dir;
	}

# Make the change
&set_all_null_print();
&save_domain_php_directory($d, $dir, $version);
&run_post_actions();

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Sets the version of PHP to be used in some web directory.\n";
print "\n";
print "usage: set-php-directory.pl   --domain domain.name\n";
print "                              --dir directory|url-path\n";
print "                              --version num\n";
exit(1);
}

