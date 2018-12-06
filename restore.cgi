#!/usr/local/bin/perl
# Actually restore some servers, after asking for confirmation

require './virtual-server-lib.pl';
$crmode = &can_restore_domain();
$crmode || &error($text{'restore_ecannot'});
$safe_backup = $crmode == 1 ? 1 : 0;
&ReadParseMime();

# Work out the current user's main domain, if needed
if ($crmode == 2) {
	$d = &get_domain_by_user($base_remote_user);
	}

# Validate inputs, starting with source
&error_setup($text{'restore_err'});
if ($in{'log'}) {
	# Restoring a logged backup
	$log = &get_backup_log($in{'log'});
	$log || &error($text{'viewbackup_egone'});
	&can_backup_log($log) || &error($text{'viewbackup_ecannot'});
	$src = $log->{'dest'};

	# Can all features of this backup be restored? Only true for backups
	# created by root
	$safe_backup = $log->{'owner'} ne $remote_user ||
		       $log->{'ownrestore'};
	}
elsif ($in{'src'}) {
	$src = $in{'src'};
	}
else {
	# Restoring from user-entered source
	$src = &parse_backup_destination("src", \%in, $crmode == 2, $d, undef);
	}
$origsrc = $in{'origsrc'} || $src;
$nice = &nice_backup_url($src);
if ($src eq "upload:") {
	# Special case - uploaded data, which we need to save locally
	$fn = $in{'src_upload_filename'};
	$fn =~ s/^.*[\\\/]//;
	if ($d) {
		# In domain's home dir
		$bdir = "$d->{'home'}/$home_virtualmin_backup";
		if (!-d $bdir) {
			&make_dir_as_domain_user($d, $bdir, 0700);
			}
		$temp = "$bdir/$fn";
		&open_tempfile_as_domain_user($d, TEMP, ">$temp", 0, 1);
		&print_tempfile(TEMP, $in{'src_upload'});
		&close_tempfile_as_domain_user($d, TEMP);
		&set_ownership_permissions(undef, undef, 0700, $temp);
		}
	else {
		# In /tmp/.webmin
		$temp = &tempname($fn);
		&open_tempfile(TEMP, ">$temp", 0, 1);
		&print_tempfile(TEMP, $in{'src_upload'});
		&close_tempfile(TEMP);
		&set_ownership_permissions(undef, undef,
			$safe_backup ? 0700 : 0755, $temp);
		}
	$src = $temp;
	}
($mode) = &parse_backup_url($src);
$mode > 0 || -r $src || -d $src || &error($text{'restore_esrc'});

# Get the backup key
$key = undef;
if (defined(&get_backup_key)) {
	if ($in{'key'}) {
		# User selected key
		$key = &get_backup_key($in{'key'});
		$key || &error($text{'backup_ekey'});
		&can_backup_key($key) || &error($text{'backup_ekeycannot'});
		}
	elsif ($log && $log->{'key'}) {
		# Key from the logged backup
		$key = &get_backup_key($log->{'key'});
		$key || &error($text{'backup_ekey'});
		}
	}

# Parse features
if ($in{'feature_all'}) {
	# All features usable by current user
	@do_features = &get_available_backup_features(!$safe_backup);
	foreach my $f (&list_backup_plugins()) {
		push(@do_features, $f);
		}
	if (!$safe_backup) {
		@do_features = grep {
			&indexof($_, @safe_backup_features) >= 0 ||
			&plugin_call($_, "feature_backup_safe") } @do_features;
		}
	}
else {
	# Selected features
	@do_features = split(/\0/, $in{'feature'});
	@do_features || &error($text{'restore_efeatures'});
	if (!$safe_backup) {
		# Make sure they are all safe
		foreach my $f (@do_features) {
			&indexof($f, @safe_backup_features) >= 0 ||
			  &plugin_call($f, "feature_backup_safe") ||
			    &error(&text('restore_eunsafe', $f));
			}
		}
	}
%do_features = map { $_, 1 } @do_features;

# Parse virtualmin configs to restore
if (&can_backup_virtualmin()) {
	@vbs = split(/\0/, $in{'virtualmin'});
	%vbs = map { $_, 1 } @vbs;
	}

# Parse option inputs
foreach $f (@do_features) {
	local $ofunc = "parse_restore_$f";
	if (defined(&$ofunc)) {
		$options{$f} = &$ofunc(\%in);
		}
	}

