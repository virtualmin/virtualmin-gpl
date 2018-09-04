#!/usr/local/bin/perl
# Update the allowed remote hosts for a domain

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_edit_databases($d) || &error($text{'databases_ecannot'});
&can_allowed_db_hosts() || &error($text{'databases_ecannot'});
&error_setup($text{'dbhosts_err'});

# Validate inputs
@hosts = split(/\r?\n/, $in{'hosts'});
@hosts || &error($text{'dbhosts_enone'});
foreach $h (@hosts) {
	$h =~ /^[a-z0-9\.\-\_\%\\:]+$/i ||
		&error(&text('dbhosts_ehost', $h));
	}

# Do the change
&ui_print_unbuffered_header(&domain_in($d), $text{'dbhosts_title'}, "");

# Call the change function
&$first_print(&text('dbhosts_doing',
		    $text{'databases_'.$in{'type'}},
		    join(", ", map { "<tt>$_</tt>" } @hosts)));
$afunc = "save_".$in{'type'}."_allowed_hosts";
$err = &$afunc($d, \@hosts);
if ($err) {
	&$second_print(&text('dbhosts_failed', $err));
	}
else {
	$ufunc = $in{'type'}."_user";
	&$second_print(&text('dbhosts_done', "<tt>".&$ufunc($d)."</tt>"));
	}

&run_post_actions();

&webmin_log("dbhosts", "domain", $d->{'dom'}, $d);

&ui_print_footer("list_databases.cgi?dom=$in{'dom'}", $text{'databases_return'},
		 &domain_footer_link($d),
		 "", $text{'index_return'});

