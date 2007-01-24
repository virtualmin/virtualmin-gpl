#!/usr/local/bin/perl
# save_vfile.cgi
# Save an autoresponder file and alias

require './virtual-server-lib.pl';
&ReadParseMime();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'aliases_ecannot'});
&can_edit_afiles() || &error($text{'vfile_ecannot'});
$what = $in{'alias'} ? 'alias' : 'user';

# Find the alias and its settings
if ($what eq "alias") {
	@aliases = &list_domain_aliases($d);
	($virt) = grep { $_->{'from'} eq $in{$what} } @aliases;
	}
else {
	@users = &list_domain_users($d);
	($user) = grep { $_->{'user'} eq $in{$what} } @users;
	}

# Validate inputs
$in{'time'} =~ /^\d+$/ || &error($text{'vfile_etime'});
$in{'num'} =~ /^\d+$/ || &error($text{'vfile_enum'});
$in{'dir_def'} || -d $in{'dir'} || &error($text{'vfile_edir'});
$in{'from'} ne 'other' || $in{'other'} =~ /^\S+$/ ||
	&error($text{'vfile_eother'});

# Update the alias
$val = "|$config{'vpopmail_auto'} $in{'time'} $in{'num'} $in{'file'}";
if ($in{'dir_def'}) {
	$val .= " ".$in{'file'}.".log";
	}
else {
	$val .= " ".$in{'dir'};
	}
if ($in{'flag'} ne "") {
	$val .= " ".$in{'flag'};
	}
elsif ($in{'from'} ne "") {
	$val .= " 0";
	}
if ($in{'from'} eq 'other') {
	$val .= " ".$in{'other'};
	}
elsif ($in{'from'} ne '') {
	$val .= " ".$in{'from'};
	}
if ($virt) {
	$virt->{'to'}->[$in{'idx'}] = $val;
	&modify_virtuser($virt, $virt);
	}
else {
	$user->{'to'}->[$in{'idx'}] = $val;
	&modify_user($user, $user, $d);
	}

# Save the file
$in{'text'} =~ s/\r//g;
&open_lock_tempfile(FILE, ">$in{'file'}", 1) ||
	&error(&text('rfile_ewrite', $in{'file'}, $dom->{'user'}, $!));
&print_tempfile(FILE, $in{'text'});
&close_tempfile(FILE);
&webmin_log("save", "vfile", $in{'file'});

&redirect("edit_$what.cgi?$what=$in{$what}&dom=$in{'dom'}");

