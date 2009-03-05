# -*- cperl -*-
# $Author$
# $Date$
# $Revision$

use ExtUtils::testlib;
use Test::More tests => 51;
use Config::Model;
use File::Path;
use File::Copy ;
use Test::Warn ;
use Test::Exception ;

use warnings;
no warnings qw(once);

use strict;

use vars qw/$model/;

$model = Config::Model -> new (legacy => 'ignore',) ;

my $arg = shift || '';

my $trace = $arg =~ /t/ ? 1 : 0 ;
$::verbose          = 1 if $arg =~ /v/;
$::debug            = 1 if $arg =~ /d/;
Config::Model::Exception::Any->Trace(1) if $arg =~ /e/;

use Log::Log4perl qw(:easy) ;
Log::Log4perl->easy_init($arg =~ /l/ ? $TRACE: $WARN);

ok(1,"compiled");


# pseudo root for config files 
my $wr_root = 'wr_root' ;
my $root1 = "$wr_root/test1/";
my $root2 = "$wr_root/test2/";
my $root3 = "$wr_root/test3/";

my $conf_dir  = '/etc/test/'; 

# cleanup before tests
rmtree($wr_root);

# model declaration
$model->create_config_class 
  (
   name   => 'Level2',
   element => [
	       [qw/X Y Z/] => {
			       type => 'leaf',
			       value_type => 'enum',
			       choice     => [qw/Av Bv Cv/]
			      }
	      ]
  );

$model->create_config_class 
  (
   name => 'Level1',

   # try first to read with cds string and then custom class
   read_config  => [ { backend => 'cds_file'}, 
		     { backend => 'custom', 
		       class => 'Level1Read', 
		       function => 'read_it' } ],
   write_config => [ { backend => 'cds_file', config_dir => $conf_dir},
		     { backend => 'perl_file', config_dir => $conf_dir},
		     { backend => 'ini_file' , config_dir => $conf_dir}],

   read_config_dir  => $conf_dir,

   element => [
	       bar => { type => 'node',
			config_class_name => 'Level2',
		      } 
	      ]
   );

$model->create_config_class 
  (
   name => 'SameReadWriteSpec',

   # try first to read with cds string and then custom class
   read_config  => [ { backend => 'cds_file', config_dir => $conf_dir }, 
		     { backend => 'custom', class => 'SameRWSpec', config_dir => $conf_dir },
		     { backend => 'ini_file', config_dir => $conf_dir } 
		   ],

   element => [
	       bar => { type => 'node',
			config_class_name => 'Level2',
		      } 
	      ]
   );


$model->create_config_class 
  (
   name => 'Master',

   read_config  => [ { backend => 'cds_file', config_dir => $conf_dir},
		     { backend => 'perl_file', config_dir => $conf_dir},
		     { backend => 'ini_file', config_dir => $conf_dir } ,
		     { backend => 'custom', class => 'MasterRead', 
		       config_dir => $conf_dir, function => 'read_it' }
		   ],
   write_config => [ { backend => 'cds_file', config_dir => $conf_dir},
		     { backend => 'perl', config_dir => $conf_dir},
		     { backend => 'ini_file', config_dir => $conf_dir } ,
		     { class => 'MasterRead', function => 'wr_stuff', 
		       config_dir => $conf_dir}
		   ],

   element => [
	       aa => { type => 'leaf',value_type => 'string'} ,
	       level1 => { type => 'node',
			   config_class_name => 'Level1',
			 },
	       samerw => { type => 'node',
			   config_class_name => 'SameReadWriteSpec',
			 },
	      ]
   );

$model->create_config_class 
  (
   name => 'FromScratch',

   read_config  => [ { backend => 'cds_file', config_dir => $conf_dir,
		       allow_empty => 1},
		   ],

   element => [
	       aa => { type => 'leaf',value_type => 'string'} ,
	      ]
   );

# global variable to snoop on read config action
my %result;

package MasterRead;

my $custom_aa = 'aa was set (custom mode)' ;

