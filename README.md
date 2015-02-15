# NAME

Distribution::Metadata - gather distribution metadata

# SYNOPSIS

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

# DESCRIPTION

Distribution::Metadata gathers distribution metadata.

# LICENSE

Copyright (C) Shoichi Kaji.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

Shoichi Kaji <skaji@cpan.org>
