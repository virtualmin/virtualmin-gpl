#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use FindBin;

do "$FindBin::Bin/../proftpd-lib.pl"
	or die "Failed to load proftpd-lib.pl: $@ $!";

# Coverage must depend on the configured pattern, not existing files. Include
# directory boundaries and shell character classes to catch false matches.
my $log = '/var/log/proftpd/sftp.log';
foreach my $test (
	[ $log, 1 ],
	[ '/var/log/proftpd/tls.log', 0 ],
	[ '/var/log/proftpd/*.log', 1 ],
	[ '/var/log/*/*.log', 1 ],
	[ '/var/log/*.log', 0 ],
	[ '/var/log/proftpd/sft?.log', 1 ],
	[ '/var/log/proftpd/????.log', 1 ],
	[ '/var/log/proftpd/???.log', 0 ],
	[ '/var/log/proftpd/[st]*.log', 1 ],
	[ '/var/log/proftpd/[!t]*.log', 1 ],
	[ '/var/log/proftpd/[!s]*.log', 0 ],
	[ '/var/log/proftpd/[a-z]*.log', 1 ],
	[ '/var/log/proftpd/[[:alpha:]]*.log', 1 ],
	[ '/var/log/proftpd/[[:digit:]]*.log', 0 ],
	[ '/var/log/proftpd/\\*.log', 0 ],
	[ '/var/log/proftpd/sftp?log', 1 ],
	[ '/var/log/proftpd/sftp.log.*', 0 ],
	[ '/var/log/proftpd[!x]sftp.log', 0 ],
	[ '/var/log/proftpd/[sftp.log', 0 ],
	) {
	is(proftpd_log_matches($log, $test->[0]), $test->[1], $test->[0]);
	}

ok(proftpd_log_matches('/var/log/proftpd/tls.log', '/var/log/proftpd/*.log'),
	'the package wildcard also covers TLS logs');
ok(!proftpd_log_matches('/var/log/proftpd/sftpXlog', $log),
	'literal dots do not match arbitrary characters');

done_testing();