sub read_it {
    my %args = @_;
    $result{master_read} = $args{config_dir};
    $args{object}->store_element_value('aa', $custom_aa);
}

sub wr_stuff {
    my %args = @_;
    $result{wr_stuff} = $args{config_dir};
    $result{wr_root_name} = $args{object}->name ;
}

package Level1Read;

sub read_it {
    my %args = @_;
    $result{level1_read} = $args{config_dir};
    $args{object}->load('bar X=Cv');
}

package SameRWSpec;

sub read {
    my %args = @_;
    $result{same_rw_read} = $args{config_dir};
    $args{object}->load('bar Y=Cv');
}

sub write {
    my %args = @_;
    $result{same_rw_write} = $args{config_dir};
}

package main;

throws_ok {
    my $i_fail = $model->instance(instance_name    => 'zero_inst',
			       root_class_name  => 'Master',
			       root_dir   => $root1 ,
			       backend => 'perl_file',
			      );
    } qr/'perl_file' backend/,  "read with forced perl_file backend fails (normal: no perl file)"  ;

my $i_zero ;
warnings_like {
$i_zero = $model->instance(instance_name    => 'zero_inst',
			   root_class_name  => 'Master',
			   root_dir   => $root1 ,
			  );
} qr/deprecated auto_read/ , "obsolete warning" ;

ok( $i_zero, "Created instance (from scratch)" );

# check that conf dir was read when instance was created
is( $result{master_read}, $conf_dir, "Master read conf dir" );

my $master = $i_zero->config_root;

ok( $master, "Master node created" );

is( $master->fetch_element_value('aa'), $custom_aa, "Master custom read" );

my $level1;

warnings_like {
    $level1 = $master->fetch_element('level1');
} qr/read_config_dir is obsolete/ , "obsolete warning" ;

ok( $level1, "Level1 object created" );

is( $level1->grab_value('bar X'), 'Cv', "Check level1 custom read" );

is( $result{level1_read} , $conf_dir, "check level1 custom read conf dir" );

my $same_rw = $master->fetch_element('samerw');

ok( $same_rw, "SameRWSpec object created" );
is( $same_rw->grab_value('bar Y'), 'Cv', "Check samerw custom read" );

is( $result{same_rw_read}, $conf_dir, "check same_rw_spec custom read conf dir" );

is( scalar @{ $i_zero->{write_back} }, 10, 
    "check that write call back are present" );

# perform write back of dodu tree dump string
$i_zero->write_back(backend => 'all');

# check written files
foreach my $suffix (qw/cds ini/) {
    map { 
	my $f = "$root1$conf_dir/$_.$suffix" ;
	ok( -e $f, "check written file $f" ); 
    } 
      ('zero_inst','zero_inst/level1','zero_inst/samerw') ;
}

foreach my $suffix (qw/pl/) {
    map { 
	my $f = "$root1$conf_dir/$_.$suffix" ;
	ok( -e "$f", "check written file $f" );
    } 
      ('zero_inst','zero_inst/level1') ;
}

# check called write routine
is($result{wr_stuff},$conf_dir,'check custom write dir') ;
is($result{wr_root_name},'Master','check custom conf root to write') ;

# perform write back of dodu tree dump string in an overridden dir
my $override = 'etc/wr_2/';
$i_zero->write_back(backend => 'all', config_dir => $override);

# check written files
foreach my $suffix (qw/cds ini/) {
    map { ok( -e "$root1$override$_.$suffix", 
	      "check written file $root1$override$_.$suffix" ); } 
      ('zero_inst','zero_inst/level1','zero_inst/samerw' ) ;
}
foreach my $suffix (qw/pl/) {
    map { ok( -e "$root1$override$_.$suffix", 
	      "check written file $root1$override$_.$suffix" ); } 
      ('zero_inst','zero_inst/level1') ;
}

is($result{wr_stuff},$override,'check custom overridden write dir') ;

my $dump = $master->dump_tree( skip_auto_write => 'cds_file' );
print "Master dump:\n$dump\n" if $trace;

