
sub require_mail
{
return if ($require_mail++);
$can_alias_types{12} = 0;	# this autoreponder for vpopmail only
if ($config{'mail_system'} == 1) {
	# Using sendmail for email
	&foreign_require("sendmail", "sendmail-lib.pl");
	&foreign_require("sendmail", "virtusers-lib.pl");
	&foreign_require("sendmail", "aliases-lib.pl");
	&foreign_require("sendmail", "boxes-lib.pl");
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
	$can_alias_comments = $virtualmin_pro && &get_webmin_version() >= 1.294;
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
	$can_alias_types{9} = 0;	# bounce not yet supported for postfix
	$can_alias_comments = $virtualmin_pro && &get_webmin_version() >= 1.294;
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
	}
}

# list_domain_aliases(&domain, [ignore-plugins])
# Returns just virtusers for some domain
sub list_domain_aliases
{
&require_mail();
local ($u, %foruser);
if ($config{'mail_system'} != 4) {
	# Filter out aliases that point to users
	foreach $u (&list_domain_users($_[0], 0, 1, 1, 1)) {
		local $pop3 = &remove_userdom($u->{'user'}, $_[0]);
		$foruser{$pop3."\@".$_[0]->{'dom'}} = $u->{'user'};
		if ($config{'mail_system'} == 0 && $u->{'user'} =~ /\@/) {
			# Special case for Postfix @ users
			$foruser{$pop3."\@".$_[0]->{'dom'}} =
				&replace_atsign($u->{'user'});
			}
		}
	if ($d->{'mailbox'}) {
		$foruser{$d->{'user'}."\@".$_[0]->{'dom'}} = $d->{'user'};
		}
	}
local @virts = &list_virtusers();
local %ignore;
if ($_[1]) {
	# Get a list to ignore from each plugin
	foreach my $f (@feature_plugins) {
		foreach my $i (&plugin_call($f, "virtusers_ignore", $_[0])) {
			$ignore{lc($i)} = 1;
			}
		}
	}

# Return only virtusers that match this domain,
# which are not for forwarding email for users in the domain,
# and which are not on the plugin ignore list.
return grep { $_->{'from'} =~ /\@(\S+)$/ && $1 eq $_[0]->{'dom'} &&
	      ($foruser{$_->{'from'}} ne $_->{'to'}->[0] ||
	       @{$_->{'to'}} != 1) &&
	      !$ignore{lc($_->{'from'})} } @virts;
}

# setup_mail(&domain, [leave-aliases])
# Adds a domain to the list of those accepted by the mail system
sub setup_mail
{
&$first_print($text{'setup_doms'});
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
	local $out = `$vpopbin/vadddomain $qdom $qpass 2>&1`;
	if ($?) {
		&$second_print(&text('setup_evadddomain', "<tt>$out</tt>"));
		return;
		}
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
		&create_virtuser({ 'from' => '@'.$_[0]->{'dom'},
				   'to' => [ '%1@'.$aliasdom->{'dom'} ] })
			if (!$gotvirt{'@'.$_[0]->{'dom'}});
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
			&create_virtuser($a) if (!$gotvirt{$a->{'from'}});
			}
		if ($tmpl->{'dom_aliases_bounce'} &&
		    !$acreate{"\@$_[0]->{'dom'}"} &&
		    !$gotvirt{'@'.$_[0]->{'dom'}}) {
			# Add bounce alias
			local $v = { 'from' => "\@$_[0]->{'dom'}",
				     'to' => [ 'BOUNCE' ] };
			&create_virtuser($v);
			}
		&$second_print($text{'setup_done'});
		}
	}

# Setup any secondary MX servers
&setup_on_secondaries($_[0]);
}

