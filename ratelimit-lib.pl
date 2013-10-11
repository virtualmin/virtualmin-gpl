# Functions for setting up email rate limits

sub get_ratelimit_type
{
if ($gconfig{'os_type'} eq 'debian-linux') {
	# Debian or Ubuntu packages
	return 'debian';
	}
elsif ($gconfig{'os_type'} eq 'redhat-linux') {
	# Redhat / CentOS packages
	return 'redhat';
	}
return undef;	# Not supported
}

sub get_ratelimit_config_file
{
return &get_ratelimit_type() eq 'redhat' ? '/etc/mail/greylist.conf' :
       &get_ratelimit_type() eq 'debian' ? '/etc/milter-greylist/greylist.conf'
					 : undef;
}

sub get_ratelimit_init_name
{
return 'milter-greylist';
}

# check_ratelimit()
# Returns undef if all the commands needed for ratelimiting are installed
sub check_ratelimit
{
&foreign_require("init");
if (!&get_ratelimit_type()) {
	# Not supported on this OS
	return $text{'ratelimit_eos'};
	}
my $config_file = &get_ratelimit_config_file();
return &text('ratelimit_econfig', "<tt>$config_file</tt>")
	if (!-r $config_file);
my $init = &get_ratelimit_init_name();
return &text('ratelimit_einit', "<tt>$init</tt>")
	if (!&init::action_status($init));

# Check mail server
&require_mail();
if ($config{'mail_system'} > 1) {
	return $text{'ratelimit_emailsystem'};
	}
elsif ($config{'mail_system'} == 1) {
	-r $sendmail::config{'sendmail_mc'} ||
		return $text{'ratelimit_esendmailmc'};
	}
return undef;
}

# can_install_ratelimit()
# Returns 1 if milter-greylist package installation is supported on this OS
sub can_install_ratelimit
{
if ($gconfig{'os_type'} eq 'debian-linux' ||
    $gconfig{'os_type'} eq 'redhat-linux') {
	&foreign_require("software", "software-lib.pl");
	return defined(&software::update_system_install);
	}
return 0;
}

# install_ratelimit_package()
# Attempt to install milter-greylist, outputting progress messages
sub install_ratelimit_package
{
&foreign_require("software", "software-lib.pl");
my $pkg = 'milter-greylist';
my @inst = &software::update_system_install($pkg);
return scalar(@inst) || !&check_ratelimit();
}

1;
