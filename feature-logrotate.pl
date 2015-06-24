# Functions for managing logrotate

sub require_logrotate
{
return if ($require_logrotate++);
&foreign_require("logrotate", "logrotate-lib.pl");
}

sub check_depends_logrotate
{
local ($d) = @_;
if (!&domain_has_website($d)) {
	return $text{'setup_edeplogrotate'};
	}
return undef;
}

# setup_logrotate(&domain)
# Create logrotate entries for the server's access and error logs
sub setup_logrotate
{
&$first_print($text{'setup_logrotate'});
&require_logrotate();
&require_apache();
&obtain_lock_logrotate($_[0]);
local $tmpl = &get_template($_[0]->{'template'});

# Work out the log files we are rotating
local @logs = &get_all_domain_logs($_[0]);
local @tmpllogs = &get_domain_template_logs($_[0]);
if (@logs) {
	# Check if any are already rotated
	local $parent = &logrotate::get_config_parent();
	foreach my $c (@{$parent->{'members'}}) {
		foreach my $n (@{$c->{'name'}}) {
			if (&indexof($n, @logs) >= 0) {
				# Clash!!
				&error(&text('setup_clashlogrotate',
					     "<tt>$n</tt>"));
				}
			}
		}

	# If in single config mode, check if there is a block for Virtualmin
	# already (based on the directory)
	local $logdir = $logs[0];
	$logdir =~ s/\/[^\/]+$//;
	local $already;
	if ($tmpl->{'logrotate_shared'} eq 'yes' &&
	    $logs[0] !~ /^\Q$d->{'home'}\E\//) {
		LOGROTATE: foreach my $c (@{$parent->{'members'}}) {
			foreach my $n (@{$c->{'name'}}) {
				if ($n =~ /^\Q$logdir\E\/[^\/]+$/) {
					$already = $c;
					last LOGROTATE;
					}
				}
			}
		}

	if (!$already) {
		# Add the new section
		local $lconf = { 'file' => &logrotate::get_add_file($_[0]->{'dom'}),
				 'name' => \@logs };
		local $newfile = !-r $lconf->{'file'};
		if ($tmpl->{'logrotate'} eq 'none') {
			# Use automatic configurtation
			local $script = &get_postrotate_script($_[0]);
			$lconf->{'members'} = [
					{ 'name' => 'rotate',
					  'value' => $config{'logrotate_num'} || 5 },
					{ 'name' => 'weekly' },
					{ 'name' => 'compress' },
					{ 'name' => 'postrotate',
					  'script' => $script },
					{ 'name' => 'sharedscripts' },
					];
			}
		else {
			# Use manually defined directives
			local $temp = &transname();
			local $txt = $tmpl->{'logrotate'};
			$txt =~ s/\t/\n/g;
			&open_tempfile(TEMP, ">$temp");
			&print_tempfile(TEMP, "/dev/null {\n");
			&print_tempfile(TEMP,
				&substitute_domain_template($txt, $_[0])."\n");
			&print_tempfile(TEMP, "}\n");
			&close_tempfile(TEMP);
			local $tconf = &logrotate::get_config($temp);
			$lconf->{'members'} = $tconf->[0]->{'members'};
			unlink($temp);
			$d->{'logrotate_shared'} = 1;
			}
		&logrotate::save_directive($parent, undef, $lconf);
		&flush_file_lines($lconf->{'file'});
		if ($newfile) {
			&set_ownership_permissions(undef, undef, 0644,
						   $lconf->{'file'});
			}
		}
	else {
		# Add to existing section
		push(@{$already->{'name'}}, @logs);
		&logrotate::save_directive($parent, $already, $already);
		&flush_file_lines($already->{'file'});
		}

	# Make sure extra log files actually exist
	foreach my $lt (@tmpllogs) {
		if (!-e $lt) {
			&open_tempfile_as_domain_user($_[0], TOUCHLOG,
						      ">$lt", 1, 1);
			&close_tempfile_as_domain_user($_[0], TOUCHLOG);
			&set_permissions_as_domain_user(
				$_[0], 0777, $lt);
			}
		}

	&$second_print($text{'setup_done'});
	}
else {
	&$second_print($text{'setup_nolog'});
	}
&release_lock_logrotate($_[0]);
}

