#!/usr/local/bin/perl
# Quickly show overview information about a domain

require './virtual-server-lib.pl';
use POSIX;
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
			"<tt><a href=http://$d->{'dom'}/>$d->{'dom'}</a></tt>",
			undef, \@tds);
	}
else {
	print &ui_table_row($text{'edit_domain'},
			    "<tt>$d->{'dom'}</tt>", undef, \@tds);
	}

# Creator
print &ui_table_row($text{'edit_created'},
	$d->{'creator'} ? &text('edit_createdby', &make_date($d->{'created'}),
						  $d->{'creator'})
			: &make_date($d->{'created'}),
	undef, \@tds);

# Owner
print &ui_table_row($text{'edit_user'}, "<tt>$d->{'user'}</tt>",
		    undef, \@tds);
print &ui_table_row($text{'edit_group'},
		    $d->{'unix'} && $d->{'group'} ? "<tt>$d->{'group'}</tt>"
						  : $text{'edit_nogroup'},
		    undef, \@tds);

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
	if ($d->{'reseller'}) {
		$resel = &get_reseller($d->{'reseller'});
		if ($resel) {
			$reselip = $resel->{'acl'}->{'defip'};
			}
		}
	print &ui_table_row($text{'edit_ip'},
		  "<tt>$d->{'ip'}</tt> ".
		  ($d->{'virt'} ? $text{'edit_private'} :
		   $d->{'ip'} eq $reselip ? &text('edit_rshared',
						  "<tt>$resel->{'name'}</tt>") :
					    $text{'edit_shared'}), 3, \@tds);
	}
if ($d->{'virt6'}) {
	print &ui_table_row($text{'edit_ip6'}, "<tt>$d->{'ip6'}</tt>");
	}

# Home directory
if (!$aliasdom && $d->{'dir'}) {
	print &ui_table_row($text{'edit_home'}, "<tt>$d->{'home'}</tt>",
			    3, \@tds);
	}

# Description
print &ui_table_row($text{'edit_owner'}, $d->{'owner'}, 3, \@tds);

if ($aliasdom) {
	# Alias destination
	print &ui_table_row($text{'edit_aliasto'},
	   "<a href='view_domain.cgi?dom=$d->{'alias'}'>".
	    &show_domain_name($aliasdom)."</a>",
	   3, \@tds);
	}
elsif (!$parentdom) {
	# Contact email address
	print &ui_table_row($text{'edit_email'}, $d->{'emailto'}, 3, \@tds);
	}
else {
	# Show link to parent domain
	print &ui_table_row($text{'edit_parent'},
	    "<a href='view_domain.cgi?dom=$d->{'parent'}'>".
	     &show_domain_name($parentdom)."</a>",
	    3, \@tds);
	}


print &ui_table_end();

&ui_print_footer("", $text{'index_return'});

