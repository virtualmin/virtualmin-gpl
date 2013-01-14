#!/usr/local/bin/perl
# Show a form for installing new third-party scripts, and a list of those
# currently installed

$trust_unknown_referers = 1;
require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newscripts_ecannot'});
&ui_print_header(undef, $text{'newscripts_title'}, "");
&ReadParse();

# Show tabs
$prog = "edit_newscripts.cgi?mode=";
@tabs = ( [ "add", $text{'newscripts_tabadd'}, $prog."add" ],
	  [ "enable", $text{'newscripts_tabenable'}, $prog."enable" ],
	  [ "upgrade", $text{'newscripts_tabupgrade'}, $prog."upgrade" ],
	  [ "warn", $text{'newscripts_tabwarn'}, $prog."warn" ],
	  [ "latest", $text{'newscripts_tablatest'}, $prog."latest" ],
	  [ "summary", $text{'newscripts_tabsummary'}, $prog."summary" ],
	);
print &ui_tabs_start(\@tabs, "mode", $in{'mode'} || "add", 1);

# Show form for installing a script installer
print &ui_tabs_start_tab("mode", "add");
print "$text{'newscripts_desc1'}<p>\n";
print &ui_form_start("add_script.cgi", "form-data");
print &ui_table_start($text{'newscripts_header'}, undef, 2);

print &ui_table_row($text{'newscripts_srcinst'},
	&ui_radio("source", 0,
  [ [ 0, &text('newscripts_src0', &ui_textbox("local", undef, 40))."<br>" ],
    [ 1, &text('newscripts_src1', &ui_upload("upload"))."<br>" ],
    [ 2, &text('newscripts_src2', &ui_textbox("url", undef, 40))."<br>" ] ]));

print &ui_table_end();
print &ui_form_end([ [ "install", $text{'newscripts_install'} ] ]);
print &ui_tabs_end_tab();

############################################################################

# Display a list of those currently available, with checkboxes for enabling
print &ui_tabs_start_tab("mode", "enable");
print "$text{'newscripts_desc2'}\n";
print "$text{'newscripts_desc2b'}<p>\n";
print "$text{'newscripts_desc2c'}<p>\n";

# Build data for table
foreach $s (&list_scripts()) {
	$script = &get_script($s);
	$script->{'sortcategory'} = $script->{'category'} || "zzz";
	push(@scripts, $script);
	}
foreach $script (sort { $a->{'sortcategory'} cmp $b->{'sortcategory'} ||
			lc($a->{'desc'}) cmp lc($b->{'desc'}) }
		      @scripts) {
	$cat = $script->{'category'} || $text{'scripts_nocat'};
	if ($cat ne $lastcat) {
		push(@table, [ { 'type' => 'group',
			         'desc' => $cat } ]);
		$lastcat = $cat;
		}
	@v = sort { &compare_versions($b, $a, $script) } @{$script->{'versions'}};
	@v = map { [ $_, $script->{'vdesc'}->{$_} || $_ ] } @v;
	push(@table, [
		{ 'type' => 'checkbox', 'name' => 'd',
		  'value' => $script->{'name'},
		  'checked' => $script->{'avail_only'} },
		$script->{'site'} ? 
			"<a href='$script->{'site'}' target=_blank>".
			"$script->{'desc'}</a>" : $script->{'desc'},
		$script->{'longdesc'},
		$text{'newscripts_'.$script->{'source'}},
		@v > 1 ? &ui_select($script->{'name'}."_minversion",
				$script->{'minversion'},
				[ [ undef, $text{'newscripts_any'} ],
				  (map { [ $_->[0], ">= $_->[1]" ] } @v),
				  (map { [ "<=$_->[0]", "<= $_->[1]" ] } @v) ],
				1, 0, 1) : "",
		]);
	}

# Generate the table of scripts
print &ui_form_columns_table(
	"disable_scripts.cgi",
	[ [ "save", $text{'newscripts_save'} ] ],
	0,
	undef,
	undef,
	[ "", $text{'newscripts_name'}, $text{'newscripts_longdesc'},
	  $text{'newscripts_src'}, $text{'newscripts_minver'} ],
	100,
	\@table);

# Show form to allow master admin
print &ui_hr();
print "<a name=allow>\n";
($allowmaster, $allowvers, $denydefault) = &get_script_master_permissions();
print &ui_form_start("save_scriptallow.cgi");
print &ui_table_start($text{'newscripts_allowheader'}, undef, 2);

