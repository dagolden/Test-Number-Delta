use Module::Build;
# See perldoc Module::Build for details of how this works

Module::Build->new( 
    module_name         => 'Test::Number::Delta',
    dist_author         => 'David A. Golden <dagolden@cpan.org>',
    create_makefile_pl  => 'traditional',
    create_readme       => 1,
    license             => 'perl',
    requires => {
        perl => 5.004,
        Test::Builder => 0.32,
        # build requires here
        Test::Builder::Tester => 1.02,
        Test::More => 0.45,
    },
)->create_build_script;
