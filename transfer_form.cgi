#!/usr/local/bin/perl
# Display server transfer form

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_transfer_domain($d) || &error($text{'transfer_ecannot'});
&ui_print_header(&domain_in($d), $text{'transfer_title'}, "", "transfer");

if (!$d->{'parent'}) {
	print "$text{'transfer_desc'}<p>\n";
	}
else {
	print "$text{'transfer_desc2'}<p>\n";
	}
print &ui_form_start("transfer.cgi");
print &ui_hidden("dom", $d->{'id'}),"\n";
print &ui_table_start($text{'transfer_header'}, undef, 2);

# Domain being transferred
print &ui_table_row($text{'transfer_dom'},
	"<tt>".&show_domain_name($d)."</tt>");

# Destination system
print &ui_table_row($text{'transfer_host'},
	&ui_textbox("desthost", undef, 40));

# Root password
print &ui_table_row($text{'transfer_pass'},
	&ui_password("destpass", undef, 40)." ".
	$text{'transfer_passdef'});

# Delete from source
print &ui_table_row($text{'transfer_delete'},
	&ui_radio("delete", 0, [ [ 2, $text{'transfer_delete2'} ],
				 [ 1, $text{'transfer_delete1'} ],
				 [ 0, $text{'transfer_delete0'} ] ]));

# Over-write when restoring?
print &ui_table_row($text{'transfer_overwrite'},
	&ui_yesno_radio("overwrite", 0));

print &ui_table_end();
print &ui_form_end([ [ undef, $text{'transfer_ok'} ] ]);

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});
