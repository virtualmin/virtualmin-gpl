# UI functions specific to Virtualmin

# virtualmin_ui_apply_radios([tag])
# Returns Javascript to fake a click on all radio buttons on a form, to make
# them perform any onClick actions
sub virtualmin_ui_apply_radios
{
local ($tag) = @_;
local $rv = <<EOF;
for(i=0; i<document.forms.length; i++) {
  form = document.forms[i];
  for(j=0; j<form.elements.length; j++) {
    e = form.elements[j];
    if (e.type == "radio") {
      if (e.checked && !e.done_click) {
        e.done_click = 1;
        e.click();
        }
      }
    }
  }
EOF
$rv =~ s/\n/ /g;
return $tag ? "$tag='$rv'" : $rv;
}

# virtualmin_ui_show_cron_time(name, &job, off-text)
# Returns HTML for a field for entering a cron time, or selecting a disabled
# option. Uses a popup for the complex time
sub virtualmin_ui_show_cron_time
{
return &theme_virtualmin_ui_show_cron_time(@_)
	if (defined(&theme_virtualmin_ui_show_cron_time));
local ($name, $job, $offmsg) = @_;
&foreign_require("cron");
local $rv;
local $mode = !$job ? 0 : $job->{'special'} ? 1 : 2;
local $complex = $mode == 2 ? &cron::when_text($job, 1) : undef;
local $button = "<input type=button onClick='cfield = form.${name}_complex; hfield = form.${name}_hidden; chooser = window.open(\"cron_chooser.cgi?complex=\"+escape(hfield.value), \"cronchooser\", \"toolbar=no,menubar=no,scrollbars=no,resizable=yes,width=800,height=400\"); chooser.cfield = cfield; window.cfield = cfield; chooser.hfield = hfield; window.hfield = hfield;' value=\"...\">\n";
local $hidden = $mode == 2 ?
	join(" ", $job->{'mins'}, $job->{'hours'},
		  $job->{'days'}, $job->{'months'}, $job->{'weekdays'}) : "";
return &ui_radio_table($name, $mode,
	 [ $offmsg ? ( [ 0, $offmsg ] ) : ( ),
	   $cron::config{'vixie_cron'} ? (
	   [ 1, $text{'cron_special'},
		   &ui_select($name."_special", $job->{'special'},
		      [ map { [ $_, $cron::text{'edit_special_'.$_} ] }
			    ('hourly', 'daily', 'weekly', 'monthly', 'yearly')
		      ]) ] ) : ( ),
	   [ 2, $text{'cron_complex'},
		   &ui_textbox($name."_complex", $complex, 30, 0, undef,
				  "readonly=true")." ".$button ],
	 ]).&ui_hidden($name."_hidden", $hidden);
}

# virtualmin_ui_parse_cron_time(name, &job, &in)
# Updates the given job object with the selected schedule. Return 1 if a
# schedule was chosen, 0 if not.
sub virtualmin_ui_parse_cron_time
{
return &theme_virtualmin_ui_parse_cron_time(@_)
	if (defined(&theme_virtualmin_ui_parse_cron_time));
local ($name, $job, $in) = @_;
if ($in{$name} == 0) {
	# Disabled
	return 0;
	}
else {
	&copy_cron_sched_keys({ }, $job);
	if ($in{$name} == 1) {
		# Simple time
		$job->{'special'} = $in{$name."_special"};
		}
	else {
		# Complex time
		local @j = split(/\s+/, $in{$name."_hidden"});
		@j == 5 || &error($text{'cron_ehidden'});
		$job->{'mins'} = $j[0];
		$job->{'hours'} = $j[1];
		$job->{'days'} = $j[2];
		$job->{'months'} = $j[3];
		$job->{'weekdays'} = $j[4];
		}
	return 1;
	}
}

# virtualmin_ui_html_editor_bodytags(name)
# Returns any extra tags needed in the <body> section by the editor returned
# by the function below.
sub virtualmin_ui_html_editor_bodytags
{
return &theme_virtualmin_ui_html_editor_bodytags(@_)
	if (defined(&theme_virtualmin_ui_html_editor_bodytags));
return "onload='xinha_init()'";
}