is($dump,qq!aa="$custom_aa" -\n!,"check master dump") ;

$dump = $level1->dump_tree( skip_auto_write => 'cds_file' );
print "Level1 dump:\n$dump\n" if $trace;
is($dump,qq!  bar\n    X=Cv - -\n!,"check level1 dump") ;


my $inst2 = 'second_inst' ;

my %cds = (
    $inst2 => 'aa="aa was set by file" - ',
    "$inst2/level1"   => 'bar X=Av Y=Bv - '
);

my $dir2 = "$root2/etc/test/" ;
mkpath($dir2.$inst2,0,0755) || die "Can't mkpath $dir2.$inst2:$!";

# write input config files
foreach my $f ( keys %cds ) {
    my $fout = "$dir2/$f.cds";
    next if -r $fout;

    open( FOUT, ">$fout" ) or die "can't open $fout:$!";
    print FOUT $cds{$f};
    close FOUT;
}

# create another instance
my $test2_inst;
warnings_like {
    $test2_inst = $model->instance(root_class_name  => 'Master',
				   instance_name    => $inst2 ,
				   root_dir         => $root2 ,);
    } [qr/deprecated/],
  "obsolete warning" ;

ok($inst2,"created second instance") ;

# access level1 to autoread it
my $root_2   = $test2_inst  -> config_root ;

my $level1_2;
warnings_like {
    $level1_2 = $root_2 -> fetch_element('level1');
} qr/read_config_dir is obsolete/ , "obsolete warning" ;


is($root_2->grab_value('aa'),'aa was set by file',"$inst2: check that cds file was read") ;

my $dump2 = $root_2->dump_tree( );
print "Read Master dump:\n$dump2\n" if $trace;

my $expect2 = 'aa="aa was set by file"
level1
  bar
    X=Av
    Y=Bv - -
samerw
  bar
    Y=Cv - - -
' ;
is( $dump2, $expect2, "$inst2: check dump" );

# test loading with ini files
map { my $o = $_; s!$root1/zero!ini!; 
      copy($o,"$root2/$_") or die "can't copy $o $_:$!" } 
  glob("$root1/*.ini") ;

# create another instance to load ini files
my $ini_inst ;
warnings_like {
    $ini_inst = $model->instance(root_class_name  => 'Master',
				instance_name => 'ini_inst' );
} [qr/deprecated/],
  "obsolete warning" ;

ok($ini_inst,"Created instance to load ini files") ;

my $expect_custom = 'aa="aa was set (custom mode)"
level1
  bar
    X=Cv - -
samerw
  bar
    Y=Cv - - -
' ;

warnings_like {
    $dump = $ini_inst ->config_root->dump_tree ;
} qr/read_config_dir is obsolete/ , "obsolete warning" ;

is( $dump, $expect_custom, "ini_test: check dump" );


unlink(glob("$root2/*.ini")) ;

# test loading with pl files
map { my $o = $_; s!$root1/zero!pl!; 
      copy($o,"$root2/$_") or die "can't copy $o $_:$!" 
  } glob("$root1/*.pl") ;

# create another instance to load pl files
my $pl_inst ;
warnings_like {
    $pl_inst = $model->instance(root_class_name  => 'Master',
				instance_name => 'pl_inst' );
} [qr/deprecated/],
  "obsolete warning" ;

ok($pl_inst,"Created instance to load pl files") ;

warnings_like {
    $dump = $pl_inst ->config_root->dump_tree ;
} qr/read_config_dir is obsolete/ , "obsolete warning" ;

is( $dump, $expect_custom, "pl_test: check dump" );

#create from scratch instance
my $scratch_i = $model->instance(root_class_name  => 'FromScratch',
				 instance_name => 'scratch_inst',
				 root_dir => $root3 ,
				);
ok($scratch_i,"Created instance from scratch to load cds files") ;

$scratch_i->config_root->load("aa=toto") ;
$scratch_i -> write_back ;
ok ( -e "$root3/$conf_dir/scratch_inst.cds", "wrote cds config file") ;
