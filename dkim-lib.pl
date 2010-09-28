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

# install_dkim_package()
# Attempt to install DKIM filter, outputting progress messages
sub install_dkim_package
{
&foreign_require("software", "software-lib.pl");
my $pkg = $gconfig{'os_type'} eq 'debian-linux' ? 'dkim-filter' :
	  $gconfig{'os_type'} eq 'redhat-linux' ? 'dkim-milter' :
						  'dkim';
my @inst = &software::update_system_install($pkg);
return scalar(@inst) || !&check_dkim();
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

# obtain_lock_dkim()
# Locks all DKIM config files
sub obtain_lock_dkim
{
foreach my $f (&get_dkim_config_files()) {
	&lock_file($f);
	}
}

# release_lock_dkim()
# Remove locks on all DKIM config files
sub release_lock_dkim
{
foreach my $f (reverse(&get_dkim_config_files())) {
	&unlock_file($f);
	}
}

# get_dkim_config_files()
# Returns a list of all DKIM-related config files
sub get_dkim_config_files
{
if ($gconfig{'os_type'} eq 'debian-linux') {
	return ( $debian_dkim_config, $debian_dkim_default );
	}
elsif ($gconfig{'os_type'} eq 'redhat-linux') {
	return ( $redhat_dkim_config );
	}
else {
	return ( );
	}
}

# enable_dkim()
# Perform all the steps needed to enable DKIM
sub enable_dkim
{
my ($dkim) = @_;
&foreign_require("webmin");
&foreign_require("init");

# Generate private key
if (!$dkim->{'keyfile'} || !-r $dkim->{'keyfile'}) {
	my $size = $config{'key_size'} || $webmin::default_key_size;
	$dkim->{'keyfile'} ||= "/etc/dkim.key";
	&$first_print(&text('dkim_newkey', "<tt>$dkim->{'keyfile'}</tt>"));
	my $out = &backquote_logged("openssl genrsa -out ".
		quotemeta($dkim->{'keyfile'})." $size 2>&1 </dev/null");
	if ($?) {
		&$second_print(&text('dkim_enewkey',
				"<tt>".&html_escape($out)."</tt>"));
		return 0;
		}
	&$second_print($text{'setup_done'});
	}

# Get the public key
&$first_print(&text('dkim_pubkey', "<tt>$dkim->{'keyfile'}</tt>"));
my $pubkey = &backquote_command(
	"openssl rsa -in ".quotemeta($dkim->{'keyfile'}).
	" -pubout -outform PEM 2>/dev/null");
if ($? || $pubkey !~ /BEGIN\s+PUBLIC\s+KEY/) {
	&$second_print(&text('dkim_epubkey',
			     "<tt>".&html_escape($pubkey)."</tt>"));
	return 0;
	}
&$second_print($text{'setup_done'});

# Add public key to DNS domain
&$first_print(&text('dkim_dns', "<tt>$dkim->{'domain'}</tt>"));
my $z = &get_bind_zone($dkim->{'domain'});
if (!$z) {
	&$second_print($text{'dkim_ednszone'});
	return 0;
	}
my $file = &bind8::find("file", $z->{'members'});
my $fn = $file->{'values'}->[0];
my @recs = &bind8::read_zone_file($fn, $dkim->{'domain'});
my $withdot = $dkim->{'domain'}.'.';
my $dkname = '_domainkey.'.$withdot;
my ($dkrec) = grep { $_->{'name'} eq $dkname &&
		     $_->{'type'} eq 'TXT' } @recs;
my $changed = 0;
if (!$dkrec) {
	&bind8::create_record($fn, $dkname, undef, 'IN', 'TXT',
			      '"t=y; o=-;"');
	$changed++;
	}
my $selname = $dkim->{'selector'}.'.'.$dkname;
my ($selrec) = grep { $_->{'name'} eq $selname && 
		      $_->{'type'} eq 'TXT' } @recs;
if (!$selrec) {
	# XXX what if changed?
	&bind8::create_record($fn, $selname, undef, 'IN', 'TXT',
                              '"k=rsa; t=y; p='.$pubkey.'"');
        $changed++;
	}
if ($changed) {
	# XXX DNSSEC?
	&bind8::bump_soa_record($fn, \@recs);
	&$second_print($text{'dkim_dnsadded'});
	}
else {
	&$second_print($text{'dkim_dnsalready'});
	}

# Add domain, key and selector to config file
# XXX

# Enable filter at boot time
# XXX

# Start filter now
# XXX

# Configure Postfix to use filter
# XXX

# Apply Postfix config
# XXX

return 1;
}

1;

