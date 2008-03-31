#!/usr/local/bin/perl
# Update the database usernames for a domain

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_edit_databases($d) || &error($text{'databases_ecannot'});
&error_setup($text{'dbname_err'});
$oldd = { %$d };

# Validate inputs
foreach $f (@database_features) {
	if (defined($in{$f}) && !$in{$f."_def"}) {
		# Validate syntax
		$in{$f} =~ /^[a-z0-9\.\-\_]+$/ || &error($text{'dbname_euser'});
		$ofunc = "${f}_user";
		$un = &$ofunc($d);
		$un ne $in{$f} || &error($text{'dbname_esame'});

		# Check for a clash
		$sfunc = "set_${f}_user";
		&$sfunc($d, $in{$f});
		$cfunc = "check_${f}_clash";
		&$cfunc($d, 'user') && error($text{'dbname_eclash'});
		}
	}

# Do the change
&ui_print_unbuffered_header(&domain_in($d), $text{'dbname_title'}, "");

# Run the before command
&set_domain_envs($oldd, "DBNAME_DOMAIN", $d);
$merr = &making_changes();
&reset_domain_envs($oldd);
&error(&text('setup_emaking', "<tt>$merr</tt>")) if (defined($merr));

# Call the database change functions
foreach $f (@database_features) {
	if (defined($in{$f}) && !$in{$f."_def"}) {
		$mfunc = "modify_${f}";
		&$mfunc($d, $oldd);
		}
	}

# Update Webmin user, so that it logs in correctly
&modify_webmin($d, $oldd);
&run_post_actions();

# Save the domain object
&$first_print($text{'save_domain'});
&save_domain($d);
&$second_print($text{'setup_done'});

# Run the after command
&set_domain_envs($d, "MODIFY_DOMAIN");
&made_changes();
&reset_domain_envs($d);

&webmin_log("dbname", "domain", $d->{'dom'}, $d);

&ui_print_footer("list_databases.cgi?dom=$in{'dom'}", $text{'databases_return'},
		 &domain_footer_link($d),
		 "", $text{'index_return'});

