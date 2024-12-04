# Functions for setting up DKIM signing

$debian_dkim_config = "/etc/dkim-filter.conf";
$debian_dkim_default = "/etc/default/dkim-filter";

$redhat_dkim_config = "/etc/mail/dkim-milter/dkim-filter.conf";
$redhat_dkim_default = "/etc/sysconfig/dkim-milter";

$ubuntu_dkim_config = "/etc/opendkim.conf";
$ubuntu_dkim_default = "/etc/default/opendkim";

$centos_dkim_config = "/etc/opendkim.conf";
$centos_dkim_default = "/etc/sysconfig/opendkim";

$freebsd_dkim_config = "/usr/local/etc/mail/opendkim.conf";

$gentoo_dkim_config = "/etc/opendkim/opendkim.conf";

# get_dkim_type()
# Returns either 'ubuntu', 'debian', 'redhat', 'freebsd', 'centos', 'gentoo' or undef
sub get_dkim_type
{
if ($gconfig{'os_type'} eq 'debian-linux' && $gconfig{'os_version'} >= 7) {
	# Debian 7+ uses OpenDKIM
	return 'ubuntu';
	}
elsif ($gconfig{'os_type'} eq 'debian-linux' && $gconfig{'os_version'} >= 6 &&
       !-x "/usr/sbin/dkim-filter") {
	# Debian 6 can use OpenDKIM, unless it is already using dkim-filter
	return 'ubuntu';
	}
elsif ($gconfig{'os_type'} eq 'debian-linux') {
	# Older Debian versions only have dkim-filter
	return 'debian';
	}
elsif ($gconfig{'os_type'} eq 'redhat-linux') {
	if ($gconfig{'os_version'} >= 15 &&
	    !-r $redhat_dkim_config) {
		# Virtualmin provides opendkim now
		return 'centos';
		}
	else {
		# dkim-milter from older CentOS versions
		return 'redhat';
		}
	}
elsif ($gconfig{'os_type'} eq 'freebsd') {
	return 'freebsd';
	}
elsif ($gconfig{'os_type'} eq 'gentoo-linux') {
	return 'gentoo';
	}
return undef;
}

# get_dkim_config_file()
# Returns the path to the DKIM config file
sub get_dkim_config_file
{
return &get_dkim_type() eq 'ubuntu' ? $ubuntu_dkim_config :
       &get_dkim_type() eq 'debian' ? $debian_dkim_config :
       &get_dkim_type() eq 'redhat' ? $redhat_dkim_config :
       &get_dkim_type() eq 'centos' ? $centos_dkim_config :
       &get_dkim_type() eq 'freebsd' ? $freebsd_dkim_config :
       &get_dkim_type() eq 'gentoo' ? $gentoo_dkim_config :
				      undef;
}

# get_dkim_defaults_file()
# Returns the path to the DKIM defaults file
sub get_dkim_defaults_file
{
return &get_dkim_type() eq 'ubuntu' ? $ubuntu_dkim_default :
       &get_dkim_type() eq 'debian' ? $debian_dkim_default :
       &get_dkim_type() eq 'redhat' ? $redhat_dkim_default :
       &get_dkim_type() eq 'centos' ? $centos_dkim_default :
				      undef;
}

# get_dkim_init_name()
# Returns the name of the DKIM init script
sub get_dkim_init_name
{
return &get_dkim_type() eq 'ubuntu' ? 'opendkim' :
       &get_dkim_type() eq 'debian' ? 'dkim-filter' :
       &get_dkim_type() eq 'freebsd' ? 'milter-opendkim' :
       &get_dkim_type() eq 'gentoo' ? 'opendkim' :
       &get_dkim_type() eq 'redhat' ? 'dkim-milter' :
       &get_dkim_type() eq 'centos' ? 'opendkim' : undef;
}

# check_dkim()
# Returns undef if all the needed commands for DKIM are installed, or an error
# message if not.
sub check_dkim
{
&foreign_require("init");
if (!$config{'mail'}) {
	return $text{'dkim_email'};
	}
if (!&get_dkim_type()) {
	# Not supported on this OS
	return $text{'dkim_eos'};
	}
my $config_file = &get_dkim_config_file();
return &text('dkim_econfig', "<tt>$config_file</tt>")
	if (!-r $config_file);
my $init = &get_dkim_init_name();
return &text('dkim_einit', "<tt>$init</tt>")
	if (!&init::action_status($init));

# Check mail server
&require_mail();
if ($mail_system == 1) {
	-r $sendmail::config{'sendmail_mc'} ||
		return $text{'dkim_esendmailmc'};
	}
elsif ($mail_system != 0) {
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
	&foreign_require("software");
	return defined(&software::update_system_install);
	}
return 0;
}

# install_dkim_package()
# Attempt to install DKIM filter, outputting progress messages
sub install_dkim_package
{
&foreign_require("software");
my $pkg = &get_dkim_type() eq 'ubuntu' ? 'opendkim' :
	  &get_dkim_type() eq 'freebsd' ? 'opendkim' :
	  &get_dkim_type() eq 'gentoo' ? 'opendkim' :
	  &get_dkim_type() eq 'debian' ? 'dkim-filter' :
	  &get_dkim_type() eq 'redhat' ? 'dkim-milter' :
	  &get_dkim_type() eq 'centos' ? 'opendkim' :
					 'dkim';
my @inst = &software::update_system_install($pkg);
return scalar(@inst) || !&check_dkim();
}

