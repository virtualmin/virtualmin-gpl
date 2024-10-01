#!/usr/local/bin/perl

=head1 list-php-directories.pl

List all directories in which a specific version of PHP has been activated

By default this command outputs a table of directories for the virtual server
specified with the C<--domain> parameter. However, the C<--multiline> flag
can be used to output more detail about each directory in a format more
easily parsed by other programs. Or if you just want a list of directories,
use the C<--name-only> flag.

By default only the base version numbers are shown, but you can switch to
showing the complete version with the C<--full-version> flag.

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
	$0 = "$pwd/list-users.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-php-directories.pl must be run as root";
	}

# Parse command-line args
$owner = 1;
&parse_common_cli_flags(\@ARGV);
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = shift(@ARGV);
		}
	elsif ($a eq "--full-version") {
		$fullver = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

$domain || &usage("No domain specified");
$d = &get_domain_by("dom", $domain);
$d || usage("Virtual server $domain does not exist");
@dirs = &list_domain_php_directories($d);

if ($multiline) {
	# Show on separate lines
	foreach $dir (@dirs) {
		my $fullver = &get_php_version($dir->{'version'}, $d);
		print $dir->{'dir'},"\n";
		print "  PHP version: $dir->{'version'}\n";
		print "  Full version: $fullver\n" if ($fullver);
		print "  Execution mode: $dir->{'mode'}\n";
		print "  Web root directory: ",
		    ($dir->{'dir'} eq &public_html_dir($d) ? "Yes" : "No"),"\n";
		}
	}
elsif ($nameonly) {
	# Just directories
	foreach $dir (@dirs) {
                print $dir->{'dir'},"\n";
		}
	}
else {
	# Show in table
	$fmt = "%-70.70s %-7.7s\n";
	printf $fmt, "Directory", "Version";
	printf $fmt, ("-" x 70), ("-" x 7);
	foreach $dir (@dirs) {
		my $v = $fullver ? &get_php_version($dir->{'version'})
				 : $dir->{'version'};
		printf $fmt, $dir->{'dir'}, $v;
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Lists web directories with different PHP versions in a virtual server.\n";
print "\n";
print "virtualmin list-php-directories --domain domain.name\n";
print "                               [--multiline | --json | --xml |\n";
print "                                --name-only]\n";
print "                               [--full-version]\n";
exit(1);
}

