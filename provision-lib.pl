# Functions for talking to a remote provisioning system

sub list_provision_features
{
return ('dns', 'mysql');
}

sub check_provision_login
{
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
	       join("", map { "&".$_."=".&urlize($args->{$_}) } (keys %$args).
	       ($multiline ? "&multiline=&perl=" : ""),
	       \$out, \$err, undef,
	       $config{'provision_ssl'},
	       $config{'provision_user'},
	       $config{'provision_pass'},
	       60, 0, 1);
if ($err) {
	return (0, $err);
	}
}

1;

