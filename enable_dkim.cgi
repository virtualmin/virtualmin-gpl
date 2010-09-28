#!/usr/bin/perl
# Enable or disable DKIM

require './virtual-server-lib.pl';
&error_setup($text{'dkim_err'});
&can_edit_templates() || &error($text{'dkim_ecannot'});
&ReadParse();

# Validate inputs
$in{'domain'} || &error($text{'dkim_edomain'});
$in{'selector'} =~ /^[a-z0-9\.\-\_]+/i || &error($text{'dkim_eselector'});

# Start the process
&ui_print_unbuffered_header(undef, $text{'dkim_title'}, "");

if ($in{'enabled'}) {
	# Turn on DKIM, or change domain
	# XXX
	}
else {
	# Turn off DKIM
	# XXX
	}

&ui_print_footer("", $text{'index_return'});

