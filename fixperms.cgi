#!/usr/local/bin/perl
# Fix permissions on selected domains

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'fixperms_err'});
&can_edit_templates() || &error($text{'fixperms_ecannot'});

# Check and parse inputs
if ($in{'servers_def'}) {
	@doms = grep { $_->{'dir'} } &list_domains();
	}
else {
	foreach $id (split(/\0/, $in{'servers'})) {
		$d = &get_domain($id);
		if ($d) {
			push(@doms, $d);
			if ($in{'subservers'}) {
				push(@doms,
				     &get_domain_by("parent", $d->{'id'}));
				}
			}
		}
	}
@doms = grep { !$_->{'parent'} } @doms;
@doms || &error($text{'fixperms_edoms'});

&ui_print_header(undef, $text{'fixperms_title'}, "");

foreach $d (@doms) {
	&$first_print(&text('fixperms_dom', &show_domain_name($d)));
	if (!$d->{'dir'}) {
		&$second_print($text{'fixperms_edir'});
		}
	else {
		$err = &set_home_ownership($d);
		if ($err) {
			&$second_print(&text('fixperms_failed', $err));
			}
		else {
			&$second_print($text{'setup_done'});
			}
		}
	}

&ui_print_footer("", $text{'index_return'},
		 "edit_newvalidate.cgi?mode=fix", $text{'newvalidate_return'});