# get_dkim_config()
# Returns a hash containing details of the DKIM configuration and status.
# Keys are :
# enabled - Set to 1 if postfix is setup to use DKIM
# selector - Record within the domain for the key
# extra - Additional domains to enable for
# keyfile - Private key file
sub get_dkim_config
{
&foreign_require("init");
my %rv;

# Check if filter is running
my $dkim_config = &get_dkim_config_file();
my $dkim_defaults = &get_dkim_defaults_file();
my $init = &get_dkim_init_name();
if (&get_dkim_type() eq 'debian' || &get_dkim_type() eq 'ubuntu') {
	# Read Debian opendkim config file
	my $conf = &get_open_dkim_config($dkim_config);
	$rv{'enabled'} = &init::action_status($init) == 2;
	$rv{'selector'} = $conf->{'Selector'};
	$rv{'keyfile'} = $conf->{'KeyFile'};

	# Read defaults file that specifies port
	my %def;
	&read_env_file($dkim_defaults, \%def);
	if ($def{'SOCKET'} =~ /^inet:(\d+)/) {
		$rv{'port'} = $1;
		}
	elsif ($def{'SOCKET'} =~ /^local:([^:]+)/) {
		$rv{'socket'} = $1;
		}
	else {
		$rv{'enabled'} = 0;
		}

	# Parse defaults option to get sign/verify mode
	if ($def{'DAEMON_OPTS'} =~ /-b\s*(\S+)/) {
		my $mode = $1;
		$rv{'sign'} = $mode =~ /s/ ? 1 : 0;
		$rv{'verify'} = $mode =~ /v/ ? 1 : 0;
		}
	else {
		$rv{'sign'} = 1;
		$rv{'verify'} = 1;
		}
	}
elsif (&get_dkim_type() eq 'redhat') {
	# Read Fedora dkim-milter config file
	my $conf = &get_open_dkim_config($dkim_config);
	$rv{'enabled'} = &init::action_status($init) == 2;
	$rv{'selector'} = $conf->{'Selector'};
	$rv{'keyfile'} = $conf->{'KeyFile'};

	# Read defaults file that specifies port
	my %def;
	&read_env_file($dkim_defaults, \%def);
	if ($def{'SOCKET'} =~ /^inet:(\d+)/) {
		$rv{'port'} = $1;
		}
	elsif ($def{'SOCKET'} =~ /^local:([^:]+)/) {
		$rv{'socket'} = $1;
		}
	else {
		# Assume default socket
		$rv{'socket'} = "/var/run/dkim-milter/dkim-milter.sock";
		}

	# Parse defaults option to get sign/verify mode
	if ($def{'EXTRA_FLAGS'} =~ /-b\s*(\S+)/) {
		my $mode = $1;
		$rv{'sign'} = $mode =~ /s/ ? 1 : 0;
		$rv{'verify'} = $mode =~ /v/ ? 1 : 0;
		}
	else {
		$rv{'sign'} = 1;
		$rv{'verify'} = 1;
		}
	}
elsif (&get_dkim_type() eq 'freebsd' || &get_dkim_type() eq 'gentoo') {
	# Read dkim config file
	my $conf = &get_open_dkim_config($dkim_config);
	$rv{'enabled'} = &init::action_status($init) == 2;
	$rv{'selector'} = $conf->{'Selector'};
	$rv{'keyfile'} = $conf->{'KeyFile'};
	
	# Work out socket from config file
	if ($conf->{'Socket'} =~ /^inet:(\d+)/) {
		$rv{'port'} = $1;
		}
	elsif ($conf->{'Socket'} =~ /^local:([^:]+)/) {
		$rv{'socket'} = $1;
		}
	else {
		$rv{'enabled'} = 0;
		}
	
	# Get sign/verify mode
	if ($conf->{'Mode'} =~ /\S+/) {
		$rv{'sign'} = $conf->{'Mode'} =~ /s/ ? 1 : 0;
		$rv{'verify'} = $conf->{'Mode'} =~ /v/ ? 1 : 0;
		}
	else {
		$rv{'sign'} = 1;
		$rv{'verify'} = 1;
		} 
	}
elsif (&get_dkim_type() eq 'centos') {
	# Read CentOS 7+ opendkim config file
	my $conf = &get_open_dkim_config($dkim_config);
	$rv{'enabled'} = &init::action_status($init) == 2;
	$rv{'selector'} = $conf->{'Selector'};
	$rv{'keyfile'} = $conf->{'KeyFile'};

	# Work out socket from config file
	if ($conf->{'Socket'} =~ /^inet:(\d+)/) {
		$rv{'port'} = $1;
		}
	elsif ($conf->{'Socket'} =~ /^local:([^:]+)/) {
		$rv{'socket'} = $1;
		}
	else {
		$rv{'enabled'} = 0;
		}

	# Parse defaults option to get sign/verify mode
	my %def;
	&read_env_file($dkim_defaults, \%def);
	if ($def{'OPTIONS'} =~ /-b\s*(\S+)/) {
		my $mode = $1;
		$rv{'sign'} = $mode =~ /s/ ? 1 : 0;
		$rv{'verify'} = $mode =~ /v/ ? 1 : 0;
		}
	else {
		$rv{'sign'} = 1;
		$rv{'verify'} = 1;
		}
	}

# Check mail server
&require_mail();
if ($mail_system == 0) {
	# Postfix config
	my $wantmilter = $rv{'port'} ? "inet:(localhost|127\.0\.0\.1):$rv{'port'}" :
			 $rv{'socket'} ? "local:$rv{'socket'}" : "";
	my $milters = &postfix::get_real_value("smtpd_milters");
	if ($wantmilter && $milters !~ /$wantmilter/) {
		$rv{'enabled'} = 0;
		}
	}
elsif ($mail_system == 1) {
	# Sendmail config
	my $wantmilter = $rv{'port'} ? "inet:$rv{'port'}\@(localhost|127\.0\.0\.1)" :
			 $rv{'socket'} ? "local:$rv{'socket'}" : "";
	my @feats = &sendmail::list_features();
	my ($milter) = grep { $_->{'text'} =~ /INPUT_MAIL_FILTER/ &&
			      $_->{'text'} =~ /$wantmilter/ } @feats;
	if (!$milter) {
		$rv{'enabled'} = 0;
                }
	}

# Add extra domains
$rv{'extra'} = [ split(/\s+/, $config{'dkim_extra'}) ];
$rv{'alldns'} = $config{'dkim_alldns'} || 0;
$rv{'exclude'} = [ split(/\s+/, $config{'dkim_exclude'}) ];

# Work out key size
if ($rv{'keyfile'} && -r $rv{'keyfile'}) {
	$rv{'size'} = &get_key_size($rv{'keyfile'});
	}

$rv{'enabled'} = 0 if (!$rv{'selector'});
return \%rv;
}

# get_open_dkim_config(file)
# Returns the config file as seen on Debian into as hash ref
sub get_open_dkim_config
{
my ($file) = @_;
my %conf;
open(DKIM, "<".$file) || return undef;
while(my $l = <DKIM>) {
	$l =~ s/#.*$//;
	if ($l =~ /^\s*(\S+)\s+(\S.*)/) {
		$conf{$1} = $2;
		}
	}
close(DKIM);
return \%conf;
}

# save_open_dkim_config(file, directive, value)
# Update a value in the Debian-style config file
sub save_open_dkim_config
{
my ($file, $name, $value) = @_;
my $lref = &read_file_lines($file);
if (defined($value)) {
	# Change value
	my $found = 0;
	foreach my $l (@$lref) {
		if ($l =~ /^\s*(\S+)\s*/ && $1 eq $name) {
			$l = $name." ".$value;
			$found = 1;
			last;
			}
		}

	# Change commented value
	if (!$found) {
		foreach my $l (@$lref) {
			if ($l =~ /^\s*#+\s*(\S+)\s*/ && $1 eq $name) {
				$l = $name." ".$value;
				$found = 1;
				last;
				}
			}
		}

	# Add to end
	if (!$found) {
		push(@$lref, "$name $value");
		}
	}
else {
	# Comment out if set
	foreach my $l (@$lref) {
		if ($l =~ /^\s*(\S+)\s*/ && $1 eq $name) {
			$l = "# ".$l;
			}
		}
	}
&flush_file_lines($file);
}

