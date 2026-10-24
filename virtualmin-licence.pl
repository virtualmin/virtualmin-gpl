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
my $params = 'id='.&urlize($hostid).'&serial='.&urlize($key);
&http_post($virtualmin_host_domain, $virtualmin_licence_port, $virtualmin_licence_page,
	   $params, \$out, \$error, undef, $virtualmin_licence_ssl, undef, undef, 10);
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

# change_licence(serial, key, [nocheck], [force-update], [no-repos], [offline])
# Changes credentials and normally validates the license and sets up repositories.
# Offline mode only replaces local credentials and invalidates cached status.
sub change_licence
{
my ($serial, $key, $nocheck, $force_update, $no_repos, $offline) = @_;
# Offline replacement shares local writes but skips loading and validation.
if ($offline) {
	return (1, 'Offline license credentials must contain only letters, numbers, underscores or hyphens')
		if (!defined($serial) || !defined($key) ||
		    $serial !~ /\A[A-Za-z0-9_-]+\z/ || $key !~ /\A[A-Za-z0-9_-]+\z/);
	($nocheck, $force_update, $no_repos) = (1, 1, 1);
	}
else {
	&require_licence($force_update);
	}
my ($status, $exp, $err, $doms, $server, $hostid);
# Keep the previous serial to find other copies of it below
my %vserial;
&read_env_file($virtualmin_license_file, \%vserial);
# Display a warning to GPL user trying to apply a license instead of
# properly upgrading. Can be bypassed by using --force-update flag
if (!$force_update) {
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
if ($webmin::config{'upsource'} =~ /(?:$upgrade_virtualmin_host_all)(?=[:\/\s]|$)/) {
	&$first_print("Updating Webmin module updates URL ..");
	&lock_file($webmin::module_config_file);
	@upsource = split(/\t/, $webmin::config{'upsource'});
	foreach my $u (@upsource) {
		if ($u =~ /^(http|https|ftp):\/\/([^:]+):([^\@]+)\@((?:$upgrade_virtualmin_host_all)(?=[:\/\s]|$).*)$/) {
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
# Systems upgraded through the web interface also keep the serial and key
# as Webmin update credentials
if ($vserial{'SerialNumber'} ne '' &&
    $webmin::config{'upuser'} eq $vserial{'SerialNumber'}) {
	&lock_file($webmin::module_config_file);
	$webmin::config{'upuser'} = $serial;
	$webmin::config{'uppass'} = $key;
	&webmin::save_module_config();
	&unlock_file($webmin::module_config_file);
	}

# Offline mode updates existing repository credentials without running setup.
return &change_licence_offline($serial, $key) if ($offline);

if (defined($status) && $status == 0) {
	# Update the status file
	if (!$nocheck) {
		&read_file($licence_status, \%licence);
		# Update the license status based on the new license as
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

# change_licence_offline(serial, key) finishes the offline change_licence path.
# Update only the known Virtualmin repository files and discard cached status.
sub change_licence_offline
{
my ($serial, $key) = @_;
foreach my $file (grep { $_ && -f $_ }
	($virtualmin_apt_auth_file, $virtualmin_yum_repo, $virtualmin_apt_repo)) {
	&lock_file($file);
	my $data = &read_file_contents($file);
	die "Cannot read license repository configuration: $file\n" if (!defined($data));
	my $old = $data;
	# RPM and older APT entries carry credentials in their repository URL.
	$data =~ s{((?:https?|ftp)://)[^\s/\@]+:[^\s/\@]+\@((?:$upgrade_virtualmin_host_all)(?=[:/\s]|$))}{$1$serial:$key\@$2}g;
	# Current APT entries use the separate Virtualmin authentication file.
	$data =~ s{(^[ \t]*machine\s+(?:https?://)?(?:$upgrade_virtualmin_host_all)(?:[/:]\S*)?\s+login\s+)\S+(\s+password\s+)\S+}{$1$serial$2$key}gm;
	&write_file_contents($file, $data) if ($data ne $old);
	&unlock_file($file);
	}
&lock_file($licence_status);
&write_file($licence_status, { status => 1, last => 0,
	err => $text{'licence_offline_changed'} });
&unlock_file($licence_status);
return (0, undef);
}

1;
