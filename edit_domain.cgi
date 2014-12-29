#!/usr/local/bin/perl
# edit_domain.cgi
# Display details of a domain for editing

require './virtual-server-lib.pl';
use POSIX;
&ReadParse();
$d = &get_domain($in{'dom'});
$d || &error($text{'edit_egone'});
&can_config_domain($d) || &error($text{'edit_ecannot'});
if ($d->{'parent'}) {
	$parentdom = &get_domain($d->{'parent'});
	}
if ($d->{'alias'}) {
	$aliasdom = &get_domain($d->{'alias'});
	}
if ($d->{'subdom'}) {
	$subdom = &get_domain($d->{'subdom'});
	}
$tmpl = &get_template($d->{'template'});
&ui_print_header(&domain_in($d), $aliasdom ?  $text{'edit_title3'} :
				 $subdom ?    $text{'edit_title4'} :
				 $parentdom ? $text{'edit_title2'} :
					      $text{'edit_title'}, "");
# Disabled, so tell the user that features cannot be changed
if ($d->{'disabled'}) {
	print "<font color=#ff0000>".
	      "<b>".$text{'edit_disabled_'.$d->{'disabled_reason'}}."\n".
	      $text{'edit_disabled'}."<br>".
	      ($d->{'disabled_why'} ?
		&text('edit_disabled_why', $d->{'disabled_why'})."<br>" : "").
	      ($d->{'disabled_time'} ?
		&text('edit_disabled_time',
		      &make_date($d->{'disabled_time'}))."<br>" : "").
	      "</b></font><p>\n";
	}

@tds = ( "width=30%" );
print &ui_form_start("save_domain.cgi", "post");
print &ui_hidden("dom", $in{'dom'}),"\n";
print &ui_hidden_table_start($text{'edit_header'}, "width=100%", 2,
			     "basic", 1, \@tds);

# Domain name, with link
$dname = &show_domain_name($d);
$url = &get_domain_url($d)."/";
print &ui_table_row($text{'edit_domain'},
	&domain_has_website($d) ?
	  "<tt><a target=_blank href=$url>$dname</a></tt>" :
	  "<tt>$dname</tt>");

if ($dname ne $d->{'dom'}) {
	print &ui_table_row($text{'edit_xndomain'},
		"<tt>$d->{'dom'}</tt>");
	}

# Username
foreach $f (@database_features) {
	$ufunc = "${f}_user";
	if (!$d->{'parent'} && $d->{$f} && defined(&$ufunc)) {
		$duser = &$ufunc($d);
		if ($duser ne $d->{'user'}) {
			push(@dbusers, &text('edit_dbuser', $duser,
					     $text{'feature_'.$f}));
			}
		}
	}
print &ui_table_row($text{'edit_user'},
		    "<tt>$d->{'user'}</tt> ".
		    (@dbusers ? " (".join(", ", @dbusers).")" : ""));

# Group name
if (($d->{'unix'} || $d->{'parent'}) && $d->{'group'}) {
	print &ui_table_row($text{'edit_group'},
			    "<tt>$d->{'group'}</tt>");
	}

# Show creator and date
print &ui_table_row($text{'edit_created'},
		    &text('edit_createdby',
			  &make_date($d->{'created'}),
			  $d->{'creator'} ? "<tt>$d->{'creator'}</tt>"
				          : $text{'maillog_unknown'}));

if ($virtualmin_pro && $d->{'reseller'}) {
	# Show reseller
	print &ui_table_row($text{'edit_reseller'},
			    "<tt>$d->{'reseller'}</tt>");
	}

if (!$aliasdom && $d->{'dir'}) {
	# Show home directory
	print &ui_table_row($text{'edit_home'},
			    "<tt>$d->{'home'}</tt>");
	}

# Show IP addresses
@ips = ( $d->{'ip'} );
if ($d->{'ip6'}) {
	push(@ips, $d->{'ip6'});
	}
print &ui_table_row($text{'edit_ips'},
	join(", ", @ips));

if ($d->{'proxy_pass_mode'} && $d->{'proxy_pass'} && &domain_has_website($d)) {
	# Show forwarding / proxy destination
	print &ui_table_row($text{'edit_proxy'.$d->{'proxy_pass_mode'}},
			    "<tt>$d->{'proxy_pass'}</tt>");
	}

if ($aliasdom) {
	# Show link to aliased domain
	print &ui_table_row($text{'edit_aliasto'},
			    "<a href='edit_domain.cgi?dom=$d->{'alias'}'>".
			    &show_domain_name($aliasdom)."</a>".
			    ($d->{'aliasmail'} ?
				" (".$text{'edit_aliasmail'}.")" : ""));
	}
elsif ($parentdom) {
	# Show link to parent domain
	print &ui_table_row($text{'edit_parent'},
			    "<a href='edit_domain.cgi?dom=$d->{'parent'}'>".
			    &show_domain_name($parentdom)."</a>");
	}

print &ui_hidden_table_end("basic");


