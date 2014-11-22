# Function to generate the left menu

require 'virtual-server-lib.pl';

# list_webmin_menu(&data)
# Returns items for the Virtualmin left menu
sub list_webmin_menu
{
my @rv;

# Preferred title
push(@rv, { 'type' => 'title',
	    'id' => 'title',
	    'icon' => '/'.$module_name.'/images/virtualmin.gif',
	    'desc' => $text{'left_virtualmin'} });

# Reseller's logo
my (undef, $image, $link, $alt) = &get_provider_link();
if ($image) {
	my $html = "";
        $html .= "<a href='".&html_escape($link)."' target='_new'>" if ($link);
        $html .= "<center><img src='".&html_escape($image)."' ".
                 "alt='".&html_escape($alt)."'></center>";
        $html .= "</a><br>\n" if ($link);
	push(@rv, { 'type' => 'html',
		    'html' => $html });
	}

# Login and level
my $level = &master_admin() ? $text{'left_master'} :
            &reseller_admin() ? $text{'left_reseller'} :
            &extra_admin() ? $text{'left_extra'} :
            $single_domain_mode ? $text{'left_single'} :
                                  $text{'left_user'};
push(@rv, { 'type' => 'text',
	    'desc' => $level });

my @alldoms = &list_domains();
my @doms = &list_visible_domains();
my $did = $data->{'dom'};
my $d;
if ($did) {
	($d) = grep { $_->{'id'} eq $did } @doms;
	}

if (@doms) {
	# Domain selector
	# XXX what if too many?
	# XXX auto-selection of summary_domain.cgi
	# XXX default domain if none is selected
	my @dlist = map { [ $_->{'id'},
			    ("&nbsp;&nbsp;" x $_->{'indent'}).
                            &shorten_domain_name($_),
                            $_->{'disabled'} ?
				"style='font-style:italic'" : "" ] } @doms;
	my $dmenu = { 'type' => 'menu',
		      'cgi' => '',
		      'name' => 'dom',
		      'icon' => '/'.$module_name.'/images/ok.gif',
		      'value' => $did,
		      'menu' => \@dlist };
	push(@rv, $menu);
	}
else {
	# No domains!
	push(@rv, { 'type' => 'text',
		    'desc' => @alldoms ? $text{'left_noaccess'}
				       : $text{'left_nodoms'} });
	}

# Domain creation item
if (&can_create_master_servers() || &can_create_sub_servers()) {
	($rdleft, $rdreason, $rdmax) = &count_domains("realdoms");
	($adleft, $adreason, $admax) = &count_domains("aliasdoms");
	if ($rdleft || $adleft) {
		push(@rv, { 'type' => 'item',
			    'desc' => $text{'left_generic'},
			    'link' => '/'.$module_name.
			     '/domain_form.cgi?generic=1&gparent='.$did,
			  });
		}
	else {
		push(@rv, { 'type' => 'html',
			    'html' => "<b>".$text{'left_nomore'}."</b>",
			  });
		}
	}

if ($d) {
	# Menu items for current domain
	my @buts = &get_all_domain_links($d);

	# Top-level links first
	my @incat = grep { $_->{'cat'} eq 'objects' } @buts;
	foreach my $b (@incat) {
		push(@rv, { 'type' => 'item',
			    'desc' => $b->{'title'},
			    'link' => $b->{'url'} });
		}

	# Other items by category
	my @cats = &unique(map { $_->{'cat'} } @buts);
	foreach my $c (@cats) {
                next if ($c eq 'objects' || $c eq 'create');
                my @incat = grep { $_->{'cat'} eq $c } @buts;
		my $cmenu = { 'type' => 'cat',
			      'desc' => $incat[0]->{'catname'},
			      'members' => [ ] };
		push(@rv, $cmenu);
		my @incatsort = grep { !$_->{'nosort'} } @incat;
                if (@incatsort) {
                        @incat = sort { ($a->{'title'} || $a->{'desc'}) cmp
                                        ($b->{'title'} || $b->{'desc'})} @incat;
                        }
		foreach my $b (@incat) {
			push(@{$cmenu->{'members'}},
			     { 'type' => 'item',
			       'desc' => $b->{'title'},
			       'link' => $b->{'url'} });
			}
		}
	}

# Global options
# XXX

return @rv;
}

1;
