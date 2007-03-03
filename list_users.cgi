#!/usr/local/bin/perl
# list_users.cgi
# List mailbox users in some domain

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_users() || &error($text{'users_ecannot'});
@users = &list_domain_users($d, 0, 0, 0, 0);
&ui_print_header(&domain_in($d), $text{'users_title'}, "");
$webinit = &create_initial_user($d, undef, 1);

# Create select / add links
($mleft, $mreason, $mmax) = &count_feature("mailboxes");
@links = ( &select_all_link("d"),
	   &select_invert_link("d") );
if ($mleft != 0) {
	push(@links, "<a href='edit_user.cgi?new=1&dom=$in{'dom'}'>".
		     "$text{'users_add'}</a>");
	}
@rlinks = ( );
if ($virtualmin_pro) {
	push(@rlinks, "<a href='mass_ucreate_form.cgi?dom=$in{'dom'}'>".
		      "$text{'users_batch2'}</a>");
	}
if ($mleft != 0 && $webinit->{'webowner'} && $virtualmin_pro) {
	push(@rlinks, "<a href='edit_user.cgi?new=1&web=1&",
		      "dom=$in{'dom'}'>$text{'users_addweb'}</a>");
	}

if (@users) {
	print &ui_form_start("change_users.cgi");
	print &ui_hidden("dom", $in{'dom'}),"\n";
	print "<table cellpadding=0 cellspacing=0 width=100%><tr><td>\n";
	if ($mleft != 0 && $mleft != -1) {
		print "<b>",&text('users_canadd'.$mreason, $mleft),"</b><p>\n";
		}
	elsif ($mleft == 0) {
		print "<b>",&text('users_noadd'.$mreason, $mmax),"</b><p>\n";
		}
	print &ui_links_row(\@links);
	print "</td> <td align=right>\n";
	print &ui_links_row(\@rlinks);
	print "</td> </tr></table>\n";
	&users_table(\@users, $d, 1);
	}
else {
	print "<b>$text{'users_none'}</b><p>\n";
	shift(@links); shift(@links);
	}

# Show below-table links
print "<table cellpadding=0 cellspacing=0 width=100%><tr><td>\n";
print &ui_links_row(\@links);
print "</td> <td align=right>\n";
print &ui_links_row(\@rlinks);
print "</td> </tr></table>\n";
if (@users) {
	print &ui_form_end([ [ "delete", $text{'users_delete'} ],
	     $virtualmin_pro ? ( [ "mass", $text{'users_mass'} ] ) : ( ) ]);
	}

if ($virtualmin_pro) {
	print "<hr>\n";
	print &ui_buttons_start();

	if ($d->{'mail'}) {
		# Button to email all users
		print &ui_buttons_row("edit_mailusers.cgi",
		      $text{'users_mail'}, $text{'users_maildesc'},
		      &ui_hidden("dom", $in{'dom'}));
		}

	# Button to set user defaults
	print &ui_buttons_row("edit_defaults.cgi",
	      $text{'users_defaults'}, $text{'users_defaultsdesc'},
	      &ui_hidden("dom", $in{'dom'}));

	print &ui_buttons_end();
	}

if ($single_domain_mode) {
	&ui_print_footer(&domain_footer_link($d),
			 "", $text{'index_return2'});
	}
else {
	&ui_print_footer(&domain_footer_link($d),
		"", $text{'index_return'});
	}

