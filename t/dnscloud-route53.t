#!/usr/bin/perl
use strict;
use warnings;
no warnings qw(once redefine);
use Test::More;
use FindBin;

do "$FindBin::Bin/../dnscloud-lib.pl" or die $@ || $!;

subtest 'lookup returns zone ID and location without changing input' => sub {
	local $main::config{route53_location} = 'us-east-1';
	local *main::call_route53_cmd = sub {
		is_deeply($_[1], ['list-hosted-zones'], 'uses the paginated AWS CLI operation');
		return {HostedZones => [{Name => 'other.example.', Id => '/hostedzone/other'},
			{Name => 'example.com.', Id => '/hostedzone/existing'}]};
	};
	my $info = {domain => 'Example.COM.'};
	is_deeply([dnscloud_route53_find_zone($info)],
		[1, {id => '/hostedzone/existing', location => 'us-east-1'}], 'returns normalized zone details');
	is_deeply($info, {domain => 'Example.COM.'}, 'lookup leaves input unchanged');
};

subtest 'absent zones and API failures remain distinct' => sub {
	local *main::call_route53_cmd = sub { return {HostedZones => []}; };
	is_deeply([dnscloud_route53_find_zone({domain => 'example.com'})], [1, undef], 'reports absent zone');
	local *main::call_route53_cmd = sub { return 'Route 53 access denied'; };
	is_deeply([dnscloud_route53_find_zone({domain => 'example.com'})],
		[0, 'Route 53 access denied'], 'returns the lookup error');
	local *main::dnscloud_route53_put_records = sub { die 'Unexpected record write'; };
	is_deeply([dnscloud_route53_create_domain({}, {domain => 'example.com'})],
		[0, 'Route 53 access denied'], 'creation also stops on lookup failure');
};

subtest 'multiple zones require a matching saved ID' => sub {
	local *main::call_route53_cmd = sub {
		return {HostedZones => [map { {Name => 'example.com.', Id => "/hostedzone/$_"} } qw(first second)]};
	};
	local *main::dnscloud_route53_put_records = sub { die 'Unexpected record write'; };
	for my $id (undef, '/hostedzone/unrelated') {
		my ($ok, $error) = dnscloud_route53_find_zone({domain => 'example.com', id => $id});
		ok(!$ok, 'ambiguous lookup fails');
		like($error, qr/Multiple Route 53 zones/, 'explains the ambiguity');
	}
	for my $id ('second', '/hostedzone/second') {
		my ($ok, $zone) = dnscloud_route53_find_zone({domain => 'example.com', id => $id, location => 'eu-west-1'});
		ok($ok, 'saved ID resolves the ambiguity');
		is($zone->{id}, '/hostedzone/second', 'uses the selected zone');
		is($zone->{location}, 'eu-west-1', 'retains the requested location');
	}
	is_deeply([dnscloud_route53_create_domain({dom => 'example.com', dns_cloud => 'route53',
		dns_cloud_id => '/hostedzone/second'}, {domain => 'example.com', location => 'eu-west-1'})],
		[1, '/hostedzone/second', 'eu-west-1'], 'restore retains the saved zone without writes');
	my ($ok) = dnscloud_route53_create_domain({dom => 'old.example', dns_cloud => 'route53',
		dns_cloud_id => '/hostedzone/second'}, {domain => 'example.com'});
	ok(!$ok, 'does not reuse an old domain ID during a rename');
};

subtest 'new zones are still created and populated' => sub {
	my @calls;
	my $writes = 0;
	local $main::config{route53_location} = 'us-east-1';
	local *main::call_route53_cmd = sub {
		push @calls, $_[1];
		return {HostedZones => []} if $_[1]->[0] eq 'list-hosted-zones';
		return {HostedZone => {Id => '/hostedzone/new'}};
	};
	local *main::dnscloud_route53_put_records = sub { $writes++; return (1); };
	is_deeply([dnscloud_route53_create_domain({}, {domain => 'example.com'})],
		[1, '/hostedzone/new', 'us-east-1'], 'creates a missing zone');
	is($calls[1]->[0], 'create-hosted-zone', 'uses normal creation');
	is($writes, 1, 'uploads initial records');
};

done_testing();
