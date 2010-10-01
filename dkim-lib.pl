# Functions for setting up DKIM signing

$debian_dkim_config = "/etc/dkim-filter.conf";
$debian_dkim_default = "/etc/default/dkim-filter";

$redhat_dkim_config = "/etc/mail/dkim-milter/dkim-filter.conf";
$redhat_dkim_default = "/etc/sysconfig/dkim-milter";

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
# domain - Domain(s) for which DKIM is enabled
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
	$rv{'selector'} = $conf->{'Selector'};
	$rv{'keyfile'} = $conf->{'KeyFile'};

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
	# Read Fedora dkim config file
	my $conf = &get_debian_dkim_config($redhat_dkim_config);
	$rv{'enabled'} = &init::action_status("dkim-milter") == 2;
	$rv{'selector'} = $conf->{'Selector'};
	$rv{'keyfile'} = $conf->{'KeyFile'};

	# Read defaults file that specifies port
	my %def;
	&read_env_file($redhat_dkim_default, \%def);
	if ($def{'SOCKET'} =~ /^inet:(\d+)/) {
		$rv{'port'} = $1;
		}
	elsif ($def{'SOCKET'} =~ /^local:([^:]+)/) {
		$rv{'socket'} = $1;
		}
	else {
		# Assume default socket
		$rv = "/var/run/dkim-milter/dkim-milter.sock";
		}
	}

# Check mail server
&require_mail();
my $wantmilter = $rv{'port'} ? "inet:localhost:$rv{'port'}" :
		 $rv{'socket'} ? "local:$rv{'socket'}" : "";
if ($config{'mail_system'} == 0) {
	# Postfix config
	my $milters = &postfix::get_real_value("smtpd_milters");
	if ($wantmilter && $milters !~ /\Q$wantmilter\E/) {
		$rv{'enabled'} = 0;
		}
	}
