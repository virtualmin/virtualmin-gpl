

create sequence nuke_access_id_seq;

CREATE TABLE nuke_access (
  access_id int primary key default nextval('nuke_access_id_seq'),
  access_title varchar(20) default NULL
) ;


INSERT INTO nuke_access VALUES (-1,'Deleted');
INSERT INTO nuke_access VALUES (1,'User');
INSERT INTO nuke_access VALUES (2,'Moderator');
INSERT INTO nuke_access VALUES (3,'Super Moderator');
INSERT INTO nuke_access VALUES (4,'Administrator');


CREATE TABLE nuke_authors (
  aid varchar(25) NOT NULL primary key default '',
  name varchar(50) default NULL,
  url varchar(255) NOT NULL default '',
  email varchar(255) NOT NULL default '',
  pwd varchar(40) default NULL,
  counter numeric(11) NOT NULL default '0',
  radminarticle numeric(2) NOT NULL default '0',
  radmintopic numeric(2) NOT NULL default '0',
  radminuser numeric(2) NOT NULL default '0',
  radminsurvey numeric(2) NOT NULL default '0',
  radminsection numeric(2) NOT NULL default '0',
  radminlink numeric(2) NOT NULL default '0',
  radminephem numeric(2) NOT NULL default '0',
  radminfaq numeric(2) NOT NULL default '0',
  radmindownload numeric(2) NOT NULL default '0',
  radminreviews numeric(2) NOT NULL default '0',
  radminnewsletter numeric(2) NOT NULL default '0',
  radminforum numeric(2) NOT NULL default '0',
  radmincontent numeric(2) NOT NULL default '0',
  radminency numeric(2) NOT NULL default '0',
  radminsuper numeric(2) NOT NULL default '1',
  admlanguage varchar(30) NOT NULL default ''
) ;


create sequence nuke_autonews_anid_seq;

CREATE TABLE nuke_autonews (
  anid numeric(11) NOT NULL primary key default nextval('nuke_autonews_anid_seq'),
  catid numeric(11) NOT NULL default '0',
  aid varchar(30) NOT NULL default '',
  title varchar(80) NOT NULL default '',
  time varchar(19) NOT NULL default '',
  hometext text NOT NULL,
  bodytext text NOT NULL,
  topic numeric(3) NOT NULL default '1',
  informant varchar(20) NOT NULL default '',
  notes text NOT NULL,
  ihome numeric(1) NOT NULL default '0',
  alanguage varchar(30) NOT NULL default '',
  acomm numeric(1) NOT NULL default '0'
) ;


create sequence nuke_banlist_ban_id_seq;

CREATE TABLE nuke_banlist (
  ban_id numeric(10) NOT NULL primary key default 
		nextval('nuke_banlist_ban_id_seq'),
  ban_userid numeric(10) default NULL,
  ban_ip varchar(16) default NULL,
  ban_start numeric(32) default NULL,
  ban_end numeric(50) default NULL,
  ban_time_type numeric(10) default NULL
) ;


create sequence nuke_banner_bid_seq;

CREATE TABLE nuke_banner (
  bid varchar(11) NOT NULL primary key default nextval('nuke_banner_bid_seq'),
  cid numeric(11) NOT NULL default '0',
  imptotal numeric(11) NOT NULL default '0',
  impmade numeric(11) NOT NULL default '0',
  clicks numeric(11) NOT NULL default '0',
  imageurl varchar(100) NOT NULL default '',
  clickurl varchar(200) NOT NULL default '',
  alttext varchar(255) NOT NULL default '',
  date timestamp ,
  dateend timestamp ,
  type numeric(1) NOT NULL default '0',
  active numeric(1) NOT NULL default '1'
) ;
create index nuke_banner_cid on nuke_banner (cid);

create sequence nuke_banner_client_cid_seq;

CREATE TABLE nuke_bannerclient (
  cid numeric(11) NOT NULL primary key 
     default nextval('nuke_banner_client_cid_seq'),
  name varchar(60) NOT NULL default '',
  contact varchar(60) NOT NULL default '',
  email varchar(60) NOT NULL default '',
  login varchar(10) NOT NULL default '',
  passwd varchar(10) NOT NULL default '',
  extrainfo text NOT NULL
) ;


create sequence nuke_bbtopics_id_seq;

CREATE TABLE nuke_bbtopics (
  topic_id numeric(10) NOT NULL primary key default nextval('nuke_bbtopics_id_seq'),
  topic_title varchar(100) default NULL,
  topic_poster numeric(10) default NULL,
  topic_time varchar(20) default NULL,
  topic_views numeric(10) NOT NULL default '0',
  topic_replies numeric(10) NOT NULL default '0',
  topic_last_post_id numeric(10) NOT NULL default '0',
  forum_id numeric(10) NOT NULL default '0',
  topic_status numeric(10) NOT NULL default '0',
  topic_notify numeric(2) default '0'
) ;

create index nuke_bbtopics_last_post_id on nuke_bbtopics (topic_last_post_id);
create index nuke_bbtopics_forum_id on nuke_bbtopics (forum_id);


create sequence nuke_blocks_bid_seq;

CREATE TABLE nuke_blocks (
  bid numeric(10) NOT NULL primary key default nextval('nuke_blocks_bid_seq'),
  bkey varchar(15) NOT NULL default '',
  title varchar(60) NOT NULL default '',
  content text NOT NULL,
  url varchar(200) NOT NULL default '',
  position char(1) NOT NULL default '',
  weight numeric(10) NOT NULL default '1',
  active numeric(1) NOT NULL default '1',
  refresh numeric(10) NOT NULL default '0',
  time varchar(14) NOT NULL default '0',
  blanguage varchar(30) NOT NULL default '',
  blockfile varchar(255) NOT NULL default '',
  view numeric(1) NOT NULL default '0'
) ;

create index nuke_blocks_title on nuke_blocks (title);


INSERT INTO nuke_blocks VALUES (1,'','Modules','','','l',1,1,0,'','','block-Modules.php',0);
INSERT INTO nuke_blocks VALUES (2,'admin','Administration','<strong><big>·</big></strong> <a href=\"admin.php\">Administration</a><br>\r\n<strong><big>·</big></strong> <a href=\"admin.php?op=adminStory\">NEW Story</a><br>\r\n<strong><big>·</big></strong> <a href=\"admin.php?op=create\">Change Survey</a><br>\r\n<strong><big>·</big></strong> <a href=\"admin.php?op=content\">Content</a><br>\r\n<strong><big>·</big></strong> <a href=\"admin.php?op=logout\">Logout</a>','','l',2,1,0,'985591188','','',2);
INSERT INTO nuke_blocks VALUES (3,'','Who\'s Online','','','l',3,1,0,'','','block-Who_is_Online.php',0);
INSERT INTO nuke_blocks VALUES (4,'','Search','','','l',4,0,3600,'','','block-Search.php',0);
INSERT INTO nuke_blocks VALUES (5,'','Languages','','','l',5,1,3600,'','','block-Languages.php',0);
INSERT INTO nuke_blocks VALUES (6,'','Random Headlines','','','l',6,0,3600,'','','block-Random_Headlines.php',0);
INSERT INTO nuke_blocks VALUES (7,'','Amazon','','','l',7,1,3600,'','','block-Amazon.php',0);
INSERT INTO nuke_blocks VALUES (8,'userbox','User\'s Custom Box','','','r',1,1,0,'','','',1);
INSERT INTO nuke_blocks VALUES (9,'','Categories Menu','','','r',2,0,0,'','','block-Categories.php',0);
INSERT INTO nuke_blocks VALUES (10,'','Survey','','','r',3,1,3600,'','','block-Survey.php',0);
INSERT INTO nuke_blocks VALUES (11,'','Login','','','r',4,1,3600,'','','block-Login.php',3);
INSERT INTO nuke_blocks VALUES (12,'','Big Story of Today','','','r',5,1,3600,'','','block-Big_Story_of_Today.php',0);
INSERT INTO nuke_blocks VALUES (13,'','Old Articles','','','r',6,1,3600,'','','block-Old_Articles.php',0);
INSERT INTO nuke_blocks VALUES (14,'','Information','<br><center><font class=\"content\">\r\n<a href=\"http://phpnuke.org\"><img src=\"images/powered/phpnuke.gif\" border=\"0\" alt=\"Powered by PHP-Nuke\" title=\"Powered by PHP-Nuke\" width=\"88\" height=\"31\"></a>\r\n<br><br>\r\n<a href=\"http://validator.w3.org/check/referer\"><img src=\"images/html401.gif\" width=\"88\" height=\"31\" alt=\"Valid HTML 4.01!\" title=\"Valid HTML 4.01!\" border=\"0\"></a>\r\n<br><br>\r\n<a href=\"http://jigsaw.w3.org/css-validator\"><img src=\"images/css.gif\" width=\"88\" height=\"31\" alt=\"Valid CSS!\" title=\"Valid CSS!\" border=\"0\"></a></font></center><br>','','r',7,1,0,'','','',0);

