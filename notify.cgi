#!/usr/local/bin/perl
# Actually email server owners

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newnotify_ecannot'});
&foreign_require("mailboxes", "mailboxes-lib.pl");
&ReadParseMime();

# Validate inputs
&error_setup($text{'notify_err'});
if ($in{'servers_def'}) {
	@doms = grep { $_->{'emailto'} } &list_domains();
	}
else {
	@doms = map { &get_domain($_) } split(/\0/, $in{'servers'});
	}
@doms || &error($text{'newnotify_edoms'});
$in{'subject'} =~ /\S/ || &error($text{'newnotify_esubject'});
$in{'from'} =~ /^\S+\@\S+$/ || &error($text{'newnotify_efrom'});
$in{'body'} =~ s/\r//g;
$in{'body'} =~ /\S/ || &error($text{'newnotify_ebody'});

# Construct and send the email
@to = map { $_->{'emailto'} } @doms;
&send_notify_email($in{'from'}, \@to, $in{'subject'}, $in{'body'},
		   $in{'attach'}, $in{"attach_filename"},
		   $in{"attach_content_type"});

# Tell the user
&ui_print_header(undef, $text{'newnotify_title'}, "");

print $text{'newnotify_done'},"<br>\n";
foreach $t (@to) {
	print "<tt>$t</tt><br>\n";
	}
&webmin_log("notify", undef, undef, { 'to' => join("\0", @to) });

&ui_print_footer("", $text{'index_return'});

