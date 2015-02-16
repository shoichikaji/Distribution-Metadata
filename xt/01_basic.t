use strict;
use warnings;
use utf8;
use Test::More;
use Distribution::Metadata;
use File::Temp 'tempdir';
use Config;
use File::Find 'find';
use File::Basename 'basename';
use File::pushd 'tempd';
use File::Spec;
sub cpanm { !system "cpanm", "-nq", "--reinstall", @_ or die "cpanm fail"; }

subtest basic => sub {
    my $tempdir = tempdir CLEANUP => 1;
    cpanm "-l$tempdir/local", 'Test::TCP@2.07';
    my $info1 = Distribution::Metadata->new_from_module(
        "Test::TCP",
        inc => ["$tempdir/local/lib/perl5", "$tempdir/local/lib/perl5/$Config{archname}"],
    );
    my $info2 = Distribution::Metadata->new_from_module(
        "Net::EmptyPort",
        inc => ["$tempdir/local/lib/perl5", "$tempdir/local/lib/perl5/$Config{archname}"],
    );

    for my $method (qw(packlist meta_directory install_json mymeta
        main_module main_module_version)) {
        ok $info1->$method;
        is $info1->$method, $info2->$method;
    }
    for my $method (qw(install_json_hash mymeta_hash files)) {
        ok $info1->$method;
        is_deeply $info1->$method, $info2->$method;
    }

    # my %files;
    # find sub { $files{$File::Find::name} = 0 if -f $_ }, $tempdir;
    #
    # for my $file (@{ $info1->files }) {
    #     if (exists $files{ $file }) {
    #         $files{ $file }++;
    #     }
    # }
    # my @not_listed_in_packlist = grep { $files{$_} == 0 } sort keys %files;
    # my @known = qw(MYMETA.json install.json .packlist perllocal.pod);
    #
    # for my $file (@not_listed_in_packlist) {
    #     my $basename = basename $file;
    #     if (0 == grep { $basename eq $_ } @known) {
    #         fail "Unexpected file '$file'";
    #     }
    # }
};

subtest prefer => sub {
    my $tempdir = tempdir CLEANUP => 1;
    cpanm "-l$tempdir/local2.07", 'Test::TCP@2.07';
    cpanm "-l$tempdir/local2.06", 'Test::TCP@2.06';
    my $info = Distribution::Metadata->new_from_module(
        "Test::TCP",
        inc => [
            "$tempdir/local2.06/lib/perl5",
            "$tempdir/local2.06/lib/perl5/$Config{archname}",
            "$tempdir/local2.07/lib/perl5",
            "$tempdir/local2.07/lib/perl5/$Config{archname}",
        ],
    );
    like $info->$_, qr/2\.06/ for qw(install_json mymeta meta_directory);
    is $info->install_json_hash->{version}, '2.06';
};

subtest abs_path => sub {
    my $tempdir = tempd;
    cpanm "-llocal", 'Test::TCP@2.07';
    my $info = Distribution::Metadata->new_from_module(
        "Test::TCP",
        inc => [
            "local/lib/perl5",
            "local/lib/perl5/$Config{archname}",
        ],
    );

    for my $method (qw(packlist mymeta install_json)) {
        my $is_abs = File::Spec->file_name_is_absolute($info->$method);
        ok $is_abs;
    }
};



done_testing;
