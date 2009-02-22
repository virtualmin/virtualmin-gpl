#!/usr/local/bin/perl
# Show the details of one plan for editing

require './virtual-server-lib.pl';
&ReadParse();
$canplans = &can_edit_plans();
$canplans || &error($text{'plans_ecannot'});

if (!$in{'new'}) {
	@allplans = &list_plans();
	@plans = &list_editable_plans();
	($plan) = grep { $_->{'id'} eq $in{'id'} } @plans;
	$plan || &error($text{'plan_ecannot'});
	}

&ui_print_header(undef, $in{'new'} ? $text{'plan_title1'}
				   : $text{'plan_title2'}, "");

# Form block start
print &ui_form_start("save_plan.cgi", "post");
print &ui_hidden("id", $in{'id'});
print &ui_hidden("new", $in{'new'});
@tds = ( "width=30%" );

# Basic plan details, quota, bw and other limits
print &ui_hidden_table_start($text{'plan_header1'}, 'width=100%', 2,
			     'main', 1, \@tds);

print &ui_table_row(&hlink($text{'plan_name'}, "plan_name"),
	&ui_textbox("name", $plan->{'name'}, 40));

# Default domain quota
print &ui_table_row(&hlink($text{'tmpl_quota'}, "template_quota"),
    &ui_radio("quota_def", $plan->{'quota'} ? 0 : 1,
	      [ [ 1, $text{'form_unlimit'} ],
		[ 0, $text{'tmpl_quotasel'} ] ])." ".
    &quota_input("quota", $plan->{'quota'}, "home"));

# Default admin user quota
print &ui_table_row(&hlink($text{'tmpl_uquota'}, "template_uquota"),
    &ui_radio("uquota_def", $plan->{'uquota'} ? 0 : 1,
	      [ [ 1, $text{'form_unlimit'} ],
		[ 0, $text{'tmpl_quotasel'} ] ])." ".
    &quota_input("uquota", $plan->{'uquota'}, "home"));

# Show limits on numbers of things
foreach my $l (@plan_maxes) {
	print &ui_table_row(&hlink($text{'tmpl_'.$l.'limit'},
				   "template_".$l."limit"),
	    &ui_radio($l.'limit_def', $plan->{$l.'limit'} eq '' ? 1 : 0,
		      [ [ 1, $text{'form_unlimit'} ],
			[ 0, $text{'tmpl_atmost'} ] ])."\n".
	    ($l eq "bw" ? 
		&bandwidth_input($l.'limit', $plan->{$l.'limit'}, 1) :
		&ui_textbox($l.'limit', $plan->{$l.'limit'}, 10)));
	}

# Rename and DB name limits
foreach my $n (@plan_restrictions) {
	print &ui_table_row(&hlink($text{'limits_'.$n}, 'limits_'.$n),
		&ui_radio($n, int($plan->{$n}),
			  [ [ 0, $text{'yes'} ],
			    [ 1, $text{'no'} ] ]));
	}

print &ui_hidden_table_end();

# Allowed features
print &ui_hidden_table_start($text{'plan_header2'}, 'width=100%', 2,
			     'features', 0, \@tds);

%flimits = map { $_, 1 } split(/\s+/, $plan->{'featurelimits'});
$ftable = &ui_radio('featurelimits_def',
		    $plan->{'featurelimits'} ? 0 : 1,
		    [ [ 1, $text{'tmpl_featauto'} ],
		      [ 0, $text{'tmpl_below'} ] ])."<br>\n";
@grid = ( );
foreach my $f (@opt_features, "virt") {
	push(@grid, &ui_checkbox("featurelimits", $f,
				 $text{'feature_'.$f} || $f,
				 $flimits{$f}));
	}
foreach my $f (@feature_plugins) {
	push(@grid, &ui_checkbox("featurelimits", $f,
			 &plugin_call($f, "feature_name"), $flimits{$f}));
	}
