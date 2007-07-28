#!/usr/local/bin/perl
# Upload one file to the public HTML directory

require './virtual-server-lib.pl';
&ReadParseMime();
&error_setup($text{'upload_err'});
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_edit_html() || &error($text{'edit_ecannot'});

# Validate inputs
$pub = &public_html_dir($d);
$in{'upload'} || &error($text{'upload_enone'});
$in{'upload_filename'} || &error($text{'upload_enone2'});

# Work out filename, and write out
$in{'upload_filename'} =~ s/^.*[\\\/]//;
&switch_to_domain_user($d);
&open_tempfile(UPLOAD, ">$pub/$in{'upload_filename'}");
&print_tempfile(UPLOAD, $in{'upload'});
&close_tempfile(UPLOAD);

if ($in{'upload_filename'} =~ /\.(htm|html)$/i) {
	# Edit this new file
	&redirect("edit_html.cgi?dom=$in{'dom'}&editok=1&edit=".
	 	  &urlize($in{'upload_filename'}));
	}
else {
	# Show confirmation page
	&ui_print_header(&domain_in($d), $text{'upload_title'}, "");

	print &text('upload_done', "<tt>$in{'upload_filename'}</tt>",
		    &nice_size(length($in{'upload'}))),"<p>\n";

	&ui_print_footer("edit_html.cgi?dom=$in{'dom'}", $text{'html_return'},
			 &domain_footer_link($d),
			 "", $text{'index_return'});
	}

