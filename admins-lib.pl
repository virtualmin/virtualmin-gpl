# Functions for managing extra admins

# list_extra_admins(&domain)
# Returns a list of extra admins for some domain
sub list_extra_admins
{
local ($d) = @_;
local @rv;
opendir(DIR, "$extra_admins_dir/$d->{'id'}");
foreach my $f (readdir(DIR)) {
	if ($f =~ /^(.*)\.admin$/) {
		local %admin;
		&read_file("$extra_admins_dir/$d->{'id'}/$f", \%admin);
		$admin{'file'} = "$extra_admins_dir/$d->{'id'}/$f";
		push(@rv, \%admin);
		}
	}
closedir(DIR);
return @rv;
}

# create_extra_admin(&admin, &domain)
# Create an extra admin account for a domain
sub create_extra_admin
{
local ($admin, $d) = @_;
mkdir($extra_admins_dir, 0700);
mkdir("$extra_admins_dir/$d->{'id'}", 0700);
$admin->{'file'} = "$extra_admins_dir/$d->{'id'}/$admin->{'name'}.admin";
&write_file($admin->{'file'}, $admin);
&push_all_print();
&refresh_webmin_user($d);
&run_post_actions();
&pop_all_print();
}

# delete_extra_admin(&admin, &domain)
# Remove an extra admin account
sub delete_extra_admin
{
local ($admin, $d) = @_;
unlink($admin->{'file'});
&push_all_print();
&refresh_webmin_user($d);
&run_post_actions();
&pop_all_print();
}

# modify_extra_admin(&admin, &old, &domain)
# Update an extra admin
sub modify_extra_admin
{
local ($admin, $old, $d) = @_;
if ($old->{'name'} ne $admin->{'name'}) {
	unlink($old->{'file'});
	$admin->{'file'} = "$extra_admins_dir/$d->{'id'}/$admin->{'name'}.admin";
	}
&write_file($admin->{'file'}, $admin);
&set_all_null_print();
&push_all_print();
&refresh_webmin_user($d);
&run_post_actions();
&pop_all_print();
}

1;

