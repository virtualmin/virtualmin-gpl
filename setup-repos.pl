#!/usr/local/bin/perl

=head1 setup-repos.pl

Setup Virtualmin repositories.

This program can be used to setup or fix Virtualmin repositories.

You can force to update license serial and key used in repos all in one
go by passing C<--serial> and C<--key> params. If not set, existing keys
found in /etc/virtualmin-license will be used. GPL users should not use
C<--serial> and C<--key> params unless they want to use this command for
a quick Virtualmin Pro repositories setup.

In case C<--serial> and C<--key> params are set and license is not actually 
valid, the error will be returned, unless the C<--no-check> param is given.

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
	$0 = "$pwd/setup-repos.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "setup-repos.pl must be run as root";
	}

# Parse command-line args
&set_all_text_print();
@OLDARGV = @ARGV;

# Parse args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--serial") {
		$serial = shift(@ARGV);
		}
	elsif ($a eq "--key") {
		$key = shift(@ARGV);
		}
	elsif ($a eq "--no-check") {
		$nocheck = "--no-check ";
		}
	elsif ($a eq "--help") {
		&usage();
		}
	}

if ($serial && $key) {
	&$first_print("Setting up license serial $serial and key $key ..");
	my $vmcmd = &get_api_helper_command();
	$vmcmd || &usage('Cannot find Virtualmin helper command');
	my ($out, $err);
	&execute_command("$vmcmd change-licence ".
		"--serial @{[quotemeta($serial)]} --key @{[quotemeta($key)]} ".
		"${nocheck}--force-update", undef, \$out, \$err);
	if ($?) {
		&$first_print(".. error : @{[setup_error($err || $out)]}");
		exit(2);
		}
	else {
		&$first_print(".. done");
		}
	}

# Setup or fix Virtualmin repositories
&$first_print("Setting up Virtualmin software repositories ..");
my $shcmd = &has_command('sh');
my ($out, $err);
&execute_command("INTERACTIVE_MODE=off $shcmd setup-repos.sh --setup", undef, \$out, \$err);
if ($?) {
	&$first_print(".. error : @{[setup_error($err || $out)]}");
	}
else {
	&$first_print(".. done");
	}

&virtualmin_api_log(\@OLDARGV);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Setup Virtualmin repositories.\n";
print "\n";
print "virtualmin setup-repos [--serial number] [--key id] [--no-check]\n";
exit(1);
}

sub setup_error
{
my ($e) = @_;
$e =~ s/Error:\s*//;
$e =~ s/[\s\n]+/ /gm;
$e =~ s/\[INFO\].*?(Hit:|Err:|Get:|E:)/$1/;
$e =~ s/\[ERROR\].*?/ /g;
$e =~ s/\s*\.\./. /g;
$e =~ s/\.\.\s*//g;
$e =~ s/\.\s\.\s+/. /g;
$e =~ s/\s+/ /g;
$e =~ s/(Exiting\.).*/$1/g;
$e = &trim($e);
return $e;
}