# delete_mail(&domain, [leave-aliases])
# Removes a domain from the list of those accepted by the mail system
sub delete_mail
{
&$first_print($text{'delete_doms'});
&require_mail();

if ($_[0]->{'alias'}) {
        # Remove whole-domain alias
        local @virts = &list_virtusers();
        local ($catchall) = grep { lc($_->{'from'}) eq '@'.$_[0]->{'dom'} }
				 @virts;
        if ($catchall) {
                &delete_virtuser($catchall);
                }
        }

if ($config{'mail_system'} == 1) {
	# Delete domain from sendmail local domains file
	local $conf = &sendmail::get_sendmailcf();
	local $cwfile;
	local @dlist = &sendmail::get_file_or_config($conf, "w", undef,
						     \$cwfile);
	&lock_file($cwfile) if ($cwfile);
	&lock_file($sendmail::config{'sendmail_cf'});
	&sendmail::delete_file_or_config($conf, "w", $_[0]->{'dom'});
	&flush_file_lines();
	&unlock_file($sendmail::config{'sendmail_cf'});
	&unlock_file($cwfile) if ($cwfile);
	if (!$no_restart_mail) {
		&sendmail::restart_sendmail();
		}
	}
elsif ($config{'mail_system'} == 0) {
	# Delete the special postfix virtuser
	local @virts = &list_virtusers();
	local ($lv) = grep { lc($_->{'from'}) eq $_[0]->{'dom'} } @virts;
	if ($lv) {
		&delete_virtuser($lv);
		}
	local @md = split(/[, ]+/,
			  lc(&postfix::get_current_value("mydestination")));
	local $idx = &indexof($_[0]->{'dom'}, @md);
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
	$dlist = [ grep { lc($_) ne $_[0]->{'dom'} } @$dlist ];
	&qmailadmin::save_control_file("locals", $dlist);

	local $rlist = &qmailadmin::list_control_file("rcpthosts");
	$rlist = [ grep { lc($_) ne $_[0]->{'dom'} } @$rlist ];
	&qmailadmin::save_control_file("rcpthosts", $rlist);

	local ($virtmap) = grep { lc($_->{'domain'}) eq $_[0]->{'dom'} &&
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
	local $qdom = quotemeta($_[0]->{'dom'});
	local $out = `$vpopbin/vdeldomain $qdom 2>&1`;
	if ($?) {
		&$second_print(&text('delete_evdeldomain', "<tt>$out</tt>"));
		return;
		}
	}
&$second_print($text{'setup_done'});

if ($config{'delete_virts'}) {
	# Delete all email aliases
	&$first_print($text{'delete_aliases'});
	foreach my $v (&list_virtusers()) {
		if ($v->{'from'} =~ /\@(\S+)$/ &&
		    $1 eq $_[0]->{'dom'}) {
			&delete_virtuser($v);
			}
		}
	&$second_print($text{'setup_done'});
	}

# Remove any secondary MX servers
&delete_on_secondaries($_[0]);
}

# modify_mail(&domain, &olddomain)
# Deal with a change in domain name
sub modify_mail
{
local $tmpl = &get_template($_[0]->{'template'});
&require_useradmin();

# Need to update the home directory of all mail users .. but only
# in the Unix object, as their files will have already been moved
# as part of the domain's directory.
# No need to do this for VPOPMail users.
# Also, any users in the user@domain name format need to be renamed
if ($_[0]->{'home'} ne $_[1]->{'home'} ||
    $_[0]->{'dom'} ne $_[1]->{'dom'} ||
    $_[0]->{'gid'} != $_[1]->{'gid'} ||
    $_[0]->{'prefix'} ne $_[1]->{'prefix'}) {
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

		# Save the user
		&modify_user($u, \%oldu, $_[0], 1);
		if (!$u->{'nomailfile'}) {
			&rename_mail_file($u, \%oldu);
			}
		}
	&$second_print($text{'setup_done'});
	}
	
if ($_[0]->{'alias'} && $_[2] && $_[2]->{'dom'} ne $_[3]->{'dom'}) {
	# This is an alias, and the domain it is aliased to has changed ..
	# update the catchall alias
	local @virts = &list_virtusers();
	local ($catchall) = grep { $_->{'to'}->[0] eq '%1@'.$_[3]->{'dom'} }
				 @virts;
	if ($catchall) {
		&$first_print($text{'save_mailalias'});
		$catchall->{'to'} = [ '%1@'.$_[2]->{'dom'} ];
		&modify_virtuser($catchall, $catchall);
		&$second_print($text{'setup_done'});
		}
	}

if ($_[0]->{'dom'} ne $_[1]->{'dom'}) {
	# Delete the old mail domain and add the new
	local $no_restart_mail = 1;
	&delete_mail($_[1], 1);
	&setup_mail($_[0], 1);
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
		}

	# Update any virtusers with addresses in the old domain
	&$first_print($text{'save_fixvirts'});
	foreach $v (&list_virtusers()) {
		if ($v->{'from'} =~ /^(\S*)\@(\S+)$/ &&
		    lc($2) eq $_[1]->{'dom'}) {
			local $oldv = { %$v };
			$v->{'from'} = "$1\@$_[0]->{'dom'}";
			&fix_alias_when_renaming($v, $_[0], $_[1]);
			&modify_virtuser($oldv, $v);
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

	&$second_print($text{'setup_done'});
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
	if (!&is_local_domain($d->{'dom'}));

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
	foreach my $user (&list_domain_users($d, 0)) {
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
			local $rg = getgrgid($st[4]) || $user->{'gid'};
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
&delete_mail($_[0], 1);

&$first_print($text{'disable_users'});
foreach my $user (&list_domain_users($_[0], 1)) {
	if (!$user->{'alwaysplain'}) {
		&set_pass_disable($user, 1);
		&modify_user($user, $user, $_[0]);
		}
	}
&$second_print($text{'setup_done'});
}

# enable_mail(&domain)
# Turn on mail for the domain, and re-enable login for all users
sub enable_mail
{
&setup_mail($_[0], 1);

&$first_print($text{'enable_users'});
foreach my $user (&list_domain_users($_[0], 1)) {
	if (!$user->{'alwaysplain'}) {
		&set_pass_disable($user, 0);
		&modify_user($user, $user, $_[0]);
		}
	}
&$second_print($text{'setup_done'});
}

# check_mail_clash()
# Does nothing, because no clash checking is needed
sub check_mail_clash
{
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
	$found++ if (&indexof($_[0], @md) >= 0);
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
return $found;
}

# list_virtusers()
# Returns a list of a virtual mail address mappings. Each may actually have
# an alias as its destination, and is automatically expanded to the
# destinations for that alias.
sub list_virtusers
{
# Build list of unix users, to exclude aliases with same name as users
# (which are picked up by list_domain_users instead).
&require_mail();
if (!defined(%unix_user)) {
	&require_useradmin(1);
	foreach my $u (&list_all_users()) {
		$unix_user{&escape_alias($u->{'user'})}++;
		}
	}

if ($config{'mail_system'} == 1) {
	# Get from sendmail
	local @svirts = &sendmail::list_virtusers($sendmail_vfile);
	local %aliases = map { lc($_->{'name'}), $_ }
			 grep { $_->{'enabled'} && !$unix_user{$_->{'name'}} }
				&sendmail::list_aliases($sendmail_afiles);
	local ($v, $a, @virts);
	foreach $v (@svirts) {
		local %rv = ( 'virt' => $v,
			      'cmt' => $v->{'cmt'},
			      'from' => lc($v->{'from'}) );
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
			 grep { $_->{'enabled'} && !$unix_user{$_->{'name'}} }
			     &postfix::list_aliases($postfix_afiles);
	local ($v, $a, @virts);
	foreach $v (@$svirts) {
		local %rv = ( 'from' => lc($v->{'name'}),
			      'cmt' => $v->{'cmt'},
			      'virt' => $v );
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
	if (!defined(@vpopmail_aliases_cache)) {
		@vpopmail_aliases_cache = ( );
		opendir(DDIR, "$config{'vpopmail_dir'}/domains");
		local @doms = grep { $_ !~ /^\./ } readdir(DDIR);
		closedir(DDIR);
		local $dname;
		foreach $dname (@doms) {
			# Get aliases from .qmail files
			local %already;
			local $ddir = "$config{'vpopmail_dir'}/domains/$dname";
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

			# Add those from valias command (for sites using MySQL or some
			# other backend)
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
}

# qmail_to_vpopmail(line, domain)
# Converts a line from a .qmail file created by vpopmail into the internal
# Virtualmin format. 
sub qmail_to_vpopmail
{
local $ddir = "$config{'vpopmail_dir'}/domains/$_[1]";
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
local $ddir = "$config{'vpopmail_dir'}/domains/$_[1]";
if ($_[0] =~ /^\S+\@\S+$/) {
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
	if ($_[0]->{'alias'}) {
		# Delete alias too
		&lock_file($_[0]->{'alias'}->{'file'});
		&sendmail::delete_alias($_[0]->{'alias'});
		&unlock_file($_[0]->{'alias'}->{'file'});
		}
	&lock_file($_[0]->{'virt'}->{'file'});
	&sendmail::delete_virtuser($_[0]->{'virt'}, $sendmail_vfile,
				   $sendmail_vdbm, $sendmail_vdbmtype);
	&unlock_file($_[0]->{'virt'}->{'file'});
	}
elsif ($config{'mail_system'} == 0) {
	# Delete from postfix file
	if ($_[0]->{'alias'}) {
		# Delete alias too
		&lock_file($_[0]->{'alias'}->{'file'});
		&postfix::delete_alias($_[0]->{'alias'});
		&unlock_file($_[0]->{'alias'}->{'file'});
		&postfix::regenerate_aliases();
		}
	&lock_file($_[0]->{'virt'}->{'file'});
	&postfix::delete_mapping($virtual_type, $_[0]->{'virt'});
	&unlock_file($_[0]->{'virt'}->{'file'});
	&postfix::regenerate_virtual_table();
	}
elsif ($config{'mail_system'} == 2) {
	# Just delete the qmail alias
	&qmailadmin::delete_alias($_[0]->{'alias'});
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
&execute_after_virtuser($_[0], 'DELETE_ALIAS');
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
		local $alias = { "name" => $an,
				 "enabled" => 1,
				 "values" => \@smto };
		$_[1]->{'alias'} = $alias;
		&sendmail::lock_alias_files($sendmail_afiles);
		&sendmail::create_alias($alias, $sendmail_afiles);
		&sendmail::unlock_alias_files($sendmail_afiles);
		local $virt = { "from" => $_[1]->{'from'},
				"to" => $an,
				"cmt" => $_[1]->{'cmt'} };
		&lock_file($_[0]->{'virt'}->{'file'});
		&sendmail::modify_virtuser($_[0]->{'virt'}, $virt,
					   $sendmail_vfile, $sendmail_vdbm,
					   $sendmail_vdbmtype);
		&unlock_file($_[0]->{'virt'}->{'file'});
		$_[1]->{'virt'} = $virt;
		}
	elsif ($alias) {
		# Just update alias and maybe virtuser
		$alias->{'values'} = \@smto;
		&lock_file($alias->{'file'});
		$alias->{'name'} = $an if ($_[1]->{'from'} ne $_[0]->{'from'});
		&sendmail::modify_alias($oldalias, $alias);
		&unlock_file($alias->{'file'});
		if ($_[1]->{'from'} ne $_[0]->{'from'} ||
		    $_[1]->{'cmt'} ne $_[0]->{'cmt'}) {
			# Re-named .. need to change virtuser too
			local $virt = { "from" => $_[1]->{'from'},
					"to" => $an,
					"cmt" => $_[1]->{'cmt'} };
			&lock_file($_[0]->{'virt'}->{'file'});
			&sendmail::modify_virtuser($_[0]->{'virt'}, $virt,
						   $sendmail_vfile,
						   $sendmail_vdbm,
						   $sendmail_vdbmtype);
			&unlock_file($_[0]->{'virt'}->{'file'});
			$_[1]->{'virt'} = $virt;
			}
		}
	else {
		# Just update virtuser
		local $virt = { "from" => $_[1]->{'from'},
				"to" => $smto[0],
				"cmt" => $_[1]->{'cmt'} };
		&lock_file($_[0]->{'virt'}->{'file'});
		&sendmail::modify_virtuser($_[0]->{'virt'}, $virt,
					   $sendmail_vfile, $sendmail_vdbm,
					   $sendmail_vdbmtype);
		&unlock_file($_[0]->{'virt'}->{'file'});
		$_[1]->{'virt'} = $virt;
		}
	}
elsif ($config{'mail_system'} == 0) {
	# Modify in postfix file
	local $alias = $_[0]->{'alias'};
	local $oldalias = $alias ? { %$alias } : undef;
	local @psto = map { $_ =~ /^BOUNCE\s+(.*)$/ ? "BOUNCE" : $_ } @to;
	$_[0]->{'from'} =~ /^(\S*)\@(\S+)$/;
	local $an = ($1 || "default")."-".$2;
	if (&needs_alias(@psto) && !$alias) {
		# Alias needs to be created and virtuser updated
		local $alias = { "name" => $an,
				 "enabled" => 1,
				 "values" => \@psto };
		$_[1]->{'alias'} = $alias;
		&postfix::lock_alias_files($postfix_afiles);
		&postfix::create_alias($alias, $postfix_afiles);
		&postfix::unlock_alias_files($postfix_afiles);
		&postfix::regenerate_aliases();
		local $virt = { "name" => $_[1]->{'from'},
				"value" => $an,
				"cmt" => $_[1]->{'cmt'} };
		&lock_file($_[0]->{'virt'}->{'file'});
		&postfix::modify_mapping($virtual_type, $_[0]->{'virt'}, $virt);
		&unlock_file($_[0]->{'virt'}->{'file'});
		$_[1]->{'virt'} = $virt;
		&postfix::regenerate_virtual_table();
		}
	elsif ($alias) {
		# Just update alias
		$alias->{'values'} = \@psto;
		&lock_file($alias->{'file'});
		$alias->{'name'} = $an if ($_[1]->{'from'} ne $_[0]->{'from'});
		&postfix::modify_alias($oldalias, $alias);
		&unlock_file($alias->{'file'});
		&postfix::regenerate_aliases();
		if ($_[1]->{'from'} ne $_[0]->{'from'} ||
		    $_[1]->{'cmt'} ne $_[0]->{'cmt'}) {
			# Re-named .. need to change virtuser too
			local $virt = { "name" => $_[1]->{'from'},
					"value" => $an,
					"cmt" => $_[1]->{'cmt'} };
			&lock_file($_[0]->{'virt'}->{'file'});
			&postfix::modify_mapping($virtual_type, $_[0]->{'virt'},
						 $virt);
			&unlock_file($_[0]->{'virt'}->{'file'});
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
		&lock_file($_[0]->{'virt'}->{'file'});
		&postfix::modify_mapping($virtual_type, $_[0]->{'virt'}, $virt);
		&unlock_file($_[0]->{'virt'}->{'file'});
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
	# Update the Qmail pseudo-user
	local $ldap = &connect_qmail_ldap();
	$_[1]->{'from'} =~ /^(\S*)\@(\S+)$/;
	local ($box, $dom) = ($1 || "catchall", $2);
	local $_[1]->{'dn'} = "uid=$box-$dom,$config{'ldap_base'}";
	local $attrs = [ "uid" => "$box-$dom",
			 "mail" => $box."\@".$dom,
			 "mailForwardingAddress" => $_[1]->{'to'} ];
	local $rv = $ldap->modify($_[0]->{'dn'},
				  replace => $attrs);
	&error($rv->error) if ($rv->code);
	if ($_[0]->{'dn'} ne $_[1]->{'dn'}) {
		# Re-named too!
		$rv = $ldap->moddn($_[0]->{'dn'},
				   newrdn => "uid=$box-$dom");
		&error($rv->error) if ($rv->code);
		}
	$ldap->unbind();
	}
elsif ($config{'mail_system'} == 5) {
	# Just delete the old vpopmail alias, and re-add!
	&delete_virtuser($_[0]);
	&create_virtuser($_[1]);
	}
&execute_after_virtuser($_[1], 'MODIFY_ALIAS');
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
		&check_alias_clash($an) && &error(&text('alias_eclash2', $an));
		local $alias = { "name" => $an,
				 "enabled" => 1,
				 "values" => \@smto };
		$_[0]->{'alias'} = $alias;
		&sendmail::lock_alias_files($sendmail_afiles);
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
	&lock_file($sendmail_vfile);
	&sendmail::create_virtuser($virt, $sendmail_vfile,
				   $sendmail_vdbm,
				   $sendmail_vdbmtype);
	&unlock_file($sendmail_vfile);
	$_[0]->{'virt'} = $virt;
	}
elsif ($config{'mail_system'} == 0) {
	# Create in postfix file
	local @psto = map { $_ =~ /^BOUNCE\s+(.*)$/ ? "BOUNCE" : $_ } @to;
	if (&needs_alias(@psto)) {
		# Need to create an alias, named address-domain
		$_[0]->{'from'} =~ /^(\S*)\@(\S+)$/;
		local $an = ($1 || "default")."-".$2;
		&check_alias_clash($an) && &error(&text('alias_eclash2', $an));
		local $alias = { "name" => $an,
				 "enabled" => 1,
				 "values" => \@psto };
		$_[0]->{'alias'} = $alias;
		&postfix::lock_alias_files($postfix_afiles);
		&postfix::create_alias($alias, $postfix_afiles);
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
	&lock_file($virtual_map_files[0]);
	&create_replace_mapping($virtual_type, $virt);
	&unlock_file($virtual_map_files[0]);
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
		local $ddir = "$config{'vpopmail_dir'}/domains/$dom";
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
&execute_after_virtuser($_[0], 'CREATE_ALIAS');
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
if ($_[0]) {
	return $err;
	}
elsif ($err) {
	&error($err);
	}
}

# create_mail_file(&user)
# Creates a new empty mail file for a user, if necessary. Returns the path
# and type (0 for mbox, 1 for maildir)
sub create_mail_file
{
&require_mail();
local $mf;
local $md;
local ($uid, $gid) = ($_[0]->{'uid'}, $_[0]->{'gid'});
if ($config{'mail_system'} == 1) {
	# Sendmail always uses mail files
	$mf = &sendmail::user_mail_file($_[0]->{'user'});
	}
elsif ($config{'mail_system'} == 0) {
	# Postfix user
	local ($s, $d) = &postfix::postfix_mail_system();
	if ($s == 0 || $s == 1) {
		# A mail file
		$mf = &postfix::postfix_mail_file($_[0]->{'user'});
		}
	elsif ($s == 2) {
		# A mail directory
		$md = &postfix::postfix_mail_file($_[0]->{'user'});
		}
	}
elsif ($config{'mail_system'} == 2 ||
       $config{'mail_system'} == 4 && !$_[0]->{'qmail'}) {
	# Normal Qmail user
	if ($qmailadmin::config{'mail_system'} == 0) {
		$mf = &qmailadmin::user_mail_file($_[0]->{'user'});
		}
	elsif ($qmailadmin::config{'mail_system'} == 1) {
		$md = &qmailadmin::user_mail_dir($_[0]->{'user'});
		}
	}
elsif ($config{'mail_system'} == 4) {
	# Qmail+LDAP mail file comes from DB
	if ($_[0]->{'mailstore'} =~ /^(.*)\/$/) {
		$md = &add_ldapmessagestore("$1");
		}
	else {
		$mf = &add_ldapmessagestore($_[0]->{'mailstore'});
		}
	if (!$_[0]->{'unix'}) {
		# For non-NSS Qmail+LDAP users, set the ownership based on
		# LDAP control files
		local $cuid = &qmailadmin::get_control_file("ldapuid");
		local $cgid = &qmailadmin::get_control_file("ldapgid");
		$uid = $cuid if (defined($cuid));
		$gid = $cgid if (defined($cgid));
		}
	}
elsif ($config{'mail_system'} == 5) {
	# Nothing to do for VPOPMail, because it gets created automatically
	# by vadduser
	@rv = ( &user_mail_file($_[0]), 1 );
	}

if ($mf && !-r $mf) {
	# Create the mailbox, owned by the user
	&open_tempfile(MF, ">$mf");
	&close_tempfile(MF);
	&set_ownership_permissions($uid, $gid, undef, $mf);
	@rv = ( $mf, 0 );
	}
if ($md && !-d $md) {
	# Create the Maildir, owned by the user
	local $d;
	foreach $d ($md, "$md/cur", "$md/tmp", "$md/new") {
		&make_dir($d, 0700, 1);
		&set_ownership_permissions($uid, $gid, undef, $d);
		}
	@rv = ( $md, 1 );
	}

if (-d $_[0]->{'home'} && $_[0]->{'unix'}) {
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
		local $umail = "$_[0]->{'home'}/$umd";
		if (!-d $umail) {
			&make_dir($umail, 0755);
			&set_ownership_permissions($uid, $gid, undef, $umail);
			}
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
	local $pfx = &qmailadmin::get_control_file("ldapmessagestore");
	return $pfx."/".$_[0];
	}
}

# delete_mail_file(&user)
sub delete_mail_file
{
&require_mail();
local $umf = &user_mail_file($_[0]);
if ($umf) {
	&system_logged("rm -rf ".quotemeta($umf));
	}
}

# rename_mail_file(&user, &olduser)
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
# Returns the full path a user's mail file, and the type
sub user_mail_file
{
&require_mail();
local @rv;
if ($config{'mail_system'} == 1) {
	# Just look at the Sendmail mail file
	@rv = ( &sendmail::user_mail_file($_[0]->{'user'}), 0 );
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
	@rv = ( "$_[0]->{'home'}/Maildir", 1 );
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
		return ($sendmail::config{'mail_dir'},
			$sendmail::config{'mail_style'}, undef, undef);
		}
	else {
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
	return "$config{'vpopmail_dir'}/domains/$_[0]->{'dom'}";
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
			       $_[0]->{'user'}."\@".$_[1]->{'dom'};
			}
		else {
			return "../mailboxes/list_mail.cgi?user=".
			       $_[0]->{'user'};
			}
		}
	else {
		# Access mail file directly
		return "../mailboxes/list_mail.cgi?user=".
			&urlize(user_mail_file($_[0]));
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
# Checks if an alias with the given name already exists
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
	local @aliases = &postfix::list_aliases($postfix_afiles);
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

# Copy plain text passwords file too
if (-r "$plainpass_dir/$_[0]->{'id'}") {
	&copy_source_dest("$plainpass_dir/$_[0]->{'id'}", "$_[1]_plainpass");
	}

&$second_print($text{'setup_done'});

if (!&mail_under_home() && $_[2]->{'mailfiles'}) {
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
		&execute_command("cd '$mbase'; tar cf '$_[1]_files' $mfiles",
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

return 1;
}

# restore_mail(&domain, file, &options, &all-options)
sub restore_mail
{
local ($u, %olduid, @errs);
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
		local %old = %$uinfo;
		$uinfo->{'email'} = $user[7];
		$uinfo->{'to'} = \@to;
		&modify_user($uinfo, \%old, $_[0]);
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

		&create_user($uinfo, $_[0]);
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
	local $_;
	open(AFILE, "$_[1]_aliases");
	while(<AFILE>) {
		if (/^(\S+):\s*(.*)/) {
			local $virt = { 'from' => $1,
					'to' => [ split(/,/, $2) ] };
			if ($virt->{'to'}->[0] =~ /^(\S+)\\@(\S+)$/ &&
			    $config{'mail_system'} == 0) {
				# Virtusers is to a local user with an @ in
				# the name, like foo\@bar.com. But on Postfix
				# this won't work - instead, we need to use the
				# alternate foo-bar.com format.
				$virt->{'to'}->[0] = $1."-".$2;
				}
			&create_virtuser($virt);
			}
		}
	close(AFILE);
	&$second_print($text{'setup_done'});
	}

if (-r "$_[1]_files" && $_[2]->{'mailfiles'} &&
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
	else {
		&$second_print($text{'setup_done'});
		}

	if (&mail_under_home()) {
		# Move mail from temp directory to homes
		&foreign_require("mailboxes", "mailboxes-lib.pl");
		local @users = &list_domain_users($_[0]);
		if ($_[2]->{'mailuser'}) {
			@users = grep { $_->{'user'} eq $foundmailuser } @users;
			}
		foreach my $u (@users) {
			local $path = "$xtract/$u->{'user'}";
			local $sf = { 'type' => -d $path ? 1 : 0,
				      'file' => $path };
			local ($df) =
				&mailboxes::list_user_folders($u->{'user'});
			&mailboxes::mailbox_empty_folder($df);
			&mailboxes::mailbox_copy_folder($sf, $df);
			}
		}
	}
# XXX deal with case where old system used ~/Maildir and this one uses /var/mail

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

return 1;
}

# show_backup_mail(&options)
# Returns HTML for mail backup option inputs
sub show_backup_mail
{
if (&mail_under_home()) {
	# Option makes no sense in this case, as the home directories backup
	# will catch it
	return "<input type=hidden name=mail_mailfiles value='$opts{'mailfiles'}'>";
	}
else {
	# Offer to backup mail files
	return sprintf
		"(<input type=checkbox name=mail_mailfiles value=1 %s> %s)",
		$opts{'mailfiles'} ? "checked" : "", $text{'backup_mailfiles2'};
	}
}

# parse_backup_mail(&in)
# Parses the inputs for mail backup options
sub parse_backup_mail
{
local %in = %{$_[0]};
return { 'mailfiles' => $in{'mail_mailfiles'} };
}

# show_restore_mail(&options, &domain)
# Returns HTML for mail restore option inputs
sub show_restore_mail
{
local $rv;
if (&mail_under_home()) {
	# Option makes no sense in this case, as the home directories backup
	# will catch it
	$rv = &ui_hidden("mail_mailfiles", $_[0]->{'mailfiles'});
	}
else {
	# Offer to restore mail files
	$rv = &ui_checkbox("mail_mailfiles", 1, $text{'restore_mailfiles2'},
			   $_[0]->{'mailfiles'});
	}
if ($_[1]) {
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
return { 'mailfiles' => $in{'mail_mailfiles'},
	 'mailuser' => $in{'mail_mailuser'} };
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
	local @aliases = &postfix::list_aliases($postfix_afiles);
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
	}
elsif ($config{'mail_system'} == 0) {
	@virtual_map_files || return $text{'setup_epostfixvfile'};
	@$postfix_afiles || return $text{'setup_epostfixafile'};
	}
if ($_[0]->{'alias'}) {
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
require 'timelocal.pl';

# Build a map from domain names to objects
local %maildoms;
foreach my $d (@$doms) {
	$maildoms{$d->{'dom'}} = $d;
	foreach my $md (split(/\s+/, $d->{'bw_maildoms'})) {
		$maildoms{$md} = $d;
		}
	}

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
	local %sizes;
	local $now = time();
	local @tm = localtime($now);
	while(<LOG>) {
		# Sendmail / postfix formats
		s/\r|\n//g;
		if (/^(\S+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\S+)\s+(\S+):\s+(\S+):\s+from=(\S+),\s+size=(\d+)/) {
			# The initial From: line that contains the size
			$sizes{$8} = $10;
			}
		elsif (/^(\S+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\S+)\s+(\S+):\s+(\S+):\s+to=(\S+),(\s+orig_to=(\S+))?/) {
			# A To: line that has the local recipient
			local $ltime = timelocal($5, $4, $3, $2,
			    $apache_mmap{lc($1)}, $tm[5]);
			if ($ltime > $now+(24*60*60)) {
				# Must have been last year!
				$ltime = timelocal($5, $4, $3, $2,
				     $apache_mmap{lc($1)}, $tm[5]-1);
				}
			local $user = $11 || $9;
			local $sz = $sizes{$8};
			$user =~ s/^<(.*)>/$1/;
			$user =~ s/,$//;
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
					# To a user in a hosted domain
					local $day =
					    int($ltime / (24*60*60));
					$bws->{$md->{'id'}}->
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
	     $config{'mail_system'} == 1 ? "sendmail" : "qmailadmin";
local $ms = $text{'mail_system_'.$config{'mail_system'}};
local @rv;
if (defined($typestatus->{$msn}) ? $typestatus->{$msn} == 1
				 : &is_mail_running()) {
	push(@rv,{ 'status' => 1,
		   'name' => &text('index_mname', $ms),
		   'desc' => $text{'index_mstop'},
		   'restartdesc' => $text{'index_mrestart'},
		   'longdesc' => $text{'index_mstopdesc'} } );
	}
else {
	push(@rv,{ 'status' => 0,
		   'name' => &text('index_mname', $ms),
		   'desc' => $text{'index_mstart'},
		   'longdesc' => $text{'index_mstartdesc'} } );
	}
if (&foreign_installed("dovecot")) {
	# Add status for Dovecot
	&foreign_require("dovecot", "dovecot-lib.pl");
	if (&dovecot::is_dovecot_running()) {
		push(@rv,{ 'status' => 1,
			   'feature' => 'dovecot',
			   'name' => &text('index_dname', $ms),
			   'desc' => $text{'index_dstop'},
			   'restartdesc' => $text{'index_drestart'},
			   'longdesc' => $text{'index_dstopdesc'} } );
		}
	else {
		push(@rv,{ 'status' => 0,
			   'feature' => 'dovecot',
			   'name' => &text('index_dname', $ms),
			   'desc' => $text{'index_dstart'},
			   'longdesc' => $text{'index_dstartdesc'} } );
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
&require_mail();
if ($config{'mail_system'} == 1) {
	# Just add to sendmail relay domains file
	local $conf = &sendmail::get_sendmailcf();
	local $cwfile;
	local @dlist = &sendmail::get_file_or_config($conf, "R", undef,
						     \$cwfile);
	if (&indexof(lc($dom), (map { lc($_) } @dlist)) >= 0) {
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
	local @rd = split(/[, ]+/,&postfix::get_current_value("relay_domains"));
	if (&indexof(lc($dom), (map { lc($_) } @rd)) >= 0) {
		return $text{'newmxs_already'};
		}
	@rd = &unique(@rd, $dom);
	&lock_file($postfix::config{'postfix_config_file'});
	&postfix::set_current_value("relay_domains", join(", ", @rd));
	&unlock_file($postfix::config{'postfix_config_file'});
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
	local @rd = split(/[, ]+/,&postfix::get_current_value("relay_domains"));
	local $idx = &indexof(lc($dom), (map { lc($_) } @rd));
	if ($idx < 0) {
		return $text{'newmxs_missing'};
		}
	splice(@rd, $idx, 1);
	&lock_file($postfix::config{'postfix_config_file'});
	&postfix::set_current_value("relay_domains", join(", ", @rd));
	&unlock_file($postfix::config{'postfix_config_file'});
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
local ($dom) = @_;
local @servers = &list_mx_servers();
return if (!@servers);
local @okservers;
&$first_print(&text('setup_mxs',
		join(", ", map { "<tt>$_->{'host'}</tt>" } @servers)));
local @errs;
foreach my $s (@servers) {
	local $err = &setup_one_secondary($dom, $s);
	if ($err) {
		push(@errs, "$s->{'host'} : $err");
		}
	else {
		push(@okservers, $s);
		}
	}
$dom->{'mx_servers'} = join(" ", map { $_->{'id'} } @okservers);
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
		join(", ", map { "<tt>$_->{'host'}</tt>" } @servers)));
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
local $atable = &ui_columns_start([ $text{'tmpl_aliasfrom'}, $text{'tmpl_aliasto'} ]);
local $i = 0;
local @dafields;
foreach my $a (@aliases, undef, undef) {
	local ($from, $to) = split(/=/, $a, 2);
	$atable .= &ui_columns_row([
		&ui_textbox("alias_from_$i", $from, 20),
		&ui_textbox("alias_to_$i", $to, 40) ]);
	push(@dafields, "alias_from_$i", "alias_to_$i");
	$i++;
	}
$atable .= &ui_columns_end();
$atable .= &ui_checkbox("bouncealias", 1,
		        &hlink("<b>$text{'tmpl_bouncealias'}</b>",
		               "template_bouncealias"),
		        $tmpl->{'dom_aliases_bounce'});
push(@dafields, "bouncealias");
print &ui_table_row(&hlink($text{'tmpl_domaliases'},
                           "template_domaliases_mode"),
		    &none_def_input("domaliases", $tmpl->{'dom_aliases'},
				    $text{'tmpl_aliasbelow'}, 0, 0, undef,
				    \@dafields)."\n".$atable);

# Unix groups for mail, FTP and DB users
print &ui_table_hr();
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
			 [ 6, "username\@domain" ] ]));
}

# parse_template_mail(&tmpl)
# Updates email and mailbox related template options from %in
sub parse_template_mail
{
local ($tmpl) = @_;

# Save mail settings
$tmpl->{'mail_on'} = $in{'mail_mode'} == 0 ? "none" :
		     $in{'mail_mode'} == 1 ? "" : "yes";
$in{'mail'} =~ s/\r//g;
$tmpl->{'mail'} = $in{'mail'};
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
if ($in{'domaliases_mode'} != 1) {
	$tmpl->{'dom_aliases_bounce'} = $in{'bouncealias'};
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

# create_generic(user, email)
# Adds an entry to the systems outgoing addresses file, if active
sub create_generic
{
local ($user, $email) = @_;
if ($config{'mail_system'} == 1) {
	local $gen = { 'from' => $user, 'to' => $email };
	&lock_file($sendmail_gfile);
	&sendmail::create_generic($gen, $sendmail_gfile,
				  $sendmail_gdbm, $sendmail_gdbmtype);
	&unlock_file($sendmail_gfile);
	}
elsif ($config{'mail_system'} == 0) {
	local $gen = { 'name' => $user,
		       'value' => $email };
	&lock_file($canonical_map_files[0]);
	&create_replace_mapping($canonical_type, $gen);
	&unlock_file($canonical_map_files[0]);
	&postfix::regenerate_canonical_table();
	}
}

# delete_generic(&generic)
# Removes one outgoing addresses table entry
sub delete_generic
{
local ($generic) = @_;
if ($config{'mail_system'} == 1) {
	# For sendmail
	&lock_file($sendmail_gfile);
	&sendmail::delete_generic($generic, $sendmail_gfile,
			$sendmail_gdbm, $sendmail_gdbmtype);
	&unlock_file($sendmail_gfile);
	}
elsif ($config{'mail_system'} == 0) {
	# For postfix
	&lock_file($canonical_map_files[0]);
	&postfix::delete_mapping($canonical_type, $generic);
	&unlock_file($canonical_map_files[0]);
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
if ($clash) {
	&delete_virtuser($clash);
	}
&create_virtuser($virt);
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
	foreach my $f (@feature_plugins) {
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

$done_feature_script{'mail'} = 1;

1;

