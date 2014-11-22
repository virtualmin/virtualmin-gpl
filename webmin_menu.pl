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

# Domain selector
my @alldoms = &list_domains();
my @doms = &list_visible_domains();

# Menu items for current domain
# XXX

# Global options
# XXX

return @rv;
}

1;
