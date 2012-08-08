#!/usr/local/bin/perl
# Show email-related settings for this virtual server

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_mail() || &error($text{'edit_ecannot'});
&require_mail();

&ui_print_header(&domain_in($d), $text{'mail_title'}, "", "mailopts");

print &ui_form_start("save_mail.cgi");
print &ui_hidden("dom", $d->{'id'}),"\n";
print &ui_table_start($text{'mail_header'}, undef, 2);

# BCC mode
if ($supports_bcc) {
	$bcc = &get_domain_sender_bcc($d);
	print &ui_table_row($text{'mail_bcc'},
		&ui_radio("bcc_def", $bcc ? 0 : 1,
		  [ [ 1, $text{'mail_bcc1'}."<br>" ],
		    [ 0, &text('mail_bcc0', &ui_textbox("bcc", $bcc, 50)) ] ]));
	}

# Alias copy mode
if ($d->{'alias'} && $supports_aliascopy) {
	print &ui_table_row($text{'edit_aliascopy'},
		    &ui_radio("aliascopy", int($d->{'aliascopy'}),
			      [ [ 1, $text{'tmpl_aliascopy1'} ],
				[ 0, $text{'tmpl_aliascopy0'} ] ]));
	}

# Outgoing IP binding
if ($supports_dependent) {
	$dependent = &get_domain_dependent($d);
	print &ui_table_row($text{'mail_dependent'},
                    &ui_radio("dependent", $dependent ? 1 : 0,
                              [ [ 0, $text{'mail_dependent0'} ],
				[ 1, &text('mail_dependent1', $d->{'ip'}) ],
			      ]));
	}

print &ui_table_end();
print &ui_form_end([ [ "save", $text{'save'} ] ]);

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});


