#!/usr/local/bin/perl

=head1 license-info.pl

Show license counts for this Virtualmin system.

This command simply outputs the serial number and license key of the current
Virtualmin system, and the number of virtual servers that exist and are allowed
by the license.

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
	$0 = "$pwd/info.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "license-info.pl must be run as root";
	}

while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Show serial and key
&read_env_file($virtualmin_license_file, \%vserial);
&read_file($licence_status, \%lstatus);
print "Serial number: $vserial{'SerialNumber'}\n";
print "License key: $vserial{'LicenseKey'}\n";
print "Expiry date: $lstatus{'expiry'}\n";

# Allowed domain counts
@realdoms = grep { !$_->{'alias'} } &list_domains();
($dleft, $dreason, $dmax, $dhide) = &count_domains("realdoms");
print "Virtual servers: ",scalar(@realdoms),"\n";
print "Maximum servers: ",($dmax > 0 ? $dmax : "Unlimited"),"\n";
print "Servers left: ",($dmax > 0 ? $dleft : "Unlimited"),"\n";

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Displays license information for this Virtualmin system.\n";
print "\n";
print "virtualmin info\n";
exit(1);
}

