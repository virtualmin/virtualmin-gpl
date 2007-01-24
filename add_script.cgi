#!/usr/local/bin/perl
# Add some third-party scripts

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newscripts_ecannot'});
&error_setup($text{'addscripts_err'});
&ReadParseMime();

# Get the file
if ($in{'source'} == 0) {
	# Local file
	-r $in{'local'} || &error($text{'addscripts_elocal'});
	$file = $in{'local'};
	$name = $in{'local'};
	}
elsif ($in{'source'} == 1) {
	# Uploaded file
	$file = &transname();
	$in{'upload'} || &error($text{'addscripts_eupload'});
	$name = $in{'upload_filename'};
	&open_tempfile(FILE, ">$file");
	print FILE $in{'upload'};
	&close_tempfile(FILE);
	}
elsif ($in{'source'} == 2) {
	# From URL
	($host, $port, $page, $ssl) = &parse_http_url($in{'url'});
	$host || &error($text{'addscripts_eurl'});
	$file = &transname();
	$name = $page;
	&http_download($host, $port, $page, $file, undef, undef, $ssl);
	}

# Check file type (tar.gz, tar.Z or just .pl script)
open(PFILE, $file);
read(PFILE, $two, 2);
close(PFILE);
if ($two eq "\037\235") {
	$cmd = "uncompress -C ".quotemeta($file)." | tar xf -";
	}
elsif ($two eq "\037\213") {
	$cmd = "gunzip -c ".quotemeta($file)." | tar xf -";
	}
if ($cmd) {
	# Extract to temp dir
	$tempdir = &transname();
	&make_dir($tempdir, 0755);
	$out = &backquote_command("cd $tempdir && $cmd");
	$? && &error(&text('addscripts_etar', $out));
	opendir(DIR, $tempdir);
	foreach $f (readdir(DIR)) {
		next if ($f eq "." || $f eq "..");
		push(@files, [ "$tempdir/$f", $f ]);
		}
	closedir(DIR);
	}
else {
	# Just using a single file
	$name =~ s/^(.*)[\\\/]//;
	@files = ( [ $file, $name ] );
	}
@files || &error($text{'addscripts_enone'});

# Validate filenames
foreach $f (@files) {
	$f->[1] =~ /^(\S+)\.pl$/ || &error(&text('addscripts_efile', $f->[1]));
	}

# Copy into place
&make_dir($scripts_directories[0], 0755);
foreach $f (@files) {
	&lock_file("$scripts_directories[0]/$f->[1]");
	&execute_command("cp ".quotemeta($f->[0]).
			 " $scripts_directories[0]/$f->[1]");
	&unlock_file("$scripts_directories[0]/$f->[1]");
	}

# Tell the user
&ui_print_header(undef, $text{'addscripts_title'}, "");
if (@files == 1) {
	($one = $files[0]->[1]) =~ s/\.pl$//;
	$script = &get_script($one);
	print &text('addscripts_done1', $script->{'desc'}),"<p>\n";
	}
else {
	print &text('addscripts_done', scalar(@files)),"<p>\n";
	}
&ui_print_footer("edit_newscripts.cgi", $text{'newscripts_return'});

&webmin_log("add", "scripts", scalar(@files),
	    { 'scripts' => [ map { $_->[1] } @files ] });

