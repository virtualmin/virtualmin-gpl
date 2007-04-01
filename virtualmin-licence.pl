# Defines the function for validating the Virtualmin licence, by making an
# HTTP request to the licence CGI.

$virtualmin_licence_host = "software.virtualmin.com";
$virtualmin_licence_port = 80;
$virtualmin_licence_prog = "/cgi-bin/vlicence.cgi";
$virtualmin_licence_ssl = 0;

# licence_scheduled(hostid)
sub licence_scheduled
{
local ($out, $error);
&read_env_file($virtualmin_license_file, \%serial);
&http_download($virtualmin_licence_host,
	       $virtualmin_licence_port,
	       "$virtualmin_licence_prog?id=$_[0]&serial=$serial{'LicenseKey'}",
	       \$out, \$error, undef, $virtualmin_licence_ssl);
return (2, undef, "Failed to contact licence server : $error") if ($error);
return $out =~ /^EXP\s+(\S+)\s+(\S+)/ ?
	(3, $1, "The licence for this server expired on $1", $2) :
       $out =~ /^ERR\s+(.*)/ ?
	(2, undef, "An error occurred checking the licence : $1", undef) :
       $out =~ /^OK\s+(\S+)\s+(\S+)/ ? (0, $1, undef, $2) :
	(1, undef, "No valid licence was found for your host ID $_[0] and serial number $serial{'LicenseKey'}", undef);
}

1;

