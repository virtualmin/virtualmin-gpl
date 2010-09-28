#!/usr/bin/perl
# Enable or disable DKIM

require './virtual-server-lib.pl';
&error_setup($text{'dkim_err'});
&can_edit_templates() || &error($text{'dkim_ecannot'});
&ReadParse();

# Validate inputs
$dkim = &get_dkim_config();
$dkim ||= { };
$in{'domain'} || &error($text{'dkim_edomain'});
$in{'selector'} =~ /^[a-z0-9\.\-\_]+/i || &error($text{'dkim_eselector'});
$dkim->{'domain'} = $in{'domain'};
$dkim->{'selector'} = $in{'selector'};
$dkim->{'enabled'} = $in{'enabled'};

# Start the process
&ui_print_unbuffered_header(undef, $text{'dkim_title'}, "");

&obtain_lock_dkim();
if ($in{'enabled'}) {
	# Turn on DKIM, or change domain
	&enable_dkim($dkim);
	}
else {
	# Turn off DKIM
	&disable_dkim($dkim);
	}
&release_lock_dkim();
&webmin_log($in{'enabled'} ? "enable" : "disable", "dkim");

&ui_print_footer("", $text{'index_return'});

