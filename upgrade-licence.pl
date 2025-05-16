#!/usr/local/bin/perl

=head1 upgrade-license.pl

Upgrade Virtualmin GPL system to Pro version

This program can be used to upgrade Virtualmin GPL system to Professional
version.

The serial C<--serial> and key C<--key> params must be set to an actual
valid license.

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
	$0 = "$pwd/upgrade-license.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "upgrade-license.pl must be run as root";
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
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	elsif ($a eq "--help") {
		&usage();
		}
	}

$serial || &usage("No serial number specified");
$key || &usage("No licence key specified");
$key =~ /^(AMAZON|DEMO|GPL)$/ && &usage("This license key cannot be used for upgrades");

my ($out, $err);

# Setup Virtualmin license and repositories
&$first_print("Upgrading Virtualmin license and repositories ..");
my $vmcmd = &get_api_helper_command();
$vmcmd || &usage('Cannot find Virtualmin helper command');
&execute_command("$vmcmd setup-repos ".
	"--serial @{[quotemeta($serial)]} --key @{[quotemeta($key)]} ".
	"--force-update", undef, \$out, \$err);
if ($?) {
	&$second_print($err || $out);
	exit(2);
	}
else {
	&$second_print("..done");
	}

# Update Virtualmin package to Pro
&$first_print("Upgrading Virtualmin package ..");
my $itype;
chop($itype = &read_file_contents("$module_root_directory/install-type"));

# Update metadata and install latest ca-certificates package
if ($itype eq "rpm") {
	&execute_command("yum clean all");
	&execute_command("yum -y update ca-certificates");

	# Run the upgrade
	&execute_command("yum -y install wbm-virtual-server wbm-virtualmin-support", undef, \$out, \$err);
	if ($?) {
		&$second_print("..error : @{[($err || $out)]}");
		exit(3);
		}
	else {
		&$second_print($text{'setup_done'});
		&$second_print($text{'upgrade_success'});
		}
	}

# Update metadata and install latest ca-certificates package
elsif ($itype eq "deb") {
	&execute_command("apt-get update");
	&execute_command("apt-get -y install ca-certificates");

	# Run the upgrade
	my @packages;
	&foreign_require("software");
	foreach $p (&software::update_system_available()) {
		if ($p->{'name'} eq 'webmin-virtual-server') {
			# For the Virtualmin package, select pro
			# version explicitly so that the GPL is
			# replaced.
			local ($ver) = grep { !/\.gpl/ }
				&apt_package_versions($p->{'name'});
                            push(@packages, $ver ? $p->{'name'}."=".$ver
					     : $p->{'name'});
			}
		}
	if (!@packages) {
		push(@packages, 'webmin-virtual-server');
		} 

	# Add Virtualmin support module
	push(@packages, 'webmin-virtualmin-support');
	&execute_command("apt-get -y --allow-unauthenticated --allow-downgrades --allow-remove-essential --allow-change-held-packages -f install ".join(" ", @packages)."", undef, \$out, \$err);
	if ($?) {
		&$second_print("..error : @{[($err || $out)]}");
		exit(3);
		}
	else {
		&$second_print($text{'setup_done'});
		&$second_print($text{'upgrade_success'});
		}
	}
else {
	&$second_print(".. error : Upgrades are not supported on this system : $itype");
	exit(4);
}

&clear_links_cache();
&virtualmin_api_log(\@OLDARGV);

sub apt_package_versions
{
local ($name) = @_;
local @rv;
open(OUT, "apt-cache show ".quotemeta($name)." |");
while(<OUT>) {
	if (/^Version:\s+(\S+)/) {
		push(@rv, $1);
		}
	}
close(OUT);
return sort { &compare_versions($b, $a) } @rv;
}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Upgrade Virtualmin GPL system to Pro.\n";
print "\n";
print "virtualmin upgrade-license --serial number\n";
print "                           --key id\n";
exit(1);
}