# virtualmin_ui_show_html_editor(name, html, baseurl)
# Returns HTML for an HTML editor with the given name, and showing the
# given text initially.
sub virtualmin_ui_show_html_editor
{
return &theme_virtualmin_ui_show_html_editor(@_)
	if (defined(&theme_virtualmin_ui_show_html_editor));
local ($name, $html, $baseurl) = @_;
local $rv;

if ($current_theme !~ /authentic-theme/) {

# Xinha editor config
$rv .= <<EOF;
<script type="text/javascript">
  _editor_url = "@{[&get_webprefix_safe()]}/mailboxes/xinha/";
  _editor_lang = "en";
</script>
EOF

# Javascript for making the Xinha editor, depending on version
$rv .= <<EOF;
<script type="text/javascript" src="@{[&get_webprefix_safe()]}/mailboxes/xinha/XinhaCore.js"></script>
<script type="text/javascript">
xinha_init = function()
{
xinha_editors = [ "body" ];
xinha_plugins = [ ];
xinha_config = new Xinha.Config();
xinha_config.baseHref = "$baseurl";
xinha_editors = Xinha.makeEditors(xinha_editors, xinha_config, xinha_plugins);
Xinha.startEditors(xinha_editors);
}
</script>
EOF
  }
else {
		print '<script type="text/javascript">xinha_init = function(){}</script>';
}

# The actual textbox
$rv .= "<textarea rows=20 cols=80 style='width:100%;height:70%' name=$name id=$name>";
$rv .= &html_escape($html);
$rv .= "</textarea>\n";
return $rv;
}

# vui_opt_bytesbox(name, value, size, option1, [option2], [disabled?],
# 		   [&extra-fields], [max], [tags], [defaultunits])
# Returns HTML for a bytes field with a 'default' option
sub vui_opt_bytesbox
{
my ($name, $value, $size, $opt1, $opt2, $dis, $extra, $max, $tags,
    $defaultunits) = @_;
$defaultunits ||= 1024*1024*1024;
my $dis1 = &js_disable_inputs([ $name, $name."_units", @$extra ], [ ]);
my $dis2 = &js_disable_inputs([ ], [ $name, $name."_units", @$extra ]);
my $rv;
$size = &ui_max_text_width($size);
$rv .= &ui_radio($name."_def", $value eq '' ? 1 : 0,
		 [ [ 1, $opt1, "onClick='$dis1'" ],
		   [ 0, $opt2 || " ", "onClick='$dis2'" ] ], $dis)."\n";
$rv .= &ui_bytesbox($name, $value, $size, $value eq "" || $dis, $tags,
		    $defaultunits);
return $rv;

}

# vui_features_sorted_grid(\@grid)
# Returns HTML for grid, formatted
# the way that it preserves the order   
sub vui_features_sorted_grid
{
my ($grid) = @_;
my @grid = @{$grid};
my @grid_left = @grid;
my $grid_tnum = scalar(@grid);
my @grid_right = splice(@grid_left, ($grid_tnum / 2) + ($grid_tnum % 2 ? 1 : 0));
my $style_force_no_border = 'style="border:0 !important; width: 50%;"';
my $style_flex_cnt = 'style="display: flex; align-items: flex-start; justify-content: center;"';
my $lgftable = &ui_grid_table(\@grid_left, 1, undef, undef, $style_force_no_border);
my $rgftable = &ui_grid_table(\@grid_right, 1, undef, undef, $style_force_no_border);
return "<div class=\"vui_features_sorted_grid\" $style_flex_cnt>" . ($lgftable . $rgftable) . "</div>";
}

=head2 vui_install_mod_perl_link(mods, return_page, return_desc, [no_dot])

# Return a UI link for installing missing Perl module

=item mods - Space separated list of modules, e.g.: XML::Simple Net::SSLeay

=item return_page - Link to the page to return after installation

=item return_desc - Text for return link 

=cut
sub vui_install_mod_perl_link
{
my ($mods, $return_page, $return_desc, $no_dot) = @_;
my $rv;
if (&foreign_available('cpan')) {
	$rv .= &text('install_mod_perl_link', "../cpan/download.cgi?source=3&cpan=$mods&mode=2&".
			"return=../virtual-server/$return_page&returndesc=".&urlize($return_desc));
		}
return $rv;
}