# modify_logrotate(&domain, &olddomain)
# Adjust path if home directory has changed
sub modify_logrotate
{
# Work out old and new Apache logs
local $alog = &get_website_log($_[0], 0);
local $oldalog = &get_old_website_log($alog, $_[0], $_[1]);
local $elog = &get_website_log($_[0], 1);
local $oldelog = &get_old_website_log($elog, $_[0], $_[1]);

# Stop here if nothing to do
return if ($alog eq $oldalog && $elog eq $oldelog &&
	   $_[0]->{'user'} eq $_[1]->{'user'} &&
	   $_[0]->{'group'} eq $_[1]->{'group'});
&require_logrotate();
&obtain_lock_logrotate($_[0]);

# Change log paths if needed
if ($alog ne $oldalog || $elog ne $oldelog) {
	&$first_print($text{'save_logrotate'});

	# Fix up the logrotate section for the old file
	local $lconf = &get_logrotate_section($oldalog);
	if ($lconf) {
		local $parent = &logrotate::get_config_parent();
		foreach my $n (@{$lconf->{'name'}}) {
			$n = $alog if ($alog && $n eq $oldalog);
			$n = $elog if ($elog && $n eq $oldelog);
			}
		&logrotate::save_directive($parent, $lconf, $lconf);
		&flush_file_lines($lconf->{'file'});
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print($text{'setup_nologrotate'});
		}
	}

# Change references to home dir
if ($_[0]->{'home'} ne $_[1]->{'home'}) {
	&$first_print($text{'save_logrotatehome'});
	local $lconf = &get_logrotate_section($alog);
	if ($lconf) {
                local $parent = &logrotate::get_config_parent();
		foreach my $n (@{$lconf->{'name'}}) {
			$n =~ s/\Q$_[1]->{'home'}\E\//$_[0]->{'home'}\//;
			}
		&logrotate::save_directive($parent, $lconf, $lconf);
		&flush_file_lines($lconf->{'file'});
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print($text{'setup_nologrotate'});
		}
	}

# Change references to user or group
if ($_[0]->{'user'} ne $_[1]->{'user'} ||
    $_[0]->{'group'} ne $_[1]->{'group'}) {
	&$first_print($text{'save_logrotateuser'});
	local $lconf = &get_logrotate_section($alog);
	if ($lconf) {
		&modify_user_logrotate($_[0], $_[1], $lconf);
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print($text{'setup_nologrotate'});
		}
	}

&release_lock_logrotate($_[0]);
}

# delete_logrotate(&domain)
# Remove logrotate section for this domain
sub delete_logrotate
{
local ($d) = @_;
&require_logrotate();
&$first_print($text{'delete_logrotate'});
&obtain_lock_logrotate($d);
local $lconf = &get_logrotate_section($d);
local $parent = &logrotate::get_config_parent();
if ($lconf) {
	# Check if all log files in the section are related to the domain
	local %logs = map { $_, 1 } &get_all_domain_logs($d);
	local @leftover = grep { !$logs{$_} } @{$lconf->{'name'}};
	if (@leftover) {
		# Just remove some log files, but leave the block
		$lconf->{'name'} = \@leftover;
		&logrotate::save_directive($parent, $lconf, $lconf);
		&flush_file_lines($lconf->{'file'});
		}
	else {
		# Remove the whole logrotate block
		&logrotate::save_directive($parent, $lconf, undef);
		&flush_file_lines($lconf->{'file'});
		undef($logrotate::get_config_parent_cache);
		undef(%logrotate::get_config_cache);
		undef(%logrotate::get_config_lnum_cache);
		undef(%logrotate::get_config_files_cache);
		&logrotate::delete_if_empty($lconf->{'file'});
		}
	&$second_print($text{'setup_done'});
	}
else {
	&$second_print($text{'setup_nologrotate'});
	}
delete($d->{'logrotate_shared'});
&release_lock_logrotate($d);
}

