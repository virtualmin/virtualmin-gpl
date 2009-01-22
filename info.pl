#!/usr/local/bin/perl

=head1 info.pl

Show general information about this Virtualmin system.

XXX

=cut

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*\/)[^\/]+$/) {
		chdir($1);
		}
	chop($pwd = `pwd`);
	$0 = "$pwd/info.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "info.pl must be run as root";
	}

@ARGV && &usage("No command line parameters are needed");

$info = &get_collected_info();
# XXX core system info

# XXX collected stuff

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Displays information about this Virtualmin system.\n";
print "\n";
print "usage: info.pl\n";
exit(1);
}

