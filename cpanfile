requires            'OpenTracing::GlobalTracer';
requires            'OpenTracing::Implementation::NoOp';

requires            'Scope::Context';

on 'develop' => sub {
    requires    "ExtUtils::MakeMaker::CPANfile";
};

on 'test' => sub {
    requires            "Test::Most";
};
