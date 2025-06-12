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
	# Outgoing BCC
	$bcc = &get_domain_sender_bcc($d);
	print &ui_table_row($text{'mail_bcc'},
		&ui_radio("bcc_def", $bcc ? 0 : 1,
		  [ [ 1, $text{'mail_bcc1'}."<br>" ],
		    [ 0, &text('mail_bcc0', &ui_textbox("bcc", $bcc, 50)) ] ]));
	}
if ($supports_bcc == 2) {
	# Incoming BCC
	$rbcc = &get_domain_recipient_bcc($d);
	print &ui_table_row($text{'mail_rbcc'},
		&ui_radio("rbcc_def", $rbcc ? 0 : 1,
		  [ [ 1, $text{'mail_bcc1'}."<br>" ],
		    [ 0, &text('mail_bcc0',
			       &ui_textbox("rbcc", $rbcc, 50)) ] ]));
	}
elsif ($supports_bcc == 1 && &master_admin()) {
	# Show message about incoming BCC not being enabled
	print &ui_table_row($text{'mail_rbcc'},
		&text('mail_bccsupport', '../postfix/bcc.cgi'));
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

# Cloud mail filter
@provs = &list_cloud_mail_providers($d);
$prov = &get_domain_cloud_mail_provider($d);
print &ui_table_row($text{'mail_cloud'},
	&ui_select("cloud", $prov ? $prov->{'name'} : undef,
		   [ [ undef, "&lt;".$text{'mail_cloudnone'}."&gt;" ],
		     map { $_->{'name'} } @provs ]));

# Cloud mail filter ID
print &ui_table_row($text{'mail_cloudid'},
	&ui_textbox("cloudid", $d->{'cloud_mail_id'}, 20));

if ($prov) {
	# Show MX records and URL
	print &ui_table_row($text{'mail_url'},
		&ui_link($prov->{'url'}, $prov->{'url'}, undef,
			 'target=_blank'));

	print &ui_table_row($text{'mail_mx'},
		join("<br>\n", @{$prov->{'mx'}}));
	}

my @okclouds;
if (defined(&list_smtp_clouds)) {
	# Find usable cloud mail delivery providers
	my @clouds = &list_smtp_clouds();
	foreach my $c (@clouds) {
		$sfunc = "smtpcloud_".$c->{'name'}."_get_state";
		$s = &$sfunc();
		push(@okclouds, $c) if ($s->{'ok'} || &smtp_uses_cloud($d, $c));
		}
	}
if (@okclouds) {
	# Cloud mail delivery provider fields
	print &ui_table_row($text{'mail_smtp_cloud'},
		&ui_select("smtp_cloud", $d->{'smtp_cloud'},
			[ [ "", $text{'mail_smtp_local'} ],
			  map { [ $_->{'name'}, $_->{'desc'} ] } @okclouds ]));
	}

# MTA-STS option
if (&can_mta_sts($d)) {
	my $mtaerr = &get_mta_sts($d);
	my $msg = !$mtaerr && !&has_mta_sts_cert($d) ?
		$text{'mail_mta_sts_cert'} : $text{'yes'};
	print &ui_table_row(
		&hlink($text{'mail_mta_sts'}, 'mail_mta_sts'),
		&ui_radio("mta_sts", $mtaerr ? 0 : 1,
			  [ [ 1, $msg ], [ 0, $text{'no'} ] ]));
	}

print &ui_table_end();
print &ui_form_end([ [ "save", $text{'save'} ] ]);

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});