# Configuration settings section
print &ui_hidden_table_start($text{'edit_headerc'}, "width=100%", 2,
			     "config", 0, \@tds);

# Show username prefix, with option to change
if (!$aliasdom && $tmpl->{'append_style'} != 6) {
	@users = &list_domain_users($d, 1, 1, 1, 1);
	$msg = &get_prefix_msg($tmpl);
	print &ui_table_row($text{'edit_'.$msg},
		@users ? "<tt>$d->{'prefix'}</tt> (".
			  &text('edit_noprefix', scalar(@users)).")"
		       : &ui_textbox("prefix", $d->{'prefix'}, 30));
	}

# Show active template
foreach $t (&list_templates()) {
	next if ($t->{'deleted'});
	next if (($d->{'parent'} && !$d->{'alias'}) && !$t->{'for_sub'});
	next if (!$d->{'parent'} && !$t->{'for_parent'});
	next if (!&master_admin() && !&reseller_admin() && !$t->{'for_users'});
	next if ($d->{'alias'} && !$t->{'for_alias'});
	next if (!&can_use_template($t));
	push(@cantmpls, $t);
	$gottmpl = 1 if ($t->{'id'} == $tmpl->{'id'});
	}
if (@cantmpls) {
	push(@cantmpls, $tmpl) if (!$gottmpl);
	print &ui_table_row(&hlink($text{'edit_tmpl'},"template"),
		    &ui_select("template", $tmpl->{'id'},
			[ map { [ $_->{'id'}, $_->{'name'} ] } @cantmpls ]));
	}

# Generate Javascript for plan change
@plans = sort { $a->{'name'} cmp $b->{'name'} } &list_available_plans();
$js = "<script>\n";
$js .= "function select_plan(num)\n";
$js .= "{\n";
foreach $plan (@plans) {
	$js .= "if (num == $plan->{'id'}) {\n";
	$js .= &quota_javascript("quota", $plan->{'quota'}, "home", 1);
	$js .= &quota_javascript("uquota", $plan->{'uquota'}, "home", 1);
	$js .= &quota_javascript("bw", $plan->{'bwlimit'}, "bw", 1);
	$js .= "    }\n";
	}
$js .= "}\n";
$js .= "</script>\n";
print $js;

# Show plan, with option to change
if (!$parentdom) {
	$plan = &get_plan($d->{'plan'});
	$label = &hlink($text{'edit_plan'}, "plan");
	if (@plans) {
		# Can select one
		($onlist) = grep { $_->{'id'} eq $plan->{'id'} } @plans;
		push(@plans, $plan) if (!$onlist);
		print &ui_table_row($label,
		   &ui_select("plan", $plan->{'id'},
		     [ map { [ $_->{'id'}, $_->{'name'} ] } @plans ],
		     1, 0, 0, 0,
		     "onChange='select_plan(options[selectedIndex].value)'").
		   " ".
		   &ui_checkbox("applyplan", 1, $text{'edit_applyplan'}, 1));
		}
	else {
		# Just show current plan
		print &ui_table_row($label, $plan->{'name'});
		}
	}

# Show description
print &ui_table_row($text{'edit_owner'},
		    &ui_textbox("owner", $d->{'owner'}, 50));

if (!$parentdom) {
	# Show owner's email address and password
	print &ui_table_row(&hlink($text{'edit_email'}, "ownersemail"),
		$d->{'unix'} ? &ui_opt_textbox("email", $d->{'email'}, 30,
					       $text{'edit_email_def'})
			     : &ui_textbox("email", $d->{'email'}, 30));

	$smsg = &get_password_synced_types($d) ?
			"<br>".$text{'edit_dbsync'} : "";
	print &ui_table_row($text{'edit_passwd'},
		&ui_opt_textbox("passwd", undef, 20,
				$text{'edit_lv'}." ".&show_password_popup($d),
				$text{'edit_set'}, undef, undef, undef,
			 	"autocomplete=off").
		$smsg);
	}

print &ui_hidden_table_end("config");

# Start of collapsible section for limits
$limits_section = !$parentdom &&
		  (&has_home_quotas() && (&can_edit_quotas() || $d->{'unix'}) ||
		  $config{'bw_active'});
if ($limits_section) {
	# Check if the domain is over any limits, show open by default if so
	$overlimits = 0;
	if ($d->{'bw_limit'} && $d->{'bw_usage'} > $d->{'bw_limit'}) {
		$overlimits++;
		}
	if ($d->{'quota'} && 0) {
		($totalhomequota, $totalmailquota) = &get_domain_quota($d);
		if ($totalhomequota > $d->{'quota'}) {
			$overlimits++;
			}
		}
	if ($d->{'uquota'} && 0) {
		$duser = &get_domain_owner($d, 1, 0, 1);
		if ($duser && $duser->{'uquota'} > $d->{'uquota'}) {
			$overlimits++;
			}
		}

	print &ui_hidden_table_start($text{'edit_limitsect'}, "width=100%", 2,
				     "limits", $overlimits, \@tds);
	}

