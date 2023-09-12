#!/usr/local/bin/perl
# Download the temp file created for a backup

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'backup_err'});
my $cbmode = &can_backup_domain();
$cbmode || &error($text{'backup_ecannot'});

my $origfile = $in{'file'};
$in{'file'} || &error($text{'backup_edownloadfile'});
&is_under_directory(&tempname_dir(), $in{'file'}) ||
	&error($text{'backup_edownloadfile6'});
-r $in{'file'} || &error($text{'backup_edownloadfile5'});
$in{'file'} =~ s/^\/.*\///g || &error($text{'backup_edownloadfile2'});
$in{'file'} =~ /\.\./ && &error($text{'backup_edownloadfile7'});
$in{'file'} =~ /\0/ && &error($text{'backup_edownloadfile7'});
$in{'file'} =~ /^(\S+):(\S+\.(zip|tar|tar\.[a-z0-9]+))$/ ||
	&error($text{'backup_edownloadfile3'});
$remote_user eq $1 || &error($text{'backup_edownloadfile4'});
my $tempfile = $2;

my @st = stat($origfile);
print "Content-type: application/octet-stream\n";
print "Content-Disposition: Attachment; filename=\"$tempfile\"\n";
print "Content-length: $st[7]\n";
print "\n";
&open_readfile(TEMP, $origfile);
&unlink_file($origfile);
my $bs = &get_buffer_size();
while(read(TEMP, $buf, $bs) > 0) {
	print $buf;
	}
close(TEMP);
