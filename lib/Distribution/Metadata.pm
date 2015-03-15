package Distribution::Metadata;
use 5.008001;
use strict;
use warnings;
use CPAN::DistnameInfo;
use CPAN::Meta;
use Config;
use Cwd ();
use ExtUtils::Packlist;
use File::Basename qw(basename dirname);
use File::Find 'find';
use File::Spec::Functions qw(catdir catfile);
use JSON ();
use Module::Metadata;
use constant DEBUG => $ENV{PERL_DISTRIBUTION_METADATA_DEBUG};

my $SEP = qr{/|\\}; # path separater
my $ARCHNAME = $Config{archname};

our $VERSION = "0.01";

my $CACHE_CORE_DISTRIBUTION = 1; # default cache on
my %CACHE;
sub cache_core_distribution {
    my $class = shift;
    if (@_) {
        $CACHE_CORE_DISTRIBUTION = $_[0];
        undef %CACHE unless $_[0];
    } else {
        $CACHE_CORE_DISTRIBUTION = 1;
    }
}

sub new_from_module {
    my ($class, $module, %option) = @_;
    my $inc = $option{inc} || \@INC;
    $inc = $class->_abs_path($inc);
    if ($option{fill_archlib}) {
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
    if ($option{fill_archlib}) {
        $inc = $class->_fill_archlib($inc);
    }
    my $self = bless {}, $class;

    my ($packlist, $files) = $class->_find_packlist($file, $inc);
    if ($packlist) {
        $self->{packlist} = $packlist;
        $self->{files}    = $files;
    } else {
        return $self;
    }

    my ($main_module, $lib) = $self->_guess_main_module($packlist);
    if ($main_module) {
        $self->{main_module} = $main_module;
        if ($main_module eq "perl") {
            $self->{main_module_version} = $^V;
            $self->{main_module_file} = $^X;
            $self->{dist} = "perl";
            my $version = "" . $^V;
            $version =~ s/v//;
            $self->{distvname} = "perl-$version";
            $self->{version} = $version;
            return $self;
        }
    } else {
        return $self;
    }

    my $archlib = catdir($lib, $ARCHNAME);
    my $metadata = Module::Metadata->new_from_module(
        $main_module, inc => [$archlib, $lib]
    );
    return $self unless $metadata;

    $self->{main_module_version} = $metadata->version;
    $self->{main_module_file} = $metadata->filename;

    my ($meta_directory, $install_json, $install_json_hash, $mymeta_json)
        = $class->_find_meta($metadata->name, $metadata->version, catdir($archlib, ".meta"));
    $self->{meta_directory}    = $meta_directory;
    $self->{install_json}      = $install_json;
    $self->{install_json_hash} = $install_json_hash;
    $self->{mymeta_json}       = $mymeta_json;
    $self;
}

sub _guess_main_module {
    my ($self, $packlist) = @_;
    my @piece = File::Spec->splitdir( dirname($packlist) );
    if ($piece[-1] eq $ARCHNAME) {
        if ($CACHE_CORE_DISTRIBUTION && !$CACHE{core_files}) {
            $CACHE{core_packlist} = $packlist;
            $CACHE{core_files}    = [sort keys %{ ExtUtils::Packlist->new($packlist) }];
        }
        return ("perl", undef);
    }

    my (@module, @lib);
    for my $i ( 1 .. ($#piece-2) ) {
        if ($piece[$i] eq $ARCHNAME && $piece[$i+1] eq "auto") {
            @module = @piece[ ($i+2) .. $#piece ];
            @lib    = @piece[ 0      .. ($i-1)  ];
            last;
        }
    }
    return unless @module;
    return ( _fix_module_name( join("::", @module) ), catdir(@lib) );
}

# ugly workaround for case insensitive filesystem
# eg: if you install 'Version::Next' module and later 'version' module,
# then version's packlist is located at Version/.packlist! (capital V!)
# Maybe there are a lot of others...
my @fix_module_name = qw(version Version::Next);
sub _fix_module_name {
    my $module_name = shift;
    if (my ($fix) = grep { $module_name =~ /^$_$/i } @fix_module_name) {
        $fix;
    } else {
        $module_name;
    }
}

sub _fill_archlib {
    my ($class, $incs) = @_;
    my %incs = map { $_ => 1 } @$incs;
    my @out;
    for my $inc (@$incs) {
        push @out, $inc;
        next if $inc =~ /$ARCHNAME$/o;
        my $archlib = catdir($inc, $ARCHNAME);
        if (-d $archlib && !$incs{$archlib}) {
            push @out, $archlib;
        }
    }
    \@out;
}

my $JSON = JSON->new;
sub _find_meta {
    my ($class, $module, $version, $dir) = @_;

    # to speed up, first try distribution which just $module =~ s/::/-/gr;
    my $naive = do { my $dist = $module; $dist =~ s/::/-/g; $dist };
    my @install_jsons = (
        ( sort { $b cmp $a } glob '"' . catfile($dir, "$naive-*", "install.json") . '"' ),
        ( sort { $b cmp $a } glob '"' . catfile($dir, "*", "install.json") . '"' ),
    );

    my ($meta_directory, $install_json, $install_json_hash, $mymeta_json);
    INSTALL_JSON_LOOP:
    for my $file (@install_jsons) {
        my $content = do { open my $fh, "<:utf8", $file or next; local $/; <$fh> };
        my $hash = $JSON->decode($content);

        # name VS target ? When LWP, name is LWP, and target is LWP::UserAgent
        # So name is main_module!
        my $name = $hash->{name} || "";
        next if $name ne $module;
        my $provides = $hash->{provides} || +{};
        for my $provide (sort keys %$provides) {
            if ($provide eq $module
                && ($provides->{$provide}{version} || "") eq $version) {
                $meta_directory = dirname($file);
                $install_json = $file;
                $mymeta_json  = catfile($meta_directory, "MYMETA.json");
                $install_json_hash = $hash;
                last INSTALL_JSON_LOOP;
            }
        }
        DEBUG and warn "==> failed to find $module $version in $file\n";
    }

    return ($meta_directory, $install_json, $install_json_hash, $mymeta_json);
}

sub _naive_packlist {
    my ($class, $module_file, $inc) = @_;
    for my $i (@$inc) {
        if (my ($path) = $module_file =~ /$i $SEP (.+)\.pm /x) {
            my $archlib = $i =~ /$ARCHNAME$/o ? $i : catdir($i, $ARCHNAME);
            my $try = catfile( $archlib, "auto", $path, ".packlist" );
            return $try if -f $try;
        }
    }
    return;
}

sub _find_packlist {
    my ($class, $module_file, $inc) = @_;

    if ($CACHE_CORE_DISTRIBUTION && $CACHE{core_files}) {
        if ( grep { $_ eq $module_file } @{ $CACHE{core_files} } ) {
            DEBUG and warn "-> hit cache core packlist: $module_file\n";
            return ($CACHE{core_packlist}, $CACHE{core_files});
        }
    }

    # to speed up, first try packlist which is naively guessed by $module_file
    if (my $naive_packlist = $class->_naive_packlist($module_file, $inc)) {
        my @files = sort keys %{ ExtUtils::Packlist->new($naive_packlist) || +{} };
        if ( grep { $module_file eq $_ } @files ) {
            DEBUG and warn "-> naively found packlist: $module_file\n";
            return ($naive_packlist, \@files);
        }
    }

    my ($packlist, $files);
    for my $dir ( grep -d, map {(catdir($_, "auto"), $_)} @{ $class->_fill_archlib($inc) } ) {
        last if $packlist;
        find {
            wanted => sub {
                return if $packlist;
                return unless -f $_ && basename($_) eq ".packlist";
                return if $CACHE_CORE_DISTRIBUTION && ($CACHE{core_packlist} || "") eq $_;
                my @files = sort keys %{ ExtUtils::Packlist->new($_) || +{} };
                if ( grep { $module_file eq $_ } @files ) {
                    $packlist = $File::Find::name;
                    $files = \@files;
                    return;
                }
            },
            no_chdir => 1,
        }, $dir;
    }
    return ($packlist, $files);
}

sub _abs_path {
    my ($class, $dirs) = @_;
    my @out;
    for my $dir (grep -d, @$dirs) {
        my $abs = Cwd::abs_path($dir);
        $abs =~ s/$SEP+$//;
        push @out, $abs if $abs;
    }
    \@out;
}

sub packlist            { shift->{packlist} }
sub meta_directory      { shift->{meta_directory} }
sub install_json        { shift->{install_json} }
sub mymeta_json         { shift->{mymeta_json} }
sub main_module         { shift->{main_module} }
sub main_module_version { shift->{main_module_version} }
sub main_module_file    { shift->{main_module_file} }
sub files               { shift->{files} }
sub install_json_hash   { shift->{install_json_hash} }

sub mymeta_json_hash {
    my $self = shift;
    return unless my $mymeta_json = $self->mymeta_json;
    $self->{mymeta_json_hash} ||= CPAN::Meta->load_file($mymeta_json)->as_struct;
}

sub _distnameinfo {
    my $self = shift;
    return unless my $hash = $self->install_json_hash;
    $self->{_distnameinfo} = CPAN::DistnameInfo->new( $hash->{pathname} );
}

for my $attr (qw(dist version cpanid distvname pathname)) {
    no strict 'refs';
    *$attr = sub {
        my $self = shift;
        return $self->{$attr} if exists $self->{$attr}; # for 'perl' distribution
        return unless $self->_distnameinfo;
        $self->_distnameinfo->$attr;
    };
}

# alias
sub name   { shift->dist }
sub author { shift->cpanid }

1;

__END__

=for stopwords .packlist inc pathname eg archname eq archlibs

=encoding utf-8

=head1 NAME

Distribution::Metadata - gather distribution metadata

=head1 SYNOPSIS

    use Distribution::Metadata;

    my $info = Distribution::Metadata->new_from_module("LWP::UserAgent");

    print $info->main_module;         # LWP
    print $info->main_module_version; # 6.08
    print $info->main_module_file;    # /Users/skaji/.plenv/versions/5.20.1/lib/site_perl/5.20.1/LWP.pm

    print $info->packlist;
    # /Users/skaji/.plenv/versions/5.20.1/lib/site_perl/5.20.1/darwin-2level/auto/LWP/.packlist
    print $info->meta_directory;
    # /Users/skaji/.plenv/versions/5.20.1/lib/site_perl/5.20.1/darwin-2level/.meta/libwww-perl-6.08
    print $info->install_json;
    # /Users/skaji/.plenv/versions/5.20.1/lib/site_perl/5.20.1/darwin-2level/.meta/libwww-perl-6.08/install.json
    print $info->mymeta_json;
    # /Users/skaji/.plenv/versions/5.20.1/lib/site_perl/5.20.1/darwin-2level/.meta/libwww-perl-6.08/MYMETA.json

    print $_, "\n" for @{ $info->files };
    # /Users/skaji/.plenv/versions/5.20.1/bin/lwp-download
    # ...
    # /Users/skaji/.plenv/versions/5.20.1/lib/site_perl/5.20.1/LWP.pm
    # /Users/skaji/.plenv/versions/5.20.1/lib/site_perl/5.20.1/LWP/Authen/Basic.pm
    # ...

    my $install_json_hash = $info->install_json_hash;
    my $mymeta_json_hash = $info->mymeta_json_hash;

=head1 DESCRIPTION

Distribution::Metadata gathers distribution metadata in local.
That is, this module tries to gather

=over 4

=item main module name, version, file

=item C<.packlist> file

=item C<.meta> directory

=item C<install.json> file

=item C<MYMETA.json> file

=back

Note that C<.meta> directory, C<install.json> file and C<MYMETA.json> file
seem to be available when you installed modules
with L<cpanm> 1.5000 (released 2011.10.13) or later.

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

Also you can append C<fill_archlib> argument
so that archlibs are automatically added to C<inc> if missing.

Please note that, even if the module cannot be found,
C<new_from_module> returns a Distribution::Metadata instance.
However almost all methods returns C<undef> for such objects.
If you want to know whether the distribution was found or not, try:

    my $info = $class->new_from_module($module);

    if ($info->packlist) {
        # found
    } else {
        # not found
    }

=item C<< my $info = $class->new_from_file($file, inc => \@dirs, fill_archlib => $bool) >>

Create Distribution::Metadata instance from file path.
You can append C<inc> and C<fill_archlib> arguments too.

Also C<new_from_file> retunes a Distribution::Metadata instance,
even if file cannot be found.

=back

=head2 METHODS

Please note that the following methods return C<undef>
when appropriate modules or files cannot be found.

=over 4

=item C<< my $file = $info->packlist >>

C<.packlist> file path

=item C<< my $dir = $info->meta_directory >>

C<.meta> directory path

=item C<< my $file = $info->install_json >>

C<install.json> file path

=item C<< my $file = $info->mymeta_json >>

C<MYMETA.json> file path

=item C<< my $main_module = $info->main_module >>

main module name

=item C<< my $version = $info->main_module_version >>

main module version

=item C<< my $file = $info->main_module_file >>

main module file path

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

=item C<< my $hash = $info->mymeta_json_hash >>

a hash reference for C<MYMETA.json>

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

