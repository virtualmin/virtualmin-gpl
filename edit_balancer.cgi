#!/usr/local/bin/perl
# Show a form for editing or adding a proxy balancer

$0 =~ /^(.*)\/pro\// && chdir($1);
require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_forward() ||
	&error($text{'balancers_ecannot'});
$has = &has_proxy_balancer($d);
$has || &error($text{'balancers_esupport'});
if (!$in{'new'}) {
	($b) = grep { $_->{'path'} eq $in{'path'} } &list_proxy_balancers($d);
	$b || &error($text{'balancer_egone'});
	}

&ui_print_header(&domain_in($d), $in{'new'} ? $text{'balancer_create'}
					    : $text{'balancer_edit'}, "");

print &ui_form_start("save_balancer.cgi", "post");
print &ui_hidden("new", $in{'new'});
print &ui_hidden("dom", $in{'dom'});
print &ui_hidden("old", $in{'path'});
print &ui_table_start($text{'balancer_header'}, undef, 2);

if ($in{'new'} && $has == 2 || !$in{'new'} && $b->{'balancer'}) {
	# Balancer name (non-editable for existing)
	print &ui_table_row($text{'balancer_name'},
		$in{'new'} ? &ui_opt_textbox("balancer", undef, 20,
					     $text{'balancer_auto'})
			   : "<tt>$b->{'balancer'}</tt>");
	}

# URL path
print &ui_table_row($text{'balancer_path'},
	&ui_textbox("path", $b->{'path'}, 20));

if ($in{'new'} && $has == 2 || !$in{'new'} && $b->{'balancer'}) {
	# Destinations
	print &ui_table_row($text{'balancer_urls'},
		&ui_textarea("urls", join("\n", @{$b->{'urls'}}), 5, 60,
			     undef, $b->{'none'}));
	}
else {
	# Just one destination
	print &ui_table_row($text{'balancer_url'},
		&ui_textbox("urls", $b->{'urls'}->[0], 60, $b->{'none'}));
	}

# Disable proxying for this URL. This is only supported under Apache 2.0+,
# and cannot be enabled for existing balancers
if (($in{'new'} || !$b->{'balancer'}) &&
    (&has_proxy_none($d) || $b->{'none'})) {
	print &ui_table_row(" ",
	    &ui_checkbox("none", 1, $text{'balancer_none'},
		 $b->{'none'}, "onClick='form.urls.disabled = this.checked'"));
	}

# Used by script
if (!$in{'new'}) {
	($sinfo) = grep { $_->{'opts'}->{'path'} eq $b->{'path'} }
			&list_domain_scripts($d);
	if ($sinfo) {
		$script = &get_script($sinfo->{'name'});
		print &ui_table_row($text{'balancer_script'},
			"<a href='edit_script.cgi?dom=$in{'dom'}&".
			"script=$sinfo->{'id'}'>$script->{'desc'}</a>");
		print &ui_table_row($text{'balancer_scriptver'},
				    $sinfo->{'version'});
		}
	}

print &ui_table_end();
print &ui_form_end(
    $in{'new'} ? [ [ undef, $text{'create'} ] ]
    	       : [ [ undef, $text{'save'} ], [ "delete", $text{'delete'} ] ]);

&ui_print_footer("list_balancers.cgi?dom=$in{'dom'}",
		 $text{'balancers_return'},
		 &domain_footer_link($d),
		 "", $text{'index_return'});
