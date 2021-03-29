# Functions for setting up email rate limits

sub get_ratelimit_type
{
if (-r "/usr/local/etc/mail/greylist.conf" && 
    -e "/usr/local/bin/milter-greylist") {
	# Installed from source
	return 'source';
	}
elsif ($gconfig{'os_type'} eq 'debian-linux') {
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
my $type = &get_ratelimit_type();
return $type eq 'redhat' ? '/etc/mail/greylist.conf' :
       $type eq 'debian' ? '/etc/milter-greylist/greylist.conf' :
       $type eq 'source' ? '/usr/local/etc/mail/greylist.conf' :
			   undef;
}

sub get_ratelimit_init_name
{
return 'milter-greylist';
}

sub get_ratelimit_user
{
my $type = &get_ratelimit_type();
return $type eq 'redhat' ? 'greylist' :
       $type eq 'debian' ? 'greylist' : undef;
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
if (&get_ratelimit_type() ne 'source') {
	my $init = &get_ratelimit_init_name();
	return &text('ratelimit_einit', "<tt>$init</tt>")
		if (!&init::action_status($init));
	}
if (!&get_milter_greylist_path()) {
	return &text('ratelimit_ecmd', "<tt>milter-greylist</tt>");
	}

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
	&foreign_require("software");
	return defined(&software::update_system_install);
	}
return 0;
}

# install_ratelimit_package()
# Attempt to install milter-greylist, outputting progress messages
sub install_ratelimit_package
{
&foreign_require("software");
my $pkg = 'milter-greylist';
my @inst = &software::update_system_install($pkg);
return scalar(@inst) || !&check_ratelimit();
}

# get_ratelimit_config()
# Returns the current rate-limiting config, parsed into an array ref
sub get_ratelimit_config
{
my $cfile = &get_ratelimit_config_file();
my @rv;
my $lref = &read_file_lines($cfile, 1);
for(my $i=0; $i<@$lref; $i++) {
	my $l = $lref->[$i];
	$l =~ s/#.*$//;
	next if ($l !~ /\S/);
	my $lnum = $i;
	while($l =~ s/\\\s*$//) {
		# Ends with / .. continue on next line
		$nl = $lref->[++$i];
		$nl =~ s/#.*$//;
		$l .= $nl;
		}
	# Split up line like foo bar { smeg spod }
	my $toks = &wsplit_with_quotes($l);
	next if (!@$toks);
	my $dir = { 'line' => $lnum,
		    'eline' => $i,
		    'file' => $cfile,
		    'name' => shift(@$toks),
		    'values' => [ ] };
	while(@$toks && $toks->[0] ne "{") {
		push(@{$dir->{'values'}}, shift(@$toks));
		}
	$dir->{'value'} = $dir->{'values'}->[0];
	$dir->{'value'} =~ s/^'(.*)'$/$1/;
	$dir->{'value'} =~ s/^"(.*)"$/$1/;
	if ($toks->[0] eq "{") {
		# Has sub-members
		$dir->{'members'} = [ ];
		shift(@$toks);
		while(@$toks && $toks->[0] ne "{") {
			push(@{$dir->{'members'}}, shift(@$toks));
			}
		}
	push(@rv, $dir);
	}
return \@rv;
}

