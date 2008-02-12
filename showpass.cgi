#!/usr/local/bin/perl
# Show a domain's password

$trust_unknown_referers = 1;
require './virtual-server-lib.pl';
use POSIX;
&ReadParse();
$d = &get_domain($in{'dom'});
$d || &error($text{'edit_egone'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_show_pass() || &error($text{'showpass_ecannot'});

&popup_header($text{'showpass_title'});

print "<center><table>\n";
print "<tr> <td><b>$text{'showpass_user'}</b></td> ",
      "<td><tt>$d->{'user'}</tt></td> </tr>\n";
print "<tr> <td><b>$text{'showpass_pass'}</b></td> ",
      "<td><tt>$d->{'pass'}</tt></td> </tr>\n";
print "</table></center>\n";

&popup_footer();