# enable_dkim(&dkim, [force-new-key], [key-size])
# Perform all the steps needed to enable DKIM
sub enable_dkim
{
my ($dkim, $newkey, $size) = @_;
&foreign_require("webmin");
&foreign_require("init");

# Find domains that we can enable DKIM for (those with mail and DNS)
&$first_print($text{'dkim_domains'});
my @alldoms = &list_domains();
my @doms = grep { &has_dkim_domain($_, $dkim) } @alldoms;
if (@doms && @{$dkim->{'extra'}}) {
	&$second_print(&text('dkim_founddomains3', scalar(@doms),
			     scalar(@{$dkim->{'extra'}})));
	}
elsif (@doms) {
	&$second_print(&text('dkim_founddomains', scalar(@doms)));
	}
elsif (@{$dkim->{'extra'}}) {
	&$second_print(&text('dkim_founddomains2',
			     scalar(@{$dkim->{'extra'}})));
	}
else {
	&$second_print($text{'dkim_nodomains'});
	return 0;
	}

# Generate private key
if (!$dkim->{'keyfile'} || !-r $dkim->{'keyfile'} || $newkey) {
	$size ||= 2048;
	$dkim->{'keyfile'} ||= "/etc/dkim.key";
	&$first_print(&text('dkim_newkey', "<tt>$dkim->{'keyfile'}</tt>"));
	my ($ok, $out) = &generate_dkim_key($size);
	if (!$ok) {
		&$second_print(&text('dkim_enewkey',
				"<tt>".&html_escape($out)."</tt>"));
		return 0;
		}
	&open_lock_tempfile(KEY, ">$dkim->{'keyfile'}");
	&print_tempfile(KEY, $out);
	&close_tempfile(KEY);
	&$second_print($text{'setup_done'});
	}

# Make sure key has the right permissions
&set_dkim_keyfile_permissions($dkim->{'keyfile'});

# Get the public key
&$first_print(&text('dkim_pubkey', "<tt>$dkim->{'keyfile'}</tt>"));
my $pubkey = &get_dkim_dns_pubkey($dkim);
if (!$pubkey) {
	&$second_print($text{'dkim_epubkey'});
	return 0;
	}
&$second_print($text{'setup_done'});

# Add domain, key and selector to config file
&$first_print($text{'dkim_config'});
my $dkim_config = &get_dkim_config_file();
if ($dkim_config) {
	# Save domains and key file in config
	&lock_file($dkim_config);
	my $conf = &get_open_dkim_config($dkim_config);
	&save_open_dkim_config($dkim_config, 
		"Selector", $dkim->{'selector'});
	&save_open_dkim_config($dkim_config, 
		"KeyFile", $dkim->{'keyfile'});
	&save_open_dkim_config($dkim_config,
                "Syslog", "yes");
	if ($conf->{'Canonicalization'} eq 'simple') {
		&save_open_dkim_config($dkim_config,
			"Canonicalization", "relaxed/relaxed");
		}

	if (&get_dkim_type() eq 'ubuntu' || &get_dkim_type() eq 'freebsd' ||
	    &get_dkim_type() eq 'centos' || &get_dkim_type() eq 'gentoo') {
		# OpenDKIM version supplied with Ubuntu and Debian 6 supports
		# a domains file
		my $domfile = $conf->{'Domain'};
		if ($domfile !~ /^\//) {
			$domfile = $dkim_config;
			$domfile =~ s/\/[^\/]+$/\/dkim-domains.txt/;
			}
		my $newfile = !-r $domfile;
		&open_lock_tempfile(DOMAINS, ">$domfile");
		foreach my $dom ((map { $_->{'dom'} } @doms),
				 @{$dkim->{'extra'}}) {
			&print_tempfile(DOMAINS, "$dom\n");
			}
		&close_tempfile(DOMAINS);
		if ($newfile) {
			&set_ownership_permissions(undef, undef, 0755,$domfile);
			}
		&save_open_dkim_config($dkim_config,
					 "Domain", $domfile);
		
		# Set socket to listen on interface
		if (!$conf->{'Socket'} ||
		    $conf->{'Socket'} =~ /^local:/) {
		        &save_open_dkim_config($dkim_config,
			    "Socket", "inet:8891\@127.0.0.1");
			}
		}
	else {
		# Work out mapping file
		&save_open_dkim_config($dkim_config, 
			"Domain", undef);
		my $keylist = $conf->{'KeyList'};
		if (!$keylist) {
			$keylist = $dkim_config;
			$keylist =~ s/\/([^\/]+)$/\/keylist/;
			&save_open_dkim_config($dkim_config,
				"KeyList", $keylist);
			}

		# Link key to same directory as mapping file, with selector
		# as filename
		my $selkeyfile = $keylist;
		$selkeyfile =~ s/\/([^\/]+)$/\/$dkim->{'selector'}/;
		if (-e $selkeyfile && !-l $selkeyfile) {
			&$second_print("<b>".&text('dkim_eselfile',
					   "<tt>$selkeyfile</tt>")."</b>");
			return 0;
			}
		&unlink_file($selkeyfile);
		&symlink_file($dkim->{'keyfile'}, $selkeyfile);

		# Create key mapping file
		&create_key_mapping_file(\@doms, $keylist, $selkeyfile,
					 $dkim->{'extra'});
		}
		
	if (&get_dkim_type() eq 'freebsd' || &get_dkim_type() eq 'centos' || &get_dkim_type() eq 'gentoo') {
		# Set milter port to listen on
		if (!$conf->{'Socket'} ||
		    $conf->{'Socket'} =~ /^inet:port/ ||
		    $conf->{'Socket'} =~ /^local:/ &&
		      $mail_system == 0) {
		        # Set socket if not set, or if a local file
		        # and Postfix is in use
		        &save_open_dkim_config($dkim_config,
			    "Socket", "inet:8891\@127.0.0.1");
		        $dkim->{'port'} = 8891;
			}
		elsif ($dkim->{'port'}) {
			# Fix up port if incorrect
			if ($conf->{'Socket'} =~ /^local:/ ||
			    $conf->{'Socket'} =~ /^inet:(\d+)/ &&
			    $1 != $dkim->{'port'}) {
				&save_open_dkim_config($dkim_config,
				  "Socket", "inet:$dkim->{'port'}\@127.0.0.1");
				}
			}
		elsif ($dkim->{'socket'}) {
			if ($conf->{'Socket'} =~ /^inet:/ ||
			    $conf->{'Socket'} =~ /^local:(\S+)/ &&
			    $1 ne $dkim->{'socket'}) {
				&save_open_dkim_config($dkim_config,
				  "Socket", "local:$dkim->{'socket'}");
				}
			}

		# Save sign/verify mode flags
		my $mode = ($dkim->{'sign'} ? "s" : "").
			   ($dkim->{'verify'} ? "v" : "");
		
		&save_open_dkim_config($dkim_config,
			"Mode", $mode);
		}
	&unlock_file($dkim_config);

	# Save list of extra domains
	$config{'dkim_extra'} = join(" ", @{$dkim->{'extra'}});
	$config{'dkim_exclude'} = join(" ", @{$dkim->{'exclude'}});
	$config{'dkim_alldns'} = $dkim->{'alldns'};
	&save_module_config();
	}

my $dkim_defaults = &get_dkim_defaults_file();
if (&get_dkim_type() eq 'debian' || &get_dkim_type() eq 'ubuntu') {
	# Set milter port to listen on
	&lock_file($dkim_defaults);
	my %def;
	&read_env_file($dkim_defaults, \%def);
	if (!$def{'SOCKET'} ||
	    $def{'SOCKET'} =~ /^local:/ && $mail_system == 0) {
		# Set socket in defaults file if missing, or if a local file
		# and Postfix is in use
		$def{'SOCKET'} = "inet:8891\@127.0.0.1";
		$dkim->{'port'} = 8891;
		}

	# Save sign/verify mode flags
	my $flags = $def{'DAEMON_OPTS'};
	my $mode = ($dkim->{'sign'} ? "s" : "").
		   ($dkim->{'verify'} ? "v" : "");
	($flags =~ s/-b\s*(\S+)/-b $mode/) ||
		($flags .= ($flags ? " " : "")."-b $mode");
	$def{'DAEMON_OPTS'} = $flags;

	&write_env_file($dkim_defaults, \%def);
	&unlock_file($dkim_defaults);

	# Add the postfix user to the opendkim Unix group
	&foreign_require("useradmin");
	&obtain_lock_unix();
	my @groups = &useradmin::list_groups();
	my ($g) = grep { $_->{'group'} eq 'opendkim' } @groups;
	if ($g) {
		my $oldg = { %$g };
		my @mems = split(/,/, $g->{'members'});
		if (&indexof("postfix", @mems) < 0) {
			push(@mems, "postfix");
			$g->{'members'} = join(",", @mems);
			&useradmin::set_group_envs($g, 'MODIFY_GROUP', $oldg);
			&useradmin::making_changes();
			&useradmin::modify_group($oldg, $g);
			&useradmin::made_changes();
			}
		}
	&release_lock_unix();
	}
elsif (&get_dkim_type() eq 'centos') {
	# Save sign/verify mode flags
	&lock_file($dkim_defaults);
	my %def;
	my $flags = $def{'OPTIONS'};
	my $mode = ($dkim->{'sign'} ? "s" : "").
		   ($dkim->{'verify'} ? "v" : "");
	($flags =~ s/-b\s*(\S+)/-b $mode/) ||
		($flags .= ($flags ? " " : "")."-b $mode");
	$def{'OPTIONS'} = $flags;

	&write_env_file($dkim_defaults, \%def);
	&unlock_file($dkim_defaults);
	}
elsif (&get_dkim_type() eq 'redhat') {
	# Set milter port to listen on
	&lock_file($dkim_defaults);
	my %def;
	&read_env_file($dkim_defaults, \%def);
	if ($mail_system == 0 && $dkim->{'socket'}) {
		# Force use of tcp socket in defaults file for postfix
		$def{'SOCKET'} = "inet:8891\@127.0.0.1";
		$dkim->{'port'} = 8891;
		delete($dkim->{'socket'});
		}

	# Save sign/verify mode flags
	my $flags = $def{'EXTRA_FLAGS'};
	my $mode = ($dkim->{'sign'} ? "s" : "").
		   ($dkim->{'verify'} ? "v" : "");
	($flags =~ s/-b\s*(\S+)/-b $mode/) ||
		($flags .= ($flags ? " " : "")."-b $mode");
	$def{'EXTRA_FLAGS'} = $flags;
	&write_env_file($dkim_defaults, \%def);
	&unlock_file($dkim_defaults);
	}
&$second_print($text{'setup_done'});

# Add public key to DNS zones for all domains that have DNS and email enabled,
my @dnsdoms = grep { &has_dkim_domain($_, $dkim) } @alldoms;
&add_dkim_dns_records(\@dnsdoms, $dkim);

# Remove from domains that didn't get the DNS records added
my %dnsdoms = map { $_->{'id'}, $_ } @dnsdoms;
my @exdoms = grep { !$dnsdoms{$_->{'id'}} && $_->{'dns'} &&
		    !&copy_alias_records($_) } &list_domains();
if (@exdoms) {
	&remove_dkim_dns_records(\@exdoms, $dkim);
	}

# Enable filter at boot time
&$first_print($text{'dkim_boot'});
my $init = &get_dkim_init_name();
&init::enable_at_boot($init);
&$second_print($text{'setup_done'});

# Re-start filter now
&$first_print($text{'dkim_start'});
&init::stop_action($init);
my ($ok, $out) = &init::start_action($init);
if (!$ok) {
	&$second_print(&text('dkim_estart',
			"<tt>".&html_escape($out)."</tt>"));
	return 0;
	}
&$second_print($text{'setup_done'});

&$first_print($text{'dkim_mailserver'});
&require_mail();
if ($mail_system == 0) {
	# Configure Postfix to use filter
	my $wantmilter = $dkim->{'port'} ? "inet:(localhost|127\.0\.0\.1):$dkim->{'port'}"
					 : "local:$dkim->{'socket'}";
	my $newmilter = $dkim->{'port'} ? "inet:127.0.0.1:$dkim->{'port'}"
					: "local:$dkim->{'socket'}";
	&lock_file($postfix::config{'postfix_config_file'});
	&postfix::set_current_value("milter_default_action", "accept");
	if (!&postfix::get_current_value("milter_protocol")) {
		&postfix::set_current_value("milter_protocol", 2);
		}
	my $milters = &postfix::get_current_value("smtpd_milters");
	if ($milters !~ /$wantmilter/) {
		$milters = $milters ? $milters.",".$newmilter : $newmilter;
		&postfix::set_current_value("smtpd_milters", $milters);
		&postfix::set_current_value("non_smtpd_milters", $milters);
		}
	&unlock_file($postfix::config{'postfix_config_file'});

	# Apply Postfix config
	&postfix::reload_postfix();
	}
elsif ($mail_system == 1) {
	# Configure Sendmail to use filter
	my $wantmilter = $dkim->{'port'} ? "inet:$dkim->{'port'}\@(localhost|127\.0\.0\.1)"
					 : "local:$dkim->{'socket'}";
	my $newmilter = $dkim->{'port'} ? "inet:$dkim->{'port'}\@127.0.0.1"
					: "local:$dkim->{'socket'}";
	&lock_file($sendmail::config{'sendmail_mc'});
	my $changed = 0;
	my @feats = &sendmail::list_features();

	# Check for filter definition
	my ($milter) = grep { $_->{'text'} =~ /INPUT_MAIL_FILTER/ &&
			      $_->{'text'} =~ /$wantmilter/ } @feats;
	if (!$milter) {
		# Add to .mc file
		&sendmail::create_feature({
			'type' => 0,
	    		'text' =>
			  "INPUT_MAIL_FILTER(`dkim-filter', `S=$newmilter')" });
		$changed++;
		}

	# Check for config for filters to call
	my ($def) = grep { $_->{'type'} == 2 &&
			   $_->{'name'} eq 'confINPUT_MAIL_FILTERS' } @feats;
	if ($def) {
		my @filters = split(/,/, $def->{'value'});
		if (&indexof("dkim-filter", @filters) < 0) {
			# Add to existing define
			push(@filters, 'dkim-filter');
			$def->{'value'} = join(',', @filters);
			&sendmail::modify_feature($def);
			$changed++;
			}
		}
	else {
		# Add the define
		&sendmail::create_feature({
			'type' => 2,
			'name' => 'confINPUT_MAIL_FILTERS',
			'value' => 'dkim-filter' });
		$changed++;
		}

	if ($changed) {
		&rebuild_sendmail_cf();
		}
	&unlock_file($sendmail::config{'sendmail_mc'});
	if ($changed) {
		&sendmail::restart_sendmail();
		}
	}
&$second_print($text{'setup_done'});

return 1;
}