# save_ratelimit_directive(&config, &old, &new, [&create-before])
# Create, update or delete a ratelimiting directive
sub save_ratelimit_directive
{
my ($conf, $o, $n, $b4) = @_;
my $file = $o ? $o->{'file'} : $b4 ? $b4->{'file'} :
	   &get_ratelimit_config_file();
$file || &error("No file to save config to!");
my $lref = &read_file_lines($file);
my @lines = $n ? &make_ratelimit_lines($n) : ();
my $idx = &indexof($o, @$conf);
my ($roffset, $rlines);
if ($o && $n) {
	# Replace existing directive
	$roffset = $o->{'line'};
	$rlines = scalar(@lines) - ($o->{'eline'} - $o->{'line'} + 1);
	splice(@$lref, $o->{'line'}, $o->{'eline'} - $o->{'line'} + 1, @lines);
	$n->{'line'} = $o->{'line'};
	$n->{'eline'} = $n->{'line'} + scalar(@lines) - 1;
	$n->{'file'} = $o->{'file'};
	if ($idx >= 0) {
		$conf->[$idx] = $n;
		}
	}
elsif ($o && !$n) {
	# Delete existing directive
	$roffset = $o->{'line'};
	$rlines = $o->{'eline'} - $o->{'line'} + 1;
	splice(@$lref, $o->{'line'}, $rlines);
	if ($idx >= 0) {
		splice(@$conf, $idx, 1);
		}
	$rlines = -$rlines;
	}
elsif (!$o && $n) {
	# Add new directive
	if ($b4) {
		# Before some directive
		$rlines = scalar(@lines);
		$roffset = $b4->{'line'} - 1;
		my $b4idx = &indexof($b4, @$conf);
		$b4idx >= 0 || &error("Directive to add before was not found ".
				      "in config!");
		splice(@$conf, $b4idx, 0, $n);
		splice(@$lref, $b4->{'line'}, 0, @lines);
		$n->{'line'} = $b4->{'line'};
		$n->{'eline'} = $n->{'line'} + scalar(@lines) - 1;
		$n->{'file'} = $file;
		}
	else {
		# At end of file
		push(@$conf, $n);
		$n->{'line'} = scalar(@$lref);
		$n->{'eline'} = $n->{'line'} + scalar(@lines) - 1;
		$n->{'file'} = $file;
		push(@$lref, @lines);
		}
	}
if ($rlines) {
	foreach my $c (@$conf) {
		$c->{'line'} += $rlines if ($c->{'line'} > $roffset);
		$c->{'eline'} += $rlines if ($c->{'eline'} > $roffset);
		}
	}
}

# make_ratelimit_lines(&directive)
# Returns an array of lines for some directive
sub make_ratelimit_lines
{
my ($dir) = @_;
my @w = ( $dir->{'name'}, @{$dir->{'values'}} );
if ($dir->{'members'}) {
	push(@w, "{", @{$dir->{'members'}}, "}");
	}
return join(" ", @w);
}

# get_milter_greylist_path()
# Returns the full path to milter-greylist, if installed
sub get_milter_greylist_path
{
return &has_command("milter-greylist");
}

# get_milter_greylist_version()
# Returns the installed version number, or undef
sub get_milter_greylist_version
{
my $path = &get_milter_greylist_path();
return undef if (!$path || !-x $path);
my $out = &backquote_command("$path -r 2>&1 </dev/null");
return $out =~ /milter-greylist-([0-9\.]+)/ ? $1 : undef;
}

# get_mailserver_chroot()
# Returns the chroot directory that the mailserver runs under. The
# milter-greylist socket file must be relative to this.
sub get_mailserver_chroot
{
if ($config{'mail_system'} == 0 && &get_ratelimit_type() eq 'debian') {
	# XXX actually check master.cf to see if chroot is enabled
	return "/var/spool/postfix";
	}
return "";
}

# is_ratelimit_enabled()
# Returns 1 if the ratelimit server is running and the mail server is using it
sub is_ratelimit_enabled
{
# Enabled at boot?
&foreign_require("init");
my $init = &get_ratelimit_init_name();
return 0 if (&init::action_status($init) != 2);

# Check mail server
my $conf = &get_ratelimit_config();
my ($socket) = grep { $_->{'name'} eq 'socket' } @$conf;
return 0 if (!$socket);		# No socket in config?!
my $socketfile = $socket->{'value'};
my $chroot = &get_mailserver_chroot();
if ($chroot) {
	$socketfile =~ s/^\Q$chroot\E//;
	}
my $wantmilter = "local:".$socketfile;
&require_mail();
if ($config{'mail_system'} == 0) {
	# Check Postfix config
	my $milters = &postfix::get_real_value("smtpd_milters");
	if ($milters !~ /\Q$wantmilter\E/) {
		# Postfix not using the milter
		return 0;
		}
	}
elsif ($config{'mail_system'} == 1) {
	# Check Sendmail config
	my @feats = &sendmail::list_features();
	my ($milter) = grep { $_->{'text'} =~ /INPUT_MAIL_FILTER/ &&
			      $_->{'text'} =~ /\Q$wantmilter\E/ } @feats;
	if (!$milter) {
		# Sendmail not using the milter
		return 0;
		}
	}
else {
	# Unsupported mail server
	return 0;
	}

return 1;
}

