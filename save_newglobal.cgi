#!/usr/local/bin/perl
# Update the list of global template variables

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'newglobal_err'});
&can_edit_templates() || &error($text{'newglobal_ecannot'});

# Parse inputs into a list
&lock_file($global_template_variables_file);
for(my $i=0; defined($in{"name_$i"}); $i++) {
	next if ($in{"name_$i"} !~ /\S/);
	$in{"name_$i"} =~ /^[a-z0-9\_]+$/i ||
		&error(&text('newglobal_ename', $i+1));
	push(@vars, { 'enabled' => $in{"enabled_$i"},
		      'name' => $in{"name_$i"},
		      'value' => $in{"value_$i"} });
	}
&save_global_template_variables(\@vars);
&unlock_file($global_template_variables_file);

&run_post_actions_silently();
&webmin_log("global");
&redirect("");

