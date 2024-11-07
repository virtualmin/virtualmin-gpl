#!/usr/local/bin/perl
# Turn two-factor on or off

require './virtual-server-lib.pl';
&ReadParse();
&licence_status();
&error_setup($text{'2fa_err'});
&can_user_2fa() || &can_master_reseller_2fa() || &error($text{'2fa_ecannot'});

# Get current status
&foreign_require("acl");
&foreign_require("webmin");
my @users = &acl::list_users();
my ($user) = grep { $_->{'name'} eq $base_remote_user } @users;
$user || &error($text{'2fa_euser'});
my @provs = &webmin::list_twofactor_providers();

if ($user->{'twofactor_provider'}) {
	# Cancel it
        $user->{'twofactor_provider'} = undef;
        $user->{'twofactor_id'} = undef;
        $user->{'twofactor_apikey'} = undef;
        &acl::modify_user($user->{'name'}, $user);
        &reload_miniserv();

	# Also cancel in Usermin, if setup
	if (&foreign_installed("usermin")) {
		&foreign_require("usermin");
		&foreign_require("webmin");
		if (defined(&webmin::save_user_twofactor)) {
			my %miniserv;
			&usermin::get_usermin_miniserv_config(\%miniserv);
			&webmin::save_user_twofactor(
				$user->{'name'}, \%miniserv);
			&usermin::reload_usermin_miniserv();
			}
		}

	&redirect("");
	}
else {
	# Validate enrollment inputs
        my $vfunc = "webmin::parse_twofactor_form_".
                    $miniserv{'twofactor_provider'};
        my $details;
        if (defined(&{\&{$vfunc}})) {
                $details = &{\&{$vfunc}}(\%in, $user);
                &error($details) if (!ref($details));
                }

	&ui_print_header(undef, $text{'2fa_title'}, "");
	my @provs = &webmin::list_twofactor_providers();
	my %miniserv;
	&get_miniserv_config(\%miniserv);
	my ($prov) = grep { $_->[0] eq $miniserv{'twofactor_provider'} } @provs;

	# Register the user
        print &text('2fa_enrolling', $prov->[1]),"<br>\n";
        my $efunc = "webmin::enroll_twofactor_".$miniserv{'twofactor_provider'};
        my $err = &{\&{$efunc}}($details, $user);
        if ($err) {
                # Failed!
                print &text('twofactor_failed', $err),"<p>\n";
                }
        else {
                print &text('twofactor_done', $user->{'twofactor_id'}),"<p>\n";

                # Print provider-specific message
                my $mfunc = "webmin::message_twofactor_".
                            $miniserv{'twofactor_provider'};
                if (defined(&{\&{$mfunc}})) {
                        print &{\&{$mfunc}}($user);
                        }

                # Save user
                $user->{'twofactor_provider'} = $miniserv{'twofactor_provider'};
                &acl::modify_user($user->{'name'}, $user);
                &reload_miniserv();

		# Also setup in Usermin, if supported
		if (&foreign_installed("usermin")) {
			&foreign_require("usermin");
			&foreign_require("webmin");
			if (defined(&webmin::save_user_twofactor)) {
				my %miniserv;
				&usermin::get_usermin_miniserv_config(
					\%miniserv);
				&webmin::save_user_twofactor(
					$user->{'name'},
					\%miniserv,
					$user->{'twofactor_provider'},
					$user->{'twofactor_id'},
					$user->{'twofactor_apikey'});
				&usermin::reload_usermin_miniserv();
				}
			}
                }

	&ui_print_footer("", $text{'index_return'});
	}
