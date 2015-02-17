package Distribution::Metadata;
use 5.008001;
use strict;
use warnings;
use CPAN::Meta;
use Config;
use ExtUtils::Packlist;
use File::Basename qw(basename dirname);
use File::Find 'find';
use JSON::PP ();
use Module::Metadata;
use File::Spec;
use Cwd ();

our $VERSION = "0.01";

sub new_from_module {
    my ($class, $module, %option) = @_;
    my $inc = $option{inc} || \@INC;
    $inc = $class->_abs_path($inc);
    unless ( exists $option{fill_archlib} && !$option{fill_archlib} ) {
        $inc = $class->_fill_archlib($inc);
    }
    my $metadata = Module::Metadata->new_from_module($module, inc => $inc);
    if ($metadata) {
        $class->new_from_file($metadata->filename, inc => $inc);
    } else {
        bless {}, $class;
    }
}

sub new_from_file {
    my ($class, $file, %option) = @_;
    my $inc = $option{inc} || \@INC;
    $inc = $class->_abs_path($inc);
    unless ( exists $option{fill_archlib} && !$option{fill_archlib} ) {
        $inc = $class->_fill_archlib($inc);
    }
    my $self = bless {}, $class;


    my $packlist = $class->_find_packlist($file, $inc);
    if ($packlist) {
        $self->{packlist} = $packlist;
    } else {
        return $self;
    }

    my ($main_module, $lib) = $self->_guess_main_module($packlist);
    if ($main_module) {
        $self->{main_module} = $main_module;
        if ($main_module eq "perl") {
            $self->{main_module_version} = $^V;
            $self->{main_module_path} = $^X;
            return $self;
        }
    } else {
        return $self;
    }

    my $archlib = File::Spec->catdir($lib, $Config{archname});
    my $metadata = Module::Metadata->new_from_module(
        $main_module, inc => [$lib, $archlib]
    );
    return $self unless $metadata;

    $self->{main_module_version} = $metadata->version;
    $self->{main_module_path} = $metadata->filename;

    my ($meta_directory, $install_json, $mymeta)
        = $class->_find_meta($metadata->name, $metadata->version, $archlib);
    $self->{meta_directory} = $meta_directory;
    $self->{install_json} = $install_json;
    $self->{mymeta} = $mymeta;
    $self;
}

