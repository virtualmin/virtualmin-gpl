#!/usr/local/bin/perl
# Show a form for backing up a single virtual server, or a bunch

require './virtual-server-lib.pl';
&ReadParse();
$cbmode = &can_backup_domain();
$cbmode || &error($text{'backup_ecannot'});
@scheds = grep { &can_backup_sched($_) } &list_scheduled_backups();

# Work out the current user's main domain, if needed
if ($cbmode == 2) {
	$d = &get_domain_by_user($base_remote_user);
	}

if ($in{'sched'}) {
	# Editing existing scheduled backup
	($sched) = grep { $_->{'id'} == $in{'sched'} } @scheds;
	$sched || &error($text{'backup_egone'});
	$omsg = undef;
	if ($sched->{'owner'}) {
		# Make owner message
		$od = &get_domain($sched->{'owner'});
		$omsg = $od ? &text('backup_odom', "<tt>$od->{'user'}</tt>")
		    : &text('backup_oresel', "<tt>$sched->{'owner'}</tt>");
		}
	&ui_print_header($omsg, $text{'backup_title2'}, "");
	print &ui_form_start("backup_sched.cgi", "post");
	print &ui_hidden("sched", $in{'sched'});
	$nodownload = 1;
	$nopurge = 0;
	}
elsif ($in{'new'}) {
	# Creating new scheduled backup
	&ui_print_header(undef, $text{'backup_title3'}, "");
	print &ui_form_start("backup_sched.cgi", "post");
	print &ui_hidden("new", 1);
	$nodownload = 1;
	$nopurge = 0;
	}
else {
	# Doing a one-off backup
	&ui_print_header(undef, $text{'backup_title'}, "");
	print &ui_form_start("backup.cgi/backup.tgz", "post");
	print &ui_hidden("oneoff", $in{'oneoff'});
	if ($in{'oneoff'}) {
		($sched) = grep { $_->{'id'} == $in{'oneoff'} } @scheds;
		$sched || &error($text{'backup_egone'});
		}
	else {
		$sched = $scheds[0];
		}
	$nodownload = 0;
	$nopurge = 1;
	}

if ($cbmode == 3 && ($in{'sched'} || $in{'oneoff'})) {
	# If this backup is to a domain's directory but the current
	# user is a reseller, use that domain
	($mode) = &parse_backup_url($sched->{'dest'});
	if ($mode == 0) {
		$d = &get_domain($sched->{'owner'});
		}
	}

# Use sensible defaults for new schedules
$sched ||= { 'all' => 1,
	     'feature_all' => 1,
	     'parent' => 1,
	     'fmt' => 2,
	     'onebyone' => 1,
	     'email' => $cbmode == 2 ? $d->{'emailto'} :
			$cbmode == 3 ? $access{'email'} : undef };
@tds = ( "width=30% ");

# Fields to select domains
print &ui_hidden_table_start($text{'backup_headerdoms'}, "width=100%",
			     2, "doms", 1, \@tds);
@bak = split(/\s+/, $sched->{'doms'});
@doms = grep { &can_backup_domain($_) } &list_domains();
$dis1 = &js_disable_inputs([ "doms" ], [ ], "onClick");
$dis2 = &js_disable_inputs([ ], [ "doms" ], "onClick");
$dsel = &ui_radio("all", int($sched->{'all'}),
		[ [ 1, $text{'backup_all'}, $dis1 ],
		  [ 0, $text{'backup_sel'}, $dis2 ],
		  [ 2, $text{'backup_exc'}, $dis2 ] ])."<br>\n".
	&servers_input("doms", \@bak, \@doms, $sched->{'all'} == 1);
$dsel .= "<br>".&ui_checkbox(
	"parent", 1, &hlink($text{'backup_parent'}, 'backup_parent'),
	$sched->{'parent'});
print &ui_table_row(&hlink($text{'backup_doms'}, "backup_doms"),
		    $dsel);

# Limit to plan
if (&can_edit_plans()) {
	@plans = sort { lc($a->{'name'}) cmp lc($b->{'name'}) } &list_plans();
	print &ui_table_row(&hlink($text{'backup_plan'}, "backup_plan"),
		&ui_select("plan", $sched->{'plan'},
			   [ [ '', "&lt;$text{'backup_anyplan'}&gt;" ],
			     map { [ $_->{'id'}, $_->{'name'} ] } @plans ]));
	}

print &ui_hidden_table_end("doms");

# Show feature and plugin selection boxes
print &ui_hidden_table_start($text{'backup_headerfeatures'}, "width=100%", 2,
			     "features", 0, \@tds);
