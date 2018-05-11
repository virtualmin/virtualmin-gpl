#!/usr/local/bin/perl
# Fix symbolic link permissions on all domains

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'fixsymlinks_ecannot'});
&ReadParse();

if ($in{'ignore'}) {
	# User chose not to fix
	&lock_file($module_config_file);
	$config{'allow_symlinks'} = 0;
	&save_module_config();
	&unlock_file($module_config_file);
	&webmin_log("nofixsymlinks");
	&redirect("");
	}
elsif ($in{'htaccess'}) {
	# Fix .htaccess files
	&ui_print_unbuffered_header(undef, $text{'fixsymlinks_title'}, "");

	&$first_print($text{'fixsymlinks_htdoing'});
	$fcount = 0;
	$dcount = 0;
	foreach $id (split(/\0/, $in{'d'})) {
		$d = &get_domain($id);
		next if (!$d);	# Huh?
		@dhtaccess = &fix_script_htaccess_files(
                                        $d, &public_html_dir($d));
		$fcount += @dhtaccess;
		$dcount++;
		}
	&$second_print(&text('fixsymlinks_htdone', $fcount, $dcount));

	&webmin_log("fixhtaccess");
	&ui_print_footer("", $text{'index_return'});
	}
else {
	# Fix symlinks, then search for htaccess files
	&ui_print_unbuffered_header(undef, $text{'fixsymlinks_title'}, "");

	# Fix symlinks
	&$first_print($text{'fixsymlinks_doing'});
	@fixdoms = &fix_symlink_security(undef, 0);
	&fix_symlink_templates();
	&$second_print(&text('fixsymlinks_done', scalar(@fixdoms)));
	&lock_file($module_config_file);
	$config{'allow_symlinks'} = 0;
	&save_module_config();
	&unlock_file($module_config_file);

	&run_post_actions();

	# Find .htaccess files that have Options set
	&$first_print($text{'fixsymlinks_finding'});
	@htaccess = ( );
	@dfound = ( );
	foreach my $d (&list_domains()) {
		next if ($d->{'alias'} || !$d->{'dir'});
		local @dhtaccess = &fix_script_htaccess_files(
                                        $d, &public_html_dir($d), 1);
		push(@htaccess, @dhtaccess);
		push(@dfound, [ $d, \@dhtaccess ]) if (@dhtaccess);
		}
	if (@htaccess) {
		&$second_print(&text('fixsymlinks_found', scalar(@htaccess),
				     scalar(@dfound)));
		}
	else {
		&$second_print($text{'fixsymlinks_none'});
		}

	# Offer to fix those too
	if (@htaccess) {
		print &ui_form_start("fix_symlinks.cgi");
		print "<b>$text{'fixsymlinks_rusure'}</b><p>\n";
		print "<b>$text{'fixsymlinks_doms'}</b> ",
		      join(" ", map { &show_domain_name($_->[0]) } @dfound),
		      "<p>\n";
		foreach $f (@dfound) {
			print &ui_hidden("d", $f->[0]->{'id'});
			}
		print &ui_submit($text{'fixsymlinks_ok'}, "htaccess");
		print &ui_form_end();
		}

	&webmin_log("fixsymlinks");
	&ui_print_footer("", $text{'index_return'});
	}
