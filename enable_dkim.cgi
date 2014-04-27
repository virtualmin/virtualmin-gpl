#!/usr/bin/perl
# Enable or disable DKIM

require './virtual-server-lib.pl';
&error_setup($text{'dkim_err'});
&can_edit_templates() || &error($text{'dkim_ecannot'});
&ReadParse();

# Validate inputs
$dkim = &get_dkim_config();
$dkim ||= { };
$in{'selector'} =~ /^[a-z0-9\.\-\_]+/i || &error($text{'dkim_eselector'});
$dkim->{'selector'} = $in{'selector'};
$dkim->{'enabled'} = $in{'enabled'};
$dkim->{'verify'} = $in{'verify'};
$dkim->{'sign'} = 1;
@extra = split(/\s+/, $in{'extra'});
foreach $e (@extra) {
	$e =~ /^[a-z0-9\-\_\.\*]+$/ || &error(&text('dkim_eextra', $e));
	}
$dkim->{'extra'} = \@extra;
@exclude = split(/\s+/, $in{'exclude'});
foreach $e (@exclude) {
	$e =~ /^[a-z0-9\-\_\.\*]+$/ || &error(&text('dkim_eexclude', $e));
	}
$dkim->{'exclude'} = \@exclude;

if ($in{'enabled'}) {
	# Turn on DKIM, or change settings
	$in{'size'} =~ /^\d+$/ && $in{'size'} >= 512 ||
		&error($text{'dkim_esize'});
	&ui_print_unbuffered_header(undef, $text{'dkim_title1'}, "");
	$ok = &enable_dkim($dkim, $in{'newkey'}, $in{'size'});
	if (!$ok) {
		print "<b>$text{'dkim_somefail'}</b><p>\n";
		}
	else {
		$config{'dkim_enabled'} = 1;
		}
	}
else {
	# Turn off DKIM
	&ui_print_unbuffered_header(undef, $text{'dkim_title2'}, "");
	$ok = &disable_dkim($dkim);
	$config{'dkim_enabled'} = 0;
	}
&lock_file($module_config_file);
&save_module_config();
&unlock_file($module_config_file);
&clear_links_cache();
&run_post_actions();
&webmin_log($in{'enabled'} ? "enable" : "disable", "dkim");

&ui_print_footer("dkim.cgi", $text{'dkim_return'});

