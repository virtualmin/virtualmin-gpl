#!/usr/local/bin/perl
# Show a form for setting up mail client auto-configuration

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'autoconfig_ecannot'});
&ui_print_header(undef, $text{'newautoconfig_title'}, "", "autoconfig");

# Link to an eligible domain with the email address required by the CGI
my ($d) = sort { $a->{'dom'} cmp $b->{'dom'} }
	grep { $_->{'mail'} && &domain_has_website($_) && !$_->{'alias'} }
		&list_visible_domains();
my $autoconfig = "<tt>/mail/config-v1.1.xml</tt>";
if ($config{'mail_autoconfig'} && $d) {
	my $url = &get_domain_url($d)."/mail/config-v1.1.xml";
	my $href = $url."?emailaddress=".
		&urlize($d->{'user'}."\@".$d->{'dom'});
	$autoconfig = "<tt>".&ui_link(&html_escape($href),
		'/mail/config-v1.1.xml', undef,
		'target=_blank rel=noopener')."</tt>";
	}
print &text('autoconfig_desc', $autoconfig),"<p>\n";
print &ui_form_start("save_newautoconfig.cgi", "post");
print &ui_table_start($text{'autoconfig_header'}, undef, 2);

print &ui_table_row($text{'autoconfig_enabled'},
	&ui_yesno_radio("autoconfig", $config{'mail_autoconfig'}));

print &ui_table_end();
print &ui_form_end([ [ undef, $text{'save'} ] ]);

&ui_print_footer("", $text{'index_return'});
