# Functions for talking to a remote provisioning system

sub list_provision_features
{
return ('dns', 'mysql');
}

# check_provision_login()
# Validate that the selected provisioning system can be used and has the needed
# features.
sub check_provision_login
{
my ($ok, $msg) = &provision_api_call("list-provision-features", {}, 1);
if (!$ok) {
	# Request failed
	return $msg;
	}
if (ref($msg) ne 'ARRAY') {
	return "Invalid response from list-provision-features : $msg";
	}
my %feats = map { $_->{'name'}, $_->{'values'} } @$msg;
if ($config{'provision_dns'}) {
	# Make sure DNS is supported
	$feats{'dns'} || return $text{'provision_edns'};
	$feats{'dns'}->{'limit'} || return $text{'provision_ednslimit'};
	$feats{'dns'}->{'systems'} || return $text{'provision_ednssystems'};
	}
if ($config{'provision_mysql'}) {
	# Make sure MySQL logins and DBs are supported
	$feats{'mysql'} && $feats{'mysqldb'} ||
		return $text{'provision_emysql'};
	$feats{'mysql'}->{'limit'} && $feats{'mysqldb'}->{'limit'} ||
		return $text{'provision_emysqllimit'};
	$feats{'mysql'}->{'systems'} && $feats{'mysqldb'}->{'systems'} ||
		return $text{'provision_emysqlsystems'};
	}
return undef;
}

# provision_api_call(command, &args, multiline)
# Calls an API program on the configured provisioning server, and returns 
# a status code (0=failed, 1=success) and either an error message, text output
# or a perl object (in multiline mode).
sub provision_api_call
{
my ($cmd, $args, $multiline) = @_;
my ($out, $err);
&http_download($config{'provision_server'}, $config{'provision_port'},
	       "/server-manager/remote.cgi?program=".&urlize($cmd).
	       join("", map { "&".$_."=".&urlize($args->{$_}) } (keys %$args)).
	       ($multiline ? "&multiline=&perl=" : ""),
	       \$out, \$err, undef,
	       $config{'provision_ssl'},
	       $config{'provision_user'},
	       $config{'provision_pass'},
	       60, 0, 1);
if ($err) {
	return (0, $err);
	}
if ($multiline) {
	# Parse perl format
	my $rv = eval $out;
	if ($@) {
		return (0, "Invalid response format : $@");
		}
	if ($rv->{'status'} ne 'success') {
		return (0, $rv->{'error'} || "$cmd failed");
		}
	return (1, $rv->{'data'});
	}
else {
	# Plain text format
	return (1, $out);
	}
}

# set_provision_features(&domain)
# Set the provision_* fields in a domain based on what provisioning features
# are currently configured, to indicate that they should be created remotely.
sub set_provision_features
{
my ($d) = @_;
foreach my $f (&list_provision_features()) {
	if ($config{'provision_'.$f}) {
		$d->{'provision_'.$f} = 1;
		}
	}
}

1;

