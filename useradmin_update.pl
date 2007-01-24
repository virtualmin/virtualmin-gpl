
do 'virtual-server-lib.pl';

# useradmin_create_user(&details)
# Does nothing
sub useradmin_create_user
{
}

# useradmin_delete_user(&details)
# Does nothing (though maybe could delete the domain)
sub useradmin_delete_user
{
}

# useradmin_modify_user(&details)
# If the domain user's password is being changed, update it in the domain's
# file as well
sub useradmin_modify_user
{
if ($_[0]->{'passmode'} == 3) {
	&set_all_null_print();
	foreach my $d (&get_domain_by("user", $_[0]->{'user'})) {
		$oldd = { %$d };
		$d->{'pass'} = $_[0]->{'plainpass'};
		if ($d->{'disabled'}) {
			# Clear any saved passwords, as they should
			# be reset at this point
			$d->{'disabled_oldpass'} = $_[0]->{'pass'};
			$d->{'disabled_mysqlpass'} = undef;
			$d->{'disabled_postgrespass'} = undef;
			}
		# Update all features
		foreach my $f (@features) {
			if ($config{$f} && $d->{$f}) {
				local $mfunc = "modify_".$f;
				&$mfunc($d, $oldd);
				}
			}
		# Update all plugins
		foreach my $f (@feature_plugins) {
			if ($d->{$f}) {
				&plugin_call($f, "feature_modify", $d, $oldd);
				}
			}
		&save_domain($d);
		}
	&run_post_actions();
	}
}

sub null_print
{
}

