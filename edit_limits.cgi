#!/usr/local/bin/perl
# edit_limits.cgi
# Display access control and usage limits for this domain's user

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_limits($d) || &error($text{'edit_ecannot'});

&ui_print_header(&domain_in($d), $text{'limits_title'}, "", "limits");

#print "$text{'limits_desc'}<p>\n";

print &ui_form_start("save_limits.cgi", "post");
print &ui_hidden("dom", $in{'dom'}),"\n";
print &ui_hidden_table_start($text{'limits_header'}, "width=100%", 2,
			     "limits", 1, [ "width=30%" ]);

# Maximum allowed mailboxes
print &ui_table_row(&hlink($text{'form_mailboxlimit'}, "limits_mailbox"),
	&ui_opt_textbox("mailboxlimit", $d->{'mailboxlimit'}, 4,
	      $text{'form_unlimit'}, $text{'form_atmost'}));

# Maximum allowed aliases
print &ui_table_row(&hlink($text{'form_aliaslimit'}, "limits_alias"),
	&ui_opt_textbox("aliaslimit", $d->{'aliaslimit'}, 4,
	      $text{'form_unlimit'}, $text{'form_atmost'}));

# Maximum allowed dbs
print &ui_table_row(&hlink($text{'form_dbslimit'}, "limits_dbs"),
	&ui_opt_textbox("dbslimit", $d->{'dbslimit'}, 4,
	      $text{'form_unlimit'}, $text{'form_atmost'}));

# Can create and edit domains?
$dlm = $d->{'domslimit'} eq "" ? 1 :
       $d->{'domslimit'} eq "*" ? 2 : 0;
print &ui_table_row(&hlink($text{'form_domslimit'}, "limits_doms"),
	&ui_radio("domslimit_def", $dlm,
		  [ [ 1, $text{'form_nocreate'} ], [ 2, $text{'form_unlimit'} ],
		    [ 0, $text{'form_atmost'}." ".
			 &ui_textbox("domslimit",
				$dlm == 0 ? $d->{'domslimit'} : "", 4) ] ]));

# Limit on alias domains
$alm = $d->{'aliasdomslimit'} eq "*" || $d->{'aliasdomslimit'} eq "" ? 1 : 0;
print &ui_table_row(&hlink($text{'form_aliasdomslimit'}, "limits_aliasdoms"),
	&ui_radio("aliasdomslimit_def", $alm,
		  [ [ 1, $text{'form_unlimit'} ],
		    [ 0, $text{'form_aliasdomslimit0'}." ".
			 &ui_textbox("aliasdomslimit", 
			    $alm ? "" : $d->{'aliasdomslimit'}, 4)." ".
			 $text{'form_aliasdomsabove'} ] ]));

# Limit on non-alias domains
$nlm = $d->{'realdomslimit'} eq "*" || $d->{'realdomslimit'} eq "" ? 1 : 0;
print &ui_table_row(&hlink($text{'form_realdomslimit'}, "limits_realdoms"),
	&ui_radio("realdomslimit_def", $nlm,
		  [ [ 1, $text{'form_unlimit'} ],
		    [ 0, $text{'form_aliasdomslimit0'}." ".
			 &ui_textbox("realdomslimit",
			    $nlm ? "" : $d->{'realdomslimit'}, 4)." ".
			 $text{'form_aliasdomsabove'} ] ]));

# Can choose db name
print &ui_table_row(&hlink($text{'limits_nodbname'}, "limits_nodbname"),
	&ui_radio("nodbname", $d->{'nodbname'} ? 1 : 0,
	       [ [ 0, $text{'yes'} ], [ 1, $text{'no'} ] ]));

# Can rename domains
print &ui_table_row(&hlink($text{'limits_norename'}, "limits_norename"),
	&ui_radio("norename", $d->{'norename'} ? 1 : 0,
	       [ [ 0, $text{'yes'} ], [ 1, $text{'no'} ] ]));

# Force sub-domain under master domain
print &ui_table_row(&hlink($text{'limits_forceunder'}, "limits_forceunder"),
	&ui_radio("forceunder", $d->{'forceunder'} ? 1 : 0,
	       [ [ 0, $text{'yes'} ], [ 1, $text{'no'} ] ]));

# Disallow domains under other people's domains
print &ui_table_row(&hlink($text{'limits_safeunder'}, "limits_safeunder"),
	&ui_radio("safeunder", $d->{'safeunder'} ? 1 : 0,
	       [ [ 0, $text{'yes'} ], [ 1, $text{'no'} ] ]));

