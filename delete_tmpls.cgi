#!/usr/local/bin/perl
# Delete one or more server templates

require './virtual-server-lib.pl';
&ReadParse();
&licence_status();
&error_setup($in{'default'} || $in{'defaultsub'} ? $text{'tdelete_err2'}
						 : $text{'tdelete_err'});
&can_edit_templates() || &error($text{'newtmpl_ecannot'});
@d = split(/\0/, $in{'d'});
@d || &error($text{'tdelete_enone'});

# Get selected templates
@tmpls = &list_templates();
foreach $tid (@d) {
	($tmpl) = grep { $_->{'id'} == $tid } @tmpls;
	if ($tmpl) {
		push(@deltmpls, $tmpl);
		push(@users, &get_domain_by("template", $tmpl->{'id'}));
		}
	}

if ($in{'default'} || $in{'defaultsub'}) {
	# Just changing the default template
	&lock_file($module_config_file);
	$tmpl = $deltmpls[0];
	if ($in{'default'}) {
		$tmpl->{'id'} == 1 && &error($text{'tdelete_edefsub'});
		$config{'init_template'} = $tmpl->{'id'};
		}
	else {
		$tmpl->{'id'} == 0 && &error($text{'tdelete_edeftop'});
		$config{'initsub_template'} = $tmpl->{'id'};
		}
	&unlock_file($module_config_file);
	&save_module_config();
	&webmin_log("default", "templates", $tmpl->{'name'});
	&redirect("edit_newtmpl.cgi");
	}
elsif ($in{'confirm'}) {
	# Do the deletion
	foreach $tmpl (@deltmpls) {
		$tmpl->{'standard'} && &error($text{'newtmpl_edelete'});
		&delete_template($tmpl);
		}
	&run_post_actions_silently();
	&webmin_log("delete", "templates", scalar(@d));
	&redirect("edit_newtmpl.cgi");
	}
else {
	# Ask first
	&ui_print_header(undef, $text{'tdelete_title'}, "");

	print &ui_confirmation_form(
		"delete_tmpls.cgi",
		&text('tdelete_warn',
		      join(", ", map { $_->{'name'} } @deltmpls)),
		[ [ 'delete', 1 ],
		  (map { [ "d", $_ ] } @d) ],
		[ [ "confirm", $text{'tdelete_confirm'} ] ],
		undef,
		@users ? &text('tdelete_users',
			   join(" ", map { &show_domain_name($_) } @users))
		       : '');

	&ui_print_footer("edit_newtmpl.cgi", $text{'newtmpl_return'},
			 "", $text{'index_return'});
	}


