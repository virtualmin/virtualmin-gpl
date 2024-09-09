#!/usr/local/bin/perl
# Show PHP info for a given domain and subdir

require './virtual-server-lib.pl';
&ReadParse();
my $d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'phpmode_phpinfo_ecannot'});
my $dir = $in{'dir'};
my $public_html = &public_html_dir($d);
if ($dir) {
	if (!-r "$public_html/$dir" || !-w "$public_html/$dir" ||
		!&is_under_directory($public_html, "$public_html/$dir")) {
		&error(&text("phpmode_phpinfo_dir_ecannot_dir",
		             "<tt>" . &html_escape($dir) . "</tt>",
		             "<tt>" . &html_escape($public_html) . "</tt>"));
		}
	}
my $r = time() . "+" . int(rand() * 1000000);
my $file = "file----phpinfo-$d->{'dom'}-$r.php";
my $ipage = $dir ? "$dir/$file" : "$file";
my $filepath = "$public_html/$ipage";
my ($iout, $ierror);
&write_as_domain_user($d, sub {
	&write_file_contents($filepath, "<?php\nif (function_exists('exec')){echo '<div style=\"font-size:115%;font-weight:500;text-align:center;margin: 1em auto;\">PHP is running as user: <span style=\"color:#5d73e8\">'.exec('whoami').'</span></div>';}\nphpinfo();\n?>");
	});
&get_http_connection($d, "/$ipage", \$iout, \$ierror);
&PrintHeader();
if ($ierror) {
	print $ierror;
	}
else {
	print $iout;
	}
&unlink_file_as_domain_user($d, $filepath);