# IP of sub-servers follows parent
print &ui_table_row(&hlink($text{'limits_ipfollow'}, "limits_ipfollow"),
	&ui_radio("ipfollow", $d->{'ipfollow'} ? 1 : 0,
	       [ [ 1, $text{'yes'} ], [ 0, $text{'no'} ] ]));

# Mongrel instances
if ($virtualmin_pro) {
	print &ui_table_row(&hlink($text{'limits_mongrels'}, "limits_mongrels"),
		&ui_opt_textbox("mongrels", $d->{'mongrelslimit'} || "", 5,
				$text{'form_unlimit'}));
	}

# Show limits from plugins
foreach $f (&list_feature_plugins()) {
	&plugin_call($f, "load_theme_library");
	$input = &plugin_call($f, "feature_limits_input", $d);
	print &ui_table_hr() if ($input && !$done_plugins_hr++);
	print $input;
	}

print &ui_hidden_table_end("limits");
print &ui_hidden_table_start($text{'limits_header2'}, "width=100%", 2,
			     "features", 0, [ "width=30%" ]);

# Capabilities when editing a server
@grid = ( );
foreach $ed (@edit_limits) {
	push(@grid, &ui_checkbox("edit", $ed, $text{'limits_edit_'.$ed} || $ed, $d->{"edit_$ed"}));
	}
$etable .= &ui_grid_table(\@grid, 2);
print &ui_table_row(&hlink($text{'limits_edit'}, "limits_edit"), $etable);

print &ui_table_hr();

# Allowed features
@grid = ( );
foreach $f (@opt_features, "virt") {
	next if (!&can_use_feature($f));
	if ($config{$f} == 3) {
		# A critical feature which cannot be turned off, so don't
		# bother showing it here
		next;
		}
	push(@grid, &ui_checkbox("features", $f, $text{'feature_'.$f} || $f, $d->{"limit_$f"}));
	}
foreach $f (&list_feature_plugins()) {
	next if (!&can_use_feature($f));
	push(@grid, &ui_checkbox("features", $f, &plugin_call($f, "feature_name"), $d->{"limit_$f"}));
	}
$ftable = &ui_grid_table(\@grid, 2);
print &ui_table_row(&hlink($text{'limits_features'}, "limits_features"),
		    $ftable);

if (defined(&list_scripts)) {
	# Allowed scripts
	print &ui_table_hr();

	$stable = &ui_radio('scripts_def',
			    $d->{'allowedscripts'} ? 0 : 1,
			    [ [ 1, $text{'plan_scriptsall'} ],
			      [ 0, $text{'tmpl_below'} ] ])."<br>\n";
	@scripts = &list_scripts();
	foreach $s (@scripts) {
		$script = &get_script($s);
		$scriptname{$s} = $script->{'desc'} if ($script);
		}
	@scripts = sort { lc($scriptname{$a}) cmp lc($scriptname{$b}) }@scripts;
	$stable .= &ui_multi_select("scripts",
		[ map { [ $_, $scriptname{$_} ] }
		      $d->{'allowedscripts'} ?
				split(/\s+/, $d->{'allowedscripts'}) :
				@scripts ],
		[ map { [ $_, $scriptname{$_} ] } @scripts ],
		10, 1, 0, $text{'plan_scriptsopts'}, $text{'plan_scriptssel'});
	print &ui_table_row(&hlink($text{'plan_scripts'}, "limits_scripts"),
			    $stable);
	}

print &ui_hidden_table_end("limits");
print &ui_hidden_table_start($text{'limits_header3'}, "width=100%", 2,
			     "other", 0, [ "width=30%" ]);

# Demo mode
print &ui_table_row(&hlink($text{'limits_demo'}, "limits_demo"),
	&ui_radio("demo", $d->{'demo'} ? 1 : 0,
	       [ [ 1, $text{'yes'} ], [ 0, $text{'no'} ] ]));

if (&can_webmin_modules()) {
	# Extra Webmin modules
	print &ui_table_row(&hlink($text{'limits_modules'}, "limits_modules"),
		&ui_textbox("modules", $d->{'webmin_modules'}, 30)."\n".
		&modules_chooser_button("modules", 1));
	}

if (&can_edit_shell() && $d->{'unix'}) {
	# Login shell, which determines FTP/SSH access
	$user = &get_domain_owner($d, 1);
	print &ui_table_row(&hlink($text{'limits_shell'}, "limits_shell"),
		    &available_shells_menu("shell", $user->{'shell'}, 'owner'));
	}

print &ui_hidden_table_end("other");
print &ui_form_end([ [ "save", $text{'save'} ] ]);

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});

