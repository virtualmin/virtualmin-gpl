# Defines the function for validating the Virtualmin licence, by making an
# HTTP request to the licence CGI.

$virtualmin_licence_host = "software.virtualmin.com";
$virtualmin_licence_port = 443;
$virtualmin_licence_prog = "/cgi-bin/vlicence.cgi";
$virtualmin_licence_ssl = 1;
$virtualmin_renewal_url = $config{'renewal_url'} ||
			  "https://virtualmin.com/shop/";

# licence_scheduled(hostid, [serial, key], [vps-type])
# Returns a status code (0=OK, 1=Invalid, 2=Down, 3=Expired), the expiry date,
# an error message, the number of domains max, the number of servers max,
# the number of servers used, and the auto-renewal flag
sub licence_scheduled
{
local ($hostid, $serial, $key, $vps) = @_;
local ($out, $error, $regerr);
local @doms = grep { !$_->{'alias'} } &list_domains();
&read_env_file($virtualmin_license_file, \%serial);
$key ||= $serial{'LicenseKey'};
&http_download($virtualmin_licence_host,
	       $virtualmin_licence_port,
	       "$virtualmin_licence_prog?id=$hostid&".
		"serial=$key&doms=".scalar(@doms)."&vps=$vps",
	       \$out, \$error, undef, $virtualmin_licence_ssl,
	       undef, undef, 10, 0, 1);
return (2, undef, "$text{'licence_efailed'} : $error") if ($error);
return $out =~ /^EXP\s+(?<exp>\S+)\s+(\S+)\s+(\S+)\s+(\S+)/ ?
	(3, "$+{exp}", &text("licence_eexp", "$+{exp}"), $2, $3, $4) :
       $out =~ /^ERR\s+(?<err>.*)/ && ($regerr = $+{err}) &&
       	       $regerr !~ /invalid\s+host\s+or\s+serial\s+number/i ?
	(2, undef, "$text{'licence_echk'} : $regerr", undef) :
       $out =~ /^OK\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\d+)/ ?
	(0, $1, undef, $2, $3, $4, $5) :	# Auto-renewal flag
       $out =~ /^OK\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)/ ?
	(0, $1, undef, $2, $3, $4) :
	(1, undef, &text("licence_evalid",
		   	 "<tt data-evalid>$serial{'SerialNumber'}</tt>"));
}

# Change license with a new serial and key
sub change_licence
{
my ($serial, $key, $nocheck, $force_update) = @_;
&require_licence($force_update);
my ($status, $exp, $err, $doms, $server, $hostid);
# Display a warning to GPL user trying to apply a license instead of
# properly upgrading. Can be bypassed by using --force-update flag
if (!$force_update) {
	my $gpl_repos_warning =
		"GPL repos detected. Use \"System Settings ⇾ ".
		"Upgrade to Virtualmin Pro\" in UI to upgrade first!";
	my $yumrepo = &read_file_lines($virtualmin_yum_repo, 1);
	my $aptrepo = &read_file_lines($virtualmin_apt_repo, 1);
	if (($yumrepo && "@{$yumrepo}" =~ /\/gpl\//) ||
	    ($aptrepo && "@{$aptrepo}" =~ /\/gpl\//)) {
		return (1, $gpl_repos_warning);
		}
	}
# Validate the new license
if (!$nocheck) {
	&$first_print("Validating serial $serial and key $key ..");
	$hostid = &get_licence_hostid();
	($status, $exp, $err, $doms, $server) =
		&licence_scheduled($hostid, $serial, $key, &get_vps_type());
	if ($status) {
		&$second_print(".. license is not valid : $err");
		return (1, undef);
		}
	else {
		&$second_print(".. valid for ".
		    ($doms <= 0 ? "unlimited" : $doms)." domains until $exp");
		}
	}

# Update RHEL repo
if (-r $virtualmin_yum_repo) {
	my $found = 0;
	my $lref = &read_file_lines($virtualmin_yum_repo);

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
	my $found = 0;
	my $lref = &read_file_lines($virtualmin_apt_repo);

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
	foreach my $u (@upsource) {
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
&$second_print(".. done");
if (defined($status) && $status == 0) {
	# Update the status file
	if (!$nocheck) {
		&read_file($licence_status, \%licence);
		&update_licence_from_site(\%licence);
		&write_file($licence_status, \%licence);
		}
	}
}

1;

