#!/usr/local/bin/perl
# Actually transfer a domain to another system

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'transfer_err'});
$d = &get_domain($in{'dom'});
&can_move_domain($d) || &error($text{'transfer_ecannot'});

# Validate inputs
my @hosts = &get_transfer_hosts();
if ($in{'host_mode'}) {
	my ($h) = grep { $_->[0] eq $in{'oldhost'} } @hosts;
	$host = $h->[0];
	$pass = $h->[1];
	}
else {
	$in{'host'} =~ /^\S+$/ || &error($text{'transfer_ehost'});
	($hostname) = split(/:/, $in{'host'});
	&to_ipaddress($hostname) || &to_ip6address($hostname) ||
		&error($text{'transfer_ehost2'});
	$host = $in{'host'};
	$pass = $in{'hostpass'};
	if ($in{'savehost'}) {
		my ($h) = grep { $_->[0] eq $in{'host'} } @hosts;
		if ($h) {
			$h->[1] = $pass;
			}
		else {
			push(@hosts, [ $host, $pass ]);
			}
		&save_transfer_hosts(@hosts);
		}
	}
my $err = &validate_transfer_host($d, $host, $pass, $in{'overwrite'});
&error($err) if ($err);

# Save the host, if requested

&ui_print_unbuffered_header(&domain_in($d), $text{'transfer_title'}, "");

# Call the transfer function
my @subs = ( &get_domain_by("parent", $d->{'id'}),
	     &get_domain_by("alias", $d->{'id'}) );
&$first_print(&text(@subs ? 'transfer_doing2' : 'transfer_doing',
		    $d->{'dom'}, $host, scalar(@subs)));
&$indent_print();
$ok = &transfer_virtual_server($d, $host, $pass,
			       $in{'delete'},
			       $in{'overwrite'} && !$in{'delete'});
&$outdent_print();
if ($ok) {
	&$second_print($text{'setup_done'});
	}
else {
	&$second_print($text{'transfer_failed'});
	}

&run_post_actions();
&webmin_log("transfer", "domain", $d->{'dom'}, $d);

# Call any theme post command
if (defined(&theme_post_save_domain)) {
        &theme_post_save_domain($d, $in{'delete'} == 2 ? 'delete' : 'modify');
        }

&ui_print_footer(&domain_footer_link($d),
        "", $text{'index_return'});