create sequence nuke_categories_id_seq;

CREATE TABLE nuke_catagories (
  cat_id numeric(10) NOT NULL primary key default nextval('nuke_categories_id_seq'),
  cat_title varchar(100) default NULL,
  cat_order varchar(10) default NULL
) ;


create sequence nuke_comments_tid_seq;

CREATE TABLE nuke_comments (
  tid numeric(11) NOT NULL primary key default nextval('nuke_comments_tid_seq'),
  pid numeric(11) default '0',
  sid numeric(11) default '0',
  date timestamp ,
  name varchar(60) NOT NULL default '',
  email varchar(60) default NULL,
  url varchar(60) default NULL,
  host_name varchar(60) default NULL,
  subject varchar(85) NOT NULL default '',
  comment text NOT NULL,
  score numeric(4) NOT NULL default '0',
  reason numeric(4) NOT NULL default '0'
) ;

create index nuke_comments_pid on nuke_comments (pid);
create index nuke_comments_sid on nuke_comments (sid);


CREATE TABLE nuke_config (
  sitename varchar(255) NOT NULL default '',
  nukeurl varchar(255) NOT NULL default '',
  site_logo varchar(255) NOT NULL default '',
  slogan varchar(255) NOT NULL default '',
  startdate varchar(50) NOT NULL default '',
  adminmail varchar(255) NOT NULL default '',
  anonpost numeric(1) NOT NULL default '0',
  Default_Theme varchar(255) NOT NULL default '',
  foot1 text NOT NULL,
  foot2 text NOT NULL,
  foot3 text NOT NULL,
  commentlimit numeric(9) NOT NULL default '4096',
  anonymous varchar(255) NOT NULL default '',
  minpass numeric(1) NOT NULL default '5',
  pollcomm numeric(1) NOT NULL default '1',
  articlecomm numeric(1) NOT NULL default '1',
  broadcast_msg numeric(1) NOT NULL default '1',
  my_headlines numeric(1) NOT NULL default '1',
  top numeric(3) NOT NULL default '10',
  storyhome numeric(2) NOT NULL default '10',
  user_news numeric(1) NOT NULL default '1',
  oldnum numeric(2) NOT NULL default '30',
  ultramode numeric(1) NOT NULL default '0',
  banners numeric(1) NOT NULL default '1',
  backend_title varchar(255) NOT NULL default '',
  backend_language varchar(10) NOT NULL default '',
  language varchar(100) NOT NULL default '',
  locale varchar(10) NOT NULL default '',
  multilingual numeric(1) NOT NULL default '0',
  useflags numeric(1) NOT NULL default '0',
  notify numeric(1) NOT NULL default '0',
  notify_email varchar(255) NOT NULL default '',
  notify_subject varchar(255) NOT NULL default '',
  notify_message varchar(255) NOT NULL default '',
  notify_from varchar(255) NOT NULL default '',
  footermsgtxt text NOT NULL,
  email_send numeric(1) NOT NULL default '1',
  attachmentdir varchar(255) NOT NULL default '',
  attachments numeric(1) NOT NULL default '0',
  attachments_view numeric(1) NOT NULL default '0',
  download_dir varchar(255) NOT NULL default '',
  defaultpopserver varchar(255) NOT NULL default '',
  singleaccount numeric(1) NOT NULL default '-9',
  singleaccountname varchar(255) NOT NULL default '',
  numaccounts numeric(2) NOT NULL default '-1',
  imgpath varchar(255) NOT NULL default '',
  filter_forward numeric(1) NOT NULL default '1',
  moderate numeric(1) NOT NULL default '0',
  admingraphic numeric(1) NOT NULL default '1',
  httpref numeric(1) NOT NULL default '1',
  httprefmax numeric(5) NOT NULL default '1000',
  CensorMode numeric(1) NOT NULL default '3',
  CensorReplace varchar(10) NOT NULL default '',
  copyright text NOT NULL,
  Version_Num varchar(10) NOT NULL default ''
) ;


INSERT INTO nuke_config VALUES ('PHP-Nuke Powered Site','http://yoursite.com','logo.gif','Your slogan here','September 2002','webmaster@yoursite.com',0,'DeepBlue','<a href=\'http://phpnuke.org\' target=\'blank\'><img src=\'images/powered/nuke.gif\' border=\'0\' Alt=\'Web site powered by PHP-Nuke\' hspace=\'10\'></a><br>','All logos and trademarks in this site are property of their respective owner. The comments are property of their posters, all the rest © 2002 by me','You can syndicate our news using the file <a href=\'backend.php\'><font class=\'footmsg_l\'>backend.php</font></a> or <a href=\'ultramode.txt\'><font class=\'footmsg_l\'>ultramode.txt</font></a>',4096,'Anonymous',5,1,1,1,1,10,10,1,30,0,1,'PHP-Nuke Powered Site','en-us','english','en_US',0,0,0,'me@yoursite.com','NEWS for my site','Hey! You got a new submission for your site.','webmaster','Mail sent from WebMail service at PHP-Nuke Powered Site\r\n- http://yoursite.com',1,'/var/www/html/modules/WebMail/tmp/',0,0,'modules/WebMail/attachments/','','0','Your account',-1,'modules/WebMail/images',1,0,1,1,1000,3,'*****','Web site engine\'s code is Copyright &copy; 2002 by <a href=\"http://phpnuke.org\"><font class=\'footmsg_l\'>PHP-Nuke</font></a>. All Rights Reserved. PHP-Nuke is Free Software released under the <a href=\"http://www.gnu.org\"><font class=\'footmsg_l\'>GNU/GPL license</font></a>.','6.0');

create sequence  nuke_contactbook_id_s;

CREATE TABLE nuke_contactbook (
  uid numeric(11) default NULL,
  contactid numeric(11) NOT NULL primary key 
    default nextval('nuke_contactbook_id_s'),
  firstname varchar(50) default NULL,
  lastname varchar(50) default NULL,
  email varchar(255) default NULL,
  company varchar(255) default NULL,
  homeaddress varchar(255) default NULL,
  city varchar(80) default NULL,
  homephone varchar(255) default NULL,
  workphone varchar(255) default NULL,
  homepage varchar(255) default NULL,
  IM varchar(255) default NULL,
  events text,
  reminders numeric(11) default NULL,
  notes text
) ;

create index nuke_contactbook_uid on nuke_contactbook (uid);



CREATE TABLE nuke_counter (
  type varchar(80) NOT NULL default '',
  var varchar(80) NOT NULL default '',
  count numeric(10) NOT NULL default '0'
) ;


