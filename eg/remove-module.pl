#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use lib "../lib";
use Distribution::Metadata;
use Config;
use Getopt::Long qw(:config no_auto_abbrev no_ignore_case);
use File::Path 'rmtree';
use Pod::Usage 'pod2usage';
use IO::Handle;
require ExtUtils::MakeMaker;
sub prompt { ExtUtils::MakeMaker::prompt(@_) }
STDOUT->autoflush(1);

GetOptions
    "h|help" => sub { pod2usage(0) },
or pod2usage(1);

my $module = shift or pod2usage(1);

my $info = Distribution::Metadata->new_from_module($module);
die "Cannot find $module\n" unless $info->packlist;

my @unlink = (@{ $info->files }, $info->install_json, $info->mymeta, $info->meta_directory);

warn "-> $_\n" for @unlink;
my $answer = prompt("=> Do you want to unlink the above files? (y/N)", "N");
exit if $answer !~ /^y$/i;

for my $entry (@unlink) {
    if (-f $entry) {
        if (unlink $entry) {
            warn "-> Removed $entry\n";
        } else {
            die "=> Failed to remove $entry: $!\n";
        }
    } elsif (-d $entry) {
        if (rmtree $entry) {
            warn "-> Removed $entry\n";
        } else {
            die "=> Failed to remove $entry";
        }
    }
}

__END__

=head1 SYNOPSIS

    > remove-module.pl MODULE

=cut
