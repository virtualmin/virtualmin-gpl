# Defines the function for validating the Virtualmin licence, by making an
# HTTP request to the licence CGI.

$virtualmin_licence_host = "software.virtualmin.com";
$virtualmin_licence_port = 80;
$virtualmin_licence_prog = "/cgi-bin/vlicence.cgi";
$virtualmin_licence_ssl = 0;
$virtualmin_renewal_url = $config{'renewal_url'} ||
			  "http://www.virtualmin.com/shop";

# licence_scheduled(hostid, [serial, key], [vps-type])
# Returns a status code (0=OK, 1=Invalid, 2=Down, 3=Expired), the expiry date,
# an error message, the number of domains max, the number of servers max,
# the number of servers used, and the auto-renewal flag
sub licence_scheduled
{
local ($hostid, $serial, $key, $vps) = @_;
local ($out, $error);
local @doms = grep { !$_->{'alias'} } &list_domains();
&read_env_file($virtualmin_license_file, \%serial);
$key ||= $serial{'LicenseKey'};
&http_download($virtualmin_licence_host,
	       $virtualmin_licence_port,
	       "$virtualmin_licence_prog?id=$hostid&".
		"serial=$key&doms=".scalar(@doms)."&vps=$vps",
	       \$out, \$error, undef, $virtualmin_licence_ssl,
	       undef, undef, 0, 0, 1);
return (2, undef, "Failed to contact licence server : $error") if ($error);
return $out =~ /^EXP\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)/ ?
	(3, $1, "The licence for this server expired on $1", $2, $3, $4) :
       $out =~ /^ERR\s+(.*)/ ?
	(2, undef, "An error occurred checking the licence : $1", undef) :
       $out =~ /^OK\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\d+)/ ?
	(0, $1, undef, $2, $3, $4, $5) :	# Auto-renewal flag
       $out =~ /^OK\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)/ ?
	(0, $1, undef, $2, $3, $4) :
	(1, undef, "No valid licence was found for your host ID $_[0] and serial number $serial{'LicenseKey'}", undef);
}

1;

