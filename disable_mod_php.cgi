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
		undef, $text{'index_disable_mod_php_title'}, "");
	&require_apache();
	my $changed = 0;
	if (&apache::can_configure_apache_modules()) {
		# System supports a2enmod or similar
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

	# Remove all php_value lines
	foreach my $d (&list_domains()) {
		next if (!$d->{'web'});
		next if ($d->{'alias'});
		my @ports = ( $d->{'web_port'} );
		push(@ports, $d->{'web_sslport'}) if ($d->{'ssl'});
		foreach my $p (@ports) {
			&fix_mod_php_directives($d, $port);
			}
		}

	if ($changed) {
		# Re-detect modules
		&unlink_file($apache::site_file);
		&register_post_action(\&restart_apache, 1);
		}
	&run_post_actions();
	&webmin_log("disable_mod_php");
	&ui_print_footer("", $text{'index_return'});
	}