# Can install any script?
print &ui_table_row($text{'newscripts_allowmaster'},
	&ui_yesno_radio("allowmaster", $allowmaster));

# Can install any version?
print &ui_table_row($text{'newscripts_allowvers'},
	&ui_yesno_radio("allowvers", $allowvers));

# Deny new scripts by default?
print &ui_table_row($text{'newscripts_denydefault'},
	&ui_yesno_radio("denydefault", $denydefault));

print &ui_table_end();
print &ui_form_end([ [ undef, $text{'save'} ] ]);

print &ui_tabs_end_tab();

############################################################################

# Show form to mass upgrade scripts
print &ui_tabs_start_tab("mode", "upgrade");
print "$text{'newscripts_desc3'}<p>\n";

# Find those we actually use, and the minimum version of each installed
@all_scripts = ( );
foreach $d (&list_domains()) {
	&detect_real_script_versions($d);
	foreach my $sinfo (&list_domain_scripts($d)) {
		$n = $sinfo->{'name'};
		$script = &get_script($n);
		push(@all_scripts, [ $d, $sinfo, $script ]);
		$used{$n}++;
		if (!$minversion{$n} ||
		    &compare_versions($sinfo->{'version'},
				      $minversion{$n}, $script) < 0) {
			$minversion{$n} = $sinfo->{'version'};
			}
		}
	}

# Find installed scripts and possible upgrades
@scriptnames = &list_available_scripts();
foreach $sname (grep { $used{$_} } @scriptnames) {
	$script = &get_script($sname);
	foreach $v (@{$script->{'versions'}}) {
		if (&compare_versions($v, $minversion{$sname}, $script) > 0) {
			push(@opts, [ "$sname $v", "$script->{'desc'} $v" ]);
			}
		}
	}
@opts = sort { lc($a->[1]) cmp lc($b->[1]) } @opts;

if (@opts) {
	# Script selector
	print &ui_form_start("mass_scripts.cgi", "post");
	print &ui_table_start($text{'newscripts_mheader'}, undef, 2);
	print &ui_table_row($text{'newscripts_script'},
			    &ui_select("script", undef, \@opts));

	# Servers to upgrade
	@doms = &list_domains();
	print &ui_table_row($text{'newscripts_servers'},
			    &ui_radio("servers_def", 1,
				[ [ 1, $text{'newips_all'} ],
				  [ 0, $text{'newips_sel'} ] ])."<br>\n".
			    &servers_input("servers", [ ], \@doms));

	print &ui_table_row($text{'newscripts_fail'},
			    &ui_yesno_radio("fail", 1));

	print &ui_table_end();
	print &ui_form_end([ [ "upgrade", $text{'newscripts_upgrade'} ] ]);
	}
else {
	# No upgrade possible
	print "<b>$text{'newscripts_noup'}</b><p>\n";
	}
print &ui_tabs_end_tab();

############################################################################

# Show form to setup scheduled email warnings about old scripts
print &ui_tabs_start_tab("mode", "warn");
print "$text{'newscripts_desc4'}<p>\n";
print &ui_form_start("save_scriptwarn.cgi", "post");
print &ui_table_start($text{'newscripts_wheader'}, undef, 2);

# Warning enabled and schedule
$job = &find_cron_script($scriptwarn_cron_cmd);
print &ui_table_row($text{'newscripts_wenabled'},
		    &ui_yesno_radio("enabled", $job ? 1 : 0));

# Limit to domains
if ($config{'scriptwarn_servers'} eq "") {
	$serversmode = 0;
	}
elsif ($config{'scriptwarn_servers'} =~ /^\!(.*)$/) {
	$serversmode = 2;
	@servers = split(/\s+/, $1);
	}
else {
	$serversmode = 1;
	@servers = split(/\s+/, $config{'scriptwarn_servers'});
	}
print &ui_table_row($text{'newscripts_wservers'},
		    &ui_radio("serversmode", $serversmode,
			      [ [ 0, $text{'newbw_servers0'} ],
			        [ 1, $text{'newbw_servers1'} ],
			        [ 2, $text{'newbw_servers2'} ] ])."<br>\n".
		    &servers_input("servers", \@servers,
				   [ &list_domains() ]));

