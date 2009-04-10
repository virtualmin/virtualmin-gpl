# Functions for IPv6 address management

# Returns 1 if this system supports IPv6 addresses. Currently only true on
# Linux where the ifconfig command reports v6 addresses
sub supports_ip6
{
if (!defined($supports_ip6_cache)) {
	if ($gconfig{'os_type'} =~ /-linux$/) {
		local $out = &backquote_command(
			"LC_ALL='' LANG='' ifconfig -a");
		$supports_ip6_cache = $out =~ /inet6 addr:/ ? 1 : 0;
		}
	else {
		$supports_ip6_cache = 0;
		}
	}
return $supports_ip6_cache;
}

# setup_virt6(&domain)
# Adds an IPv6 address to the system for a domain
sub setup_virt6
{
# XXX now and boot time
}

# modify_virt6(&domain, &old-domain)
# Changes the IPv6 address for a domain, if needed
sub modify_virt6
{
}

# delete_virt6(&domain)
# Removes the IPv6 interface for a domain
sub delete_virt6
{
}

1;

