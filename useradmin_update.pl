
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
if ($_[0]->{'olduser'} && $_[0]->{'olduser'} ne $_[0]->{'user'}) {
	local $d = &get_user_domain($_[0]->{'user'});
	if ($d) {
		# User was renamed .. update mailbox plainpass
		local %plain;
		&read_file_cached("$plainpass_dir/$d->{'id'}", \%plain);
		if ($plain{$_[0]->{'olduser'}}) {
			$plain{$_[0]->{'user'}} = $plain{$_[0]->{'olduser'}};
			delete($plain{$_[0]->{'olduser'}});
			&write_file("$plainpass_dir/$d->{'id'}", \%plain);
			}

		# And hashed passwords
		local %hash;
		&read_file_cached("$hashpass_dir/$d->{'id'}", \%hash);
		if ($hash{$_[0]->{'olduser'}}) {
			foreach my $s (@hashpass_types) {
				$hash{$_[0]->{'user'}.' '.$s} =
					$hash{$_[0]->{'olduser'}.' '.$s};
				delete($hash{$_[0]->{'olduser'}.' '.$s});
				}
			&write_file("$hashpass_dir/$d->{'id'}", \%hash);
			}
		}
	}

if ($_[0]->{'passmode'} == 3) {
	&set_all_null_print();

	# Update passwords for domain owners
	foreach my $d (&get_domain_by("user", $_[0]->{'user'})) {
		$oldd = { %$d };
		$d->{'pass'} = $_[0]->{'plainpass'};
		$d->{'pass_set'} = 1;
		&generate_domain_password_hashes($d, 0);
		if ($d->{'disabled'}) {
			# Clear any saved passwords, as they should
			# be reset at this point
			$d->{'disabled_oldpass'} = $_[0]->{'pass'};
			$d->{'disabled_mysqlpass'} = undef;
			$d->{'disabled_postgrespass'} = undef;
			}
		# Update all features, except Unix which has already been
		# updated by caller
		foreach my $f (@features) {
			if ($f ne "unix" && $config{$f} && $d->{$f}) {
				local $mfunc = "modify_".$f;
				&$mfunc($d, $oldd);
				}
			}
		# Update all plugins
		foreach my $f (&list_feature_plugins()) {
			if ($d->{$f}) {
				&plugin_call($f, "feature_modify", $d, $oldd);
				}
			}
		&save_domain($d);
		}

	# Update mailbox user passwords
	local $d = &get_user_domain($_[0]->{'user'});
	if ($d && $d->{'user'} ne $_[0]->{'user'}) {
		local ($user) = grep { $_->{'user'} eq $_[0]->{'user'} }
				     &list_domain_users($d, 1, 0, 0, 0);
		if ($user) {
			$olduser = { %$user };
			$user->{'passmode'} = 3;
			$user->{'plainpass'} = $_[0]->{'plainpass'};
			$user->{'pass'} = &encrypt_user_password(
						$user, $_[0]->{'plainpass'});
			&modify_user($user, $olduser, $d);

			# Call plugin save functions
			foreach $f (&list_mail_plugins()) {
				&plugin_call($f, "mailbox_modify",
					     $user, $olduser, $d);
				}
			}
		}

	&run_post_actions();
	}
}

sub null_print
{
}