# Notification schedule
$sched = $job ? &parse_cron_schedule($job)
	      : $config{'scriptwarn_wsched'} || 'daily';
if ($sched) {
	print &ui_table_row($text{'newscripts_wsched'},
		&ui_select("wsched", $sched,
			   [ map { [ $_, $cron::text{'edit_special_'.$_} ] }
				 ( 'daily', 'weekly', 'monthly' ) ]));
	print &ui_hidden("old_wsched", $sched);
	}

# Notify each person only once?
print &ui_table_row($text{'newscripts_wnotify'},
	&ui_radio("wnotify", int($config{'scriptwarn_notify'}),
		  [ [ 1, $text{'newscripts_wnotify1'} ],
		    [ 0, $text{'newscripts_wnotify0'} ] ]));

# Send email to
%email = map { $_, 1 } split(/\s+/, $config{'scriptwarn_email'});
($other) = grep { /\@/ } (keys %email);
print &ui_table_row($text{'newscripts_wemail'},
	    &ui_checkbox("wemail", "owner", $text{'newscripts_wowner'},
			 $email{'owner'})."<br>\n".
	    &ui_checkbox("wemail", "reseller", $text{'newscripts_wreseller'},
			 $email{'reseller'})."<br>\n".
	    &ui_checkbox("wemail", "other", $text{'newscripts_wother'},
			 $other)." ".
	    &ui_textbox("wother", $other, 40));

print &ui_table_end();
print &ui_form_end([ [ undef, $text{'save'} ] ]);
print &ui_tabs_end_tab();

############################################################################

# Show form for downloading script updates
print &ui_tabs_start_tab("mode", "latest");
print "$text{'newscripts_desc5'}<p>\n";
print &ui_form_start("save_scriptlatest.cgi", "post");
print &ui_table_start($text{'newscripts_lheader'}, undef, 2);

# Automatically download latest scripts?
$job = &find_cron_script($scriptlatest_cron_cmd);
print &ui_table_row($text{'newscripts_lenabled'},
	&ui_yesno_radio("enabled", $job ? 1 : 0));

# Scripts to include
print &ui_table_row($text{'newscripts_lscripts'},
	&ui_radio("scripts_def", $config{'scriptlatest'} ? 0 : 1,
	      [ [ 1, $text{'newscripts_lall'} ],
		[ 0, $text{'newscripts_lsel'} ] ])."<br>\n".
	&ui_select("scripts",
		   [ split(/\s+/, $config{'scriptlatest'}) ],
		   [ map { [ $_->{'name'}, $_->{'desc'} ] }
		      sort { lc($a->{'desc'}) cmp lc($b->{'desc'}) } @scripts ],
		   10, 1));

print &ui_table_end();
print &ui_form_end([ [ undef, $text{'save'} ] ]);
print &ui_tabs_end_tab();

############################################################################

# Show summary of all installed scripts
print &ui_tabs_start_tab("mode", "summary");
print "$text{'newscripts_desc6'}<p>\n";

foreach $as (sort { $a->[0]->{'dom'} cmp $b->[0]->{'dom'} } @all_scripts) {
	($d, $sinfo, $script) = @$as;
	$desc = $script->{'desc'};
	if ($sinfo->{'partial'}) {
		$desc = "<i>$desc</i>";
		}
	$path = $sinfo->{'opts'}->{'path'};
	$status = &describe_script_status($sinfo, $script);
	push(@all_table,
	     [ &show_domain_name($d),
	       "<a href='edit_script.cgi?dom=$d->{'id'}&".
                 "script=$sinfo->{'id'}'>$desc</a>",
	       $script->{'vdesc'}->{$sinfo->{'version'}} ||
		  $sinfo->{'version'},
	       $sinfo->{'url'} && !$sinfo->{'deleted'} ? 
		  "<a href='$sinfo->{'url'}' target=_blank>$path</a>" :
		  $path,
	       $status,
	     ]);
	}
print &ui_columns_table(
	[ $text{'newscripts_dom'}, $text{'scripts_name'},
	  $text{'scripts_ver'}, $text{'scripts_path'}, 
	  $text{'scripts_status'} ],
	100,
	\@all_table,
	undef,
	0,
	undef,
	$text{'newscripts_noneyet'},
	);

print &ui_tabs_end_tab();


print &ui_tabs_end(1);

&ui_print_footer("", $text{'index_return'});