=head2 vui_make_and

Joins multiple words with command and 'and' where needed

=cut
sub vui_make_and
{
my @w = @_;
if (@w == 0) {
	return "";
	}
elsif (@w == 1) {
	return $w[0];
	}
elsif (@w == 2) {
	return &text('nf_and', $w[0], $w[1]);
	}
else {
	my $f = pop(@w);
	return &text('nf_and', join(", ", @w), $f);
	}
}

=head2 vui_footer_history_back

Returns a link and text for `ui_print_footer` on error to go back

=cut
sub vui_footer_history_back
{
	return ("javascript:history.back()", $text{'error_previous'});
}

=head2 vui_ui_block_no_wrap(html, [add-white-space-around])

Returns passed HTML as block element with no wrap

=cut
sub vui_ui_block_no_wrap
{
my ($html, $nbsps) = @_;
$nbsps = "&nbsp;&nbsp;" if ($nbsps);
	return "<div style='white-space: nowrap;'>$nbsps$html$nbsps</div>";
}

=head2 vui_ui_block(html)

Returns passed HTML as block element

=cut
sub vui_ui_block
{
my ($html) = @_;
return "<div class='vui_ui_block'>$html</div>";
}

=head2 vui_ui_input_noauto_attrs()

Returns attributes preventing browser to autofill input fields

=cut
sub vui_ui_input_noauto_attrs
{
return "autocomplete='new-password' autocorrect='off' spellcheck='false'";
}

=head2 vui_noauto_textbox(name, value, size, [disabled?], [maxlength], [tags])

Like ui_textbox, but with autocompletion disabled

=cut
sub vui_noauto_textbox
{
my ($name, $value, $size, $dis, $max, $tags) = @_;
$tags ||= "";
$tags .= " ".&vui_ui_input_noauto_attrs();
return &ui_textbox($name, $value, $size, $dis, $max, $tags);
}

=head2 vui_noauto_password(name, value, size, [disabled?], [maxlength], [tags])

Like ui_password, but with autocompletion disabled

=cut
sub vui_noauto_password
{
my ($name, $value, $size, $dis, $max, $tags) = @_;
$tags ||= "";
$tags .= " ".&vui_ui_input_noauto_attrs();
return &ui_password($name, $value, $size, $dis, $max, $tags);
}

=head2 vui_edit_link_icon()

Returns a link as a unicode symbol (icon)

=cut
sub vui_edit_link_icon
{
my ($link, $unisymb) = @_;
my $styles = "font-size: 140%;";
   $styles .= "position: absolute;";
   $styles .= "margin: -4px 0 0 4px;";
$unisymb ||= '&#9881;'; # default is cog
my $unisymb_class = $unisymb;
$unisymb_class =~ tr/[0-9]//cd;
return &ui_link($link,
  "<span style='$styles'>$unisymb</span>",
  "vui_edit_link_icon i$unisymb_class");
}

=head2 vui_inline_label()

Returns a text label as a inline element

=cut
sub vui_inline_label
{
my ($textid, $upper, $class) = @_;
my $styles = "font-size: 10px;";
   $styles .= "font-weight: bold;";
   $styles .= "background-color: #bdbdbd;";
   $styles .= "border-radius: 50px;";
   $styles .= "color: #fff;";
   $styles .= "line-height: inherit;";
   $styles .= "margin: 0 5px 0 10px;";
   $styles .= "padding: 1px 5px;";
   $styles .= "vertical-align: inherit;";
my $styles_cnt .= "display:contents;";
my $text = $text{$textid};
$text = uc($text) if ($upper);
$class = " $class" if ($class);
return "<span class='vui_inline_label$class' style='$styles_cnt'>".
       "<span data-$textid style='$styles'>$text</span></span>";
}

=head2 vui_hidden()

Given content returns it as a hidden container

=cut
sub vui_hidden
{
my ($content) = @_;
return "<div class='vui_hidden' style='display: none'>$content</div>";
}

=head2 vui_note(text)

Returns a note as a small font size text

=cut
sub vui_note
{
my ($text) = @_;
return "<font style='font-size:92%;opacity:0.66'>&nbsp;&nbsp;ⓘ&nbsp;&nbsp;".
	"$text</font>";
}

1;
