#!/usr/local/bin/perl
# Show a page for entering possible shared IP addresses

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'sharedips_ecannot'});
&ui_print_header(undef, $text{'sharedips_title'}, "", "sharedips");

print "$text{'sharedips_desc'}<p>\n";
print &ui_form_start("save_newsharedips.cgi", "post");
print &ui_table_start($text{'sharedips_header'}, undef, 2);

# Current default IP
print &ui_table_row($text{'sharedips_def'},
		    &get_default_ip());

if (defined(&list_resellers)) {
	# Shared IPs owned by resellers
	foreach $r (&list_resellers()) {
		if ($r->{'acl'}->{'defip'}) {
			push(@rips, "<tt>$r->{'acl'}->{'defip'}</tt> ".
				    "($r->{'name'})");
			}
		}
	if (@rips) {
		print &ui_table_row($text{'sharedips_rips'},
				    join("<br>\n", @rips));
		}
	}

# Other possible shared IPs for regular servers
print &ui_table_row($text{'sharedips_ips'},
		    &ui_textarea("ips", join("\n", &list_shared_ips()),
				 5, 20));

# Allocate a new one from the default template
$tmpl = &get_template(&get_init_template(0));
if ($tmpl->{'ranges'}) {
	print &ui_table_row(" ",
		&ui_checkbox("alloc", 1, $text{'sharedips_alloc'}, 0));
	}

if (&supports_ip6()) {
	# Default IPv6 address
	print &ui_table_row($text{'sharedips_def6'},
		    &get_default_ip6() || "<i>$text{'sharedips_def6none'}</i>");

	# Other possible shared IPv6 addressses for regular servers
	print &ui_table_row($text{'sharedips_ip6s'},
		    &ui_textarea("ip6s", join("\n", &list_shared_ip6s()),
				 5, 40));
	}

print &ui_table_end();
print &ui_form_end([ [ "ok", $text{'sharedips_ok'} ] ]);

&ui_print_footer("", $text{'index_return'});