# Parse creation options
if ($crmode == 1) {
	$options{'reuid'} = $in{'reuid'};
	$options{'fix'} = $in{'fix'};

	# Parse IP inputs
	$ipinfo = { };
	$tmpl = &get_template(0);
	if (&can_select_ip() && $in{'virt'} != -1) {
		# Different IPv4 address selected
		($ip, $virt, $virtalready, $netmask) =
			&parse_virtual_ip($tmpl, undef);
		$ipinfo->{'ip'} = $ip;
		$ipinfo->{'virt'} = $virt;
		$ipinfo->{'mode'} = $in{'virt'};
		$ipinfo->{'virtalready'} = $virtalready;
		$ipinfo->{'netmask'} = $netmask;
		}
	if (&can_select_ip6() && &supports_ipv6() && $in{'virt6'} != -1) {
		# Different IPv6 address selected
		($ip6, $virt6, $virt6already, $netmask6) =
			&parse_virtual_ip6($tmpl, undef);
		$ipinfo->{'ip6'} = $ip6;
		$ipinfo->{'virt6'} = $virt6;
		$ipinfo->{'mode6'} = $in{'virt6'};
		$ipinfo->{'virt6already'} = $virt6already;
		$ipinfo->{'netmask6'} = $netmask6;
		}
	}

($cont, $contdoms) = &backup_contents($src, 1, $key, $d);
if ($log && ref($cont)) {
	# Limit to domains in the backup that the user has access to
	my %dnames = map { $_, 1 } &backup_log_own_domains($log);
	foreach my $k (keys %$cont) {
		if (!$dnames{$k}) {
			delete($cont->{$k});
			}
		}
	if ($contdoms) {
		$contdoms = [ grep { $dnames{$_->{'dom'}} } @$contdoms ];
		}
	}
if (!$in{'confirm'}) {
	# See what is in the tar file or directory, to show the user
	ref($cont) || &error(&text('restore_efile', $cont));
	(keys %$cont) || &error($text{'restore_enone'});
	}
else {
	# Find the selected domains, in preparation for actual restore
	$gotvbs = 0;
	foreach $d (split(/\0/, $in{'dom'})) {
		if ($d eq "virtualmin") {
			$gotvbs = 1;
			next;
			}
		local $dinfo = &get_domain_by("dom", $d);
		if ($dinfo) {
			&can_edit_domain($dinfo) ||
				&error(&text('restore_ecannotdom',
					&show_domain_name($dinfo)));
			push(@doms, $dinfo);
			}
		else {
			$crmode == 1 || &error(&text('restore_ecannotcreate',
						 &show_domain_name($d)));
			push(@doms, { 'dom' => $d,
				      'missing' => 1 });
			}
		}
	@vbs = ( ) if (!$gotvbs);
	@doms || @vbs || &error($text{'restore_edoms'});
	}

if ($in{'confirm'}) {
	&ui_print_unbuffered_header(undef, $text{'restore_title'}, "");
	}
else {
	&ui_print_header(undef, $text{'restore_title'}, "");
	}

