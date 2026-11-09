#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Basename qw(dirname);
use File::Spec;
use File::Temp qw(tempdir);
use Cwd qw(abs_path);

my $root = abs_path(File::Spec->catdir(dirname(__FILE__), '..'));
my $script = File::Spec->catfile($root, 'list-mailbox.pl');
open(my $sfh, '<', $script) || die $!;
my $source = do { local $/; <$sfh> };
close($sfh);

my ($function) = $source =~
	/(^sub list_mailbox_file_owned\n\{.*?^\})/ms;
ok($function, 'mailbox ownership helper is present');
eval "package virtual_server; $function";
die $@ if ($@);

my $dir = tempdir(CLEANUP => 1);
my $mail = File::Spec->catfile($dir, 'mail');
open(my $mfh, '>', $mail) || die $!;
print {$mfh} "message\n";
close($mfh);
my $uid = (stat($mail))[4];

ok(virtual_server::list_mailbox_file_owned($mail, $uid),
	'mail user can read an owned mailbox file');
ok(!virtual_server::list_mailbox_file_owned($mail, $uid + 1),
	'foreign mailbox owner is rejected');
ok(!virtual_server::list_mailbox_file_owned("$dir/missing", $uid),
	'missing mailbox file is rejected');

my $link = File::Spec->catfile($dir, 'mail-link');
symlink($mail, $link) || die $!;
ok(!virtual_server::list_mailbox_file_owned($link, $uid + 1),
	'a link cannot hide a foreign target owner');

like($source,
	qr/!&master_admin\(\).*?list_mailbox_file_owned\(\$folder->\{'file'\},\s*\$user->\{'uid'\}\)/s,
	'non-master folder access checks the mail user owner');
like($source,
	qr/my \$f = \$m->\{'file'\} \|\| \$folder->\{'file'\};.*?list_mailbox_file_owned\(\$f, \$user->\{'uid'\}\)/s,
	'filename output checks each mail file owner');
like($source,
	qr/list_mailbox_file_owned\(\$m->\{'file'\} \|\| \$folder->\{'file'\},\s*\$user->\{'uid'\}\)/,
	'message output checks each mail file owner');

done_testing();
