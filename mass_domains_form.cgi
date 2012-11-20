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

print &text('massdomains_doms', &nice_domains_list(\@doms)),"<p>\n";

print &ui_form_start("mass_domains_change.cgi", "post");
foreach $d (@doms) {
	print &ui_hidden("d", $d->{'id'}),"\n";
	}
@tds = ( "width=30%" );

$anyqb = &has_home_quotas() && &can_edit_quotas() ||
	 $config{'bw_active'} && &can_edit_bandwidth();
if ($anyqb) {
	print &ui_hidden_table_start($text{'massdomains_headerq'}, "width=100%",
				     2, "quotas", 0);
	}

# Quota change fields
if (&has_home_quotas() && &can_edit_quotas()) {
	print &ui_table_row($text{'massdomains_quota'},
		&opt_quota_input("quota", "none", "home",
				 $text{'massdomains_leave'}),
		1, \@tds);

	print &ui_table_row($text{'massdomains_uquota'},
		&opt_quota_input("uquota", "none", "home",
				 $text{'massdomains_leave'}),
		1, \@tds);
	}

# Bandwidth limit fields
if ($config{'bw_active'} && &can_edit_bandwidth()) {
	print &ui_table_row($text{'massdomains_bw'},
		&bandwidth_input("bw", undef, 0, 1),
		1, \@tds);
	}

if ($anyqb) {
	print &ui_hidden_table_end("quotas");
	}

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
foreach $f (&list_feature_plugins()) {
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

print &ui_hidden_table_end("features");

if (&can_edit_limits($doms[0])) {
	print &ui_hidden_table_start($text{'massdomains_headerl'}, "width=100%",
				     2, "limits", 0);

	# Account plan
	@plans = sort { $a->{'name'} cmp $b->{'name'} } &list_available_plans();
	if (@plans) {
		print &ui_table_row($text{'massdomains_plan'},
			&ui_select("plan", undef,
			   [ [ undef, $text{'massdomains_leave'} ],
			     map { [ $_->{'id'}, $_->{'name'} ] } @plans ])." ".
			&ui_checkbox("applyplan", 1,
				     $text{'edit_applyplan'}, 1));
		}

	# Mailbox/alias/doms limits
	foreach $l (@limit_types) {
		print &ui_table_row($text{'form_'.$l},
			&ui_radio($l."_def", 2,
			  [ [ 2, $text{'massdomains_leave'} ],
			    [ 1, $text{'form_unlimit'} ],
			    [ 0, $text{'form_atmost'}." ".
				 &ui_textbox($l, "", 4) ] ]),
			1, \@tds);
		}
	print &ui_hidden_end(),&ui_table_end();

	# Editable capabilities
	print &ui_hidden_table_start($text{'massdomains_headerc'}, "width=100%",
				     2, "capabilities", 0);
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
	foreach $f (&list_feature_plugins()) {
		push(@opts, [ $f, &plugin_call($f, "feature_name") ]);
		}
	print &ui_table_row($text{'massdomains_features'},
		&ui_radio("features_def", 2,
			[ [ 2, $text{'massdomains_features2'}."<br>" ],
			  [ 1, $text{'massdomains_features1'}." ".
				&ui_select("feature1", undef, \@opts)."<br>" ],
			  [ 0, $text{'massdomains_features0'}." ".
				&ui_select("feature0", undef, \@opts)."<br>" ] ]
			), 1, \@tds);
	print &ui_hidden_table_end("limits");
	}

# Start section for PHP options
@avail = &list_available_php_versions();
$anyphp = @avail > 1 && &can_edit_phpver() ||
	  &can_edit_phpmode();
if ($anyphp) {
	print &ui_hidden_table_start($text{'massdomains_headerp'},
				     "width=100%", 2, "php", 0);
	}

# PHP and Ruby execution modes
if (&can_edit_phpmode()) {
	print &ui_table_row($text{'massdomains_phpmode'},
		&ui_radio("phpmode", undef,
			  [ [ "", $text{'massdomains_leave'}."<br>" ],
			    map { [ $_, $text{'phpmode_'.$_}."<br>" ] }
				&supported_php_modes() ]), 1, \@tds);
	}
@rubys = &supported_ruby_modes();
if (&can_edit_phpmode() && @rubys) {
	print &ui_table_row($text{'massdomains_rubymode'},
		&ui_radio("rubymode", undef,
			  [ [ "", $text{'massdomains_leave'}."<br>" ],
			    [ "none", $text{'phpmode_noruby'}."<br>" ],
			    map { [ $_, $text{'phpmode_'.$_}."<br>" ] }
				@rubys ]), 1, \@tds);
	}

# Default PHP version
if (@avail > 1 && &can_edit_phpver()) {
	print &ui_table_row($text{'massdomains_phpver'},
		&ui_radio("phpver", undef,
			  [ [ "", $text{'massdomains_leave'} ],
			    map { [ $_->[0] ] } @avail ]), 1, \@tds);
	}

# PHP child processes
if (&can_edit_phpmode()) {
	print &ui_table_row($text{'massdomains_phpchildren'},
		&ui_radio("phpchildren_def", 1,
			  [ [ 1, $text{'massdomains_leave'} ],
			    [ 2, $text{'tmpl_phpchildrennone'} ],
			    [ 0, &ui_textbox("phpchildren", undef, 5) ] ]));
	}

if ($anyphp) {
	print &ui_hidden_table_end("php");
	}

print &ui_hidden_table_start($text{'massdomains_headero'}, "width=100%", 2,
			     "others", 0);

# Spam clearing mode
if ($config{'spam'} && &can_edit_spam()) {
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
if (&can_edit_shell()) {
	print &ui_table_row($text{'massdomains_shell'},
	    &ui_radio("shell_def", 1,
	      [ [ 1, $text{'massdomains_leave'} ],
		[ 0, &available_shells_menu("shell", undef, 'owner') ] ]),
	    1, \@tds);
	}

print &ui_hidden_table_end("others");

print &ui_form_end([ [ "ok", $text{'massdomains_ok'} ] ]);

&ui_print_footer("", $text{'index_return'});
