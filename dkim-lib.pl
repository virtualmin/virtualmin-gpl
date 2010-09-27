# Functions for setting up DKIM signing

$debian_dkim_config = "/etc/dkim-filter.conf";
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
}

1;

