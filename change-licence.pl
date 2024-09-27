#!/usr/local/bin/perl

=head1 change-licence.pl

Change a system's Virtualmin license key

This program updates all files that we know contain a Virtualmin licence key
with a new serial and key. The two required parameters are C<--serial>
and C<--key>, which of course are followed by a valid Virtualmin Pro serial
number and key code respectively. If these are not actually valid, the
program will refuse to apply them, unless the C<--no-check> flag is given. If
GPL detection must be disabled use the C<--force-update> flag.

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
local @ARGV = @ARGV;
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
	elsif ($a eq "--force-update") {
		$force_update = 1;
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

# Make sure it is valid
&require_licence($force_update);
if (!$nocheck && defined(&licence_scheduled)) {
	&$first_print("Validating serial $serial and key $key ..");
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

# Display a warning to GPL user trying to apply a license instead of properly upgrading
# Can be bypassed by using --force-update flag
my $gpl_repos_warning = "GPL repos detected. Use \`System Settings ⇾ Upgrade to Virtualmin Pro\` in UI instead to upgrade first!";

# Update RHEL repo
if (-r $virtualmin_yum_repo) {
	my $found = 0;
	my $lref = &read_file_lines($virtualmin_yum_repo);
	
	my $gpl_warning = ("@{$lref}" =~ /\/gpl\// && !$force_update);
	&usage($gpl_repos_warning) if ($gpl_warning);

	&$first_print("Updating Virtualmin repository ..");
	&lock_file($virtualmin_yum_repo);
	foreach my $l (@$lref) {
		if (
			# Pro license
			$l =~ /^baseurl=(https?):\/\/([^:]+):([^\@]+)\@($upgrade_virtualmin_host.*)$/ ||
			# GPL license
			($force_update && $l =~ /^baseurl=(https?):(\/)(\/)($upgrade_virtualmin_host.*)$/)
			) {
				my $host = $4;
				if ($force_update && $l =~ /\/gpl\//) {
					$host =~ s/gpl\//pro\//;
				}
				$l = "baseurl=https://".$serial.":".$key."\@".$host;
				$found++;
			}
		}
	&flush_file_lines($virtualmin_yum_repo);
	&unlock_file($virtualmin_yum_repo);
	if ($found) {
		&execute_command("yum clean all");
		}
	&$second_print($found ? ".. done" : ".. no lines for $upgrade_virtualmin_host found!");
	}

# Update Debian repo
if (-r $virtualmin_apt_repo) {
	local $found = 0;
	local $lref = &read_file_lines($virtualmin_apt_repo);
	
	my $gpl_warning = ("@{$lref}" =~ /\/gpl\// && !$force_update);
	&usage($gpl_repos_warning) if ($gpl_warning);
	
	&$first_print("Updating Virtualmin repository ..");
	&lock_file($virtualmin_apt_repo);
	foreach my $l (@$lref) {
		if (
			# Pro license old format
			$l =~ /^deb(.*?)(https?):\/\/([^:]+):([^\@]+)\@($upgrade_virtualmin_host.*)$/ ||
			# Pro license new format and GPL license
			(-d $virtualmin_apt_auth_dir && $l =~ /^deb(.*?)(https?):(\/)(\/).*($upgrade_virtualmin_host.*)$/) ||
			# GPL license on old systems
			($force_update && $l =~ /^deb(.*?)(https?):(\/)(\/).*($upgrade_virtualmin_host.*)$/)
			) {
				my $gpgkey = $1;
				my $host = $5;
				if ($force_update && $l =~ /\/gpl\//) {
					$host =~ s/gpl\//pro\//;
					}
				if (-d $virtualmin_apt_auth_dir) {
					$l = "deb${gpgkey}https://".$host;
					}
				else {
					$l = "deb${gpgkey}https://".$serial.":".$key."\@".$host;
					}
				$found++;
			}
		}
	&flush_file_lines($virtualmin_apt_repo);
	&unlock_file($virtualmin_apt_repo);
	if (-d $virtualmin_apt_auth_dir) {
		&write_file_contents(
		    "$virtualmin_apt_auth_dir/virtualmin.conf",
		    "machine $upgrade_virtualmin_host login $serial password $key\n");
		}
	if ($found) {
		&execute_command("apt-get update");
		}
	&$second_print($found ? ".. done" : ".. no lines for $upgrade_virtualmin_host found!");
	}

# Update Webmin updates file
&foreign_require("webmin");
if ($webmin::config{'upsource'} =~ /\Q$upgrade_virtualmin_host\E/) {
	&$first_print("Updating Webmin module updates URL ..");
	&lock_file($webmin::module_config_file);
	@upsource = split(/\t/, $webmin::config{'upsource'});
	foreach $u (@upsource) {
		if ($u =~ /^(http|https|ftp):\/\/([^:]+):([^\@]+)\@($upgrade_virtualmin_host.*)$/) {
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
&write_env_file($virtualmin_license_file, \%lfile);
&unlock_file($virtualmin_license_file);
if ($status == 0) {
	# Update the status file
	if (!$nocheck) {
		&read_file($licence_status, \%licence);
		&update_licence_from_site(\%licence);
		&write_file($licence_status, \%licence);
		}
	&$second_print(".. done");
	}
else {
	&$second_print(".. failed : $err");
	}
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
print "                         [--force-update]\n";
exit(1);
}


