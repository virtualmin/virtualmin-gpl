
sub require_mail
{
return if ($require_mail++);
$can_alias_types{12} = 0;	# this autoreponder for vpopmail only
$supports_bcc = 0;
if ($config{'mail_system'} == 1) {
	# Using sendmail for email
	&foreign_require("sendmail", "sendmail-lib.pl");
	&foreign_require("sendmail", "virtusers-lib.pl");
	&foreign_require("sendmail", "aliases-lib.pl");
	&foreign_require("sendmail", "boxes-lib.pl");
	&foreign_require("sendmail", "features-lib.pl");
	%sconfig = &foreign_config("sendmail");
	$sendmail_conf = &sendmail::get_sendmailcf();
	$sendmail_vfile = &sendmail::virtusers_file($sendmail_conf);
	($sendmail_vdbm, $sendmail_vdbmtype) =
		&sendmail::virtusers_dbm($sendmail_conf);
	$sendmail_afiles = &sendmail::aliases_file($sendmail_conf);
	if ($config{'generics'}) {
		&foreign_require("sendmail", "generics-lib.pl");
		$sendmail_gfile = &sendmail::generics_file($sendmail_conf);
		($sendmail_gdbm, $sendmail_gdbmtype) =
			&sendmail::generics_dbm($sendmail_conf);
		}
	$can_alias_comments = $virtualmin_pro;
	$supports_aliascopy = 1;
	}
elsif ($config{'mail_system'} == 0) {
	# Using postfix for email
	&foreign_require("postfix", "postfix-lib.pl");
	&foreign_require("postfix", "boxes-lib.pl");
	%pconfig = &foreign_config("postfix");
	$virtual_type = $postfix::virtual_maps || "virtual_maps";
	$virtual_maps = &postfix::get_real_value($virtual_type);
	@virtual_map_files = &postfix::get_maps_files($virtual_maps);
	$postfix_afiles = [ &postfix::get_aliases_files(
				&postfix::get_real_value("alias_maps")) ];
	if ($config{'generics'}) {
		$canonical_type = "sender_canonical_maps";
		$canonical_maps = &postfix::get_real_value($canonical_type);
		@canonical_map_files =&postfix::get_maps_files($canonical_maps);
		}

	# Work out storage type for Postfix
	@virtual_map_backends = map { $_->[0] }
		&postfix::get_maps_types_files($virtual_maps);
	@alias_backends = map { $_->[0] }
		&postfix::get_maps_types_files(
			&postfix::get_real_value("alias_maps"));
	@canonical_backends = map { $_->[0] }
			&postfix::get_maps_types_files($canonical_maps);

	$can_alias_types{9} = 0;	# bounce not yet supported for postfix
	$can_alias_comments = $virtualmin_pro;
	if ($can_alias_comments &&
	    $virtual_maps !~ /^hash:/ &&
	    !&postfix::can_map_comments($virtual_type)) {
		# Comments not supported by map backend, such as MySQL
		$can_alias_comments = 0;
		}

	# New functions that can use maps
	$postfix_list_aliases = \&postfix::list_postfix_aliases;
	$postfix_create_alias = \&postfix::create_postfix_alias;
	$postfix_modify_alias = \&postfix::modify_postfix_alias;
	$postfix_delete_alias = \&postfix::delete_postfix_alias;

	# Work out if we can turn on automatic bcc'ing
	if ($config{'bccs'}) {
		$sender_bcc_maps = &postfix::get_real_value("sender_bcc_maps");
		@sender_bcc_map_files = &postfix::get_maps_files(
						$sender_bcc_maps);
		if (@sender_bcc_map_files) {
			$supports_bcc = 1;
			}
		}

	# Work out if per-domain outgoing IP support is available
	if (&compare_versions($postfix::postfix_version, 2.7) >= 0) {
		$dependent_maps = &postfix::get_real_value(
			"sender_dependent_default_transport_maps");
		@dependent_map_files = &postfix::get_maps_files(
						$dependent_maps);
		if (@dependent_map_files) {
			$supports_dependent = 1;
			}
		}

	$supports_aliascopy = 1;
	}
elsif ($config{'mail_system'} == 2 || $config{'mail_system'} == 4 ||
       $config{'mail_system'} == 5) {
	# Using qmail for email
	&foreign_require("qmailadmin", "qmail-lib.pl");
	%qmconfig = &foreign_config("qmailadmin");
	$can_alias_types{2} = 0;	# cannot use addresses in file
	$can_alias_types{8} = 0;	# cannot use same in other domain
	if ($config{'mail_system'} == 5) {
		$vpopbin = "$config{'vpopmail_dir'}/bin";
		}
	if ($config{'mail_system'} == 4) {
		# Qmail+LDAP can only alias to email addresses
		foreach my $t (3, 4, 5, 6, 7, 9, 10, 11) {
			$can_alias_types{$t} = 0;
			}
		}
	elsif ($config{'mail_system'} == 5) {
		# VPOPMail can use local addresses, files, mailbox, bouncer,
		# deleter and autoresponder
		foreach my $t (5, 6, 7, 8) {
			$can_alias_types{$t} = 0;
			}
		$can_alias_types{12} = 1
			if (&has_command($config{'vpopmail_auto'}));
		}
	else {
		# Plain Qmail cannot use the bouncer
		$can_alias_types{7} = 0;
		$can_alias_types{9} = 0;
		$can_alias_types{10} = 0;
		}
	$can_alias_comments = 0;
	$supports_aliascopy = 0;
	}
elsif ($config{'mail_system'} == 6) {
	# Using sendmail for email
	&foreign_require("exim", "exim-lib.pl");
	%xconfig = &foreign_config("exim");
	$can_alias_comments = 0;
	$supports_aliascopy = 0;
	}
}

# list_domain_aliases(&domain, [ignore-plugins])
# Returns just virtusers for some domain
sub list_domain_aliases
{
local ($d, $ignore_plugins) = @_;
&require_mail();
local ($u, %foruser);
if ($config{'mail_system'} != 4) {
	# Filter out aliases that point to users
	foreach $u (&list_domain_users($d, 0, 1, 1, 1)) {
		local $pop3 = &remove_userdom($u->{'user'}, $d);
		$foruser{$pop3."\@".$d->{'dom'}} = $u->{'user'};
		if ($config{'mail_system'} == 0 && $u->{'user'} =~ /\@/) {
			# Special case for Postfix @ users
			$foruser{$pop3."\@".$d->{'dom'}} =
				&replace_atsign($u->{'user'});
			}
		}
	if ($d->{'mail'}) {
		$foruser{$d->{'user'}."\@".$d->{'dom'}} = $d->{'user'};
		}
	}
local @virts = &list_virtusers();
local %ignore;
if ($ignore_plugins) {
	# Get a list to ignore from each plugin
	foreach my $f (&list_feature_plugins()) {
		foreach my $i (&plugin_call($f, "virtusers_ignore", $d)) {
			$ignore{lc($i)} = 1;
			}
		}
	}
if ($ignore_plugins && $d->{'spam'}) {
	# Skip spamtrap and hamtrap aliases
	foreach my $v (@virts) {
		if ($v->{'from'} =~ /^(spamtrap|hamtrap)\@/ &&
		    @{$v->{'to'}} == 1 &&
		    $v->{'to'}->[0] =~ /^\Q$trap_base_dir\E\//) {
			$ignore{lc($v->{'from'})} = 1;
			}
		}
	}

# Return only virtusers that match this domain,
# which are not for forwarding email for users in the domain,
# and which are not on the plugin ignore list.
return grep { $_->{'from'} =~ /\@(\S+)$/ && lc($1) eq lc($d->{'dom'}) &&
	      !($foruser{$_->{'from'}} eq $_->{'to'}->[0] &&
		@{$_->{'to'}} == 1) &&
	      !$ignore{lc($_->{'from'})} } @virts;
}

# setup_mail(&domain, [no-aliases])
# Adds a domain to the list of those accepted by the mail system
sub setup_mail
{
&$first_print($text{'setup_doms'});
&obtain_lock_mail($_[0]);
&complete_domain($_[0]);
&require_mail();
local $tmpl = &get_template($_[0]->{'template'});
if ($config{'mail_system'} == 1) {
	# Just add to sendmail local domains file
	local $conf = &sendmail::get_sendmailcf();
	local $cwfile;
	local @dlist = &sendmail::get_file_or_config($conf, "w", undef,
						     \$cwfile);
	&lock_file($cwfile) if ($cwfile);
	&lock_file($sendmail::config{'sendmail_cf'});
	&sendmail::add_file_or_config($conf, "w", $_[0]->{'dom'});
	&flush_file_lines();
	&unlock_file($sendmail::config{'sendmail_cf'});
	&unlock_file($cwfile) if ($cwfile);
	if (!$no_restart_mail) {
		&sendmail::restart_sendmail();
		}
	}
elsif ($config{'mail_system'} == 0) {
	# Add a special postfix virtual entry just for the domain
	&create_virtuser({ 'from' => $_[0]->{'dom'},
			   'to' => [ $_[0]->{'dom'} ] });
	}
elsif ($config{'mail_system'} == 2) {
	# Add to qmail rcpthosts file and virtualdomains file
	local $rlist = &qmailadmin::list_control_file("rcpthosts");
	push(@$rlist, $_[0]->{'dom'});
	&qmailadmin::save_control_file("rcpthosts", $rlist);

	local $virtmap = { 'domain' => $_[0]->{'dom'},
			   'prepend' => $_[0]->{'prefix'}.'pfx' };
	&qmailadmin::create_virt($virtmap);
	if (!$no_restart_mail) {
		&qmailadmin::restart_qmail();
		}
	}
elsif ($config{'mail_system'} == 4) {
	# Just add to qmail locals file, as virtualdomains is not
	# needed for qmail+ldap
	local $llist = &qmailadmin::list_control_file("locals");
	push(@$llist, $_[0]->{'dom'});
	&qmailadmin::save_control_file("locals", $llist);
	&execute_command("cd /etc/qmail && make");
	if (!$no_restart_mail) {
		&qmailadmin::restart_qmail();
		}
	}
elsif ($config{'mail_system'} == 5) {
	# Call vpopmail domain creation program
	local $qdom = quotemeta($_[0]->{'dom'});
	local $qpass = quotemeta($_[0]->{'pass'});
	local $qowner = '';
	local $qdir = '';
	if ($config{'vpopmail_owner'}) {
		local $quid = quotemeta($_[0]->{'uid'});
		local $qgid = quotemeta($_[0]->{'gid'});
		$qowner = "-i $quid -g $qgid"
	}
	if ($config{'vpopmail_maildir'}) {
		local $qmdir = quotemeta($_[0]->{'home'}.'/'.$config{'vpopmail_maildir'});
		$qdir = "-d $qmdir";
		if (!-e $qmdir) {
			mkdir($_[0]->{'home'}.'/'.$config{'vpopmail_maildir'});
			chown($_[0]->{'uid'},$_[0]->{'gid'},$_[0]->{'home'}.'/'.$config{'vpopmail_maildir'})
		}
	}
	local $out;
	local $errorlabel;
	if ($_[0]->{'alias'} && !$_[0]->{'aliasmail'}) {
		local $aliasdom = &get_domain($_[0]->{'alias'});
		$out = &backquote_command(
		    "$vpopbin/vaddaliasdomain $qdom $aliasdom->{'dom'} 2>&1");
		$errorlabel = 'setup_evaddaliasdomain';
		}
	else {
		$errorlabel = 'setup_evadddomain';
		$out = &backquote_command(
		    "$vpopbin/vadddomain $qdir $qowner $qdom $qpass 2>&1");
		}
	if ($?) {
		&$second_print(&text($label, "<tt>$out</tt>"));
		return;
		}
	}
elsif ($config{'mail_system'} == 6) {
	&exim::add_local_domain( $_[0]->{'dom'} );
	}

&$second_print($text{'setup_done'});

# Create any aliases specified in the template, if missing
if (!$_[1] && !$_[0]->{'no_tmpl_aliases'}) {
	local %gotvirt;
	foreach my $v (&list_virtusers()) {
		$gotvirt{$v->{'from'}} = $v;
		}
	if ($_[0]->{'alias'}) {
		# Alias all mail to this domain to a different domain
		local $aliasdom = &get_domain($_[0]->{'alias'});
		if ($supports_aliascopy && !$_[0]->{'aliasmail'}) {
			$_[0]->{'aliascopy'} = $tmpl->{'aliascopy'};
			}
		if ($_[0]->{'aliascopy'}) {
			# Sync all virtusers from the dest domain
			&copy_alias_virtuals($_[0], $aliasdom);
			}
		elsif (!$gotvirt{'@'.$_[0]->{'dom'}}) {
			# Just create a catchall
			&create_virtuser({ 'from' => '@'.$_[0]->{'dom'},
				   'to' => [ '%1@'.$aliasdom->{'dom'} ] })
			}
		}
	elsif (&has_deleted_aliases($_[0])) {
		# Restore aliases from before mail was deleted
		my @deleted = &get_deleted_aliases($_[0]);
		foreach my $a (@deleted) {
			&create_virtuser($a) if (!$gotvirt{$a->{'from'}}++);
			}
		&clear_deleted_aliases($_[0]);
		}
	elsif ($tmpl->{'dom_aliases'} && $tmpl->{'dom_aliases'} ne "none") {
		# Setup aliases from this domain based on the template
		&$first_print($text{'setup_domaliases'});
		local @aliases = split(/\t+/, $tmpl->{'dom_aliases'});
		local ($a, %acreate);
		foreach $a (@aliases) {
			local ($from, $to) = split(/=/, $a, 2);
			if ($config{'mail_system'} == 5 &&
			    lc($from) eq 'postmaster') {
				# Postmaster is created automatically
				# on vpopmail systems
				next;
				}
			$to = &substitute_domain_template($to, $_[0]);
			$from = $from eq "*" ? "\@$_[0]->{'dom'}" : "$from\@$_[0]->{'dom'}";
			if ($acreate{$from}) {
				push(@{$acreate{$from}->{'to'}}, $to);
				}
			else {
				$acreate{$from} = { 'from' => $from,
						    'to' => [ $to ] };
				}
			}
		foreach $a (values %acreate) {
			&create_virtuser($a) if (!$gotvirt{$a->{'from'}}++);
			}
		if ($tmpl->{'dom_aliases_bounce'} &&
		    !$acreate{"\@$_[0]->{'dom'}"} &&
		    !$gotvirt{'@'.$_[0]->{'dom'}} &&
		    $config{'mail_system'} != 0) {
			# Add bounce alias, if there isn't one yet, and if
			# we are not running Postfix.
			local $v = { 'from' => "\@$_[0]->{'dom'}",
				     'to' => [ 'BOUNCE' ] };
			&create_virtuser($v);
			$gotvirt{'@'.$_[0]->{'dom'}}++;
			}
		&$second_print($text{'setup_done'});
		}
	}

# Setup default BCC address
if ($supports_bcc && $tmpl->{'bccto'} ne 'none') {
	&$first_print(&text('mail_bccing', $tmpl->{'bccto'}));
	&save_domain_sender_bcc($_[0], $tmpl->{'bccto'});
	&$second_print($text{'setup_done'});
	}

# Setup any secondary MX servers
if (!$_[0]->{'nosecondaries'}) {
	&setup_on_secondaries($_[0]);
	}

# Create file containing all users' email addresses
if (!$_[0]->{'alias'} && !$_[0]->{'aliasmail'}) {
	&create_everyone_file($_[0]);
	}

# Add domain to DKIM list
&update_dkim_domains($_[0], 'setup');

# Request a call to sync to secondary MX servers after creation.
# create_virtuser cannot do this, as the domain doesn't exist yet
&register_post_action(\&sync_secondary_virtusers, $_[0]);

&release_lock_mail($_[0]);
}

# delete_mail(&domain, [leave-aliases])
# Removes a domain from the list of those accepted by the mail system
sub delete_mail
{
local ($d, $leave_aliases) = @_;

&$first_print($text{'delete_doms'});
&obtain_lock_mail($d);
&require_mail();

local $isalias = $d->{'alias'} && !$d->{'aliasmail'};
if ($isalias && !$d->{'aliascopy'} ||
    !$isalias && $config{'mail_system'} == 0) {
        # Remove whole-domain alias, for alias domains or regular domains using
	# Postfix
        local @virts = &list_virtusers();
        local ($catchall) = grep { lc($_->{'from'}) eq '@'.$d->{'dom'} }
				 @virts;
        if ($catchall) {
                &delete_virtuser($catchall);
                }
        }
elsif ($isalias && $d->{'aliascopy'}) {
	# Remove alias copy virtuals
	&delete_alias_virtuals($d);
	}

if ($config{'mail_system'} == 1) {
	# Delete domain from sendmail local domains file
	local $conf = &sendmail::get_sendmailcf();
	local $cwfile;
	local @dlist = &sendmail::get_file_or_config($conf, "w", undef,
						     \$cwfile);
	&lock_file($cwfile) if ($cwfile);
	&lock_file($sendmail::config{'sendmail_cf'});
	&sendmail::delete_file_or_config($conf, "w", $d->{'dom'});
	&flush_file_lines();
	&unlock_file($sendmail::config{'sendmail_cf'});
	&unlock_file($cwfile) if ($cwfile);

	# Also delete from generics domain file or list
	local $cgfile;
	local @dlist = &sendmail::get_file_or_config($conf, "G", undef,
                                                     \$cgfile);
	if (&indexof($d->{'dom'}, @dlist) >= 0) {
		&lock_file($cgfile) if ($cgfile);
		&lock_file($sendmail::config{'sendmail_cf'});
		&sendmail::delete_file_or_config($conf, "G", $d->{'dom'});
		&flush_file_lines();
		&unlock_file($sendmail::config{'sendmail_cf'});
		&unlock_file($cgfile) if ($cgfile);
		&sendmail::restart_sendmail();
		}

	if (!$no_restart_mail) {
		&sendmail::restart_sendmail();
		}
	}
elsif ($config{'mail_system'} == 0) {
	# Delete the special postfix virtuser
	local @virts = &list_virtusers();
	local ($lv) = grep { lc($_->{'from'}) eq $d->{'dom'} } @virts;
	if ($lv) {
		&delete_virtuser($lv);
		}
	local @md = split(/[, ]+/,
			  lc(&postfix::get_current_value("mydestination")));
	local $idx = &indexof($d->{'dom'}, @md);
	if ($idx >= 0) {
		# Delete old-style entry too
		&lock_file($postfix::config{'postfix_config_file'});
		splice(@md, $idx, 1);
		&postfix::set_current_value("mydestination", join(", ", @md));
		&unlock_file($postfix::config{'postfix_config_file'});
		if (!$no_restart_mail) {
			&shutdown_mail_server();
			&startup_mail_server();
			}
		}
	}
elsif ($config{'mail_system'} == 2 || $config{'mail_system'} == 4) {
	# Delete domain from qmail locals file, rcpthosts file and virtuals
	local $dlist = &qmailadmin::list_control_file("locals");
	$dlist = [ grep { lc($_) ne $d->{'dom'} } @$dlist ];
	&qmailadmin::save_control_file("locals", $dlist);

	local $rlist = &qmailadmin::list_control_file("rcpthosts");
	$rlist = [ grep { lc($_) ne $d->{'dom'} } @$rlist ];
	&qmailadmin::save_control_file("rcpthosts", $rlist);

	local ($virtmap) = grep { lc($_->{'domain'}) eq $d->{'dom'} &&
				  !$_->{'user'} } &qmailadmin::list_virts();
	&qmailadmin::delete_virt($virtmap) if ($virtmap);
        if ($config{'mail_system'} == 4) {
                &execute_command("cd /etc/qmail && make");
                }
	if (!$no_restart_mail) {
		&qmailadmin::restart_qmail();
		}
	}
elsif ($config{'mail_system'} == 5) {
	# Call vpopmail domain deletion program
	local $qdom = quotemeta($d->{'dom'});
	local $out = &backquote_logged("$vpopbin/vdeldomain $qdom 2>&1");
	if ($?) {
		&$second_print(&text('delete_evdeldomain', "<tt>$out</tt>"));
		return;
		}
	}
elsif ($config{'mail_system'} == 6) {
	&exim::remove_domain( $d->{'dom'} );
	}

&$second_print($text{'setup_done'});

if (!$leave_aliases) {
	# Delete all email aliases, saving them to a per-domain file
	# so they can be restored if email is later enabled.
	# The leave_aliases flag is only set to true when the whole virtual
	# server is being deleted, as aliases will be already removed in the
	# function delete_virtual_server.
	&$first_print($text{'delete_aliases'});
	local @deleted;
	foreach my $v (&list_virtusers()) {
		if ($v->{'from'} =~ /\@(\S+)$/ &&
		    $1 eq $d->{'dom'}) {
			&delete_virtuser($v);
			push(@deleted, $v);
			}
		}
	if (!$d->{'aliascopy'}) {
		&save_deleted_aliases($d, \@deleted);
		}
	&$second_print($text{'setup_done'});
	}

# Remove BCC address
if ($supports_bcc) {
	local $bcc = &get_domain_sender_bcc($d);
	if ($bcc) {
		&save_domain_sender_bcc($d, undef);
		}
	}

# Remove sender-dependent outgoing IP
if ($supports_dependent) {
	&save_domain_dependent($d, 0);
	}

# Remove any secondary MX servers
&delete_on_secondaries($d);

# Delete file containing all users' aliases
&delete_everyone_file($d);

# Remove domain from DKIM list
&update_dkim_domains($d, 'delete');

&release_lock_mail($d);
}

# clone_mail(&domain, &old-domain)
# Copy all mail aliases and mailboxes from the old domain to the new one
sub clone_mail
{
local ($d, $oldd) = @_;
&$first_print($text{'clone_mail2'});
if ($d->{'alias'} && !$d->{'aliasmail'}) {
	&$second_print($text{'clone_mailalias'});
	return 1;
	}
&obtain_lock_mail($d);
&obtain_lock_cron($d);

# Clone all users
local $ucount = 0;
local $hb = "$d->{'home'}/$config{'homes_dir'}";
local $mail_under_home = &mail_under_home();
foreach my $u (&list_domain_users($oldd, 1, 0, 0, 0)) {
	local $newu = { %$u };
	local $as = &guess_append_style($u->{'user'}, $oldd);
	local $ushort = &remove_userdom($u->{'user'}, $oldd);
	$newu->{'user'} = &userdom_name($ushort, $d, $as);
	if ($u->{'uid'} == $d->{'uid'}) {
		# Web management user, so same UID as new domain
		$newu->{'uid'} = $d->{'uid'};
		}
	else {
		# Allocate UID
		local %taken;
		&build_taken(\%taken);
		$newu->{'uid'} = &allocate_uid(\%taken);
		}
	$newu->{'gid'} = $d->{'gid'};
	$newu->{'home'} =~ s/^\Q$oldd->{'home'}\E/$d->{'home'}/;

	# Fix email addresses
	$newu->{'email'} =~ s/\@\Q$oldd->{'dom'}\E/\@$d->{'dom'}/;
	foreach my $extra (@{$newu->{'extraemail'}}) {
		$extra =~ s/\@\Q$oldd->{'dom'}\E/\@$d->{'dom'}/;
		}

	# Fix database access list
	local @newdbs;
	foreach my $db (@{$newu->{'dbs'}}) {
		local $newprefix = &fix_database_name($d->{'prefix'},
						      $db->{'type'});
		local $oldprefix = &fix_database_name($oldd->{'prefix'},
						      $db->{'type'});
		if ($db->{'name'} eq $oldd->{'db'}) {
			# Use new main DB
			$db->{'name'} = $d->{'db'};
			}
		elsif ($db->{'name'} !~ s/\Q$oldprefix\E/$newprefix/) {
			# If cannot replace old prefix with new, prepend
			# the new prefix to match what is done when the
			# DB is cloned
			$db->{'name'} = $newprefix.$db->{'name'};
			}
		push(@newdbs, $db);
		}
	$newu->{'dbs'} = \@newdbs;

	# Fix email forwarding destinations
	foreach my $t (@{$newu->{'to'}}) {
		local ($atype, $adest) = &alias_type($t, $u->{'user'});
		if ($atype == 1) {
			# Change destination to new domain
			$t =~ s/\@\Q$oldd->{'dom'}\E$/\@$d->{'dom'}/;
			}
		elsif ($atype == 2 || $atype == 3 || $atype == 4 ||
		       $atype == 5 || $atype == 6) {
			if ($adest =~ /^\Q$oldd->{'home'}\E\/(\S+)$/) {
				# Rename the autoreply file too
				local $newadest = "$d->{'home'}/$1";
				$newadest =~ s/\@\Q$oldd->{'dom'}\E/\@$d->{'dom'}/g;
				&rename_logged($adest, $newadest);
				}
			$t =~ s/\Q$oldd->{'home'}\E/$d->{'home'}/g;
			if ($atype == 5) {
				# Change domain name and ID in autoreply files
				$t =~ s/\@\Q$oldd->{'dom'}\E/\@$d->{'dom'}/g;
				$t =~ s/\Q$oldd->{'id'}\E/$d->{'id'}/g;
				}
			}
		}

	# Create the user
	&create_user($newu, $d);
	&create_mail_file($newu, $d);

	# Clone mail files under /var/mail , if needed
	if ($mail_under_home) {
		local $oldmf = &user_mail_file($u);
		local $newmf = &user_mail_file($newu);
		local @st = stat($newmf);
		if (@st && -r $oldmf) {
			&copy_source_dest($oldmf, $newmf);
			&set_ownership_permissions(
				$st[5], $st[5], $st[2]&0777, $newmf);
			}
		}

	# Fix home directory permissions
	if (-d $newu->{'home'} && &is_under_directory($hb, $newu->{'home'})) {
		&execute_command("chown -R $newu->{'uid'}:$newu->{'gid'} ".
                       quotemeta($newu->{'home'}));
		}

	# Copy user cron jobs
	&copy_unix_cron_jobs($newu->{'user'}, $u->{'user'});

	$ucount++;
	}
&$second_print(&text('clone_maildone', $ucount));

# Clone all aliases
&$first_print($text{'clone_mail1'});
local %already = map { $_->{'from'}, $_ } &list_domain_aliases($d, 0);
local $acount = 0;
foreach my $a (&list_domain_aliases($oldd, 1)) {
	local ($mailbox, $dom) = split(/\@/, $a->{'from'});
	local @to;
	foreach my $t (@{$a->{'to'}}) {
		local ($atype, $adest) = &alias_type($t, $a->{'from'});
		if ($atype == 1) {
			$t =~ s/\@\Q$oldd->{'dom'}\E$/\@$d->{'dom'}/;
			}
		elsif ($atype == 2 || $atype == 3 || $atype == 4 ||
		       $atype == 5 || $atype == 6) {
			if ($adest =~ /^\Q$oldd->{'home'}\E\/(\S+)$/) {
				# Rename the autoreply file too
				local $newadest = "$d->{'home'}/$1";
				$newadest =~ s/\@\Q$oldd->{'dom'}\E/\@$d->{'dom'}/g;
				&rename_logged($adest, $newadest);
				}
			$t =~ s/\Q$oldd->{'home'}\E/$d->{'home'}/g;
			if ($atype == 5) {
				# Change domain name and ID in autoreply files
				$t =~ s/\@\Q$oldd->{'dom'}\E/\@$d->{'dom'}/g;
				$t =~ s/\Q$oldd->{'id'}\E/$d->{'id'}/g;
				}
			}
		elsif ($atype == 13) {
			$t =~ s/\Q$oldd->{'id'}\E/$d->{'id'}/;
			}
		push(@to, $t);
		}
	local $newa = { 'from' => $mailbox."\@".$d->{'dom'},
			'cmt' => $a->{'cmt'},
			'to' => \@to };
	if (!$already{$newa->{'from'}}) {
		&create_virtuser($newa);
		$acount++;
		}
	}
&create_autoreply_alias_links($d);
&sync_alias_virtuals($d);
&$second_print(&text('clone_maildone', $acount));

&release_lock_cron($d);
&release_lock_mail($d);
return 1;
}

