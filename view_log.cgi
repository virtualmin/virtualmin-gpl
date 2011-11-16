#!/usr/local/bin/perl
# Display the webalizer report for some domain

require './virtual-server-lib.pl';
&require_webalizer();
&ReadParse();

$ENV{'PATH_INFO'} =~ /^\/([^\/]+)(\/.*)$/ ||
	&error($webalizer::text{'view_epath'});
$did = $1;
$file = $2;
$d = &get_domain($did);
$log = &get_website_log($d);
$file =~ /\.\./ || $file =~ /\<|\>|\||\0/ &&
	&error($webalizer::text{'view_efile'});

$lconf = &webalizer::get_log_config($log) ||
	&error($webalizer::text{'view_elog'}." : $log");
$full = "$lconf->{'dir'}$file";
open(FILE, $full) || &error($webalizer::text{'view_eopen'}." : $full");

# Display file contents
if ($full =~ /\.(html|htm)$/i) {
	while(read(FILE, $buf, 1024)) {
		$data .= $buf;
		}
	close(FILE);
	$data =~ /<TITLE>(.*)<\/TITLE>/i;
	$title = $1;
	$data =~ s/^[\000-\377]*<BODY.*>//i;
	$data =~ s/<\/BODY>[\000-\377]*$//i;

	&ui_print_header(undef, $title || $text{'view_title'}, "");
	print $data;
	&ui_print_footer("/$module_name/edit_domain.cgi?dom=$d->{'id'}",
			 $text{'edit_return'},
			 "/$module_name/", $text{'index_return'});
	}
else {
	print "Content-type: ",$full =~ /\.png$/i ? "image/png" :
			       $full =~ /\.gif$/i ? "image/gif" :
			       $full =~ /\.(jpg|jpeg)$/i ? "image/jpeg" :
			       $full =~ /\.(html|htm)$/i ? "text/html" :
							   "text/plain","\n";
	print "\n";
	while(read(FILE, $buf, 1024)) {
		print $buf;
		}
	close(FILE);
	}

