#!/usr/local/bin/perl
# Show the multi-step post-install wizard

require './virtual-server-lib.pl';
&ReadParse();

if ($in{'cancel'}) {
	# Give up on the whole wizard
	$config{'wizard_run'} = 1;
	&save_module_config();
	&redirect("");
	return;
	}

@wizard_steps = &get_wizard_steps();
$step = $wizard_steps[$in{'step'} || 0];

if ($in{'parse'}) {
	# Call the parse function for this step, which may return an error.
	# If so, re-display the page .. otherwise, re-direct
	$pfunc = "wizard_parse_".$step;
	if (defined(&$pfunc)) {
		$err = &$pfunc(\%in);
		}
	if (!$err) {
		# Worked, show next step
		&redirect("wizard.cgi?step=".($in{'step'}+1));
		}
	}

&ui_print_header($text{'wizard_title_'.$step}, $text{'wizard_title'}, "");

print &ui_form_start("wizard.cgi", "post");
print &ui_hidden("step", $in{'step'});
print &ui_hidden("parse", 1);
if ($err) {
	print "<b><font color=#ff0000>$err</font></b><p>\n";
	}
print &ui_table_start(undef, "width=100%", 2);

# Show step-specific inputs
$ffunc = "wizard_show_".$step;
&$ffunc();

print &ui_table_end();
print &ui_form_end([ [ undef, $text{'wizard_next'} ],
		     undef,
		     [ "cancel", $text{'wizard_cancel'} ] ]);

&ui_print_footer("", $text{'index_return'});


1;