INSERT INTO nuke_counter VALUES ('total','hits',1);
INSERT INTO nuke_counter VALUES ('browser','WebTV',0);
INSERT INTO nuke_counter VALUES ('browser','Lynx',0);
INSERT INTO nuke_counter VALUES ('browser','MSIE',0);
INSERT INTO nuke_counter VALUES ('browser','Opera',0);
INSERT INTO nuke_counter VALUES ('browser','Konqueror',0);
INSERT INTO nuke_counter VALUES ('browser','Netscape',1);
INSERT INTO nuke_counter VALUES ('browser','Bot',0);
INSERT INTO nuke_counter VALUES ('browser','Other',0);
INSERT INTO nuke_counter VALUES ('os','Windows',0);
INSERT INTO nuke_counter VALUES ('os','Linux',1);
INSERT INTO nuke_counter VALUES ('os','Mac',0);
INSERT INTO nuke_counter VALUES ('os','FreeBSD',0);
INSERT INTO nuke_counter VALUES ('os','SunOS',0);
INSERT INTO nuke_counter VALUES ('os','IRIX',0);
INSERT INTO nuke_counter VALUES ('os','BeOS',0);
INSERT INTO nuke_counter VALUES ('os','OS/2',0);
INSERT INTO nuke_counter VALUES ('os','AIX',0);
INSERT INTO nuke_counter VALUES ('os','Other',0);

create sequence nuke_disallow_id_seq;

CREATE TABLE nuke_disallow (
  disallow_id numeric(10) NOT NULL primary key 
    default nextval('nuke_disallow_id_seq'),
  disallow_username varchar(50) 
) ;


create sequence nuke_downloads_categories_cid_s;


CREATE TABLE nuke_downloads_categories (
  cid numeric(11) NOT NULL primary key
    default nextval('nuke_downloads_categories_cid_s'),
  title varchar(50) NOT NULL default '',
  cdescription text NOT NULL,
  parentid numeric(11) NOT NULL default '0'
) ;

create index nuke_downloads_categories_title on 
nuke_downloads_categories (title);

create sequence nuke_downloads_downloads_id_seq;

CREATE TABLE nuke_downloads_downloads (
  lid numeric(11) NOT NULL primary key 
    default nextval('nuke_downloads_downloads_id_seq'),
  cid numeric(11) NOT NULL default '0',
  sid numeric(11) NOT NULL default '0',
  title varchar(100) NOT NULL default '',
  url varchar(100) NOT NULL default '',
  description text NOT NULL,
  date timestamp ,
  name varchar(100) NOT NULL default '',
  email varchar(100) NOT NULL default '',
  hits numeric(11) NOT NULL default '0',
  submitter varchar(60) NOT NULL default '',
  downloadratingsummary numeric(6,4) NOT NULL default '0.0000',
  totalvotes numeric(11) NOT NULL default '0',
  totalcomments numeric(11) NOT NULL default '0',
  filesize numeric(11) NOT NULL default '0',
  version varchar(10) NOT NULL default '',
  homepage varchar(200) NOT NULL default ''
) ;

create index nuke_downloads_downloads_cid on 
  nuke_downloads_downloads (cid);

create index nuke_downloads_downloads_sid on 
  nuke_downloads_downloads (sid);

create index nuke_downloads_downloads_title on 
  nuke_downloads_downloads (title);

CREATE TABLE nuke_downloads_editorials (
  downloadid numeric(11) NOT NULL primary key default '0',
  adminid varchar(60) NOT NULL default '',
  editorialtimestamp timestamp NOT NULL default '1903-01-01 00:00:00.00',
  editorialtext text NOT NULL,
  editorialtitle varchar(100) NOT NULL default ''
) ;


create sequence nuke_downloads_modrequest_id_s;

CREATE TABLE nuke_downloads_modrequest (
  requestid numeric(11) NOT NULL primary key 
   default nextval('nuke_downloads_modrequest_id_s'),
  lid numeric(11) NOT NULL default '0',
  cid numeric(11) NOT NULL default '0',
  sid numeric(11) NOT NULL default '0',
  title varchar(100) NOT NULL default '',
  url varchar(100) NOT NULL default '',
  description text NOT NULL,
  modifysubmitter varchar(60) NOT NULL default '',
  brokendownload numeric(3) NOT NULL default '0',
  name varchar(100) NOT NULL default '',
  email varchar(100) NOT NULL default '',
  filesize numeric(11) NOT NULL default '0',
  version varchar(10) NOT NULL default '',
  homepage varchar(200) NOT NULL default ''
) ;


create sequence nuke_downloads_newdownload_ld_s;

CREATE TABLE nuke_downloads_newdownload (
  lid numeric(11) NOT NULL default 
    nextval('nuke_downloads_newdownload_ld_s'),
  cid numeric(11) NOT NULL default '0',
  sid numeric(11) NOT NULL default '0',
  title varchar(100) NOT NULL default '',
  url varchar(100) NOT NULL default '',
  description text NOT NULL,
  name varchar(100) NOT NULL default '',
  email varchar(100) NOT NULL default '',
  submitter varchar(60) NOT NULL default '',
  filesize numeric(11) NOT NULL default '0',
  version varchar(10) NOT NULL default '',
  homepage varchar(200) NOT NULL default ''
) ;

create index nuke_downloads_newdownload_cid on nuke_downloads_newdownload (cid);
create index nuke_downloads_newdownload_sid on nuke_downloads_newdownload (sid);
create index nuke_downloads_newdownload_title on 
  nuke_downloads_newdownload (title);

create sequence nuke_downloads_votedata_id_seq;

CREATE TABLE nuke_downloads_votedata (
  ratingdbid numeric(11) NOT NULL primary key default nextval('nuke_downloads_votedata_id_seq'),
  ratinglid numeric(11) NOT NULL default '0',
  ratinguser varchar(60) NOT NULL default '',
  rating numeric(11) NOT NULL default '0',
  ratinghostname varchar(60) NOT NULL default '',
  ratingcomments text NOT NULL,
  ratingtimestamp timestamp NOT NULL default '1903-01-01 00:00:00.00'
) ;


create sequence  nuke_encyclopedia_eid_seq;

CREATE TABLE nuke_encyclopedia (
  eid numeric(10) NOT NULL primary key default nextval('nuke_encyclopedia_eid_seq'),
  title varchar(255) NOT NULL default '',
  description text NOT NULL,
  elanguage varchar(30) NOT NULL default '',
  active numeric(1) NOT NULL default '0'
) ;


create sequence nuke_encyclopedia_text_tid_seq;

CREATE TABLE nuke_encyclopedia_text (
  tid numeric(10) NOT NULL primary key 
    default nextval('nuke_encyclopedia_text_tid_seq'),
  eid numeric(10) NOT NULL default '0',
  title varchar(255) NOT NULL default '',
  text text NOT NULL,
  counter numeric(10) NOT NULL default '0'
) ;

create index  nuke_encyclopedia_text_eid on  nuke_encyclopedia_text (eid);
create index  nuke_encyclopedia_text_title on  nuke_encyclopedia_text (title);


create sequence nuke_ephem_eid_seq;

CREATE TABLE nuke_ephem (
  eid numeric(11) NOT NULL primary key default nextval('nuke_ephem_eid_seq'),
  did numeric(2) NOT NULL default '0',
  mid numeric(2) NOT NULL default '0',
  yid numeric(4) NOT NULL default '0',
  content text NOT NULL,
  elanguage varchar(30) NOT NULL default ''
) ;


create sequence  nuke_faqAnswer_id_seq;

CREATE TABLE nuke_faqAnswer (
  id numeric(4) NOT NULL primary key default nextval('nuke_faqAnswer_id_seq'),
  id_cat numeric(4) default NULL,
  question varchar(255) default NULL,
  answer text
) ;

create index nuke_faqAnswer_id_cat on nuke_faqAnswer (id_cat);

create sequence  nuke_faqCategories_id_seq;

CREATE TABLE nuke_faqCategories (
  id_cat numeric(3) NOT NULL primary key default nextval('nuke_faqCategories_id_seq'),
  categories varchar(255) default NULL,
  flanguage varchar(30) NOT NULL default ''
) ;




CREATE TABLE nuke_forum_access (
  forum_id numeric(10) NOT NULL default '0',
  user_id numeric(10) NOT NULL default '0',
  can_post numeric(1) NOT NULL default '0'
);

create unique index nuke_forum_access_forum_usr on nuke_forum_access
(forum_id, user_id);



