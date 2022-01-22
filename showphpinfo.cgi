#!/usr/local/bin/perl
# Show PHP info for a given domain and subdir

require './virtual-server-lib.pl';
&ReadParse();
my $d = &get_domain($in{'dom'});
my $dir = $in{'dir'};
&can_edit_domain($d) || &error($text{'phpmode_phpinfo_ecannot'});
if ($dir) {
	if (!-r "$d->{'public_html_path'}/$dir" || !-w "$d->{'public_html_path'}/$dir" ||
		!&is_under_directory($d->{'public_html_path'}, "$d->{'public_html_path'}/$dir")) {
		&error(&text("phpmode_phpinfo_dir_ecannot_dir",
		             "<tt>" . &html_escape($dir) . "</tt>",
		             "<tt>" . &html_escape($d->{'public_html_path'}) . "</tt>"));
		}
	}
my $r = time() . "+" . int(rand() * 1000000);
my $file = "file----phpinfo-$d->{'dom'}-$r.php";
my $ipage = $dir ? "$dir/$file" : "$file";
my $filepath = "$d->{'public_html_path'}/$ipage";
my ($iout, $ierror);
&write_file_contents($filepath, "<?php\nphpinfo();\n?>");
&set_ownership_permissions($d->{'uid'}, $d->{'gid'}, undef, $filepath);
&get_http_connection($d, "/$ipage", \$iout, \$ierror);
&PrintHeader();
if ($ierror) {
	print $ierror;
	}
else {
	print $iout;
	}
unlink($filepath);