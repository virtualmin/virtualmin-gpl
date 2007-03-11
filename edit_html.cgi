#!/usr/local/bin/perl
# Show a form for editing or creating an HTML page in a virtual server

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});

$editing = $in{'editok'} ? 1 :
	   $in{'createok'} || $in{'create'} ? 2 : 0;
&ui_print_header(&domain_in($d), $text{'html_title'}, "", undef, 0, 0, 0,
		 undef, undef, $editing ? "onload='initEditor()'" : undef);

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
	print "<td>",&ui_submit($text{'html_editok'}, 'editok'),"</td>\n";
	print "</tr>\n";
	}

print &ui_form_end();

# Show file upload form
print &ui_form_start("upload_html.cgi", "form-data");
print &ui_hidden("dom", $in{'dom'}),"\n";
print "<tr>\n";
print "<td><b>$text{'html_upload'}</b></td>\n";
print "<td>",&ui_upload("upload", 30),"</td>\n";
print "<td>",&ui_submit($text{'html_uploadok'}, 'uploadok'),"</td>\n";
print "</tr>\n";
print &ui_form_end();

print "</table>\n";

# Output HTMLarea init code
$mbroot = &module_root_directory("mailboxes");
$prog = -d "$mbroot/xinha" ? "xinha" : "htmlarea";
print <<EOF;
<script type="text/javascript">
  _editor_url = "$gconfig{'webprefix'}/mailboxes/$prog/";
  _editor_lang = "en";
</script>
<script type="text/javascript" src="../mailboxes/$prog/htmlarea.js"></script>

<script type="text/javascript">
var editor = null;
function initEditor() {
  editor = new HTMLArea("body");
  editor.config.baseHref = "http://www.$d->{'dom'}/";
  editor.config.baseURL = "http://www.$d->{'dom'}/";
  editor.config.getHtmlMethod = "TransformInnerHTML";
  editor.generate();
  return false;
}
</script>
EOF

if ($editing) {
	&switch_to_domain_user($d);
	if ($editing == 1) {
		# Read the selected HTML file
		$in{'edit'} !~ /\.\./ && $in{'edit'} !~ /\0/ ||
			&error($text{'html_efile'});
		$data = &read_file_contents("$pub/$in{'edit'}");
		}
	else {
		# Read a template file if one exists
		if (-r "$pub/template.html") {
			$data = &read_file_contents("$pub/template.html");
			}
		}

	# Show form for editing
	print "<hr>\n";
	print "<b>";
	if ($editing == 1) {
		$port = $d->{'web_port'} == 80 ? "" : ":".$d->{'web_port'};
		print &text('html_editing', "<a href='http://www.$d->{'dom'}$port/$in{'edit'}' target=_new><tt>$in{'edit'}</tt></a>");
		}
	else {
		print &text('html_creating', "<tt>$in{'create'}</tt>");
		}
	print "</b><br>\n";
	print &ui_form_start("save_html.cgi", "form-data");
	print &ui_hidden("dom", $in{'dom'}),"\n";
	print &ui_hidden("file", $editing == 1 ? $in{'edit'} : $in{'create'});
	print "<textarea rows=20 cols=80 style='width:100%;height:70%' name=body id=body>";
	print &html_escape($data);
	print "</textarea>\n";

	if ($in{'editok'}) {
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