CREATE TABLE nuke_forum_config (
  allow_html numeric(2) default NULL,
  allow_bbcode numeric(2) default NULL,
  allow_sig numeric(2) default NULL,
  posts_per_page numeric(10) default NULL,
  hot_threshold numeric(10) default NULL,
  topics_per_page numeric(10) default NULL,
  index_head text,
  index_foot text,
  max_upfile numeric(6) NOT NULL default '300'
) ;


INSERT INTO nuke_forum_config VALUES (1,1,1,10,10,20,NULL,NULL,300);



CREATE TABLE nuke_forum_mods (
  forum_id numeric(10) NOT NULL default '0',
  user_id numeric(10) NOT NULL default '0'
) ;

create index  nuke_forum_mods_forum_id on nuke_forum_mods (forum_id);
create index  nuke_forum_mods_user_id on nuke_forum_mods (user_id);

create sequence nuke_forum_id_seq;

CREATE TABLE nuke_forums (
  forum_id numeric(10) NOT NULL primary key default nextval('nuke_forum_id_seq'),
  forum_name varchar(150) default NULL,
  forum_desc text,
  forum_access numeric(10) default '1',
  forum_moderator numeric(10) default NULL,
  cat_id numeric(10) default NULL,
  forum_type numeric(10) default '0',
  forum_pass varchar(60) default NULL,
  forum_notify_email varchar(30) default NULL,
  forum_atch numeric(2) NOT NULL default '0'
) ;

create index nuke_forums_form_id on nuke_forums (forum_id);
create index nuke_forums_form_name on nuke_forums (forum_name);

create sequence nuke_forumotopics_id_seq;

CREATE TABLE nuke_forumtopics (
  topic_id numeric(10) NOT NULL primary key default nextval('nuke_forumotopics_id_seq'),
  topic_title varchar(100) default NULL,
  topic_poster numeric(10) default NULL,
  topic_time varchar(20) default NULL,
  topic_views numeric(10) NOT NULL default '0',
  forum_id numeric(10) default NULL,
  topic_status numeric(10) NOT NULL default '0',
  topic_notify numeric(2) default '0'
) ;


create sequence nuke_headlines_hid_seq;

CREATE TABLE nuke_headlines (
  hid numeric(11) NOT NULL primary key 
     default nextval('sequence nuke_headlines_hid_seq'),
  sitename varchar(30) NOT NULL default '',
  headlinesurl varchar(200) NOT NULL default ''
) ;


INSERT INTO nuke_headlines VALUES (1,'PHP-Nuke','http://phpnuke.org/backend.php');
INSERT INTO nuke_headlines VALUES (2,'ODISEA','http://odisea.org/backend.php');
INSERT INTO nuke_headlines VALUES (3,'LinuxCentral','http://linuxcentral.com/backend/lcnew.rdf');
INSERT INTO nuke_headlines VALUES (4,'NewsForge','http://www.newsforge.com/newsforge.rdf');
INSERT INTO nuke_headlines VALUES (5,'PHPBuilder','http://phpbuilder.com/rss_feed.php');
INSERT INTO nuke_headlines VALUES (6,'PHP-Nuke Español','http://phpnuke-espanol.org/backend.php');
INSERT INTO nuke_headlines VALUES (7,'Freshmeat','http://freshmeat.net/backend/fm.rdf');
INSERT INTO nuke_headlines VALUES (8,'AppWatch','http://static.appwatch.com/appwatch.rdf');
INSERT INTO nuke_headlines VALUES (9,'LinuxWeelyNews','http://lwn.net/headlines/rss');
INSERT INTO nuke_headlines VALUES (10,'HappyPenguin','http://happypenguin.org/html/news.rdf');
INSERT INTO nuke_headlines VALUES (11,'Segfault','http://segfault.org/stories.xml');
INSERT INTO nuke_headlines VALUES (13,'KDE','http://www.kde.org/news/kdenews.rdf');
INSERT INTO nuke_headlines VALUES (14,'Perl.com','http://www.perl.com/pace/perlnews.rdf');
INSERT INTO nuke_headlines VALUES (15,'Themes.org','http://www.themes.org/news.rdf.phtml');
INSERT INTO nuke_headlines VALUES (16,'BrunchingShuttlecocks','http://www.brunching.com/brunching.rdf');
INSERT INTO nuke_headlines VALUES (17,'MozillaNewsBot','http://www.mozilla.org/newsbot/newsbot.rdf');
INSERT INTO nuke_headlines VALUES (18,'NewsTrolls','http://newstrolls.com/newstrolls.rdf');
INSERT INTO nuke_headlines VALUES (19,'FreakTech','http://sunsite.auc.dk/FreakTech/FreakTech.rdf');
INSERT INTO nuke_headlines VALUES (20,'AbsoluteGames','http://files.gameaholic.com/agfa.rdf');
INSERT INTO nuke_headlines VALUES (21,'SciFi-News','http://www.technopagan.org/sf-news/rdf.php');
INSERT INTO nuke_headlines VALUES (22,'SisterMachineGun','http://www.smg.org/index/mynetscape.html');
INSERT INTO nuke_headlines VALUES (23,'LinuxM68k','http://www.linux-m68k.org/linux-m68k.rdf');
INSERT INTO nuke_headlines VALUES (24,'Protest.net','http://www.protest.net/netcenter_rdf.cgi');
INSERT INTO nuke_headlines VALUES (25,'HollywoodBitchslap','http://hollywoodbitchslap.com/hbs.rdf');
INSERT INTO nuke_headlines VALUES (26,'DrDobbsTechNetCast','http://www.technetcast.com/tnc_headlines.rdf');
INSERT INTO nuke_headlines VALUES (27,'RivaExtreme','http://rivaextreme.com/ssi/rivaextreme.rdf.cdf');
INSERT INTO nuke_headlines VALUES (28,'Linuxpower','http://linuxpower.org/linuxpower.rdf');
INSERT INTO nuke_headlines VALUES (29,'PBSOnline','http://cgi.pbs.org/cgi-registry/featuresrdf.pl');
INSERT INTO nuke_headlines VALUES (30,'Listology','http://listology.com/recent.rdf');
INSERT INTO nuke_headlines VALUES (31,'Linuxdev.net','http://linuxdev.net/archive/news.cdf');
INSERT INTO nuke_headlines VALUES (32,'LinuxNewbie','http://www.linuxnewbie.org/news.cdf');
INSERT INTO nuke_headlines VALUES (33,'exoScience','http://www.exosci.com/exosci.rdf');
INSERT INTO nuke_headlines VALUES (34,'Technocrat','http://technocrat.net/rdf');
INSERT INTO nuke_headlines VALUES (35,'PDABuzz','http://www.pdabuzz.com/netscape.txt');
INSERT INTO nuke_headlines VALUES (36,'MicroUnices','http://mu.current.nu/mu.rdf');
INSERT INTO nuke_headlines VALUES (37,'TheNextLevel','http://www.the-nextlevel.com/rdf/tnl.rdf');
INSERT INTO nuke_headlines VALUES (38,'Gnotices','http://news.gnome.org/gnome-news/rdf');
INSERT INTO nuke_headlines VALUES (39,'DailyDaemonNews','http://daily.daemonnews.org/ddn.rdf.php3');
INSERT INTO nuke_headlines VALUES (40,'PerlMonks','http://www.perlmonks.org/headlines.rdf');
INSERT INTO nuke_headlines VALUES (41,'PerlNews','http://news.perl.org/perl-news-short.rdf');
INSERT INTO nuke_headlines VALUES (42,'BSDToday','http://www.bsdtoday.com/backend/bt.rdf');
INSERT INTO nuke_headlines VALUES (43,'DotKDE','http://dot.kde.org/rdf');
INSERT INTO nuke_headlines VALUES (44,'GeekNik','http://www.geeknik.net/backend/weblog.rdf');
INSERT INTO nuke_headlines VALUES (45,'HotWired','http://www.hotwired.com/webmonkey/meta/headlines.rdf');
INSERT INTO nuke_headlines VALUES (46,'JustLinux','http://www.justlinux.com/backend/features.rdf');
INSERT INTO nuke_headlines VALUES (47,'LAN-Systems','http://www.lansystems.com/backend/gazette_news_backend.rdf');
INSERT INTO nuke_headlines VALUES (48,'DigitalTheatre','http://www.dtheatre.com/backend.php3?xml=yes');
INSERT INTO nuke_headlines VALUES (49,'Linux.nu','http://www.linux.nu/backend/lnu.rdf');
INSERT INTO nuke_headlines VALUES (50,'Lin-x-pert','http://www.lin-x-pert.com/linxpert_apps.rdf');
INSERT INTO nuke_headlines VALUES (51,'MaximumBSD1','http://www.maximumbsd.com/backend/weblog.rdf1');
INSERT INTO nuke_headlines VALUES (52,'SolarisCentral','http://www.SolarisCentral.org/news/SolarisCentral.rdf');
INSERT INTO nuke_headlines VALUES (53,'Slashdot','http://slashdot.org/slashdot.rdf');
INSERT INTO nuke_headlines VALUES (54,'Linux.com','http://linux.com/linuxcom.rss');
INSERT INTO nuke_headlines VALUES (55,'WebReference','http://webreference.com/webreference.rdf');
INSERT INTO nuke_headlines VALUES (56,'FreeDOS','http://www.freedos.org/channels/rss.cgi');