if (!$in{'confirm'}) {
	# Tell the user what will be done
	print &text('restore_from', $nice),"<p>\n";

	# Check for missing features
	@missing = &missing_restore_features($cont, $contdoms);
	@critical = grep { $_->{'critical'} } @missing;
	if (@critical) {
		print "<b>",&text('restore_fmissing', 
			join(", ", map { $_->{'desc'} } @critical)),"</b><p>\n";
		print "<b>",$text{'restore_fmissing3'},"</b><p>\n";
		goto FAILED;
		}
	elsif (@missing) {
		print "<b>",&text('restore_fmissing', 
			join(", ", map { $_->{'desc'} } @missing)),"</b><p>\n";
		print "<b>",$text{'restore_fmissing2'},"</b><p>\n";
		}

	# Check for backup problems
	@errs = &check_restore_errors($cont, $contdoms);
	@criticalerrs = $in{'skipwarnings'} ? (grep { $_->{'critical'} } @errs)
				      	    : @errs;
	if (@criticalerrs) {
		print "<b>",&text('restore_rerrors', 
		    join(", ", &unique(map { $_->{'desc'} } @criticalerrs))),
		    "</b><p>\n";
		goto FAILED;
		}
	elsif (@errs) {
		print "<b>",&text('restore_rerrors2', 
		    join(", ", &unique(map { $_->{'desc'} } @criticalerrs))),
		    "</b><p>\n";
		}

	print &ui_form_start("restore.cgi", "form-data");
	print &ui_hidden("origsrc", $origsrc);

	# Show domains with features below them
	@links = ( &select_all_link("dom", 0), &select_invert_link("dom", 0) );
	print &ui_links_row(\@links);
	%plugins = map { $_, 1 } &list_backup_plugins();
	print "<dl>\n";
	$anymissing = 0;
	foreach $d (sort { $a cmp $b } keys %$cont) {
		next if ($d eq "virtualmin");
		local $dinfo = &get_domain_by("dom", $d);
		local $can = $crmode == 1 ||
			     $dinfo && &can_edit_domain($dinfo);
		if ($in{'log'} && !$can) {
			# When restoring from a logged backup, don't even show
			# domains that this user can't restore
			next;
			}
		print "<dt>",&ui_checkbox("dom", $d,
				"<b>".&show_domain_name($d)."</b>",
				$can, undef, !$can),"\n";
		if (!$dinfo) {
			# Tell user that it doesn't exist, and if he can create
			if ($crmode == 1) {
				print "($text{'restore_create'})\n";
				}
			else {
				print "($text{'restore_nocreate'})\n";
				}
			$anymissing++;
			}
		elsif (!&can_edit_domain($dinfo)) {
			# Warn if cannot restore
			print "($text{'restore_norestore'})\n";
			}

		@dfeats = grep { $do_features{$_} } @{$cont->{$d}};
		@dfeats_f = grep { !$plugins{$_} } @dfeats;
		@dfeats_p = grep { $plugins{$_} } @dfeats;
		if (!@dfeats && !$in{'fix'}) {
			print "<dd><i>$text{'restore_nofeat'}</i>\n";
			}
		else {
			print "<dd>",join("<br>",
				map { $text{'backup_feature_'.$_} ||
				      $text{'feature_'.$_} } @dfeats_f),"\n";
			print "<dd>",join("<br>",
				map { &plugin_call($_, "feature_backup_name") ||
				      &plugin_call($_, "feature_name") }
				    @dfeats_p),"\n";
			$any++;
			}
		}

	# Show virtualmin settings
	if ($cont->{'virtualmin'} && &can_backup_virtualmin()) {
		print "<dt>",&ui_checkbox("dom", "virtualmin",
			"<b>$text{'restore_dovirtualmin'}</b>", 1),"\n";
		@dvbs = grep { $vbs{$_} } @{$cont->{'virtualmin'}};
		if (!@dvbs) {
			print "<dd><i>$text{'restore_novirt'}</i>\n";
			}
		else {
			print "<dd>",join("<br>",
				map { $text{'backup_v'.$_} } @dvbs),"\n";
			$any++;
			}
		}

	print "</dl>\n";
	print &ui_links_row(\@links);
	if ($any) {
		# Pass all HTML inputs to program again, and show OK button
		print &ui_hidden("src", $src),"\n";
		foreach $i (keys %in) {
			next if ($i =~ /^src_/);
			foreach $v (split(/\0/, $in{$i})) {
				print &ui_hidden($i, $v),"\n";
				}
			}
		print "<center>",&ui_submit($text{'restore_now2'}, "confirm"),
		      "<br>",&ui_checkbox("skipwarnings", 1,
					  $text{'restore_wskip'}, 0),
		      (keys %$cont > 1 ?
			      "<br>".&ui_checkbox("continue", 1,
					  $text{'restore_wcontinue'}, 0) : ""),
		      "</center>\n";
		}
	else {
		print "$text{'restore_notany'}<p>\n";
		}
	print &ui_form_end();
	}
else {
	# Actually execute the restore
	if (@doms) {
		print &text('restore_doing', scalar(@doms), $nice),"<p>\n";
		}
	else {
		print &text('restore_doing2', scalar(@vbs), $nice),"<p>\n";
		}
	$ok = &restore_domains($src, \@doms, \@do_features, \%options, \@vbs,
			       $in{'only'}, $ipinfo, !$safe_backup,
			       $in{'skipwarnings'}, $key, $in{'continue'},
			       $in{'delete_existing'});
	&run_post_actions();
	if ($ok) {
		print &text('restore_done'),"<p>\n";
		}
	else {
		print &text('restore_failed'),"<p>\n";
		}
	if ($origsrc eq "upload:") {
		# Delete uploaded temp file
		&unlink_file($src);
		}
	&webmin_log("restore", $src, undef,
		    { 'doms' => [ map { $_->{'dom'} } @doms ] });

	# Call any theme post command
	foreach my $d (@doms) {
		if (defined(&theme_post_save_domain)) {
			&theme_post_save_domain($d,
				$d->{'missing'} ? 'create' : 'modify');
			}
		}
	}

FAILED:
if (defined($in{'onedom'})) {
	# Link is back to view/edit form
	&ui_print_footer(&domain_footer_link(&get_domain($in{'onedom'})));
	}
else {
	&ui_print_footer("", $text{'index_return'});
	}