$ftable = "";
$ftable .= &ui_radio("feature_all", int($sched->{'feature_all'}),
		[ [ 1, $text{'backup_allfeatures'} ],
		  [ 0, $text{'backup_selfeatures'} ] ])."<br>\n";
@links = ( &select_all_link("feature"), &select_invert_link("feature") );
$ftable .= &ui_links_row(\@links);
@schedfeats = split(/\s+/, $sched->{'features'});
foreach $f (&get_available_backup_features()) {
	$ftable .= &ui_checkbox("feature", $f,
		$text{'backup_feature_'.$f} || $text{'feature_'.$f},
		&indexof($f, @schedfeats) >= 0)."\n";
	local $ofunc = "show_backup_$f";
	if (defined(&$ofunc)) {
		local %opts = map { split(/=/, $_) }
				 split(/,/, $sched->{'backup_opts_'.$f});
		$ftable .= &$ofunc(\%opts);
		}
	$ftable .= "<br>\n";
	}
foreach $f (&list_backup_plugins()) {
	$ftable .= &ui_checkbox("feature", $f,
		&plugin_call($f, "feature_backup_name") ||
		    &plugin_call($f, "feature_name"),
		&indexof($f, @schedfeats) >= 0)."\n";
	if (&plugin_defined($f, "feature_backup_opts")) {
		local %opts = map { split(/=/, $_) }
				 split(/,/, $sched->{'backup_opts_'.$f});
		$ftable .= &plugin_call($f, "feature_backup_opts", \%opts);
		}
	$ftable .= "<br>\n";
	}
$ftable .= &ui_links_row(\@links);
print &ui_table_row(&hlink($text{'backup_features'}, "backup_features"),
		    $ftable);

# Show virtualmin object backup options
if (&can_backup_virtualmin()) {
	$vtable = "";
	%virts = map { $_, 1 } split(/\s+/, $sched->{'virtualmin'});
	foreach $vo (@virtualmin_backups) {
		$vtable .= &ui_checkbox("virtualmin", $vo,
				$text{'backup_v'.$vo}, $virts{$vo})."<br>\n";
		}
	@links = ( &select_all_link("virtualmin"),
		   &select_invert_link("virtualmin") );
	$vtable .= &ui_links_row(\@links);
	print &ui_table_row(&hlink($text{'backup_virtualmin'},
				   "backup_virtualmin"), $vtable);
	}

# Show files to exclude from each domain
@exclude = split(/\t+/, $sched->{'exclude'});
print &ui_table_row(&hlink($text{'backup_exclude'}, 'backup_exclude'),
	&ui_textarea("exclude", join("\n", @exclude), 5, 80));

print &ui_hidden_table_end("features");

# Build destination field inputs
@dests = &get_scheduled_backup_dests($sched);
push(@dests, undef) if ($in{'sched'});
@purges = &get_scheduled_backup_purges($sched);
@dfields = ( );
$i = 0;
foreach $dest (@dests) {
	# Show destination fields
	$dfield = &show_backup_destination("dest".$i, $dest, $cbmode == 3,
					   $d, $nodownload, 1);

	# Add purging option
	@grid = ( );
	if (!$nopurge) {
		push(@grid, &hlink($text{'backup_purge'}, "backup_purge"));
		push(@grid, &ui_opt_textbox("purge".$i, $purges[$i], 5,
			$text{'backup_purgeno'}, $text{'backup_purgeyes'})." ".
			$text{'newbw_days'});
		}

	if (@grid) {
		$dfield .= &ui_grid_table(\@grid, 2, 30,
					  [ "nowrap", "nowrap" ]);
		}

	if (!$dest && $in{'sched'}) {
		# Last option is hidden
		$dfield = &ui_hidden_start($text{'backup_adddest'},
					   "adddest", 0).$dfield.
			  &ui_hidden_end("adddest");
		}
	push(@dfields, $dfield);
	$i++;
	}

# Show destination fields
print &ui_hidden_table_start($text{'backup_headerdest'}, "width=100%", 2,
			     "dest", 1, \@tds);
print &ui_table_row(&hlink($text{'backup_dest'}, "backup_dest"),
	    join("<hr>\n", @dfields));

print &ui_table_row($text{'backup_opts'},
	    &ui_checkbox("strftime", 1,
			 &hlink($text{'backup_strftime'}, "backup_strftime"),
			 $sched->{'strftime'})."<br>\n".
	    &ui_checkbox("onebyone", 1,
			 &hlink($text{'backup_onebyone'}, "backup_onebyone"),
			 $sched->{'onebyone'}));

