#!/usr/local/bin/perl
# Update the database passwords for a domain

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_edit_databases($d) || &error($text{'databases_ecannot'});
&error_setup($text{'dbpass_err'});
$oldd = { %$d };

# Do the change
&ui_print_unbuffered_header(&domain_in($d), $text{'dbpass_title'}, "");

# Run the before command
&set_domain_envs($oldd, "DBPASS_DOMAIN", $d);
$merr = &making_changes();
&reset_domain_envs($oldd);
&error(&text('setup_emaking', "<tt>$merr</tt>")) if (defined($merr));

# Call the database change functions
foreach $f (@database_features) {
	if (defined($in{$f}) && $in{$f."_def"} != 2) {
		$cfunc = "set_".$f."_pass";
		&$cfunc($d, $in{$f."_def"} ? undef : $in{$f});
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
&set_domain_envs($d, "MODIFY_DOMAIN", undef, $oldd);
local $merr = &made_changes();
&$second_print(&text('setup_emade', "<tt>$merr</tt>")) if (defined($merr));
&reset_domain_envs($d);

&webmin_log("dbpass", "domain", $d->{'dom'}, $d);

&ui_print_footer("list_databases.cgi?dom=$in{'dom'}", $text{'databases_return'},
		 &domain_footer_link($d),
		 "", $text{'index_return'});

