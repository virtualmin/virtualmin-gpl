#!/usr/local/bin/perl

=head1 change-licence.pl

Change a system's Virtualmin license key

This program updates all files that we know contain a Virtualmin licence key
with a new serial and key. The two required parameters are C<--serial>
and C<--key>, which of course are followed by a valid Virtualmin Pro serial
number and key code respectively. If these are not actually valid the
program will refuse to apply them unless the C<--no-check> flag is given.

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
	$< == 0 || die "change-licence.pl must be run as root";
	}
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
		$nocheck = 1;
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
$serial || &usage("No serial number specified");
$key || &usage("No licence key specified");

# Make sure it is valid
&require_licence();
if (!$nocheck && defined(&licence_scheduled)) {
	&$first_print("Checking serial $serial and key $key ..");
	$hostid = &get_licence_hostid();
	($status, $exp, $err, $doms, $server) =
		&licence_scheduled($hostid, $serial, $key, &get_vps_type());
	if ($status) {
		&$second_print(".. license is not valid : $err");
		exit(1);
		}
	else {
		&$second_print(".. valid for ".
		    ($doms <= 0 ? "unlimited" : $doms)." domains until $exp");
		}
	}

# Update YUM repo
if (-r $virtualmin_yum_repo) {
	&$first_print("Updating Virtualmin YUM repository ..");
	&lock_file($virtualmin_yum_repo);
	local $found = 0;
	local $lref = &read_file_lines($virtualmin_yum_repo);
	foreach my $l (@$lref) {
		if ($l =~ /^baseurl=(http|https|ftp):\/\/([^:]+):([^\@]+)\@(software.virtualmin.com.*)$/) {
			$l = "baseurl=".$1."://".$serial.":".$key."\@".$4;
			$found++;
			}
		}
	&flush_file_lines($virtualmin_yum_repo);
	&unlock_file($virtualmin_yum_repo);
	if ($found) {
		&execute_command("yum clean all");
		}
	&$second_print($found ? ".. done" : ".. no lines for software.virtualmin.com found!");
	}

# Update Debian repo
$sources_list = "/etc/apt/sources.list";
if (-r $sources_list) {
	&$first_print("Updating Virtualmin APT repository ..");
	&lock_file($sources_list);
	local $found = 0;
	local $lref = &read_file_lines($sources_list);
	foreach my $l (@$lref) {
		if ($l =~ /^deb\s+(http|https|ftp):\/\/([^:]+):([^\@]+)\@(software.virtualmin.com.*)$/) {
			$l = "deb ".$1."://".$serial.":".$key."\@".$4;
			$found++;
			}
		}
	&flush_file_lines($sources_list);
	&unlock_file($sources_list);
	if ($found) {
		&execute_command("apt-get update");
		}
	&$second_print($found ? ".. done" : ".. no lines for software.virtualmin.com found!");
	}

# Update Webmin updates file
&foreign_require("webmin");
if ($webmin::config{'upsource'} =~ /\Q$upgrade_virtualmin_host\E/) {
	&$first_print("Updating Webmin module updates URL ..");
	&lock_file($webmin::module_config_file);
	@upsource = split(/\t/, $webmin::config{'upsource'});
	foreach $u (@upsource) {
		if ($u =~ /^(http|https|ftp):\/\/([^:]+):([^\@]+)\@(software.virtualmin.com.*)$/) {
			$u = $1."://".$serial.":".$key."\@".$4;
			}
		}
	$webmin::config{'upsource'} = join("\t", @upsource);
	&webmin::save_module_config();
	&unlock_file($webmin::module_config_file);
	&$second_print(".. done");
	}

# Update Virtualmin licence file
&$first_print("Updating Virtualmin license file ..");
&lock_file($virtualmin_license_file);
%lfile = ( 'SerialNumber' => $serial,
           'LicenseKey' => $key );
if (!$nocheck) {
	&update_licence_from_site(\%lfile);
	}
&write_env_file($virtualmin_license_file, \%lfile);
&unlock_file($virtualmin_license_file);
&$second_print(".. done");
&run_post_actions_silently();
&virtualmin_api_log(\@OLDARGV);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Updates the Virtualmin Pro license for this system.\n";
print "\n";
print "virtualmin change-licence --serial number\n";
print "                          --key id\n";
print "                         [--no-check]\n";
exit(1);
}


