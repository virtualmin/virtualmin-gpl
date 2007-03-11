#!/usr/local/bin/perl
# Write out a HTML file

require './virtual-server-lib.pl';
&ReadParseMime();
&error_setup($text{'html_err'});
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});

# Validate filename
$pub = &public_html_dir($d);
$in{'file'} !~ /\.\./ && $in{'file'} !~ /\0/ ||
	&error($text{'html_efile'});

if ($in{'cancel'}) {
	# Just return to non-editing page
	&redirect("edit_html.cgi?dom=$in{'dom'}");
	}
elsif ($in{'delete'}) {
	# Delete, after asking for confirmation
	if ($in{'confirm'}) {
		&switch_to_domain_user($d);
		&unlink_file("$pub/$in{'file'}");
		&redirect("edit_html.cgi?dom=$in{'dom'}");
		}
	else {
		# Ask first
		&ui_print_header(&domain_in($d), $text{'html_dtitle'}, "");

		@st = stat("$pub/$in{'file'}");
		print "<center>\n";
		print &ui_form_start("save_html.cgi", "form-data");
		print &ui_hidden("dom", $in{'dom'}),"\n";
		print &ui_hidden("delete", 1),"\n";
		print &ui_hidden("file", $in{'file'}),"\n";
		print &text('html_drusure', "<tt>$in{'file'}</tt>",
			    &nice_size($st[7])),"<p>\n";
		print &ui_form_end([ [ "confirm", $text{'html_dok'} ] ]);
		print "</center>\n";

		&ui_print_footer("edit_html.cgi?dom=$in{'dom'}&editok=1&edit=".
				  &urlize($in{'file'}),
				 $text{'html_return'},
				 &domain_footer_link($d),
				 "", $text{'index_return'});
		}
	}
else {
	# Validate inputs
	$data = $in{'body'};
	$data =~ s/\r//g;
	$data || &error($text{'html_enone'});

	# Get the original file, and use its header
	&switch_to_domain_user($d);
	$olddata = &read_file_contents("$pub/$in{'file'}");
	if ($olddata && $data !~ /<body.*>/i) {
		($oldhead, $oldbody, $oldfoot) =
			&html_extract_head_body($olddata);
		$data = $oldhead.$data.$oldfoot;
		}
	elsif (!$olddata && $data !~ /<body.*>/i &&
	       -r "$pub/template.html") {
		# Use head and body from template file
		$tmpldata = &read_file_contents("$pub/template.html");
		($tmplhead, $tmplbody, $tmplfoot) =
			&html_extract_head_body($tmpldata);
		$data = $tmplhead.$data.$tmplfoot;
		}

	# Write out the file
	&open_tempfile(HTML, ">$pub/$in{'file'}");
	&print_tempfile(HTML, $data);
	&close_tempfile(HTML);

	&redirect("edit_html.cgi?dom=$in{'dom'}&edit=".
		  &urlize($in{'file'}));
	}

