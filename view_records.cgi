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
$recs = [ ];
&create_standard_records($recs, $temp, $d, $d->{'dns_ip'} || $d->{'ip'});
if ($config{'mail_autoconfig'} && &domain_has_website($d)) {
	# Add autoconfig records
	foreach my $autoconfig (&get_autoconfig_hostname($d)) {
		&create_dns_autoconfig_records($d, $autoconfig, $temp, $recs);
		}
	}
if ($d->{'mail'} && !&check_dkim() && ($dkim = &get_dkim_config()) &&
    $dkim->{'enabled'}) {
	# Add DKIM record
	&add_domain_dkim_record($d, $dkim, $recs, $temp);
	}
@$recs = grep { $_->{'type'} ne 'NS' &&
		$_->{'type'} ne 'SOA' &&
		!$_->{'defttl'} } @$recs;
$out = &format_dns_text_records(&dns_records_to_text(@$recs));

# Show them
print &ui_alert_box($text{'records_viewdesc'}, 'warn', undef, undef, "");
print &ui_table_start(undef, undef, 2);
print &ui_table_row(undef, "<pre>".&html_escape($out)."</pre>", 2);
print &ui_table_end();

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});
