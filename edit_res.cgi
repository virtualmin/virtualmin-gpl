#!/usr/local/bin/perl
# Display memory and process limits

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_res($d) || &error($text{'edit_ecannot'});

&ui_print_header(&domain_in($d), $text{'res_title'}, "", "res");
$rv = &get_domain_resource_limits($d);

print &ui_form_start("save_res.cgi");
print &ui_hidden("dom", $in{'dom'});
print &ui_table_start($text{'res_header'}, undef, 2);

# Maximum processes
print &ui_table_row($text{'res_procs'},
	&ui_opt_textbox("procs", $rv->{'procs'}, 5, $text{'res_procsdef'},
			$text{'res_procsset'}));

# Memory limit
print &ui_table_row($text{'res_mem'},
	&ui_radio("mem_def", $rv->{'mem'} ? 0 : 1,
		  [ [ 1, $text{'res_procsdef'} ],
		    [ 0, $text{'res_procsset'} ] ])." ".
	&ui_bytesbox("mem", $rv->{'mem'}, 8));

# Maximum CPU time
print &ui_table_row($text{'res_time'},
	&ui_opt_textbox("time", $rv->{'time'}, 5, $text{'res_procsdef'},
			$text{'res_procsset'})." ".$text{'res_mins'});

print &ui_table_end();
print &ui_form_end([ [ "save", $text{'save'} ] ]);

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});

