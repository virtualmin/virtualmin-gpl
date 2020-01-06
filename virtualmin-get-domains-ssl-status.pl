#!/usr/bin/perl
# Extract expiry dates of all SSL certificates for virtual servers

use strict;
use warnings;

use POSIX;

eval "use Text::ASCIITable";
if ($@) {
    print
"Error: Perl module Text::ASCIITable is not installed.\nYou can install it by package name on\n  RHEL systems\n\    `perl-Text-ASCIITable\`\n  Debian systems\n    `libtext-asciitable-perl\`\nIf one of the above packages are not availabe on your\nsystem, you could install it using CPAN command:\n\   `cpan -i Text::ASCIITable\`\nExiting..\n";
    exit;
}
eval "use Time::Piece";
if ($@) {
    print
"Error: Perl module Time::Piece is not installed.\nYou can install it by package name on\n  RHEL systems\n\    `perl-Time-Piece\`\n  Debian systems\n    `libtime-piece-perl\`\nIf one of the above packages are not availabe on your\nsystem, you could install it using CPAN command:\n\   `cpan -i Time::Piece\`\nExiting..\n";
    exit;
}
my $out = `virtualmin list-certs --all-domains --cert`;
my (@data) = $out =~ /(.*):\n.*\n.*File:\s+(.*?)\n/g;

if (@data) {
    my $table   = Text::ASCIITable->new({ headingText => 'SSL CERTIFICATES EXPIRATION DATES' });
    my $fpm_in  = "%b  %d %H:%M:%S %Y";
    my $fpm_out = "%b %d, %Y";
    my $now     = Time::Piece->new();
    $table->setCols('DOMAIN NAME', 'PATH TO CERTIFICATE FILE', 'VALID UNTIL', 'EXPIRES IN', 'STATUS');
    my $i = 1;
    foreach my $d (@data) {
        if ($i % 2 == 1) {
            my $domain          = $d;
            my $cfile           = $data[$i];
            my $expiration_date = `openssl x509 -enddate -noout -in "$cfile"`;
            ($expiration_date) = $expiration_date =~ /notAfter=(.*)\sGMT/;
            my $valid_until    = Time::Piece->strptime($expiration_date, $fpm_in);
            my $status         = 'VALID';
            my $now_st         = $now->strftime("%s");
            my $valid_until_st = $valid_until->strftime("%s");

            if ($now_st > $valid_until_st) {
                $status = 'EXPIRED';
            }
            my $diff = int(($valid_until_st - $now_st) / (3600 * 24));
            if ($diff < 0) {
                $diff = '';
            } elsif ($diff > 365) {
                $diff = floor($diff / 365);
                if ($diff == 1) {
                    $diff .= " year";
                } else {
                    $diff .= " years";
                }
            } elsif ($diff > 100) {
                $diff = floor($diff / 30);
                $diff .= " months";
            } else {
                if ($diff == 1) {
                    $diff .= " day";
                } else {
                    $diff .= " days";
                }
            }
            $table->addRow($domain, $cfile, $valid_until->strftime($fpm_out), $diff, $status);
        }
        $i++;
    }
    $table->addRowLine();
    print $table;
} else {
    print "There are no virtual servers with valid SSL certificates found.\n";
}
