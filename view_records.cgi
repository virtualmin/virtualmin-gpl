#!/usr/local/bin/perl
# Show DNS records that should be added to the system that actually hosts DNS
# for this domain

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
$d || &error($text{'edit_egone'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});

&ui_print_header(&domain_in($d), $text{'records_title'}, "");

# Create standard set of records
$temp = &transname();
local $bind8::config{'auto_chroot'} = undef;
local $bind8::config{'chroot'} = undef;
local $bind8::get_chroot_cache = "";
&create_standard_records($temp, $d, $d->{'dns_ip'} || $d->{'ip'});
if ($config{'mail_autoconfig'} && &domain_has_website($d)) {
	&enable_dns_autoconfig($d, &get_autoconfig_hostname($d), $temp);
	}
$recs = &read_file_contents($temp);
&unlink_file($temp);
$recs =~ s/^\$ttl.*\n//;
$recs =~ s/.*NS.*\n//g;
$recs =~ s/.*SOA.*\([^\)]+\).*\n//;

# Show them
print "<b>",$text{'records_viewdesc'},"</b><p>\n";
print &ui_table_start(undef, undef, 2);
print &ui_table_row(undef, "<pre>".&html_escape($recs)."</pre>", 2);
print &ui_table_end();

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});
