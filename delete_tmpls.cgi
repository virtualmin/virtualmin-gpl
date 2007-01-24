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
		&delete_template($tmpl);
		}
	}
&webmin_log("delete", "templates", scalar(@d));
&redirect("edit_newtmpl.cgi");