# modify_mail(&domain, &olddomain)
# Deal with a change in domain name, UID or home.
# Note - this may be called even for domains without mail enabled, in order to
# just update users.
sub modify_mail
{
local $tmpl = &get_template($_[0]->{'template'});
&require_useradmin();
local $our_mail_locks = 0;
local $our_unix_locks = 0;

# Special case - conversion of an alias domain to non-alias
local $isalias = $_[0]->{'alias'} && !$_[0]->{'aliasmail'};
local $wasalias = $_[1]->{'alias'} && !$_[1]->{'aliasmail'};
if ($wasalias && !$isalias) {
	&obtain_lock_mail($_[0]);
	if ($_[0]->{'aliascopy'}) {
		# Stop copying mail aliases
		&$first_print($text{'save_mailunalias1'});
		$_[0]->{'aliascopy'} = 0;
		&delete_alias_virtuals($_[0]);
		}
	else {
		# Remove catchall
		&$first_print($text{'save_mailunalias2'});
		local ($catchall) = grep { $_->{'from'} eq '@'.$_[0]->{'dom'} }
					 &list_virtusers();
		if ($catchall) {
			&delete_virtuser($catchall);
			}
		}
	&$second_print($text{'setup_done'});
	&release_lock_mail($_[0]);
	return 1;
	}

# Need to update the home directory of all mail users .. but only
# in the Unix object, as their files will have already been moved
# as part of the domain's directory.
# No need to do this for VPOPMail users.
# Also, any users in the user@domain name format need to be renamed
local %renamed = ( $_[1]->{'user'} => $_[0]->{'user'} );
if (($_[0]->{'home'} ne $_[1]->{'home'} ||
     $_[0]->{'dom'} ne $_[1]->{'dom'} ||
     $_[0]->{'gid'} != $_[1]->{'gid'} ||
     $_[0]->{'prefix'} ne $_[1]->{'prefix'}) && !$isalias) {
	&obtain_lock_mail($_[0]); $our_mail_locks++;
	&obtain_lock_unix($_[0]); $our_unix_locks++;
	&$first_print($text{'save_mailrename'});
	local $u;
	local $domhack = { %{$_[0]} };		# This hack is needed to find
	$domhack->{'home'} = $_[1]->{'home'};	# users under the old home dir
	$domhack->{'gid'} = $_[1]->{'gid'};	# and GID and parent
	$domhack->{'parent'} = $_[1]->{'parent'};
	foreach $u (&list_domain_users($domhack, 1)) {
		local %oldu = %$u;
		if ($_[0]->{'home'} ne $_[1]->{'home'} &&
		    $config{'mail_system'} != 5) {
			# Change home directory
			$u->{'home'} =~ s/$_[1]->{'home'}/$_[0]->{'home'}/;
			}
		local $olddom = $_[1]->{'dom'};
		if ($_[0]->{'dom'} ne $_[1]->{'dom'} &&
		    $tmpl->{'append_style'} == 6 &&
		    $u->{'user'} =~ /^(.*)\@\Q$olddom\E$/) {
			# Rename this guy, as he is using an @domain name
			local $pop3 = $1;
			$u->{'user'} = &userdom_name($pop3, $_[0]);
			if ($u->{'email'}) {
				$u->{'email'} = "$pop3\@$_[0]->{'dom'}";
				}
			}
		elsif ($_[0]->{'prefix'} ne $_[1]->{'prefix'}) {
			# Username prefix has changed, so user may need to be
			# renamed.
			$u->{'user'} =~ s/^\Q$_[1]->{'prefix'}\E([\.\-])/$_[0]->{'prefix'}$1/ ||
				$u->{'user'} =~ s/([\.\-])\Q$_[1]->{'prefix'}\E$/$1$_[0]->{'prefix'}/;
			}
		if ($_[0]->{'gid'} != $_[1]->{'gid'}) {
			# Domain owner has changed, so user's GID must too ..
			# and so must the GID on his files
			$u->{'gid'} = $_[0]->{'gid'};
			&useradmin::recursive_change($u->{'home'},
				$u->{'uid'}, $_[1]->{'gid'},
				$u->{'uid'}, $_[0]->{'gid'});
			}
		if ($_[0]->{'uid'} != $_[1]->{'uid'} &&
 		    $u->{'uid'} == $_[1]->{'uid'}) {
			# Website FTP access user's UID needs to change
			$u->{'uid'} = $_[0]->{'uid'};
			}

		if ($_[0]->{'mail'}) {
			# Update email address attributes for the user, as these
			# are used in LDAP
			if ($u->{'email'}) {
				$u->{'email'} =~
				    s/\@\Q$_[1]->{'dom'}\E$/\@$_[0]->{'dom'}/;
				}
			local @newextra;
			foreach my $extra (@{$u->{'extraemail'}}) {
				my $newextra = $extra;
				$newextra =~
				    s/\@\Q$_[1]->{'dom'}\E$/\@$_[0]->{'dom'}/;
				push(@newextra, $newextra);
				}
			$u->{'extraemail'} = \@newextra;
			}

		# Save the user
		&modify_user($u, \%oldu, $_[0], 1);
		if (!$u->{'nomailfile'} && $_[0]->{'mail'}) {
			&rename_mail_file($u, \%oldu);
			}
		if ($oldu{'user'} ne $u->{'user'}) {
			$renamed{$oldu{'user'}} = $u->{'user'};
			}
		}
	&$second_print($text{'setup_done'});
	}
	
if ($isalias && $_[2] && $_[2]->{'dom'} ne $_[3]->{'dom'}) {
	# This is an alias, and the domain it is aliased to has changed ..
	# update the catchall alias or virtuser copies
	&obtain_lock_mail($_[0]); $our_mail_locks++;
	if (!$_[0]->{'aliascopy'}) {
		# Fixup dest in catchall
		local @virts = &list_virtusers();
		local ($catchall) = grep {
			$_->{'to'}->[0] eq '%1@'.$_[3]->{'dom'} } @virts;
		if ($catchall) {
			&$first_print($text{'save_mailalias'});
			$catchall->{'to'} = [ '%1@'.$_[2]->{'dom'} ];
			&modify_virtuser($catchall, $catchall);
			&$second_print($text{'setup_done'});
			}
		}
	else {
		# Re-write all copied virtuals
		&copy_alias_virtuals($_[0], $_[2]);
		}
	}
elsif ($isalias && $_[0]->{'dom'} ne $_[1]->{'dom'} &&
       $_[0]->{'aliascopy'}) {
	# This is an alias and the domain name has changed - fix all virtuals
	&obtain_lock_mail($_[0]); $our_mail_locks++;
	&delete_alias_virtuals($_[1]);
	local $alias = &get_domain($_[0]->{'alias'});
	&copy_alias_virtuals($_[0], $alias);
	}

if ($_[0]->{'dom'} ne $_[1]->{'dom'} && $_[0]->{'mail'}) {
	# Delete the old mail domain and add the new
	local $no_restart_mail = 1;
	local $oldbcc;
	if ($supports_bcc) {
		$oldbcc = &get_domain_sender_bcc($_[1]);
		}
	&delete_mail($_[1], 1);
	&setup_mail($_[0], 1);
	if ($supports_bcc) {
		$oldbcc =~ s/\Q$_[1]->{'dom'}\E/$_[0]->{'dom'}/g;
		&save_domain_sender_bcc($_[0], $oldbcc);
		}
	&require_mail();
	if (&is_mail_running()) {
		if ($config{'mail_system'} == 1) {
			&sendmail::restart_sendmail();
			}
		elsif ($config{'mail_system'} == 0) {
			&shutdown_mail_server();
			&startup_mail_server();
			}
		elsif ($config{'mail_system'} == 2 ||
		       $config{'mail_system'} == 4) {
			&qmailadmin::restart_qmail();
			}
		elsif ($config{'mail_system'} == 6) {
			&exim::restart_exim();
			}
		}

	if (!$_[0]->{'aliascopy'}) {
		# Update any virtusers with addresses in the old domain
		&$first_print($text{'save_fixvirts'});
		foreach $v (&list_virtusers()) {
			if ($v->{'from'} =~ /^(\S*)\@(\S+)$/ &&
			    lc($2) eq $_[1]->{'dom'}) {
				local $oldv = { %$v };
				local $u = $1;
				if ($u eq $_[1]->{'user'}) {
					# For admin user, who has changed
					$u = $_[0]->{'user'};
					}
				$v->{'from'} = "$u\@$_[0]->{'dom'}";
				&fix_alias_when_renaming($v, $_[0], $_[1]);
				&modify_virtuser($oldv, $v);
				}
			}
		}

	if (!$isalias) {
		# Update any generics/sender canonical entries in the old domain
		if ($config{'generics'}) {
			local %ghash = &get_generics_hash();
			foreach my $g (values %ghash) {
				if ($g->{'to'} =~ /^(.*)\@(\S+)$/ &&
				    $2 eq $_[1]->{'dom'}) {
					local $oldg = { %$g };
					local $u = $1;
					if ($u eq $_[1]->{'user'}) {
						# For admin user, who has
						# changed name
						$u = $_[0]->{'user'};
						}
					if ($renamed{$g->{'from'}}) {
						# Username has been changed by
						# the rename process
						$g->{'from'} =
						  $renamed{$g->{'from'}};
						}
					$g->{'to'} = "$u\@$_[0]->{'dom'}";
					&modify_generic($g, $oldg);
					}
				}
			}

		# Make a second pass through users to fix aliases
		&flush_virtualmin_caches();
		foreach my $u (&list_domain_users($_[0])) {
			local $oldu = { %$u };
			if (&fix_alias_when_renaming($u, $_[0], $_[1])) {
				&modify_user($u, $oldu, $_[0]);
				}
			}
		}

	&$second_print($text{'setup_done'});
	}

# Re-write the file containing all users' addresses, in case the domain changed 
if (!$isalias) {
	&create_everyone_file($_[0]);
	}

# Update domain in DKIM list, if DNS was enabled or disabled
if ($_[0]->{'dns'} && !$_[1]->{'dns'}) {
	&update_dkim_domains($_[0], 'setup');
	}
elsif (!$_[0]->{'dns'} && $_[1]->{'dns'}) {
	&update_dkim_domains($_[0], 'delete');
	}

# Update any outgoing IP mapping
if (($_[0]->{'dom'} ne $_[1]->{'dom'} ||
     $_[0]->{'ip'} ne $_[1]->{'ip'}) && $supports_dependent) {
	local $old_dependent = &get_domain_dependent($_[1]);
	if ($old_dependent) {
		&save_domain_dependent($_[1], 0);
		&save_domain_dependent($_[0], 1);
		}
	}

# If contact email changed, update aliases to it
if ($_[0]->{'emailto'} ne $_[1]->{'emailto'}) {
	&$first_print($text{'save_mailto'});
	local @tmplaliases = split(/\t+/, $tmpl->{'dom_aliases'});
	local @aliases = &list_domain_aliases($_[0]);
	foreach $a (@tmplaliases) {
                local ($from, $to) = split(/=/, $a, 2);
		local ($virt) = grep { $_->{'from'} eq
				       $from."\@".$_[0]->{'dom'} } @aliases;
		next if (!$virt);
		next if ($virt->{'to'}->[0] ne $_[1]->{'emailto'});
		local $oldvirt = { %$virt };
		$virt->{'to'}->[0] = $_[0]->{'emailto'};
		&modify_virtuser($oldvirt, $virt);
		}
	&sync_alias_virtuals($_[0]);
	&$second_print($text{'setup_done'});
	}

# Unlock mail and unix DBs the same number of times we locked them
while($our_mail_locks--) {
	&release_lock_mail($_[0]);
	}
while($our_unix_locks--) {
	&release_lock_unix($_[0]);
	}
}

# fix_alias_when_renaming(&alias|&user, &dom, &olddom)
# When renaming a domain, fix up the destination addresses in the given
# alias or user.
sub fix_alias_when_renaming
{
local ($virt, $dom, $olddom) = @_;
local $changed = 0;
local @newto = ( );
foreach my $ot (@{$virt->{'to'}}) {
	local $t = $ot;
	if ($t =~ /^(\S*)\@(\S+)$/ &&
	    lc($2) eq $olddom->{'dom'}) {
		# Destination is an address in the
		# domain being renamed
		$t = "$1\@$dom->{'dom'}";
		}
	elsif ($t =~ /^\Q$olddom->{'prefix'}\E([\.\-].*)$/) {
		# Destination is a user being renamed,
		# with prefix at start
		$t = "$dom->{'prefix'}$1";
		}
	elsif ($t =~ /^(.*[\.\-])\Q$olddom->{'prefix'}\E$/) {
		# Destination is a user being renamed,
		# with prefix at end
		$t = "$1$dom->{'prefix'}";
		}

	# Change home directory references, for auto-
	# reply files.
	local $type = &alias_type($t);
	if ($type == 5) {
		$t =~ s/\Q$olddom->{'home'}\E/$dom->{'home'}/g;
		$t =~ s/\Q$olddom->{'dom'}\E /$dom->{'dom'} /g;
		}
	$changed++ if ($t ne $ot);
	push(@newto, $t);
	}
$virt->{'to'} = \@newto;
return $changed;
}

# validate_mail(&domain)
# Returns an error message if the server is not setup to receive mail for
# this domain, or if mail users have incorrect permissions.
sub validate_mail
{
local ($d) = @_;

# Check if this server is receiving email
return &text('validate_email', "<tt>$d->{'dom'}</tt>")
	if (!&is_local_domain($d->{'dom'}) && !$d->{'disabled'});

# Check any secondary MX servers
local %ids = map { $_, 1 } split(/\s+/, $d->{'mx_servers'});
local @servers = grep { $ids{$_->{'id'}} } &list_mx_servers();
foreach my $s (@servers) {
	next if (!$ids{$s->{'id'}});
	local $ok = &is_one_secondary($d, $s);
	if ($ok eq '0') {
		return &text('validate_emailmx', $s->{'host'});
		}
	elsif ($ok ne '1') {
		return &text('validate_emailmx2', $s->{'host'}, $ok);
		}
	}

# Check mailbox permissions
if ($config{'mail_system'} != 5) {	# skip for vpopmail
	local %doneuid;
	foreach my $user (&list_domain_users($d, 1)) {
		if (!$user->{'webowner'} && $doneuid{$user->{'uid'}}++) {
			return &text('validate_emailuid', $user->{'user'},
							  $user->{'uid'});
			}
		local @st = stat($user->{'home'});
		if (!@st) {
			return &text('validate_emailhome', $user->{'user'},
							   $user->{'home'});
			}
		if ($st[4] != $user->{'uid'}) {
			local $ru = getpwuid($st[4]) || $user->{'uid'};
			return &text('validate_emailhomeu',
				$user->{'user'}, $user->{'home'}, $ru);
			}
		if ($st[5] != $user->{'gid'}) {
			local $rg = getgrgid($st[5]) || $user->{'gid'};
			return &text('validate_emailhomeg',
				$user->{'user'}, $user->{'home'}, $rg);
			}
		}
	}
return undef;
}

# disable_mail(&domain)
# Turn off mail for the domain, and disable login for all users
sub disable_mail
{
&obtain_lock_mail($_[0]);
&obtain_lock_unix($_[0]);
if ($config{'mail_system'} == 5) {
	# Just call vpopmail's disable function
	local $qdom = quotemeta($_[0]->{'dom'});
	&system_logged("$vpopbin/vmoduser -p $qdom 2>&1");
	}
else {
	# Delete mail access for the domain
	&delete_mail($_[0], 1);
	}

&$first_print($text{'disable_users'});
foreach my $user (&list_domain_users($_[0], 1)) {
	if (!$user->{'alwaysplain'}) {
		&set_pass_disable($user, 1);
		&modify_user($user, $user, $_[0]);
		}
	if ($user->{'unix'}) {
		&disable_unix_cron_jobs($user->{'user'});
		}
	}
&$second_print($text{'setup_done'});
&release_lock_mail($_[0]);
&release_lock_unix($_[0]);
}

# enable_mail(&domain)
# Turn on mail for the domain, and re-enable login for all users
sub enable_mail
{
&obtain_lock_mail($_[0]);
&obtain_lock_unix($_[0]);
if ($config{'mail_system'} == 5) {
	# Just call vpopmail's enable function
	local $qdom = quotemeta($_[0]->{'dom'});
	&system_logged("$vpopbin/vmoduser -x $qdom 2>&1");
	}
else {
	# Re-enable mail, and re-copy aliases from target domain (if any)
	&setup_mail($_[0], 1);
	if ($_[0]->{'alias'} && !$_[0]->{'aliasmail'} && $_[0]->{'aliascopy'}) {
		my $target = &get_domain($_[0]->{'alias'});
		&copy_alias_virtuals($_[0], $target);
		}
	}

&$first_print($text{'enable_users'});
foreach my $user (&list_domain_users($_[0], 1)) {
	if (!$user->{'alwaysplain'}) {
		&set_pass_disable($user, 0);
		&modify_user($user, $user, $_[0]);
		}
	if ($user->{'unix'}) {
		&enable_unix_cron_jobs($user->{'user'});
		}
	}
&$second_print($text{'setup_done'});
&release_lock_mail($_[0]);
&release_lock_unix($_[0]);
}

# check_mail_clash()
# Does nothing, because no clash checking is needed.
# Except for qmail, where we have to check for clash with hostname.
sub check_mail_clash
{
local ($dname) = @_;
if ($config{'mail_system'} == 2 || $config{'mail_system'} == 4) {
	# Qmail virtualdomains don't work if the domain name is the same
	# as the hostname
	&require_mail();
	local $qme = &qmailadmin::get_control_file("me");
	$qme ||= &get_system_hostname();
	if ($dname eq $qme) {
		return &text('setup_qmailme', "<tt>$qme</tt>");
		}
	}
return 0;
}

# is_local_domain(domain)
# Returns 1 if some domain is used for mail on this system, 0 if not
sub is_local_domain
{
local $found = 0;
&require_mail();
if ($config{'mail_system'} == 1) {
	# Check Sendmail local domains file
	local $conf = &sendmail::get_sendmailcf();
        local @dlist = &sendmail::get_file_or_config($conf, "w");
	foreach my $d (@dlist) {
		$found++ if (lc($d) eq lc($_[0]));
		}
	}
elsif ($config{'mail_system'} == 0) {
	# Check Postfix virtusers and mydestination
	local @virts = &list_virtusers();
	local ($lv) = grep { lc($_->{'from'}) eq $_[0] } @virts;
	$found++ if ($lv);
	local @md = split(/[, ]+/,&postfix::get_current_value("mydestination"));
	local $hostname = lc(&get_system_hostname());
	foreach my $md (@md) {
		$found++ if (lc($md) eq lc($_[0]) ||
			     $md eq '$myhostname' && lc($_[0]) eq $hostname);
		}
	}
elsif ($config{'mail_system'} == 2) {
	# Check qmail rcpthosts and virtualdomains files
	local $rlist = &qmailadmin::list_control_file("rcpthosts");
	@$rlist = map { lc($_) } @$rlist;
	local ($virtmap) = grep { lc($_->{'domain'}) eq $_[0]->{'dom'} &&
				  !$_->{'user'} } &qmailadmin::list_virts();
	$found++ if (&indexof($_[0], @$rlist) >= 0 && $virtmap);
	}
elsif ($config{'mail_system'} == 4) {
	# Check qmail locals file
	local $rlist = &qmailadmin::list_control_file("locals");
	@$rlist = map { lc($_) } @$rlist;
	$found++ if (&indexof($_[0], @$rlist) >= 0);
	}
elsif ($config{'mail_system'} == 5) {
	# Check active vpopmail domains
	$found = -e "$config{'vpopmail_dir'}/domains/$_[0]";
	}
elsif ($config{'mail_system'} == 6) {
	# Look in Exim domains list
	local @dlist = &exim::list_domains();
	foreach my $d (@dlist) {
		$found++ if (lc($d) eq lc($_[0]));
		}
	}
return $found;
}