elsif ($config{'mail_system'} == 1) {
	# Sendmail config
	my @feats = &sendmail::list_features();
	my ($milter) = grep { $_->{'text'} =~ /INPUT_MAIL_FILTER/ &&
			      $_->{'text'} =~ /\Q$wantmilter\E/ } @feats;
	if (!$milter) {
		$rv{'enabled'} = 0;
                }
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

# save_debian_dkim_config(file, directive, value)
# Update a value in the Debian-style config file
sub save_debian_dkim_config
{
my ($file, $name, $value) = @_;
my $lref = &read_file_lines($file);
my $found = 0;
foreach my $l (@$lref) {
	if ($l =~ /^\s*#*\s*(\S+)\s*(\S.*)$/ && $1 eq $name) {
		$l = "$name $value";
		$found = 1;
		last;
		}
	}
if (!$found) {
	push(@$lref, "$name $value");
	}
&flush_file_lines($file);
}

# enable_dkim()
# Perform all the steps needed to enable DKIM
sub enable_dkim
{
my ($dkim) = @_;
&foreign_require("webmin");
&foreign_require("init");

# Find domains that we can enable DKIM for (those with mail and DNS)
&$first_print($text{'dkim_domains'});
my @doms = grep { $_->{'dns'} && $_->{'mail'} } &list_domains();
if (@doms) {
	&$second_print(&text('dkim_founddomains', scalar(@doms)));
	}
else {
	&$second_print($text{'dkim_nodomains'});
	return 0;
	}

# Generate private key
if (!$dkim->{'keyfile'} || !-r $dkim->{'keyfile'}) {
	my $size = $config{'key_size'} || $webmin::default_key_size;
	$dkim->{'keyfile'} ||= "/etc/dkim.key";
	&$first_print(&text('dkim_newkey', "<tt>$dkim->{'keyfile'}</tt>"));
	&lock_file($dkim->{'keyfile'});
	my $out = &backquote_logged("openssl genrsa -out ".
		quotemeta($dkim->{'keyfile'})." $size 2>&1 </dev/null");
	if ($?) {
		&$second_print(&text('dkim_enewkey',
				"<tt>".&html_escape($out)."</tt>"));
		return 0;
		}
	if ($gconfig{'os_type'} eq 'debian-linux') {
		&set_ownership_permissions("dkim-filter", undef, 0700,
					   $dkim->{'keyfile'});
		}
	elsif ($gconfig{'os_type'} eq 'redhat-linux') {
		&set_ownership_permissions("dkim-milter", undef, 0700,
					   $dkim->{'keyfile'});
		}
	&unlock_file($dkim->{'keyfile'});
	&$second_print($text{'setup_done'});
	}

# Get the public key
&$first_print(&text('dkim_pubkey', "<tt>$dkim->{'keyfile'}</tt>"));
my $pubkey = &get_dkim_pubkey($dkim);
if (!$pubkey) {
	&$second_print($text{'dkim_epubkey'});
	return 0;
	}
&$second_print($text{'setup_done'});

# Add public key to DNS domain
&add_dkim_dns_records(\@doms, $dkim);

# Add domain, key and selector to config file
&$first_print($text{'dkim_config'});
if ($gconfig{'os_type'} eq 'debian-linux') {
	# Save domains and key file in config
	&lock_file($debian_dkim_config);
	&save_debian_dkim_config($debian_dkim_config, 
		"Domain", join(",", map { $_->{'dom'} } @doms));
	&save_debian_dkim_config($debian_dkim_config, 
		"Selector", $dkim->{'selector'});
	&save_debian_dkim_config($debian_dkim_config, 
		"KeyFile", $dkim->{'keyfile'});
	&unlock_file($debian_dkim_config);

	# Set socket in defaults file if missing
	&lock_file($debian_dkim_default);
	my %def;
	&read_env_file($debian_dkim_default, \%def);
	if (!$def{'SOCKET'}) {
		$def{'SOCKET'} = "inet:8891\@localhost";
		&write_env_file($debian_dkim_default, \%def);
		$dkim->{'port'} = 8891;
		}
	&unlock_file($debian_dkim_default);
	}
elsif ($gconfig{'os_type'} eq 'redhat-linux') {
	# Save domains and key file in config
	&lock_file($redhat_dkim_config);
	&save_debian_dkim_config($redhat_dkim_config, 
		"Domain", join(",", map { $_->{'dom'} } @doms));
	&save_debian_dkim_config($redhat_dkim_config, 
		"Selector", $dkim->{'selector'});
	&save_debian_dkim_config($redhat_dkim_config, 
		"KeyFile", $dkim->{'keyfile'});
	&unlock_file($redhat_dkim_config);
	}
&$second_print($text{'setup_done'});

# Enable filter at boot time
&$first_print($text{'dkim_boot'});
if ($gconfig{'os_type'} eq 'debian-linux') {
	&init::enable_at_boot("dkim-filter");
	}
elsif ($gconfig{'os_type'} eq 'redhat-linux') {
	&init::enable_at_boot("dkim-milter");
	}
&$second_print($text{'setup_done'});

# Re-start filter now
&$first_print($text{'dkim_start'});
my ($ok, $out);
if ($gconfig{'os_type'} eq 'debian-linux') {
	&init::stop_action("dkim-filter");
	($ok, $out) = &init::start_action("dkim-filter");
	}
elsif ($gconfig{'os_type'} eq 'redhat-linux') {
	&init::stop_action("dkim-milter");
	($ok, $out) = &init::start_action("dkim-milter");
	}
if (!$ok) {
	&$second_print(&text('dkim_estart',
			"<tt>".&html_escape($out)."</tt>"));
	return 0;
	}
&$second_print($text{'setup_done'});

&$first_print($text{'dkim_mailserver'});
&require_mail();
my $newmilter = $dkim->{'port'} ? "inet:localhost:$dkim->{'port'}"
				: "local:$dkim->{'socket'}";
if ($config{'mail_system'} == 0) {
	# Configure Postfix to use filter
	&lock_file($postfix::config{'postfix_config_file'});
	&postfix::set_current_value("milter_default_action", "accept");
	&postfix::set_current_value("milter_protocol", 2);
	my $milters = &postfix::get_current_value("smtpd_milters");
	if ($milters !~ /\Q$newmilter\E/) {
		$milters = $milters ? $milters.",".$newmilter : $newmilter;
		&postfix::set_current_value("smtpd_milters", $milters);
		&postfix::set_current_value("non_smtpd_milters", $milters);
		}
	&unlock_file($postfix::config{'postfix_config_file'});

	# Apply Postfix config
	&postfix::reload_postfix();
	}
elsif ($config{'mail_system'} == 1) {
	# Configure Sendmail to use filter
	&lock_file($sendmail::config{'sendmail_mc'});
	my @feats = &sendmail::list_features();
	my ($milter) = grep { $_->{'text'} =~ /INPUT_MAIL_FILTER/ &&
			      $_->{'text'} =~ /\Q$wantmilter\E/ } @feats;
	if (!$milter) {
		# Add to .mc file
		&sendmail::create_feature({
			'type' => 0,
	    		'text' =>
			  "INPUT_MAIL_FILTER(`dkim-filter', `S=$newmilter')" });

		# Rebuild .cf file
		my $cmd = "cd $sendmail::config{'sendmail_features'}/m4 ; ".
			  "m4 $sendmail::config{'sendmail_features'}/m4/cf.m4 ".
			  "$sendmail::config{'sendmail_mc'}";
		&lock_file($sendmail::config{'sendmail_cf'});
		&system_logged("$cmd 2>/dev/null >$config{'sendmail_cf'} ".
			       "</dev/null");
		&unlock_file($sendmail::config{'sendmail_cf'});
		}
	&unlock_file($sendmail::config{'sendmail_mc'});
	&sendmail::restart_sendmail();
	}
&$second_print($text{'setup_done'});

return 1;
}

# get_dkim_pubkey(&dkim)
# Returns the public key in a format suitable for inclusion in a DNS record
sub get_dkim_pubkey
{
my $pubkey = &backquote_command(
        "openssl rsa -in ".quotemeta($dkim->{'keyfile'}).
        " -pubout -outform PEM 2>/dev/null");
if ($? || $pubkey !~ /BEGIN\s+PUBLIC\s+KEY/) {
	return undef;
        }
$pubkey =~ s/\-+(BEGIN|END)\s+PUBLIC\s+KEY\-+//g;
$pubkey =~ s/\s+//g;
return $pubkey;
}

# disable_dkim(&dkim)
# Turn off the DKIM filter and mail server integration
sub disable_dkim
{
my ($dkim) = @_;
&foreign_require("init");

# Remove from DNS
my @doms = grep { $_->{'dns'} && $_->{'mail'} } &list_domains();
&remove_dkim_dns_records(\@doms, $dkim);

&$first_print($text{'dkim_unmailserver'});
&require_mail();
if ($config{'mail_system'} == 0) {
	# Configure Postfix to use filter
	&lock_file($postfix::config{'postfix_config_file'});
	&postfix::set_current_value("milter_default_action", "accept");
	&postfix::set_current_value("milter_protocol", 2);
	my $milters = &postfix::get_current_value("smtpd_milters");
	my $oldmilter = $dkim->{'port'} ? "inet:localhost:$dkim->{'port'}"
					: "local:$dkim->{'socket'}";
	if ($milters =~ /\Q$oldmilter\E/) {
		$milters = join(",", grep { $_ ne $oldmilter }
				split(/\s+,\s+/, $milters));
		&postfix::set_current_value("smtpd_milters", $milters);
		&postfix::set_current_value("non_smtpd_milters", $milters);
		}
	&unlock_file($postfix::config{'postfix_config_file'});

	# Apply Postfix config
	&postfix::reload_postfix();
	}
elsif ($config{'mail_system'} == 1) {
	# Configure Sendmail to not use filter
	# XXX
	}
&$second_print($text{'setup_done'});

# Stop filter now
&$first_print($text{'dkim_stop'});
if ($gconfig{'os_type'} eq 'debian-linux') {
	&init::stop_action("dkim-filter");
	}
elsif ($gconfig{'os_type'} eq 'redhat-linux') {
	&init::stop_action("dkim-milter");
	}
&$second_print($text{'setup_done'});

# Disable filter at boot time
&$first_print($text{'dkim_unboot'});
if ($gconfig{'os_type'} eq 'debian-linux') {
	&init::disable_at_boot("dkim-filter");
	}
elsif ($gconfig{'os_type'} eq 'redhat-linux') {
	&init::disable_at_boot("dkim-milter");
	}
&$second_print($text{'setup_done'});

return 1;
}

# update_dkim_domains([&domain, action])
# Updates the list of domains to sign mail for, if needed
sub update_dkim_domains
{
my ($d, $action) = @_;
return if (&check_dkim());
my $dkim = &get_dkim_config();
return if (!$dkim || !$dkim->{'enabled'});

# Enable DKIM for all domains with mail
my @doms = grep { $_->{'mail'} && $_->{'dns'} } &list_domains();
if ($d && ($action eq 'setup' || $action eq 'modify')) {
	push(@doms, $d);
	}
elsif ($d && $action eq 'delete') {
	@doms = grep { $_->{'id'} ne $d->{'id'} } @doms;
	}
my %done;
@doms = grep { !$done{$_->{'id'}}++ } @doms;
&set_dkim_domains(\@doms);

# Add DNS records
if ($d && ($action eq 'setup' || $action eq 'modify')) {
	&add_dkim_dns_records([ $d ], $dkim);
	}
elsif ($d && $action eq 'delete') {
	&remove_dkim_dns_records([ $d ], $dkim);
	}
else {
	&add_dkim_dns_records(\@doms, $dkim);
	}
}

# set_dkim_domains(&domains)
# Configure the DKIM filter to sign mail for the given list of domaisn
sub set_dkim_domains
{
my ($doms) = @_;
if ($gconfig{'os_type'} eq 'debian-linux') {
	&lock_file($debian_dkim_config);
	my $conf = &get_debian_dkim_config($debian_dkim_config);
	&save_debian_dkim_config($debian_dkim_config, "Domain",
		join(",", map { $_->{'dom'} } @$doms));
	&unlock_file($debian_dkim_config);
	if (&init::action_status("dkim-filter")) {
		&init::restart_action("dkim-filter");
		}
	}
elsif ($gconfig{'os_type'} eq 'redhat-linux') {
	&lock_file($redhat_dkim_config);
	my $conf = &get_debian_dkim_config($redhat_dkim_config);
	&save_debian_dkim_config($redhat_dkim_config, "Domain",
		join(",", map { $_->{'dom'} } @$doms));
	&unlock_file($redhat_dkim_config);
	if (&init::action_status("dkim-milter")) {
		&init::restart_action("dkim-milter");
		}
	}
}

# add_dkim_dns_records(&domains, &dkim)
# Add DKIM DNS records to the given list of domains
sub add_dkim_dns_records
{
my ($doms, $dkim) = @_;
my $pubkey = &get_dkim_pubkey($dkim);
my $anychanged = 0;
foreach my $d (@$doms) {
	&$first_print(&text('dkim_dns', "<tt>$d->{'dom'}</tt>"));
	my $z = &get_bind_zone($d->{'dom'});
	if (!$z) {
		&$second_print($text{'dkim_ednszone'});
		next;
		}
	&obtain_lock_dns($d);
	my $file = &bind8::find("file", $z->{'members'});
	my $fn = $file->{'values'}->[0];
	my @recs = &bind8::read_zone_file($fn, $d->{'dom'});
	my $withdot = $d->{'dom'}.'.';
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
		# Add new record
		&bind8::create_record($fn, $selname, undef, 'IN', 'TXT',
				      '"k=rsa; t=y; p='.$pubkey.'"');
		$changed++;
		}
	elsif ($selrec && $selrec->{'values'}->[0] !~ /p=\Q$pubkey\E/) {
		# Fix existing record
		my $val = $selrec->{'values'}->[0];
		if ($val !~ s/p=([^;]+)/p=$pubkey/) {
			$val = '"k=rsa; t=y; p='.$pubkey.'"';
			}
		&bind8::modify_record($selrec->{'file'}, $selrec,
				      $selrec->{'name'}, $selrec->{'ttl'},
				      $selrec->{'class'}, $selrec->{'type'},
				      $val);
		$changed++;
		}
	if ($changed) {
		&bind8::bump_soa_record($fn, \@recs);
		if (defined(&bind8::supports_dnssec) &&
		    &bind8::supports_dnssec()) {
			eval {
				local $main::error_must_die = 1;
				&bind8::sign_dnssec_zone_if_key($z, \@recs, 0);
				};
			}
		&$second_print($text{'dkim_dnsadded'});
		$anychanged++;
		}
	else {
		&$second_print($text{'dkim_dnsalready'});
		}
	&release_lock_dns($d);
	}
&register_post_action(\&restart_bind) if ($anychanged);
}

