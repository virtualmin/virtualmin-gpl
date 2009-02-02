#!/usr/local/bin/perl
# Show the details of one plan for editing

require './virtual-server-lib.pl';
$canplans = &can_edit_plans();
$canplans || &error($text{'plans_ecannot'});

if (!$in{'new'}) {
	@plans = &list_editable_plans();
	($plan) = grep { $_->{'id'} eq $in{'id'} } @plans;
	$plan || &error($text{'plan_ecannot'});
	}

&ui_print_header(undef, $in{'new'} ? $text{'plan_title1'}
				   : $text{'plan_title2'}, "", "editplan");

# Form block start
print &ui_form_start("save_plan.cgi", "post");
print &ui_hidden("id", $in{'id'});
print &ui_hidden("new", $in{'new'});

# Basic plan details, quota, bw and other limits
print &ui_hidden_table_start($text{'plan_header1'}, 'width=100%', 2,
			     1, 'main');

print &ui_table_row($text{'plan_name'},
	&ui_textbox("name", $plan->{'name'}, 40));

# Show quota limits
# XXX

# Show limits on numbers of things
foreach my $l ("mailbox", "alias", "dbs", "doms", "aliasdoms", "realdoms", "bw",
	       $virtualmin_pro ? ( "mongrels" ) : ( )) {
	print &ui_table_row(&hlink($text{'tmpl_'.$l.'limit'},
				   "template_".$l."limit"),
	    &ui_radio($l.'limit_def', $tmpl->{$l.'limit'} eq '' ? 1 : 0,
		      [ [ 1, $text{'form_unlimit'} ],
			[ 0, $text{'tmpl_atmost'} ] ])."\n".
	    ($l eq "bw" ? 
		&bandwidth_input($l.'limit', $limit, 1) :
		&ui_textbox($l.'limit', $limit, 10)));
	}

# Rename and DB name limits
# XXX
foreach my $n ('nodbname', 'norename', 'forceunder') {
	print &ui_table_row(&hlink($text{'limits_'.$n}, 'limits_'.$n),
		&ui_radio($n, $tmpl->{$n},
			  [ $tmpl->{'default'} ? ( ) :
				( [ "", $text{'default'} ] ),
			    [ 0, $text{'yes'} ],
			    [ 1, $text{'no'} ] ]));
	}

print &ui_hidden_table_end();

# Allowed features
print &ui_hidden_table_start($text{'plan_header2'}, 'width=100%', 2,
			     1, 'features');

%flimits = map { $_, 1 } split(/\s+/, $tmpl->{'featurelimits'});
$ftable = &ui_radio('featurelimits_def',
		    $tmpl->{'featurelimits'} eq 'none' ? 1 : 0,
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
$ftable .= &ui_grid_table(\@grid, 2);
print &ui_table_row(&hlink($text{'tmpl_featurelimits'},
			   "template_featurelimits"), $ftable);

print &ui_hidden_table_end();

# Allowed capabilities
print &ui_hidden_table_start($text{'plan_header3'}, 'width=100%', 2,
                             1, 'caps');

%caps = map { $_, 1 } split(/\s+/, $tmpl->{'capabilities'});
$etable = 
local $etable;
$etable .= &none_def_input("capabilities", $tmpl->{'capabilities'},
	   $text{'tmpl_below'}, 0, 0, $text{'tmpl_capauto'},
	   [ "capabilities" ])."<br>\n";
local @grid;
foreach my $ed (@edit_limits) {
	push(@grid, &ui_checkbox("capabilities", $ed,
				 $text{'limits_edit_'.$ed} || $ed,
				 $caps{$ed}));
	}
$etable .= &ui_grid_table(\@grid, 2);
print &ui_table_row(&hlink($text{'tmpl_capabilities'},
			   "template_capabilities"), $etable);

print &ui_hidden_table_end();


# Granted to resellers (for master admin)
# XXX


# Form end and buttons
if ($in{'new'}) {
	print &ui_form_end([ [ undef, $text{'create'} ] ]);
	}
else {
	print &ui_form_end([ [ undef, $text{'save'} ],
			     [ 'delete', $text{'delete'} ] ]);
	}

&ui_print_footer("edit_newplan.cgi", $text{'plans_return'},
		 "", $text{'index_return'});