# list_virtusers([include-everything])
# Returns a list of a virtual mail address mappings. Each may actually have
# an alias as its destination, and is automatically expanded to the
# destinations for that alias.
sub list_virtusers
{
local ($incall) = @_;

# Build list of unix users, to exclude aliases with same name as users
# (which are picked up by list_domain_users instead).
&require_mail();
if (!%unix_user) {
	&require_useradmin(1);
	foreach my $u (&list_all_users()) {
		$unix_user{&escape_alias($u->{'user'})}++;
		}
	}

# Build a list of copy-mode alias domains, as their Sendmail and Postfix
# virtusers shouldn't be included
local %alias_copy;
if ($supports_aliascopy && !$incall) {
	foreach my $d (&get_domain_by("alias", "_ANY_")) {
		if ($d->{'aliascopy'}) {
			$alias_copy{$d->{'dom'}}++;
			}
		}
	}

if ($config{'mail_system'} == 1) {
	# Get from sendmail
	local @svirts = &sendmail::list_virtusers($sendmail_vfile);
	local %aliases = map { lc($_->{'name'}), $_ }
			 grep { $_->{'enabled'} &&
				(!$unix_user{$_->{'name'}} || $incall) }
				&sendmail::list_aliases($sendmail_afiles);
	local ($v, $a, @virts);
	foreach $v (@svirts) {
		local %rv = ( 'virt' => $v,
			      'cmt' => $v->{'cmt'},
			      'from' => lc($v->{'from'}) );
		local ($mb, $dname) = split(/\@/, $rv{'from'});
		next if ($alias_copy{$dname});
		if ($v->{'to'} !~ /\@/ && ($a = $aliases{lc($v->{'to'})})) {
			# Points to an alias - use its values
			$rv{'to'} = $a->{'values'};
			$rv{'alias'} = $a;
			}
		else { 
			# Just the original value
			$rv{'to'} = [ $v->{'to'} ];
			if ($v->{'to'} eq "error:nouser User unknown") {
				# Default message
				$rv{'to'} = [ "BOUNCE" ];
				}
			elsif ($v->{'to'} =~ /^error:nouser\s+(.*)/i) {
				# Custom message
				$rv{'to'} = [ "BOUNCE $1" ];
				}
			elsif ($v->{'to'} eq "error:nouser") {
				# No message
				$rv{'to'} = [ "BOUNCE" ];
				}
			}
		push(@virts, \%rv);
		}
	return @virts;
	}
elsif ($config{'mail_system'} == 0) {
	# Get from postfix
	local $svirts = &postfix::get_maps($virtual_type);
	local %aliases = map { lc($_->{'name'}), $_ }
			 grep { $_->{'enabled'} &&
				(!$unix_user{$_->{'name'}} || $incall) }
			      &$postfix_list_aliases($postfix_afiles);
	local ($v, $a, @virts);
	foreach $v (@$svirts) {
		local %rv = ( 'from' => lc($v->{'name'}),
			      'cmt' => $v->{'cmt'},
			      'virt' => $v );
		local ($mb, $dname) = split(/\@/, $rv{'from'});
		next if ($alias_copy{$dname});
		if ($v->{'value'} !~ /\@/ &&
		    ($a = $aliases{lc($v->{'value'})})) {
			$rv{'to'} = $a->{'values'};
			$rv{'alias'} = $a;
			}
		else {
			$rv{'to'} = [ $v->{'value'} ];
			}
		local $t;	# postfix format for catchall forward is
				# different from sendmail
		foreach $t (@{$rv{'to'}}) {
			$t =~ s/^\@(\S+)$/\%1\@$1/;
			}
		push(@virts, \%rv);
		}
	return @virts;
	}
elsif ($config{'mail_system'} == 2) {
	# Find all qmail aliases like .qmail-group-user
	local @virtmaps = grep { !$_->{'user'} } &qmailadmin::list_virts();
	local @aliases = &qmailadmin::list_aliases();
	local ($an, $v, @virts);
	foreach $an (@aliases) {
		# Find domain in virtual maps
		local $a = &qmailadmin::get_alias($an);
		local $name = $a->{'name'};
		foreach $v (@virtmaps) {
			if ($a->{'name'} =~ /^\Q$v->{'prepend'}\E\-(.*)$/) {
				$name = ($1 eq "default" ? "" : $1)
					."\@".$v->{'domain'};
				}
			}
		push(@virts, { 'from' => $name,
			       'alias' => $a,
			       'to' => [ map { s/^\&//; $_ }
					       @{$a->{'values'}} ] });
		}
	return @virts;
	}
elsif ($config{'mail_system'} == 4) {
	# Looks for psuedo qmail users with no mail store
	local $ldap = &connect_qmail_ldap();
	local $rv = $ldap->search(base => $config{'ldap_base'},
				  filter => "(objectClass=qmailUser)");
	&error($rv->error) if ($rv->code);
	local ($u, @virts);
	foreach $u ($rv->all_entries) {
		next if ($u->get_value("mailMessageStore"));	# skip user
		local $mail = $u->get_value("mail");
		if ($mail =~ /^catchall\@(.*)$/) {
			$mail = "\@$1";
			}
		local @to = $u->get_value("mailForwardingAddress");
		push(@virts, { 'from' => $mail,
			       'dn' => $u->dn(),
			       'ldap' => $u,
			       'to' => \@to });
		}
	$ldap->unbind();
	return @virts;
	}
elsif ($config{'mail_system'} == 5) {
	# Use the valias program to get aliases for all domains
	if (!@vpopmail_aliases_cache) {
		@vpopmail_aliases_cache = ( );

		# Build up list of all domains
		opendir(DDIR, "$config{'vpopmail_dir'}/domains");
		local @df = readdir(DDIR);
		local @doms = grep { $_ !~ /^\./ && length($_) > 1 } @df;
		local @letters = grep { $_ !~ /^\./ && length($_) == 1 } @df;
		closedir(DDIR);
		foreach my $l (@letters) {
			opendir(DDIR, "$config{'vpopmail_dir'}/domains/$l");
			push(@doms, grep { $_ !~ /^\./ } readdir(DDIR));
			closedir(DDIR);
			}

		local $dname;
		foreach $dname (@doms) {
			# Get aliases from .qmail files
			local %already;
			local $ddir = &domain_vpopmail_dir($dname);
			opendir(DDIR, $ddir);
			while($qf = readdir(DDIR)) {
				next if ($qf !~ /^.qmail-(.*)$/);
				local $alias = { 'from' => $1 eq "default" ?
						    "\@$dname" : "$1\@$dname",
						 'to' => [ ] };
				local $_;
				open(QMAIL, "$ddir/$qf");
				while(<QMAIL>) {
					s/\r|\n//g;
					push(@{$alias->{'to'}},
					     &qmail_to_vpopmail($_, $dname));
					}
				close(QMAIL);
				$already{$alias->{'from'}} = $alias;
				push(@vpopmail_aliases_cache, $alias);
				}
			closedir(DDIR);

			# Add those from valias command (for sites using MySQL
			# or some other backend)
			local %aliases;
			local $_;
			open(ALIASES, "$vpopbin/valias -s $dname |");
			while(<ALIASES>) {
				s/\r|\n//g;
				if (/^(\S+)\s+\->\s+(.*)/) {
					local ($from, $to) = ($1, $2);
					next if ($already{$from});	# already above
					local $alias;
					$to = &qmail_to_vpopmail($to, $dname);
					if ($alias = $aliases{$from}) {
						push(@{$alias->{'to'}}, $to);
						}
					else {
						$alias = { 'from' => $from,
							   'to' => [ $to ] };
						$aliases{$from} = $alias;
						push(@vpopmail_aliases_cache,
						     $alias);
						}
					}
				}
			close(ALIASES);
			}
		}
	return @vpopmail_aliases_cache;
	}
elsif ($config{'mail_system'} == 6) {
	return &exim::list_virtusers();
	}
}

# qmail_to_vpopmail(line, domain)
# Converts a line from a .qmail file created by vpopmail into the internal
# Virtualmin format. 
sub qmail_to_vpopmail
{
local $ddir = &domain_vpopmail_dir($_[1]);
if ($_[0] =~ /^\|\s*$vpopbin\/vdelivermail\s+''\s+(\S+)\@(\S+)$/) {
	# External address
	return $2 eq $_[1] ? $1 : "$1\@$2";
	}
elsif ($_[0] =~ /^\|\s*$vpopbin\/vdelivermail\s+''\s+\Q$ddir\E\/(\S+)$/) {
	# Direct to user
	return "\\$1";
	}
elsif ($_[0] =~ /^\|\s*$vpopbin\/vdelivermail\s+''\s+bounce-no-mailbox$/) {
	# Bouncer
	return "BOUNCE";
	}
elsif ($_[0] =~ /^\|\s*$vpopbin\/vdelivermail\s+''\s+delete$/) {
	# Deleter
	return "/dev/null";
	}
else {
	# Some other line
	return $_[0];
	}
}

# vpopmail_to_qmail(alias, domain)
sub vpopmail_to_qmail
{
local $ddir = &domain_vpopmail_dir($_[1]);
if ($_[0] =~ /^\S+\@\S+$/) {
	# A full email address .. just leave as is
	return $_[0];
	}
elsif ($_[0] eq "BOUNCE") {
	return "| $vpopbin/vdelivermail '' bounce-no-mailbox";
	}
elsif ($_[0] eq "/dev/null") {
	return "| $vpopbin/vdelivermail '' delete";
	}
elsif ($_[0] =~ /^\\(\S+)$/) {
	return "| $vpopbin/vdelivermail '' $ddir/$1";
	}
elsif ($_[0] =~ /^[a-z0-9\.\-\_]+$/) {
	# A username - deliver to him
	return "| $vpopbin/vdelivermail '' $_[0]\@$_[1]";
	}
else {
	return $_[0];
	}
}

# delete_virtuser(&virtuser)
# Deletes a virtual mail user mapping
sub delete_virtuser
{
&require_mail();
&execute_before_virtuser($_[0], 'DELETE_ALIAS');
if ($config{'mail_system'} == 1) {
	# Delete from sendmail
	if ($_[0]->{'alias'} && !$_[0]->{'alias'}->{'deleted'}) {
		# Delete alias too
		&sendmail::delete_alias($_[0]->{'alias'});
		$_[0]->{'alias'}->{'deleted'} = 1;
		}
	if (!$_[0]->{'virt'}->{'deleted'}) {
		&sendmail::delete_virtuser($_[0]->{'virt'}, $sendmail_vfile,
					   $sendmail_vdbm, $sendmail_vdbmtype);
		$_[0]->{'virt'}->{'deleted'} = 1;
		}
	}
elsif ($config{'mail_system'} == 0) {
	# Delete from postfix file
	if ($_[0]->{'alias'} && !$_[0]->{'alias'}->{'deleted'}) {
		# Delete alias too
		&$postfix_delete_alias($_[0]->{'alias'});
		&postfix::regenerate_aliases();
		$_[0]->{'alias'}->{'deleted'} = 1;
		}
	if (!$_[0]->{'virt'}->{'deleted'}) {
		&postfix::delete_mapping($virtual_type, $_[0]->{'virt'});
		&postfix::regenerate_virtual_table();
		$_[0]->{'virt'}->{'deleted'} = 1;
		}
	}
elsif ($config{'mail_system'} == 2) {
	# Just delete the qmail alias
	return if ($_[0]->{'alias'}->{'deleted'});
	&qmailadmin::delete_alias($_[0]->{'alias'});
	$_[0]->{'alias'}->{'deleted'} = 1;
	}
elsif ($config{'mail_system'} == 4) {
	# Remove pseudo Qmail user
	local $ldap = &connect_qmail_ldap();
	local $rv = $ldap->delete($_[0]->{'dn'});
	&error($rv->error) if ($rv->code);
	$ldap->unbind();
	}
elsif ($config{'mail_system'} == 5) {
	# Remove all vpopmail aliases
	$_[0]->{'from'} =~ /^(\S*)\@(\S+)$/;
	local ($box, $dom) = ($1 || "default", $2);
	local $qfrom = quotemeta("$box\@$dom");
	local $cmd = "$vpopbin/valias -d $qfrom";
	local $out = &backquote_logged("$cmd 2>&1");
	if ($?) {
		&error("<tt>$cmd</tt> failed : <pre>$out</pre>");
		}
	}
elsif ($config{'mail_system'} == 6) {
	# Delete Exim alias
	if (!$_[0]->{'deleted'}) {
		$_[0]->{'from'} =~ /^(\S*)\@(\S+)$/;
		local ($box, $dom) = ($1 || "default", $2);
		local $alias = { 'name' => "$box",
				 'dom' => $dom };
		&exim::delete_alias($alias);
		$_[0]->{'deleted'} = 1;
		}
	}
&execute_after_virtuser($_[0], 'DELETE_ALIAS');
&register_sync_secondary_virtuser($_[0]);
}

# modify_virtuser(&old, &new)
# Update an email alias, which forwards mail from some address to multiple
# destinations (addresses, autoresponders, etc).
sub modify_virtuser
{
&require_mail();
&execute_before_virtuser($_[0], 'MODIFY_ALIAS');
local @to = @{$_[1]->{'to'}};
if ($config{'mail_system'} == 1) {
	# Modify in sendmail
	local $alias = $_[0]->{'alias'};
	local $oldalias = $alias ? { %$alias } : undef;
	local @smto = map { $_ eq "BOUNCE" ? "error:nouser User unknown" :
			    $_ =~ /^BOUNCE\s+(.*)$/ ? "error:nouser $1" :
			    $_ } @to;
	$_[1]->{'from'} =~ /^(\S*)\@(\S+)$/;
	local $an = ($1 || "default")."-".$2;
	if (&needs_alias(@smto) && !$alias) {
		# Alias needs to be created and virtuser updated
		local $clash = &check_alias_clash($an);
		local $alias = { "name" => $an,
				 "enabled" => 1,
				 "values" => \@smto };
		$_[1]->{'alias'} = $alias;
		&sendmail::lock_alias_files($sendmail_afiles);
		if ($clash) {
			&sendmail::delete_alias($clash);  # Overwrite clash
			}
		&sendmail::create_alias($alias, $sendmail_afiles);
		&sendmail::unlock_alias_files($sendmail_afiles);
		local $virt = { "from" => $_[1]->{'from'},
				"to" => $an,
				"cmt" => $_[1]->{'cmt'} };
		&sendmail::modify_virtuser($_[0]->{'virt'}, $virt,
					   $sendmail_vfile, $sendmail_vdbm,
					   $sendmail_vdbmtype);
		$_[1]->{'virt'} = $virt;
		}
	elsif ($alias) {
		# Just update alias and maybe virtuser
		$alias->{'values'} = \@smto;
		$alias->{'name'} = $an if ($_[1]->{'from'} ne $_[0]->{'from'});
		&sendmail::modify_alias($oldalias, $alias);
		if ($_[1]->{'from'} ne $_[0]->{'from'} ||
		    $_[1]->{'cmt'} ne $_[0]->{'cmt'}) {
			# Re-named .. need to change virtuser too
			local $virt = { "from" => $_[1]->{'from'},
					"to" => $an,
					"cmt" => $_[1]->{'cmt'} };
			&sendmail::modify_virtuser($_[0]->{'virt'}, $virt,
						   $sendmail_vfile,
						   $sendmail_vdbm,
						   $sendmail_vdbmtype);
			$_[1]->{'virt'} = $virt;
			}
		}
	else {
		# Just update virtuser
		local $virt = { "from" => $_[1]->{'from'},
				"to" => $smto[0],
				"cmt" => $_[1]->{'cmt'} };
		&sendmail::modify_virtuser($_[0]->{'virt'}, $virt,
					   $sendmail_vfile, $sendmail_vdbm,
					   $sendmail_vdbmtype);
		$_[1]->{'virt'} = $virt;
		}
	}
elsif ($config{'mail_system'} == 0) {
	# Modify in postfix file
	local $alias = $_[0]->{'alias'};
	local $oldalias = $alias ? { %$alias } : undef;
	local @psto = map { $_ =~ /^BOUNCE\s+(.*)$/ ? "BOUNCE" : $_ } @to;
	$_[1]->{'from'} =~ /^(\S*)\@(\S+)$/;
	local $an = ($1 || "default")."-".$2;
	if (&needs_alias(@psto) && !$alias) {
		# Alias needs to be created and virtuser updated
		local $clash = &check_alias_clash($an);
		local $alias = { "name" => $an,
				 "enabled" => 1,
				 "values" => \@psto };
		$_[1]->{'alias'} = $alias;
		&postfix::lock_alias_files($postfix_afiles);
		if ($clash) {
			&$postfix_delete_alias($clash);   # Overwrite clash
			}
		&$postfix_create_alias($alias, $postfix_afiles);
		&postfix::unlock_alias_files($postfix_afiles);
		&postfix::regenerate_aliases();
		local $virt = { "name" => $_[1]->{'from'},
				"value" => $an,
				"cmt" => $_[1]->{'cmt'} };
		&postfix::modify_mapping($virtual_type, $_[0]->{'virt'}, $virt);
		$_[1]->{'virt'} = $virt;
		&postfix::regenerate_virtual_table();
		}
	elsif ($alias) {
		# Just update alias
		$alias->{'values'} = \@psto;
		$alias->{'name'} = $an if ($_[1]->{'from'} ne $_[0]->{'from'});
		&$postfix_modify_alias($oldalias, $alias);
		&postfix::regenerate_aliases();
		if ($_[1]->{'from'} ne $_[0]->{'from'} ||
		    $_[1]->{'cmt'} ne $_[0]->{'cmt'}) {
			# Re-named .. need to change virtuser too
			local $virt = { "name" => $_[1]->{'from'},
					"value" => $an,
					"cmt" => $_[1]->{'cmt'} };
			&postfix::modify_mapping($virtual_type, $_[0]->{'virt'},
						 $virt);
			$_[1]->{'virt'} = $virt;
			&postfix::regenerate_virtual_table();
			}
		}
	else {
		# Just update virtuser
		local $t = $psto[0];
		$t =~ s/^\%1\@/\@/;	# postfix format is different
		local $virt = { "name" => $_[1]->{'from'},
				"value" => $t,
				"cmt" => $_[1]->{'cmt'} };
		&postfix::modify_mapping($virtual_type, $_[0]->{'virt'}, $virt);
		$_[1]->{'virt'} = $virt;
		&postfix::regenerate_virtual_table();
		}
	}
elsif ($config{'mail_system'} == 2) {
	# Just update the qmail alias
	$_[1]->{'from'} =~ /^(\S*)\@(\S+)$/;
	local ($box, $dom) = ($1 || "default", $2);
	local ($virtmap) = grep { $_->{'domain'} eq $dom && !$_->{'user'} }
			        &qmailadmin::list_virts();
	local $alias = { 'name' => "$virtmap->{'prepend'}-$box",
			 'values' => \@to };
	&qmailadmin::modify_alias($_[0]->{'alias'}, $alias);
	$_[1]->{'alias'} = $alias;
	}
elsif ($config{'mail_system'} == 4) {
	# Update the Qmail+LDAP pseudo-user
	local $ldap = &connect_qmail_ldap();
	$_[1]->{'from'} =~ /^(\S*)\@(\S+)$/;
	local ($box, $dom) = ($1 || "catchall", $2);
	local $newdn = "uid=$box-$dom,$config{'ldap_base'}";
	if (!&same_dn($_[0]->{'dn'}, $newdn)) {
		# Re-named, so use new DN first
		$rv = $ldap->moddn($_[0]->{'dn'},
				   newrdn => "uid=$box-$dom");
		&error($rv->error) if ($rv->code);
		$_[1]->{'dn'} = $newdn;
		}
	# Update other attributes
	local $attrs = [ "uid" => "$box-$dom",
			 "mail" => $box."\@".$dom,
			 "mailForwardingAddress" => $_[1]->{'to'} ];
	local $rv = $ldap->modify($_[1]->{'dn'},
				  replace => $attrs);
	&error($rv->error) if ($rv->code);
	$ldap->unbind();
	}
elsif ($config{'mail_system'} == 5) {
	# Just delete the old vpopmail alias, and re-add!
	&delete_virtuser($_[0]);
	&create_virtuser($_[1]);
	}
elsif ($config{'mail_system'} == 6) {
	$_[1]->{'from'} =~ /^(\S*)\@(\S+)$/;
	local ($box, $dom) = ($1 || "default", $2);
	local $alias = { 'name' => "$box",
			 'dom' => "$dom",
			 'values' => $_[1]->{'to'} };
	$_[0]->{'from'} =~ /^(\S*)\@(\S+)$/;
	local ($box, $dom) = ($1 || "default", $2);
	local $old = { 'name' => "$box",
			 'dom' => "$dom",
			 'values' => $_[0]->{'to'} };
	&exim::modify_alias($old,$alias);
	$_[1]->{'alias'} = $alias;
	}
&execute_after_virtuser($_[1], 'MODIFY_ALIAS');
&register_sync_secondary_virtuser($_[0]);
&register_sync_secondary_virtuser($_[1]);
}

# create_virtuser(&virtuser)
# Creates a new virtual mail mapping
sub create_virtuser
{
&require_mail();
local @to = @{$_[0]->{'to'}};
&execute_before_virtuser($_[0], 'CREATE_ALIAS');
if ($config{'mail_system'} == 1) {
	# Create in sendmail
	local $virt;
	local @smto = map { $_ eq "BOUNCE" ? "error:nouser User unknown" :
			    $_ =~ /^BOUNCE\s+(.*)$/ ? "error:nouser $1" :
			    $_ } @to;
	if (&needs_alias(@smto)) {
		# Need to create an alias, named address-domain
		$_[0]->{'from'} =~ /^(\S*)\@(\S+)$/;
		local $an = ($1 || "default")."-".$2;
		local $clash = &check_alias_clash($an);
		local $alias = { "name" => $an,
				 "enabled" => 1,
				 "values" => \@smto };
		$_[0]->{'alias'} = $alias;
		&sendmail::lock_alias_files($sendmail_afiles);
		if ($clash) {
			&sendmail::delete_alias($clash);  # Overwrite clash
			}
		&sendmail::create_alias($alias, $sendmail_afiles);
		&sendmail::unlock_alias_files($sendmail_afiles);
		$virt = { "from" => $_[0]->{'from'},
			  "to" => $an,
			  "cmt" => $_[0]->{'cmt'} };
		}
	else {
		# A single virtuser will do
		$virt = { "from" => $_[0]->{'from'},
			  "to" => $smto[0],
			  "cmt" => $_[0]->{'cmt'} };
		}
	local @svirts = &sendmail::list_virtusers($sendmail_vfile);
	local ($vclash) = grep { $_->{'from'} eq $virt->{'from'} } @svirts;
	if ($vclash) {
		# Replace clash
		&sendmail::delete_virtuser($vclash, $sendmail_vfile,
                                           $sendmail_vdbm, $sendmail_vdbmtype);
		}
	&sendmail::create_virtuser($virt, $sendmail_vfile,
				   $sendmail_vdbm,
				   $sendmail_vdbmtype);
	$_[0]->{'virt'} = $virt;
	}
elsif ($config{'mail_system'} == 0) {
	# Create in postfix file
	local @psto = map { $_ =~ /^BOUNCE\s+(.*)$/ ? "BOUNCE" : $_ } @to;
	local $virt;
	if (&needs_alias(@psto)) {
		# Need to create an alias, named address-domain
		$_[0]->{'from'} =~ /^(\S*)\@(\S+)$/;
		local $an = ($1 || "default")."-".$2;
		local $clash = &check_alias_clash($an);
		local $alias = { "name" => $an,
				 "enabled" => 1,
				 "values" => \@psto };
		$_[0]->{'alias'} = $alias;
		&postfix::lock_alias_files($postfix_afiles);
		if ($clash) {
			&$postfix_delete_alias($clash);   # Overwrite clash
			}
		&$postfix_create_alias($alias, $postfix_afiles);
		&postfix::unlock_alias_files($postfix_afiles);
		&postfix::regenerate_aliases();
		$virt = { 'name' => $_[0]->{'from'},
			  'value' => $an,
			  'cmt' => $_[0]->{'cmt'} };
		}
	else {
		# A single virtuser will do
		local $t = $psto[0];
		$t =~ s/^\%1\@/\@/;	# postfix format is different
		$virt = { 'name' => $_[0]->{'from'},
			  'value' => $t,
			  'cmt' => $_[0]->{'cmt'} };
		}
	&create_replace_mapping($virtual_type, $virt);
	&postfix::regenerate_virtual_table();
	$_[0]->{'virt'} = $virt;
	}
elsif ($config{'mail_system'} == 2) {
	# Create a single Qmail alias
	$_[0]->{'from'} =~ /^(\S*)\@(\S+)$/;
	local ($box, $dom) = ($1 || "default", $2);
	local ($virtmap) = grep { $_->{'domain'} eq $dom && !$_->{'user'} }
			        &qmailadmin::list_virts();
	local $alias = { 'name' => "$virtmap->{'prepend'}-$box",
			 'values' => \@to };
	&qmailadmin::create_alias($alias);
	$_[0]->{'alias'} = $alias;
	}
elsif ($config{'mail_system'} == 4) {
	# Create a psuedo Qmail user
	local $ldap = &connect_qmail_ldap();
	$_[0]->{'from'} =~ /^(\S*)\@(\S+)$/;
	local ($box, $dom) = ($1 || "catchall", $2);
	local $_[0]->{'dn'} = "uid=$box-$dom,$config{'ldap_base'}";
	local @oc = ( "qmailUser", split(/\s+/, $config{'ldap_aclasses'}) );
	local $attrs = [ "objectClass" => \@oc,
			 "uid" => "$box-$dom",
		 	 "deliveryMode" => "nolocal",
			 "mail" => $box."\@".$dom,
			 "mailForwardingAddress" => $_[0]->{'to'} ];
	local $rv = $ldap->add($_[0]->{'dn'}, attr => $attrs);
        &error($rv->error) if ($rv->code);
        $ldap->unbind();
	}
elsif ($config{'mail_system'} == 5) {
	# Add one vpopmail alias for each destination
	local $t;
	$_[0]->{'from'} =~ /^(\S*)\@(\S+)$/;
	local ($box, $dom) = ($1 || "default", $2);
	local $maxlen = 0;
	foreach $t (@{$_[0]->{'to'}}) {
		$maxlen = length($t) if (length($t) > $maxlen);
		}
	if ($box eq "default" || $maxlen > 160) {
		# Create .qmail file directly
		local $ddir = &domain_vpopmail_dir($dom);
		local $qmf = "$ddir/.qmail-$box";
		&lock_file($qmf);
		&open_tempfile(QMAIL, ">$qmf");
		foreach $t (@{$_[0]->{'to'}}) {
			&print_tempfile(QMAIL, &vpopmail_to_qmail($t, $dom),"\n");
			}
		&close_tempfile(QMAIL);
		local @uinfo = getpwnam($config{'vpopmail_user'});
		local @ginfo = getgrnam($config{'vpopmail_group'});
		&set_ownership_permissions($uinfo[2], $ginfo[2], 0600, $qmf);
		&unlock_file($qmf);
		}
	else {
		# Create with valias command
		local $qfrom = quotemeta("$box\@$dom");
		foreach $t (@{$_[0]->{'to'}}) {
			local $qto = quotemeta(&vpopmail_to_qmail($t, $dom));
			local $cmd = "$vpopbin/valias -i $qto $qfrom";
			local $out = &backquote_logged("$cmd 2>&1");
			if ($?) {
				&error("<tt>$cmd</tt> failed: <pre>$out</pre>");
				}
			}
		}
	}
elsif ($config{'mail_system'} == 6) {
	$_[0]->{'from'} =~ /^(\S*)\@(\S+)$/;
	local ($box, $dom) = ($1 || "default", $2);
	local $alias = { 'name' => "$box",
			 'dom' => $dom,
			 'values' => \@to };
	&exim::create_alias($alias);
	$_[0]->{'alias'} = $alias;
	}
&execute_after_virtuser($_[0], 'CREATE_ALIAS');
&register_sync_secondary_virtuser($_[0]);
}

# sync_secondary_virtusers(&domain, [&only-servers])
# Find all virtusers in the given domain, and make sure all secondary MX
# servers running Postfix or Sendmail have only those users on their list to
# allow relaying for.
# This function is called on the master Virtualmin.
# Returns a list of tuples containing the server object and error message.
sub sync_secondary_virtusers
{
local ($d, $onlyservers) = @_;
local @servers = $onlyservers ? @$onlyservers : &list_mx_servers();
return if (!@servers);

# Build list of mailboxes in the domain
local @mailboxes;
foreach my $v (&list_virtusers(1)) {
	my ($mb, $dom) = split(/\@/, $v->{'from'});
	if ($dom eq $d->{'dom'}) {
		push(@mailboxes, $mb);
		}
	}

# Sync to each secondary
local @rv;
&remote_error_setup(\&secondary_error_handler);
foreach my $s (@servers) {
	alarm(20);
	$SIG{'ALRM'} = sub { die "timeout" };
	eval {
		$secondary_error = undef;
		&remote_foreign_require($s, "virtual-server",
					    "virtual-server-lib.pl");
		if ($secondary_error) {
			push(@rv, [ $s, $secondary_error ]);
			}
		else {
			local $err = &remote_foreign_call($s, "virtual-server",
				  "update_secondary_mx_virtusers", $d->{'dom'},
				  \@mailboxes);
			push(@rv, [ $s, $err ]);
			}
		};
	alarm(0);
	if ($@) {
		push(@rv, [ $s, $@ =~ /timeout/ ?
				  "Timeout connecting to Webmin" : $@ ]);
		}
	}
&remote_error_setup(undef);
return @rv;
}

# update_secondary_mx_virtusers(domain, &mailbox-names)
# Update the list of mailboxes allowed to relay for some domain.
# This is called on the secondary MX Virtualmins.
sub update_secondary_mx_virtusers
{
local ($dom, $mailboxes) = @_;
local %mailboxes_map = map { $_, 1 } @$mailboxes;
&obtain_lock_mail($_[0]);
&require_mail();
if ($config{'mail_system'} == 1) {
	# Update Sendmail access list
	&foreign_require("sendmail", "access-lib.pl");
	local $conf = &sendmail::get_sendmailcf();
	local $afile = &sendmail::access_file($conf);
	local ($adbm, $adbmtype) = &sendmail::access_dbm($conf);
	if (!$adbm) {
		return $text{'mxv_eaccess'};
		}
	if (!-r $afile) {
		return &text('mxv_eaccessfile', "<tt>$afile</tt>");
		}
	&lock_file($afile);
	local @accs = &sendmail::list_access($afile);
	local $gotdoma;
	foreach my $a (@accs) {
		next if ($a->{'tag'} ne 'To');
		if ($a->{'from'} eq $dom) {
			$gotdoma = $a;
			next;
			}
		my ($mbox, $mdom) = split(/\@/, $a->{'from'});
		next if ($mdom ne $dom);
		if ($mailboxes_map{$mbox}) {
			# Already got, so leave alone
			delete($mailboxes_map{$mbox});
			}
		else {
			# Need to remove
			&sendmail::delete_access($a, $afile, $adbm, $adbmtype);
			}
		}
	foreach my $mbox (keys %mailboxes_map) {
		next if ($mbox eq "");	# Wildcard is handled below
		&sendmail::create_access({ 'tag' => 'To',
					   'from' => $mbox.'@'.$dom,
					   'action' => 'RELAY' },
					 $afile, $adbm, $adbmtype);
		}

	# Check if relaying for this domain - will be false after deletion
	local $cwfile;
	local @dlist = &sendmail::get_file_or_config($conf, "R", undef,
                                                     \$cwfile);
	local $relaying = &indexof(lc($dom), (map { lc($_) } @dlist)) >= 0;

	# Add, update or remove domain-level rule
	if (!$relaying && scalar(keys %mailboxes_map) == 0) {
		# No longer relaying, so delete domain-level rule
		if ($gotdoma) {
			&sendmail::delete_access($gotdoma, $afile, $adbm,
						 $adbmtype);
			}
		}
	elsif (!$gotdoma && !$mailboxes_map{""}) {
		# Add special rule to reject the whole domain
		&sendmail::create_access({ 'tag' => 'To',
					   'from' => $dom,
					   'action' => 'REJECT' },
					 $afile, $adbm, $adbmtype);
		}
	elsif (!$gotdoma && $mailboxes_map{""}) {
		# Add special rule to access the whole domain
		&sendmail::create_access({ 'tag' => 'To',
					   'from' => $dom,
					   'action' => 'RELAY' },
					 $afile, $adbm, $adbmtype);
		}
	elsif ($gotdoma) {
		# Update domain rule
		$gotdoma->{'action'} = $mailboxes_map{""} ? 'RELAY' : 'REJECT';
		&sendmail::modify_access($gotdoma, $gotdoma,
					 $afile, $adbm, $adbmtype);
		}
	&unlock_file($afile);
	}
elsif ($config{'mail_system'} == 0) {
	# Update Postfix relay_recipient_maps
	local $rrm = &postfix::get_current_value("relay_recipient_maps");
	if (!$rrm) {
		return &text('mxv_rrm', 'relay_recipient_maps');
		}
	local @mapfiles = &postfix::get_maps_files();
	foreach my $f (@mapfiles) {
		&lock_file($f);
		}
	local $maps = &postfix::get_maps('relay_recipient_maps');
	local @maps_copy = @$maps;	# delete_virtuser modifies map cache
	foreach my $m (@maps_copy) {
		my ($mbox, $mdom) = split(/\@/, $m->{'name'});
		next if ($mdom ne $dom);
		if ($mailboxes_map{$mbox}) {
			# Already got, so leave alone
			delete($mailboxes_map{$mbox});
			}
		else {
			# Need to remove
			&postfix::delete_mapping('relay_recipient_maps', $m);
			}
		}
	foreach my $mbox (keys %mailboxes_map) {
		&postfix::create_mapping('relay_recipient_maps',
					 { 'name' => $mbox.'@'.$dom,
					   'value' => 'OK' });
		}
	&postfix::regenerate_any_table('relay_recipient_maps');
	foreach my $f (@mapfiles) {
		&unlock_file($f);
		}
	return undef;
	}
else {
	return $text{'mxv_unsupported'};
	}
}

# register_sync_secondary_virtuser(&virtuser)
# Register a call to sync_secondary_virtusers after everything is done for the
# domain is one alias
sub register_sync_secondary_virtuser
{
local ($virt) = @_;
if ($virt->{'from'} =~ /\@(\S+)$/) {
	local $d = &get_domain_by("dom", "$1");
	if ($d) {
		&register_post_action(\&sync_secondary_virtusers, $d);
		}
	}
}

# needs_alias(list..)
sub needs_alias
{
return 1 if (@_ != 1);
local $t;
foreach $t (@_) {
	return 1 if (&alias_type($t) != 1 && &alias_type($t) != 8 &&
		     &alias_type($t) != 9);
	}
return 0;
}

# join_alias(list..)
sub join_alias
{
return join(',', map { /\s/ ? "\"$_\"" : $_ } @_);
}

# is_mail_running()
# Returns 1 if the configured mail server is running, 0 if not
sub is_mail_running
{
&require_mail();
if ($config{'mail_system'} == 1) {
	# Call the sendmail module
	return &sendmail::is_sendmail_running();
	}
elsif ($config{'mail_system'} == 0) {
	# Call the postfix module 
	return &postfix::is_postfix_running();
	}
elsif ($config{'mail_system'} == 2 || $config{'mail_system'} == 4 ||
       $config{'mail_system'} == 5) {
	# Just look for qmail-send
	local ($pid) = &find_byname("qmail-send");
	return $pid ? 1 : 0;
	}
elsif ($config{'mail_system'} == 6) {
	# Call the postfix module 
	local ($pid) = &find_byname("exim4");
	return $pid ? 1 : 0;
	}
}

# shutdown_mail_server([return-error])
# Shuts down the mail server, or calls &error
sub shutdown_mail_server
{
&require_mail();
local $err;
if ($config{'mail_system'} == 1) {
	# Kill or stop sendmail
	$err = &sendmail::stop_sendmail();
	}
elsif ($config{'mail_system'} == 0) {
	# Run the postfix stop command
	$err = &postfix::stop_postfix();
	}
elsif ($config{'mail_system'} == 2 || $config{'mail_system'} == 4 ||
       $config{'mail_system'} == 5) {
	# Call the qmail stop function
	$err = &qmailadmin::stop_qmail();
	}
elsif ($config{'mail_system'} == 6) {
	# Run the sendmail start command
	$err = &backquote_command("/etc/init.d/exim4 stop", 1);
	}
if ($_[0]) {
	return $err;
	}
elsif ($err) {
	&error($err);
	}
}

# startup_mail_server([return-error])
# Starts up the mail server, or calls &error
sub startup_mail_server
{
&require_mail();
local $err;
if ($config{'mail_system'} == 1) {
	# Run the sendmail start command
	$err = &sendmail::start_sendmail();
	}
elsif ($config{'mail_system'} == 0) {
	# Run the postfix start command
	$err = &postfix::start_postfix();
	}
elsif ($config{'mail_system'} == 2 || $config{'mail_system'} == 4 ||
       $config{'mail_system'} == 5) {
	# Call the qmail start function
	$err = &qmailadmin::start_qmail();
	}
elsif ($config{'mail_system'} == 6) {
	# Run the sendmail start command
	$err = &backquote_command("/etc/init.d/exim4 start", 1);
	}
if ($_[0]) {
	return $err;
	}
elsif ($err) {
	&error($err);
	}
}

# create_mail_file(&user, &domain)
# Creates a new empty mail file for a user, if necessary. Returns the path
# and type (0 for mbox, 1 for maildir)
sub create_mail_file
{
local ($user, $d) = @_;
&require_mail();
local $mf;
local $md;
local ($uid, $gid) = ($user->{'uid'}, $user->{'gid'});
local @rv;
if ($config{'mail_system'} == 1) {
	# Sendmail normally uses a mail file
	$mf = &sendmail::user_mail_file($user->{'user'});
	if ($sendmail::config{'mail_type'} == 1) {
		# But not today
		$md = $mf;
		$mf = undef;
		}
	}
elsif ($config{'mail_system'} == 0) {
	# Postfix user
	local ($s, $d) = &postfix::postfix_mail_system();
	if ($s == 0 || $s == 1) {
		# A mail file
		$mf = &postfix::postfix_mail_file($user->{'user'});
		if ($s == 0 && $user->{'user'} =~ /\@/) {
			# For Postfix delivering to /var/mail with @ usernames,
			# we need to create the file without the @ in it, and
			# link from the @ so that the mail server and Webmin
			# agree.
			$mfreal = &postfix::postfix_mail_file(
					&replace_atsign($user->{'user'}));
			}
		}
	elsif ($s == 2) {
		# A mail directory
		$md = &postfix::postfix_mail_file($user->{'user'});
		}
	}
elsif ($config{'mail_system'} == 2 ||
       $config{'mail_system'} == 4 && !$user->{'qmail'}) {
	# Normal Qmail user
	if ($qmailadmin::config{'mail_system'} == 0) {
		$mf = &qmailadmin::user_mail_file($user->{'user'});
		}
	elsif ($qmailadmin::config{'mail_system'} == 1) {
		$md = &qmailadmin::user_mail_dir($user->{'user'});
		}
	}
elsif ($config{'mail_system'} == 4) {
	# Qmail+LDAP mail file comes from DB
	if ($user->{'mailstore'} =~ /^(.*)\/$/) {
		$md = &add_ldapmessagestore("$1");
		}
	else {
		$mf = &add_ldapmessagestore($user->{'mailstore'});
		}
	if (!$user->{'unix'}) {
		# For non-NSS Qmail+LDAP users, set the ownership based on
		# LDAP control files
		local $quid = &qmailadmin::get_control_file("qmailuid");
		local $qgid = &qmailadmin::get_control_file("qmailgid");
		local $cuid = &qmailadmin::get_control_file("ldapuid");
		local $cgid = &qmailadmin::get_control_file("ldapgid");
		$uid = defined($quid) ? $quid :
		       defined($cuid) ? $cuid : $uid;
		$gid = defined($qgid) ? $qgid :
		       defined($cgid) ? $cgid : $gid;
		}
	}
elsif ($config{'mail_system'} == 5) {
	# Nothing to do for VPOPMail, because it gets created automatically
	# by vadduser
	@rv = ( &user_mail_file($user), 1 );
	}
elsif ($config{'mail_system'} == 6) {
	if ($exim::config{'mail_system'} == 0) {
		$mf = &exim::user_mail_file($user);
		}
	elsif ($exim::config{'mail_system'} == 1) {
		$md = &exim::user_mail_file($user);
		}
	}

if ($mf) {
	if (!-r $mf) {
		# Create the mailbox, owned by the user
		if ($mfreal) {
			# Create real file, and link to it
			&unlink_file($mfreal);
			&open_tempfile(MF, ">$mfreal", 1);
			&close_tempfile(MF);
			&set_ownership_permissions($uid, $gid, undef, $mfreal);
			&symlink_file($mfreal, $mf);
			}
		else {
			# Just one file
			&unlink_file($mf);
			&open_tempfile(MF, ">$mf", 1);
			&close_tempfile(MF);
			&set_ownership_permissions($uid, $gid, undef, $mf);
			}
		}
	@rv = ( $mf, 0 );
	}
elsif ($md) {
	if (!-d $md) {
		# Create the Maildir, owned by the user
		local $d;
		&unlink_file($md);
		foreach $d ($md, "$md/cur", "$md/tmp", "$md/new") {
			&make_dir($d, 0700, 1);
			&set_ownership_permissions($uid, $gid, undef, $d);
			}
		}
	@rv = ( $md, 1 );
	}

if (-d $user->{'home'} && $user->{'unix'}) {
	# Create Usermin ~/mail directory (if installed)
	if (&foreign_installed("usermin")) {
		local %uminiserv;
		&usermin::get_usermin_miniserv_config(\%uminiserv);
		local $mod = "mailbox";
		local %uconfig;
		&read_file("$uminiserv{'root'}/$mod/defaultuconfig",
			   \%uconfig);
		&read_file("$usermin::config{'usermin_dir'}/$mod/uconfig",
			   \%uconfig);
		local $umd = $uconfig{'mailbox_dir'} || "mail";
		local $umail = "$user->{'home'}/$umd";
		if (!-e $umail) {
			&make_dir($umail, 0755);
			&set_ownership_permissions($uid, $gid, undef, $umail);
			}
		}
	}

# Create spam, virus, drafts, sent and trash Maildir sub-directories
if ($md && $md =~ /\/Maildir$/) {
	local @folders;
	foreach my $n ("trash", "drafts", "sent") {
		local $tname = $config{$n.'_folder'};
		$tname ||= $n;
		if ($tname ne "*") {
			push(@folders, "$md/.$tname");
			}
		}
	if ($d->{'spam'}) {
		local ($sdmode, $sdpath) = &get_domain_spam_delivery($d);
		if ($sdmode == 6) {
			push(@folders, "$md/.".($sdpath || "Junk"));
			}
		elsif ($sdmode == 1 && $sdpath =~ /^Maildir\/(\S+)\/$/) {
			push(@folders, "$md/$1");
			}
		}
	if ($d->{'virus'}) {
		local ($vdmode, $vdpath) = &get_domain_virus_delivery($d);
		if ($vdmode == 6) {
			push(@folders, "$md/.".($vdpath || "Virus"));
			}
		elsif ($vdmode == 1 && $vdpath =~ /^Maildir\/(\S+)\/$/) {
			push(@folders, "$md/$1");
			}
		}

	# Actually create the folders
	my @subs;
	foreach my $f (@folders) {
		if ($f =~ /\/Maildir\/\.(\S+)$/) {
			push(@subs, $1);
			}
		next if (-d $f);
		foreach $d ($f, "$f/cur", "$f/tmp", "$f/new") {
			&make_dir($d, 0700, 1);
			&set_ownership_permissions($uid, $gid, undef, $d);
			}
		}

	# Create subscriptions file for Dovecot
	if (@subs) {
		&open_tempfile(SUBS, ">$md/subscriptions");
		foreach my $s (@subs) {
			&print_tempfile(SUBS, $s."\n");
			}
		&close_tempfile(SUBS);
		&set_ownership_permissions($uid, $gid, undef,
					   "$md/subscriptions");
		}
	}

return @rv;
}

# add_ldapmessagestore(path)
sub add_ldapmessagestore
{
if ($_[0] =~ /^\//) {
	return $_[0];
	}
else {
	&require_mail();
	local $pfx = &qmailadmin::get_control_file("ldapmessagestore");
	return $pfx."/".$_[0];
	}
}

# set_mailfolder_owner(&folder, &user)
# Chowns some mail folder to a user
sub set_mailfolder_owner
{
local ($folder, $user) = @_;
&execute_command("chown -R $user->{'uid'}:$user->{'gid'} ".
		 quotemeta($folder->{'file'}));
}

# delete_mail_file(&user)
# Delete's a unix user's mail file, associated indexes, and clamav temp files
sub delete_mail_file
{
&require_mail();

# Remove mailboxes moduile indexes
&foreign_require("mailboxes", "mailboxes-lib.pl");
&mailboxes::delete_user_index_files($_[0]->{'user'});

local $umf = &user_mail_file($_[0]);
if ($umf) {
	&system_logged("rm -rf ".quotemeta($umf));
	}
if ($config{'mail_system'} == 0 && $_[0]->{'user'} =~ /\@/) {
	# Remove real file as well as link, if any
	local $fakeuser = { %{$_[0]} };
	$fakeuser->{'user'} = &replace_atsign($_[0]->{'user'});
	local ($realumf, $realtype) = &user_mail_file($fakeuser);
	if ($realumf ne $umf && $realtype == 0) {
		&system_logged("rm -f ".quotemeta($realumf));
		}
	}

# Delete old-style mail file under /var/mail or /var/spool/mail , which
# procmail sometimes creates
&unlink_file("/var/mail/$_[0]->{'user'}",
	     "/var/spool/mail/$_[0]->{'user'}");

# Remove clamav temp files
opendir(TEMP, "/tmp");
foreach my $f (readdir(TEMP)) {
	local $p = "/tmp/$f";
	if ($f =~ /^clamav-([a-f0-9]+)$/ || $f =~ /^clamwrapper\.\d+$/ ||
	    $f =~ /^\.spamassassin.*tmp$/) {
		local @st = stat($p);
		if ($st[4] == $_[0]->{'uid'} && $st[5] == $_[0]->{'gid'}) {
			# Found one to remove
			&unlink_file($p);
			}
		}
	}
closedir(TEMP);

# Remove Dovecot index files
if (&foreign_check("dovecot")) {
	&foreign_require("dovecot", "dovecot-lib.pl");
	local $conf = &dovecot::get_config();
	local $loc = &dovecot::find_value("mail_location", $conf);
	$loc ||= &dovecot::find_value("default_mail_env", $conf);
	local @doves;
	if ($loc =~ /INDEX=([^:]+)\/%u/) {
		push(@doves, $1);
		}
	if ($loc =~ /CONTROL=([^:]+)\/%u/) {
		push(@doves, $1);
		}
	foreach my $dove (@doves) {
		&unlink_file($dove."/".$_[0]->{'user'});
		&unlink_file($dove."/".&replace_atsign($_[0]->{'user'}));
		}
	}
}

# rename_mail_file(&user, &olduser)
# Rename a user's mail files, if they change due to a user rename
sub rename_mail_file
{
return if (&mail_under_home());
&require_mail();
if ($config{'mail_system'} == 1) {
	# Just rename the Sendmail mail file (if necessary)
	local $of = &sendmail::user_mail_file($_[1]->{'user'});
	local $nf = &sendmail::user_mail_file($_[0]->{'user'});
	&rename_logged($of, $nf);
	}
elsif ($config{'mail_system'} == 0) {
	# Find out from Postfix which file to rename (if necessary)
	local $newumf = &postfix::postfix_mail_file($_[0]->{'user'});
	local $oldumf = &postfix::postfix_mail_file($_[1]->{'user'});
	&rename_logged($oldumf, $newumf);
	}
elsif ($config{'mail_system'} == 2 ||
       $config{'mail_system'} == 4 && !$_[0]->{'qmail'}) {
	# Just rename the Qmail mail file (if necessary)
	local $of = &qmailadmin::user_mail_file($_[1]->{'user'});
	local $nf = &qmailadmin::user_mail_file($_[0]->{'user'});
	&rename_logged($of, $nf);
	}
elsif ($config{'mail_system'} == 4) {
	# Rename from LDAP property
	&rename_logged($_[1]->{'mailstore'}, $_[0]->{'mailstore'});
	}

# Rename Dovecot index files
if (&foreign_check("dovecot")) {
	&foreign_require("dovecot", "dovecot-lib.pl");
	local $conf = &dovecot::get_config();
	local $loc = &dovecot::find_value("mail_location", $conf);
	$loc ||= &dovecot::find_value("default_mail_env", $conf);
	local @doves;
	if ($loc =~ /INDEX=([^:]+)\/%u/) {
		push(@doves, $1);
		}
	if ($loc =~ /CONTROL=([^:]+)\/%u/) {
		push(@doves, $1);
		}
	foreach my $dove (@doves) {
		&rename_file($dove."/".$_[1]->{'user'},
			     $dove."/".$_[0]->{'user'});
		&rename_file($dove."/".&replace_atsign($_[1]->{'user'}),
			     $dove."/".&replace_atsign($_[0]->{'user'}));
		}
	}

}

# mail_under_home()
# Returns 1 if mail is stored under user home directories
sub mail_under_home
{
&require_mail();
if ($config{'mail_system'} == 1) {
	return !$sconfig{'mail_dir'};
	}
elsif ($config{'mail_system'} == 0) {
	local $s = &postfix::postfix_mail_system();
	return $s != 0;
	}
elsif ($config{'mail_system'} == 2) {
	return $qmconfig{'mail_system'} != 0 || !$qmconfig{'mail_dir'};
	}
elsif ($config{'mail_system'} == 4) {
	return $config{'ldap_mailstore'} =~ /^(\$HOME|\$\{HOME\})/;
	}
elsif ($config{'mail_system'} == 5) {
	# VPOPMail users always have it under their homes
	return 1;
	}
}

# user_mail_file(&user)
# Returns the full path to a user's mail file, and the type
sub user_mail_file
{
&require_mail();
local @rv;
if (!$_[0]->{'user'} || !$_[0]->{'home'}) {
	# User doesn't exist!
	@rv = ( );
	}
elsif ($config{'mail_system'} == 1) {
	# Just look at the Sendmail mail file
	@rv = ( &sendmail::user_mail_file($_[0]->{'user'}),
		$sendmail::config{'mail_type'} );
	}
elsif ($config{'mail_system'} == 0) {
	# Find out from Postfix which file to check
	local @pms = &postfix::postfix_mail_system();
	@rv = ( &postfix::postfix_mail_file($_[0]->{'user'}),
		$pms[0] == 2 ? 1 : 0 );
	}
elsif ($config{'mail_system'} == 2 ||
       $config{'mail_system'} == 4 && !$_[0]->{'qmail'}) {
	# Find out from Qmail which file or dir to check
	@rv = ( &qmailadmin::user_mail_dir($_[0]->{'user'}),
		$qmailadmin::config{'mail_system'} == 1 ? 1 : 0 );
	}
elsif ($config{'mail_system'} == 4) {
	# Mail file is an LDAP property
	local $rv = &add_ldapmessagestore($_[0]->{'mailstore'});
	if (-d "$rv/Maildir") {
		@rv = ( "$rv/Maildir", 1 );
		}
	else {
		@rv = ( $rv, 1 );
		}
	}
elsif ($config{'mail_system'} == 5) {
	# Mail dir is under VPOPMail home
	local $md = $config{'vpopmail_md'} || "Maildir";
	@rv = ( "$_[0]->{'home'}/$md", 1 );
	}
elsif ($config{'mail_system'} == 6) { 
	if (-d "$_[0]->{'home'}/Maildir") {
		@rv = ( "$_[0]->{'home'}/Maildir", 1 );
	} 
	else {
		@rv = ( "/var/mail/$_[0]->{'user'}", 1 );
		}
	}
return wantarray ? @rv : $rv[0];
}

# get_mail_style()
# Returns a list containing the mail base directory, directory style,
# mail file in home dir, and maildir in home dir
sub get_mail_style
{
&require_mail();
if ($config{'mail_system'} == 1) {
	# Can get paths from Sendmail module config
	if ($sendmail::config{'mail_dir'}) {
		# File under /var/mail
		return ($sendmail::config{'mail_dir'},
			$sendmail::config{'mail_style'}, undef, undef);
		}
	elsif ($sendmail::config{'mail_type'} == 1) {
		# Maildir in home directory
		return (undef, $sendmail::config{'mail_style'},
			undef, $sendmail::config{'mail_file'});
		}
	else {
		# mbox in home directory
		return (undef, $sendmail::config{'mail_style'},
			$sendmail::config{'mail_file'}, undef);
		}
	}
elsif ($config{'mail_system'} == 0) {
	# Need to query Postfix module for paths
	local @s = &postfix::postfix_mail_system();
	$s[1] =~ s/\/$//;	# Remove / from Maildir/
	if ($s[0] == 0) {
		return ($s[1], 0, undef, undef);
		}
	elsif ($s[0] == 1) {
		return (undef, 0, $s[1], undef);
		}
	elsif ($s[0] == 2) {
		return (undef, 0, undef, $s[1]);
		}
	}
elsif ($config{'mail_system'} == 2) {
	# Need to check qmail module config for paths
	if ($qmailadmin::config{'mail_system'} == 1) {
		return (undef, 0, undef,
			$qmailadmin::config{'mail_dir_qmail'});
		}
	elsif ($qmailadmin::config{'mail_dir'}) {
		return ($qmailadmin::config{'mail_dir'},
			$qmailadmin::config{'mail_style'}, undef, undef);
		}
	else {
		return (undef, $qmailadmin::config{'mail_style'},
			$qmailadmin::config{'mail_file'}, undef);
		}
	}
elsif ($config{'mail_system'} == 4) {
	# Assume ~/Maildir for qmail+ldap
	return (undef, undef, undef, "Maildir");
	}
return ( );
}

# mail_file_size(&user)
# Returns the size in bytes (rounded to blocks), path to and last modified date
# of a user's mail file or directory
sub mail_file_size
{
&require_mail();
local $umf = &user_mail_file($_[0]);
if (-d $umf) {
	# Need to sum up a maildir-format directory, via a recursive search
	local ($sz, $maxmod) = &recursive_disk_usage_mtime($umf);
	return ( $sz, $umf, $maxmod );
	}
else {
	# Just the size of a single mail file
	local @st = stat($umf);
	return ( $st[12]*&quota_bsize("mail", 1) || $st[7], $umf, $st[9] );
	}
}

# recursive_disk_usage_mtime(directory, [only-gid], [levels])
# Returns the number of bytes taken up by all files in some directory,
# and the most recent modification time. The size is based on the filesystem's
# block size, not the file lengths in bytes.
sub recursive_disk_usage_mtime
{
local ($dir, $gid, $levels, $inodes) = @_;
local $dir = &translate_filename($dir);
local $bs = &quota_bsize("mail", 1);
$inodes ||= { };
if (-l $dir) {
	return (0, undef);
	}
elsif (!-d $dir) {
	local @st = stat($dir);
	if ($inodes{$st[1]}++) {
		# Already done this inode (ie. hard link)
		return ( 0, undef );
		}
	elsif (!defined($gid) || $st[5] == $gid) {
		return ( $st[12]*$bs, $st[9] );
		}
	else {
		return ( 0, undef );
		}
	}
else {
	local @st = stat($dir);
	local ($rv, $rt) = (0, undef);
	if (!defined($gid) || $st[5] == $gid) {
		$rv = $st[12]*$bs;
		$rt = $st[9];
		}
	if (!defined($levels) || $levels > 0) {
		opendir(DIR, $dir);
		local @files = readdir(DIR);
		closedir(DIR);
		foreach my $f (@files) {
			next if ($f eq "." || $f eq "..");
			local ($ss, $st) = &recursive_disk_usage_mtime(
				"$dir/$f", $gid,
				defined($levels) ? $levels - 1 : undef,
				$inodes);
			$rv += $ss;
			$rt = $st if ($st > $rt);
			}
		}
	return ($rv, $rt);
	}
}



# mail_system_base()
# Returns the base directory under which user mail files can be found
sub mail_system_base
{
&require_mail();
if ($config{'mail_system'} == 1) {
	# Find out from sendmail module config
	if ($sconfig{'mail_dir'}) {
		return $sconfig{'mail_dir'};
		}
	}
elsif ($config{'mail_system'} == 0) {
	# Find out from postfix
	local @s = &postfix::postfix_mail_system();
	if ($s[0] == 0) {
		return $s[1];
		}
	}
elsif ($config{'mail_system'} == 2) {
	# Find out from qmail module config
	if ($qmconfig{'mail_system'} == 0 && $qmconfig{'mail_dir'}) {
		return $qmconfig{'mail_dir'};
		}
	}
elsif ($config{'mail_system'} == 4) {
	# Need to look at template from module config
	local $pfx = &qmailadmin::get_control_file("ldapmessagestore");
	if ($config{'ldap_mailstore'} =~ /^(\$HOME|\$\{HOME\})/) {
		# Under home .. return it
		&require_useradmin();
		return $home_base;
		}
	elsif ($config{'ldap_mailstore'} !~ /^\//) {
		return $pfx;
		}
	else {
		# Get fixed directory
		local $dir = $config{'ldap_mailstore'};
		$dir =~ s/\$.*$//;
		$dir =~ s/\/[^\/]*$//;
		return $dir || "/";
		}
	}
# If we get here, assume that mail is under home dirs
local %uconfig = &foreign_config("useradmin");
return $home_base;
}

# mail_domain_base(&domain)
# Returns the directory under which user mail files are located for some
# domain, or undef
sub mail_domain_base
{
if ($config{'mail_system'} == 4) {
	# Guess base for domain from mailstore pattern
	local $guess = { 'user' => 'USER', 'home' => 'HOME' };
	&userdom_substitutions($guess, $_[0]);
	local $dir = &add_ldapmessagestore(
		&substitute_domain_template($config{'ldap_mailstore'}, $guess));
	if ($dir =~ /^(.*)\/\Q$_[0]->{'dom'}\E/) {
		return $1;
		}
	return undef;
	}
elsif ($config{'mail_system'} == 5) {
	# All mail for VPOPmail is under the domain's directory
	return &domain_vpopmail_dir($_[0]);
	}
elsif (&mail_under_home()) {
	return "$_[0]->{'home'}/homes";
	}
else {
	# There is no base directory
	return undef;
	}
}

# read_mail_link(&user, &domain)
sub read_mail_link
{
if (&foreign_available("mailboxes")) {
	# Use mailboxes module if possible
	local %mconfig = &foreign_config("mailboxes");
	local %minfo = &get_module_info("mailboxes");
	if ($mconfig{'mail_system'} == $config{'mail_system'}) {
		# Read a Unix user's mail
		if ($config{'mail_system'} == 5) {
			return "../mailboxes/list_mail.cgi?user=".
			       $_[0]->{'user'}."\@".$_[1]->{'dom'}.
			       "&dom=".$_[1]->{'id'};
			}
		else {
			return "../mailboxes/list_mail.cgi?user=".
			       $_[0]->{'user'}."&dom=".$_[1]->{'id'};
			}
		}
	else {
		# Access mail file directly
		return "../mailboxes/list_mail.cgi?user=".
			&urlize(user_mail_file($_[0])).
			"&dom=".$_[1]->{'id'};
		}
	}
else {
	# No mail reading module available
	return undef;
	}
}

# postfix_installed()
# Returns 1 if postfix is installed
sub postfix_installed
{
return &foreign_installed("postfix", 1) == 2;
}

# sendmail_installed()
# Returns 1 if postfix is installed
sub sendmail_installed
{
return &foreign_installed("sendmail", 1) == 2;
}

# exim_installed()
# Returns 1 if exim installed
sub exim_installed
{
return &foreign_installed("exim", 1) == 2;
}

# qmail_installed()
# Returns 1 if qmail is installed
sub qmail_installed
{
return &foreign_installed("qmailadmin", 1) == 2;
}

# qmail_ldap_installed()
# Returns 1 if qmail is installed, and supports LDAP
sub qmail_ldap_installed
{
return 0 if (!&qmail_installed());
local %qconfig = &foreign_config("qmailadmin");
return -r "$qconfig{'qmail_dir'}/control/ldapserver" ? 1 : 0;
}

# qmail_vpopmail_installed()
# Returns 1 if qmail is installed, and the VPOPMail extensions
sub qmail_vpopmail_installed
{
return 0 if (!&qmail_installed());
return -x "$config{'vpopmail_dir'}/bin/vadddomain";
}

# check_alias_clash(name)
# Checks if an alias with the given name already exists, and returns it
sub check_alias_clash
{
&require_mail();
if ($config{'mail_system'} == 1) {
	local @aliases = &sendmail::list_aliases($sendmail_afiles);
	local ($clash) = grep { lc($_->{'name'}) eq lc($_[0]) &&
				$_->{'enabled'} } @aliases;
	return $clash;
	}
elsif ($config{'mail_system'} == 0) {
	local @aliases = &$postfix_list_aliases($postfix_afiles);
	local ($clash) = grep { lc($_->{'name'}) eq lc($_[0]) &&
				$_->{'enabled'} } @aliases;
	return $clash;
	}
return undef;
}

# backup_mail(&domain, file, &options)
# Saves all mail aliases and mailbox users for this domain
sub backup_mail
{
&require_mail();

# Create dummy file
&open_tempfile(FILE, ">$_[1]");
&close_tempfile(FILE);

# Build file of all virtusers. Each line contains one virtuser address and
# it's destinations, in alias-style format. Those used by some plugin (like
# Mailman) are not included
&$first_print($text{'backup_mailaliases'});
&open_tempfile(AFILE, ">$_[1]_aliases");
local $a;
foreach $a (&list_domain_aliases($_[0], 1)) {
	&print_tempfile(AFILE, $a->{'from'},": ");
	&print_tempfile(AFILE, join(",", @{$a->{'to'}}),"\n");
	}
&close_tempfile(AFILE);
&$second_print($text{'setup_done'});

# Build file of all mailboxes. Each user has a passwd-file style line with
# the email address and quotas appended, followed by a list of destination
# addresses.
&$first_print($text{'backup_mailusers'});
&open_tempfile(UFILE, ">$_[1]_users");
local $u;
foreach $u (&list_domain_users($_[0])) {
	&print_tempfile(UFILE, join(":", $u->{'user'}, $u->{'pass'},
			      $u->{'webowner'} ? 'w' : $u->{'uid'}, $u->{'gid'},
			      $u->{'real'}, $u->{'home'}, $u->{'shell'},
			      $u->{'email'}));

	# Add home and mail quotas
	if (&has_home_quotas() && $u->{'unix'}) {
		&print_tempfile(UFILE, ":$u->{'quota'}");
		if (&has_mail_quotas()) {
			&print_tempfile(UFILE, ":$u->{'mquota'}");
			}
		else {
			&print_tempfile(UFILE, ":-");
			}
		}
	elsif ($u->{'mailquota'}) {
		&print_tempfile(UFILE, ":$u->{'qquota'}");
		&print_tempfile(UFILE, ":-");
		}
	else {
		&print_tempfile(UFILE, ":-:-");
		}

	# Add databases
	local (@dbstr, %donetype);
	foreach my $db (@{$u->{'dbs'}}) {
		push(@dbstr, $db->{'type'}." ".$db->{'name'});
		$donetype{$db->{'type'}}++;
		}
	&print_tempfile(UFILE, ":".(join(";", @dbstr) || "-"));

	# Add database-type passwords
	local (@passstr);
	foreach my $t (keys %donetype) {
		push(@passstr, $t." ".$u->{$t."_pass"});
		}
	&print_tempfile(UFILE, ":".(join(";", @passstr) || "-"));

	# Add secondary groups
	&print_tempfile(UFILE, ":".(join(";", @{$u->{'secs'}}) || "-"));

	&print_tempfile(UFILE, "\n");
	&print_tempfile(UFILE, join(",", @{$u->{'to'}}),"\n");
	}
&close_tempfile(UFILE);

# Copy plain text and hashed passwords file too
if (-r "$plainpass_dir/$_[0]->{'id'}") {
	&copy_source_dest("$plainpass_dir/$_[0]->{'id'}", "$_[1]_plainpass");
	}
if (-r "$hashpass_dir/$_[0]->{'id'}") {
	&copy_source_dest("$hashpass_dir/$_[0]->{'id'}", "$_[1]_hashpass");
	}

# Copy no-spam flags file too
if (-r "$nospam_dir/$_[0]->{'id'}") {
	&copy_source_dest("$nospam_dir/$_[0]->{'id'}", "$_[1]_nospam");
	}

# Create BCC file
if ($supports_bcc) {
	local $bcc = &get_domain_sender_bcc($_[0]);
	&open_tempfile(BCC, ">$_[1]_bcc");
	&print_tempfile(BCC, $bcc,"\n");
	&close_tempfile(BCC);
	}

# Create sender dependent file
if ($supports_dependent) {
	local $dependent = &get_domain_dependent($_[0]);
	&open_tempfile(DEPENDENT, ">$_[1]_dependent");
	&print_tempfile(DEPENDENT, $dependent,"\n");
	&close_tempfile(DEPENDENT);
	}

&$second_print($text{'setup_done'});

if (!&mail_under_home()) {
	# Backup actual mail files too..
	local $mbase = &mail_system_base();
	local @mfiles;
	&$first_print($text{'backup_mailfiles'});
	foreach $u (&list_domain_users($_[0])) {
		local $umf = &user_mail_file($u);
		if ($umf =~ s/^$mbase\///) {
			push(@mfiles, $umf) if (-r "$mbase/$umf");
			}
		}
	if (!@mfiles) {
		&$second_print($text{'backup_mailfilesnone'});
		}
	else {
		local $mfiles = join(" ", map { quotemeta($_) } @mfiles);
		local $out;
		&execute_command("cd '$mbase' && tar cf '$_[1]_files' $mfiles",
				 undef, \$out, \$out);
		if ($?) {
			&$second_print(&text('backup_mailfilesfailed',
					     "<pre>$out</pre>"));
			return 0;
			}
		else {
			&$second_print($text{'setup_done'});
			}
		}
	}

# Backup all user cron jobs
&foreign_require("cron", "cron-lib.pl");
&$first_print($text{'backup_mailcrons'});
local $croncount = 0;
foreach $u (&list_domain_users($_[0], 1)) {
	local $cronfile = &cron::cron_file({ 'user' => $u->{'user'} });
	if (-r $cronfile) {
		&copy_source_dest($cronfile, $_[1]."_cron_".$u->{'user'});
		$croncount++;
		}
	}
&open_tempfile(COUNT, ">$_[1]_cron");
&print_tempfile(COUNT, $croncount,"\n");
&close_tempfile(COUNT);
if ($croncount) {
	&$second_print($text{'setup_done'});
	}
else {
	&$second_print($text{'backup_mailfilesnone'});
	}

# Backup Dovecot control files, if in custom location
if (&foreign_check("dovecot") && &foreign_installed("dovecot")) {
	&foreign_require("dovecot");
	local $conf = &dovecot::get_config();
	local $env = &dovecot::find("mail_location", $conf, 2) ?
			&dovecot::find_value("mail_location", $conf) :
			&dovecot::find_value("default_mail_env", $conf);
	if ($env =~ /:CONTROL=([^:]+)\/%u/) {
		local $control = $1;
		&$first_print($text{'backup_mailcontrol'});
		local @names;
		foreach $u (&list_domain_users($_[0], 0, 1, 1, 1)) {
			if (-e "$control/$u->{'user'}") {
				push(@names, $u->{'user'});
				}
			local $repl = &replace_atsign($u->{'user'});
			if ($repl ne $u->{'user'} && -e "$control/$repl") {
				push(@names, $repl);
				}
			}
		@names = &unique(@names);
		if (@names) {
			local $out;
			&execute_command("cd ".quotemeta($control)." && ".
					 "tar cf ".quotemeta($_[1]."_control").
					 " ".join(" ", @names),
					 undef, \$out, \$out);
			if ($?) {
				&$second_print(&text('backup_emailcontrol',
						     $out));
				}
			else {
				&$second_print($text{'setup_done'});
				}
			}
		else {
			&$second_print($text{'backup_nomailcontrol'});
			}
		}
	}

# If any user's homes are outside the domain root, back them up separately
local @homeless;
foreach $u (&list_domain_users($_[0], 1)) {
	if ($u->{'unix'} && -d $u->{'home'} &&
	    !&is_under_directory($_[0]->{'home'}, $u->{'home'})) {
		push(@homeless, $u);
		}
	}
if (@homeless) {
	&$first_print(&text('backup_mailhomeless', scalar(@homeless)));
	foreach my $u (@homeless) {
		local $file = $_[1]."_homes_".$u->{'user'};
		local $out;
		&execute_command("cd ".quotemeta($u->{'home'})." && ".
				 "tar cf ".quotemeta($file)." .",
				 undef, \$out, \$out);
		if ($?) {
			&$second_print(&text('backup_mailhomefailed',
					     "<pre>$out</pre>"));
			}
		}
	&$second_print($text{'setup_done'});
	}

return 1;
}

# restore_mail(&domain, file, &options, &all-options)
sub restore_mail
{
local ($u, %olduid, @errs);
&obtain_lock_mail($_[0]);
&obtain_lock_unix($_[0]);
if ($_[2]->{'mailuser'}) {
	# Just doing a single user .. delete him first if he exists
	&$first_print(&text('restore_mailusers2', $_[2]->{'mailuser'}));
	($u) = grep { $_->{'user'} eq $_[2]->{'mailuser'} ||
	      &remove_userdom($_->{'user'}, $_[0]) eq $_[2]->{'mailuser'} }
	      &list_domain_users($_[0], 1);
	if ($u) {
		$olduid{$u->{'user'}} = $u->{'uid'};
		&delete_user($u, $_[0]);
		}
	}
else {
	# Delete all mailboxes (but not home dirs) and re-create
	&$first_print($text{'restore_mailusers'});
	foreach $u (&list_domain_users($_[0], 1)) {
		$olduid{$u->{'user'}} = $u->{'uid'};
		&delete_user($u, $_[0]);
		}
	}
local %exists;
foreach $u (&list_all_users()) {
	$exists{$u->{'name'},$u->{'unix'}} = $u;
	}
local $foundmailuser;
local $_;
open(UFILE, "$_[1]_users");
while(<UFILE>) {
	s/\r|\n//g;
	local @user = split(/:/, $_);
	$_ = <UFILE>;
	s/\r|\n//g;
	if ($_[2]->{'mailuser'}) {
		# Skip all users except the specified one
		if ($user[0] eq $_[2]->{'mailuser'} ||
		    &remove_userdom($user[0], $_[0]) eq $_[2]->{'mailuser'}) {
			$foundmailuser = $user[0];
			}
		else {
			next;
			}
		}
	local @to = split(/,/, $_);
	if ($user[0] eq $_[0]->{'user'}) {
		# Domain owner, just update alias list
		local @users = &list_domain_users($_[0]);
		local ($uinfo) = grep { $_->{'user'} eq $_[0]->{'user'}} @users;
		if ($uinfo) {
			local %old = %$uinfo;
			$uinfo->{'email'} = $user[7];
			$uinfo->{'to'} = \@to;
			&modify_user($uinfo, \%old, $_[0]);
			}
		}
	else {
		# Need to create user
		local $uinfo = &create_initial_user($_[0], 0, $user[2] eq 'w');
		if ($exists{$user[0],$uinfo->{'unix'}}) {
			push(@errs, &text('restore_mailexists', $user[0]));
			next;
			}
		$uinfo->{'user'} = $user[0];
		$uinfo->{'pass'} = $user[1];
		if ($user[2] eq 'w') {
			# Web management user, so user same UID as server
			$uinfo->{'uid'} = $_[0]->{'uid'};
			}
		elsif ($olduid{$user[0]}) {
			# Use old UID
			$uinfo->{'uid'} = $olduid{$user[0]};
			}
		elsif ($_[3]->{'reuid'}) {
			# Re-allocate UID
			local %taken;
			&build_taken(\%taken);
			$uinfo->{'uid'} = &allocate_uid(\%taken);
			}
		else {
			# Stick with original
			$uinfo->{'uid'} = $user[2];
			}
		$uinfo->{'gid'} = $_[0]->{'gid'};
		$uinfo->{'real'} = $user[4];
		if ($uinfo->{'fixedhome'}) {
			# Home directory is fixed, so don't set
			}
		elsif ($_[5]->{'home'} && $_[5]->{'home'} ne $_[0]->{'home'}) {
			# Restoring under different domain home, so need to fix
			# user's home
			$uinfo->{'home'} = $user[5];
			$uinfo->{'home'} =~s/^$_[5]->{'home'}/$_[0]->{'home'}/g;
			}
		else {
			# Use home from original
			$uinfo->{'home'} = $user[5];
			}
		$uinfo->{'shell'} = $user[6];
		$uinfo->{'email'} = $user[7];
		$uinfo->{'to'} = \@to;
		if ($uinfo->{'mailquota'}) {
			$uinfo->{'qquota'} = $user[8];
			}
		elsif ($uinfo->{'unix'} && !$uinfo->{'noquota'}) {
			$uinfo->{'quota'} = $user[8];
			$uinfo->{'mquota'} = $user[9];
			}

		# Restore databases
		if ($user[10] && $user[10] ne "-") {
			local @dbs = split(/;/, $user[10]);
			foreach my $db (@dbs) {
				my ($dbtype, $dbname) = split(/\s+/, $db, 2);
				push(@{$uinfo->{'dbs'}}, { 'type' => $dbtype,
							   'name' => $dbname });
				}
			}

		# Restore database passwords
		if ($user[11] && $user[11] ne "-") {
			local @dbpass = split(/;/, $user[11]);
			foreach my $db (@dbpass) {
				my ($dbtype, $dbpass) = split(/\s+/, $db, 2);
				$uinfo->{$dbtype."_pass"} = $dbpass;
				}
			}

		# Restore secondary groups
		if ($user[12] && $user[12] ne "-") {
			$uinfo->{'secs'} = [ split(/;/, $user[12]) ];
			}

		# Check for possible DB username clashes
		#foreach my $dt (&unique(map { $_->{'type'} }
		#			&domain_databases($_[0]))) {
		#	local $cfunc = "check_".$dt."_user_clash";
		#	next if (!defined(&$cfunc));
		#	local $ufunc = $dt."_username";
		#	if (&$cfunc($_[0], &$ufunc($uinfo->{'user'}))) {
		#		# Clash found! Don't create this DB type login
		#		@{$uinfo->{'dbs'}} =
		#			grep { $_->{'type'} ne $dt }
		#			@{$uinfo->{'dbs'}};
		#		delete($uinfo->{$dt."_pass"});
		#		}
		#	}

		# Create the user, which will also add any configured DB account
		&create_user($uinfo, $_[0]);

		# Create an empty mail file, which may be needed if inbox
		# location has moved
		if ($uinfo->{'email'} && !$uinfo->{'nomailfile'}) {
			&create_mail_file($uinfo, $_[0]);
			}

		# If the user's home is outside the domain's home, re-extract
		# it from the backup
		if ($uinfo->{'unix'} &&
		    !&is_under_directory($_[0]->{'home'}, $uinfo->{'home'})) {
			local $file = $_[1]."_homes_".$uinfo->{'user'};
			if (!-d $uinfo->{'home'}) {
				&create_user_home($uinfo, $_[0]);
				}
			local $out;
			&execute_command(
				"cd ".quotemeta($uinfo->{'home'})." && ".
				"tar xf ".quotemeta($file)." .",
				undef, \$out, \$out);
			}
		}
	}
close(UFILE);

# Restore plain-text password file too
if (-r "$_[1]_plainpass") {
	if ($_[2]->{'mailuser'}) {
		# Just copy one plain password
		local (%oldplain, %newplain);
		&read_file("$_[1]_plainpass", \%oldplain);
		&read_file("$plainpass_dir/$_[0]->{'id'}", \%newplain);
		$newplain{$_[2]->{'mailuser'}} = $oldplain{$_[2]->{'mailuser'}};
		$newplain{$_[2]->{'mailuser'}." encrypted"} =
			$oldplain{$_[2]->{'mailuser'}." encrypted"};
		&write_file("$plainpass_dir/$_[0]->{'id'}", \%newplain);
		}
	else {
		# Copy the whole file
		&copy_source_dest("$_[1]_plainpass",
				  "$plainpass_dir/$_[0]->{'id'}");
		}
	}

# Restore hashed password file too
if (-r "$_[1]_hashpass") {
	if ($_[2]->{'mailuser'}) {
		# Just copy one hash password
		local (%oldhash, %newhash);
		&read_file("$_[1]_hashpass", \%oldhash);
		&read_file("$hashpass_dir/$_[0]->{'id'}", \%newhash);
		foreach my $s (@hashpass_types) {
			$newhash{$_[2]->{'mailuser'}.' '.$s} =
				$oldhash{$_[2]->{'mailuser'}.' '.$s};
			}
		&write_file("$hashpass_dir/$_[0]->{'id'}", \%newhash);
		}
	else {
		# Copy the whole file
		&copy_source_dest("$_[1]_hashpass",
				  "$hashpass_dir/$_[0]->{'id'}");
		}
	}

# Restore no-spam flags file too
if (-r "$_[1]_nospam") {
	if ($_[2]->{'mailuser'}) {
		# Just copy one flag
		local (%oldspam, %newspam);
		&read_file("$_[1]_nospam", \%oldspam);
		&read_file("$nospam_dir/$_[0]->{'id'}", \%newspam);
		$newspam{$_[2]->{'mailuser'}} = $oldspam{$_[2]->{'mailuser'}};
		&write_file("$nospam_dir/$_[0]->{'id'}", \%newspam);
		}
	else {
		# Copy the whole file
		&copy_source_dest("$_[1]_nospam",
				  "$nospam_dir/$_[0]->{'id'}");
		}
	}

# Restore BCC file
if ($supports_bcc && -r "$_[1]_bcc") {
	local $bcc = &read_file_contents("$_[1]_bcc");
	chop($bcc);
	&save_domain_sender_bcc($_[0], $bcc);
	}

# Restore sender-dependent IP
if ($supports_dependent && -r "$_[1]_dependent") {
	local $dependent = &read_file_contents("$_[1]_dependent");
	chop($dependent);
	&save_domain_dependent($_[0], $dependent ? 1 : 0);
	}

if (@errs) {
	&$second_print(&text('restore_mailerrs', join(" ", @errs)));
	}
elsif ($_[2]->{'mailuser'} && !$foundmailuser) {
	&$second_print(&text('restore_mailnosuch', $_[2]->{'mailuser'}));
	}
else {
	&$second_print($text{'setup_done'});
	}

if (!$_[2]->{'mailuser'}) {
	# Delete all aliases and re-create (except for those used by plugins
	# such as mailman)
	&$first_print($text{'restore_mailaliases'});
	local $a;
	foreach $a (&list_domain_aliases($_[0], 1)) {
		&delete_virtuser($a);
		}
	local %existing = map { $_->{'from'}, $_ } &list_virtusers();
	local $_;
	open(AFILE, "$_[1]_aliases");
	while(<AFILE>) {
		if (/^(\S+):\s*(.*)/) {
			local $virt = { 'from' => $1,
					'to' => [ split(/,/, $2) ] };
			next if ($exists{$virt->{'from'}}++);
			if ($virt->{'to'}->[0] =~ /^(\S+)\\@(\S+)$/ &&
			    $config{'mail_system'} == 0) {
				# Virtuser is to a local user with an @ in
				# the name, like foo\@bar.com. But on Postfix
				# this won't work - instead, we need to use the
				# alternate foo-bar.com format.
				$virt->{'to'}->[0] = $1."-".$2;
				}
			eval {
				# Alias creation can fail if a clash exists..
				# but just skip it
				eval {
					local $main::error_must_die = 1;
					&create_virtuser($virt);
					};
				};
			}
		}
	close(AFILE);
	&sync_alias_virtuals($_[0]);
	&$second_print($text{'setup_done'});
	}

# Get users whose mail files may need to be moved
&foreign_require("mailboxes", "mailboxes-lib.pl");
local @users = &list_domain_users($_[0]);
if ($_[2]->{'mailuser'}) {
	@users = grep { $_->{'user'} eq $foundmailuser } @users;
	}


if (-r "$_[1]_files" &&
    (!$_[2]->{'mailuser'} || $foundmailuser)) {
	local $xtract;
	if (!&mail_under_home()) {
		# Can just extract all mail files in /var/mail
		$xtract = &mail_system_base();
		}
	else {
		# This system puts mail files under homes, but the source
		# system used /var/mail ! So we need to extract to a temp
		# location and then move mail files.
		$xtract = &transname();
		&make_dir($xtract, 0700);
		}
	local $out;
	if ($_[2]->{'mailuser'}) {
		# Just do one user
		&$first_print(&text('restore_mailfiles3', $_[2]->{'mailuser'}));
		&execute_command("cd '$xtract' && tar xf '$_[1]_files' '$foundmailuser' 2>&1", undef, \$out, \$out);
		}
	else {
		# Do all users
		&$first_print($text{'restore_mailfiles'});
		&execute_command("cd '$xtract' && tar xf '$_[1]_files' 2>&1",
				 undef, \$out, \$out);
		}
	if ($?) {
		&$second_print(&text('backup_mailfilesfailed',
				     "<pre>$out</pre>"));
		return 0;
		}
	if (&mail_under_home()) {
		# Move mail from /var/mail to ~/Maildir
		foreach my $u (@users) {
			local $path = "$xtract/$u->{'user'}";
			local $sf = { 'type' => -d $path ? 1 : 0,
				      'file' => $path };
			local ($df) =
				&mailboxes::list_user_folders($u->{'user'});
			if ($df) {
				&mailboxes::mailbox_empty_folder($df);
				&mailboxes::mailbox_copy_folder($sf, $df);
				}
			}
		}
	&$second_print($text{'setup_done'});
	}
elsif (!&mail_under_home()) {
	# If the users have ~/Maildir directories and no mail files
	# at the new locations (typically /var/mail), move them over
	local $doneprint;
	foreach my $u (@users) {
		local ($df) = &mailboxes::list_user_folders($u->{'user'});
		next if (-e $df->{'file'});
		local $sf;
		if (-d "$u->{'home'}/Maildir") {
			$sf = { 'type' => 1,
				'file' => "$u->{'home'}/Maildir" };
			}
		elsif (-r "$u->{'home'}/Mailbox") {
			$sf = { 'type' => 0,
				'file' => "$u->{'home'}/Mailbox" };
			}
		else {
			next;
			}
		nest if ($sf->{'file'} eq $df->{'file'});
		if (!$doneprint) {
			&$first_print($text{'restore_movemove'});
			$doneprint++;
			}
		&mailboxes::mailbox_move_folder($sf, $df);
		}
	if ($doneprint) {
		&$second_print($text{'setup_done'});
		}
	}

# Check if the location for additional folders differs between systems,
# and if so copy them across
local %mconfig = &foreign_config("mailboxes");
local $newdir = $mconfig{'mail_usermin'};
local $olddir = $_[0]->{'backup_mail_folders'};
if ($newdir && $olddir && $newdir ne $olddir && @users) {
	# Need to migrate, such as when moving from a system using ~/mail/mbox
	# to ~/Maildir/.dir
	&$first_print(&text('restore_mailmove2'));
	foreach my $u (@users) {
		local $mailboxes::config{'mail_usermin'} = $olddir;
		local @folders = &mailboxes::list_user_folders($u->{'user'});
		local $newbase = "$u->{'home'}/$newdir";
		local $oldbase = "$u->{'home'}/$olddir";
		if (!-e $newbase) {
			# Create folders dir
			&make_dir($newbase, 0755);
			&set_ownership_permissions($u->{'uid'}, $u->{'gid'},
						   undef, $newbase);
			}
		foreach my $oldf (@folders) {
			next if (!&is_under_directory("$u->{'home'}/$olddir",
						      $oldf->{'file'}));
			local $newf = { };
			local $oldname = $oldf->{'file'};
			next if ($oldname eq $oldbase);	  # Skip inbox
			$oldname =~ s/^\Q$oldbase\E\///;  # Get folder name,
			local $oldnameorig = $oldname;
			$oldname =~ s/^\.//;		  # with no dots before
			$oldname =~ s/\/\./\//;		  # path elements
			if ($newdir eq "Maildir") {
				# Assume Maildir++ format for dest
				$newf->{'type'} = 1;
				$oldname =~ s/\//\.\//g;  # Put back Maildir++
				$oldname = ".$oldname";   # dots before elements
				$newf->{'file'} = "$newbase/$oldname";
				}
			elsif ($newdir eq "mail") {
				# Assume mbox
				$newf->{'type'} = 0;
				$newf->{'file'} = "$newbase/$oldname";
				}
			else {
				# Keep the same
				$newf->{'type'} = $oldf->{'type'};
				$newf->{'file'} = "$newbase/$oldnameorig";
				}
			if ($newf->{'type'} == 1 && !-e $newf->{'file'}) {
				# Create Maildir if missing
				&make_dir($newf->{'file'}, 0755);
				&set_ownership_permissions(
					$u->{'uid'}, $u->{'gid'}, 0755,
					$newf->{'file'});
				}
			eval {
				local $main::error_must_die = 1;
				&mailboxes::mailbox_move_folder($oldf, $newf);
				};
			if ($@) {
				&$second_print(&text('restore_emailmove2',
					$oldf->{'file'}, $newf->{'file'}, $@));
				}
			}
		}
	&$second_print($text{'setup_done'});
	}

# Restore Cron job files
if (-r "$_[1]_cron") {
	&$first_print($text{'restore_mailcrons'});
	&foreign_require("cron", "cron-lib.pl");
	foreach $u (&list_domain_users($_[0], 1)) {
		next if ($_[2]->{'mailuser'} && $u->{'user'} ne $foundmailuser);
		local $cf = $_[1]."_cron_".$u->{'user'};
		$cf = "/dev/null" if (!-r $cf);
		&copy_source_dest($cf, $cron::cron_temp_file);
		&cron::copy_crontab($u->{'user'});
		}
	&$second_print($text{'setup_done'});
	}

# Restore Dovecot control files
if (-r "$_[1]_control" && &foreign_check("dovecot") &&
			  &foreign_installed("dovecot")) {
	&foreign_require("dovecot");
        local $conf = &dovecot::get_config();
	local $env = &dovecot::find("mail_location", $conf, 2) ?
                        &dovecot::find_value("mail_location", $conf) :
                        &dovecot::find_value("default_mail_env", $conf);
	if ($env =~ /:CONTROL=([^:]+)\/%u/) {
		# Local dovecot specifies a control file location
		local $control = $1;
		&$first_print($text{'restore_mailcontrol'});
		local $cmd = "cd ".quotemeta($control)." && ".
                             "tar xf ".quotemeta($_[1]."_control");
		if ($_[2]->{'mailuser'}) {
			# Limit extract to one user
			$cmd .= " ".quotemeta($_[2]->{'mailuser'});
			local $at = &replace_atsign($_[2]->{'mailuser'});
			if ($at ne $_[2]->{'mailuser'}) {
				$cmd .= " ".quotemeta($at);
				}
			}
		local $out;
		&execute_command($cmd, undef, \$out, \$out);
		if ($?) {
			&$second_print(&text('restore_emailcontrol', $out));
			}
		else {
			&$second_print($text{'setup_done'});
			}
		}
	}

# Set mailbox user home directory permissions
local $hb = "$_[0]->{'home'}/$config{'homes_dir'}";
foreach $u (&list_domain_users($_[0], 1)) {
	if (-d $u->{'home'} && &is_under_directory($hb, $u->{'home'}) &&
	    (!$_[2]->{'mailuser'} || $u->{'user'} eq $foundmailuser)) {
		&execute_command("chown -R $u->{'uid'}:$u->{'gid'} ".
		       quotemeta($u->{'home'}));
		}
	}

# Create autoreply file links
if (defined(&create_autoreply_alias_links)) {
	&create_autoreply_alias_links($_[0]);
	}

&release_lock_mail($_[0]);
&release_lock_unix($_[0]);
return 1;
}

# show_restore_mail(&options, &domain)
# Returns HTML for mail restore option inputs
sub show_restore_mail
{
local $rv;
if ($_[1] && !&mail_under_home()) {
	# Offer to restore just one user
	$rv .= "<br>".$text{'restore_mailuser'}." ".
		&ui_textbox("mail_mailuser", $_[0]->{'mailuser'}, 15);
	}
return $rv;
}

# parse_restore_mail(&in, &domain)
# Parses the inputs for mail backup options
sub parse_restore_mail
{
local %in = %{$_[0]};
return { 'mailuser' => $in{'mail_mailuser'} };
}

# check_clash(name, dom)
# Returns 1 if a virtuser or user with the name already exists.
# Returns 2 if an alias with the same mailbox name already exists.
sub check_clash
{
&require_mail();
local @virts = &list_virtusers();
local ($clash) = grep { $_->{'from'} eq $_[0]."\@".$_[1] } @virts;
return 1 if ($clash);
if ($config{'mail_system'} == 1) {
	# Check for a Sendmail alias with the same name as the user
	local @aliases = &sendmail::list_aliases($sendmail_afiles);
	local $an = $_[0] ? "$_[0]-$_[1]" : "default-$_[1]";
	($clash) = grep { ($config{'alias_clash'} &&
			   $_[0] && $_->{'name'} eq $_[0]) ||
			  $_->{'name'} eq $an } @aliases;
	return 2 if ($clash);
	}
elsif ($config{'mail_system'} == 0) {
	# Check for a Postfix alias with the same name as the user
	local @aliases = &$postfix_list_aliases($postfix_afiles);
	local $an = $_[0] ? "$_[0]-$_[1]" : "default-$_[1]";
	($clash) = grep { ($config{'alias_clash'} &&
			   $_[0] && $_->{'name'} eq $_[0]) ||
			  $_->{'name'} eq $an } @aliases;
	return 2 if ($clash);
	}
elsif ($config{'mail_system'} == 2) {
	# Check for a Qmail .qmail file with the same name as the user
	local @aliases = &qmailadmin::list_aliases();
	($clash) = grep { $config{'alias_clash'} && $_[0] && $_ eq $_[0] }
			@aliases;
	return 2 if ($clash);
	}
return 0;
}

# check_depends_mail(&dom)
# Ensure that a mail domain has a home directory and Unix group
sub check_depends_mail
{
# Check for virtusers file
&require_mail();
if ($config{'mail_system'} == 1) {
	$sendmail_vfile || return $text{'setup_esendmailvfile'};
	@$sendmail_afiles || return $text{'setup_esendmailafile'};
	!$config{'generics'} || $sendmail_gdbm ||
		return $text{'setup_esendmailgfile'};
	}
elsif ($config{'mail_system'} == 0) {
	@virtual_map_files || $virtual_map_backends[0] eq "mysql" ||
	    $virtual_map_backends[0] eq "ldap" ||
		return $text{'setup_epostfixvfile'};
	@$postfix_afiles || $alias_backends[0] eq "mysql" ||
	    $alias_backends[0] eq "ldap" || return $text{'setup_epostfixafile'};
	!$config{'generics'} || $canonical_maps ||
		return $text{'setup_epostfixgfile'};
	}
if ($_[0]->{'alias'} && !$_[0]->{'aliasmail'}) {
	# If this is an alias domain, then no home is needed
	return undef;
	}
elsif ($_[0]->{'parent'}) {
	# If this is a sub-domain, then the parent needs a Unix user
	local $parent = &get_domain($_[0]->{'parent'});
	return $parent->{'unix'} ? undef : $text{'setup_edepmail'};
	}
elsif ($config{'mail_system'} == 5) {
	# For a VPOPMail domain, there are no dependencies!
	return undef;
	}
else {
	# For a top-level domain, it needs a Unix user
	return $_[0]->{'unix'} ? undef : $text{'setup_edepmail'};
	}
}

# check_anti_depends_mail(&dom)
# Ensure that a parent server without email does not have any aliases with it
sub check_anti_depends_mail
{
if (!$_[0]->{'mail'}) {
	local @aliases = &get_domain_by("alias", $_[0]->{'id'});
	foreach my $s (@aliases) {
		return &text('setup_edepmailalias', $s->{'dom'})
			if ($s->{'mail'});
		}
	}
return undef;
}

# mail_system_name([num])
sub mail_system_name
{
local $num = defined($_[0]) ? $_[0] : $config{'mail_system'};
return $text{'mail_system_'.$num} || "???";
}

# create_replace_mapping(mapname, &map, [&force-file])
# Add or replace a Postfix mapping
sub create_replace_mapping
{
local $maps = &postfix::get_maps($_[0], $_[2]);
local ($clash) = grep { $_->{'name'} eq $_[1]->{'name'} } @$maps;
if ($clash) {
	&postfix::modify_mapping($_[0], $clash, $_[1]);
	}
else {
	&postfix::create_mapping($_[0], $_[1], $_[2]);
	}
}

# mail_system_needs_group()
# Returns 1 if the current mail system needs a Unix group for mailboxes
sub mail_system_needs_group
{
return 0 if ($config{'mail_system'} == 5);	# never for vpopmail
#return 0 if ($config{'mail_system'} == 4 &&	# not for Qmail+LDAP,
#	     !$config{'ldap_unix'});		# if users are non-unix
return 0 if ($config{'mail_system'} == 6);	# never for exim
return 1;
}

# bandwidth_all_mail(&domains-list, &starts-hash, &bw-hash-hash)
# Scans through the mail log, and updates all domains at once. Returns a new
# hash reference of start times.
sub bandwidth_all_mail
{
local ($doms, $starts, $bws) = @_;
local %max_ltime = %$starts;
local %max_updated;
local $maillog = $config{'bw_maillog'};
$maillog = &get_mail_log() if ($maillog eq "auto");
return $starts if (!$maillog);

# Build a map from domain names to objects, and from Unix usernames to objects
local (%maildoms, %mailusers);
foreach my $d (@$doms) {
	$maildoms{$d->{'dom'}} = $d;
	foreach my $md (split(/\s+/, $d->{'bw_maildoms'})) {
		$maildoms{$md} = $d;
		if($config{'bw_mail_all'}){ $maildoms{$d->{'uid'}} = $d; }
		}
	foreach my $user (&list_domain_users($d, 0, 1, 1, 1)) {
		$mailusers{$user->{'user'}} = $d;
		if($config{'bw_mail_all'}){ $maildoms{$user->{'user'}} = $d; }
		}
	}
local $myhostname = &get_system_hostname();

# Find the minimum last activity time
local $start_now = time();
local $min_ltime = $start_now+24*60*60;
foreach my $lt (values %$starts) {
	$min_ltime = $lt if ($lt && $lt < $min_ltime);
	}

local $f;
foreach $f ($config{'bw_maillog_rotated'} ?
	    &all_log_files($maillog, $min_ltime) :
	    ( $maillog )) {
	local $_;
	&open_uncompress_file(LOG, $f);

	# Scan the log, looking for entries for various mail systems
	local (%sizes, %fromdoms);
	local $now = time();
	local @tm = localtime($now);
	while(<LOG>) {
		# Sendmail / postfix formats
		s/\r|\n//g;

		# Remove Solaris extra part like [ID 197553 mail.info]
		s/\[ID\s+\d+\s+\S+\]\s+//;
        
		if ($config{'bw_mail_all'} && /^(\S+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\S+)\s+(\S+):\s+(\S+):\s+uid=(\S+)\s+from=(\S+)/) {
			# The initial Sending Uid: line that contains the user id and user for sending from scripts
			# Will not work if not running php as cgi
			local ($id, $uid, $fromuser) = ($8, $9, $10);
			local $md = $maildoms{$uid};
			if ($md && $config{'bw_mail_all'}) {
				# Mail is from a local user. If it is to a non-
				# local domain, we will count it in the next block
				$fromdoms{$id} = $md;
				}
			}
		elsif ($config{'bw_mail_all'} && /^(\S+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\S+)\s+(\S+):\s+(\S+):\s+client=(\S+),\s+sasl_method=(\S+),\s+sasl_username=(\S+)/) {
			# The initial Authenticated Sending User: line that contains the user logged in sending from sasl_authentication
			local ($id, $fromuser) = ($8, $11);
			local $md = $maildoms{$fromuser};
			if ($md && !$fromdoms{$id} && $config{'bw_mail_all'}) {
				# Mail is from a local authenticated user. If it is to a non-
				# local domain, we will count it in the next block
				$fromdoms{$id} = $md;
				}
			}
		
		elsif (/^(\S+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\S+)\s+(\S+):\s+(\S+):\s+from=(\S+),\s+size=(\d+)/) {
			# The initial From: line that contains the size
			local ($id, $size, $fromuser) = ($8, $10, $9);
			$sizes{$id} = $size;
			$fromuser =~ s/^<(.*)>/$1/;
                        $fromuser =~ s/,$//;
			local ($mb, $dom) = split(/\@/, $fromuser);
			local $md = $maildoms{$dom};
			if (!$md && $dom eq $myhostname) {
				# Check for mail from local user@hostname
				$md = $mailusers{$mb};
				}
			if (!$md && !$dom) {
				# Check for mail from un-qualified user
				$md = $mailusers{$fromuser};
				}
			if ($md) {
				# Mail is from a hosted domain. If it is to a
				# non-local domain, we will count it in the
				# next block
				$fromdoms{$id} = $md;
				}
			}
		elsif (/^(\S+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\S+)\s+(\S+):\s+(\S+):\s+to=(\S+),(\s+orig_to=(\S+))?/) {
			# A To: line that has the local recipient.
			# The date doesn't have the year, so we need to try
			# the day and month for this year and last year.
			local $ltime;
			eval { $ltime = timelocal($5, $4, $3, $2,
			    $apache_mmap{lc($1)}, $tm[5]); };
			if (!$ltime || $ltime > $now+(24*60*60)) {
				# Must have been last year!
				eval { $ltime = timelocal($5, $4, $3, $2,
				     $apache_mmap{lc($1)}, $tm[5]-1); };
				}
			local $user = $11 || $9;
			if($config{'bw_mail_all'}){
				local $user = $11;
				local $id = $8;
			}
			local $sz = $sizes{$8};
			local $fd = $fromdoms{$8};
			$user =~ s/^<(.*)>/$1/;
			$user =~ s/,$//;
			local ($mb, $dom) = split(/\@/, $user);
			local $md = $maildoms{$dom};
			if ($md && $fd && !$config{'bw_nomailout'} && $config{'bw_mail_all'}) {
				# To a local domain - add the size to the 
				# sending domain's usage once for local deliveries
				if ($ltime > $max_ltime{$fd->{'id'}}) {
					# Update most recent seen time for
					# this domain.
					$max_ltime{$fd->{'id'}} = $ltime;
					$max_updated{$fd->{'id'}} = 1;
					}
				if ($ltime > $starts->{$fd->{'id'}} && $sz && !$lc{$id}) {
					# New enough to record
					local $day =
					    int($ltime / (24*60*60));
					$bws->{$fd->{'id'}}->
						{"mail_".$day} += $sz;
					$lc{$id} += 1;
					} 
				}
			elsif ($md) {
				# To a local domain - add the size to that
				# receiving domain's usage for off-site domain
				if ($ltime > $max_ltime{$md->{'id'}}) {
					# Update most recent seen time for
					# this domain.
					$max_ltime{$md->{'id'}} = $ltime;
					$max_updated{$md->{'id'}} = 1;
					}
				if ($ltime > $starts->{$md->{'id'}} && $sz) {
					# New enough to record
					local $day =
					    int($ltime / (24*60*60));
					$bws->{$md->{'id'}}->
						{"mail_".$day} += $sz;
					}
				}
			elsif ($fd && !$config{'bw_nomailout'}) {
				# From a local domain, but to an off-site domain -
				# add the size to the sender's usage
				if ($ltime > $max_ltime{$fd->{'id'}}) {
					# Update most recent seen time for
					# this domain.
					$max_ltime{$fd->{'id'}} = $ltime;
					$max_updated{$fd->{'id'}} = 1;
					}
				if ($ltime > $starts->{$fd->{'id'}} && $sz) {
					# New enough to record
					local $day =
					    int($ltime / (24*60*60));
					$bws->{$fd->{'id'}}->
						{"mail_".$day} += $sz;
					}
				}
			}
		elsif ($config{'bw_mail_all'} && !/status=(deferred|bounced)/ && /^(\S+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\S+)\s+(\S+):\s+(\S+):\s+to=(\S+),(.+\s?=sent)?/) {
			# A To: line that has the off-site recipient
			local $ltime = timelocal($5, $4, $3, $2,
			    $apache_mmap{lc($1)}, $tm[5]);
			if ($ltime > $now+(24*60*60)) {
				# Must have been last year!
				$ltime = timelocal($5, $4, $3, $2,
				     $apache_mmap{lc($1)}, $tm[5]-1);
				}
			local $id = $8;
			local $sz = $sizes{$8};
			local $fd = $fromdoms{$8};
			if ($fd && !$config{'bw_nomailout'} && $config{'bw_mail_all'}) {
				# From a local domain, but to an off-site
				# domain - add the size to the sender's usage
				if ($ltime > $max_ltime{$fd->{'id'}}) {
					# Update most recent seen time for
					# this domain.
					$max_ltime{$fd->{'id'}} = $ltime;
					$max_updated{$fd->{'id'}} = 1;
					}
				if ($ltime > $starts->{$fd->{'id'}} && $sz) {
					# New enough to record
					local $day =
					    int($ltime / (24*60*60));
					$bws->{$fd->{'id'}}->
						{"mail_".$day} += $sz;
					}
				}
			}

		# Qmail format
		elsif (/^\@(\S+)\s+info\s+msg\s+(\S+):\s+bytes\s+(\d+)\s+from/ ||
		       /(\d+\.\d+)\s+info\s+msg\s+(\S+):\s+bytes\s+(\d+)\s+from/) {
			# From: line with size
			$sizes{$2} = $3;
			}
		elsif (/^\@(\S+)\s+starting\s+delivery\s+(\S+):\s+msg\s+(\S+)\s+to\s+local\s+(\S+)/ ||
		       /(\d+\.\d+)\s+starting\s+delivery\s+(\S+):\s+msg\s+(\S+)\s+to\s+local\s+(\S+)/) {
			# To: line with actual address
			local $sz = $sizes{$3};
			local $user = $4;
			local $ltime = &tai64_time($1);
			$user =~ s/^<(.*)>/$1/;
			local ($mb, $dom) = split(/\@/, $user);
			local $md = $maildoms{$dom};
			if ($md) {
				if ($ltime > $max_ltime{$md->{'id'}}) {
					# Update most recent seen time for
					# this domain.
					$max_ltime{$md->{'id'}} = $ltime;
					$max_updated{$md->{'id'}} = 1;
					}
				if ($ltime > $starts->{$md->{'id'}} && $sz) {
					# To a user in this domain
					local $day =
					    int($ltime / (24*60*60));
					$bws->{$md->{'id'}}->
						{"mail_".$day} += $sz;
					}
				}

			}

		# Dovecot byte counts
		elsif (/^(\S+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\S+)\s+(\S+):\s+(IMAP|POP3)\((\S+)\).*(bytes=(\d+)\/(\d+)|retr=(\d+)\/(\d+))/) {
			local $ltime;
			eval { $ltime = timelocal($5, $4, $3, $2,
			    $apache_mmap{lc($1)}, $tm[5]); };
			if (!$ltime || $ltime > $now+(24*60*60)) {
				# Must have been last year!
				eval { $ltime = timelocal($5, $4, $3, $2,
				     $apache_mmap{lc($1)}, $tm[5]-1); };
				}
			local $user = $9;
			local $sz = $11 + $12 || $14;
			local $md = $mailusers{$user};
			if ($md) {
				if ($ltime > $max_ltime{$md->{'id'}}) {
					# Update most recent seen time for
					# this domain.
					$max_ltime{$md->{'id'}} = $ltime;
					$max_updated{$md->{'id'}} = 1;
					}
				if ($ltime > $starts->{$md->{'id'}} && $sz) {
					# New enough to record
					local $day =
					    int($ltime / (24*60*60));
					$bws->{$md->{'id'}}->
						{"mail_".$day} += $sz;
					}
				}
			}
		}
	close(LOG);
	}

# For any domain for which max_ltime was not updated (because we didn't see
# any email), set it to the current time
foreach my $did (keys %max_ltime) {
	if (!$max_updated{$did}) {
		$max_ltime{$did} = $start_now;
		}
	}

return \%max_ltime;
}

sub tai64_time
{
if ($_[0] =~ /^40000000(\S{8})/) {
	return hex($1);
	}
elsif ($_[0] =~ /^(\d+)\.(\d+)$/) {
	return $1;
	}
return undef;
}

# can_users_without_mail(&domain)
# Returns 1 if some domain can have users without mail enabled. Not allowed
# when using VPOPMail and Qmail+LDAP
sub can_users_without_mail
{
return $config{'mail_system'} != 4 && $config{'mail_system'} != 5;
}

# sysinfo_mail()
# Returns the mail server version and path
sub sysinfo_mail
{
&require_mail();
if ($config{'mail_system'} == 0) {
	# Postfix
	local $prog = -x "/usr/lib/sendmail" ? "/usr/lib/sendmail" :
			&has_command("sendmail");
	if (!$postfix::postfix_version) {
		local $out = &backquote_command("$postfix::config{'postfix_config_command'} mail_version 2>&1", 1);
		$postfix_version = $1 if ($out =~ /mail_version\s*=\s*(.*)/);
		}
	return ( [ $text{'sysinfo_postfix'}, $postfix::postfix_version ],
		 [ $text{'sysinfo_mailprog'}, $prog." -t" ] );
	}
elsif ($config{'mail_system'} == 1) {
	# Sendmail
	local $ever = &sendmail::get_sendmail_version();
	return ( [ $text{'sysinfo_sendmail'}, $ever ],
		 [ $text{'sysinfo_mailprog'},
			$sendmail::config{'sendmail_path'}." -t" ] );
	}
elsif ($config{'mail_system'} == 2 || $config{'mail_system'} == 4 ||
       $config{'mail_system'} == 5) {
	# Some Qmail variant
	return ( [ $text{'sysinfo_qmail'}, "Unknown" ],
		 [ $text{'sysinfo_mailprog'},
			"$qmailadmin::config{'qmail_dir'}/bin/qmail-inject" ] );
	}
elsif ($config{'mail_system'} == 6) {
	return ( [ $text{'sysinfo_exim'}, "Unknown" ],
		 [ $text{'sysinfo_mailprog'}, $prog." -t" ] );
	}
else {
	return ( );
	}
}

# mail_system_has_procmail()
# Returns 1 if the current mail system is configured to use procmail
sub mail_system_has_procmail
{
&require_mail();
if ($config{'mail_system'} == 0) {
	# Check postfix delivery command
	local $cmd = &postfix::get_real_value("mailbox_command");
	return $cmd =~ /procmail/;
	}
elsif ($config{'mail_system'} == 1) {
	# See if sendmail's local mailer is procmail
	local $conf = &sendmail::get_sendmailcf();
	foreach my $m (&sendmail::find_type("M", $conf)) {
		if ($m->{'value'} =~ /^local.*procmail/) {
			return 1;
			}
		}
	return 0;
	}
elsif ($config{'mail_system'} == 2 || $config{'mail_system'} == 4) {
	# Check Qmail rc script for use of procmail as default delivery
	local $got;
	local $_;
	open(RC, "$qmailadmin::config{'qmail_dir'}/rc");
	while(<RC>) {
		s/#.*$//;
		$got = 1 if (/procmail/);
		}
	close(RC);
	return $got;
	}
elsif ($config{'mail_system'} == 5) {
	# I don't think vpopmail supports procmail
	return 0;
	}
return 0;
}

# get_mail_log()
# Returns the default mail log file for this system
sub get_mail_log
{
if (&foreign_installed("syslog")) {
	# Try syslog first
	&foreign_require("syslog", "syslog-lib.pl");
	local $conf = &syslog::get_config();
	foreach my $c (@$conf) {
		next if (!$c->{'active'});
		next if (!$c->{'file'});
		next if ($c->{'file'} =~ /^\/dev\//);
		foreach my $s (@{$c->{'sel'}}) {
			local ($fac,$level) = split(/\./, $s);
			return $c->{'file'} if ($fac =~ /mail/ &&
						$level ne "none");
			}
		}
	}
elsif (&foreign_installed("syslog-ng")) {
	# Try syslog-ng (by looking for a d_mail destination, or any dest
	# with mail in the name)
	&foreign_require("syslog-ng", "syslog-ng-lib.pl");
	local $conf = &syslog_ng::get_config();
	local @dests = &syslog_ng::find("destination", $conf);
	local ($dest) = grep { $_->{'name'} eq 'd_mail' } @dests;
	if (!$dest) {
		($dest) = grep { $_->{'name'} =~ /mail/ } @dests;
		}
	if ($dest) {
		return &find_value("file", $dest->{'members'});
		}
	}
# Fall back to common files
foreach my $f ("/var/log/mail", "/var/log/maillog", "/var/log/mail.log") {
	return $f if (-r $f);
	}
return undef;
}

sub startstop_mail
{
local ($typestatus) = @_;
local $msn = $config{'mail_system'} == 0 ? "postfix" :
	     $config{'mail_system'} == 6 ? "exim" :
	     $config{'mail_system'} == 1 ? "sendmail" : "qmailadmin";
local $ms = $text{'mail_system_'.$config{'mail_system'}};
local @rv;
local @links;
push(@links, { 'link' => "/$msn/",
	       'desc' => $text{'index_mmanage'},
	       'manage' => 1 });
if (&can_show_history() &&
    &indexof("mailcount", &list_historic_stats()) >= 0) {
	foreach my $s ("mailcount", "spamcount", "viruscount") {
		push(@links, { 'stat' => $s });
		}
	}
if (defined($typestatus->{$msn}) ? $typestatus->{$msn} == 1
				 : &is_mail_running()) {
	push(@rv,{ 'status' => 1,
		   'name' => &text('index_mname', $ms),
		   'desc' => $text{'index_mstop'},
		   'restartdesc' => $text{'index_mrestart'},
		   'longdesc' => $text{'index_mstopdesc'},
		   'links' => \@links } );
	}
else {
	push(@rv,{ 'status' => 0,
		   'name' => &text('index_mname', $ms),
		   'desc' => $text{'index_mstart'},
		   'longdesc' => $text{'index_mstartdesc'},
		   'links' => \@links } );
	}
if (&foreign_installed("dovecot")) {
	# Add status for Dovecot
	&foreign_require("dovecot", "dovecot-lib.pl");
	local @dlinks;
	push(@dlinks, { 'link' => "/dovecot/",
		        'desc' => $text{'index_dmanage'},
		        'manage' => 1 });
	if (&dovecot::is_dovecot_running()) {
		push(@rv,{ 'status' => 1,
			   'feature' => 'dovecot',
			   'name' => &text('index_dname', $ms),
			   'desc' => $text{'index_dstop'},
			   'restartdesc' => $text{'index_drestart'},
			   'longdesc' => $text{'index_dstopdesc'},
			   'links' => \@dlinks } );
		}
	else {
		push(@rv,{ 'status' => 0,
			   'feature' => 'dovecot',
			   'name' => &text('index_dname', $ms),
			   'desc' => $text{'index_dstart'},
			   'longdesc' => $text{'index_dstartdesc'},
			   'links' => \@dlinks } );
		}
	}
return @rv;
}

sub start_service_mail
{
return &startup_mail_server(1);
}

sub stop_service_mail
{
return &shutdown_mail_server(1);
}

sub start_service_dovecot
{
&foreign_require("dovecot", "dovecot-lib.pl");
return &dovecot::start_dovecot();
}

sub stop_service_dovecot
{
&foreign_require("dovecot", "dovecot-lib.pl");
return &dovecot::stop_dovecot();
}

# check_secondary_mx()
# Returns undef if this system can be a secondary MX, or an error message if not
sub check_secondary_mx
{
local $ms = $config{'mail_system'};
if (!$config{'mail'}) {
	return $text{'newmxs_email'};
	}
elsif ($ms == 3) {
	return $text{'newmxs_emailsystem'};
	}
elsif ($ms == 1 && !&sendmail_installed() ||
       $ms == 0 && !&postfix_installed() ||
       $ms == 2 && !&qmail_installed() ||
       $ms == 4 && !&qmail_ldap_installed() ||
       $ms == 5 && !&qmail_vpopmail_installed()) {
	return &text('newmxs_esystem', $text{'mail_system_'.$ms});
	}
else {
	return undef;
	}
}

# setup_secondary_mx(domain)
# Set up this system as a secondary MX for the given domain. Returns undef on
# success, or an error message on failure.
sub setup_secondary_mx
{
local ($dom) = @_;
&obtain_lock_mail($_[0]);
&require_mail();
if ($config{'mail_system'} == 1) {
	# Just add to sendmail relay domains file
	local $conf = &sendmail::get_sendmailcf();
	local $cwfile;
	local @dlist = &sendmail::get_file_or_config($conf, "R", undef,
						     \$cwfile);
	if (&indexoflc($dom, @dlist) >= 0) {
		return $text{'newmxs_already'};
		}
	&lock_file($cwfile) if ($cwfile);
	&lock_file($sendmail::config{'sendmail_cf'});
	&sendmail::add_file_or_config($conf, "R", $dom);
	&flush_file_lines();
	&unlock_file($sendmail::config{'sendmail_cf'});
	&unlock_file($cwfile) if ($cwfile);
	&sendmail::restart_sendmail();
	}
elsif ($config{'mail_system'} == 0) {
	# Add to Postfix relay domains
	local @rd = split(/[, ]+/,
			&postfix::get_current_value("relay_domains"));
	if ($rd[0] =~ /:/) {
		# Actually in a map
		local $rmaps = &postfix::get_maps("relay_domains");
		@rds = map { $_->{'name'} } @$rmaps;
		}
	if (&indexoflc($dom, @rd) >= 0) {
		return $text{'newmxs_already'};
		}
	if ($rd[0] =~ /:/) {
		# Add to the map
		&create_replace_mapping("relay_domains",
					{ 'name' => $dom, 'value' => $dom });
		&postfix::regenerate_any_table("relay_domains");
		}
	else {
		# Add to main.cf
		@rd = &unique(@rd, $dom);
		&lock_file($postfix::config{'postfix_config_file'});
		&postfix::set_current_value("relay_domains", join(", ", @rd));
		&unlock_file($postfix::config{'postfix_config_file'});
		}
	}
elsif ($config{'mail_system'} == 2 || $config{'mail_system'} == 4 ||
       $config{'mail_system'} == 5) {
	# Add to Qmail rcpthosts file
	local $rlist = &qmailadmin::list_control_file("rcpthosts");
	if (&indexof(lc($dom), (map { lc($_) } @$rlist)) >= 0) {
		return $text{'newmxs_already'};
		}
	push(@$rlist, $dom);
	&qmailadmin::save_control_file("rcpthosts", $rlist);
	}
return undef;
}

# delete_secondary_mx(domain)
# Removes the given domain from the secondary MX list for this server. Returns
# an error message or undef.
sub delete_secondary_mx
{
local ($dom) = @_;
&obtain_lock_mail($_[0]);
&require_mail();
if ($config{'mail_system'} == 1) {
	# Just remove from sendmail relay domains file
	local $conf = &sendmail::get_sendmailcf();
	local $cwfile;
	local @dlist = &sendmail::get_file_or_config($conf, "R", undef,
						     \$cwfile);
	local $idx = &indexof(lc($dom), (map { lc($_) } @dlist));
	if ($idx < 0) {
		return $text{'newmxs_missing'};
		}
	&lock_file($cwfile) if ($cwfile);
	&lock_file($sendmail::config{'sendmail_cf'});
	&sendmail::delete_file_or_config($conf, "R", $dom);
	&flush_file_lines();
	&unlock_file($sendmail::config{'sendmail_cf'});
	&unlock_file($cwfile) if ($cwfile);
	&sendmail::restart_sendmail();
	}
elsif ($config{'mail_system'} == 0) {
	# Add to Postfix relay domains
	local @rd = split(/[, ]+/,
			&postfix::get_current_value("relay_domains"));
	local $idx = &indexoflc($dom, @rd);
	if ($rd[0] =~ /:/ && $idx < 0) {
		# Actually in a map
		local $rmaps = &postfix::get_maps("relay_domains");
		local ($m) = grep { $_->{'name'} eq $dom } @$rmaps;
		if ($m) {
			&postfix::delete_mapping("relay_domains", $m);
			&postfix::regenerate_any_table("relay_domains");
			}
		else {
			return $text{'newmxs_missing'};
			}
		}
	else {
		# Remove from main.cf
		if ($idx < 0) {
			return $text{'newmxs_missing'};
			}
		splice(@rd, $idx, 1);
		&lock_file($postfix::config{'postfix_config_file'});
		&postfix::set_current_value("relay_domains", join(", ", @rd));
		&unlock_file($postfix::config{'postfix_config_file'});
		}
	}
elsif ($config{'mail_system'} == 2 || $config{'mail_system'} == 4 ||
       $config{'mail_system'} == 5) {
	# Add to Qmail rcpthosts file
	local $rlist = &qmailadmin::list_control_file("rcpthosts");
	local $idx = &indexof(lc($dom), (map { lc($_) } @$rlist));
	if ($idx < 0) {
		return $text{'newmxs_missing'};
		}
	splice(@$rlist, $idx, 1);
	&qmailadmin::save_control_file("rcpthosts", $rlist);
	}
return undef;
}

# is_secondary_mx(domain)
# Returns 1 if this server is a secondary MX for the given domain
sub is_secondary_mx
{
local ($dom) = @_;
&require_mail();
if ($config{'mail_system'} == 1) {
	# Check sendmail relay domains file
	local $conf = &sendmail::get_sendmailcf();
	local $cwfile;
	local @dlist = &sendmail::get_file_or_config($conf, "R", undef,
						     \$cwfile);
	local $idx = &indexof(lc($dom), (map { lc($_) } @dlist));
	return $idx < 0 ? 0 : 1;
	}
elsif ($config{'mail_system'} == 0) {
	# Add to Postfix relay domains
	local @rd = split(/[, ]+/,&postfix::get_current_value("relay_domains"));
	local $idx = &indexof(lc($dom), (map { lc($_) } @rd));
	return $idx < 0 ? 0 : 1;
	}
elsif ($config{'mail_system'} == 2 || $config{'mail_system'} == 4 ||
       $config{'mail_system'} == 5) {
	# Add to Qmail rcpthosts file
	local $rlist = &qmailadmin::list_control_file("rcpthosts");
	local $idx = &indexof(lc($dom), (map { lc($_) } @$rlist));
	return $idx < 0 ? 0 : 1;
	}
return 0;
}

sub secondary_error_handler
{
$secondary_error = join("", @_);
}

# setup_on_secondaries(&dom)
# Add this domain to all secondary MX servers
sub setup_on_secondaries
{
local ($d) = @_;
local @servers = &list_mx_servers();
return if (!@servers);
local @okservers;
&$first_print(&text('setup_mxs',
	join(", ", map { "<tt>".($_->{'mxname'} || $_->{'host'})."</tt>" }
		       @servers)));
local @errs;
foreach my $s (@servers) {
	local $err = &setup_one_secondary($d, $s);
	if ($err) {
		push(@errs, "$s->{'host'} : $err");
		}
	else {
		push(@okservers, $s);
		}
	}
$d->{'mx_servers'} = join(" ", map { $_->{'id'} } @okservers);
if ($d->{'dns'}) {
	# Add DNS MX records. This is needed because sometimes the mail setup
	# happens after DNS, and so mx_servers hasn't been populated.
	my ($recs, $file) = &get_domain_dns_records_and_file($d);
	my $withdot = $_[0]->{'dom'}.".";
	my $added = 0;
	foreach my $s (@okservers) {
		my $mxhost = $s->{'mxname'} || $s->{'host'};
		my ($r) = grep { $_->{'type'} eq 'MX' &&
				 $r->{'name'} eq $withdot &&
				 $r->{'values'}->[1] eq $mxhost."." } @$recs;
		if (!$r) {
			&bind8::create_record($file, $withdot, undef,
				      "IN", "MX", "10 $mxhost.");
			$added++;
			}
		}
	&register_post_action(\&restart_bind, $d) if ($added);
	}
if (@errs) {
	&$second_print($text{'setup_mxserrs'}."<br>\n".
			join("<br>\n", @errs));
	}
else {
	&$second_print($text{'setup_done'});
	}
}

# setup_one_secondary(&domain, &server)
# Add a secondary mail domain on one Webmin server. Returns undef on success or
# an error message on failure.
sub setup_one_secondary
{
local ($dom, $s) = @_;
&remote_error_setup(\&secondary_error_handler);
$secondary_error = undef;
&remote_foreign_require($s, "virtual-server", "virtual-server-lib.pl");
if ($secondary_error) {
	&remote_error_setup(undef);
	return $secondary_error;
	}
local $err = &remote_foreign_call($s, "virtual-server",
				  "setup_secondary_mx", $dom->{'dom'});
&remote_error_setup(undef);
return $err;
}

# delete_on_secondaries(&dom)
# Remove this domain from all secondary MX servers
sub delete_on_secondaries
{
local ($dom) = @_;
local %ids = map { $_, 1 } split(/\s+/, $dom->{'mx_servers'});
local @servers = grep { $ids{$_->{'id'}} } &list_mx_servers();
return if (!@servers);
&$first_print(&text('delete_mxs',
	join(", ", map { "<tt>".($_->{'mxname'} || $_->{'host'})."</tt>" }
		       @servers)));
local @errs;
foreach my $s (@servers) {
	local $err = &delete_one_secondary($dom, $s);
	if ($err) {
		push(@errs, "$s->{'host'} : $err");
		}
	}
if (@errs) {
	&$second_print($text{'setup_mxserrs'}."<br>\n".
			join("<br>\n", @errs));
	}
else {
	&$second_print($text{'setup_done'});
	}
delete($dom->{'mx_servers'});
}

# delete_one_secondary(&domain, &server)
# Remove a secondary mail domain on one Webmin server. Returns undef on success
# or an error message on failure.
sub delete_one_secondary
{
local ($dom, $s) = @_;
&remote_error_setup(\&secondary_error_handler);
$secondary_error = undef;
&remote_foreign_require($s, "virtual-server", "virtual-server-lib.pl");
if ($secondary_error) {
	&remote_error_setup(undef);
	return $secondary_error;
	}
local $err = &remote_foreign_call($s, "virtual-server",
				  "delete_secondary_mx", $dom->{'dom'});
&remote_error_setup(undef);
return $err;
}

# is_one_secondary(&domain, &server)
# Checks if some secondary MX server is relaying a domain. Returns '1' if OK,
# '0' if not, or an error message
sub is_one_secondary
{
local ($dom, $s) = @_;
&remote_error_setup(\&secondary_error_handler);
$secondary_error = undef;
&remote_foreign_require($s, "virtual-server", "virtual-server-lib.pl");
if ($secondary_error) {
	&remote_error_setup(undef);
	return $secondary_error;
	}
local $ok = &remote_foreign_call($s, "virtual-server",
				 "is_secondary_mx", $dom->{'dom'});
&remote_error_setup(undef);
return $secondary_error ? $secondary_error : $ok ? 1 : 0;
}

# execute_after_virtuser(&alias, action)
# Runs any command configured to be run after an alias is changed
sub execute_after_virtuser
{
local ($alias, $action) = @_;
return if (!$config{'alias_post_command'});
local %OLDENV = %ENV;
$ENV{'ALIAS_ACTION'} = $action;
$ENV{'ALIAS_FROM'} = $alias->{'from'};
$ENV{'ALIAS_TO'} = join(",", @{$alias->{'to'}});
$ENV{'ALIAS_CMT'} = $alias->{'cmt'};
&system_logged("($config{'alias_post_command'}) 2>&1 </dev/null");
}

# execute_before_virtuser(&alias, action)
# Runs any command configured to be run before an alias is changed
sub execute_before_virtuser
{
local ($alias, $action) = @_;
return if (!$config{'alias_pre_command'});
local %OLDENV = %ENV;
$ENV{'ALIAS_ACTION'} = $action;
$ENV{'ALIAS_FROM'} = $alias->{'from'};
$ENV{'ALIAS_TO'} = join(",", @{$alias->{'to'}});
$ENV{'ALIAS_CMT'} = $alias->{'cmt'};
local $out =&backquote_logged("($config{'alias_pre_command'}) 2>&1 </dev/null");
if ($?) {
	&error(&text('alias_ebefore', "<tt>$out</tt>"));
	}
}

# show_template_mail(&tmpl)
# Outputs HTML for editing email and mailbox related template options
sub show_template_mail
{
local ($tmpl) = @_;

# Email message for server creation
print &ui_table_row(&hlink($text{'tmpl_mail'}, "template_mail"),
	&none_def_input("mail", $tmpl->{'mail_on'}, $text{'tmpl_mailbelow'},
			0, 0, undef, [ "mail", "subject", "cc", "bcc" ]).
	"<br>\n".
	&ui_textarea("mail", $tmpl->{'mail'} eq "none" ? "" :
				join("\n", split(/\t/, $tmpl->{'mail'})),
		     10, 60)."\n".
	&email_template_input(undef, $tmpl->{'mail_subject'},
			      $tmpl->{'mail_cc'}, $tmpl->{'mail_bcc'})
	);

print &ui_table_hr();

# Aliases for new users
local @aliases = $tmpl->{'user_aliases'} eq "none" ? ( ) :
		split(/\t+/, $tmpl->{'user_aliases'});
local @afields = map { ("type_".$_, "val_".$_) } (0..scalar(@aliases)+2);
print &ui_table_row(&hlink($text{'tmpl_aliases'}, "template_aliases_mode"),
	&none_def_input("aliases", $tmpl->{'user_aliases'},
			$text{'tmpl_aliasbelow'}, 0, 0, undef,
			\@afields)."<br>");
&alias_form(\@aliases, " ", undef, "user", "NEWUSER");

# Aliases for new domains
local @aliases = $tmpl->{'dom_aliases'} eq "none" ? ( ) :
			split(/\t+/, $tmpl->{'dom_aliases'});
local @atable;
local $i = 0;
local @dafields;
foreach my $a (@aliases, undef, undef) {
	local ($from, $to) = split(/=/, $a, 2);
	push(@atable, [ &ui_textbox("alias_from_$i", $from, 20),
			&ui_textbox("alias_to_$i", $to, 40) ]);
	push(@dafields, "alias_from_$i", "alias_to_$i");
	$i++;
	}
local $atable = &ui_columns_table(
	[ $text{'tmpl_aliasfrom'}, $text{'tmpl_aliasto'} ],
	undef,
	\@atable,
	undef,
	1);
if ($config{'mail_system'} != 0) {
	# Bounce-all alias, not shown for Postfix
	$atable .= &ui_checkbox("bouncealias", 1,
				&hlink("<b>$text{'tmpl_bouncealias'}</b>",
				       "template_bouncealias"),
				$tmpl->{'dom_aliases_bounce'});
	push(@dafields, "bouncealias");
	}
print &ui_table_row(&hlink($text{'tmpl_domaliases'},
                           "template_domaliases_mode"),
		    &none_def_input("domaliases", $tmpl->{'dom_aliases'},
				    $text{'tmpl_aliasbelow'}, 0, 0, undef,
				    \@dafields)."\n".$atable);

# Virtusers mode for alias domains
if ($supports_aliascopy) {
	print &ui_table_row(
		&hlink($text{'tmpl_aliascopy'}, "template_aliascopy"),
		&ui_radio("aliascopy", $tmpl->{'aliascopy'},
			  [ $tmpl->{'default'} ? ( )
					       : ( [ "", $text{'default'} ] ),
			    [ 1, $text{'tmpl_aliascopy1'} ],
			    [ 0, $text{'tmpl_aliascopy0'} ] ]));
	}

# BCC address
if ($supports_bcc) {
	local $mode = $tmpl->{'bccto'} eq 'none' ? 0 :
		      $tmpl->{'bccto'} eq '' ? 1 : 2;
	print &ui_table_row(
                &hlink($text{'tmpl_bccto'}, "template_bccto"),
		&ui_radio("bccto_def", $mode,
		  [ $tmpl->{'default'} ? ( )
				       : ( [ 1, $text{'default'}."<br>" ] ),
		    [ 0, $text{'mail_bcc1'}."<br>" ],
		    [ 2, &text('mail_bcc0',
		     	       &ui_textbox("bccto",
				    $mode == 2 ? $tmpl->{'bccto'} : "", 50)) ]
		  ]));
	}

print &ui_table_hr();

# Default mailbox quota
print &ui_table_row(&hlink($text{'tmpl_defmquota'}, "template_defmquota"),
    &none_def_input("defmquota", $tmpl->{'defmquota'}, $text{'tmpl_quotasel'},
		    0, 0, $text{'form_unlimit'},
		    [ "defmquota", "defmquota_units" ])."\n".
    &quota_input("defmquota", $tmpl->{'defmquota'} eq "none" ?
				"" : $tmpl->{'defmquota'}, "home"));

# Unix groups for mail, FTP and DB users
foreach $g ("mailgroup", "ftpgroup", "dbgroup") {
	print &ui_table_row(&hlink($text{'tmpl_'.$g}, "template_".$g),
		    &none_def_input($g, $tmpl->{$g},
			    $text{'tmpl_setgroup'}, 0, 0, undef, [ $g ]).
		    &ui_textbox($g, $tmpl->{$g} eq 'none' ? undef :
					      $tmpl->{$g}, 15));
	}

# Other groups to which users can be assigned
print &ui_table_row(&hlink($text{'tmpl_othergroups'}, "template_othergroups"),
	    &none_def_input("othergroups", $tmpl->{'othergroups'},
		    $text{'tmpl_setgroups'}, 0, 0, undef, [ "othergroups" ]).
	    &ui_textbox("othergroups", $tmpl->{"othergroups"} eq 'none' ?
				undef : $tmpl->{'othergroups'}, 40));

# Prefix/suffix mode
print &ui_table_row(&hlink($text{'tmpl_append'}, "template_append"),
	    &none_def_input("append", $tmpl->{'append_style'}, undef, 1)."\n".
	    &ui_select("append", $tmpl->{'append_style'},
		       [ [ 0, "username.domain" ],
			 [ 2, "domain.username" ],
			 [ 1, "username-domain" ],
			 [ 3, "domain-username" ],
			 [ 4, "username_domain" ],
			 [ 5, "domain_username" ],
			 [ 6, "username\@domain" ],
			 [ 7, "username\%domain" ] ]));
}

# parse_template_mail(&tmpl)
# Updates email and mailbox related template options from %in
sub parse_template_mail
{
local ($tmpl) = @_;
&require_mail();

# Save mail settings
$tmpl->{'mail_on'} = $in{'mail_mode'} == 0 ? "none" :
		     $in{'mail_mode'} == 1 ? "" : "yes";
if ($tmpl->{'mail_on'} eq 'yes') {
	$in{'mail'} =~ s/\r//g;
	$tmpl->{'mail'} = $in{'mail'};
	}
$tmpl->{'mail_subject'} = $in{'subject'};
$tmpl->{'mail_cc'} = $in{'cc'};
$tmpl->{'mail_bcc'} = $in{'bcc'};

# Save new user aliases
if ($in{'aliases_mode'} == 0) {
	$tmpl->{'user_aliases'} = "none";
	}
elsif ($in{'aliases_mode'} == 1) {
	$tmpl->{'user_aliases'} = "";
	}
else {
	@aliases = &parse_alias(0, "NEWUSER");
	$tmpl->{'user_aliases'} = join("\t", @aliases);
	}

# Save new domain aliases
if ($in{'domaliases_mode'} == 0) {
	$tmpl->{'dom_aliases'} = "none";
	}
elsif ($in{'domaliases_mode'} == 1) {
	$tmpl->{'dom_aliases'} = undef;
	}
else {
	@aliases = ( );
	for($i=0; defined($from = $in{"alias_from_$i"}); $i++) {
		$to = $in{"alias_to_$i"};
		next if (!$from);
		$from =~ /^\S+$/ ||
			&error(&text('tmpl_ealiasfrom', $i+1));
		$to =~ /\S/ || &error(&text('tmpl_ealiasto', $i+1));
		if ($from eq "*" && $in{'bouncealias'}) {
			&error(&text('tmpl_ealiasfrombounce', $i+1));
			}
		push(@aliases, "$from=$to");
		}
	@aliases || &error(&text('tmpl_ealiases'));
	$tmpl->{'dom_aliases'} = join("\t", @aliases);
	}
if ($in{'domaliases_mode'} != 1 && $config{'mail_system'} != 0) {
	$tmpl->{'dom_aliases_bounce'} = $in{'bouncealias'};
	}
if ($supports_aliascopy) {
	$tmpl->{'aliascopy'} = $in{'aliascopy'};
	}
if ($supports_bcc) {
	if ($in{'bccto_def'} == 0) {
		$tmpl->{'bccto'} = 'none';	# Nowhere
		}
	elsif ($in{'bccto_def'} == 1) {
		$tmpl->{'bccto'} = '';		# Default
		}
	else {
		# Explicit email address
		$in{'bccto'} =~ /^\S+\@\S+$/ || &error($text{'tmpl_ebccto'});
		$tmpl->{'bccto'} = $in{'bccto'};
		}
	}

# Save default quota
$tmpl->{'defmquota'} = &parse_none_def("defmquota");
if ($in{"defmquota_mode"} == 2) {
	$in{'defmquota'} =~ /^[0-9\.]+$/ || &error($text{'tmpl_edefmquota'});
	$tmpl->{'defmquota'} = &quota_parse("defmquota", "home");
	}

# Save secondary groups
foreach $g ("mailgroup", "ftpgroup", "dbgroup") {
	if ($in{$g.'_mode'} == 2) {
		$in{$g} =~ /^\S+$/ || &error($text{'tmpl_e'.$g});
		}
	$tmpl->{$g} = &parse_none_def($g);
	}
if ($in{'othergroups_mode'} == 2) {
	foreach my $g (split(/\s+/, $in{'othergroups'})) {
		defined(getgrnam($g)) || &error(&text('tmpl_eothergroup', $g));
		}
	}
$tmpl->{'othergroups'} = &parse_none_def('othergroups');
$tmpl->{'append_style'} = &parse_none_def('append');
if ($in{'append_mode'} == 2 && $in{'append'} == 6 &&
    $config{'mail_system'} == 2) {
	# user@domain style is not allowed for Qmail
	&error($text{'tmpl_eappend'});
	}

}

# postsave_template_mail(&template)
# Called after a template is saved
sub postsave_template_mail
{
local ($tmpl) = @_;

if (!$in{'new'}) {
	# Update the secondary group lists for all domains in this template
	local @secdons;
	if ($tmpl->{'id'} == 0) {
		@secdoms = &list_domains();
		}
	else {
		@secdoms = &get_domain_by("template", $tmpl->{'id'});
		}
	foreach my $sd (@secdoms) {
		&update_secondary_groups($sd);
		}
	}
}

# get_generics_hash()
# Returns a hash of all username to outgoing address mappings
sub get_generics_hash
{
&require_mail();
if ($config{'mail_system'} == 1) {
	return map { $_->{'from'}, $_ }
		   &sendmail::list_generics($sendmail_gfile);
	}
elsif ($config{'mail_system'} == 0) {
	local $cans = &postfix::get_maps($canonical_type);
	return map { $_->{'name'}, $_ } @$cans;
	}
else {
	return ( );
	}
}

# create_generic(user, email, [no-restart])
# Adds an entry to the systems outgoing addresses file, if active
sub create_generic
{
local ($user, $email, $norestart) = @_;
if ($config{'mail_system'} == 1) {
	# Add to Sendmail generics file
	local $gen = { 'from' => $user, 'to' => $email };
	&sendmail::create_generic($gen, $sendmail_gfile,
				  $sendmail_gdbm, $sendmail_gdbmtype);

	# And generics domain list, if missing and if using a file
	local $conf = &sendmail::get_sendmailcf();
	local $cgfile;
	local @dlist = &sendmail::get_file_or_config($conf, "G", undef,
                                                     \$cgfile);
	local ($mb, $dname) = split(/\@/, $email);
	if (&indexof($dname, @dlist) < 0 && $cgfile) {
		&lock_file($cgfile);
		&lock_file($sendmail::config{'sendmail_cf'});
		&sendmail::add_file_or_config($conf, "G", $dname);
		&flush_file_lines();
		&unlock_file($sendmail::config{'sendmail_cf'});
		&unlock_file($cgfile);
		&sendmail::restart_sendmail() if (!$norestart);
		}
	}
elsif ($config{'mail_system'} == 0) {
	# Add to Postfix generics map
	local $gen = { 'name' => $user,
		       'value' => $email };
	&create_replace_mapping($canonical_type, $gen);
	&postfix::regenerate_canonical_table();
	}
}

# delete_generic(&generic)
# Removes one outgoing addresses table entry
sub delete_generic
{
local ($generic) = @_;
return if ($generic->{'deleted'});
if ($config{'mail_system'} == 1) {
	# From Sendmail generics file
	&sendmail::delete_generic($generic, $sendmail_gfile,
			$sendmail_gdbm, $sendmail_gdbmtype);
	}
elsif ($config{'mail_system'} == 0) {
	# From Postfix generics map
	&postfix::delete_mapping($canonical_type, $generic);
	&postfix::regenerate_canonical_table();
	}
$generic->{'deleted'} = 1;
}

# modify_generic(&generic, &old-generic)
# Updates one outgoing addresses table entry
sub modify_generic
{
local ($generic, $oldgeneric) = @_;
if ($config{'mail_system'} == 1) {
	# In Sendmail generics file
	&sendmail::modify_generic($oldgeneric, $generic, $sendmail_gfile,
			$sendmail_gdbm, $sendmail_gdbmtype);
	}
elsif ($config{'mail_system'} == 0) {
	# In Postfix generics map
	&postfix::modify_mapping($canonical_type, $oldgeneric, $generic);
	}
}

# create_domain_forward(&dom, fwdto)
# Adds or updates a virtuser to forward all email sent to this domain
sub create_domain_forward
{
local ($d, $fwdto) = @_;
local $virt = { 'from' => "\@$d->{'dom'}",
		'to' => [ $fwdto ] };
local ($clash) = grep { $_->{'from'} eq $virt->{'from'} } &list_virtusers();
&delete_virtuser($clash) if ($clash);
&create_virtuser($virt);
if ($d->{'unix'}) {
	# Also forward domain owner's mail
	local @users = &list_domain_users($d);
	local ($uinfo) = grep { $_->{'user'} eq $d->{'user'}} @users;
	if ($uinfo) {
		local %old = %$uinfo;
		$uinfo->{'to'} = [ $fwdto ];
		&modify_user($uinfo, \%old, $d);
		}
	}
&sync_alias_virtuals($d);
}

# get_mail_virtusertable()
# Returns the path to a file mapping email addresses to usernames, suitable
# for the mail server in use.
sub get_mail_virtusertable
{
&require_mail();
return $config{'mail_system'} == 1 ? $sendmail_vfile :
       $config{'mail_system'} == 0 ? $virtual_map_files[0] : undef;
}

# get_mail_genericstable()
# Returns the path to a file mapping usernames to email addresses, suitable
# for the mail server in use, if one exists.
sub get_mail_genericstable
{
&require_mail();
return $config{'mail_system'} == 1 ? $sendmail_gfile :
       $config{'mail_system'} == 0 ? $canonical_map_files[0] : undef;
}

# count_domain_aliases([ignore-plugins]
# Return a hash ref from domain ID to a count of aliases.
sub count_domain_aliases
{
local ($ignore) = @_;
local %rv;

# Find local users, so we can skip aliases from user@domain -> user.domain
local %users;
foreach my $u (&list_all_users_quotas(1)) {
	$users{$u->{'user'}} = 1;
	}

local %ignore;
if ($ignore) {
	# Get a list to ignore from each plugin
	foreach my $f (&list_feature_plugins()) {
		foreach my $i (&plugin_call($f, "virtusers_ignore", undef)) {
			$ignore{lc($i)} = 1;
			}
		}
	}

# Map each virtuser to a domain, except for those owned by plugins or for
# which the destination is a user
local %dmap = map { $_->{'dom'}, $_ } &list_domains();
foreach my $v (&list_virtusers()) {
	if (!$ignore{$v->{'from'}} && $v->{'from'} =~ /\@(\S+)$/) {
		local $d = $dmap{$1};
		if ($d) {
			if (@{$v->{'to'}} == 1 && $users{$v->{'to'}->[0]}) {
				# Points to a user .. skip only if the 
				# email addresss is for that user
				local $user = &remove_userdom(
						$v->{'to'}->[0], $d);
				if ($v->{'from'} eq $user."\@".$d->{'dom'}) {
					next;
					}
				}
			$rv{$d->{'id'}}++;
			}
		}
	}

return \%rv;
}

# copy_alias_virtuals(&dom, &sourcedom)
# Copy all virtual/virtuser entries from some source domain into the alias
sub copy_alias_virtuals
{
local ($d, $aliasdom) = @_;
local (%need, %already);
&obtain_lock_mail($d);
if ($config{'mail_system'} == 1) {
	# Find existing Sendmail virtusers in the alias domain
	foreach my $virt (&sendmail::list_virtusers($sendmail_vfile)) {
		local ($mb, $dname) = split(/\@/, $virt->{'from'});
		if ($dname eq $d->{'dom'}) {
			$already{$mb} = $virt;
			}
		elsif ($dname eq $aliasdom->{'dom'}) {
			$need{$mb} = { 'from' => $mb."\@".$d->{'dom'},
				       'to' => $virt->{'to'} };
			}
		}
	# Add those that are missing, update existing
	local @sargs = ( $sendmail_vfile, $sendmail_vdbm, $sendmail_vdbmtype );
	foreach my $mb (keys %need) {
		local $virt = $already{$mb};
		if ($virt) {
			if ($virt->{'to'} ne $need{$mb}->{'to'}) {
				&sendmail::modify_virtuser($virt, $need{$mb},
							   @sargs);
				}
			}
		else {
			&sendmail::create_virtuser($need{$mb}, @sargs);
			}
		delete($already{$mb});
		}
	# Delete any leftovers
	foreach my $virt (values %already) {
		&sendmail::delete_virtuser($virt, @sargs);
		}
	}
elsif ($config{'mail_system'} == 0) {
	# Find existing Postfix virtuals in the alias domain
	local $alreadyvirts = &postfix::get_maps($virtual_type);
	foreach my $virt (@$alreadyvirts) {
		local ($mb, $dname) = split(/\@/, $virt->{'name'});
		if ($dname eq $d->{'dom'}) {
			$already{$mb} = $virt;
			}
		elsif ($dname eq $aliasdom->{'dom'}) {
			$need{$mb} = { 'name' => $mb."\@".$d->{'dom'},
				       'value' => $virt->{'value'} };
			}
		}
	# Add those that are missing, update existing
	foreach my $mb (keys %need) {
		local $virt = $already{$mb};
		if ($virt) {
			if ($virt->{'value'} ne $need{$mb}->{'value'}) {
				&postfix::modify_mapping($virtual_type,
							 $virt, $need{$mb});
				}
			}
		else {
			&postfix::create_mapping($virtual_type, $need{$mb});
			}
		delete($already{$mb});
		}
	# Delete any leftovers
	foreach my $virt (values %already) {
		&postfix::delete_mapping($virtual_type, $virt);
		}
	&postfix::regenerate_virtual_table();
	}
&release_lock_mail($d);
}

# delete_alias_virtuals(&dom)
# Removes all virtusers for some domain, typically for conversion away from
# alias copy mode.
sub delete_alias_virtuals
{
local ($d) = @_;
&obtain_lock_mail($d);
if ($config{'mail_system'} == 1) {
	# Remove virtusers in Sendmail
	foreach my $virt (&sendmail::list_virtusers($sendmail_vfile)) {
		local ($mb, $dname) = split(/\@/, $virt->{'from'});
		if ($dname eq $d->{'dom'}) {
			&sendmail::delete_virtuser($virt,
			   $sendmail_vfile, $sendmail_vdbm, $sendmail_vdbmtype);
			}
		}
	}
elsif ($config{'mail_system'} == 0) {
	# Remove Postfix virtuals
	local $virts = &postfix::get_maps($virtual_type);
	local @origvirts = @$virts;	# Needed as $virts gets modified!
	foreach my $virt (@origvirts) {
		local ($mb, $dname) = split(/\@/, $virt->{'name'});
		if ($dname eq $d->{'dom'}) {
			&postfix::delete_mapping($virtual_type, $virt);
			}
		}
	&postfix::regenerate_virtual_table();
	}
&release_lock_mail($d);
}

# sync_alias_virtuals(&domain)
# This is called after making any changes to mail aliases, to update the
# copied virtusers in any alias domains that point to it.
sub sync_alias_virtuals
{
local ($d) = @_;
foreach my $ad (&get_domain_by("alias", $d->{'id'})) {
	if ($ad->{'aliascopy'}) {
		&copy_alias_virtuals($ad, $d);
		}
	}
}

# create_everyone_file(&domain)
# Create the file containing the email address of every user in a domain, for
# use in everyone include
sub create_everyone_file
{
local ($d) = @_;
if (!-d $everyone_alias_dir) {
	&make_dir($everyone_alias_dir, 0755);
	}
&open_tempfile(EVERYONE, ">$everyone_alias_dir/$d->{'id'}");
foreach my $u (&list_domain_users($d, 0, 0, 1, 1)) {
	if ($u->{'email'}) {
		&print_tempfile(EVERYONE, $u->{'email'},"\n");
		}
	}
&close_tempfile(EVERYONE);
}

# delete_everyone_file(&domain)
# Remove the file containing the email address of every user in a domain
sub delete_everyone_file
{
local ($d) = @_;
&unlink_file("$everyone_alias_dir/$d->{'id'}");
}

# get_domain_sender_bcc(&domain)
# If a domain has automatic BCCing enabled, return the address to which mail
# is sent. Otherwise, return undef.
sub get_domain_sender_bcc
{
local ($d) = @_;
&require_mail();
if ($config{'mail_server'} == 0 && $sender_bcc_maps) {
	# Check Postfix config
	local $map = &postfix::get_maps("sender_bcc_maps");
	local ($rv) = grep { $_->{'name'} eq '@'.$d->{'dom'} } @$map;
	return $rv ? $rv->{'value'} : undef;
	}
return undef;
}

# save_domain_sender_bcc(&domain, [email])
# Turns on or off automatic BCCing for some domain. May call &error.
sub save_domain_sender_bcc
{
local ($d, $email) = @_;
&require_mail();
if ($config{'mail_server'} == 0) {
	$sender_bcc_maps || &error($text{'bcc_epostfix'});
	local $map = &postfix::get_maps("sender_bcc_maps");
        local ($rv) = grep { $_->{'name'} eq '@'.$d->{'dom'} } @$map;
	if ($rv && $email) {
		# Update existing
		local $old = { %$rv };
		$rv->{'value'} = $email;
		&postfix::modify_mapping("sender_bcc_maps", $old, $rv);
		}
	elsif ($rv && !$email) {
		# Remove existing
		&postfix::delete_mapping("sender_bcc_maps", $rv);
		}
	elsif (!$rv && $email) {
		# Add new mapping
		&postfix::create_mapping("sender_bcc_maps",
					 { 'name' => '@'.$d->{'dom'},
					   'value' => $email });
		}
	&postfix::regenerate_bcc_table();
	}
else {
	return $text{'bcc_emailserver'};
	}
}

# get_domain_dependent(&domain)
# If a sender-dependent outgoing IP is enabled for the given domain, returns it.
# Otherwise returns undef.
sub get_domain_dependent
{
local ($d) = @_;
return undef if (!$supports_dependent);
&require_mail();

# Read the map file to find an entry for the domain
local $map = &postfix::get_maps("sender_dependent_default_transport_maps");
local ($rv) = grep { $_->{'name'} eq '@'.$d->{'dom'} } @$map;
return undef if (!$rv);

# Check for a Postfix service
local $master = &postfix::get_master_config();
foreach my $m (@$master) {
	if ($m->{'name'} eq $rv->{'value'} && $m->{'enabled'}) {
		# Found match on the name .. extract the IP
		if ($m->{'command'} =~ /smtp_bind_address=([0-9\.]+)/) {
			return $1;
			}
		}
	}

return undef;
}

# save_domain_dependent(&domain, enabled-flag)
# Enables or disables sender-dependent outgoing IP for the domain
sub save_domain_dependent
{
local ($d, $dependent) = @_;
return undef if (!$supports_dependent);
&require_mail();

# Read the map file to find an entry for the domain
local $map = &postfix::get_maps("sender_dependent_default_transport_maps");
local ($rv) = grep { $_->{'name'} eq '@'.$d->{'dom'} } @$map;
if ($rv && !$dependent) {
	# Need to remove
	&postfix::delete_mapping(
		"sender_dependent_default_transport_maps", $rv);
	&postfix::regenerate_any_table(
		"sender_dependent_default_transport_maps");
	}
elsif (!$rv && $dependent) {
	# Need to add
	$rv = { 'name' => '@'.$d->{'dom'},
		'value' => 'smtp-'.$d->{'id'} };
	&postfix::create_mapping(
		"sender_dependent_default_transport_maps", $rv);
	&postfix::regenerate_any_table(
		"sender_dependent_default_transport_maps");
	}

# Find the master file entry for smtp
local $master = &postfix::get_master_config();
local ($smtp) = grep { $_->{'name'} eq 'smtp' &&
		       $_->{'type'} eq 'unix' &&
		       $_->{'enabled'} } @$master;
return "No master service named smtp found!" if (!$smtp);

# Find the master file entry for this domain
local ($m) = grep { $_->{'name'} eq 'smtp-'.$d->{'id'} && $_->{'enabled'} }
		  @$master;
if ($m && !$dependent) {
	# Need to remove
	&postfix::delete_master($m);
	&postfix::reload_postfix();
	}
elsif (!$m && $dependent) {
	# Need to add
	$m = { %$smtp };
	delete($m->{'line'});
	delete($m->{'uline'});
	$m->{'command'} .= " -o smtp_bind_address=$d->{'ip'}";
	$m->{'name'} = "smtp-".$d->{'id'};
	&postfix::create_master($m);
	&postfix::reload_postfix();
	}
elsif ($m && $dependent) {
	# Need to fix IP, maybe
	if ($m->{'command'} =~ /smtp_bind_address=([0-9\.]+)/ &&
	    $1 ne $d->{'ip'}) {
		$m->{'command'} =~ s/smtp_bind_address=([0-9\.]+)/smtp_bind_address=$d->{'ip'}/;
		&postfix::modify_master($m);
		&postfix::reload_postfix();
		}
	}
return undef;
}

# check_postfix_map(mapname)
# Checks that all data sources in a map are usable. Returns undef if OK, or
# an error message if not.
sub check_postfix_map
{
local ($mapname) = @_;
&require_mail();
local $tv = &postfix::get_real_value($mapname);
$tv || return &text('checkmap_enone', '../postfix/');
if (defined(&postfix::can_access_map)) {
	# Can use new Webmin functions to check
	local @tv = &postfix::get_maps_types_files($tv);
	@tv || return &text('checkmap_enone', '../postfix/');
	foreach my $tv (@tv) {
		if (!&postfix::supports_map_type($tv->[0])) {
			return &text('checkmap_esupport',
				     "$tv->[0]:$tv->[1]");
			}
		local $err = &postfix::can_access_map(@$tv);
		if ($err) {
			return &text('checkmap_eaccess',
				     "$tv->[0]:$tv->[1]", $err);
			}
		}
	}
else {
	# Only allow file-based maps
	$tv =~ /(hash|regexp|pcre|btree|dbm):/i ||
		return $text{'checkmap_efile'};
	}
return undef;
}

# obtain_lock_mail(&domain)
# Lock the mail aliases and virtusers files
sub obtain_lock_mail
{
return if (!$config{'mail'});
&obtain_lock_anything();
if ($main::got_lock_mail == 0) {
	&require_mail();
	@main::got_lock_mail_files = ( );
	if ($config{'mail_system'} == 0) {
		# Lock Postfix files
		push(@main::got_lock_mail_files, @virtual_map_files);
		push(@main::got_lock_mail_files, @canonical_map_files);
		push(@main::got_lock_mail_files, @$postfix_afiles);
		push(@main::got_lock_mail_files, @sender_bcc_map_files);
		undef(%postfix::list_aliases_cache);
		undef(%postfix::maps_cache);
		}
	elsif ($config{'mail_system'} == 1) {
		# Lock Sendmail files
		push(@main::got_lock_mail_files, $sendmail_vfile);
		push(@main::got_lock_mail_files, @$sendmail_afiles);
		push(@main::got_lock_mail_files, $sendmail_gfile);
		undef(%sendmail::list_aliases_cache);
		undef(@sendmail::list_virtusers_cache);
		undef(@sendmail::list_generics_cache);
		}
	elsif ($config{'mail_system'} == 2 || $config{'mail_system'} == 4) {
		# Lock Qmail control files
		push(@main::got_lock_mail_files,
		     "$qmailadmin::qmail_control_dir/rcpthosts",
		     "$qmailadmin::qmail_control_dir/locals");
		}
	if (-d $everyone_alias_dir && $_[0] &&
	    !($_[0]->{'alias'} && !$_[0]->{'aliasmail'})) {
		push(@main::got_lock_mail_files,
		     "$everyone_alias_dir/$_[0]->{'id'}");
		}
	@main::got_lock_mail_files = grep { /^\// } @main::got_lock_mail_files;
	foreach my $f (@main::got_lock_mail_files) {
		&lock_file($f);
		}
	}
$main::got_lock_mail++;
}

# Unlock all Mail server files
sub release_lock_mail
{
return if (!$config{'mail'});
if ($main::got_lock_mail == 1) {
	foreach my $f (@main::got_lock_mail_files) {
		&unlock_file($f);
		}
	}
$main::got_lock_mail-- if ($main::got_lock_mail);
&release_lock_anything();
}

# domain_vpopmail_dir(&domain|dname)
# Returns the vpopmail directory for a domain
sub domain_vpopmail_dir
{
local ($d) = @_;
local $dname = ref($d) ? $d->{'dom'} : $d;
local $ddir = "$config{'vpopmail_dir'}/domains/$dname";
if (-d $ddir) {
	return $ddir;
	}
else {
	return glob("$config{'vpopmail_dir'}/domains/?/$dname");
	}
}

# same_dn(dn1, dn2)
# Returns 1 if two DNs are the same
sub same_dn
{
local $dn0 = join(",", split(/,\s*/, $_[0]));
local $dn1 = join(",", split(/,\s*/, $_[1]));
return lc($dn0) eq lc($dn1);
}

# update_last_login_times()
# Scans the mail log and updates the last time a user logs in via IMAP, POP3
# or SMTP.
sub update_last_login_times
{
# Find the mail log
my $maillog = $config{'bw_maillog'};
$maillog = &get_mail_log() if ($maillog eq "auto");
return 0 if (!$maillog);

# Seek to the last position
&lock_file($mail_login_file);
my @st = stat($maillog);
my $lastpost;
my %logins;
&read_file($mail_login_file, \%logins);
$lastpos = $logins{'lastpos'} || $st[7];
if ($lastpos > $st[7]) {
	# Off end .. file has probably been rotated
	$lastpos = 0;
	}
open(MAILLOG, $maillog);
seek(MAILLOG, $lastpos, 0);
my $now = time();
my @tm = localtime($now);
while(<MAILLOG>) {
	s/\r|\n//g;

	# Remove Solaris extra part like [ID 197553 mail.info]
	s/\[ID\s+\d+\s+\S+\]\s+//;

	if (/^(\S+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\S+)\s+dovecot:\s+(pop3|imap)-login:\s+Login:\s+user=<([^>]+)>/) {
		# POP3 or IMAP login with dovecot
		my $ltime;
		eval { $ltime = timelocal($5, $4, $3, $2,
				          $apache_mmap{lc($1)}, $tm[5]); };
		if (!$ltime || $ltime > $now+(24*60*60)) {
			# Must have been last year!
			eval { $ltime = timelocal($5, $4, $3, $2,
					  $apache_mmap{lc($1)}, $tm[5]-1); };
			}
		&add_last_login_time(\%logins, $ltime, $7, $8);
		}
	elsif (/^(\S+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\S+)\s+.*sasl_username=([^ ,]+)/) {
		# Postfix SMTP
		my $ltime;
		eval { $ltime = timelocal($5, $4, $3, $2,
				          $apache_mmap{lc($1)}, $tm[5]); };
		if (!$ltime || $ltime > $now+(24*60*60)) {
			# Must have been last year!
			eval { $ltime = timelocal($5, $4, $3, $2,
					  $apache_mmap{lc($1)}, $tm[5]-1); };
			}
		&add_last_login_time(\%logins, $ltime, 'smtp', $7);
		}
	}
close(MAILLOG);
@st = stat($maillog);
$logins{'lastpos'} = $st[7];
&write_file($mail_login_file, \%logins);
&unlock_file($mail_login_file);
return 1;
}

# add_last_login_time(&logins, time, type, username)
# Add to the hash of login types for some user
sub add_last_login_time
{
my ($logins, $ltime, $ltype, $user) = @_;
my %curr = map { split(/=/, $_) } split(/\s+/, $logins->{$user});
$curr{$ltype} = $ltime;
$logins->{$user} = join(" ", map { $_."=".$curr{$_} } keys %curr);
}

# get_last_login_time(username)
# Returns a hash ref of last login types to times for a user
sub get_last_login_time
{
my ($user) = @_;
my %logins;
&read_file_cached($mail_login_file, \%logins);
if ($logins{$user}) {
	return { map { split(/=/, $_) } split(/\s+/, $logins{$user}) };
	}
else {
	return undef;
	}
}

# save_deleted_aliases(&domain, &aliases)
# Record aliases that belonged to a deleted domain, to restore if mail is
# later re-enabled
sub save_deleted_aliases
{
my ($d, $aliases) = @_;
if (!-d $saved_aliases_dir) {
	&make_dir($saved_aliases_dir, 0700);
	}
&open_lock_tempfile(DELETED, ">$saved_aliases_dir/$d->{'id'}");
foreach my $a (@$aliases) {
	&print_tempfile(DELETED,
		join("\t", $a->{'from'}, @{$a->{'to'}}),"\n");
	}
&close_tempfile(DELETED);
}

# get_deleted_aliases(&domain)
# Returns a list of aliases saved for a domain by save_deleted_aliases
sub get_deleted_aliases
{
my ($d) = @_;
my @rv;
open(DELETED, "$saved_aliases_dir/$d->{'id'}");
while(my $l = <DELETED>) {
	$l =~ s/\r|\n//g;
	my ($from, @to) = split(/\t+/, $l);
	$from =~ s/\@.*$/\@$d->{'dom'}/;
	push(@rv, { 'from' => $from,
		    'to' => \@to });
	}
close(DELETED);
return @rv;
}

# has_deleted_aliases(&domain)
# Returns 1 if deleted aliases were saved for a domain
sub has_deleted_aliases
{
my ($d) = @_;
return -r "$saved_aliases_dir/$d->{'id'}" ? 1 : 0;
}

# clear_deleted_aliases(&domain)
# Remove the file storing deleted aliases. Typically called after they have
# been re-created.
sub clear_deleted_aliases
{
my ($d) = @_;    
&unlink_logged("$saved_aliases_dir/$d->{'id'}");
}

# enable_email_autoconfig(&domain)
# Sets up an autoconfig.domain.com server alias and DNS entry, and configures
# /mail/config-v1.1.xml?emailaddress=foo@domain.com to return XML for
# automatic configuration for that domain
sub enable_email_autoconfig
{
local ($d) = @_;
local $autoconfig = "autoconfig.".$d->{'dom'};

# Work out IMAP server port and mode
local $imap_host = "mail.$d->{'dom'}";
local $imap_port = 143;
local $imap_type = "plain";
local $imap_enc = "password-cleartext";
if (&foreign_installed("dovecot")) {
	&foreign_require("dovecot");
	local $conf = &dovecot::get_config();
	local $sslopt = &dovecot::find("ssl_disable", $conf, 2) ?
			"ssl_disable" : "ssl";
	if ($sslopt eq "ssl" &&
	    &dovecot::find_value($sslopt, $conf) ne "no") {
		$imap_port = 993;
		$imap_type = "SSL";
		}
	elsif ($sslopt eq "ssl_disable" &&
	       &dovecot::find_value($sslopt, $conf) ne "yes") {
		$imap_port = 993;
		$imap_type = "SSL";
		}
	if ($imap_type ne "SSL" &&
	    &dovecot::find_value("disable_plaintext_auth", $conf) ne "no") {
		# Force use of hashed passwords
		$imap_enc = "password-encrypted";
		}
	}

# Work out SMTP server port and mode
local $smtp_host = "mail.$d->{'dom'}";
local $smtp_port = 25;
local $smtp_type = "plain";
local $smtp_enc = "password-cleartext";
if ($config{'mail_system'} == 0) {
	# Check for Postfix submission port
	&foreign_require("postfix");
	local $master = postfix::get_master_config();
	local ($submission) = grep { $_->{'name'} eq 'submission' &&
				     $_->{'enabled'} } @$master;
	if ($submission) {
		$smtp_port = 587;
		if ($submission->{'command'} =~ /smtpd_tls_security_level=(encrypt|may)/) {
			$smtp_type = "STARTTLS";
			}
		}
	}
elsif ($config{'mail_system'} == 1) {
	# Check for Sendmail submission port
	&foreign_require("sendmail");
	local $conf = &sendmail::get_sendmailcf();
	foreach my $dpo (&sendmail::find_options("DaemonPortOptions", $conf)) {
		if ($dpo->[1] =~ /Port=(587|submission)/) {
			$smtp_port = 587;
			}
		}
	}

# Create CGI that outputs the correct XML for the domain
local $cgidir = &cgi_bin_dir($d);
local $autocgi = "$cgidir/autoconfig.cgi";
if (!-d $cgidir) {
	return "CGI directory $cgidir does not exist";
	}
&lock_file($autocgi);
&copy_source_dest_as_domain_user($d, "$module_root_directory/autoconfig.cgi",
				 $autocgi);
local $lref = &read_file_lines_as_domain_user($d, $autocgi);
local $tmpl = &get_template($d->{'template'});
foreach my $l (@$lref) {
	if ($l =~ /^#!/) {
		$l = "#!".&get_perl_path();
		}
	elsif ($l =~ /^\$OWNER\s+=/) {
		$l = "\$OWNER = '$d->{'owner'}';";
		}
	elsif ($l =~ /^\$USER\s+=/ && !$d->{'parent'}) {
		$l = "\$USER = '$d->{'user'}';";
		}
	elsif ($l =~ /^\$SMTP_HOST\s+=/) {
		$l = "\$SMTP_HOST = '$smtp_host';";
		}
	elsif ($l =~ /^\$SMTP_PORT\s+=/) {
		$l = "\$SMTP_PORT = '$smtp_port';";
		}
	elsif ($l =~ /^\$SMTP_TYPE\s+=/) {
		$l = "\$SMTP_TYPE = '$smtp_type';";
		}
	elsif ($l =~ /^\$SMTP_ENC\s+=/) {
		$l = "\$SMTP_ENC = '$smtp_enc';";
		}
	elsif ($l =~ /^\$IMAP_HOST\s+=/) {
		$l = "\$IMAP_HOST = '$imap_host';";
		}
	elsif ($l =~ /^\$IMAP_PORT\s+=/) {
		$l = "\$IMAP_PORT = '$imap_port';";
		}
	elsif ($l =~ /^\$IMAP_TYPE\s+=/) {
		$l = "\$IMAP_TYPE = '$imap_type';";
		}
	elsif ($l =~ /^\$IMAP_ENC\s+=/) {
		$l = "\$IMAP_ENC = '$imap_enc';";
		}
	elsif ($l =~ /^\$PREFIX\s+=/) {
		$l = "\$PREFIX = '$d->{'prefix'}';";
		}
	elsif ($l =~ /^\$STYLE\s+=/) {
		$l = "\$STYLE = '$tmpl->{'append_style'}';";
		}
	}
local $xml;
local $tmpl = &get_template($d->{'template'});
if ($tmpl->{'autoconfig'} && $tmpl->{'autoconfig'} ne 'none') {
	$xml = &substitute_domain_template($tmpl->{'autoconfig'}, $d);
	$xml =~ s/\t/\n/g;
	}
else {
	$xml = &get_autoconfig_xml();
	}
local $idx = &indexof("_XML_GOES_HERE_", @$lref);
if ($idx >= 0) {
	splice(@$lref, $idx, 1, split(/\n/, $xml));
	}
&flush_file_lines_as_domain_user($d, $autocgi);
&set_ownership_permissions(undef, undef, 0755, $autocgi);
&unlock_file($autocgi);

# Add ServerAlias and redirect if missing
local $p = &domain_has_website($d);
if ($p && $p ne "web") {
	# Call plugin, like Nginx
	local $err = &plugin_call($p, "feature_save_web_autoconfig", $d, 1);
	return $err if ($err);
	}
elsif ($p) {
	# Add to Apache config
	&obtain_lock_web($d);
	&require_apache();
	local @ports = ( $d->{'web_port'},
		      $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( ) );
	local $any;
	local $found;
	foreach my $p (@ports) {
		local ($virt, $vconf, $conf) =
			&get_apache_virtual($d->{'dom'}, $p);
		next if (!$virt);
		$found++;

		# Add ServerAlias
		local @sa = &apache::find_directive("ServerAlias", $vconf);
		local $found;
		foreach my $sa (@sa) {
			local @saw = split(/\s+/, $sa);
			$found++ if (&indexoflc($autoconfig, @saw) >= 0);
			}
		if (!$found) {
			push(@sa, $autoconfig);
			&apache::save_directive("ServerAlias", \@sa,
						$vconf, $conf);
			&flush_file_lines($virt->{'file'});
			$any++;
			}

		# Add redirect to CGI
		local @rd = &apache::find_directive("Redirect", $vconf);
		local $found;
		foreach my $rd (@rd) {
			if ($rd =~ /^\/mail\/config-v1.1.xml\s/) {
				$found = 1;
				}
			}
		if (!$found) {
			push(@rd, "/mail/config-v1.1.xml ".
				  "/cgi-bin/autoconfig.cgi");
			&apache::save_directive("Redirect", \@rd,
						$vconf, $conf);
			&flush_file_lines($virt->{'file'});
			$any++;
			}
		}
	if ($any) {
		&register_post_action(\&restart_apache);
		}
	&release_lock_web($d);
	$found || return "No Apache virtual hosts for $d->{'dom'} found";
	}

if ($d->{'dns'}) {
	# Add DNS entry
	&obtain_lock_dns($d);
	local ($recs, $file) = &get_domain_dns_records_and_file($d);
	$autoconfig .= ".";
	if ($file) {
		local ($r) = grep { $_->{'name'} eq $autoconfig } @$recs;
		if (!$r) {
			my $ip = $d->{'dns_ip'} || $d->{'ip'};
			&bind8::create_record($file, $autoconfig, undef,
					      "IN", "A", $ip);
			my $err = &post_records_change($d, $recs, $file);
			&register_post_action(\&restart_bind, $d);
			}
		}
	&release_lock_dns($d);
	$file || return "No DNS zone for $d->{'dom'} found";
	}
return undef;
}

# disable_email_autoconfig(&domain)
# Delete the DNS entry, ServerAlias and Redirect for mail auto-config
sub disable_email_autoconfig
{
local ($d) = @_;
local $autoconfig = "autoconfig.".$d->{'dom'};

# Remove ServerAlias and redirect if they exist
local $p = &domain_has_website($d);
if ($p && $p ne "web") {
	# Call plugin, like Nginx
	local $err = &plugin_call($p, "feature_save_web_autoconfig", $d, 0);
	return $err if ($err);
	}
elsif ($p) {
	# Add to Apache config
	&require_apache();
	&obtain_lock_web($d);
	local @ports = ( $d->{'web_port'},
		      $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( ) );
	local $any;
	local $found;
	foreach my $p (@ports) {
		local ($virt, $vconf, $conf) =
			&get_apache_virtual($d->{'dom'}, $p);
		next if (!$virt);
		$found++;

		# Remove ServerAlias
		local @sa = &apache::find_directive("ServerAlias", $vconf);
		local $found;
		foreach my $sa (@sa) {
			local @saw = split(/\s+/, $sa);
			local $idx = &indexoflc($autoconfig, @saw);
			if ($idx >= 0) {
				splice(@saw, $idx, 1);
				$sa = join(" ", @saw);
				$found++;
				}
			}
		if ($found) {
			@sa = grep { $_ ne "" } @sa;
			&apache::save_directive("ServerAlias", \@sa,
						$vconf, $conf);
			&flush_file_lines($virt->{'file'});
			$any++;
			}

		# Remove redirect to CGI
		local @rd = &apache::find_directive("Redirect", $vconf);
		local $found;
		foreach my $rd (@rd) {
			if ($rd =~ /^\/mail\/config-v1.1.xml\s/) {
				@rd = grep { $_ ne $rd } @rd;
				$found = 1;
				last;
				}
			}
		if ($found) {
			&apache::save_directive("Redirect", \@rd,
						$vconf, $conf);
			&flush_file_lines($virt->{'file'});
			$any++;
			}
		}
	&release_lock_web($d);
	if ($any) {
		&register_post_action(\&restart_apache);
		}
	$found || return "No Apache virtual hosts for $d->{'dom'} found";
	}

if ($d->{'dns'}) {
	# Remove DNS entry
	&obtain_lock_dns($d);
	local ($recs, $file) = &get_domain_dns_records_and_file($d);
	$autoconfig .= ".";
	if ($file) {
		local ($r) = grep { $_->{'name'} eq $autoconfig } @$recs;
		if ($r) {
			&bind8::delete_record($file, $r);
			my $err = &post_records_change($d, $recs, $file);
			&register_post_action(\&restart_bind, $d);
			}
		}
	&release_lock_dns($d);
	$file || return "No DNS zone for $d->{'dom'} found";
	}
return undef;
}

# get_autoconfig_xml()
# Returns the XML template for the autoconfig response
sub get_autoconfig_xml
{
return <<'EOF';
<?xml version="1.0" encoding="UTF-8"?>
 
<clientConfig version="1.1">
  <emailProvider id="$SMTP_DOMAIN">
    <domain>$SMTP_DOMAIN</domain>
    <displayName>$OWNER Email</displayName>
    <displayShortName>$OWNER</displayShortName>
    <incomingServer type="imap">
      <hostname>$IMAP_HOST</hostname>
      <port>$IMAP_PORT</port>
      <socketType>$IMAP_TYPE</socketType>
      <authentication>$IMAP_ENC</authentication>
      <username>$SMTP_LOGIN</username>
    </incomingServer>
    <outgoingServer type="smtp">
      <hostname>$SMTP_HOST</hostname>
      <port>$SMTP_PORT</port>
      <socketType>$SMTP_TYPE</socketType>
      <authentication>$SMTP_ENC</authentication>
      <username>$SMTP_LOGIN</username>
    </outgoingServer>
  </emailProvider>
</clientConfig>
EOF
}

$done_feature_script{'mail'} = 1;

1;