# remove_dkim_dns_records(&domains, &dkim)
# Delete all DKIM TXT records from the given DNS domains
sub remove_dkim_dns_records
{
my ($doms, $dkim) = @_;
my $anychanged = 0;
foreach my $d (@$doms) {
	&$first_print(&text('dkim_undns', "<tt>$d->{'dom'}</tt>"));
	my $z = &get_bind_zone($d->{'dom'});
	if (!$z) {
		&$second_print($text{'dkim_ednszone'});
		next;
		}
	&obtain_lock_dns($d);
	my $file = &bind8::find("file", $z->{'members'});
	my $fn = $file->{'values'}->[0];
	my @recs = &bind8::read_zone_file($fn, $d->{'dom'});
	my $withdot = $d->{'dom'}.'.';
	my $dkname = '_domainkey.'.$withdot;
	my ($dkrec) = grep { $_->{'name'} eq $dkname &&
			     $_->{'type'} eq 'TXT' } @recs;
	my $selname = $dkim->{'selector'}.'.'.$dkname;
	my ($selrec) = grep { $_->{'name'} eq $selname &&
                              $_->{'type'} eq 'TXT' } @recs;
	my $changed = 0;
	if ($selrec) {
		&bind8::delete_record($fn, $selrec);
		$changed++;
		}
	if ($dkrec) {
		&bind8::delete_record($fn, $dkrec);
		$changed++;
		}
	if ($changed) {
		&bind8::bump_soa_record($fn, \@recs);
		if (defined(&bind8::supports_dnssec) &&
		    &bind8::supports_dnssec()) {
			eval {
				local $main::error_must_die = 1;
				&bind8::sign_dnssec_zone_if_key($z, \@recs, 0);
				};
			}
		&$second_print($text{'dkim_dnsremoved'});
		$anychanged++;
		}
	else {
		&$second_print($text{'dkim_dnsalreadygone'});
		}
	&release_lock_dns($d);
	}
&register_post_action(\&restart_bind) if ($anychanged);
}

1;

