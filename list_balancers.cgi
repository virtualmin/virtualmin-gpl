#!/usr/local/bin/perl
# Display proxies in some domain

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_forward() ||
	&error($text{'balancers_ecannot'});
$has = &has_proxy_balancer($d);
$has || &error($text{'balancers_esupport'});
&ui_print_header(&domain_in($d), $text{'balancers_title'}, "", "balancers");

# Find scripts and plugins in this domain that use the proxy path
&get_balancer_usage($d, \%used, \%pused);

# Build table data
@balancers = &list_proxy_balancers($d);
foreach $b (@balancers) {
	$umsg = "";
	if ($sinfo = $used{$b->{'path'}}) {
		# Used by a script
		$script = &get_script($sinfo->{'name'});
		$umsg = &ui_link("edit_script.cgi?dom=$in{'dom'}&".
				 "script=$sinfo->{'id'}",
				 &text('balancers_script', $script->{'desc'},
					$sinfo->{'version'}));
		}
	elsif ($pinfo = $pused{$b->{'path'}}) {
		# Used by a plugin
		%pinfo = &get_module_info($pinfo->{'plugin'});
		$umsg = $pinfo->{'link'} ?
				&ui_link($pinfo->{'link'}, $pinfo->{'desc'}) :
				$pinfo->{'desc'};
		}
	&remove_unix_localhost($b);
	push(@table, [
		{ 'type' => 'checkbox', 'name' => 'd',
		  'value' => $b->{'path'} },
		&ui_link("edit_balancer.cgi?dom=$in{'dom'}&path=".
			 &urlize($b->{'path'}), $b->{'path'}),
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
          $text{'balancers_urls'},
          $text{'balancers_used2'} ],
	100,
	\@table,
	undef,
	0,
	undef,
	$text{'balancers_none'},
	);

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});
