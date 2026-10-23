#!/usr/local/bin/perl

=head1 change-licence.pl

Change a system's Virtualmin license key

This program updates all files that we know contain a Virtualmin licence key
with a new serial and key. The two required parameters are C<--serial>
and C<--key>, which of course are followed by a valid Virtualmin Pro serial
number and key code respectively. If these are not actually valid, the
program will refuse to apply them, unless the C<--no-check> flag is given. If
GPL detection must be disabled use the C<--force-update> flag.
C<--offline> replaces credentials in existing local configuration without
validation, repository setup, package commands or post-change hooks. It also
clears the previous license status without changing the installed edition.

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
	$0 = "$pwd/change-licence.pl";
	require './virtual-server-lib.pl';
	require './virtualmin-licence.pl';
	$< == 0 || die "change-licence.pl must be run as root";
	}
&set_all_text_print();
@OLDARGV = @ARGV;

# Parse args
while(@ARGV > 0) {
	my $a = shift(@ARGV);
	if ($a eq "--serial") {
		$serial = shift(@ARGV);
		}
	elsif ($a eq "--key") {
		$key = shift(@ARGV);
		}
	elsif ($a eq "--no-check") {
		$nocheck = 1;
		}
	elsif ($a eq "--force-update") {
		$force_update = 1;
		}
	# Offline replacement must not validate credentials or rebuild repositories.
	elsif ($a eq "--offline") {
		$offline = 1;
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	elsif ($a eq "--help") {
		&usage();
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
$serial || &usage("No serial number specified");
$key || &usage("No licence key specified");

# Apply credentials through the selected online or offline path.
my ($err, $msg) = &change_licence($serial, $key, $nocheck, $force_update, undef, $offline);
&usage($msg) if ($err && $msg);
&run_post_actions_silently() if (!$offline);
&virtualmin_api_log(\@OLDARGV);

# usage([error]) prints supported arguments and exits without changing files.
sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Updates the Virtualmin Pro license for this system.\n";
print "\n";
print "virtualmin change-licence --serial number\n";
print "                          --key id\n";
print "                         [--no-check]\n";
print "                         [--force-update]\n";
print "                         [--offline]\n";
exit(1);
}