# get_dkim_dns_pubkey(&dkim, &domain)
# Returns the public key in a format suitable for inclusion in a DNS record
sub get_dkim_dns_pubkey
{
my ($dkim, $d) = @_;
my $pubkey = &get_dkim_pubkey($dkim, $d);
return undef if (!$pubkey);
$pubkey =~ s/\-+(BEGIN|END)\s+PUBLIC\s+KEY\-+//g;
$pubkey =~ s/\s+//g;
return $pubkey;
}

# get_dkim_pubkey(&dkim, &domain)
# Returns the public key in PEM format
sub get_dkim_pubkey
{
my ($dkim, $d) = @_;
my $keyfile = &get_domain_dkim_key($d) ||
	      $dkim->{'keyfile'};
my $type = &get_ssl_key_type($keyfile, $d->{'ssl_pass'});
my $pubkey = &backquote_command(
        "openssl $type -in ".quotemeta($keyfile).
        " -pubout -outform PEM 2>/dev/null");
if ($? || $pubkey !~ /BEGIN\s+PUBLIC\s+KEY/) {
	return undef;
        }
return $pubkey;
}

# get_dkim_privkey(&dkim, &domain)
# Returns the private key in PEM format
sub get_dkim_privkey
{
my ($dkim, $d) = @_;
my $keyfile = &get_domain_dkim_key($d) ||
	      $dkim->{'keyfile'};
return &read_file_contents($keyfile);
}

