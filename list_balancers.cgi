#!/usr/local/bin/perl
# Display proxies in some domain

$0 =~ /^(.*)\/pro\// && chdir($1);
require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_forward() ||
	&error($text{'balancers_ecannot'});
$has = &has_proxy_balancer($d);
$has || &error($text{'balancers_esupport'});
&ui_print_header(&domain_in($d), $text{'balancers_title'}, "", "balancers");

# Find scripts in this domain that use the proxy path
foreach $sinfo (&list_domain_scripts($d)) {
	$used{$sinfo->{'opts'}->{'path'}} = $sinfo;
	}

# Build table data
@balancers = &list_proxy_balancers($d);
foreach $b (@balancers) {
	$sinfo = $used{$b->{'path'}};
	$umsg = "";
	if ($sinfo) {
		# Used by a script
		$script = &get_script($sinfo->{'name'});
		$umsg = "<a href='edit_script.cgi?dom=$in{'dom'}&".
			"script=$sinfo->{'id'}'>".
			$script->{'desc'}." ".$sinfo->{'version'}.
			"</a>";
		}
	push(@table, [
		{ 'type' => 'checkbox', 'name' => 'd',
		  'value' => $b->{'path'} },
		"<a href='edit_balancer.cgi?dom=$in{'dom'}&".
		  "path=$b->{'path'}'>$b->{'path'}</a>",
		$has == 2 ? ( $b->{'balancer'} ) : ( ),
		$b->{'none'} ? "<i>$text{'balancers_none2'}</i>"
			     : join("<br>", @{$b->{'urls'}}),
		$umsg,
		]);
	}

# Generate the table
print &ui_form_columns_table(
	"delete_balancers.cgi",
	[ [ undef, $text{'balancers_delete'} ] ],
	1,
	[ [ "edit_balancer.cgi?new=1&dom=$in{'dom'}",
	    $text{'balancers_add'} ] ],
	[ [ "dom", $in{'dom'} ] ],
	[ "", $text{'balancers_path'},
          $has == 2 ? ( $text{'balancers_name'} ) : ( ),
          $text{'balancers_urls'},
          $text{'balancers_used'} ],
	100,
	\@table,
	undef,
	0,
	undef,
	$text{'balancers_none'},
	);

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});
