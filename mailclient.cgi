#!/usr/local/bin/perl
# Show helpful mail client settings

$trust_unknown_referers = 1;
require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
$d || &error($text{'edit_egone'});
&can_edit_domain($d) && &can_edit_users() || &error($text{'users_ecannot'});

# Work out mail server ports and modes
($imap_host, $imap_port, $imap_type, $imap_ssl, $imap_enc,
 $pop3_port, $pop3_enc, $pop3_ssl) = &get_email_autoconfig_imap($d);
($smtp_host, $smtp_port, $smtp_type, $smtp_ssl, $smtp_enc) =
      &get_email_autoconfig_smtp($d);

&ui_print_header(&domain_in($d), $text{'mailclient_title'}, "");

print &ui_table_start($text{'mailclient_header'}, undef, 2);

@users = grep { $_->{'email'} } &list_domain_users($d, 1, 0, 1, 1);
if (!@users) {
	@users = grep { $_->{'email'} } &list_domain_users($d, 0, 0, 1, 1);
	}
if (@users) {
	print &ui_table_row($text{'mailclient_exemail'},
		"<tt>".$users[0]->{'email'}."</tt>");

	print &ui_table_row($text{'mailclient_exshort'},
		"<tt>".&remove_userdom($users[0]->{'user'}, $d)."</tt>");

	print &ui_table_row($text{'mailclient_exuser'},
		"<tt>".$users[0]->{'user'}."</tt>");

	print &ui_table_hr();
	}

print &ui_table_row($text{'mailclient_imap_host'},
	"<tt>".$imap_host."</tt>");

print &ui_table_row($text{'mailclient_imap_port'},
	"<tt>".$imap_port."</tt>");

print &ui_table_row($text{'mailclient_imap_ssl'},
	$imap_ssl eq 'yes'? $text{'yes'} : $text{'no'});

print &ui_table_row($text{'mailclient_imap_pass'},
	$imap_enc eq 'password-encrypted' ? $text{'mailclient_imap_enc'}
					  : $text{'mailclient_imap_plain'});

if ($pop3_port) {
	print &ui_table_hr();

	print &ui_table_row($text{'mailclient_pop3_host'},
		"<tt>".$imap_host."</tt>");

	print &ui_table_row($text{'mailclient_pop3_port'},
		"<tt>".$pop3_port."</tt>");

	print &ui_table_row($text{'mailclient_pop3_ssl'},
		$pop3_ssl eq 'yes'? $text{'yes'} : $text{'no'});
	}

print &ui_table_hr();

print &ui_table_row($text{'mailclient_smtp_host'},
	"<tt>".$smtp_host."</tt>");

print &ui_table_row($text{'mailclient_smtp_port'},
	"<tt>".$smtp_port."</tt>");

print &ui_table_row($text{'mailclient_smtp_ssl'},
	$smtp_ssl eq 'yes'? $text{'yes'} : $text{'no'});

print &ui_table_row($text{'mailclient_smtp_pass'},
	$smtp_enc eq 'password-encrypted' ? $text{'mailclient_imap_enc'}
					  : $text{'mailclient_imap_plain'});

print &ui_table_row($text{'mailclient_smtp_type'}, "<tt>".
	($smtp_type eq "STARTTLS" ? $text{'mailclient_smtp_starttls'} :
	$smtp_type eq "SSL" ? $text{'mailclient_smtp_ssltls'} :
			      $text{'mailclient_smtp_plain'}) . "</tt>");

print &ui_table_end();

&ui_print_footer("list_users.cgi?dom=$in{'dom'}", $text{'users_return'},
		 "", $text{'index_return2'});
