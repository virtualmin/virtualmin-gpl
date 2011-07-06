#!/usr/local/bin/perl
# Create or delete a database

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_edit_databases($d) || &error($text{'databases_ecannot'});
$tmpl = &get_template($d->{'template'});

if ($in{'new'}) {
	# Create one, after checking for clashes
	&error_setup($text{'database_err'});
	($dleft, $dreason, $dmax) = &count_feature("dbs");
	$dleft == 0 && &error($text{'database_emax'});

	# Append prefix, if any
	if ($tmpl->{'mysql_suffix'} ne "none") {
		$prefix = &substitute_domain_template(
				$tmpl->{'mysql_suffix'}, $d);
		$prefix = &fix_database_name($prefix, $in{'type'});
		if ($in{'name'} !~ /^\Q$prefix\E/i) {
			$in{'name'} = $prefix.$in{'name'};
			}
		}

	# Validate name
	$in{'name'} = lc($in{'name'});
	$err = &validate_database_name($d, $in{'type'}, $in{'name'});
	&error($err) if ($err);

	# Parse type-specific options
	if (&indexof($in{'type'}, &list_database_plugins()) < 0) {
		# Core DB type
		$ofunc = "creation_parse_$in{'type'}";
		if ($in{'new'} && defined(&$ofunc)) {
			$opts = &$ofunc($d, \%in);
			}
		}
	else {
		# Plugin type options
		if ($in{'new'} &&
		    &plugin_defined($in{'type'}, "creation_parse")) {
			$opts = &plugin_call($in{'type'}, "creation_parse",
					     $d, \%in);
			}
		}

	if (&indexof($in{'type'}, &list_database_plugins()) >= 0) {
		&plugin_call($in{'type'}, "database_clash", $d, $in{'name'}) &&
			&error($text{'database_eclash'});
		}
	else {
		$cfunc = "check_".$in{'type'}."_database_clash";
		&$cfunc($d, $in{'name'}) &&
			&error($text{'database_eclash'});
		}

	# Go for it
	&ui_print_header(&domain_in($d), $text{'database_title1'}, "");
	if (&indexof($in{'type'}, &list_database_plugins()) >= 0) {
		&plugin_call($in{'type'}, "database_create", $d, $in{'name'},
			     $opts);
		}
	else {
		$crfunc = "create_".$in{'type'}."_database";
		&$crfunc($d, $in{'name'}, $opts);
		}
	&save_domain($d);
	&refresh_webmin_user($d);
	&run_post_actions();
	&webmin_log("create", "database", $in{'name'},
		    { 'type' => $in{'type'}, 'dom' => $d->{'dom'} });
	}
elsif ($in{'delete'} && !$in{'confirm'}) {
	# Ask the user if he wants to delete
	&ui_print_header(&domain_in($d), $text{'database_title3'}, "");
	print "<center>",&text('database_rusure', $in{'name'}),"<p>\n";
	print &ui_form_start("save_database.cgi", "post");
	foreach $i ("dom", "name", "type", "delete") {
		print &ui_hidden($i, $in{$i}),"\n";
		}
	print &ui_submit($text{'database_ok'}, "confirm"),"</center>\n";
	print &ui_form_end();
	}
elsif ($in{'delete'}) {
	# Delete now
	if ($in{'name'} eq $d->{'db'} && !&can_edit_database_name()) {
		# Not allowed according to nodbname
		&error($text{'database_edbdef'});
		}
	&ui_print_header(&domain_in($d), $text{'database_title3'}, "");
	if (&indexof($in{'type'}, &list_database_plugins()) >= 0) {
		&plugin_call($in{'type'}, "database_delete", $d, $in{'name'});
		}
	else {
		$dfunc = "delete_".$in{'type'}."_database";
		&$dfunc($d, $in{'name'});
		}
	&save_domain_print($d);
	&refresh_webmin_user($d);
	&run_post_actions();
	&webmin_log("delete", "database", $in{'name'},
		    { 'type' => $in{'type'}, 'dom' => $d->{'dom'} });
	}
elsif ($in{'disc'}) {
	# Remove from server's list
	&ui_print_header(&domain_in($d), $text{'database_title4'}, "");
	@dbs = split(/\s+/, $d->{'db_'.$in{'type'}});
	@dbs = grep { $_ ne $in{'name'} } @dbs;
	$d->{'db_'.$in{'type'}} = join(" ", @dbs);

	# Call the revoke function to actually remove access
	$gfunc = "revoke_".$in{'type'}."_database";
	if (defined(&$gfunc)) {
		&$gfunc($d, $in{'name'});
		}

	&save_domain_print($d);
	&refresh_webmin_user($d);
	&run_post_actions();
	&webmin_log("export", "database", $in{'name'},
		    { 'type' => $in{'type'}, 'dom' => $d->{'dom'} });
	}
elsif ($in{'manage'}) {
	# Just redirect to module to manage
	($db) = grep { $_->{'name'} eq $in{'name'} &&
		       $_->{'type'} eq $in{'type'} } &domain_databases($d);
	&redirect($db->{'link'});
	exit;
	}

&ui_print_footer("list_databases.cgi?dom=$in{'dom'}", $text{'databases_return'},
		 &domain_footer_link($d),
		 "", $text{'index_return'});

sub save_domain_print
{
&$first_print($text{'setup_save'});
&save_domain($_[0]);
&$second_print($text{'setup_done'});
}
