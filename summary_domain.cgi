#!/usr/local/bin/perl
# Quickly show overview information about a domain

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
$d || &error($text{'edit_egone'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
if ($d->{'parent'}) {
	$parentdom = &get_domain($d->{'parent'});
	}
if ($d->{'alias'}) {
	$aliasdom = &get_domain($d->{'alias'});
	}
if ($d->{'subdom'}) {
	$subdom = &get_domain($d->{'subdom'});
	}
$tmpl = &get_template($d->{'template'});

&ui_print_header(&domain_in($d), $aliasdom ?  $text{'summary_title3'} :
                                 $subdom ?    $text{'summary_title4'} :
                                 $parentdom ? $text{'summary_title2'} :
                                              $text{'summary_title'}, "");

@tds = ( "width=30%" );
print &ui_table_start($text{'edit_header'}, "width=100%", 4);

# Domain name (with link), user and group
if ($d->{'web'}) {
	print &ui_table_row($text{'edit_domain'},
	    "<tt>".&ui_link($url, $d->{'dom'}, undef, "target=_blank")."</tt>",
	    undef, \@tds);
	}
else {
	print &ui_table_row($text{'edit_domain'},
			    "<tt>$d->{'dom'}</tt>", undef, \@tds);
	}

# Creator
print &ui_table_row($text{'edit_created'},
	$d->{'creator'} ? &text('edit_createdby', &make_date($d->{'created'},1),
						  $d->{'creator'})
			: &make_date($d->{'created'}),
	$d->{'creator'} ? 3 : 1, \@tds);

# Owner
print &ui_table_row($text{'edit_user'}, "<tt>$d->{'user'}</tt>",
		    undef, \@tds);
if (!$d->{'parent'}) {
	print &ui_table_row($text{'edit_group'},
		    $d->{'unix'} && $d->{'group'} ? "<tt>$d->{'group'}</tt>"
						  : $text{'edit_nogroup'},
		    undef, \@tds);
	}

# Show user and group quotas
if (&has_home_quotas() && !$parentdom) {
	print &ui_table_row($text{'edit_quota'},
	    $d->{'quota'} ? &quota_show($d->{'quota'}, "home")
			  : $text{'form_unlimit'}, 1, \@tds);

	print &ui_table_row($text{'edit_uquota'},
	    $d->{'uquota'} ? &quota_show($d->{'uquota'}, "home")
			   : $text{'form_unlimit'}, 1, \@tds);
	}


# IP-related options
if (!$aliasdom) {
	if (defined(&get_reseller)) {
		foreach $r (split(/\s+/, $d->{'reseller'})) {
			$resel = &get_reseller($r);
			if ($resel && $resel->{'acl'}->{'defip'}) {
				$reselip = $resel->{'acl'}->{'defip'};
				$reselip6 = $resel->{'acl'}->{'defip6'};
				}
			}
		}
	print &ui_table_row($text{'edit_ip'},
		  "<tt>$d->{'ip'}</tt> ".
		  ($d->{'virt'} ? $text{'edit_private'} :
		   $d->{'ip'} eq $reselip ? &text('edit_rshared',
						  "<tt>$resel->{'name'}</tt>") :
					    $text{'edit_shared'}), 3, \@tds);
	}
if ($d->{'ip6'} && !$aliasdom) {
	print &ui_table_row($text{'edit_ip6'},
		"<tt>$d->{'ip6'}</tt> ".
		($d->{'virt6'} ? $text{'edit_private'} :
		 $d->{'ip6'} eq $reselip6 ? &text('edit_rshared',
						  "<tt>$resel->{'name'}</tt>") :
			       		    $text{'edit_shared'}), 3, \@tds);
	}

# Plan, if any
if ($d->{'plan'}) {
	$plan = &get_plan($d->{'plan'});
	print &ui_table_row($text{'edit_plan'}, $plan->{'name'}, undef, \@tds);
	}

if ($aliasdom) {
	# Alias destination
	print &ui_table_row($text{'edit_aliasto'},
	   "<a href='view_domain.cgi?dom=$d->{'alias'}'>".
	    &show_domain_name($aliasdom)."</a>",
	   undef, \@tds);
	}
elsif (!$parentdom) {
	# Contact email address
	print &ui_table_row($text{'edit_email'},
			    &html_escape($d->{'emailto'}), undef, \@tds);
	}
else {
	# Show link to parent domain
	print &ui_table_row($text{'edit_parent'},
	    "<a href='view_domain.cgi?dom=$d->{'parent'}'>".
	     &show_domain_name($parentdom)."</a>",
	    undef, \@tds);
	}

# Home directory
if (!$aliasdom && $d->{'dir'}) {
	print &ui_table_row($text{'edit_home'}, "<tt>$d->{'home'}</tt>",
			    3, \@tds);
	}

# Description
print &ui_table_row($text{'edit_owner'}, $d->{'owner'}, 3, \@tds);

# Show domain ID
if (&master_admin()) {
	print &ui_table_row($text{'edit_id'},
			    "<tt>$d->{'id'}</tt>");
	}

print &ui_table_end();

&ui_print_footer("", $text{'index_return'});

