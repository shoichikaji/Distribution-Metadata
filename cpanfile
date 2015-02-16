requires 'perl', '5.008001';
requires 'CPAN::Meta';
requires 'ExtUtils::Packlist';
requires 'JSON::PP';
requires 'Module::Metadata';

on 'test' => sub {
    requires 'Test::More', '0.98';
    requires 'App::cpanminus';
    requires 'File::pushd';
};