# disable_dkim(&dkim)
# Turn off the DKIM filter and mail server integration
sub disable_dkim
{
my ($dkim) = @_;
&foreign_require("init");

# Remove from DNS
my @doms = grep { $_->{'dns'} && !&copy_alias_records($_) } &list_domains();
&remove_dkim_dns_records(\@doms, $dkim);

&$first_print($text{'dkim_unmailserver'});
&require_mail();
if ($mail_system == 0) {
	# Configure Postfix to not use filter
	my $oldmilter = $dkim->{'port'} ? "inet:(localhost|127\.0\.0\.1):$dkim->{'port'}"
					: "local:$dkim->{'socket'}";
	&lock_file($postfix::config{'postfix_config_file'});
	my $milters = &postfix::get_current_value("smtpd_milters");
	if ($milters =~ /$oldmilter/) {
		$milters = join(",", grep { !/$oldmilter/ }
				split(/\s*,\s*/, $milters));
		&postfix::set_current_value("smtpd_milters", $milters);
		&postfix::set_current_value("non_smtpd_milters", $milters);
		}
	&unlock_file($postfix::config{'postfix_config_file'});

	# Apply Postfix config
	&postfix::reload_postfix();
	}
elsif ($mail_system == 1) {
	# Configure Sendmail to not use filter
	my $oldmilter = $dkim->{'port'} ? "inet:$dkim->{'port'}\@(localhost|127\.0\.0\.1)"
					: "local:$dkim->{'socket'}";
	&lock_file($sendmail::config{'sendmail_mc'});
	my @feats = &sendmail::list_features();
	my $changed = 0;

	# Remove from list of milter to call
	my ($def) = grep { $_->{'type'} == 2 &&
			   $_->{'name'} eq 'confINPUT_MAIL_FILTERS' } @feats;
	if ($def) {
		my @filters = split(/,/, $def->{'value'});
		@filters = grep { $_ ne 'dkim-filter' } @filters;
		if (@filters) {
			# Some still left, so update
			$def->{'value'} = join(',', @filters);
			&sendmail::modify_feature($def);
			}
		else {
			# Delete completely
			&sendmail::delete_feature($def);
			}
		$changed++;
		}

	# Remove milter definition
	my ($milter) = grep { $_->{'text'} =~ /INPUT_MAIL_FILTER/ &&
			      $_->{'text'} =~ /$oldmilter/ } @feats;
	if ($milter) {
		&sendmail::delete_feature($milter);
		$changed++;
		}

	if ($changed) {
		&rebuild_sendmail_cf();
		}
	&unlock_file($sendmail::config{'sendmail_mc'});
	if ($changed) {
		&sendmail::restart_sendmail();
		}
	}
&$second_print($text{'setup_done'});

# Stop filter now
&$first_print($text{'dkim_stop'});
my $init = &get_dkim_init_name();
&init::stop_action($init);
&$second_print($text{'setup_done'});

# Disable filter at boot time
&$first_print($text{'dkim_unboot'});
&init::disable_at_boot($init);
&$second_print($text{'setup_done'});

return 1;
}

# can_dkim_domain(&domain, &dkim)
# Returns 1 if a domain should have DKIM enabled by default
sub can_dkim_domain
{
my ($d, $dkim) = @_;
if (!$d->{'dns'}) {
	return 0;
	}
elsif (&copy_alias_records($d)) {
	return 0;
	}
elsif ($dkim->{'alldns'} == 1) {
	# Can be enabled even without email
	return 1;
	}
elsif ($dkim->{'alldns'} == 2) {
	# Cannot be enabled even with email
	return 0;
	}
else {
	# Depends on email feature
	return $d->{'mail'} ? 1 : 0;
	}
}