sub _guess_main_module {
    my ($self, $packlist) = @_;
    my @piece = File::Spec->splitdir( dirname($packlist) );
    return "perl" if $piece[-1] eq $Config{archname};

    my (@module, @lib);
    for my $i ( 1 .. ($#piece-2) ) {
        if ($piece[$i] eq $Config{archname} && $piece[$i+1] eq "auto") {
            @module = @piece[ ($i+2) .. $#piece ];
            @lib    = @piece[ 0      .. ($i-1)  ];
            last;
        }
    }
    return unless @module;
    return (join("::", @module), File::Spec->catdir(@lib));
}

sub _fill_archlib {
    my ($class, $incs) = @_;
    my %incs = map { $_ => 1 } @$incs;
    my @out;
    for my $inc (@$incs) {
        push @out, $inc;
        next if $inc =~ /$Config{archname}$/;
        my $archlib = File::Spec->catdir($inc, $Config{archname});
        if (-d $archlib && !$incs{$archlib}) {
            push @out, $archlib;
        }
    }
    \@out;
}

sub _find_meta {
    my ($class, $module, $version, $dir) = @_;
    my ($meta_directory, $install_json, $mymeta);
    my $json = JSON::PP->new;
    find {
        wanted => sub {
            return if $meta_directory;
            return unless -f $_ && basename($_) eq "install.json";
            my $content = do { open my $fh, "<:utf8", $_ or return; local $/; <$fh> };
            my $hash = eval { $json->decode($content) } || +{};

            # name VS target ? When LWP, name is LWP, and target is LWP::UserAgent
            # So name is main_module!
            my $name = $hash->{name} || "";
            return if $name ne $module;
            my $provides = $hash->{provides} || +{};
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

sub _abs_path {
    my ($class, $dirs) = @_;
    my @out;
    for my $dir (@$dirs) {
        my $abs = eval { Cwd::abs_path($dir) };
        push @out, $abs if $abs;
    }
    \@out;
}

sub packlist { shift->{packlist} }
sub meta_directory { shift->{meta_directory} }
sub install_json { shift->{install_json} }
sub mymeta { shift->{mymeta} }
sub main_module { shift->{main_module} }
sub main_module_version { shift->{main_module_version} }
sub main_module_path { shift->{main_module_path} }

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

1;

__END__

=for stopwords .packlist inc pathname eg archname eq

=encoding utf-8

=head1 NAME

Distribution::Metadata - gather distribution metadata

=head1 SYNOPSIS

    use Distribution::Metadata;

    my $info = Distribution::Metadata->new_from_module("LWP::UserAgent");

    print $info->main_module;         # LWP
    print $info->main_module_version; # 6.08
    print $info->main_module_path;    # /Users/skaji/.plenv/versions/5.20.1/lib/site_perl/5.20.1/LWP.pm

    print $info->packlist;
    # /Users/skaji/.plenv/versions/5.20.1/lib/site_perl/5.20.1/darwin-2level/auto/LWP/.packlist
    print $info->meta_directory;
    # /Users/skaji/.plenv/versions/5.20.1/lib/site_perl/5.20.1/darwin-2level/.meta/libwww-perl-6.08
    print $info->install_json;
    # /Users/skaji/.plenv/versions/5.20.1/lib/site_perl/5.20.1/darwin-2level/.meta/libwww-perl-6.08/install.json
    print $info->mymeta;
    # /Users/skaji/.plenv/versions/5.20.1/lib/site_perl/5.20.1/darwin-2level/.meta/libwww-perl-6.08/MYMETA.json

    print $_, "\n" for @{ $info->files };
    # /Users/skaji/.plenv/versions/5.20.1/bin/lwp-download
    # ...
    # /Users/skaji/.plenv/versions/5.20.1/lib/site_perl/5.20.1/LWP.pm
    # /Users/skaji/.plenv/versions/5.20.1/lib/site_perl/5.20.1/LWP/Authen/Basic.pm
    # ...

    my $install_json_hash = $info->install_json_hash;
    my $mymeta_hash = $info->mymeta_hash;

=head1 DESCRIPTION

Distribution::Metadata gathers distribution metadata in local.
That is, this module tries to gather

=over 4

=item main module name, version, path

=item C<.packlist> file

=item C<.meta> directory

=item C<install.json> file

=item C<MYMETA.json> (or C<MYMETA.yml>) file

=back

=head1 HOW IT WORKS

Let me explain how C<< $class->new_from_module($module, inc => $inc) >> works.

=over 4

=item Get C<$module_file> by

    Module::Metadata->new_from_module($module, inc => $inc)->filename.

=item Find C<$packlist> in which C<$module_file> is listed.

=item From C<$packlist> pathname (eg: ...auto/LWP/.packlist), determine C<$main_module> and main module search directory C<$lib>.

=item Get C<$main_module_version> by

    Module::Metadata->new_from_module($main_module, inc => [$lib, "$lib/$Config{archname}"])->version

=item Find install.json that has "name" eq C<$main_module>, and provides C<$main_module> with version C<$main_module_version>.

=item Get .meta directory and MYMETA.json with install.json.

=back

=head2 CONSTRUCTORS

=over 4

=item C<< my $info = $class->new_from_module($module, inc => \@dirs, fill_archlib => $bool) >>

Create Distribution::Metadata instance from module name.
You can append C<inc> argument
to specify module/packlist/meta search paths. Default is C<\@INC>.
If the inc directories do not contain archlibs, then they are automatically added.
You can turn off this behavior by setting C<< fill_archlib => undef >>.

Please note that, even if the module cannot be found,
C<new_from_module> returns a Distribution::Metadata instance.
However almost all methods returns C<undef> for such objects.

=item C<< my $info = $class->new_from_file($file, inc => \@dirs, fill_archlib => $bool) >>

Create Distribution::Metadata instance from file path.
You can append C<inc> and C<fill_archlib> arguments too.

Also C<new_from_file> retunes a Distribution::Metadata instance,
even if file cannot be found.

=back

=head2 METHODS

=over 4

=item C<< my $file = $info->packlist >>

C<.packlist> file path

=item C<< my $dir = $info->meta_directory >>

C<.meta> directory path

=item C<< my $file = $info->mymeta >>

C<MYMETA.json> (or C<MYMETA.yml>) file path

=item C<< my $main_module = $info->main_module >>

main module name

=item C<< my $version = $info->main_module_version >>

main module version

=item C<< my $path = $info->main_module_path >>

main module path

=item C<< my $files = $info->files >>

file paths which is listed in C<.packlist> file

=item C<< my $hash = $info->install_json_hash >>

a hash reference for C<install.json>

    my $info = Distribution::Metadata->new_from_module("LWP::UserAgent");
    my $install = $info->install_json_hash;
    $install->{version};  # 6.08
    $install->{dist};     # libwww-perl-6.08
    $install->{pathname}; # M/MS/MSCHILLI/libwww-perl-6.08.tar.gz
    ...

=item C<< my $hash = $info->mymeta_hash >>

a hash reference for C<MYMETA.json> (or C<MYMETA.yml>)

    my $info = Distribution::Metadata->new_from_module("LWP::UserAgent");
    my $meta = $info->mymeta_hash;
    $meta->{version};  # 6.08
    $meta->{abstract}; # The World-Wide Web library for Perl
    $meta->{prereqs};  # prereq hash
    ...

=back

=head1 SEE ALSO

L<Module::Metadata>

L<App::cpanminus>

=head1 LICENSE

Copyright (C) Shoichi Kaji.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Shoichi Kaji E<lt>skaji@cpan.orgE<gt>

=cut

