#!/usr/local/bin/perl
# Show a domain's or user's password

$trust_unknown_referers = 1;
require './virtual-server-lib.pl';
use POSIX;
&ReadParse();
$d = &get_domain($in{'dom'});
$d || &error($text{'edit_egone'});
&can_show_pass() || &error($text{'showpass_ecannot'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
if ($in{'user'}) {
	# Showing for mailbox user
	&can_edit_users() || &error($text{'users_ecannot'});
	@users = &list_domain_users($d, 0, 1, 1, 1);
	($user) = grep { $_->{'user'} eq $in{'user'} } @users;
	$user || &error($text{'showpass_egone'});
	$username = $user->{'user'};
	$pass = $user->{'plainpass'};
	$msg1 = $text{'showpass_useru'};
	$msg2 = $text{'showpass_passu'};
	}
else {
	# For a domain
	$username = $d->{'user'};
	$pass = $d->{'pass'};
	$msg1 = $text{'showpass_user'};
	$msg2 = $text{'showpass_pass'};
	}

&popup_header($text{'showpass_title'});

print "<center><table>\n";
print "<tr> <td><b>$msg1</b></td> ",
      "<td><tt>",&html_escape($username),"</tt></td> </tr>\n";
print "<tr> <td><b>$msg2</b></td> ",
      "<td><tt>",&html_escape($pass),"</tt></td> </tr>\n";
print "</table></center>\n";

&popup_footer();
