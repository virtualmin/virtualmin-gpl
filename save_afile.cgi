#!/usr/local/bin/perl
# save_afile.cgi
# Save an addresses file

require './virtual-server-lib.pl';
&ReadParseMime();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'aliases_ecannot'});
&can_edit_afiles() || &error($text{'afile_ecannot'});

$in{'text'} =~ s/\r//g;
$in{'text'} =~ s/\n*$/\n/;
&lock_file($in{'file'});
&open_tempfile_as_domain_user($d, FILE, ">$in{'file'}", 1, 1) ||
	&error(&text('afile_ewrite', $in{'file'}, $dom->{'user'}, $!));
print FILE $in{'text'};
&close_tempfile_as_domain_user($d, FILE);
&unlock_file($in{'file'});
&webmin_log("save", "afile", $in{'file'});

$what = $in{'alias'} ? 'alias' : 'user';
&redirect("edit_$what.cgi?$what=$in{$what}&dom=$in{'dom'}");

