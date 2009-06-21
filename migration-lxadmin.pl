# Functions for migrating an LXadmin backup

# migration_cpanel_validate(file, domain, [user], [&parent], [prefix], [pass])
# Make sure the given file is an LXadmin backup, and contains the domain
sub migration_lxadmin_validate
{
local ($file, $dom, $user, $parent, $prefix, $pass) = @_;
local ($ok, $root) = &extract_lxadmin_dir($file);
$ok || return ("Not an LXadmin tar file : $root");
-r "$root/kloxo.file" ||
	return ("Not an LXadmin backup - missing kloxo.file");
-r "$root/kloxo.metadata" ||
	return ("Not an LXadmin backup - missing kloxo.metadata");

# Parse data files
local $filehash = &parse_lxadmin_file("$root/kloxo.file");
ref($filehash) || return "Failed to parse kloxo.file : $filehash";
local $metahash = &parse_lxadmin_file("$root/kloxo.metadata");
ref($metahash) || return "Failed to parse kloxo.metadata : $metahash";

if (!$dom) {
	# Work out the domain
	}
else {
	# Validate that the domain is in this backup
	}

# Work out the username

# Get the password from the metadata file

return (undef, $dom, $user, $pass);
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

# extract_lxadmin_dir(file)
# Extracts a tar file, and returns a status code and either the directory
# under which it was extracted, or an error message
sub extract_lxadmin_dir
{
local ($file) = @_;
return undef if (!-r $file);
if ($main::lxadmin_dir_cache{$file} && -d $main::lxadmin_dir_cache{$file}) {
	# Use cached extract from this session
	return (1, $main::lxadmin_dir_cache{$file});
	}
local $temp = &transname();
mkdir($temp, 0700);
local $err = &extract_compressed_file($file, $temp);
if ($err) {
	return (0, $err);
	}
$main::lxadmin_dir_cache{$file} = $temp;
return (1, $temp);
}

# parse_lxadmin_file(file)
# Returns a hash ref for the contents of an LXadmin metadata file, which is
# actually just PHP serialized data. Returns a string on failure.
sub parse_lxadmin_file
{
local ($file) = @_;
local $ser = &read_file_contents($file);
$ser || return "$file is missing or empty";
$ser =~ /0:6:"Remote"/ || return "$file does not appear to contain PHP serialized data";
eval "use serialize";
$@ && return "Failed to load serialize module : $@";
local $rv = eval { unserialize($ser) };
$@ && return "Un-serialization failed : $@";
ref($rv) || return "Un-serialization did not return a hash : $rv";
return $rv;
}