# Encrypt with key
@allkeys = defined(&list_backup_keys) ? &list_available_backup_keys() : ( );
if (@allkeys) {
	print &ui_table_row(&hlink($text{'backup_key'}, "backup_key"),
		&ui_select("key", $sched->{'key'},
			   [ [ "", "&lt;$text{'backup_nokey'}&gt;" ],
		 	     map { [ $_->{'id'}, $_->{'desc'} ] } @allkeys ],
			   1, 0, 1));
	}

# Single/multiple file mode
print &ui_table_row(&hlink($text{'backup_fmt'}, "backup_fmt"),
	&ui_radio("fmt", int($sched->{'fmt'}),
		  [ [ 0, $text{'backup_fmt0'} ],
		    [ 1, $text{'backup_fmt1'} ],
		    [ 2, $text{'backup_fmt2'} ] ])."<br>".
	&ui_checkbox("mkdir", 1, $text{'backup_mkdir'},
		     int($sched->{'mkdir'})));

# Show error mode
print &ui_table_row(&hlink($text{'backup_errors'}, "backup_errors"),
		    &ui_radio("errors", int($sched->{'errors'}),
			      [ [ 0, $text{'backup_errors0'} ],
				[ 1, $text{'backup_errors1'} ] ]));

# For a single domain, show option to add sub-servers
if ($d) {
	print &ui_table_row(&hlink($text{'backup_parent2'}, "backup_parent2"),
		    &ui_yesno_radio("parent", $sched->{'parent'} ? 1 : 0));
	}

# Show incremental option
if (&has_incremental_tar() && &has_incremental_format()) {
	print &ui_table_row(
		&hlink($text{'backup_increment'}, "backup_increment"),
			    &ui_radio("increment", int($sched->{'increment'}),
				      [ [ 0, $text{'backup_increment0'} ]."<br>",
					[ 1, $text{'backup_increment1'} ]."<br>",
					[ 2, $text{'backup_increment2'} ] ]));
	}

# Before and after commands (fixed)
if ($in{'oneoff'}) {
	if ($sched->{'before'}){
		print &ui_table_row($text{'backup_before'},
		    "<tt>".&html_escape($sched->{'before'})."</tt>");
		}
	if ($sched->{'after'}){
		print &ui_table_row($text{'backup_after'},
		    "<tt>".&html_escape($sched->{'after'})."</tt>");
		}
	}

print &ui_hidden_table_end("dest");

if ($in{'sched'} || $in{'new'}) {
	# Show schedule inputs
	print &ui_hidden_table_start($text{'backup_headersched'}, "width=100%",
				     2, "sched", 0, \@tds);

	# Email input
	print &ui_table_row(&hlink($text{'backup_email'}, "backup_email"),
			    &ui_textbox("email", $sched->{'email'}, 40).
			    "<br>\n".
			    &ui_checkbox("email_err", 1,
					 $text{'backup_email_err'},
					 $sched->{'email_err'}).
			    "<br>\n".
			    ($cbmode != 2 ?
			       &ui_checkbox("email_doms", 1,
					    $text{'backup_email_doms'},
					    $sched->{'email_doms'}) : "")
			    );

	# Enabled/disabled input
	print &ui_table_row(&hlink($text{'backup_when'}, "backup_when"),
		&virtualmin_ui_show_cron_time("enabled", $sched->{'enabled'} ? $sched : undef, $text{'backup_disabled'}));

	# Commands to run before and after
	if (&can_backup_commands()) {
		print &ui_table_row(
			&hlink($text{'backup_before'}, "backup_before"),
			&ui_opt_textbox("before", $sched->{'before'}, 40,
					$text{'backup_none'}));

		print &ui_table_row(
			&hlink($text{'backup_after'}, "backup_after"),
			&ui_opt_textbox("after", $sched->{'after'}, 40,
					$text{'backup_none'}));
		}
	print &ui_hidden_table_end("sched");

	# Save buttons
	if ($in{'new'}) {
		print &ui_form_end([ [ "save", $text{'backup_create'} ] ]);
		}
	else {
		print &ui_form_end([ [ "save", $text{'backup_save'} ],
			$in{'sched'} == 1 ? ( ) :
				( [ "delete", $text{'backup_delete'} ] ) ]);
		}
	}
else {
	print &ui_form_end([ [ "now", $text{'backup_now'} ],
			     $in{'oneoff'} ? ( [ "bg", $text{'backup_bg'} ] )
					   : ( ) ]);
	}

&ui_print_footer(
	$in{'sched'} || $in{'new'} ?
		( "list_sched.cgi", $text{'sched_return'} ) : ( ),
	"", $text{'index_return'});

