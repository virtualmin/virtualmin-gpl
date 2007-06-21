#!/usr/local/bin/perl
# Create multiple mail aliases from a batch file

require './virtual-server-lib.pl';
&ReadParseMime();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'aliases_ecannot'});
&error_setup($text{'amass_err'});

# Validate source file
if ($in{'file_def'} == 1) {
	# Server-side file
	&master_admin() || &error($text{'cmass_elocal'});
	open(LOCAL, $in{'local'}) || &error($text{'cmass_elocal2'});
	while(<LOCAL>) {
		$source .= $_;
		}
	close(LOCAL);
	$src = "<tt>$in{'local'}</tt>";
	}
elsif ($in{'file_def'} == 0) {
	# Uploaded file
	$in{'upload'} =~ /\S/ || &error($text{'cmass_eupload'});
	$source = $in{'upload'};
	$src = $text{'cmass_uploaded'};
	}
elsif ($in{'file_def'} == 2) {
	# Pasted text
	$in{'text'} =~ /\S/ || &error($text{'cmass_etext'});
	$source = $in{'text'};
	$src = $text{'cmass_texted'};
	}
$source =~ s/\r//g;

# Do it!
&ui_print_header(&domain_in($d), $text{'amass_title'}, "", "amass");

print &text('amass_doing', $src),"<p>\n";

@aliases = &list_domain_aliases($d);

# Split into lines, and process each one
@lines = split(/\n+/, $source);
$lnum = 0;
$count = $ecount = 0;
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
	if (!@dests) {
		&line_error($text{'amass_edests'});
		next USER;
		}

	# Create the simple alias object
	$name = "%1" if ($name eq "*");
	local $virt = { 'from' => $name."\@".$d->{'dom'},
		    	'cmt' => $desc };
	local $simple= { };

	# Check for a clash
	($clash) = grep { $_->{'from'} eq $virt->{'from'} } @aliases;
	if ($clash) {
		&line_error($text{'amass_eclash'});
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
		}
	if ($simple->{'bounce'} &&
	    ($simple->{'local'} || $simple->{'auto'} || $simple->{'forward'})) {
		&line_error($text{'amass_ebounce'});
		next USER;
		}

	# Create it
	&save_simple_alias($d, $virt, $simple);
	&create_virtuser($virt);
	push(@created, $simple);
	push(@aliases, $virt);

	print "<font color=#00aa00>",
	      &text('amass_done', "<tt>$virt->{'from'}</tt>"),"</font><br>\n";
	$count++;
	}

print "<p>\n";
print &text('cmass_complete', $count, $ecount),"<br>\n";
&webmin_log("create", "aliases", $count);

# Write out autoreply files. This has to be done last, as it is done
# with domain owner permissions
&switch_to_domain_user($d);
foreach $simple (@created) {
	&write_simple_autoreply($d, $simple);
	}

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

