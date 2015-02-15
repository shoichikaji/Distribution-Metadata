package Distribution::Metadata;
use 5.008001;
use strict;
use warnings;
use CPAN::Meta;
use Config;
use ExtUtils::Packlist;
use File::Basename 'basename';
use File::Find 'find';
use JSON::PP ();
use Module::Metadata;

our $VERSION = "0.01";

sub packlist { shift->{packlist} }
sub meta_directory { shift->{meta_directory} }
sub install_json { shift->{install_json} }
sub mymeta { shift->{mymeta} }

sub new_from_module {
    my ($class, $module, %option) = @_;
    my $inc = $option{inc} || \@INC;
    my $module_metadata = Module::Metadata->new_from_module($module, inc => $inc)
        or return;
    $class->new_from_file($module_metadata->filename, inc => $inc);
}

sub new_from_file {
    my ($class, $file, %option) = @_;
    my $inc = $option{inc} || \@INC;
    my $packlist = $class->_find_packlist($file, $inc)
        or return;
    my $self = bless {
        files => undef,
        install_json => undef,
        install_json_hash => undef,
        meta_directory => undef,
        mymeta => undef,
        mymeta_hash => undef,
        packlist => $packlist,
    }, $class;

    my ($lib, $main_module);
    if ($packlist =~ m{^(.+)/$Config{archname}/auto/(.+)/.packlist$}) {
        $lib = $1;
        $main_module = join "::", split m{/}, $2;
    } elsif ($packlist =~ m{^(.+)/$Config{archname}/.packlist$}) {
        # core module
        return $self;
    } else {
        die "Unexpected";
    }

    my $metadata = Module::Metadata->new_from_module(
        $main_module, inc => [$lib, "$lib/$Config{archname}"]
    ) or die "Cannot find '$main_module' in $lib";

    my ($meta_directory, $install_json, $mymeta)
        = $class->_find_meta($metadata->name, $metadata->version, "$lib/$Config{archname}");
    $self->{meta_directory} = $meta_directory;
    $self->{install_json} = $install_json;
    $self->{mymeta} = $mymeta;
    $self;
}

sub _find_meta {
    my ($class, $module, $version, $dir) = @_;
    my ($meta_directory, $install_json, $mymeta);
    my $json = JSON::PP->new;
    find {
        wanted => sub {
            return if $meta_directory;
            return unless -f $_ && basename($_) eq "install.json";
            my $content = do { open my $fh, "<", $_ or return; local $/; <$fh> };
            my $provides = eval { $json->decode($content)->{provides} } or return;
            for my $provide ( sort keys %$provides) {
                if ($provide eq $module
                    && ($provides->{$provide}{version} || "") eq $version) {
                    $meta_directory = $File::Find::dir;
                    return;
                }
            }
        },
        no_chdir => 1,
    }, $dir;

    if ($meta_directory) {
        $install_json = "$meta_directory/install.json";
        ($mymeta) = grep -f, map { "$meta_directory/MYMETA.$_" } qw(json yml);
    };
    return ($meta_directory, $install_json, $mymeta);
}

sub _find_packlist {
    my ($class, $module_path, $inc) = @_;

    my $packlist;
    find {
        wanted => sub {
            return if $packlist;
            return unless -f $_ && basename($_) eq ".packlist";
            my @paths = sort keys %{ ExtUtils::Packlist->new($_) || +{} };
            for my $path (@paths) {
                if ($path eq $module_path) {
                    $packlist = $_;
                    return;
                }
            }
        },
        no_chdir => 1,
    }, @$inc;
    return $packlist;
}

sub files {
    my $self = shift;
    return unless my $packlist = $self->packlist;
    $self->{files} ||= do {
        my $hash = ExtUtils::Packlist->new($packlist);
        [ sort grep { length $_ } keys %$hash ];
    };
}

sub install_json_hash {
    my $self = shift;
    return unless my $install_json = $self->install_json;
    $self->{install_json_hash} ||= do {
        my $content = do {
            open my $fh, "<:utf8", $install_json or die "$install_json: $!";
            local $/; <$fh>;
        };
        eval { JSON::PP->new->decode($content) };
    };
}

sub mymeta_hash {
    my $self = shift;
    return unless my $mymeta = $self->mymeta;
    $self->{mymeta_hash} ||= CPAN::Meta->load_file($mymeta)->as_struct;
}

sub version {
    my $self = shift;
    ( $self->install_json_hash || +{} )->{version};
}


1;

__END__

=encoding utf-8

=head1 NAME

Distribution::Metadata - gather distribution metadata

=head1 SYNOPSIS

    use Distribution::Metadata;

    my $info = Distribution::Metadata->new_from_module("LWP::UserAgent");

    print $info->packlist;
    # /Users/skaji/.plenv/versions/5.20.1/lib/site_perl/5.20.1/darwin-2level/auto/LWP/.packlist
    print $info->meta_directory;
    # /Users/skaji/.plenv/versions/5.20.1/lib/site_perl/5.20.1/darwin-2level/.meta/libwww-perl-6.08
    print $info->install_json;
    # /Users/skaji/.plenv/versions/5.20.1/lib/site_perl/5.20.1/darwin-2level/.meta/libwww-perl-6.08/install.json
    print $info->mymeta;
    # /Users/skaji/.plenv/versions/5.20.1/lib/site_perl/5.20.1/darwin-2level/.meta/libwww-perl-6.08/MYMETA.json

    print "$_\n" for @{ $info->files };
    # /Users/skaji/.plenv/versions/5.20.1/bin/lwp-download
    # /Users/skaji/.plenv/versions/5.20.1/bin/lwp-dump
    # /Users/skaji/.plenv/versions/5.20.1/bin/lwp-mirror
    # /Users/skaji/.plenv/versions/5.20.1/bin/lwp-request
    # /Users/skaji/.plenv/versions/5.20.1/lib/site_perl/5.20.1/LWP.pm
    # /Users/skaji/.plenv/versions/5.20.1/lib/site_perl/5.20.1/LWP/Authen/Basic.pm
    # ...

=head1 DESCRIPTION

Distribution::Metadata gathers distribution metadata.

=head1 LICENSE

Copyright (C) Shoichi Kaji.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Shoichi Kaji E<lt>skaji@cpan.orgE<gt>

=cut