# enable_ratelimit()
# Turn on rate limiting, while printing progress
sub enable_ratelimit
{
# Build stop and start commands (needed when installed from source)
my $conf = &get_ratelimit_config();
my ($pidfile) = grep { $_->{'name'} eq 'pidfile' } @$conf;
if (!$pidfile) {
	$pidfile = { 'name' => 'pidfile',
		     'value' => '/var/run/milter-greylist.pid',
		     'values' => [ '"/var/run/milter-greylist.pid"' ] };
	&save_ratelimit_directive($conf, undef, $pidfile);
	&flush_file_lines($pidfile->{'file'});
	}
my $stopcmd = "kill `cat $pidfile->{'value'}` && sleep 5";
my $startcmd = &has_command("milter-greylist").
	       " -f ".&get_ratelimit_config_file();

# Enable at boot
&foreign_require("init");
my $init = &get_ratelimit_init_name();
&$first_print(&text('ratelimit_atboot', "<tt>$init</tt>"));
&init::enable_at_boot($init,
	"Start milter-greylist",
	$startcmd, $stopcmd, undef, 
	{ 'fork' => 1 });

# On Debian, update the defaults file
my $dfile = "/etc/default/milter-greylist";
if (&get_ratelimit_type() eq 'debian' && -r $dfile) {
	my $lref = &read_file_lines($dfile);
	foreach my $l (@$lref) {
		if ($l =~ /^\s*ENABLED=/) {
			$l = "ENABLED=1";
			}
		}
	&flush_file_lines($dfile);
	}
&$second_print($text{'setup_done'});

# Pick a socket file under the mail server's chroot
&$first_print($text{'ratelimit_socket'});
my $chroot = &get_mailserver_chroot();
my ($oldsocket) = grep { $_->{'name'} eq 'socket' } @$conf;
if (!$oldsocket) {
	&$second_print($text{'ratelimit_esocket'});
	return 0;
	}
my $socketfile = $oldsocket->{'value'};		# Socket path used by postfix
if ($chroot) {
	# Adjust the socket to ensure it is under the chroot
	if (!&is_under_directory($chroot, $socketfile) &&
	    $socketfile !~ /^\Q$chroot\E/) {
		# Not currently under the chroot .. make it so
		my $newsocket = { 'name' => 'socket',
				  'values' => [ "\"$chroot$socketfile\"" ] };
		&save_ratelimit_directive($conf, $oldsocket, $newsocket);
		&flush_file_lines($oldsocket->{'file'});
		}
	else {
		# Already under the chroot, so remove the chroot prefix
		$socketfile =~ s/^\Q$chroot\E//;
		}

	# Change path in init script and defaults file if needed
	foreach my $ifile (&init::action_filename($init),
			   "/etc/default/milter-greylist") {
		if ($ifile && -r $ifile) {
			my $lref = &read_file_lines($ifile);
			foreach my $l (@$lref) {
				if ($l =~ /^SOCKET\s*=/) {
					$l = "SOCKET=$chroot$socketfile";
					}
				}
			&flush_file_lines($ifile);
			}
		}

	# Make sure the socket file directory exists
	my $socketdir = "$chroot$socketfile";
	$socketdir =~ s/\/[^\/]+$//;
	if (!-d $socketdir) {
		&make_dir($socketdir, 0775, 1);
		my $user = &get_ratelimit_user();
		if ($user) {
			&set_ownership_permissions($user, undef, undef,
						   $socketdir);
			}
		}
	}

# Set socket to 666 permissions
my ($socket) = grep { $_->{'name'} eq 'socket' } @$conf;
if ($socket && $socket->{'values'}->[1] ne '666') {
	$socket->{'values'}->[1] = '666';
	&save_ratelimit_directive($conf, $socket, $socket);
	&flush_file_lines($socket->{'file'});
	}

&$second_print($text{'setup_done'});

# Start up now, if not running
&$first_print($text{'ratelimit_start'});
&init::stop_action($init);
sleep(5);	# Seems to need time to stop
my ($ok, $err) = &init::start_action($init);
if (!$ok) {
	&$second_print(&text('ratelimit_estart', $err));
	return 0;
	}
else {
	&$second_print($text{'setup_done'});
	}

# Configure mail server
&$first_print($text{'ratelimit_mailserver'});
&require_mail();
my $newmilter = "local:".$socketfile;
if ($config{'mail_system'} == 0) {
	# Configure Postfix to use filter
	&lock_file($postfix::config{'postfix_config_file'});
	&postfix::set_current_value("milter_default_action", "accept");
	if (!&postfix::get_current_value("milter_protocol")) {
		&postfix::set_current_value("milter_protocol", 2);
		}
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
	my $changed = 0;
	my @feats = &sendmail::list_features();

	# Check for filter definition
	my ($milter) = grep { $_->{'text'} =~ /INPUT_MAIL_FILTER/ &&
			      $_->{'text'} =~ /\Q$newmilter\E/ } @feats;
	if (!$milter) {
		# Add to .mc file
		&sendmail::create_feature({
			'type' => 0,
	    		'text' =>
			  "INPUT_MAIL_FILTER(`ratelimit-filter', `S=$newmilter')" });
		$changed++;
		}

	# Check for config for filters to call
	my ($def) = grep { $_->{'type'} == 2 &&
			   $_->{'name'} eq 'confINPUT_MAIL_FILTERS' } @feats;
	if ($def) {
		my @filters = split(/,/, $def->{'value'});
		if (&indexof("ratelimit-filter", @filters) < 0) {
			# Add to existing define
			push(@filters, 'ratelimit-filter');
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
			'value' => 'ratelimit-filter' });
		$changed++;
		}

	# Add other defines to change milter behavior
	foreach my $l ([ 'confMILTER_MACROS_CONNECT', 'j, {if_addr}' ],
		       [ 'confMILTER_MACROS_HELO', '{verify}, {cert_subject}' ],
		       [ 'confMILTER_MACROS_ENVFROM', 'i, {auth_authen}' ],
		       [ 'confMILTER_MACROS_ENVRCPT', '{greylist}' ]) {
		my ($def) = grep { $_->{'type'} == 2 &&
				   $_->{'name'} eq $l->[0] } @$conf;
		if (!$def) {
			&sendmail::create_feature({
				'type' => 2,
				'name' => $l->[0],
				'value' => $l->[1] });
			$changed++;
			}
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

# disable_ratelimit()
# Shut down the greylist server and stop the mail sever from using it
sub disable_ratelimit
{
&$first_print($text{'ratelimit_unmailserver'});
my $conf = &get_ratelimit_config();
my ($socket) = grep { $_->{'name'} eq 'socket' } @$conf;
if (!$socket) {
	&$second_print($text{'ratelimit_esocket'});
	return 0;
	}
my $socketfile = $socket->{'value'};
my $chroot = &get_mailserver_chroot();
if ($chroot) {
	$socketfile =~ s/^\Q$chroot\E//;
	}
my $oldmilter = "local:".$socketfile;
&require_mail();
if ($config{'mail_system'} == 0) {
	# Configure Postfix to not use filter
	&lock_file($postfix::config{'postfix_config_file'});
	my $milters = &postfix::get_current_value("smtpd_milters");
	if ($milters =~ /\Q$oldmilter\E/) {
		$milters = join(",", grep { $_ ne $oldmilter }
				split(/\s*,\s*/, $milters));
		&postfix::set_current_value("smtpd_milters", $milters);
		&postfix::set_current_value("non_smtpd_milters", $milters);
		}
	&unlock_file($postfix::config{'postfix_config_file'});

	# Apply Postfix config
	&postfix::reload_postfix();
	}
elsif ($config{'mail_system'} == 1) {
	# Configure Sendmail to not use filter
	&lock_file($sendmail::config{'sendmail_mc'});
	my @feats = &sendmail::list_features();
	my $changed = 0;

	# Remove from list of milter to call
	my ($def) = grep { $_->{'type'} == 2 &&
			   $_->{'name'} eq 'confINPUT_MAIL_FILTERS' } @feats;
	if ($def) {
		my @filters = split(/,/, $def->{'value'});
		@filters = grep { $_ ne 'ratelimit-filter' } @filters;
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
			      $_->{'text'} =~ /\Q$oldmilter\E/ } @feats;
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
&$first_print($text{'ratelimit_stop'});
my $init = &get_ratelimit_init_name();
&init::stop_action($init);
&$second_print($text{'setup_done'});

# Disable filter at boot time
&$first_print($text{'ratelimit_unboot'});
&init::disable_at_boot($init);
&$second_print($text{'setup_done'});

return 1;
}

# wsplit_with_quotes(string)
# Splits a string like  foo "foo bar" bazzz  into an array of words, preserving
# the quotes around them
sub wsplit_with_quotes
{
my $s = $_[0];
my @rv;
$s =~ s/\\\"/\0/g;
while($s =~ /^("[^"]*")\s*(.*)$/ || $s =~ /^(\S+)\s*(.*)$/) {
	my $w = $1;
	$s = $2;
	$w =~ s/\0/"/g;
	push(@rv, $w);
	}
return \@rv;
}

1;
