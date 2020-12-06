#!/usr/local/bin/perl
# Update per-directory PHP versions

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_edit_phpver($d) || &error($text{'phpver_ecannot'});
&obtain_lock_web($d);

my $updated = 0;
&set_all_null_print();
if ($in{'delete'}) {
	# Remove selected
	&error_setup($text{'phpver_derr'});
	@d = split(/\0/, $in{'d'});
	@d || &error($text{'phpver_enone'});
	foreach $dir (@d) {
		&delete_domain_php_directory($d, $dir);
		}
	}
else {
	# Update versions
	&error_setup($text{'phpver_err'});
	%curr = map { $_->{'dir'}, $_->{'version'} }
		    &list_domain_php_directories($d);
	for($i=0; defined($in{"dir_$i"}); $i++) {
		if ($in{"ver_$i"} ne $curr{$in{"dir_$i"}}) {
			$updated = 1;
			$err = &save_domain_php_directory($d, $in{"dir_$i"},
						       $in{"ver_$i"});
			&error($err) if ($err);
			}
		}

	# Add new directory
	if ($in{'newdir'}) {
		$in{'newdir'} =~ /^[^\/]\S+$/ ||
			&error($text{'phpver_enewdir'});
		$in{'newdir'} =~ /^(http|https|ftp):/ &&
			&error($text{'phpver_enewdir'});
		$updated = 1;
		$err = &save_domain_php_directory($d, &public_html_dir($d)."/".
					       $in{'newdir'}, $in{'newver'});
		&error($err) if ($err);
		}
	}
&release_lock_web($d);
$mode = &get_domain_php_mode($d);
if ($mode ne "mod_php" && $mode ne "fpm") {
	my $err = &save_domain_php_mode($d, $mode);
	&error($err) if ($err);
	}
&clear_links_cache($d);
&run_post_actions();
&webmin_log("phpver", "domain", $d->{'dom'});
&domain_redirect($d, $updated);