create sequence nuke_journal_jid_seq;

CREATE TABLE nuke_journal (
  jid numeric(11) NOT NULL primary key default 
    nextval('sequencenuke_journal_jid_seq'),
  aid varchar(30) NOT NULL default '',
  title varchar(80) default NULL,
  bodytext text NOT NULL,
  mood varchar(48) NOT NULL default '',
  pdate varchar(48) NOT NULL default '',
  ptime varchar(48) NOT NULL default '',
  status varchar(48) NOT NULL default '',
  mtime varchar(48) NOT NULL default '',
  mdate varchar(48) NOT NULL default ''
) ;

create index nuke_journal_aid on nuke_journal (aid);

create sequence nuke_journal_comments_cid_seq;

CREATE TABLE nuke_journal_comments (
  cid numeric(11) NOT NULL primary key 
    default nextval('nuke_journal_comments_cid_seq'),
  rid varchar(48) NOT NULL default '',
  aid varchar(30) NOT NULL default '',
  comment text NOT NULL,
  pdate varchar(48) NOT NULL default '',
  ptime varchar(48) NOT NULL default ''
) ;

create index nuke_journal_comments_rid on nuke_journal_comments (rid);
create index nuke_journal_comments_aid on nuke_journal_comments (aid);


create sequence nuke_journal_stats_id_seq;

CREATE TABLE nuke_journal_stats (
  id numeric(11) NOT NULL primary key default nextval('nuke_journal_stats_id_seq'),
  joid varchar(48) NOT NULL default '',
  nop varchar(48) NOT NULL default '',
  ldp varchar(24) NOT NULL default '',
  ltp varchar(24) NOT NULL default '',
  micro varchar(128) NOT NULL default ''
) ;


create sequence  nuke_links_categories_cid_seq;

CREATE TABLE nuke_links_categories (
  cid numeric(11) NOT NULL primary key 
        default nextval('nuke_links_categories_cid_seq'),
  title varchar(50) NOT NULL default '',
  cdescription text NOT NULL,
  parentid numeric(11) NOT NULL default '0'
) ;




CREATE TABLE nuke_links_editorials (
  linkid numeric(11) NOT NULL primary key default '0',
  adminid varchar(60) NOT NULL default '',
  editorialtimestamp timestamp NOT NULL default '1903-01-01 00:00:00.00',
  editorialtext text NOT NULL,
  editorialtitle varchar(100) NOT NULL default ''
) ;


create sequence  nuke_links_links_lid_seq;

CREATE TABLE nuke_links_links (
  lid numeric(11) NOT NULL primary key 
     default nextval('nuke_links_links_lid_seq'),
  cid numeric(11) NOT NULL default '0',
  sid numeric(11) NOT NULL default '0',
  title varchar(100) NOT NULL default '',
  url varchar(100) NOT NULL default '',
  description text NOT NULL,
  date timestamp ,
  name varchar(100) NOT NULL default '',
  email varchar(100) NOT NULL default '',
  hits numeric(11) NOT NULL default '0',
  submitter varchar(60) NOT NULL default '',
  linkratingsummary numeric(6,4) NOT NULL default '0.0000',
  totalvotes numeric(11) NOT NULL default '0',
  totalcomments numeric(11) NOT NULL default '0'
) ;

create index nuke_links_links_cid on nuke_links_links (cid);
create index nuke_links_links_sid on nuke_links_links (sid);


create sequence nuke_links_modrequest_rid_seq;

CREATE TABLE nuke_links_modrequest (
  requestid numeric(11) NOT NULL primary key default 
   nextval('nuke_links_modrequest_rid_seq'),
  lid numeric(11) NOT NULL default '0',
  cid numeric(11) NOT NULL default '0',
  sid numeric(11) NOT NULL default '0',
  title varchar(100) NOT NULL default '',
  url varchar(100) NOT NULL default '',
  description text NOT NULL,
  modifysubmitter varchar(60) NOT NULL default '',
  brokenlink numeric(3) NOT NULL default '0'
) ;


create sequence nuke_links_newlink_lid_seq;

CREATE TABLE nuke_links_newlink (
  lid numeric(11) NOT NULL primary key default nextval('nuke_links_newlink_lid_seq'),
  cid numeric(11) NOT NULL default '0',
  sid numeric(11) NOT NULL default '0',
  title varchar(100) NOT NULL default '',
  url varchar(100) NOT NULL default '',
  description text NOT NULL,
  name varchar(100) NOT NULL default '',
  email varchar(100) NOT NULL default '',
  submitter varchar(60) NOT NULL default ''
) ;

create index nuke_links_newlink_cid on nuke_links_newlink (cid);
create index nuke_links_newlink_sid on nuke_links_newlink (sid);

create sequence nuke_links_votedata_id_seq;

CREATE TABLE nuke_links_votedata (
  ratingdbid numeric(11) NOT NULL primary key
    default nextval('sequence nuke_links_votedata_id_seq'),
  ratinglid numeric(11) NOT NULL default '0',
  ratinguser varchar(60) NOT NULL default '',
  rating numeric(11) NOT NULL default '0',
  ratinghostname varchar(60) NOT NULL default '',
  ratingcomments text NOT NULL,
  ratingtimestamp timestamp NOT NULL default '1903-01-01 00:00:00.00'
) ;




CREATE TABLE nuke_main (
  main_module varchar(255) NOT NULL default ''
) ;


INSERT INTO nuke_main VALUES ('News');

create sequence nuke_message_mid_seq;

CREATE TABLE nuke_message (
  mid numeric(11) NOT NULL primary key 
    default nextval('sequence nuke_message_mid_seq'),
  title varchar(100) NOT NULL default '',
  content text NOT NULL,
  date varchar(14) NOT NULL default '',
  expire numeric(7) NOT NULL default '0',
  active numeric(1) NOT NULL default '1',
  view numeric(1) NOT NULL default '1',
  mlanguage varchar(30) NOT NULL default ''
) ;


