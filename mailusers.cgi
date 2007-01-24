#!/usr/local/bin/perl
# Actually email server owners

require './virtual-server-lib.pl';
&ReadParseMime();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'users_ecannot'});
&can_edit_users() || &error($text{'users_ecannot'});
&foreign_require("mailboxes", "mailboxes-lib.pl");

# Validate inputs
&error_setup($text{'mailusers_err'});
if ($in{'to_def'}) {
	@to = map { $_->{'email'} || $_->{'user'} }
		  grep { $_->{'email'} || $_->{'user'} eq $d->{'user'} }
		       &list_domain_users($d, 0, 0, 1, 1);
	}
else {
	@to = split(/\0/, $in{'to'});
	}
@to || &error($text{'mailusers_eto'});
$in{'subject'} =~ /\S/ || &error($text{'newnotify_esubject'});
$in{'from'} =~ /^\S+\@\S+$/ || &error($text{'newnotify_efrom'});
$in{'body'} =~ s/\r//g;
$in{'body'} =~ /\S/ || &error($text{'newnotify_ebody'});

# Construct and send the email
&send_notify_email($in{'from'}, \@to, $in{'subject'}, $in{'body'},
		   $in{'attach'}, $in{"attach_filename"},
		   $in{"attach_content_type"});

# Tell the user
&ui_print_header(&domain_in($d), $text{'mailusers_title'}, "");

print $text{'newnotify_done'},"<br>\n";
foreach $t (@to) {
	print "<tt>$t</tt><br>\n";
	}
&webmin_log("mailusers", undef, undef, { 'to' => join("\0", @to) });

&ui_print_footer("list_users.cgi?dom=$in{'dom'}", $text{'users_return'},
		 "", $text{'index_return'});
