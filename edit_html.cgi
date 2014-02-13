#!/usr/local/bin/perl
# Show a form for editing or creating an HTML page in a virtual server

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_edit_html() || &error($text{'edit_ecannot'});

$editing = $in{'editok'} || $in{'textok'} ? 1 :
	   $in{'createok'} || $in{'create'} ? 2 : 0;
&ui_print_header(&domain_in($d), $text{'html_title'}, "", undef, 0, 0, 0,
		 undef, undef,
		 $editing ? &virtualmin_ui_html_editor_bodytags() : undef);

# Find web pages in server's directory
$pub = &public_html_dir($d);
opendir(DIR, $pub);
foreach $f (readdir(DIR)) {
	if ($f =~ /\.(htm|html)/i) {
		push(@html, $f);
		}
	}
closedir(DIR);

# Show web page selection form
print &ui_form_start("edit_html.cgi");
print &ui_hidden("dom", $in{'dom'}),"\n";
print "<table>\n";

# Creating new HTML doc
print "<tr>\n";
print "<td><b>$text{'html_create'}</b></td>\n";
print "<td>",&ui_textbox("create", $in{'create'}, 40),"</td>\n";
print "<td>",&ui_submit($text{'html_createok'}, 'createok'),"</td>\n";
print "</tr>\n";

if (@html) {
	# Select existing HTML doc
	print "<tr>\n";
	print "<td><b>$text{'html_edit'}</b></td>\n";
	print "<td>",&ui_select("edit", $in{'edit'},
				[ map { [ $_ ] } @html ]),"</td>\n";
	print "<td>",&ui_submit($text{'html_editok'}, 'editok')," ",
		     &ui_submit($text{'html_textok'}, 'textok'),"</td>\n";
	print "</tr>\n";
	}

print &ui_form_end();
$forms++;

# Show file upload form
print &ui_form_start("upload_html.cgi", "form-data");
print &ui_hidden("dom", $in{'dom'}),"\n";
print "<tr>\n";
print "<td><b>$text{'html_upload'}</b></td>\n";
print "<td>",&ui_upload("upload", 30),"</td>\n";
print "<td>",&ui_submit($text{'html_uploadok'}, 'uploadok'),"</td>\n";
print "</tr>\n";
print &ui_form_end();
$forms++;

# Show form to apply a style
print &ui_form_start("apply_style.cgi", "post");
print &ui_hidden("dom", $in{'dom'}),"\n";
print "<tr>\n";
print "<td><b>$text{'html_apply'}</b></td>\n";
print "<td>",&content_style_chooser("style", undef, $forms),"</td>\n";
print "<td>",&ui_submit($text{'html_styleok'}, 'styleok'),"</td>\n";
print "</tr>\n";
print &ui_form_end();
$forms++;

print "</table>\n";

# Tell the user if something was saved
$url = &get_domain_url($d);
if ($in{'saved'}) {
	print "<p><b>",&text('html_saved', "<a href='$url/$in{'edit'}' target=_blank><tt>$in{'edit'}</tt></a>"),"</b><p>\n";
	}

if ($editing) {
	if ($editing == 1) {
		# Read the selected HTML file
		$in{'edit'} !~ /\.\./ && $in{'edit'} !~ /\0/ ||
			&error($text{'html_efile'});
		$data = &read_file_contents_as_domain_user(
				$d, "$pub/$in{'edit'}");
		}
	else {
		# Read a template file if one exists
		if (-r "$pub/template.html") {
			$data = &read_file_contents_as_domain_user(
				$d, "$pub/template.html");
			}
		}

	# Show form for editing
	print &ui_hr();
	print "<b>";
	if ($editing == 1) {
		print &text('html_editing', "<a href='$url/$in{'edit'}' target=_blank><tt>$in{'edit'}</tt></a>");
		}
	else {
		print &text('html_creating', "<tt>$in{'create'}</tt>");
		}
	print "</b><br>\n";
	print &ui_form_start("save_html.cgi", "form-data");
	print &ui_hidden("dom", $in{'dom'}),"\n";
	print &ui_hidden("file", $editing == 1 ? $in{'edit'} : $in{'create'});

	# Show editor, which may be text only
	if ($in{'textok'}) {
		print &ui_hidden("text", 1);
		print &ui_textarea("body", $data, 20, 80, undef, 0,
				   "style='width:100%;height:70%'");
		}
	else {
		print &virtualmin_ui_show_html_editor("body", $data,
						      $url."/");
		}

	if ($in{'editok'} || $in{'textok'}) {
		print &ui_form_end([ [ "save", $text{'save'} ],
				     [ "cancel", $text{'html_cancel'} ],
				     undef,
				     [ "delete", $text{'html_delete'} ],
				   ]);
		}
	else {
		print &ui_form_end([ [ "create", $text{'create'} ],
				     [ "cancel", $text{'html_cancel'} ] ]);
		}
	}

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});
