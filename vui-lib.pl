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
		   &ui_textbox($name."_complex", $complex, 40, 0, undef,
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
  _editor_url = "$gconfig{'webprefix'}/mailboxes/xinha/";
  _editor_lang = "en";
</script>
EOF

# Javascript for making the Xinha editor, depending on version
$rv .= <<EOF;
<script type="text/javascript" src="$gconfig{'webprefix'}/mailboxes/xinha/XinhaCore.js"></script>
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

1;
