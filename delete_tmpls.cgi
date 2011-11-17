#!/usr/local/bin/perl
# Delete one or more server templates

require './virtual-server-lib.pl';
&error_setup($text{'tdelete_err'});
&can_edit_templates() || &error($text{'newtmpl_ecannot'});
&ReadParse();
@d = split(/\0/, $in{'d'});
@d || &error($text{'tdelete_enone'});

@tmpls = &list_templates();
foreach $tid (@d) {
	($tmpl) = grep { $_->{'id'} == $tid } @tmpls;
	if ($tmpl) {
		push(@deltmpls, $tmpl);
		push(@users, &get_domain_by("template", $tmpl->{'id'}));
		}
	}

if ($in{'confirm'}) {
	# Do the deletion
	foreach $tmpl (@deltmpls) {
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
		[ map { [ "d", $_ ] } @d ],
		[ [ "confirm", $text{'tdelete_confirm'} ] ],
		undef,
		@users ? &text('tdelete_users',
			   join(" ", map { &show_domain_name($_) } @users)),
		       : '');

	&ui_print_footer("edit_newtmpl.cgi", $text{'newtmpl_return'},
			 "", $text{'index_return'});
	}


