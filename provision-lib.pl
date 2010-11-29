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
if (ref($msg) ne 'HASH') {
	return "Invalid response from list-provision-features : $msg";
	}
if ($config{'provision_dns'}) {
	# Make sure DNS is supported
	$msg->{'dns'} || return $text{'provision_edns'};
	$msg->{'dns'}->{'limit'} || return $text{'provision_ednslimit'};
	$msg->{'dns'}->{'systems'} || return $text{'provision_ednssystems'};
	}
if ($config{'provision_mysql'}) {
	# Make sure MySQL logins and DBs are supported
	$msg->{'mysql'} && $msg->{'mysqldb'} ||
		return $text{'provision_emysql'};
	$msg->{'mysql'}->{'limit'} && $msg->{'mysqldb'}->{'limit'} ||
		return $text{'provision_emysqllimit'};
	$msg->{'mysql'}->{'systems'} && $msg->{'mysqldb'}->{'systems'} ||
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
	return (1, $rv);
	}
else {
	# Plain text format
	return (1, $out);
	}
}

1;