INSERT INTO nuke_message VALUES (1,'Welcome to PHP-Nuke!','<br>Congratulations! You have now a web portal installed!. You can edit or change this message from the <a href=\"admin.php\">Administration</a> page.\r\n<br><br>\r\n<center><b>For security reasons the best idea is to create the Super User right NOW by clicking <a href=\"admin.php\">HERE</a></b></center>\r\n<br><br>\r\nYou can also create a user for you from the same page. Please read carefully the README file, CREDITS file to see from where comes the things and remember that this is free software released under the GPL License (read COPYING file for details). Hope you enjoy this software. Please report any bug you find when one of this annoying things happens and I\'ll try to fix it for the next release.\r\n<br><br>\r\nIf you like this software and want to make a contribution you can purchase me something from my <a href=\"http://www.amazon.com/exec/obidos/wishlist/1N51JTF344VHI\">Wish List</a>, you can also donate some money to PHP-Nuke project by clicking <a href=\"https://secure.reg.net/product.asp?ID=11155\">here</a> or if you prefer you can become a PHP-Nuke\'s Club Member by clicking <a href=\"http://phpnuke.org/modules.php?name=Club\">here</a> and obtain extra goodies for your system.\r\n<br><br>\r\nPHP-Nuke is an advanced and <i>intelligent</i> content management system designed and programmed with very hard work. PHP-Nuke has the biggest user\'s community in the world for this kind of application, thousands of friendly people (users and programmers) are waiting for you to join the revolution at <a href=\"http://phpnuke.org\">http://phpnuke.org</a> where you can find thousands of modules/addons, themes, blocks, graphics, utilities and much more...\r\n<br><br>\r\nThanks for your support and for select PHP-Nuke as you web site\'s code! Hope you can can enjoy this application as much as we enjoy developing it!','993373194',0,1,1,'');


create sequence nuke_modules_mid_seq;

CREATE TABLE nuke_modules (
  mid numeric(10) NOT NULL primary key default nextval('nuke_modules_mid_seq'),
  title varchar(255) NOT NULL default '',
  custom_title varchar(255) NOT NULL default '',
  active numeric(1) NOT NULL default '0',
  view numeric(1) NOT NULL default '0',
  inmenu numeric(1) NOT NULL default '1'
) ;

create index nuke_modules_title on nuke_modules (title);
create index nuke_modules_custom_title on nuke_modules (custom_title);


INSERT INTO nuke_modules VALUES (1,'AvantGo','',1,0,1);
INSERT INTO nuke_modules VALUES (2,'Downloads','',1,0,1);
INSERT INTO nuke_modules VALUES (3,'Feedback','',1,0,1);
INSERT INTO nuke_modules VALUES (4,'Journal','',1,0,1);
INSERT INTO nuke_modules VALUES (5,'News','',1,0,1);
INSERT INTO nuke_modules VALUES (6,'Private_Messages','',1,0,1);
INSERT INTO nuke_modules VALUES (7,'Recommend_Us','',1,0,1);
INSERT INTO nuke_modules VALUES (8,'Search','',1,0,1);
INSERT INTO nuke_modules VALUES (9,'Statistics','',1,0,1);
INSERT INTO nuke_modules VALUES (10,'Stories_Archive','',1,0,1);
INSERT INTO nuke_modules VALUES (11,'Submit_News','',1,0,1);
INSERT INTO nuke_modules VALUES (12,'Surveys','',1,0,1);
INSERT INTO nuke_modules VALUES (13,'Top','Top 10',1,0,1);
INSERT INTO nuke_modules VALUES (14,'Topics','',1,0,1);
INSERT INTO nuke_modules VALUES (15,'Web_Links','',1,0,1);
INSERT INTO nuke_modules VALUES (16,'WebMail','',1,1,1);
INSERT INTO nuke_modules VALUES (17,'Your_Account','',1,0,1);
INSERT INTO nuke_modules VALUES (18,'Addon_Sample','',0,2,1);
INSERT INTO nuke_modules VALUES (19,'Content','',0,0,1);
INSERT INTO nuke_modules VALUES (20,'Encyclopedia','',0,0,1);
INSERT INTO nuke_modules VALUES (21,'FAQ','',0,0,1);
INSERT INTO nuke_modules VALUES (22,'Forums','',0,0,1);
INSERT INTO nuke_modules VALUES (23,'Members_List','',0,1,1);
INSERT INTO nuke_modules VALUES (24,'Reviews','',0,0,1);
INSERT INTO nuke_modules VALUES (25,'Sections','',0,0,1);


create sequence nuke_pages_pid_seq;

CREATE TABLE nuke_pages (
  pid numeric(10) NOT NULL primary key 
    default nextval('nuke_pages_pid_seq'),
  cid numeric(10) NOT NULL default '0',
  title varchar(255) NOT NULL default '',
  subtitle varchar(255) NOT NULL default '',
  active numeric(1) NOT NULL default '0',
  page_header text NOT NULL,
  text text NOT NULL,
  page_footer text NOT NULL,
  signature text NOT NULL,
  date timestamp NOT NULL default '1903-01-01 00:00:00.00',
  counter numeric(10) NOT NULL default '0',
  clanguage varchar(30) NOT NULL default ''
) ;

create index nuke_pages_cid on nuke_pages (cid);


create sequence nuke_pages_categories_cid_seq;

CREATE TABLE nuke_pages_categories (
  cid numeric(10) NOT NULL primary key default nextval('nuke_pages_categories_cid_seq'),
  title varchar(255) NOT NULL default '',
  description text NOT NULL
) ;




CREATE TABLE nuke_poll_check (
  ip varchar(20) NOT NULL default '',
  time varchar(14) NOT NULL default '',
  pollID numeric(10) NOT NULL default '0'
) ;




CREATE TABLE nuke_poll_data (
  pollID numeric(11) NOT NULL default '0',
  optionText char(50) NOT NULL default '',
  optionCount numeric(11) NOT NULL default '0',
  voteID numeric(11) NOT NULL default '0'
) ;


INSERT INTO nuke_poll_data VALUES (1,'Ummmm, not bad',0,1);
INSERT INTO nuke_poll_data VALUES (1,'Cool',0,2);
INSERT INTO nuke_poll_data VALUES (1,'Terrific',0,3);
INSERT INTO nuke_poll_data VALUES (1,'The best one!',0,4);
INSERT INTO nuke_poll_data VALUES (1,'what the hell is this?',0,5);
INSERT INTO nuke_poll_data VALUES (1,'',0,6);
INSERT INTO nuke_poll_data VALUES (1,'',0,7);
INSERT INTO nuke_poll_data VALUES (1,'',0,8);
INSERT INTO nuke_poll_data VALUES (1,'',0,9);
INSERT INTO nuke_poll_data VALUES (1,'',0,10);
INSERT INTO nuke_poll_data VALUES (1,'',0,11);
INSERT INTO nuke_poll_data VALUES (1,'',0,12);


create sequence nuke_poll_desc_pollid_seq;

CREATE TABLE nuke_poll_desc (
  pollID numeric(11) NOT NULL primary key default nextval('nuke_poll_desc_pollid_seq'),
  pollTitle varchar(100) NOT NULL default '',
  timeStamp numeric(11) NOT NULL default '0',
  voters numeric(9) NOT NULL default '0',
  planguage varchar(30) NOT NULL default '',
  artid numeric(10) NOT NULL default '0'
) ;


INSERT INTO nuke_poll_desc VALUES (1,'What do you think about this site?',961405160,0,'english',0);


create sequence nuke_pollcomments_tid_seq;

CREATE TABLE nuke_pollcomments (
  tid numeric(11) NOT NULL primary key 
   default nextval('nuke_pollcomments_tid_seq'),
  pid numeric(11) default '0',
  pollID numeric(11) default '0',
  date timestamp ,
  name varchar(60) NOT NULL default '',
  email varchar(60) default NULL,
  url varchar(60) default NULL,
  host_name varchar(60) default NULL,
  subject varchar(60) NOT NULL default '',
  comment text NOT NULL,
  score numeric(4) NOT NULL default '0',
  reason numeric(4) NOT NULL default '0'
) ;

create index nuke_pollcomments_pid on nuke_pollcomments (pid);
create index nuke_pollcomments_pollid on nuke_pollcomments (pollid);


create sequence nuke_popsettings_id_seq;

CREATE TABLE nuke_popsettings (
  id numeric(11) NOT NULL primary key 
     default nextval('nuke_popsettings_id_seq'),
  uid numeric(11) default NULL,
  account varchar(50) default NULL,
  popserver varchar(255) default NULL,
  port numeric(5) default NULL,
  uname varchar(100) default NULL,
  passwd varchar(20) default NULL,
  numshow numeric(11) default NULL,
  deletefromserver char(1) default NULL,
  refresh numeric(11) default NULL,
  timeout numeric(11) default NULL
) ;

