# Functions for migrating an LXadmin backup

# migration_cpanel_validate(file, domain, [user], [&parent], [prefix], [pass])
# Make sure the given file is an LXadmin backup, and contains the domain
sub migration_lxadmin_validate
{
local ($file, $dom, $user, $parent, $prefix, $pass) = @_;

# XXX
}

# migration_lxadmin_migrate(file, domain, username, create-webmin, template-id,
#			    ip-address, virtmode, pass, [&parent], [prefix],
#			    virt-already, [email], [netmask])
# Actually extract the given LXadmin backup, and return the list of domains
# created.
sub migration_lxadmin_migrate
{
local ($file, $dom, $user, $webmin, $template, $ip, $virt, $pass, $parent,
       $prefix, $virtalready, $email, $netmask) = @_;
local @rv;

# XXX

return @rv;
}

