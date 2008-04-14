#!/usr/local/bin/perl
# Save the list of ProFTPd chroot directories

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'chroot_ecannot'});
&has_ftp_chroot() || &error($text{'chroot_esupport'});
&error_setup($text{'chroot_err'});
&ReadParse();

# Validate and store inputs
@chroots = ( );
for($i=0; defined($in{"all_$i"}); $i++) {
	next if (!$in{"enabled_$i"});
	$chroot = { };
	if (!$in{"all_$i"}) {
		$chroot->{'group'} = $in{"group_$i"};
		$chroot->{'neg'} = $in{"neg_$i"};
		}
	if ($in{"mode_$i"} == 2) {
		$chroot->{'dir'} = '/';
		}
	elsif ($in{"mode_$i"} == 1) {
		$chroot->{'dir'} = '~';
		}
	elsif ($in{"mode_$i"} == 3) {
		# A domain's home directory
		$chroot->{'group'} || &error(&text('chroot_egroup', $i+1));
		$chroot->{'neg'} && &error(&text('chroot_eneg', $i+1));
		$d = &get_domain_by("group", $chroot->{'group'}, "parent", "");
		$d || &error(&text('chroot_edom', $chroot->{'group'}));
		$chroot->{'dir'} = $d->{'home'};
		}
	elsif ($in{"mode_$i"} == 0) {
		-d $in{"dir_$i"} ||
			&error(&text('chroot_edir', $i+1));
		$chroot->{'dir'} =  $in{"dir_$i"};
		}
	push(@chroots, $chroot);
	}

# Really save, and tell the user what is being done
&ui_print_unbuffered_header(undef, $text{'newchroot_title'}, "");

&obtain_lock_ftp();
&$first_print($text{'chroot_saving'});
&save_ftp_chroots(\@chroots);
&$second_print($text{'setup_done'});
&release_lock_ftp();

&run_post_actions();
&webmin_log("chroot");

&ui_print_footer("", $text{'index_return'});
