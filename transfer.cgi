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
	# Use an old host
	my ($h) = grep { $_->[0] eq $in{'oldhost'} } @hosts;
	$h || &error($text{'transfer_eoldhost'});
	$host = $h->[0];
	$pass = $h->[1];
	$proto = $h->[2] || 'ssh';
	$user = $h->[3] || 'root';
	}
else {
	# Entering a new host
	$in{'host'} =~ /^\S+$/ || &error($text{'transfer_ehost'});
	($hostname) = split(/:/, $in{'host'});
	&to_ipaddress($hostname) || &to_ip6address($hostname) ||
		&error($text{'transfer_ehost2'});
	$host = $in{'host'};
	$user = $in{'hostuser'};
	$pass = $in{'hostpass'};
	$proto = $in{'proto'};
	if ($in{'savehost'}) {
		my ($h) = grep { $_->[0] eq $in{'host'} } @hosts;
		if ($h) {
			$h->[1] = $pass;
			$h->[2] = $proto;
			$h->[3] = $user;
			}
		else {
			push(@hosts, [ $host, $pass, $proto, $user ]);
			}
		&save_transfer_hosts(@hosts);
		}
	}
my $err = &validate_transfer_host($d, $host, $user, $pass, $proto,
				  $in{'overwrite'});
&error($err) if ($err);

# Cannot both delete and replicate
if ($in{'delete'} && $in{'replication'}) {
	&error($text{'transfer_ereplication'});
	}

&ui_print_unbuffered_header(&domain_in($d), $text{'transfer_title'}, "");

# Call the transfer function
my @subs = ( &get_domain_by("parent", $d->{'id'}),
	     &get_domain_by("alias", $d->{'id'}) );
&$first_print(&text(@subs ? 'transfer_doing2' : 'transfer_doing',
		    $d->{'dom'}, $host, scalar(@subs)));
&$indent_print();
$ok = &transfer_virtual_server($d, $host, $user, $pass, $proto,
			       $in{'delete'},
			       $in{'overwrite'} && !$in{'delete'},
			       $in{'replication'}, $in{'output'});
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


