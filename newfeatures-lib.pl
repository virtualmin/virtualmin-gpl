# Functions for getting and showing new Virtualmin features

# list_new_features(mod, version)
# Returns a list of new features in a given Virtualmin or plugin version. Each
# is a hash ref containing the keys :
#  id - A unique name
#  desc - A short description
#  html - A longer HTML description
#  owner,reseller,admin - Set to 1 if usable by this type of user
#  link - An optional link to the feature. May include substitutions like $ID
# The list is returned oldest first, assuming that features have numeric prefix
sub list_new_features
{
local ($mod, $ver) = @_;
local (@rv, @dirs);
if ($mod eq $module_name) {
	# Core virtualmin features
	@dirs = map { "$_/$ver" } @newfeatures_dirs;
	}
else {
	# Features from some plugin
	@dirs = ( &module_root_directory($mod)."/newfeatures/".$ver );
	}
foreach my $dir (@dirs) {
	opendir(NF, $dir);
	foreach my $f (grep { !/^\./ } readdir(NF)) {
		local %nf;
		&read_file_cache("$dir/$f", \%nf);
		$nf{'id'} = $f;
		$nf{'mod'} = $mod;
		$nf{'ver'} = $ver;
		push(@rv, \%nf);
		}
	closedir(NF);
	}
return sort { $a <=> $b } @rv;
}

# should_show_new_features()
# If the current user should see new features, returns a list of modules and
# version numbers to show for.
sub should_show_new_features
{
# XXX plugins too
}

# set_seen_new_features(module, version, seen)
# Flags that the current user has seen (or not) new features for some version
sub set_seen_new_features
{
}

1;

