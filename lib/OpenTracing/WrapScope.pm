package OpenTracing::WrapScope;
our $VERSION = 'v0.106.0';
use strict;
use warnings;
use warnings::register;
use B::Hooks::EndOfScope;
use B::Hooks::OP::Check::StashChange;
use Carp qw/croak/;
use List::Util qw/uniq/;
use OpenTracing::GlobalTracer;
use PerlX::Maybe;
use Sub::Info qw/sub_info/;

{  # transparent caller, stolen from Hook::LexWrap
no warnings 'redefine';
*CORE::GLOBAL::caller = sub (;$) {
    my ($height) = ($_[0]||0);
    my $i=1;
    my $name_cache;
    while (1) {
        my @caller = CORE::caller() eq 'DB'
            ? do { package DB; CORE::caller($i++) }
            : CORE::caller($i++);
        return if not @caller;
        $caller[3] = $name_cache if $name_cache;
        $name_cache = $caller[0] eq __PACKAGE__ ? $caller[3] : '';
        next if $name_cache || $height-- != 0;
        return wantarray ? @_ ? @caller : @caller[0..2] : $caller[0];
    }
};
}

my @sub_sets;    # leftover non-wrapped subs
END { _warn_unwrapped(@sub_sets) }

sub import {
    shift;    # __PACKAGE__
    my $target_package = caller;

    my ($use_env, @subs, @files);
    while (my (undef, $arg) = each @_) {
        if ($arg eq '-env') {
            $use_env = 1;
        }
        elsif ($arg eq '-file') {
            my (undef, $next) = each @_ or last;
            push @files, ref $next eq 'ARRAY' ? @$next : $next;
        }
        else {
            push @subs, _qualify_sub($arg, $target_package);
        }
    }
    if ($use_env and $ENV{OPENTRACING_WRAPSCOPE_FILE}) {
        push @files, split ':', $ENV{OPENTRACING_WRAPSCOPE_FILE};
    }
    push @subs, map { _load_sub_spec($_) } grep { -f } map { glob } uniq @files;

    _setup_install_hooks(@subs);
    return;
}

sub _setup_install_hooks {
    my %stashes;
    foreach my $sub (@_) {
        my ($stash) = $sub =~ s/(?:'|::)\w+\z//r;
        $stashes{$stash}{$sub} = 1;
    }
    push @sub_sets, \%stashes;

    on_scope_end {
        foreach my $stash (keys %stashes) {
            _install_from_stash($stashes{$stash});
            delete $stashes{$stash} if not %{ $stashes{$stash} };
        }
    };

    my $id;
    my $installer = sub {    # run when a new package is being compiled
        my ($new_stash) = @_;
        return if not exists $stashes{$new_stash};

        on_scope_end {       # check for wanted subs when it's done compiling
            my $stash = $stashes{$new_stash}
                or return;    # might have been removed by another hook
            _install_from_stash($stash);
            delete $stashes{$new_stash} if not %$stash;
        };

        # everything is installed, stop checking
        B::Hooks::OP::Check::StashChange::unregister($id) if not %stashes;
    };
    $id = B::Hooks::OP::Check::StashChange::register($installer);

    return;
}

sub _install_from_stash {
    my ($stash) = @_;
    return if not $stash;
    
    foreach my $sub (keys %$stash) {
        next unless defined &$sub;
        install_wrapped($sub);
        delete $stash->{$sub};
    }
    return;
}

sub install_wrapped {
    foreach my $sub (@_) {
        my $full_sub = _qualify_sub($sub, scalar caller);

        if (not defined &$sub) {
            warnings::warn "Couldn't find sub: $sub";
            next;
        }

        no strict 'refs';
        no warnings 'redefine';
        *$sub = wrapped(\&$sub);
    }
    return;
}

sub wrapped {
    my ($coderef) = @_;
    my $info = sub_info($coderef);

    return sub {
        my ($call_package, $call_filename, $call_line) = caller(0);
        my $call_sub = (caller(1))[3];
        my $tracer = OpenTracing::GlobalTracer->get_global_tracer; 
        my $scope = $tracer->start_active_span(
            "$info->{package}::$info->{name}",
            tags => {
                'source.subname' => $info->{name},
                'source.file'    => $info->{file},
                'source.line'    => $info->{start_line},
                'source.package' => $info->{package},
                maybe
                'caller.subname' => $call_sub,
                'caller.file'    => $call_filename,
                'caller.line'    => $call_line,
                'caller.package' => $call_package,
            },
        );

        my $result;
        my $wantarray = wantarray;    # eval will have its own
        my $ok = eval {
            if (defined $wantarray) {
                $result = $wantarray ? [&$coderef] : &$coderef;
            }
            else {
                &$coderef;
            }
            1;
        };
        # TODO: message should go to logs but we don't have those yet
        $scope->get_span->add_tags(error => 1, message => "$@") unless $ok;
        $scope->close();

        die $@ unless $ok;
        return if not defined wantarray;
        return wantarray ? @$result : $result;
    };
}

sub _qualify_sub {
    my ($sub, $pkg) = @_;
    return $sub if $sub =~ /'|::/;
    return "${pkg}::$sub";
}

sub _load_sub_spec {
    my ($filename) = @_;

    open my $fh_subs, '<', $filename or die "$filename: $!";

    my @subs;
    while (<$fh_subs>) {
        next if /^\s*#/;    # commented-out line
        s/\s*#.*\Z//;       # trailing comment
        chomp;
        croak "Unqualified subroutine: $_" if !/'|::/;
        push @subs, $_;
    }
    close $fh_subs;

    return @subs;
}

sub wrap_from_file {
    my ($filename) = @_;
    install_wrapped( _load_sub_spec($filename) );
    return;
}

sub _warn_unwrapped {
    foreach my $stash_set (@_) {
        next if not %$stash_set;
        foreach my $sub (map { keys %$_ } values %$stash_set) {
            warnings::warn "OpenTracing::WrapScope didn't find sub: $sub";
        }
    }
}


1;