$ftable .= &ui_grid_table(\@grid, 2).
	   &ui_links_row([ &select_all_link("featurelimits"),
			   &select_invert_link("featurelimits") ]);
print &ui_table_row(&hlink($text{'tmpl_featurelimits'},
			   "template_featurelimits"), $ftable);

print &ui_hidden_table_end();

# Allowed capabilities
print &ui_hidden_table_start($text{'plan_header3'}, 'width=100%', 2,
                             'caps', 0, \@tds);

%caps = map { $_, 1 } split(/\s+/, $plan->{'capabilities'});
$etable = &ui_radio('capabilities_def',
		    $plan->{'capabilities'} ? 0 : 1,
		    [ [ 1, $text{'tmpl_capauto'} ],
		      [ 0, $text{'tmpl_below'} ] ])."<br>\n";
@grid = ( );
foreach my $ed (@edit_limits) {
	push(@grid, &ui_checkbox("capabilities", $ed,
				 $text{'limits_edit_'.$ed} || $ed,
				 $caps{$ed}));
	}
$etable .= &ui_grid_table(\@grid, 2).
	   &ui_links_row([ &select_all_link("capabilities"),
			   &select_invert_link("capabilities") ]);
print &ui_table_row(&hlink($text{'tmpl_capabilities'},
			   "template_capabilities"), $etable);

print &ui_hidden_table_end();

# Granted to resellers (for master admin)
@resels = $virtualmin_pro ? &list_resellers() : ( );
if ($canplans == 2 && @resels) {
	print &ui_hidden_table_start($text{'plan_header4'}, 'width=100%', 2,
				     'resellers', 0, \@tds);

	print &ui_table_row(
		&hlink($text{'plan_resellers'}, "plan_resellers"),
		&ui_radio("resellers_def", $plan->{'resellers'} eq "" ? 1 :
					 $plan->{'resellers'} eq "none" ? 2 : 0,
			[ [ 1, $text{'tmpl_resellers_all'} ],
			  [ 2, $text{'tmpl_resellers_none'} ],
			  [ 0, $text{'tmpl_resellers_sel'} ] ])."<br>\n".
		&ui_select("resellers", [ split(/\s+/, $plan->{'resellers'}) ],
			 [ map { [ $_->{'name'},
				   $_->{'name'}.
				    ($_->{'acl'}->{'desc'} ?
					" ($_->{'acl'}->{'desc'})" : "") ] }
			       @resels ], 5, 1));

	print &ui_hidden_table_end();
	}

# Virtual servers currently on this plan
@doms = ( );
if (!$in{'new'}) {
	@doms = grep { !$_->{'parent'} } &get_domain_by("plan", $plan->{'id'});
	@doms = &sort_indent_domains(\@doms);
	}
if (@doms) {
	print &ui_hidden_table_start($text{'plan_header5'}, 'width=100%', 2,
                                     'doms', 0, \@tds);
	if ($config{'display_max'} && @doms > $config{'display_max'}) {
		# Too many to show
		print &ui_table_row(undef, &text('plan_toomany', scalar(@doms),
					         $config{'display_max'}), 2);
		}
	else {
		# Show the domains
		local $config{'show_quotas'} = scalar(@doms) > 100 ? 0 : 1;
		print &ui_table_row(undef, &domains_table(\@doms, 0, 1), 2);
		}
	print &ui_hidden_table_end();
	}


# Form end and buttons
if ($in{'new'}) {
	print &ui_form_end([ [ undef, $text{'create'} ] ]);
	}
else {
	print &ui_form_end([ [ undef, $text{'save'} ],
			     @doms ? ( [ 'apply', $text{'plan_apply'} ] )
				   : ( ),
			     @allplans > 1 ? ( [ 'delete', $text{'delete'} ] )
					   : ( ) ]);
	}

&ui_print_footer("edit_newplan.cgi", $text{'plans_return'},
		 "", $text{'index_return'});

