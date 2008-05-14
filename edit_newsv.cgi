#!/usr/local/bin/perl
# Show a form for changing global spam and virus scanning options

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'sv_ecannot'});
&ui_print_header(undef, $text{'sv_title'}, "", "sv");

print "$text{'sv_desc'}<p>\n";
print &ui_form_start("save_newsv.cgi", "post");
print &ui_table_start($text{'sv_header'}, "width=100%", 2, [ "width=30%" ]);
@doms = &list_domains();

if ($config{'spam'}) {
	# Spam scanning program
	($client, $host, $size) = &get_global_spam_client();
	print &ui_table_row(&hlink($text{'spam_client'}, 'spam_client'),
		    &ui_select("client", $client,
			       [ [ "spamassassin", $text{'tmpl_spamassassin'} ],
				 [ "spamc", $text{'tmpl_spamc'} ] ]));

	# Spamc host
	print &ui_table_row(
		&hlink($text{'tmpl_spam_host'}, 'template_spam_host'),
		&ui_opt_textbox("host", $host, 30, "<tt>localhost</tt>"));

	# Spamc max size
	print &ui_table_row(
		&hlink($text{'tmpl_spam_size'}, 'template_spam_size'),
		&ui_opt_textbox("size", $size, 8,
				$text{'template_spam_unlimited'}));

	# Allow user .procmailrc file?
	print &ui_table_row(
		&hlink($text{'spam_procmail'}, 'config_default_procmail'),
		&ui_radio("default_procmail", $config{'default_procmail'},
			  [ [ 0, $text{'yes'} ], [ 1, $text{'no'} ] ]));
	}

# Virus scanning program
if ($config{'virus'}) {
	# Virus scanner
	$scanner = &get_global_virus_scanner();
	$mode = $scanner eq 'clamscan' ? 0 :
	        $scanner eq 'clamdscan' ? 1 : 2;
	print &ui_table_row(&hlink($text{'spam_scanner'}, 'spam_scanner'),
		&ui_radio('scanner', $mode,
		  [ [ 0, $text{'spam_scanner0'}."<br>" ],
		    [ 1, $text{'spam_scanner1'}."<br>" ],
		    [ 2, &text('spam_scanner2',
		&ui_textbox("scanprog", $mode == 2 ? $scanner : "", 40)) ] ]));
	}

print &ui_table_end();
print &ui_form_end([ [ undef, $text{'save'} ] ]);

# Check if clamd is running, if not offer to set it up
if ($config{'virus'}) {
	$cs = &check_clamd_status();
	if ($cs != -1) {
		print &virtualmin_ui_hr();
		print &ui_buttons_start();
		if ($cs) {
			print &ui_buttons_row("disable_clamd.cgi",
				$text{'sv_disable'}, $text{'sv_disabledesc'});
			}
		else {
			print &ui_buttons_row("enable_clamd.cgi",
				$text{'sv_enable'}, $text{'sv_enabledesc'});
			}
		print &ui_buttons_end();
		}
	}

&ui_print_footer("", $text{'index_return'});