# clone_logrotate(&domain, &old-domain)
# Copy logrotate directives to a new domain
sub clone_logrotate
{
local ($d, $oldd) = @_;
&obtain_lock_logrotate($d);
&$first_print($text{'clone_logrotate'});
local $lconf = &get_logrotate_section($d);
local $olconf = &get_logrotate_section($oldd);
if (!$olconf) {
	&$second_print($text{'clone_logrotateold'});
	return 0;
	}
if (!$lconf) {
	&$second_print($text{'clone_logrotatenew'});
	return 0;
	}
&require_logrotate();

# Splice across the lines
local $lref = &read_file_lines($lconf->{'file'});
local $olref = &read_file_lines($olconf->{'file'});
local @lines = @$olref[$olconf->{'line'}+1 .. $olconf->{'eline'}-1];
splice(@$lref, $lconf->{'line'}+1,
       $lconf->{'eline'}-$lconf->{'line'}-1, @lines);
&flush_file_lines($lconf->{'file'});
undef($logrotate::get_config_parent_cache);
undef(%logrotate::get_config_cache);
undef(%logrotate::get_config_lnum_cache);
undef(%logrotate::get_config_files_cache);

# Fix username if changed
if ($d->{'user'} ne $oldd->{'user'}) {
	local $lconf = &get_logrotate_section($d);
	&modify_user_logrotate($d, $oldd, $lconf);
	}

&release_lock_logrotate($d);
&$second_print($text{'setup_done'});
return 1;
}

# validate_logrotate(&domain)
# Returns an error message if a domain's logrotate section is not found
sub validate_logrotate
{
local ($d) = @_;
local $log = &get_website_log($d);
return &text('validate_elogfile', "<tt>$d->{'dom'}</tt>") if (!$log);
local $lconf = &get_logrotate_section($d);
return &text('validate_elogrotate', "<tt>$log</tt>") if (!$lconf);
return undef;
}

# get_logrotate_section(&domain|log-file)
# Returns the Logrotate configuration block for some domain or log file
sub get_logrotate_section
{
&require_logrotate();
&require_apache();
local $alog = ref($_[0]) ? &get_website_log($_[0]) : $_[0];
if (!$alog && ref($_[0])) {
	# Website may have been already deleted, so we don't know the log
	# file path! Try the template default.
	$alog = &get_apache_template_log($_[0]);
	}
local $conf = &logrotate::get_config();
local ($c, $n);
foreach $c (@$conf) {
	foreach $n (@{$c->{'name'}}) {
		return $c if ($n eq $alog);
		}
	}
return undef;
}

# check_logrotate_clash()
# No need to check for clashes ..
sub check_logrotate_clash
{
return 0;
}

# backup_logrotate(&domain, file)
# Saves the log rotation section for this domain to a file
sub backup_logrotate
{
local ($d, $file) = @_;
&$first_print($text{'backup_logrotatecp'});
local $lconf = &get_logrotate_section($d);
if ($lconf) {
	local $lref = &read_file_lines($lconf->{'file'});
	&open_tempfile_as_domain_user($d, FILE, ">$file");
	foreach my $l (@$lref[$lconf->{'line'} .. $lconf->{'eline'}]) {
		&print_tempfile(FILE, "$l\n");
		}
	&close_tempfile_as_domain_user($d, FILE);
	&$second_print($text{'setup_done'});
	return 1;
	}
else {
	&$second_print($text{'setup_nologrotate'});
	return 0;
	}
}

# restore_logrotate(&domain, file, &options, &all-options, home-format,
#		    &olddomain)
sub restore_logrotate
{
&$first_print($text{'restore_logrotatecp'});
local $tmpl = &get_template($_[0]->{'template'});
if ($d->{'logrotate_shared'}) {
	&$second_print($text{'restore_logrotatecpshared'});
	return 1;
	}
&obtain_lock_logrotate($_[0]);
local $lconf = &get_logrotate_section($_[0]);
local $rv;
if ($lconf) {
	local $srclref = &read_file_lines($_[1]);
	local $dstlref = &read_file_lines($lconf->{'file'});
	splice(@$dstlref, $lconf->{'line'}+1,
	       $lconf->{'eline'}-$lconf->{'line'}-1,
	       @$srclref[1 .. @$srclref-2]);
	my @range = ($lconf->{'line'} .. $lconf->{'line'}+scalar(@$srclref)-1);
	if ($_[5]->{'home'} && $_[5]->{'home'} ne $_[0]->{'home'}) {
		# Fix up any references to old home dir
		foreach my $i (@range) {
			$dstlref->[$i] =~ s/(^|\s)$_[5]->{'home'}/$1$_[0]->{'home'}/g;
			}
		}

	# Replace the old postrotate block with the config from this system
	foreach my $i (@range) {
		if ($dstlref->[$i] =~ /^\s*postrotate/) {
			$dstlref->[$i+1] = "\t".&get_postrotate_script($_[0]);
			last;
			}
		}

	&flush_file_lines($lconf->{'file'});
	undef($logrotate::get_config_parent_cache);
	undef($logrotate::get_config_cache);
	&$second_print($text{'setup_done'});
	$rv = 1;
	}
else {
	&$second_print($text{'setup_nologrotate'});
	$rv = 0;
	}
&release_lock_logrotate($_[0]);
return $rv;
}