# has_dkim_domain(&domain, &dkim)
# Returns 1 if a domain must have DKIM enabled
sub has_dkim_domain
{
my ($d, $dkim) = @_;
return 0 if (!$d->{'dns'});
return 0 if (&copy_alias_records($d));
return 0 if ($d->{'dkim_enabled'} eq '0');
return 1 if ($d->{'dkim_enabled'} eq '1');
return &can_dkim_domain($d, $dkim);
}

# update_dkim_domains(&domain, action, [no-dns])
# Updates the list of domains to sign mail for, if needed
sub update_dkim_domains
{
my ($d, $action, $nodns) = @_;
return if (&check_dkim());
&lock_file(&get_dkim_config_file());
my $dkim = &get_dkim_config();
return if (!$dkim || !$dkim->{'enabled'});

# Enable DKIM for all domains with mail
my @doms = grep { &has_dkim_domain($_, $dkim) } &list_domains();
if (($action eq 'setup' || $action eq 'modify')) {
	push(@doms, $d);
	}
elsif ($action eq 'delete') {
	@doms = grep { $_->{'id'} ne $d->{'id'} } @doms;
	}
my %done;
@doms = grep { !$done{$_->{'id'}}++ } @doms;
&set_dkim_domains(\@doms, $dkim);
&unlock_file(&get_dkim_config_file());

# Add or remove DNS records
if ($d->{'dns'} && !&copy_alias_records($d) && !$nodns) {
	if ($action eq 'setup' || $action eq 'modify') {
		&add_dkim_dns_records([ $d ], $dkim);
		}
	elsif ($action eq 'delete') {
		&remove_dkim_dns_records([ $d ], $dkim);
		}
	}
}

# create_key_mapping_file(&domains, mapping-file, key-file, &extra-domains)
# Write out a file of all domains to perform DKIM on
sub create_key_mapping_file
{
my ($doms, $keylist, $keyfile, $extra) = @_;

# Build a list of existing domains with their own keys
my $lref = &read_file_lines($keylist, 1);
my %keymap;
foreach my $l (@$lref) {
	my ($pat, $dom, $file) = split(/:/, $l);
	if (!&same_file($file, $keyfile)) {
		$keymap{$dom} = $file;
		}
	}

# Re-write the whole mapping file
&open_lock_tempfile(KEYLIST, ">$keylist");
foreach my $d (@$doms) {
	&print_tempfile(KEYLIST,
		"*\@".$d->{'dom'}.":".$d->{'dom'}.":".
		($keymap{$d->{'dom'}} || $keyfile)."\n");
	}
foreach my $dname (@$extra) {
	&print_tempfile(KEYLIST,
		"*\@".$dname.":".$dname.":".($keymap{$dname} || $keyfile)."\n");
	}
&close_tempfile(KEYLIST);
&set_ownership_permissions(undef, undef, 0755, $keylist);
}

# set_dkim_domains(&domains, &dkim)
# Configure the DKIM filter to sign mail for the given list of domaisn
sub set_dkim_domains
{
my ($doms, $dkim) = @_;
my $dkim_config = &get_dkim_config_file();
my $init = &get_dkim_init_name();
my $dkim = &get_dkim_config();
if ($dkim_config) {
	my $conf = &get_open_dkim_config($dkim_config);
	my $keylist = $conf->{'KeyList'};
	if ($keylist) {
		# Update key to domain map
		&save_open_dkim_config($dkim_config, 
			"Domain", undef);
		my $selector = $conf->{'Selector'};
		my $keylist = $conf->{'KeyList'};
		my $selkeyfile = $keylist;
		$selkeyfile =~ s/\/([^\/]+)$/\/$selector/;
		&create_key_mapping_file($doms, $keylist, $selkeyfile,
					 $dkim->{'extra'});
		}
	else {
		# Just set list of domains
		my $domfile = $conf->{'Domain'};
		if ($domfile !~ /^\//) {
			$domfile = $dkim_config;
			$domfile =~ s/\/[^\/]+$/\/dkim-domains.txt/;
			}
		&open_lock_tempfile(DOMAINS, ">$domfile");
		foreach my $dom ((map { $_->{'dom'} } @$doms),
				 @{$dkim->{'extra'}}) {
			&print_tempfile(DOMAINS, "$dom\n");
			}
		&close_tempfile(DOMAINS);
		&save_open_dkim_config($dkim_config,
					 "Domain", $domfile);
		}

	# Restart milter
	&foreign_require("init");
	if (&init::action_status($init)) {
		&init::restart_action($init);
		}
	}
}