# Show user and group quota editing inputs
if (&has_home_quotas() && !$parentdom && &can_edit_quotas()) {
	print &ui_table_row($text{'edit_quota'},
		&opt_quota_input("quota", $d->{'quota'}, "home"));
	print &ui_table_row($text{'edit_uquota'},
		&opt_quota_input("uquota", $d->{'uquota'}, "home"));
	}

if ($config{'bw_active'} && !$parentdom) {
	# Show bandwidth limit and period
	if (&can_edit_bandwidth()) {
		print &ui_table_row($text{'edit_bw'},
			    &bandwidth_input("bw", $d->{'bw_limit'}));

		# If bandwidth disabling is enabled, show option to turn off
		# for this domain
		if ($config{'bw_disable'}) {
			print &ui_table_row($text{'edit_bw_disable'},
				&ui_radio("bw_no_disable",
					  int($d->{'bw_no_disable'}),
					  [ [ 0, $text{'yes'} ],
					    [ 1, $text{'no'} ] ]));
			}
		}
	else {
		print &ui_table_row($text{'edit_bw'},
		  $d->{'bw_limit'} ?
		    &text('edit_bwpast_'.$config{'bw_past'},
		        &nice_size($d->{'bw_limit'}), $config{'bw_period'}) :
		    $text{'edit_bwnone'});
		}
	}

# Show total disk usage, broken down into unix user and mail users
if (&has_home_quotas() && !$parentdom && $d->{'unix'}) {
	&show_domain_quota_usage($d);
	}

if ($config{'bw_active'} && !$parentdom) {
	# Show usage over current period
	&show_domain_bw_usage($d);
	}

if ($limits_section) {
	print &ui_hidden_table_end("limits");
	}

# Show section for custom fields, if any
$fields = &show_custom_fields($d, \@tds);
if ($fields) {
	print &ui_hidden_table_start($text{'edit_customsect'}, "width=100%", 2,
				     "custom", 1, \@tds);
	print $fields;
	print &ui_hidden_table_end("custom");
	}

# Show buttons for turning features on and off (if allowed)
if (!$d->{'disabled'}) {
	# Show features for this domain
	print &ui_hidden_table_start($text{'edit_featuresect'}, "width=100%", 2,
				     "feature", 0);
	@grid = ( );
	$i = 0;
	foreach my $f (&list_possible_domain_features($d)) {
		# Don't show features that are always enabled, if currently set
		if ($config{$f} == 3 && $d->{$f}) {
			print &ui_hidden($f, $d->{$f}),"\n";
			next;
			}

		# Don't show dir option for alias domains if not needed
		if ($f eq 'dir' && $config{$f} == 3 && $d->{'alias'} &&
		    $tmpl->{'aliascopy'}) {
			print &ui_hidden($f, $d->{$f}),"\n";
			next;
			}

		local $txt = $parentdom ? $text{'edit_sub'.$f} : undef;
		$txt ||= $text{'edit_'.$f};
		if (!&can_use_feature($f)) {
			push(@grid, &ui_checkbox($f."_dis", 1, undef,
						$d->{$f}, undef, 1).
				    &ui_hidden($f, $d->{$f}).
				    " <b>".&hlink($txt, $f)."</b>");
			}
		else {
			push(@grid, &ui_checkbox($f, 1, "", $d->{$f}).
				    " <b>".&hlink($txt, $f)."</b>");
			}
		}

	foreach $f (&list_feature_plugins()) {
		next if (!&plugin_call($f, "feature_suitable",
					$parentdom, $aliasdom, $subdom));

		$label = &plugin_call($f, "feature_label", 1);
		$label = "<b>$label</b>";
		$hlink = &plugin_call($f, "feature_hlink");
		$label = &hlink($label, $hlink, $f) if ($hlink);
		if (!&can_use_feature($f)) {
			push(@grid, &ui_checkbox($f."_dis", 1, "",
						 $d->{$f}, undef, 1).
				    &ui_hidden($f, $d->{$f}).
				    " ".$label);
			}
		else {
			push(@grid, &ui_checkbox($f, 1, "", $d->{$f}).
				    " ".$label);
			}
		}

	$ftable = &ui_grid_table(\@grid, 2, 100,
			[ "align=left", "align=left" ]);
	print &ui_table_row(undef, $ftable, 2);
	print &ui_hidden_table_end("feature");
	}

# Save changes button
print &ui_form_end([ [ "save", $text{'edit_save'} ] ]);

# Show actions for this domain, unless the theme vetos it (cause they are on
# the left menu)
if ($current_theme ne "virtual-server-theme" &&
    !$main::basic_virtualmin_domain &&
    !$main::basic_virtualmin_menu) {
	&show_domain_buttons($d);
	}

# Make sure the left menu is showing this domain
if (defined(&theme_select_domain)) {
	&theme_select_domain($d);
	}

&ui_print_footer("", $text{'index_return'});

