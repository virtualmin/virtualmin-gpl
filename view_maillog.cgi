#!/usr/local/bin/perl
# Show details of a single logged email

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'viewmaillog_err'});

# Get the message
($l) = &parse_procmail_log(undef, undef, undef, undef, $in{'cid'});
$l || &error($text{'viewmaillog_egone'});

# Validate destination domain
if ($l->{'to'} =~ /^(\S+)\@(\S+)$/) {
	$dname = $2;
	$d = &get_domain_by("dom", $dname);
	}
&can_view_maillog($d) || &error($text{'maillog_ecannot2'});

&ui_print_header($d ? &domain_in($d) : undef,
		 $text{'viewmaillog_title'}, "");

# Show email details
print &ui_table_start($text{'viewmaillog_header'}, "width=100%", 4);

print &ui_table_row($text{'viewmaillog_id'},
		    $l->{'id'} || $text{'viewmaillog_unknown'});

print &ui_table_row($text{'viewmaillog_time'},
		    &make_date($l->{'time'}));

print &ui_table_row($text{'viewmaillog_from'},
		    "<tt>$l->{'from'}</tt>");

print &ui_table_row($text{'viewmaillog_to'},
		    "<tt>$l->{'to'}</tt>");

print &ui_table_row($text{'viewmaillog_level'},
		    $l->{'level'} ? $text{'viewmaillog_level1'}
				  : $text{'viewmaillog_level0'});

print &ui_table_row($text{'viewmaillog_user'},
		    $l->{'user'} ? "<tt>$l->{'user'}</tt>"
				 : $text{'viewmaillog_none'});

print &ui_table_row($text{'viewmaillog_size'},
		    $l->{'size'} ? &nice_size($l->{'size'})
				 : $text{'viewmaillog_unknown'});

print &ui_table_row($text{'viewmaillog_dest'},
		    &maillog_destination($l));

if ($l->{'fullfile'}) {
	print &ui_table_row($text{'viewmaillog_file'},
			    "<tt>$l->{'fullfile'}</tt>", 3);
	}

if ($l->{'relay'}) {
	print &ui_table_row($text{'viewmaillog_relay'},
			    "<tt>$l->{'relay'}</tt>", 3);
	}

if ($l->{'status'}) {
	print &ui_table_row($text{'viewmaillog_status'},
			    "<tt>$l->{'status'}</tt>", 3);
	}

print &ui_table_end();
print "<p>\n";

&ui_print_footer($d ? ( &domain_footer_link($d) ) : ( ),
	 "maillog.cgi".($d ? "?dom=$d->{'id'}" : ""), $text{'maillog_return'},
	 "", $text{'index_return'});

