#!/usr/local/bin/perl
# Create, update or delete multiple aliases from a text file

require './virtual-server-lib.pl';
&ReadParseMime();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'aliases_ecannot'});
($mleft, $mreason, $mmax, $mhide) = &count_feature("aliases");

# Find the old aliases
@aliases = &list_domain_aliases($d, 1);
foreach $o (split(/\0/, $in{'orig'})) {
	my ($alias) = grep { $_->{'from'} eq $o } @aliases;
	if ($alias) {
		$oldmap{$o} = $alias;
		}
	}

# Do it!
&ui_print_header(&domain_in($d), $text{'aedit_title'}, "");

print $text{'aedit_doing'},"<p>\n";

# Parse and process each line
$in{'aliases'} =~ s/\r//g;
@lines = split(/\n+/, $in{'aliases'});
$lnum = 0;
$count = $ecount = $mcount = $dcount = 0;
USER: foreach $line (@lines) {
	$lnum++;
	next if ($line !~ /\S/);
	local ($name, $desc, @dests) = split(/:/, $line, -1);

	# Make sure needed parameters are given
	if ($name =~ /^\@\S*$/) {
		$name = "*";
		}
	else {
		$name =~ s/\@\S*$//;
		}
	$name = lc($name);
	if (!$name || ($name !~ /^[A-Za-z0-9\.\-\_]+$/ && $name ne "*")) {
		&line_error($text{'amass_ename'});
		next USER;
		}
	if ($name eq "*" && !&can_edit_catchall()) {
		&line_error($text{'amass_ecatchall'});
		next USER;
		}
	if (!@dests) {
		&line_error($text{'amass_edests'});
		next USER;
		}

	# Check if this alias already exists
	$name = "" if ($name eq "*");
	$from = $name."\@".$d->{'dom'};
	$virt = $oldmap{$from};
	$old = $virt ? { %$virt } : undef;
	if (!$virt) {
		$virt = { 'from' => $from };
		}
	$simple= { };

	# Cannot edit the same alias twice
	if ($seen{$from}++) {
		&line_error($text{'aedit_etwice'});
		next USER;
		}

	# Add destinations to the simple object
	foreach $dest (@dests) {
		if ($dest eq "bounce") {
			$simple->{'bounce'} = 1;
			}
		elsif ($dest =~ /^local\s+(\S+)$/) {
			if ($simple->{'local'}) {
				&line_error($text{'amass_elocal'});
				next USER;
				}
			$simple->{'local'} = $1;
			}
		elsif ($dest =~ /^autoreply\s+(.*)$/) {
			if ($simple->{'auto'}) {
				&line_error($text{'amass_eauto'});
				next USER;
				}
			$simple->{'auto'} = 1;
			$simple->{'autotext'} = $1;
			}
		elsif ($dest =~ /^\S+\@\S+$/) {
			push(@{$simple->{'forward'}}, $dest);
			}
		elsif ($dest =~ /^[a-z0-9\.\-\_\+]+$/i) {
			push(@{$simple->{'forward'}}, $dest);
			}
		else {
			&line_error(&text('amass_eunknown', "<tt>$dest</tt>"));
			next USER;
			}
		}
	if ($simple->{'bounce'} &&
	    ($simple->{'local'} || $simple->{'auto'} || $simple->{'forward'})) {
		&line_error($text{'amass_ebounce'});
		next USER;
		}
	&save_simple_alias($d, $virt, $simple);
	$virt->{'cmt'} = $desc;

	# Check if we really changed anything
	if ($old) {
		$oldto = join(" ", sort { $a cmp $b } @{$old->{'to'}});
		$newto = join(" ", sort { $a cmp $b } @{$virt->{'to'}});
		if ($oldto eq $newto &&
		    $old->{'cmt'} eq $virt->{'cmt'}) {
			next USER;
			}
		}

	# Create or update it
	if ($old) {
		&modify_virtuser($old, $virt);
		}
	else {
		if ($mleft == 0) {
			# No more left
			&line_error($text{'alias_ealiaslimit'});
			next USER;
			}
		else {
			&create_virtuser($virt);
			$mleft-- if ($mleft > 0);
			}
		}
	push(@created, $simple);

	# Tell the user
	if ($old) {
		print "<font color=#ffaa00>";
		print &text('aedit_done', "<tt>$virt->{'from'}</tt>");
		print "</font><br>\n";
		$mcount++;
		}
	else {
		print "<font color=#00aa00>";
		print &text('amass_done', "<tt>$virt->{'from'}</tt>");
		print "</font><br>\n";
		$count++;
		}
	}

# Find aliases that are no longer in the list
foreach $o (keys %oldmap) {
	if (!$seen{$o}) {
		$virt = $oldmap{$o};
		$simple = &get_simple_alias($d, $virt);
		if ($simple) {
			&delete_simple_autoreply($d, $simple);
			}
		&delete_virtuser($virt);
		print "<font color=#ff0000>";
		print &text('aedit_deleted', "<tt>$virt->{'from'}</tt>");
		print "</font><br>\n";
		$dcount++;
		}
	}

# Write out autoreply files
foreach $simple (@created) {
	&write_simple_autoreply($d, $simple);
	}

&sync_alias_virtuals($d);
print "<p>\n";
print &text('aedit_complete', $count, $ecount, $mcount, $dcount),"<br>\n";
&run_post_actions();
&webmin_log("manual", "aliases", $count);

&ui_print_footer("list_aliases.cgi?dom=$in{'dom'}", $text{'aliases_return'},
		 "", $text{'index_return'});

sub line_error
{
local ($msg) = @_;
print "<font color=#ff0000>";
if (!$name) {
	print &text('cmass_eline', $lnum, $msg);
	}
else {
	print &text('cmass_eline2', $lnum, $msg, "<tt>$name</tt>");
	}
print "</font><br>\n";
$ecount++;
}

