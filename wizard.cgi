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

$step = $wizard_steps[$in{'step'} || 0];

if ($in{'parse'}) {
	# Call the parse function for this step, which may return an error.
	# If so, re-display the page .. otherwise, re-direct
	}

&ui_print_header($text{'wizard_'.$step}, $text{'wizard_title'}, "");

print &ui_form_start("wizard.cgi", "post");
print &ui_hidden("step", $in{'step'});

print &ui_form_end([ [ undef, $text{'wizard_next'} ],
		     undef,
		     [ "cancel", $text{'wizard_cancel'} ] ]);

&ui_print_footer("", $text{'index_return'});


1;