# sysinfo_logrotate()
# Returns the Logrotate version
sub sysinfo_logrotate
{
&require_logrotate();
$logrotate::logrotate_version ||= &logrotate::get_logrotate_version();
return ( [ $text{'sysinfo_logrotate'}, $logrotate::logrotate_version ] );
}

# check_logrotate_template([directives])
# Returns an error message if the default Logrotate directives don't look valid
sub check_logrotate_template
{
local ($d, $gotpostrotate);
local @dirs = split(/\t+/, $_[0]);
foreach $d (@dirs) {
	if ($d =~ /\s*postrotate/) {
		$gotpostrotate = 1;
		}
	}
$gotpostrotate || return $text{'lcheck_epost'};
return undef;
}

# show_template_logrotate(&tmpl)
# Outputs HTML for editing Logrotate related template options
sub show_template_logrotate
{
local ($tmpl) = @_;

# Use shared logrotate config
print &ui_table_row(
	&hlink($text{'tmpl_logrotate_shared'}, "template_logrotate_shared"),
	&ui_radio("logrotate_shared", $tmpl->{'logrotate_shared'},
	  [ $tmpl->{'default'} ? ( ) : ( [ "", $text{'tmpl_default'} ] ),
	    [ "no", $text{'tmpl_logrotate_shared0'} ],
	    [ "yes", $text{'tmpl_logrotate_shared1'} ] ]));

# Logrotate directives
print &ui_table_row(
	&hlink($text{'tmpl_logrotate'}, "template_logrotate"),
	&none_def_input("logrotate", $tmpl->{'logrotate'},
			$text{'tmpl_ftpbelow'}, 0, 0,
			$text{'tmpl_logrotatenone'},
			[ "logrotate" ])."<br>\n".
	&ui_textarea("logrotate",
		$tmpl->{'logrotate'} eq "none" ? undef :
		  join("\n", split(/\t/, $tmpl->{'logrotate'})),
		5, 60));

# Additional files to rotate
print &ui_table_row(
        &hlink($text{'tmpl_logrotate_files'}, "template_logrotatefiles"),
	&none_def_input("logrotate_files", $tmpl->{'logrotate_files'},
			$text{'tmpl_ftpbelow2'}, 0, 0,
                        $text{'tmpl_logrotatenone2'},
			[ "logrotate_files" ])."<br>\n".
	&ui_textarea("logrotate_files",
		     $tmpl->{'logrotate_files'} eq 'none' ? '' :
		       join("\n", split(/\t+/, $tmpl->{'logrotate_files'})),
		     5, 60));
}

# parse_template_logrotate(&tmpl)
# Updates Logrotate related template options from %in
sub parse_template_logrotate
{
local ($tmpl) = @_;

# Save logrotate settings
$tmpl->{'logrotate_shared'} = $in{'logrotate_shared'};
$tmpl->{'logrotate'} = &parse_none_def("logrotate");
if ($in{"logrotate_mode"} == 2) {
	local $err = &check_logrotate_template($in{'logrotate'});
	&error($err) if ($err);
	}

$tmpl->{'logrotate_files'} = &parse_none_def("logrotate_files");
}

