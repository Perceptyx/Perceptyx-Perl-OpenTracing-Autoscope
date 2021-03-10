use Test::Most tests => 1;
use OpenTracing::Implementation 'NoOp';
use OpenTracing::AutoScope;

lives_ok {
    OpenTracing::AutoScope->start_guarded_span('test')
} 'NoOp compatible';
