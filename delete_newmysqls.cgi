#!/usr/local/bin/perl
# Remove a MySQL clone module

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newmysqls_ecannot'});
&error_setup($text{'newmysqls_derr'});
&ReadParse();
my @d = split(/\0/, $in{'d'});
@d || &error($text{'newmysqls_enone'});

# Get the modules to remove
my @alldoms = grep { $_->{'mysql'} } &list_domains();
my %modmap = map { $_->{'minfo'}->{'dir'}, $_ } &list_remote_mysql_modules();
my @del;
foreach my $d (@d) {
	my $mm = $modmap{$d};
	$mm || &error($text{'newmysqls_egone'});
	$mm->{'minfo'}->{'dir'} eq 'mysql' &&
		&error($text{'newmysqls_edelete'});
	my @doms = grep { $_->{'mysql_module'} eq
		       $mm->{'minfo'}->{'dir'} } @alldoms;
	@doms == 0 || &error(&text('newmysqls_einuse', scalar(@doms)));
	push(@del, $mm);
	}

# Delete them
foreach my $mm (@del) {
	&delete_remote_mysql_module($mm);
	}

&webmin_log("delete", "newmysqls", scalar(@d));
&redirect("edit_newmysqls.cgi");
