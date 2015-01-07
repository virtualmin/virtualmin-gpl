# Function to generate the left menu

require 'virtual-server-lib.pl';

# list_webmin_menu(&data, &in)
# Returns items for the Virtualmin left menu
sub list_webmin_menu
{
my ($data, $in) = @_;
my @rv;

# Preferred title
push(@rv, { 'type' => 'title',
	    'id' => 'title',
	    'icon' => '/'.$module_name.'/images/virtualmin.png',
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
push(@rv, { 'type' => 'text',
	    'desc' => &text('left_login', $remote_user) });
my $level = &master_admin() ? $text{'left_master'} :
            &reseller_admin() ? $text{'left_reseller'} :
            &extra_admin() ? $text{'left_extra'} :
            $single_domain_mode ? $text{'left_single'} :
                                  $text{'left_user'};
push(@rv, { 'type' => 'text',
	    'desc' => $level });
push(@rv, { 'type' => 'hr' });

# Get domains and find the default
my @alldoms = &list_domains();
my @doms = &list_visible_domains();
my ($d, $did);
if (defined($in->{'dom'})) {
	# Specific domain given
	$did = $in->{'dom'};
	$d = &get_domain($did);
	}
elsif (defined($in{'dname'})) {
	# Domain selected by name or username
	$d = &get_domain_by("dom", $in->{'dname'});
	if (!$d) {
		$d = &get_domain_by("user", $in->{'dname'}, "parent", "");
		}
	$did = $d->{'id'} if ($d);
	}
elsif ($data->{'dom'}) {
	# Default as requested by theme
	$did = $data->{'dom'};
	$d = &get_domain($did);
	}
if (!$d || !&can_edit_domain($d)) {
	$d = $did = undef;
	}

# Make sure the selected domain is in the menu .. may not be for
# alias domains if they are hidden
if ($d && &can_edit_domain($d)) {
	my @ids = map { $_->{'id'} } @doms;
	if (&indexof($d->{'id'}, @ids) < 0) {
		push(@doms, $d);
		}
	}
@doms = &sort_indent_domains(\@doms);

# Fall back to first owned by this user, or first in list
$d ||= &get_domain_by("user", $remote_user, "parent", "");
$d ||= $doms[0];

if (@doms > $config{'display_max'} && $config{'display_max'}) {
	# Domain text box
	my $dfield = { 'type' => 'input',
		       'cgi' => '',
		       'name' => 'dname',
		       'icon' => '/'.$module_name.'/images/ok.png',
		       'value' => $d ? $d->{'dom'} : '',
		       'size' => 15 };
	push(@rv, $dfield);
	}
elsif (@doms) {
	# Domain selector
	my @dlist = map { [ $_->{'id'},
			    ("&nbsp;&nbsp;" x $_->{'indent'}).
                            &shorten_domain_name($_),
                            $_->{'disabled'} ?
				"style='font-style:italic'" : "" ] } @doms;
	my $dmenu = { 'type' => 'menu',
		      'cgi' => '',
		      'name' => 'dom',
		      'icon' => '/'.$module_name.'/images/ok.png',
		      'value' => $did,
		      'onchange' => '/'.$module_name.'/summary_domain.cgi?dom=',
		      'menu' => \@dlist };
	push(@rv, $dmenu);
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
			     '/domain_form.cgi?generic=1&amp;gparent='.$did,
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
		push(@rv, &button_to_menu_item($b));
		}

	# Other items by category
	my @cats = &unique(map { $_->{'cat'} } @buts);
	foreach my $c (@cats) {
                next if ($c eq 'objects' || $c eq 'create');
                my @incat = grep { $_->{'cat'} eq $c } @buts;
		my $cmenu = { 'type' => 'cat',
			      'id' => 'cat_'.$c,
			      'desc' => $incat[0]->{'catname'},
			      'members' => [ ] };
		push(@rv, $cmenu);
		my @incatsort = grep { !$_->{'nosort'} } @incat;
                if (@incatsort) {
                        @incat = sort { ($a->{'title'} || $a->{'desc'}) cmp
                                        ($b->{'title'} || $b->{'desc'})} @incat;
                        }
		foreach my $b (@incat) {
			push(@{$cmenu->{'members'}}, &button_to_menu_item($b));
			}
		}
	}

# Global options
push(@rv, { 'type' => 'hr' });
my @buts = &get_all_global_links();
my @tcats = &unique(map { $_->{'cat'} } @buts);
foreach my $tc (@tcats) {
	my @incat = grep { $_->{'cat'} eq $tc } @buts;
	if ($tc) {
		# Under a category
		my $cmenu = { 'type' => 'cat',
			      'id' => 'global_'.$tc,
			      'desc' => $incat[0]->{'catname'},
			      'members' => [ ] };
		my @incatsort = sort { ($a->{'title'} || $a->{'desc'}) cmp
                                        ($b->{'title'} || $b->{'desc'}) }
				     @incat;
		foreach my $b (@incatsort) {
			push(@{$cmenu->{'members'}}, &button_to_menu_item($b));
			}
		push(@rv, $cmenu);
		}
	else {
		# At top level
		foreach my $b (@incat) {
			push(@rv, &button_to_menu_item($b, 1));
			}
		}
	}

return @rv;
}

# button_to_menu_item(&button, want-icon)
sub button_to_menu_item
{
my ($b, $wanticon) = @_;
my $i = { 'type' => 'item',
	  'desc' => $b->{'title'},
	  'link' => $b->{'url'} };
if ($b->{'icon'} && $wanticon) {
	$i->{'icon'} = '/'.$module_name.'/images/'.$b->{'icon'}.'.png';
	}
if ($b->{'target'} eq '_top') {
	$i->{'target'} = 'window';
	}
elsif ($b->{'target'} eq '_blank' || $b->{'target'} eq '_new') {
	$i->{'target'} = 'new';
	}
return $i;
}

1;
