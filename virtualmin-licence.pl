# Defines the function for validating the Virtualmin license, by making an
# HTTP request to the license CGI.

$virtualmin_licence_host = "software.virtualmin.com";
$virtualmin_licence_port = 443;
$virtualmin_licence_ssl = 1;
$virtualmin_licence_prog = "/cgi-bin/vlicence.cgi";
$virtualmin_licence_page = "/api/license/client";
$virtualmin_renewal_url = $config{'renewal_url'} ||
			  $virtualmin_shop_link;

# licence_scheduled(hostid, serial, key)
# Returns a status code (0=OK, 1=Invalid, 2=Down, 3=Expired), the expiry date,
# an error message, the number of domains max, the number of servers max,
# the number of servers used, and the auto-renewal flag
sub licence_scheduled
{
my ($hostid, $serial, $key) = @_;
my ($out, $error, $regerr, %serial);
if (!$serial || !$key) {
	# Read from license file only if not provided
	&read_env_file($virtualmin_license_file, \%serial);
	$serial = $serial{'SerialNumber'};
	$key = $serial{'LicenseKey'};
	}
# New API call using POST
my $post_details = {
	'domain' => $virtualmin_host_domain,
	'dom' => $virtualmin_host_domain,
	'ip' => $virtualmin_host_domain,
	'web_sslport' => $virtualmin_licence_port,
	'web_port' => $virtualmin_licence_port,
	'ssl' => $virtualmin_licence_ssl };
my $params = 'id='.&urlize($hostid).'&serial='.&urlize($key);
&post_http_connection($post_details, $virtualmin_licence_page, $params,
		      \$out, \$error, undef, undef, undef, undef, 10);
if ($error) {
	# Try the old API if the new fails (why would it?)
	$error = undef;
	&http_download($virtualmin_licence_host,
		       $virtualmin_licence_port,
		       "$virtualmin_licence_prog?id=$hostid&serial=$key",
		       \$out, \$error, undef, $virtualmin_licence_ssl,
		       undef, undef, 10, 0, 1);
	}
return (2, undef, "$text{'licence_efailed'} : @{[lcfirst($error)]}") if ($error);
return $out =~ /^EXP\s+(?<exp>\S+)\s+(\S+)\s+(\S+)\s+(\S+)(?:\s+(\d+)(?:\s+([\w])(?:\s+(\d+))?)?)?/ ?
	(3, "$+{exp}", &text("licence_eexp", "$+{exp}"), $2, $3, $4, $5, $6, $7) :
       $out =~ /^ERR\s+(?<err>.*)/ && ($regerr = $+{err}) &&
       	       $regerr !~ /invalid\s+host\s+or\s+serial\s+number/i ?
	(2, undef, "$text{'licence_echk'} : $regerr", undef) :
       $out =~ /^OK\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)(?:\s+(\d+)(?:\s+([\w])(?:\s+(\d+))?)?)?/ ?
	(0, $1, undef, $2, $3, $4, $5, $6, $7) :
	(1, undef,
	 	(!$serial || uc($serial) eq 'GPL') ? 
		    $text{"licence_evalidnone"} :
		    &text("licence_evalid", "<tt data-evalid>$serial</tt>"));
}

# Changes license with a new serial and key, and performs repo setup unless
# disabled
sub change_licence
{
my ($serial, $key, $nocheck, $force_update, $no_repos) = @_;
&require_licence($force_update);
my ($status, $exp, $err, $doms, $server, $hostid);
# Display a warning to GPL user trying to apply a license instead of
# properly upgrading. Can be bypassed by using --force-update flag
if (!$force_update) {
	my %vserial;
	&read_env_file($virtualmin_license_file, \%vserial);
	if ($vserial{'SerialNumber'} eq 'GPL' ||
	    $vserial{'LicenseKey'} eq 'GPL') {
		return (1, $text{'licence_gpl_repos_warning'});
		}
	}
# Validate the new license
if (!$nocheck) {
	&$first_print(&text("licence_validating", "<tt>$key</tt>"));
	$hostid = &get_licence_hostid();
	($status, $exp, $err, $doms, $server) =
		&licence_scheduled($hostid, $serial, $key);
	if ($status) {
		$err = lcfirst($err);
		if ($status == 2) {
			&$second_print("$text{'licence_evalidating'} : $err");
			}
		else {
			&$second_print("$text{'licence_ecanvalidating'} : $err");
			}
		return (1, undef);
		}
	else {
		my $dcount = ($doms <= 0 ? 0 : $doms);
		if ($dcount == 0) {
			&$second_print(&text("licence_valid_unlim", $exp));
			}
		else {
			&$second_print(&text("licence_valid", $dcount, $exp));
			}
		}
	}

# Update Virtualmin license file before running repo setup which relies on it
# to perform automatic repo setup
&$first_print($text{'licence_updfile'});
&lock_file($virtualmin_license_file);
%lfile = ( 'SerialNumber' => $serial,
           'LicenseKey' => $key );
&write_env_file($virtualmin_license_file, \%lfile);
&unlock_file($virtualmin_license_file);
&$second_print($text{'setup_done'});

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
	&$second_print($text{'setup_done'});
	}
# Update DEB or RPM repos, and preserve the correct branch previously chosen
# by the user
elsif (!$no_repos) {
	my $repo_branch = &detect_virtualmin_repo_branch();
	$repo_branch ||= 'stable';
	&$first_print($text{"licence_updating_repo_${repo_branch}_pro"});
	my ($st, $err, $out) = &setup_virtualmin_repos($repo_branch);
	if (!$st) {
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print(&text('setup_postfailure',
			       &setup_repos_error($err || $out)));
		}
	}

if (defined($status) && $status == 0) {
	# Update the status file
	if (!$nocheck) {
		&read_file($licence_status, \%licence);
		# Update the licence status based on the new licence as
		# Virtualmin server can block on too many requests
		$licence{'status'} = $status;
		$licence{'expiry'} = $exp;
		$licence{'doms'} = $doms;
		$licence{'servers'} = $server;
		&update_licence_from_site(\%licence);
		&write_file($licence_status, \%licence);
		}
	}
}

1;

