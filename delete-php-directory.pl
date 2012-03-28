#!/usr/local/bin/perl

=head1 delete-php-directory.pl

Remove any custom version of PHP for some directory

If a specific version of PHP has been configured for some directory, it
can be removed with this command. The required parameters are C<--domain>
followed by a domain name, and C<--dir> followed by a full directory like
C</home/domain/public_html/horde>. 

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
	$0 = "$pwd/delete-php-directory.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "delete-php-directory.pl must be run as root";
	}
@OLDARGV = @ARGV;

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
	elsif ($a eq "--multiline") {
		$multiline = 1;
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
&obtain_lock_web($d);
&set_all_null_print();
&delete_domain_php_directory($d, $dir);
&release_lock_web($d);
&virtualmin_api_log(\@OLDARGV, $d);
&run_post_actions();

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Removes any custom PHP version used in some web directory.\n";
print "\n";
print "virtualmin delete-php-directory --domain domain.name\n";
print "                                --dir directory|url-path\n";
exit(1);
}