create index nuke_popsettings_uid on nuke_popsettings (uid);


create sequence nuke_posts_id_seq; 

CREATE TABLE nuke_posts (
  post_id numeric(10) NOT NULL primary key default nextval('nuke_posts_id_seq'),
  image varchar(100) default NULL,
  topic_id numeric(10) NOT NULL default '0',
  forum_id numeric(10) NOT NULL default '0',
  poster_id numeric(10) default NULL,
  post_text text,
  post_time varchar(20) default NULL,
  poster_ip varchar(16) default NULL
) ;

create index nuke_posts_topic_id on nuke_posts (topic_id);
create index nuke_posts_forum_id on nuke_posts (forum_id);
create index nuke_posts_poster_id on nuke_posts (poster_id);



CREATE TABLE nuke_posts_text (
  post_id numeric(10) NOT NULL primary key default '0',
  post_text text
) ;


create sequence nuke_priv_msgs_id_seq;

CREATE TABLE nuke_priv_msgs (
  msg_id numeric(10) NOT NULL primary key 
     default nextval('nuke_priv_msgs_id_seq'),
  msg_image varchar(100) default NULL,
  subject varchar(100) default NULL,
  from_userid numeric(10) NOT NULL default '0',
  to_userid numeric(10) NOT NULL default '0',
  msg_time varchar(20) default NULL,
  msg_text text,
  read_msg numeric(10) NOT NULL default '0'
) ;

create index nuke_priv_msgs_to_userid on nuke_priv_msgs (to_userid);
create index nuke_priv_msgs_from_userid on nuke_priv_msgs (from_userid);


create sequence  nuke_public_messages_mid_seq;

CREATE TABLE nuke_public_messages (
  mid varchar(10) NOT NULL primary key 
    default nextval('nuke_public_messages_mid_seq'),
  content varchar(255) NOT NULL default '',
  date varchar(14) default NULL,
  who varchar(25) NOT NULL default ''
) ;


create sequence nuke_queue_qid_seq;

CREATE TABLE nuke_queue (
  qid numeric(5) NOT NULL primary key 
     default nextval('nuke_queue_qid_seq'),
  uid numeric(9) NOT NULL default '0',
  uname varchar(40) NOT NULL default '',
  subject varchar(100) NOT NULL default '',
  story text,
  storyext text NOT NULL,
  timestamp timestamp NOT NULL default '1903-01-01 00:00:00.00',
  topic varchar(20) NOT NULL default '',
  alanguage varchar(30) NOT NULL default ''
) ;

create index nuke_queue_uid on nuke_queue (uid);
create index nuke_queue_uname on nuke_queue (uname);

create sequence nuke_quotes_qid_seq;

CREATE TABLE nuke_quotes (
  qid numeric(10) NOT NULL primary key default nextval('nuke_quotes_qid_seq'),
  quote text
) ;


INSERT INTO nuke_quotes VALUES (1,'Nos morituri te salutamus - CBHS');


create sequence nuke_ranks_id_seq;

CREATE TABLE nuke_ranks (
  rank_id numeric(10) NOT NULL primary key default nextval('nuke_ranks_id_seq'),
  rank_title varchar(50) NOT NULL default '',
  rank_min numeric(10) NOT NULL default '0',
  rank_max numeric(10) NOT NULL default '0',
  rank_special numeric(2) default '0',
  rank_image varchar(255) default NULL
) ;

create index nuke_ranks_min on nuke_ranks (rank_min);
create index nuke_ranks_max on nuke_ranks (rank_max);


create sequence nuke_referer_rid_seq;

CREATE TABLE nuke_referer (
  rid numeric(11) NOT NULL primary key default nextval('nuke_referer_rid_seq'),
  url varchar(100) NOT NULL default ''
) ;


create sequence nuke_related_rid_seq;

CREATE TABLE nuke_related (
  rid numeric(11) NOT NULL primary key default nextval('nuke_related_rid_seq'),
  tid numeric(11) NOT NULL default '0',
  name varchar(30) NOT NULL default '',
  url varchar(200) NOT NULL default ''
) ;

create index nuke_related_tid on nuke_related (tid);

create sequence nuke_reviews_id_seq;

CREATE TABLE nuke_reviews (
  id numeric(10) NOT NULL primary key default nextval('nuke_reviews_id_seq'),
  date date NOT NULL default '0001-01-01',
  title varchar(150) NOT NULL default '',
  text text NOT NULL,
  reviewer varchar(20) default NULL,
  email varchar(60) default NULL,
  score numeric(10) NOT NULL default '0',
  cover varchar(100) NOT NULL default '',
  url varchar(100) NOT NULL default '',
  url_title varchar(50) NOT NULL default '',
  hits numeric(10) NOT NULL default '0',
  rlanguage varchar(30) NOT NULL default ''
) ;


create sequence nuke_previews_add_id_seq;

CREATE TABLE nuke_reviews_add (
  id numeric(10) NOT NULL primary key 
     default nextval('nuke_previews_add_id_seq'),
  date date default NULL,
  title varchar(150) NOT NULL default '',
  text text NOT NULL,
  reviewer varchar(20) NOT NULL default '',
  email varchar(60) default NULL,
  score numeric(10) NOT NULL default '0',
  url varchar(100) NOT NULL default '',
  url_title varchar(50) NOT NULL default '',
  rlanguage varchar(30) NOT NULL default ''
) ;


create sequence nuke_reviews_comments_cid_seq;

CREATE TABLE nuke_reviews_comments (
  cid numeric(10) NOT NULL primary key default nextval('nuke_reviews_comments_cid_seq'),
  rid numeric(10) NOT NULL default '0',
  userid varchar(25) NOT NULL default '',
  date timestamp ,
  comments text,
  score numeric(10) NOT NULL default '0'
) ;

create index nuke_reviews_comments_rid on nuke_reviews_comments (rid);
create index nuke_reviews_comments_userid on nuke_reviews_comments (userid);


CREATE TABLE nuke_reviews_main (
  title varchar(100) default NULL,
  description text
) ;


INSERT INTO nuke_reviews_main VALUES ('Reviews Section Title','Reviews Section Long Description');

create sequence nuke_seccont_artid_seq;

CREATE TABLE nuke_seccont (
  artid numeric(11) NOT NULL primary key default nextval('nuke_seccont_artid_seq'),
  secid numeric(11) NOT NULL default '0',
  title text NOT NULL,
  content text NOT NULL,
  counter numeric(11) NOT NULL default '0',
  slanguage varchar(30) NOT NULL default ''
) ;

create index nuke_seccont_secid on nuke_seccont (secid);

create sequence nuke_sections_secid_seq;

CREATE TABLE nuke_sections (
  secid numeric(11) NOT NULL primary key default nextval(''),
  secname varchar(40) NOT NULL default '',
  image varchar(50) NOT NULL default ''
) ;




CREATE TABLE nuke_session (
  username varchar(25) NOT NULL default '',
  time varchar(14) NOT NULL default '',
  host_addr varchar(48) NOT NULL default '',
  guest numeric(1) NOT NULL default '0'
) ;
create index nuke_session_time on nuke_session (time);
create index nuke_session_guest on nuke_session (guest);


create sequence nuke_smiles_id_seq;

CREATE TABLE nuke_smiles (
  id numeric(10) NOT NULL primary key  default nextval('nuke_smiles_id_seq'),
  code varchar(50) default NULL,
  smile_url varchar(100) default NULL,
  emotion varchar(75) default NULL,
  active numeric(2) default '0'
) ;


