#!/usr/local/bin/perl
# Create, update or delete a template

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newtmpl_ecannot'});
&ReadParse();
@tmpls = &list_templates();
if (!$in{'new'}) {
	# Fetch existing template object
	($tmpl) = grep { $_->{'id'} == $in{'id'} } @tmpls;
	$tmpl || &error($text{'tmpl_egone'});
	}
elsif ($in{'cloneof'}) {
	# Fetch source for clone
	($cloneof) = grep { $_->{'id'} == $in{'cloneof'} } @tmpls;
	$tmpl = { %$cloneof };
	$tmpl->{'id'} = undef;
	$tmpl->{'standard'} = 0;
	}
elsif ($in{'cp'}) {
	# Fetch source for copy
	($cloneof) = grep { $_->{'id'} == 0 } @tmpls;
	$tmpl = { %$cloneof };
	$tmpl->{'id'} = undef;
	$tmpl->{'standard'} = 0;
	$tmpl->{'default'} = 0;
	}
else {
	# Start with blank
	$tmpl = { };
	}

if ($in{'delete'}) {
	if ($in{'confirm'}) {
		# Just delete this template
		&delete_template($tmpl);
		&webmin_log("delete", "template", $tmpl->{'name'});
		&redirect("edit_newtmpl.cgi");
		}
	else {
		# Ask first, and check for domains using it
		&ui_print_header($tmpl->{'name'}, $text{'tmpl_title5'}, "");

		@users = &get_domain_by("template", $tmpl->{'id'});
		print &ui_confirmation_form(
			"save_tmpl.cgi",
			$text{'tmpl_deletewarn'},
			[ [ "id", $in{'id'} ],
			  [ "delete", 1 ] ],
			[ [ "confirm", $text{'tmpl_deleteconfirm'} ] ],
			undef,
			@users ? &text('tmpl_deleteusers', scalar(@users))
			       : '');

		&ui_print_footer("edit_newtmpl.cgi", $text{'newtmpl_return'},
				 "", $text{'index_return'});
		}
	exit;
	}
elsif ($in{'clone'}) {
	# Re-direct to creation page, in clone mode
	&redirect("edit_tmpl.cgi?new=1&clone=$in{'id'}");
	exit;
	}

# Validate and store all inputs
$oldname = $tmpl->{'name'};
&error_setup($text{'tmpl_err'});
$pfunc = "parse_template_".$in{'editmode'};
&$pfunc($tmpl);

# Check for name clash
if ($in{'new'} || lc($tmpl->{'name'}) ne lc($oldname)) {
	($clash) = grep { lc($_->{'name'}) eq lc($tmpl->{'name'}) &&
			 $_->{'id'} ne $tmpl->{'id'} &&
			 !$_->{'deleted'} } @tmpls;
	$clash && &error($text{'tmpl_eclash'});
	}

# Create or update the template
&save_template($tmpl);
if ($in{'cloneof'} || $in{'cp'}) {
	# Also copy template scripts
	$scripts = &list_template_scripts($cloneof);
	&save_template_scripts($tmpl, $scripts);
	}

# Update the module config for the default template
if ($in{'init'}) {
	$config{'init_template'} = $tmpl->{'id'};
	}
if ($in{'initsub'}) {
	$config{'initsub_template'} = $tmpl->{'id'};
	}
&save_module_config();

&webmin_log($in{'new'} ? "create" : "modify", "template", $tmpl->{'name'});

# Call post-save function
$psfunc = "postsave_template_".$in{'editmode'};
if (defined(&$psfunc)) {
	&$psfunc($tmpl);
	}

# Update all Webmin users for domains on this template, if a template
# section that effects Webmin users was changed
if (!$in{'new'} &&
    &indexof($in{'editmode'}, @template_features_effecting_webmin) >= 0) {
	&set_all_null_print();
	&modify_all_webmin($tmpl->{'standard'} ? undef : $tmpl->{'id'});
	&run_post_actions();
	}

if ($in{'next'}) {
	# And go to next section
	@editmodes = &list_template_editmodes($tmpl);
	$idx = &indexof($in{'editmode'}, @editmodes);
	if ($idx == @editmodes-1) {
		$nextmode = $editmodes[0];
		}
	else {
		$nextmode = $editmodes[$idx+1];
		}
	&redirect("edit_tmpl.cgi?id=$tmpl->{'id'}&editmode=$nextmode");
	}
else {
	# Return to template list
	&redirect("edit_newtmpl.cgi");
	}

# parse_none_def(name)
sub parse_none_def
{
if ($in{$_[0]."_mode"} == 0) {
	return "none";
	}
elsif ($in{$_[0]."_mode"} == 1) {
	return undef;
	}
else {
	$in{$_[0]} =~ s/\t/ /g;
	$in{$_[0]} =~ s/\r//g;
	$in{$_[0]} =~ s/\n/\t/g;
	return $in{$_[0]};
	}
}


