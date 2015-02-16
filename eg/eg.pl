#!/usr/bin/env perl
use 5.20.0;
use utf8;
use warnings;
use experimental 'signatures', 'postderef';
use lib "../lib";
use Data::Dump;

use Distribution::Metadata;

my $d = Distribution::Metadata->new_from_module("LWP::Simple");

dd $d->install_json_hash;
dd $d->mymeta_hash;
dd $d->files;
