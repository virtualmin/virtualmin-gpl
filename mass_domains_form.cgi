#!/usr/local/bin/perl
# Show a form for modifying multiple virtual servers

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'massdomains_err'});

# Validate inputs and get the domains
@d = split(/\0/, $in{'d'});
@d || &error($text{'massdelete_enone'});
foreach $did (@d) {
	$d = &get_domain($did);
	$d && $d->{'uid'} && ($d->{'gid'} || $d->{'ugid'}) ||
		&error("Domain $did does not exist!");
	&can_config_domain($d) || &error($text{'edit_ecannot'});
	push(@doms, $d);
	}

# Show the form
&ui_print_header(undef, $text{'massdomains_title'}, "", "massdomains");

@dnames = map { $_->{'dom'} } @doms;
print &text('massdomains_doms', 
	join(" ", map { "<tt>$_</tt>" } @dnames)),"<p>\n";

print &ui_form_start("mass_domains_change.cgi", "post");
foreach $d (@doms) {
	print &ui_hidden("d", $d->{'id'}),"\n";
	}
@tds = ( "width=30%" );
print &ui_hidden_table_start($text{'massdomains_headerq'}, "width=100%", 2,
			     "quotas", 0);

# Quota change fields
if (&has_home_quotas() && &can_edit_quotas()) {
	print &ui_table_row($text{'massdomains_quota'},
		&ui_radio("quota_def", 2,
		  [ [ 2, $text{'massdomains_leave'} ],
		    [ 1, $text{'form_unlimit'} ],
		    [ 0, &quota_input("quota", undef, "home") ] ]),
		1, \@tds);

	print &ui_table_row($text{'massdomains_uquota'},
		&ui_radio("uquota_def", 2,
		  [ [ 2, $text{'massdomains_leave'} ],
		    [ 1, $text{'form_unlimit'} ],
		    [ 0, &quota_input("uquota", undef, "home") ] ]),
		1, \@tds);
	}

# Bandwidth limit fields
if ($config{'bw_active'} && &can_edit_bandwidth()) {
	print &ui_table_row($text{'massdomains_bw'},
		&bandwidth_input("bw", undef, 0, 1),
		1, \@tds);
	}

print &ui_hidden_end(),&ui_table_end();

# Feature enable/disable
print &ui_hidden_table_start($text{'massdomains_headerf'}, "width=100%", 2,
			     "features", 0);
foreach $f (@opt_features) {
	if (&can_use_feature($f)) {
		print &ui_table_row($text{'edit_'.$f},
			&ui_radio($f, 2, [ [ 2, $text{'massdomains_leave'} ],
					   [ 1, $text{'massdomains_enable'} ],
					   [ 0, $text{'massdomains_disable'} ],
					 ]),
			1, \@tds);
		}
	}
foreach $f (@feature_plugins) {
	if (&can_use_feature($f)) {
		$label = &plugin_call($f, "feature_label", 1);
		print &ui_table_row($label,
			&ui_radio($f, 2, [ [ 2, $text{'massdomains_leave'} ],
					   [ 1, $text{'massdomains_enable'} ],
					   [ 0, $text{'massdomains_disable'} ],
					 ]),
			1, \@tds);
		}
	}

print &ui_hidden_end(),&ui_table_end();

# Mailbox/alias/doms limits
print &ui_hidden_table_start($text{'massdomains_headerl'}, "width=100%", 2,
			     "limits", 0);
foreach $l (@limit_types) {
	print &ui_table_row($text{'form_'.$l},
		&ui_radio($l."_def", 2,
		  [ [ 2, $text{'massdomains_leave'} ],
		    [ 1, $text{'form_unlimit'} ],
		    [ 0, $text{'form_atmost'}." ".&ui_textbox($l, "", 4) ] ]),
		1, \@tds);
	}
print &ui_hidden_end(),&ui_table_end();

# Editable capabilities
print &ui_hidden_table_start($text{'massdomains_headerc'}, "width=100%", 2,
			     "capabilities", 0);
foreach $ed (@edit_limits) {
	print &ui_table_row($text{'limits_edit_'.$ed},
		&ui_radio("edit_".$ed, 2,
		  [ [ 2, $text{'massdomains_leave'} ],
		    [ 1, $text{'yes'} ],
		    [ 0, $text{'no'} ] ]),
		1, \@tds);
	}
# Allowed features
@opts = ( );
foreach $f (@opt_features, "virt") {
	push(@opts, [ $f, $text{'feature_'.$f} ]);
	}
foreach $f (@feature_plugins) {
	push(@opts, [ $f, &plugin_call($f, "feature_name") ]);
	}
print &ui_table_row($text{'massdomains_features'},
	&ui_radio("features_def", 2,
		[ [ 2, $text{'massdomains_features2'}."<br>" ],
		  [ 1, $text{'massdomains_features1'}." ".
			&ui_select("feature1", undef, \@opts)."<br>" ],
		  [ 0, $text{'massdomains_features0'}." ".
			&ui_select("feature0", undef, \@opts)."<br>" ] ]),
	1, \@tds);
print &ui_hidden_end(),&ui_table_end();

# Spam clearing mode
print &ui_hidden_table_start($text{'massdomains_headero'}, "width=100%", 2,
			     "others", 0);
if ($config{'spam'}) {
	print &ui_table_row($text{'massdomains_spamclear'},
		&ui_radio("spamclear_def", 1,
			[ [ 1, $text{'massdomains_leave'}."<br>" ],
			  [ 0, $text{'no'}."<br>" ],
			  [ 2, &text('spam_cleardays',
			     &ui_textbox("spamclear_days", undef, 5))."<br>" ],
			  [ 3, &text('spam_clearsize',
			     &ui_bytesbox("spamclear_size", undef)) ],
			 ]),
		1, \@tds);
	}

# Login shell
@shells = &get_unix_shells();
@shello = ( );
foreach $st ('nologin', 'ftp', 'ssh') {
	($sho) = grep { $_->[0] eq $st } @shells;
	if ($sho) {
		push(@shello, [ $sho->[1], $text{'limits_shell_'.$st} ]);
		}
	}
print &ui_table_row($text{'massdomains_shell'},
		    &ui_radio("shell_def", 1,
		      [ [ 1, $text{'massdomains_leave'} ],
			[ 0, &ui_select("shell", undef, \@shello) ] ]),
		    1, \@tds);
print &ui_hidden_end(),&ui_table_end();


print &ui_table_end();
print &ui_submit($text{'massdomains_ok'}, "ok");
print "&nbsp;\n";
print &ui_submit($text{'massdomains_enablebutton'}, "enable");
print &ui_submit($text{'massdomains_disablebutton'}, "disable");
print "<b>$text{'disable_why'}</b> ",
      &ui_textbox("why", undef, 30),"\n";
print &ui_form_end();

&ui_print_footer("", $text{'index_return'});
