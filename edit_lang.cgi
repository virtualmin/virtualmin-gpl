#!/usr/local/bin/perl
# Show a form for changing a user's language

require './virtual-server-lib.pl';
&ReadParse();
&can_change_language() || &error($text{'lang_ecannot'});
&foreign_require("acl");
my @users = &acl::list_users();
my ($user) = grep { $_->{'name'} eq $base_remote_user } @users;
$user || &error($text{'lang_euser'});

&ui_print_header(undef, $text{'lang_title'}, "");

print &ui_form_start("save_lang.cgi", "post");
print &ui_table_start($text{'lang_header'}, undef, 2);

# Find languages with Virtualmin translations
my @alllangs = &list_languages();
my @langs = grep { -e "$module_root_directory/lang/$_->{'lang'}" } @alllangs;

# Current language
my ($clang) = grep { $_->{'lang'} eq $current_lang } @alllangs;
print &ui_table_row($text{'lang_current'},
	$clang->{'desc'}." (".uc($clang->{'lang'}).")");

# Default language
my $deflang = $gconfig{"lang"} || $default_lang;
my ($dlang) = grep { $_->{'lang'} eq $deflang } @alllangs;
print &ui_table_row($text{'lang_default'},
	$dlang->{'desc'}." (".uc($dlang->{'lang'}).")");

# New language
print &ui_table_row($text{'lang_preferred'},
	&ui_select("lang", $user->{'lang'},
	    [ [ "", "&lt;$text{'lang_defsel'}&gt;" ],
	      map { [ $_->{'lang'},
		      $_->{'desc'}." (".uc($_->{'lang'}).")" ] } @langs ],
	    1, 0, 1));

print &ui_table_end();
print &ui_form_end([ [ undef, $text{'lang_ok'} ] ]);

&ui_print_footer("", $text{'index_return'});

