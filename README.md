# NAME

Distribution::Metadata - gather distribution metadata in local

# SYNOPSIS

    use Distribution::Metadata;

    my $info = Distribution::Metadata->new_from_module("LWP::UserAgent");

    print $info->name;      # libwww-perl
    print $info->version;   # 6.13
    print $info->distvname; # libwww-perl-6.13
    print $info->author;    # ETHER
    print $info->pathname;  # E/ET/ETHER/libwww-perl-6.13.tar.gz

    print $info->main_module;         # LWP
    print $info->main_module_version; # 6.13
    print $info->main_module_file;    # path of LWP.pm

    print $info->packlist;       # path of .packlist
    print $info->meta_directory; # path of .meta directory
    print $info->install_json;   # path of install.json
    print $info->mymeta_json;    # path of MYMETA.json

    my $files = $info->files; # files which are listed in .packlist

    my $install_json_hash = $info->install_json_hash;
    my $mymeta_json_hash  = $info->mymeta_json_hash;

# DESCRIPTION

(**CAUTION**: This module is still in development phase. API will change without notice.)

Sometimes we want to know:
_Where this module comes from? Which distribution does this module belong to?_

Since [cpanm](https://metacpan.org/pod/cpanm) 1.5000 (released 2011.10.13),
it installs not only modules but also their meta data.
So we can answer that questions!

Distribution::Metadata gathers distribution metadata in local.
That is, this module tries to gather

- main module name, version, file
- `.packlist` file
- `.meta` directory
- `install.json` file
- `MYMETA.json` file

Please note that as mentioned above, **this module deeply depends on cpanm behavior**.
If you install cpan modules by hands or some cpan clients other than cpanm,
this module won't work.

# HOW IT WORKS

Let me explain how `$class->new_from_module($module, inc => $inc)` works.

- Get `$module_file` by

        Module::Metadata->new_from_module($module, inc => $inc)->filename.

- Find `$packlist` in which `$module_file` is listed.
- From `$packlist` pathname (eg: ...auto/LWP/.packlist), determine `$main_module` and main module search directory `$lib`.
- Get `$main_module_version` by

        Module::Metadata->new_from_module($main_module, inc => [$lib, "$lib/$Config{archname}"])->version

- Find install.json that has "name" eq `$main_module`, and provides `$main_module` with version `$main_module_version`.
- Get .meta directory and MYMETA.json with install.json.

## CONSTRUCTORS

- `my $info = $class->new_from_module($module, inc => \@dirs, fill_archlib => $bool)`

    Create Distribution::Metadata instance from module name.

    You can append `inc` argument
    to specify module/packlist/meta search paths. Default is `\@INC`.

    Also you can append `fill_archlib` argument
    so that archlibs are automatically added to `inc` if missing.

    Please note that, even if the module cannot be found,
    `new_from_module` returns a Distribution::Metadata instance.
    However almost all methods returns false for such objects.
    If you want to know whether the distribution was found or not, try:

        my $info = $class->new_from_module($module);

        if ($info->packlist) {
            # found
        } else {
            # not found
        }

- `my $info = $class->new_from_file($file, inc => \@dirs, fill_archlib => $bool)`

    Create Distribution::Metadata instance from file path.
    You can append `inc` and `fill_archlib` arguments too.

    Also `new_from_file` retunes a Distribution::Metadata instance,
    even if file cannot be found.

## METHODS

Please note that the following methods return false
when appropriate modules or files cannot be found.

- `my $name = $info->name (alias: $info->dist)`

    distribution name (eg: `libwww-perl`)

- `my $version = $info->version`

    distribution version (eg: `6.13`)

- `my $distvname = $info->distvname`

    distribution vname (eg: `libwww-perl-6.13`)

- `my $author = $info->author (alias: $info->cpanid)`

    distribution author (eg: `ETHER`)

- `my $pathname = $info->pathname`

    distribution pathname (eg: `E/ET/ETHER/libwww-perl-6.13.tar.gz`)

- `my $file = $info->packlist`

    `.packlist` file path

- `my $dir = $info->meta_directory`

    `.meta` directory path

- `my $file = $info->install_json`

    `install.json` file path

- `my $file = $info->mymeta_json`

    `MYMETA.json` file path

- `my $main_module = $info->main_module`

    main module name

- `my $version = $info->main_module_version`

    main module version

- `my $file = $info->main_module_file`

    main module file path

- `my $files = $info->files`

    file paths which is listed in `.packlist` file

- `my $hash = $info->install_json_hash`

    a hash reference for `install.json`

        my $info = Distribution::Metadata->new_from_module("LWP::UserAgent");
        my $install = $info->install_json_hash;
        $install->{version};  # 6.13
        $install->{dist};     # libwww-perl-6.13
        $install->{provides}; # a hash reference of providing modules
        ...

- `my $hash = $info->mymeta_json_hash`

    a hash reference for `MYMETA.json`

        my $info = Distribution::Metadata->new_from_module("LWP::UserAgent");
        my $meta = $info->mymeta_hash;
        $meta->{version};  # 6.13
        $meta->{abstract}; # The World-Wide Web library for Perl
        $meta->{prereqs};  # prereq hash
        ...

# SEE ALSO

[Module::Metadata](https://metacpan.org/pod/Module::Metadata)

[App::cpanminus](https://metacpan.org/pod/App::cpanminus)

# LICENSE

Copyright (C) 2015 Shoichi Kaji

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

Shoichi Kaji <skaji@cpan.org>
