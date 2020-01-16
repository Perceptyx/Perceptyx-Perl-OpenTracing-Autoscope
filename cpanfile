requires            'OpenTracing::GlobalTracer';

requires            'Scope::Context';

on 'test' => sub {
    requires            "Test::Most";
};
