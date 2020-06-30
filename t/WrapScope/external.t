use Test::Most tests => 1;
use Test::OpenTracing::Integration;
use OpenTracing::Implementation qw/Test/;
use OpenTracing::WrapScope qw/Test::WrapScope::External::stuff/;
use lib 't/lib';
use Test::WrapScope::External;

Test::WrapScope::External::stuff();

global_tracer_cmp_easy(
    [{ operation_name => 'Test::WrapScope::External::stuff' }],
    'sub from a module wrapped correctly'
);