INSERT INTO nuke_smiles VALUES (1,':D','icon_biggrin.gif','Very Happy',0);
INSERT INTO nuke_smiles VALUES (2,':-D','icon_biggrin.gif','Very Happy',1);
INSERT INTO nuke_smiles VALUES (3,':grin:','icon_biggrin.gif','Very Happy',0);
INSERT INTO nuke_smiles VALUES (4,':)','icon_smile.gif','Smile',0);
INSERT INTO nuke_smiles VALUES (5,':-)','icon_smile.gif','Smile',1);
INSERT INTO nuke_smiles VALUES (6,':smile:','icon_smile.gif','Smile',0);
INSERT INTO nuke_smiles VALUES (7,':(','icon_frown.gif','Sad',0);
INSERT INTO nuke_smiles VALUES (8,':-(','icon_frown.gif','Sad',1);
INSERT INTO nuke_smiles VALUES (9,':sad:','icon_frown.gif','Sad',0);
INSERT INTO nuke_smiles VALUES (10,':o','icon_eek.gif','Surprised',0);
INSERT INTO nuke_smiles VALUES (11,':-o','icon_eek.gif','Surprised',1);
INSERT INTO nuke_smiles VALUES (12,':eek:','icon_eek.gif','Suprised',0);
INSERT INTO nuke_smiles VALUES (13,':-?','icon_confused.gif','Confused',1);
INSERT INTO nuke_smiles VALUES (14,':???:','icon_confused.gif','Confused',0);
INSERT INTO nuke_smiles VALUES (15,'8)','icon_cool.gif','Cool',0);
INSERT INTO nuke_smiles VALUES (16,'8-)','icon_cool.gif','Cool',1);
INSERT INTO nuke_smiles VALUES (17,':cool:','icon_cool.gif','Cool',0);
INSERT INTO nuke_smiles VALUES (18,':lol:','icon_lol.gif','Laughing',1);
INSERT INTO nuke_smiles VALUES (19,':x','icon_mad.gif','Mad',0);
INSERT INTO nuke_smiles VALUES (20,':-x','icon_mad.gif','Mad',1);
INSERT INTO nuke_smiles VALUES (21,':mad:','icon_mad.gif','Mad',0);
INSERT INTO nuke_smiles VALUES (22,':P','icon_razz.gif','Razz',0);
INSERT INTO nuke_smiles VALUES (23,':-P','icon_razz.gif','Razz',1);
INSERT INTO nuke_smiles VALUES (24,':razz:','icon_razz.gif','Razz',0);
INSERT INTO nuke_smiles VALUES (25,':oops:','icon_redface.gif','Embaressed',1);
INSERT INTO nuke_smiles VALUES (26,':cry:','icon_cry.gif','Crying (very sad)',1);
INSERT INTO nuke_smiles VALUES (27,':evil:','icon_evil.gif','Evil or Very Mad',1);
INSERT INTO nuke_smiles VALUES (28,':roll:','icon_rolleyes.gif','Rolling Eyes',1);
INSERT INTO nuke_smiles VALUES (29,':wink:','icon_wink.gif','Wink',0);
INSERT INTO nuke_smiles VALUES (30,';)','icon_wink.gif','Wink',0);
INSERT INTO nuke_smiles VALUES (31,';-)','icon_wink.gif','Wink',1);


CREATE TABLE nuke_stats_date (
  year numeric(6) NOT NULL default '0',
  month numeric(4) NOT NULL default '0',
  date numeric(4) NOT NULL default '0',
  hits numeric(20) NOT NULL default '0'
) ;



CREATE TABLE nuke_stats_hour (
  year numeric(6) NOT NULL default '0',
  month numeric(4) NOT NULL default '0',
  date numeric(4) NOT NULL default '0',
  hour numeric(4) NOT NULL default '0',
  hits numeric(11) NOT NULL default '0'
) ;



CREATE TABLE nuke_stats_month (
  year numeric(6) NOT NULL default '0',
  month numeric(4) NOT NULL default '0',
  hits numeric(20) NOT NULL default '0'
) ;



CREATE TABLE nuke_stats_year (
  year numeric(6) NOT NULL default '0',
  hits numeric(20) NOT NULL default '0'
) ;


INSERT INTO nuke_stats_year VALUES (2002,1);

create sequence nuke_stories_sid_seq;

CREATE TABLE nuke_stories (
  sid numeric(11) NOT NULL primary key default nextval('nuke_stories_sid_seq'),
  catid numeric(11) NOT NULL default '0',
  aid varchar(30) NOT NULL default '',
  title varchar(80) default NULL,
  time timestamp ,
  hometext text,
  bodytext text NOT NULL,
  comments numeric(11) default '0',
  counter numeric(8) default NULL,
  topic numeric(3) NOT NULL default '1',
  informant varchar(20) NOT NULL default '',
  notes text NOT NULL,
  ihome numeric(1) NOT NULL default '0',
  alanguage varchar(30) NOT NULL default '',
  acomm numeric(1) NOT NULL default '0',
  haspoll numeric(1) NOT NULL default '0',
  pollID numeric(10) NOT NULL default '0',
  score numeric(10) NOT NULL default '0',
  ratings numeric(10) NOT NULL default '0'
) ;

create index nuke_stories_catid on nuke_stories (catid);

create sequence nuke_stories_catid_seq;

CREATE TABLE nuke_stories_cat (
  catid numeric(11) NOT NULL primary key default nextval('nuke_stories_catid_seq'),
  title varchar(20) NOT NULL default '',
  counter numeric(11) NOT NULL default '0'
) ;


create sequence nuke_topics_id_seq;

CREATE TABLE nuke_topics (
  topicid numeric(3) NOT NULL primary key default nextval('nuke_topics_id_seq'),
  topicname varchar(20) default NULL,
  topicimage varchar(20) default NULL,
  topictext varchar(40) default NULL,
  counter numeric(11) NOT NULL default '0'
) ;


INSERT INTO nuke_topics VALUES (1,'phpnuke','phpnuke.gif','PHP-Nuke',0);

create sequence nuke_users_uid_seq;

CREATE TABLE nuke_users (
  uid numeric(11) NOT NULL primary key default nextval('nuke_users_uid_seq'),
  name varchar(60) NOT NULL default '',
  uname varchar(25) NOT NULL default '',
  email varchar(255) NOT NULL default '',
  femail varchar(255) NOT NULL default '',
  url varchar(255) NOT NULL default '',
  user_avatar varchar(30) default NULL,
  user_regdate varchar(20) NOT NULL default '',
  user_icq varchar(15) default NULL,
  user_occ varchar(100) default NULL,
  user_from varchar(100) default NULL,
  user_intrest varchar(150) default NULL,
  user_sig varchar(255) default NULL,
  user_viewemail numeric(2) default NULL,
  user_theme numeric(3) default NULL,
  user_aim varchar(18) default NULL,
  user_yim varchar(25) default NULL,
  user_msnm varchar(25) default NULL,
  pass varchar(40) NOT NULL default '',
  storynum numeric(4) NOT NULL default '10',
  umode varchar(10) NOT NULL default '',
  uorder numeric(1) NOT NULL default '0',
  thold numeric(1) NOT NULL default '0',
  noscore numeric(1) NOT NULL default '0',
  bio text NOT NULL,
  ublockon numeric(1) NOT NULL default '0',
  ublock text NOT NULL,
  theme varchar(255) NOT NULL default '',
  commentmax numeric(11) NOT NULL default '4096',
  counter numeric(11) NOT NULL default '0',
  newsletter numeric(1) NOT NULL default '0',
  user_posts numeric(10) NOT NULL default '0',
  user_attachsig numeric(2) NOT NULL default '0',
  user_rank numeric(10) NOT NULL default '0',
  user_level numeric(10) NOT NULL default '1',
  broadcast numeric(1) NOT NULL default '1',
  popmeson numeric(1) NOT NULL default '0'
) ;

create index nuke_users_uname on nuke_users (uname);


INSERT INTO nuke_users VALUES (1,'','Anonymous','','','','blank.gif','Nov 10, 2000','','','','','',0,0,'','','','',10,'',0,0,0,'',0,'','',4096,0,0,0,0,0,1,0,0);

create sequence nuke_words_id_seq;

CREATE TABLE nuke_words (
  word_id numeric(10) NOT NULL primary key default nextval('nuke_words_id_seq'),
  word varchar(100) default NULL,
  replacement varchar(100) default NULL
) ;