# get_dkim_domains(&dkim)
# Returns the list of all domains currently being signed for
sub get_dkim_domains
{
my ($dkim) = @_;
my $dkim_config = &get_dkim_config_file();
return ( ) if (!$dkim_config);
my $conf = &get_open_dkim_config($dkim_config);
my $keylist = $conf->{'KeyList'};
my @rv;
if ($keylist) {
	# Use the key mapping file
	my $lref = &read_file_lines($keylist, 1);
	foreach my $l (@$lref) {
		my @w = split(/:/, $l);
		push(@rv, $w[1]);
		}
	}
else {
	# Use a domains file
	my $file = $conf->{'Domain'};
	if ($file && -r $file) {
		my $lref = &read_file_lines($file, 1);
		@rv = grep { !/^#/ && /\S/ } @$lref;
		}
	}
return @rv;
}

# add_dkim_dns_records(&domains, &dkim)
# Add DKIM DNS records to the given list of domains
sub add_dkim_dns_records
{
my ($doms, $dkim) = @_;
my $anychanged = 0;
foreach my $d (@$doms) {
	&$first_print(&text('dkim_dns', "<tt>$d->{'dom'}</tt>"));
	&pre_records_change($d);
	my ($recs, $file) = &get_domain_dns_records_and_file($d);
	if (!$file) {
		&after_records_change($d);
		&$second_print($text{'dkim_ednszone'});
		next;
		}
	&obtain_lock_dns($d);
	my $changed = &add_domain_dkim_record($d, $dkim, $recs, $file);
	if ($changed) {
		my $err = &post_records_change($d, $recs, $file);
		if ($err) {
			&$second_print(&text('dkim_ednsadded', $err));
			}
		else {
			&$second_print($text{'dkim_dnsadded'});
			}
		$anychanged++;
		}
	else {
		&after_records_change($d);
		&$second_print($text{'dkim_dnsalready'});
		}
	&release_lock_dns($d);
	}
&register_post_action(\&restart_bind) if ($anychanged);
}

# add_domain_dkim_record(&domain, &dkim, &recs, file)
# Add the DKIM record for a single domain to its zone file
sub add_domain_dkim_record
{
my ($d, $dkim, $recs, $file) = @_;
my $withdot = $d->{'dom'}.'.';
my $dkname = '_domainkey.'.$withdot;
my $changed = 0;
my $selname = $dkim->{'selector'}.'.'.$dkname;
my ($selrec) = grep { $_->{'name'} eq $selname && 
		      $_->{'type'} eq 'TXT' } @$recs;
my $pubkey = &get_dkim_dns_pubkey($dkim, $d);
if (!$selrec) {
	# Add new record
	my $selrec = { 'name' => $selname,
		       'type' => 'TXT',
		       'values' => [ 'v=DKIM1; k=rsa; t=s; p='.
				     $pubkey ] };
	&create_dns_record($recs, $file, $selrec);
	$changed++;
	}
elsif ($selrec && join("", @{$selrec->{'values'}}) !~ /p=\Q$pubkey\E/) {
	# Fix existing record
	my $val = join("", @{$selrec->{'values'}});
	if ($val !~ s/p=([^;]+)/p=$pubkey/) {
		$val = 'k=rsa; t=s; p='.$pubkey;
		}
	$selrec->{'values'} = [ $val ];
	&modify_dns_record($recs, $file, $selrec);
	$changed++;
	}
return $changed;
}

# remove_dkim_dns_records(&domains, &dkim)
# Delete all DKIM TXT records from the given DNS domains
sub remove_dkim_dns_records
{
my ($doms, $dkim) = @_;
my $anychanged = 0;
foreach my $d (@$doms) {
	&$first_print(&text('dkim_undns', "<tt>$d->{'dom'}</tt>"));
	&pre_records_change($d);
	my ($recs, $file) = &get_domain_dns_records_and_file($d);
	if (!$file) {
		&after_records_change($d);
		&$second_print($text{'dkim_ednszone'});
		next;
		}
	&obtain_lock_dns($d);
	my $changed = &remove_domain_dkim_record($d, $dkim, $recs, $file);
	if ($changed) {
		&post_records_change($d, $recs, $file);
		&$second_print($text{'dkim_dnsremoved'});
		$anychanged++;
		}
	else {
		&after_records_change($d);
		&$second_print($text{'dkim_dnsalreadygone'});
		}
	&release_lock_dns($d);
	}
&register_post_action(\&restart_bind) if ($anychanged);
}

# remove_domain_dkim_record(&domain, &dkim, &recs, file)
# Remove the DKIM records for a single domain from its zone file
sub remove_domain_dkim_record
{
my ($d, $dkim, $recs, $file) = @_;
my $withdot = $d->{'dom'}.'.';
my $dkname = '_domainkey.'.$withdot;
my ($dkrec) = grep { $_->{'name'} eq $dkname &&
		     $_->{'type'} eq 'TXT' } @$recs;
my $selname = $dkim->{'selector'}.'.'.$dkname;
my ($selrec) = grep { $_->{'name'} eq $selname &&
		      $_->{'type'} eq 'TXT' } @$recs;
my $changed = 0;
if ($selrec) {
	&delete_dns_record($recs, $selrec->{'file'}, $selrec);
	$changed++;
	}
if ($dkrec) {
	&delete_dns_record($recs, $dkrec->{'file'}, $dkrec);
	$changed++;
	}
return $changed;
}

# rebuild_sendmail_cf()
# Rebuild sendmail's .cf file from the .mc file
sub rebuild_sendmail_cf
{
my $cmd = "cd $sendmail::config{'sendmail_features'}/m4 ; ".
	  "m4 $sendmail::config{'sendmail_features'}/m4/cf.m4 ".
	  "$sendmail::config{'sendmail_mc'}";
&lock_file($sendmail::config{'sendmail_cf'});
&system_logged("$cmd 2>/dev/null >$sendmail::config{'sendmail_cf'} ".
	       "</dev/null");
&unlock_file($sendmail::config{'sendmail_cf'});
}

# get_domain_dkim_key(&domain)
# Returns the DKIM private key file for a domain
sub get_domain_dkim_key
{
my ($d) = @_;
my $dkim_config = &get_dkim_config_file();
return undef if (!-r $dkim_config);
my $conf = &get_open_dkim_config($dkim_config);
if ($conf->{'KeyList'}) {
	# Old-style file mapping domains to key files
	my $keyfile = $conf->{'KeyFile'};
	my $lref = &read_file_lines($conf->{'KeyList'}, 1);
	foreach my $l (@$lref) {
		my ($pat, $dom, $file) = split(/:/, $l);
		if ($dom eq $d->{'dom'} && !&same_file($file, $keyfile)) {
			# Has it's own key
			return $file;
			}
		}
	}
elsif ($conf->{'SigningTable'} && $conf->{'KeyTable'}) {
	# New style mapping domains to key names, and key names to files
	my $signingfile = $conf->{'SigningTable'};
	$signingfile =~ s/^[a-z]+://;
	my $slref = &read_file_lines($signingfile, 1);
	my $keyname;
	foreach my $l (@$slref) {
		my ($re, $name) = split(/\s+/, $l);
		if ($re eq "*\@$d->{'dom'}") {
			$keyname = $name;
			last;
			}
		}
	return undef if (!$keyname);
	my $keyfile = $conf->{'KeyTable'};
	$keyfile =~ s/^[a-z]+://;
	my $klref = &read_file_lines($keyfile, 1);
	foreach my $l (@$klref) {
		my ($name, $kdom, $ksel, $kfile) = split(/\s+|:/, $l);
		if ($name eq $keyname) {
			return $kfile;
			}
		}
	}
return undef;
}

# save_domain_dkim_key(&domain, [key-text])
# Updates the private key for a domain (also in DNS)
sub save_domain_dkim_key
{
my ($d, $key) = @_;
&$first_print($key ? $text{'domdkim_setkey'} : $text{'domdkim_clearkey'});
my $dkim = &get_dkim_config();
my $dkim_config = &get_dkim_config_file();
if (!-r $dkim_config) {
	&$second_print($text{'domdkim_econfig'});
	return 0;
	}
my $conf = &get_open_dkim_config($dkim_config);
if (&get_dkim_type() ne 'ubuntu' && &get_dkim_type() ne 'centos') {
	# Old style which supports a single key list file
	if (!$conf->{'KeyList'}) {
		&$second_print($text{'domdkim_ekeylist'});
		return 0;
		}
	my $keyfile = $conf->{'KeyFile'};
	&lock_file($conf->{'KeyList'});
	my $lref = &read_file_lines($conf->{'KeyList'});
	my $selkeyfile = $conf->{'KeyList'};
	$selkeyfile =~ s/\/([^\/]+)$/\/$dkim->{'selector'}/;
	foreach my $l (@$lref) {
		my ($pat, $dom, $file) = split(/:/, $l);
		if ($dom eq $d->{'dom'}) {
			# Found the domain's line
			if ($key) {
				# Use a custom key file. The suffix is used as
				# the selector name by dkim-milter
				my $dir = $conf->{'KeyList'};
				$dir =~ s/\/([^\/]+)$/\/$d->{'id'}/;
				if (-f $dir) {
					&unlink_file($dir);
					}
				&make_dir($dir, 0755);
				$file = "$dir/$dkim->{'selector'}";
				&open_lock_tempfile(PRIVKEY, ">$file");
				&print_tempfile(PRIVKEY, $key);
				&close_tempfile(PRIVKEY);
				&set_dkim_keyfile_permissions($file);
				}
			else {
				# Revert to default (which is a link to the
				# actual key)
				$file = $selkeyfile;
				}
			$l = join(":", $pat, $dom, $file);
			}
		}
	&flush_file_lines($conf->{'KeyList'});
	&unlock_file($conf->{'KeyList'});
	}
else {
	# New style with SigningTable and KeyTable options

	# Add missing directives if needed
	if (!$conf->{'SigningTable'}) {
		$conf->{'SigningTable'} = "refile:".$dkim_config;
		$conf->{'SigningTable'} =~ s/\/([^\/]+)$/\/dkim-signingtable/;
		&save_open_dkim_config($dkim_config,
			"SigningTable", $conf->{'SigningTable'});
		}
	if (!$conf->{'KeyTable'}) {
		$conf->{'KeyTable'} = $dkim_config;
		$conf->{'KeyTable'} =~ s/\/([^\/]+)$/\/dkim-keytable/;
		&save_open_dkim_config($dkim_config,
			"KeyTable", $conf->{'KeyTable'});
		}

	# Find domain's entry in signing table
	my $signingfile = $conf->{'SigningTable'};
	$signingfile =~ s/^[a-z]+://;
	my $newfile = !-r $signingfile;
	&lock_file($signingfile);
	my $slref = &read_file_lines($signingfile);
	if (!@$slref) {
		# Add entry for the default key
		push(@$slref, "*\tdefault");
		}
	my $i = 0;
	my $sidx = -1;
	foreach my $l (@$slref) {
		my ($re, $name) = split(/\s+/, $l);
		if ($re eq "*\@$d->{'dom'}") {
			$sidx = $i;
			last;
			}
		$i++;
		}
	if ($sidx < 0 && $key) {
		# Need to add (at the start, so it matches first)
		splice(@$slref, 0, 0, "*\@$d->{'dom'}\t$d->{'id'}");
		}
	elsif ($sidx >= 0 && !$key) {
		# Need to remove
		splice(@$slref, $sidx, 1);
		}
	&flush_file_lines($signingfile);
	&unlock_file($signingfile);
	if ($newfile) {
		&set_ownership_permissions(undef, undef, 0755, $signingfile);
		}

	# Find domain's entry in key table
	my $keytablefile = $conf->{'KeyTable'};
	$keytablefile =~ s/^[a-z]+://;
	$newfile = !-r $keytablefile;
	&lock_file($keytablefile);
	my $klref = &read_file_lines($keytablefile);
	if (!@$klref) {
		# Add entry for the default key
		push(@$klref, "default\t%:$dkim->{'selector'}:".
			      $dkim->{'keyfile'});
		}
	$i = 0;
	my $kidx = -1;
	foreach my $l (@$klref) {
		my ($name, $kdom, $ksel, $kfile) = split(/\s+|:/, $l);
		if ($name eq $d->{'id'}) {
			$kidx = $i;
			last;
			}
		$i++;
		}
	my $keydir = $dkim_config;
	$keydir =~ s/\/([^\/]+)$//;
	if ($keydir eq "/etc" && -d "/etc/dkimkeys" &&
	    !-r $keydir."/".$d->{'id'}.".dkim-key") {
		# Use /etc/dkimkeys if if exists and the key isn't
		# already in /etc
		$keydir = "/etc/dkimkeys";
		}
	my $keyfile = $keydir."/".$d->{'id'}.".dkim-key";
	my $keyline = "$d->{'id'}\t$d->{'dom'}:$dkim->{'selector'}:$keyfile";
	if ($kidx < 0 && $key) {
		# Need to add
		&open_lock_tempfile(PRIVKEY, ">$keyfile");
		&print_tempfile(PRIVKEY, $key);
		&close_tempfile(PRIVKEY);
		&set_dkim_keyfile_permissions($keyfile);
		push(@$klref, $keyline);
		}
	elsif ($kidx >= 0 && !$key) {
		# Need to remove
		splice(@$klref, $kidx, 1);
		}
	elsif ($kidx >= 0 && $key) {
		# Need to update
		$klref->[$kidx] = $keyline;
		}
	&flush_file_lines($keytablefile);
	&unlock_file($keytablefile);
	if ($newfile) {
		&set_ownership_permissions(undef, undef, 0755, $keytablefile);
		}
	}
&$second_print($text{'setup_done'});

if ($d->{'dns'} && !&copy_alias_records($d)) {
	&add_dkim_dns_records([ $d ], $dkim);
	}

# Restart milter
my $init = &get_dkim_init_name();
&foreign_require("init");
if (&init::action_status($init)) {
	&init::restart_action($init);
	}

return 1;
}

# generate_dkim_key([size])
# Generate a new DKIM PEM format key of the given size. Returns either 0 and
# an error message, or 1 and the key text
sub generate_dkim_key
{
my ($size) = @_;
$size ||= 2048;
my $temp = &transname();
my $out = &backquote_logged("openssl genrsa -out ".
	quotemeta($temp)." $size 2>&1 </dev/null");
my $ex = $?;
my $key = &read_file_contents($temp);
&unlink_file($temp);
if ($ex) {
	return (0, $out);
	}
else {
	return (1, $key);
	}
}

# set_dkim_keyfile_permissions(keyfile)
# Set the ownership and perms on a key file
sub set_dkim_keyfile_permissions
{
my ($keyfile) = @_;
if (&get_dkim_type() eq 'ubuntu' || &get_dkim_type() eq 'centos') {
	&set_ownership_permissions("opendkim", undef, 0700, $keyfile);
	}
elsif (&get_dkim_type() eq 'debian') {
	&set_ownership_permissions("dkim-filter", undef, 0700, $keyfile);
	}
elsif (&get_dkim_type() eq 'redhat') {
	&set_ownership_permissions("dkim-milter", undef, 0700, $keyfile);
	}
elsif (&get_dkim_type() eq 'gentoo') {
	&set_ownership_permissions("milter", undef, 0700, $keyfile);
	}
elsif (&get_dkim_type() eq 'freebsd') {
	&set_ownership_permissions("opendkim", undef, 0700, $keyfile);
	}
}

# get_default_dkim_selector()
# Returns a default selector based on the current month and year
sub get_default_dkim_selector
{
my @tm = localtime(time());
return sprintf "%4.4d%2.2d", $tm[5] + 1900, $tm[4];
}

1;

