#!/usr/local/bin/perl
# Disable mod_php or stop asking

require './virtual-server-lib.pl';
&ReadParse();
&master_admin() || &error($text{'index_edisable_mod_php_cannot'});

if ($in{'cancel'}) {
	# Don't ask again
	&lock_file($module_config_file);
	$config{'mod_php_ok'} = 1;
	&save_module_config();
	&unlock_file($module_config_file);
	&redirect("");
	}
else {
	# Disable in Apache
	&ui_print_unbuffered_header(
		$text{'index_disable_mod_php_subtitle'}, $text{'index_disable_mod_php_title'}, "");
	&require_apache();
	my $changed = 0;

	if (&apache::can_configure_apache_modules()) {
		# System supports a2enmod or similar
		&$first_print($text{'index_disable_mod_php_enmod'});
		my @mods = &apache::list_configured_apache_modules();
		my @pmods = grep { $_->{'mod'} =~ /^(mod_)?php[0-9\.]*$/ }
				 @mods;
		@pmods || &error($text{'index_edisable_mod_php_mods'});
		foreach my $m (@pmods) {
			&apache::remove_configured_apache_module($m->{'mod'});
			$changed++;
			}
		}
	else {
		# Remove the LoadModule line
		&$first_print($text{'index_disable_mod_php_load'});
		my $conf = &apache::get_config();
		my @lm = &apache::find_directive_struct("LoadModule", $conf);
		my @remlm;
		foreach my $l (@lm) {
			if ($l->{'words'}->[0] =~ /^php[0-9\.]*_module/) {
				# Found one to remove
				push(@remlm, $l);
				}
			}
		@remlm || &error($text{'index_edisable_mod_php_mods'});
		foreach my $l (@remlm) {
			&lock_file($l->{'file'});
			&apache::save_directive_struct($l, undef, $conf, $conf);
			&flush_file_lines($l->{'file'});
			&unlock_file($l->{'file'});
			$changed++;
			}
		}
	undef(@apache::get_config_cache);
	undef($apache_mod_php_version_cache);
	delete($apache::httpd_modules{'mod_php5'});
	delete($apache::httpd_modules{'mod_php7'});
	&$second_print($text{'setup_done'});

	# Remove all php_value lines from domains
	my @dtargs = &list_mod_php_directives();
	&$first_print($text{'index_disable_mod_php_doms'});
	my $dcount = 0;
	foreach my $d (&list_domains()) {
		next if (!$d->{'web'});
		next if ($d->{'alias'});
		my @ports = ( $d->{'web_port'} );
		push(@ports, $d->{'web_sslport'}) if ($d->{'ssl'});
		my $c = 0;
		foreach my $p (@ports) {
			$c += &fix_mod_php_directives($d, $p, 1);
			}
		$dcount++ if ($c);
		}
	&$second_print(&text('index_disable_mod_php_ddone', $dcount));

	# And at the top level
	&$first_print($text{'index_disable_mod_php_global'});
	my $conf = &apache::get_config();
	foreach my $pval (@dtargs) {
		&apache::save_directive($pval, [ ], $conf, $conf);
		}
	&flush_file_lines();
	&register_post_action(\&restart_apache, 0);
	&$second_print($text{'setup_done'});

	if ($changed) {
		# Re-detect modules
		&unlink_file($apache::site_file);
		&register_post_action(\&restart_apache, 1);
		}
	&run_post_actions();
	&webmin_log("disable_mod_php");
	&ui_print_footer("", $text{'index_return'});
	}
