#!/usr/local/bin/perl
# Actually restore some servers, after asking for confirmation

require './virtual-server-lib.pl';
$crmode = &can_restore_domain();
$crmode || &error($text{'restore_ecannot'});
&ReadParse();

# Validate inputs, starting with source
&error_setup($text{'restore_err'});
if ($in{'src'}) {
	$src = $in{'src'};
	}
else {
	$src = &parse_backup_destination("src", \%in);
	}
($mode) = &parse_backup_url($src);
$mode > 0 || -r $src || -d $src || &error($text{'restore_esrc'});

# Parse features
if ($in{'feature_all'}) {
	@do_features = ( &get_available_backup_features($crmode == 2),
			 @backup_plugins );
	}
else {
	@do_features = split(/\0/, $in{'feature'});
	}
@do_features || &error($text{'restore_efeatures'});
if ($crmode == 2) {
	# Make sure they are all safe
	foreach my $f (@do_features) {
		&indexof($f, @safe_backup_features) >= 0 ||
		  &plugin_call($f, "feature_backup_safe") ||
		    &error(&text('restore_eunsafe', $f));
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
	if (!&can_select_ip() || $in{'virt'} == -1) {
		# Just use original IP, or shared IP
		$ipinfo = undef;
		}
	else {
		$tmpl = &get_template(0);
		($ip, $virt, $virtalready) = &parse_virtual_ip($tmpl, undef);
		$ipinfo = { 'ip' => $ip, 'virt' => $virt, 'mode' => $in{'virt'},
			    'virtalready' => $virtalready };
		}
	}

($cont, $contdoms) = &backup_contents($src, 1);
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

$nice = &nice_backup_url($src);
if (!$in{'confirm'}) {
	# Tell the user what will be done
	print &ui_form_start("restore.cgi", "post");
	print &text('restore_from', $nice),"<p>\n";

	# Check for missing features
	@missing = &missing_restore_features($cont, $contdoms);
	if (@missing) {
		print "<b>",&text('restore_fmissing', 
			join(", ", map { $_->{'desc'} } @missing)),"</b><p>\n";
		print "<b>",$text{'restore_fmissing2'},"</b><p>\n";
		}

	# Show domains with features below them
	@links = ( &select_all_link("dom", 0), &select_invert_link("dom", 0) );
	print &ui_links_row(\@links);
	%plugins = map { $_, 1 } @backup_plugins;
	print "<dl>\n";
	foreach $d (sort { $a cmp $b } keys %$cont) {
		next if ($d eq "virtualmin");
		local $dinfo = &get_domain_by("dom", $d);
		local $can = $crmode == 1 ||
			     $dinfo && &can_edit_domain($dinfo);
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
			       $in{'only'}, $ipinfo, $crmode == 2);
	&run_post_actions();
	if ($ok) {
		print &text('restore_done'),"<p>\n";
		}
	else {
		print &text('restore_failed'),"<p>\n";
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

if (defined($in{'onedom'})) {
	# Link is back to view/edit form
	&ui_print_footer(&domain_footer_link(&get_domain($in{'onedom'})));
	}
else {
	&ui_print_footer("", $text{'index_return'});
	}

