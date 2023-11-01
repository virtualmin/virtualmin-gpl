#!/usr/local/bin/perl
# Show available and installed scripts for this domain

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_scripts() || &error($text{'edit_ecannot'});
&domain_has_website($d) && $d->{'dir'} || &error($text{'scripts_eweb'});
&detect_real_script_versions($d);
@got = &list_domain_scripts($d);

&ui_print_header(&domain_in($d), $text{'scripts_title'}, "", "scripts");
@allscripts = map { &get_script($_) } &list_scripts();
@scripts = grep { $_->{'avail'} } @allscripts;
%smap = map { $_->{'name'}, $_ } @allscripts;

# Start tabs for listing and installing
@tabs = ( [ "existing", $text{'scripts_tabexisting'},
	    "list_scripts.cgi?dom=$in{'dom'}&scriptsmode=existing" ],
	  [ "new", $text{'scripts_tabnew'},
	    "list_scripts.cgi?dom=$in{'dom'}&scriptsmode=new" ] );
if (&can_unsupported_scripts()) {
	push(@tabs, [ "unsup", $text{'scripts_tabunsup'},
		      "list_scripts.cgi?dom=$in{'dom'}&scriptsmode=unsup" ] );
	}
print &ui_tabs_start(\@tabs, "scriptsmode",
	$in{'scriptsmode'} ? $in{'scriptsmode'} : @got ? "existing" : "new", 1);

# Build table of installed scripts (if any)
print &ui_tabs_start_tab("scriptsmode", "existing");
@table = ( );
$upcount = 0;
foreach $sinfo (sort { lc($smap{$a->{'name'}}->{'desc'}) cmp
		       lc($smap{$b->{'name'}}->{'desc'}) } @got) {
	# Check if a newer version exists
	$script = $smap{$sinfo->{'name'}};
	($status, $canup) = &describe_script_status($sinfo, $script);
	$upcount += $canup if (!script_migrated_disallowed($script->{'migrated'}));
	$path = $sinfo->{'opts'}->{'path_real'} || $sinfo->{'opts'}->{'path'};
	($dbtype, $dbname) = split(/_/, $sinfo->{'opts'}->{'db'}, 2);
	if ($dbtype && $dbname && $script->{'name'} !~ /^php(\S+)admin$/i) {
		$dbdesc = &text('scripts_idbname2',
		      "edit_database.cgi?dom=$in{'dom'}&type=$dbtype&".
			"name=$dbname",
		      $text{'databases_'.$dbtype}, "<tt>$dbname</tt>");
		}
	elsif ($sinfo->{'opts'}->{'db'}) {
		# Just a DB name, perhaps for a script that can only
		# use a single type
		$dbdesc = "<tt>$sinfo->{'opts'}->{'db'}</tt>";
		}
	else {
		$dbdesc = "<i>$text{'scripts_nodb'}</i>";
		}
	$desc = $script->{'desc'};
	if ($sinfo->{'partial'}) {
		$desc = "<i>$desc</i>";
		}
	my $desc_full = $script->{'desc'} ? "<a href='edit_script.cgi?dom=$in{'dom'}&".
		 "script=$sinfo->{'id'}'>$desc</a>" : $sinfo->{'name'};
	my $sversion = $script->{'vdesc'}->{$sinfo->{'version'}} || $sinfo->{'version'};
	$sversion =~ s/\.$//;
	push(@table, [
		{ 'type' => 'checkbox', 'name' => 'd',
		  'value' => $sinfo->{'id'}, 'disabled' => !$script->{'desc'} },
		$desc_full,
		$sversion,
		!$sinfo->{'deleted'} ? &get_script_link($d, $sinfo) : $path,
		$dbdesc,
		!$script->{'desc'} ? &ui_text_color($text{'scripts_discontinued'}, 'danger') :
		                     script_migrated_status($status, $script->{'migrated'}, $canup),
		]);
	}

# Show table of scripts
if (@got) {
	print $text{'scripts_desc3'},"<p>\n";
	}
print &ui_form_columns_table(
	"mass_uninstall.cgi",
	[ [ "uninstall", $text{'scripts_uninstalls'} ],
	  $upcount ? ( [ "upgrade", $text{'scripts_upgrades'} ] ) : ( ) ],
	1,
	undef,
	[ [ "dom", $in{'dom'} ] ], 
	[ "", $text{'scripts_name'}, $text{'scripts_ver'},
	  $text{'scripts_path'}, $text{'scripts_db'}, $text{'scripts_status'} ],
	100,
	\@table,
	undef,
	0,
	undef,
	$text{'scripts_noexisting'}
	);

print &ui_tabs_end_tab();

