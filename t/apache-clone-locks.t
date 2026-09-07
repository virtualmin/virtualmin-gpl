#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use FindBin;
use Scalar::Util qw(refaddr);

# Load the feature functions without initializing Webmin or any host services.
foreach my $feature (qw(web ssl)) {
	do "$FindBin::Bin/../feature-$feature.pl"
		or die "Failed to load feature-$feature.pl: $@ $!";
	}

# Exercise the real clone and counted-lock functions against an Apache cache
# that replaces its parsed objects whenever a new outer lock is acquired.
sub run_clone
{
my ($feature, $missing) = @_;
my $source = { 'id' => 1, 'dom' => 'source.test', 'web_port' => 80,
	      'web_sslport' => 443 };
my $target = { 'id' => 2, 'dom' => 'target.test', 'web_port' => 80,
	      'web_sslport' => 443, 'ssl_same' => 1,
	      'ssl_cert' => '/target.cert', 'ssl_key' => '/target.key',
	      'ssl_combined' => '/target.combined' };
my (@cache, %locked, @unlocked_reads, @stale_writes, @unlocked_writes);
my ($flushes, $nested_updates, $writes) = (0, 0, 0);
my $mainfile = '/apache/httpd.conf';
my $result;

{
	no warnings qw(once redefine);
	local %main::config = ( 'web' => 1 );
	local %main::got_lock_web_file;
	local %main::got_lock_web_path;
	local $main::got_lock_web_conf;
	local $main::first_print = sub { };
	local $main::second_print = sub { };
	local *main::require_apache = sub { };
	local *main::obtain_lock_anything = sub { };
	local *main::release_lock_anything = sub { };
	local *main::get_website_file = sub { return '/apache/'.$_[0]->{'dom'}.'.conf'; };
	local *main::lock_file = sub { $locked{$_[0]} = 1; };
	local *main::unlock_file = sub { delete($locked{$_[0]}); };
	local *apache::find_httpd_conf = sub { return $mainfile; };
	local *apache::flush_config_cache = sub { @cache = (); $flushes++; };
	local *main::get_apache_virtual = sub {
		my ($name) = @_;
		push(@unlocked_reads, $name) if (!$locked{$mainfile});
		if (!@cache) {
			@cache = map { { 'dom' => $_->{'dom'},
				'file' => "/apache/$_->{'dom'}.conf",
				'members' => [ { 'name' => 'SSLProtocol',
					'value' => 'all -TLSv1 -TLSv1.1' } ] } }
				grep { !$missing || $_->{'dom'} ne "$missing.test" }
				($source, $target);
			}
		my ($virt) = grep { $_->{'dom'} eq $name } @cache;
		return $virt ? ($virt, $virt->{'members'}, \@cache) : ();
		};

	# Verify that edits use the current parse while its outer lock is held.
	my $check_write = sub {
		my ($members) = @_;
		$writes++;
		push(@unlocked_writes, 1) if (!$locked{$mainfile});
		my ($current) = grep { $_->{'dom'} eq $target->{'dom'} } @cache;
		push(@stale_writes, 1) if (!$current ||
			refaddr($members) != refaddr($current->{'members'}));
		};
	local *main::clone_web_domain = sub { $check_write->($_[3]->{'members'}); };
	local *apache::save_directive = sub { $check_write->($_[2]); };
	local *apache::find_directive = sub { return (); };
	local *main::flush_file_lines = sub { };

	# Force the SSL relinking branch to make a nested web-lock acquisition,
	# just as save_website_ssl_file does through obtain_lock_ssl.
	local *main::check_domain_certificate = sub { return 0; };
	local *main::get_domain = sub { return $source; };
	local *main::break_ssl_linkage = sub {
		my ($d) = @_;
		&obtain_lock_web($d);
		my ($virt) = &get_apache_virtual($d->{'dom'}, $d->{'web_sslport'});
		$virt->{'members'}->[0]->{'value'} = 'all -SSLv3 -TLSv1 -TLSv1.1';
		delete($d->{'ssl_same'});
		$nested_updates++;
		&release_lock_web($d);
		};

	# Files, PHP pools and service restarts are covered by disposable-VM tests.
	local *main::get_template = sub { return {}; };
	local *main::get_domain_php_mode = sub { return 'none'; };
	local *main::link_apache_logs = sub { };
	local *main::find_html_cgi_dirs = sub { };
	local *main::need_php_wrappers = sub { return 0; };
	local *main::fix_php_ini_files = sub { };
	local *main::create_ssl_certificate_directories = sub { };
	local *main::list_ssl_file_types = sub { return (); };
	local *main::sync_combined_ssl_cert = sub { };
	local *main::apache_combined_cert = sub { return 1; };
	local *main::ssl_needs_apache_restart = sub { return 0; };
	local *main::register_post_action = sub { };

	$result = $feature eq 'web' ? &clone_web($target, $source)
				  : &clone_ssl($target, $source);
	is($result, $missing ? 0 : 1, 'returns the expected clone result');
	is_deeply(\@unlocked_reads, [], 'all vhost lookups occur while locked');
	is_deeply(\%locked, {}, 'no file locks remain after returning');
	is_deeply([ grep { $_ } values %main::got_lock_web_file ], [],
		'no counted web locks remain after returning');
	is_deeply(\@unlocked_writes, [], 'all Apache edits occur while locked');
	is_deeply(\@stale_writes, [], 'all Apache edits use the current parse');
	ok($writes, 'the successful clone edited Apache directives') if (!$missing);
	if (!$missing && $feature eq 'ssl') {
		is($nested_updates, 1, 'the invalid SSL link was repaired');
		is($flushes, 1, 'nested SSL updates preserve the outer parse');
		}
	}
}

# Both failed lookups must release their locks, including the main Apache lock.
foreach my $feature (qw(web ssl)) {
	foreach my $missing (qw(source target)) {
		subtest "$feature clone with missing $missing" => sub {
			&run_clone($feature, $missing);
			};
		}
	subtest "$feature clone keeps edits under its lock" => sub {
		&run_clone($feature, undef);
		};
	}

done_testing();
