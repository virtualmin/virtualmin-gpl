# Functions for setting up jails for domain owners

# check_jailkit_support()
# Returns an error message if jailing users is not available, undef otherwise
sub check_jailkit_support
{
if (!&foreign_check("jailkit")) {
	return $text{'jailkit_emodule'};
	}
if (!&foreign_installed("jailkit")) {
	return $text{'jailkit_emodule2'};
	}
return undef;
}

1;