# Show table for installing scripts
print &ui_tabs_start_tab("scriptsmode", "new");
@allscripts = @scripts;
if (@scripts) {
	# Show search form
	print &ui_form_start("list_scripts.cgi");
	print &ui_hidden("dom", $in{'dom'});
	print &ui_hidden("scriptsmode", "new");
	print "<b>$text{'scripts_find'}</b> ",
	      &ui_textbox("search", $in{'search'}, 30)," ",
	      &ui_submit($text{'scripts_findok'});
	print &ui_form_end();
	}

if ($in{'search'}) {
	# Limit to matches
	$search = $in{'search'};
	@scripts = grep { $_->{'desc'} =~ /\Q$search\E/i ||
			  $_->{'longdesc'} =~ /\Q$search\E/i ||
			  join(" ", @{$_->{'categories'}}) =~ /\Q$search\E/i } @scripts;
	}

# Check out migrate scripts for GPL users
if (!$virtualmin_pro) {
	@scripts = grep { !$_->{'migrated'} } @scripts;
	}

# Build table of available scripts
@table = ( );
my @scripts_added;
my @scripts_sorted =
	sort { lc($a->{'desc'}) cmp lc($b->{'desc'}) } @scripts;
my $show_list_of_pro_scripts_to_gpl = &list_scripts_pro_tip(\@scripts_sorted);

foreach $script (@scripts_sorted) {
	@vers = grep { &can_script_version($script, $_) }
		     @{$script->{'install_versions'}};
	next if (!@vers && !$script->{'pro'});	# No allowed versions!
	next if (grep (/^$script->{'name'}$/, @scripts_added));
	if (!$script->{'pro'}) {
		if (@vers > 1) {
			my $pfunc = $script->{'preferred_version_func'};
			my $pver = $vers[0];
			if (defined(&$pfunc)) {
				$pver = &$pfunc($d);
				}
			$vsel = &ui_select("ver_".$script->{'name'},
			    $pver,
			    [ map { [ $_, $script->{'vdesc'}->{$_} ] }
				  @vers ]);
			}
		else {
			$vsel = ($script->{'vdesc'}->{$vers[0]} ||
				 $vers[0]).
				&ui_hidden("ver_".$script->{'name'},
					   $vers[0]);
			}
		}
	my @script_data = (
	    $script->{'pro'} ? undef :
	    { 'type' => 'radio', 'name' => 'script',
	      'value' => $script->{'name'},
	      'checked' => $in{'search'} && @scripts == 1 },
	    $script->{'site'} ?
	    	"<a href='@{[&script_link($script->{'site'}, undef, 1)]}' target=_blank>".
				"$script->{'desc'}</a>" : $script->{'desc'},
	    $script->{'pro'} ? $script->{'version'} : 
	    $vsel." ".
	    "<input type=image name=fast ".
	      "value=\"".&quote_escape($script->{'name'})."\" ".
	      "src=images/ok.gif ".
	      "onClick='form.fhidden.value=\"$script->{'name'}\"'>",
	    $script->{'longdesc'},
	    join(", ", @{$script->{'categories'}})
	    );
	push(@script_data, ($script->{'pro'} ? 'Pro' : 'GPL'))
		if ($show_list_of_pro_scripts_to_gpl);
	push(@table, \@script_data);
	push(@scripts_added, $script->{'name'});
	}

# Show table of available scripts
my @cols = ( "", $text{'scripts_name'}, $text{'scripts_ver'},
	      $text{'scripts_longdesc'}, $text{'scripts_cats'});
push(@cols, $text{'scripts_can'})
	if ($show_list_of_pro_scripts_to_gpl);

print &ui_form_columns_table(
	"script_form.cgi",
	[ [ undef, $text{'scripts_ok'} ] ],
	0,
	undef,
	[ [ "dom", $in{'dom'} ],
	  [ "fhidden", "" ] ],
	\@cols,
	100,
	\@table,
	undef,
	0,
	undef,
	!@allscripts ? $text{'scripts_nonew'} : $text{'scripts_nomatch'}
	);

print &ui_tabs_end_tab();

# Show form for installing a non-standard version
if (&can_unsupported_scripts()) {
	print &ui_tabs_start_tab("scriptsmode", "unsup");
	print $text{'scripts_unsupdesc'},"<p>\n";
	print &ui_form_start("script_form.cgi");
	print &ui_hidden("dom", $in{'dom'}),"\n";
	print &ui_table_start($text{'scripts_unsupheader'}, undef, 2);

	# Script type
	print &ui_table_row($text{'scripts_unsupname'},
	   &ui_select("script", undef, 
	      [ map { [ $_->{'name'}, $_->{'desc'} ] }
		 sort { lc($a->{'desc'}) cmp lc($b->{'desc'}) } @scripts ]));

	# Version to install
	print &ui_table_row($text{'scripts_unsupver'},
		&ui_textbox("ver", undef, 15));

	print &ui_table_end();
	print &ui_form_end([ [ undef, $text{'scripts_ok'} ] ]);
	print &ui_tabs_end_tab();
	}

print &ui_tabs_end(1);

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});

