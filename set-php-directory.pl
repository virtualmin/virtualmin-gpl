#!/usr/local/bin/perl

=head1 set-php-directory.pl

Set the version of PHP to run in some directory

If more than one version of PHP is installed on your system and either CGI
or fCGId is used to run PHP scripts in some virtual server, it can be configured
to run a different PHP version on a per-directory basis. This is most useful
when running PHP applications that only support specific versions, like an
old script that only runs under version 4.

To set a PHP directory, the C<--domain> flag must be used to specify the
directory, C<--dir> to set the path (like C<horde> or C</home/domain/public_html/horde>),
and C<--version> to set the version number. At the time of writing, only
versions 4 and 5 are supported.

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
	$0 = "$pwd/set-php-directory.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "set-php-directory.pl must be run as root";
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
	elsif ($a eq "--version") {
		$version = shift(@ARGV);
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
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
&obtain_lock_web($d);
&set_all_null_print();
&save_domain_php_directory($d, $dir, $version);
&release_lock_web($d);
&run_post_actions();
&virtualmin_api_log(\@OLDARGV, $d);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Sets the version of PHP to be used in some web directory.\n";
print "\n";
print "virtualmin set-php-directory --domain domain.name\n";
print "                             --dir directory|url-path|\".\"\n";
print "                             --version num\n";
exit(1);
}

