#!/usr/local/bin/perl
# save_rfile.cgi
# Save an autoreply file

require './virtual-server-lib.pl';
&ReadParseMime();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'aliases_ecannot'});
&can_edit_afiles() || &error($text{'rfile_ecannot'});

$in{'replies_def'} || $in{'replies'} =~ /^\/\S+/ ||
	&error($text{'rfile_ereplies'});
$in{'period_def'} || $in{'period'} =~ /^\d+$/ ||
	&error($text{'rfile_eperiod'});

$in{'text'} =~ s/\r//g;
&lock_file($in{'file'});
&open_tempfile_as_domain_user($d, FILE, ">$in{'file'}", 1) ||
	&error(&text('rfile_ewrite', $in{'file'}, $dom->{'user'}, $!));
if (!$in{'replies_def'}) {
	&print_tempfile(FILE, "Reply-Tracking: $in{'replies'}\n");
	}
if (!$in{'period_def'}) {
	&print_tempfile(FILE, "Reply-Period: $in{'period'}\n");
	}
&print_tempfile(FILE, $in{'text'});
&close_tempfile_as_domain_user($d, FILE);
&unlock_file($in{'file'});
&run_post_actions_silently();
&webmin_log("save", "rfile", $in{'file'});

$what = $in{'alias'} ? 'alias' : 'user';
&redirect("edit_$what.cgi?$what=$in{$what}&dom=$in{'dom'}&unix=1");

