# Functions for setting up DKIM signing

$debian_dkim_config = "/etc/dkim-filter.conf";
$debian_dkim_default = "/etc/default/dkim-filter";
$redhat_dkim_config = "/etc/sysconfig/dkim-milter";

# check_dkim()
# Returns undef if all the needed commands for DKIM are installed, or an error
# message if not.
sub check_dkim
{
&foreign_require("init");
if ($gconfig{'os_type'} eq 'debian-linux') {
	# Look for milter config file
	return &text('dkim_econfig', "<tt>$debian_dkim_config</tt>")
		if (!-r $debian_dkim_config);
	return &text('dkim_einit', "<tt>dkim-filter</tt>")
		if (!&init::action_status("dkim-filter"));
	}
elsif ($gconfig{'os_type'} eq 'redhat-linux') {
	# Look for mfilter sysconfig file and init script
	return &text('dkim_econfig', "<tt>$redhat_dkim_config</tt>")
		if (!-r $redhat_dkim_config);
	return &text('dkim_einit', "<tt>dkim-milter</tt>")
		if (!&init::action_status("dkim-milter"));
	}
else {
	# Not supported on this OS
	return $text{'dkim_eos'};
	}

# Check mail server
if ($config{'mail_system'} > 1) {
	return $text{'dkim_emailsystem'};
	}
return undef;
}

# can_install_dkim()
# Returns 1 if DKIM package installation is supported on this OS
sub can_install_dkim
{
if ($gconfig{'os_type'} eq 'debian-linux' ||
    $gconfig{'os_type'} eq 'redhat-linux') {
	&foreign_require("software", "software-lib.pl");
	return defined(&software::update_system_install);
	}
return 0;
}

# get_dkim_config()
# Returns a hash containing details of the DKIM configuration and status.
# Keys are :
# enabled - Set to 1 if postfix is setup to use DKIM
# domain - Domain in which DKIM records are created
# selector - Record within the domain for the key
sub get_dkim_config
{
&foreign_require("init");
my %rv;

# Check if filter is running
if ($gconfig{'os_type'} eq 'debian-linux') {
	# Read Debian dkim config file
	my $conf = &get_debian_dkim_config($debian_dkim_config);
	$rv{'enabled'} = &init::action_status("dkim-filter") == 2;
	$rv{'domain'} = $conf{'Domain'};
	$rv{'selector'} = $conf{'Selector'};
	$rv{'keyfile'} = $conf{'KeyFile'};

	# Read defaults file that specifies port
	my %def;
	&read_env_file($debian_dkim_default, \%def);
	if ($def{'SOCKET'} =~ /^inet:(\d+)/) {
		$rv{'port'} = $1;
		}
	elsif ($def{'SOCKET'} =~ /^local:([^:]+)/) {
		$rv{'socket'} = $1;
		}
	else {
		$rv{'enabled'} = 0;
		}
	}
elsif ($gconfig{'os_type'} eq 'redhat-linux') {
	# XXX
	}

# Check mail server
&require_mail();
if ($config{'mail_system'} == 0) {
	# Postfix config
	my $milters = &postfix::get_real_value("smtpd_milters");
	if ($rv{'port'}) {
		if ($milters !~ /inet:localhost:(\d+)/ || $1 != $rv{'port'}) {
			$rv{'enabled'} = 0;
			}
		}
	elsif ($rv{'socket'}) {
		if ($milters !~ /local:([^\s,:]+)/ || $1 ne $rv{'socket'}) {
			$rv{'enabled'} = 0;
			}
		}
	}
elsif ($config{'mail_system'} == 1) {
	# Sendmail config
	# XXX
	}

return \%rv;
}

# get_debian_dkim_config(file)
# Returns the config file as seen on Debian into as hash ref
sub get_debian_dkim_config
{
my ($file) = @_;
my %conf;
open(DKIM, $file) || return undef;
while(my $l = <DKIM>) {
	$l =~ s/#.*$//;
	if ($l =~ /^\s*(\S+)\s+(\S.*)/) {
		$conf{$1} = $2;
		}
	}
close(DKIM);
return \%conf;
}

1;

