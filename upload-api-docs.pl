#!/usr/local/bin/perl
# Convert all Virtualmin API POD docs into Wiki format, and upload them to
# virtualmin.com.

$wiki_pages_host = "virtualmin.com";
$wiki_pages_user = "virtualmin";
$wiki_pages_dir = "/home/virtualmin/domains/jdev.virtualmin.com/public_html/components/com_openwiki/data/pages";

# Go to script's directory
if ($0 =~ /^(.*\/)[^\/]+$/) {
	chdir($1);
	}
chop($pwd = `pwd`);

# XXX find all API scripts

# XXX identify categories (domains, users, etc..)

# XXX convert to wiki format

# XXX extract command-line args summary

# XXX upload

# XXX create index pages and upload