# chained_logrotate(&domain, [&old-domain])
# Logrotate is automatically enabled when a website is, if set to always mode
# and if the website is just being turned on now.
sub chained_logrotate
{
local ($d, $oldd) = @_;
if ($config{'logrotate'} != 3) {
	# Not in auto mode, so don't touch
	return undef;
	}
elsif ($d->{'alias'} || $d->{'subdom'}) {
	# These types never have logs
	return 0;
	}
elsif (&domain_has_website($d)) {
	if (!$oldd || !&domain_has_website($oldd)) {
		# Turning on web, so turn on logrotate
		return 1;
		}
	else {
		# Don't do anything
		return undef;
		}
	}
else {
	# Always off when web is
	return 0;
	}

return &domain_has_website($d) &&
       (!$oldd || !&domain_has_website($oldd)) &&
       !$d->{'alias'} && !$d->{'subdom'} &&
       $config{'logrotate'} == 3;
}

# modify_user_logrotate(&domain, &old-domain, &logrotate-config)
# Change the user and group names in a logrotate config
sub modify_user_logrotate
{
local ($d, $oldd, $lconf) = @_;
local $create = &logrotate::find_value("create", $lconf->{'members'});
if ($create =~ /^(\d+)\s+(\S+)\s+(\S+)$/) {
	local ($p, $u, $g) = ($1, $2, $3);
	$u = $d->{'user'} if ($u eq $oldd->{'user'});
	$g = $d->{'group'} if ($g eq $oldd->{'group'});
	&logrotate::save_directive($lconf, "create",
		{ 'name' => 'create',
		  'value' => join(" ", $p, $u, $g) }, "\t");
	&flush_file_lines($lconf->{'file'});
	}
}

# Lock the logrotate config files
sub obtain_lock_logrotate
{
return if (!$config{'logrotate'});
&obtain_lock_anything();
if ($main::got_lock_logrotate == 0) {
	&require_logrotate();
	&lock_file($logrotate::config{'add_file'})
		if ($logrotate::config{'add_file'});
	&lock_file($logrotate::config{'logrotate_conf'});
	undef($logrotate::get_config_cache);
	}
$main::got_lock_logrotate++;
}

# Unlock all logrotate config files
sub release_lock_logrotate
{
return if (!$config{'logrotate'});
if ($main::got_lock_logrotate == 1) {
	&require_logrotate();
	&unlock_file($logrotate::config{'add_file'})
		if ($logrotate::config{'add_file'});
	&unlock_file($logrotate::config{'logrotate_conf'});
	}
$main::got_lock_logrotate-- if ($main::got_lock_logrotate);
&release_lock_anything();
}

# get_postrotate_script(&domain)
# Returns the script (as a string) for running after rotation
sub get_postrotate_script
{
local ($d) = @_;
local $p = &domain_has_website($d);
local $script;
if ($p eq 'web') {
	# Get restart command from Apache
	local $apachectl = $apache::config{'apachectl_path'} ||
			   &has_command("apachectl") ||
			   &has_command("apache2ctl") ||
			   "apachectl";
	local $apply_cmd = $apache::config{'apply_cmd'};
	$apply_cmd = undef if ($apply_cmd eq 'restart');
	$script = $apache::config{'graceful_cmd'} ||
		  $apply_cmd ||
		  "$apachectl graceful";
	$script .= " ; sleep 5";
	}
else {
	# Ask plugin
	$script = &plugin_call($p, "feature_restart_web_command", $d);
	}
return $script;
}

# get_all_domain_logs(&domain)
# Returns all logs that should be rotated for a domain
sub get_all_domain_logs
{
local ($d) = @_;
local $alog = &get_website_log($d, 0);
local $elog = &get_website_log($d, 1);
local @logs = ( $alog, $elog );
if ($d->{'ftp'}) {
	push(@logs, &get_proftpd_log($d->{'ip'}));
	}
push(@logs, &get_domain_template_logs($d));
return &unique(grep { $_ } @logs);
}

# get_domain_template_logs(&domain)
# Returns extra logs from a domain's template 
sub get_domain_template_logs
{
local ($d) = @_;
local $tmpl = &get_template($d->{'template'});
local @tmpllogs;
foreach my $lt (split(/\t+/, $tmpl->{'logrotate_files'})) {
	if ($lt && $lt ne "none") {
		push(@tmpllogs, &substitute_domain_template($lt, $d));
		}
	}
return @tmpllogs;
}

$done_feature_script{'logrotate'} = 1;

1;

