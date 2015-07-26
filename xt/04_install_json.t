use strict;
use warnings;
use utf8;
use Test::More;
use File::Temp 'tempdir';
sub cpanm { !system "cpanm", "-nq", "--reinstall", @_ or die "cpanm fail"; }

use Distribution::Metadata::Factory;

my $tempdir = tempdir CLEANUP => 1;
cpanm "-l$tempdir/local", 'Module::Build';
my $factory = Distribution::Metadata::Factory->new(
    inc => ["$tempdir/local/lib/perl5", @INC], fill_archlib => 1,
);

# Module::Build in $tempdir/local
# Module::Metadata in site_lib
# check Factory take care of install_json in different directories
my $info1 = $factory->create_from_module("Module::Build");
my $info2 = $factory->create_from_module("Module::Metadata");

ok $info1->install_json;
ok $info2->install_json;

done_testing;
