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

	# Validate name
	if ($tmpl->{'mysql_suffix'} ne "none") {
		$prefix = &substitute_domain_template(
				$tmpl->{'mysql_suffix'}, $d);
		$prefix =~ s/-/_/g;
		$prefix =~ s/\./_/g;
		$in{'name'} = $prefix.$in{'name'};
		}
	$in{'name'} =~ /^[a-z0-9\_]+$/i && $in{'name'} =~ /^[a-z]/i ||
		&error($text{'database_ename'});

	# Parse type-specific options
	if (&indexof($in{'type'}, @database_plugins) < 0) {
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

	if (&indexof($in{'type'}, @database_plugins) >= 0) {
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
	if (&indexof($in{'type'}, @database_plugins) >= 0) {
		&plugin_call($in{'type'}, "database_create", $d, $in{'name'},
			     $opts);
		}
	else {
		$crfunc = "create_".$in{'type'}."_database";
		&$crfunc($d, $in{'name'}, $opts);
		}
	&save_domain($d);
	&refresh_webmin_user($d);
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
	&ui_print_header(&domain_in($d), $text{'database_title3'}, "");
	if (&indexof($in{'type'}, @database_plugins) >= 0) {
		&plugin_call($in{'type'}, "database_delete", $d, $in{'name'});
		}
	else {
		$dfunc = "delete_".$in{'type'}."_database";
		&$dfunc($d, $in{'name'});
		}
	&save_domain_print($d);
	&refresh_webmin_user($d);
	&webmin_log("delete", "database", $in{'name'},
		    { 'type' => $in{'type'}, 'dom' => $d->{'dom'} });
	}
elsif ($in{'disc'}) {
	# Remove from server's list
	&ui_print_header(&domain_in($d), $text{'database_title4'}, "");
	@dbs = split(/\s+/, $d->{'db_'.$in{'type'}});
	@dbs = grep { $_ ne $in{'name'} } @dbs;
	$d->{'db_'.$in{'type'}} = join(" ", @dbs);
	&save_domain_print($d);
	&refresh_webmin_user($d);
	&webmin_log("export", "database", $in{'name'},
		    { 'type' => $in{'type'}, 'dom' => $d->{'dom'} });
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
